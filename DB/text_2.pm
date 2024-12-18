use strict;
package Sakia::DB::text;
use Fcntl;
#-------------------------------------------------------------------------------
our $FileNameFormat;
our %IndexCache;
################################################################################
# insert, update, delete
################################################################################
#-------------------------------------------------------------------------------
# insert
#-------------------------------------------------------------------------------
sub insert {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	my ($table, $h) = @_;
	$table =~ s/\W//g;

	my $db = $self->load_index_for_edit($table);
	if (!defined $db) {
		$self->edit_index_exit($table);
		$self->error("Can't find '%s' table", $table);
		return 0;
	}

	# check data type
	$h = $self->check_column_type($table, $h);
	if (!defined $h) {
		$self->edit_index_exit($table);
		return 0;	# error exit
	}

	# set pkey
	my $pkey = $h->{pkey};
	if (exists($h->{pkey})) {
		# rewrite new pkey
		if ($pkey>$self->{"$table.serial"}) {
			$self->{"$table.serial"} = $pkey;
		}
	} else {	# auto pkey
		$pkey = $h->{pkey} = ++( $self->{"$table.serial"} );	# pkey
	}

	# default value
	$h = { %{$self->{"$table.default"}}, %$h };

	# check UNIQUE
	my @unique_cols = keys(%{ $self->{"$table.unique"} });
	my $unique_hash = $self->load_unique_hash($table);
	foreach(@unique_cols) {
		my $v = $h->{$_};
		if ($v eq '' || !exists $unique_hash->{$_}->{$v}) { next; }
		# Error
		$self->edit_index_exit($table);
		$self->error("On '%s' table, duplicate key value violates unique constraint '%s'(value is '%s')", $table, $_, $v);
		return 0;
	}

	# add column to $db list
	push(@$db, $h);		# add
	$self->add_unique_hash($table, $h);

	# save
	$self->write_rowfile($table, $h);
	my $r = $self->save_index($table);
	if ($r) { return 0; }	# fail

	return $pkey;		# success
}

#-------------------------------------------------------------------------------
# generate pkey
#-------------------------------------------------------------------------------
sub generate_pkey {
	my ($self, $table) = @_;
	my $ROBJ = $self->{ROBJ};
	$table =~ s/\W//g;

	# if running transaction
	if ($self->{begin}) {
		my $db = $self->load_index_for_edit($table);
		if (!defined $db) {
			$self->edit_index_exit($table);
			$self->error("Can't find '%s' table", $table);
			return 0;
		}
		return ++( $self->{"$table.serial"} )
	}

	# check
	my $dir = $self->{dir} . $table . '/';
	if (!-e $dir) {
		return 0;	# not exists table
	}
	my $index = $dir . $self->{index_file};
	if (!-e $index) {
		$self->rebuild_index( $table );
		if (!-e $index) {
			return 0;
		}
	}

	# lock index
	my $fh;
	if ( !sysopen($fh, $index, O_RDWR) ) {
		return 0;
	}
	$ROBJ->write_lock($fh);
	binmode($fh);

	# read 3 lines
	my $version = <$fh>;
	my $random  = <$fh>;
	my $serial  = <$fh>;
	chop($serial);	# delete "\n"

	# next value
	my $nextval = $serial+1;
	my $datalen = length($serial);
	if ($datalen < length($nextval)) {
		# Increase data size, rewrite all data
		my $max = -s $index;
		read($fh, my $buf, $max);

		sysseek($fh, 0, 0);
		syswrite($fh, $version . $random . "$nextval\n");
		syswrite($fh, $buf);
		close($fh);

	} else {
		# rewrite only 3 lines
		my $nextval_str = substr(('0' x $datalen) . $nextval, -$datalen);

		my $fail;
		if (!sysseek($fh, length($version)+length($random), 0)) { $fail=1; }
		if (!$fail) {
			if (syswrite($fh, $nextval_str, $datalen) != $datalen) { $fail=1; }
		}
		close($fh);
		if ($fail) { return 0; }
	}

	$self->{"$table.serial"} = $nextval;
	return $nextval;
}

#-------------------------------------------------------------------------------
# update
#-------------------------------------------------------------------------------
sub update_match {
	my $self = shift;
	my $table= shift;
	my $h    = shift;
	my $ROBJ = $self->{ROBJ};
	$table =~ s/\W//g;

	my $r = $self->load_index_for_edit($table);
	if (!defined $r) {
		$self->edit_index_exit($table);
		$self->error("Can't find '%s' table", $table);
		return 0;
	}

	# Contains an expression in the update data
	my %funcs;
	foreach (keys(%$h)) {
		if (ord($_) != 0x2a) { next; }		# "*column"

		my $v=$h->{$_};
		$v =~ s![^\w\+\-\*\/\%\(\)\|\&\~<>]!!g;
		if ($v =~ /\w\(/) {
			$self->error("expression error(not allow function). table=$table, $v");
			return 0;
		}
		$v =~ s/([A-Za-z_]\w*)/\$h->{$1}/g;
		my $func;
		eval "\$func=sub {my \$h=shift; return $v;}";
		# $ROBJ->debug("$v");
		if ($@) {
			$self->error("expression error. table=$table, $@");
			return 0;
		}
		delete $h->{$_};
		my $k=substr($_, 1);
		if ($k eq 'pkey') {
			$self->error("On '%s' table, disallow pkey update",$table);
			return 0;
		}
		$funcs{$k} = $func;
	}

	# check update data
	$h = $self->check_column_type($table, $h, 'is_update');
	if (!defined $h) {
		$self->edit_index_exit($table);
		return 0;	# error exit
	}
	delete $h->{pkey};

	# generate where
	my ($func,$db,$in) = $self->load_and_generate_where($table, @_);
	if (!$func) {
		return 0;	# error exit
	}

	# rewrite matching lines
	my @unique_cols = keys(%{ $self->{"$table.unique"} });
	my $unique_hash = $self->load_unique_hash($table);
	my $updates = 0;
	my @new_db = @$db;
	my @save_array;
	foreach(@new_db) {
		if (! &$func($_, $in)) { next; }	# not match

		$updates++;
		$self->delete_unique_hash($table, $_);

		# rewrite internal memory data
		my $row = $self->read_rowfile($table, $_);
		foreach my $k (keys(%$h)) {
			# replace
			$row->{$k} = $h->{$k};
		}
		foreach my $k (keys(%funcs)) {
			$row->{$k} = &{ $funcs{$k} }($row);
		}
		# save hash
		push(@save_array, $row);
		$_ = $row;

		# check UNIQUE
		foreach my $col (@unique_cols) {
			my $v = $row->{$col};
			if ($v eq '' || !exists $unique_hash->{$col}->{$v}) { next; }

			# found a duplicate
			$self->edit_index_exit($table);
			$self->clear_unique_cache($table);
			$self->error("On '%s' table, duplicate key value violates unique constraint '%s'(value is '%s')", $table, $col, $_->{$col});
			return 0;
		}
		# renew UNIQUE hash
		$self->add_unique_hash($table, $row);
	}

	# save
	if ($updates) {
		$self->{"$table.tbl"}=\@new_db;
		foreach(@save_array) {
			$self->write_rowfile($table, $_);
		}
		my $r = $self->save_index($table);	# save index
		if ($r) { return 0; }			# fail
	} elsif(! $self->{begin}) {
		$self->edit_index_exit($table);		# free the lock
	}

	return $updates;
}

#-------------------------------------------------------------------------------
# delete
#-------------------------------------------------------------------------------
sub delete_match {
	my $self = shift;
	my $table= shift;
	my $ROBJ = $self->{ROBJ};
	$table =~ s/\W//g;

	my $r = $self->load_index_for_edit($table);
	if (!defined $r) {
		$self->edit_index_exit($table);
		$self->error("Can't find '%s' table", $table);
		return 0;
	}

	# generate where
	my ($func,$db,$in) = $self->load_and_generate_where($table, @_);
	if (!$func) {
		return 0;	# error exit
	}

	my @new_db;
	my $count;
	my $trace_ary = $self->load_trace_ary($table);
	foreach(@$db) {
		if (! &$func($_, $in)) {
			push(@new_db, $_);	# skip
			next;
		}

		# delete
		$self->delete_rowfile($table, $_);
		$count++;
		# update UNIQUE hash
		$self->delete_unique_hash($table, $_);
	}
	$self->{"$table.tbl"}=\@new_db;
	$self->save_index($table);

	return $count;
}

################################################################################
# select by group
################################################################################
sub select_by_group {
	my ($self, $_tbl, $h) = @_;

	my ($table, $tname) = $self->parse_table_name($_tbl);

	#-------------------------------------------------------------
	# prepare select
	#-------------------------------------------------------------
	my %w = %$h;
	delete $w{sort};
	delete $w{sort_rev};
	delete $w{offset};
	delete $w{limit};

	# group by
	my $group_col = $h->{group_by};
	$group_col =~ s/[^\w\.]//g;

	my @sum_cols = ref($h->{sum_cols}) ? @{$h->{sum_cols}} : ( $h->{sum_cols} eq '' ? () : ($h->{sum_cols}) );
	my @max_cols = ref($h->{max_cols}) ? @{$h->{max_cols}} : ( $h->{max_cols} eq '' ? () : ($h->{max_cols}) );
	my @min_cols = ref($h->{min_cols}) ? @{$h->{min_cols}} : ( $h->{min_cols} eq '' ? () : ($h->{min_cols}) );

	#-------------------------------------------------------------
	# prase join
	#-------------------------------------------------------------
	my %jnames;
	if ($h->{ljoin}) {
		my @ljoin;
		my $jary = ref($h->{ljoin}) eq 'ARRAY' ? $h->{ljoin} : [ $h->{ljoin} ];
		foreach(@$jary) {
			my ($jt,$jn) = $self->parse_table_name($_->{table});

			my $x = { %$_, cols=>[] };
			$jnames{$jn} = $x;
			push(@ljoin, $x);
		}
		$w{ljoin}=\@ljoin;
	}

	my %colh = map {$_ => 1} ('pkey',$group_col,@sum_cols,@max_cols,@min_cols);
	delete $colh{''};

	my %c;
	foreach(keys(%colh)) {
		if ($_ !~ /^(\w+)\.(\w+)$/) { $c{$_}=1; next; }	# main table
		if ($1 eq $tname)           { $c{$2}=1; next; }	# main table

		my $j = $jnames{$1};
		if (!$h) {
			$self->error('%s column is not found', $_);
			return [];
		}
		push(@{$j->{cols}}, $2);
	}
	$w{cols} = [ keys(%c) ];

	foreach($group_col,@sum_cols,@max_cols,@min_cols) {
		$_ =~ s/^\w+\.(\w+)$/$1/;		# delete table name
	}

	#-------------------------------------------------------------
	# load data
	#-------------------------------------------------------------
	my $db = $self->select("$table $tname", \%w);

	#-------------------------------------------------------------
	# Aggregation
	#-------------------------------------------------------------
	my %group;
	my %sum = map { $_=>{} } @sum_cols;
	my %max = map { $_=>{} } @max_cols;
	my %min = map { $_=>{} } @min_cols;
	foreach my $x (@$db) {
		my $g = $x->{$group_col};
		$group{ $g } ++;

		foreach (@sum_cols) {
			$sum{$_}->{$g} += $x->{$_};
		}
		foreach (@max_cols) {
			my $y = $max{$_}->{$g};
			my $z = $x->{$_};
			$max{$_}->{$g} = ($y eq '') ? $z : ($y<$z ? $z : $y);
		}
		foreach (@min_cols) {
			my $y = $min{$_}->{$g};
			my $z = $x->{$_};
			$min{$_}->{$g} = ($y eq '') ? $z : ($y>$z ? $z : $y);
		}
	}

	#-------------------------------------------------------------
	# save result
	#-------------------------------------------------------------
	my @ret;
	while(my ($k,$v) = each(%group)) {
		my %h;
		$h{$group_col} = $k;
		$h{_count}     = $v;
		foreach (@sum_cols) {
			$h{"${_}_sum"} = $sum{$_}->{$k};
		}
		foreach (@max_cols) {
			$h{"${_}_max"} = $max{$_}->{$k};
		}
		foreach (@min_cols) {
			$h{"${_}_min"} = $min{$_}->{$k};
		}
		push(@ret, \%h);
	}

	#-------------------------------------------------------------
	# sort
	#-------------------------------------------------------------
	my $sort = $h->{sort};
	if ($sort) {
		my @ary = ref($sort) ? @$sort : ($sort);
		foreach(@ary) {
			$_ =~ s/^(-?)\w+\.(\w+)/$1/g;
		}

		my ($sort_func, $cols) = $self->generate_sort_func($table, {
			sort	=> \@ary,
			sort_rev=> $h->{sort_rev}
		});
		@ret = sort $sort_func @ret;
	}

	return \@ret;
}

################################################################################
# UNIQUE column processing
################################################################################
#-------------------------------------------------------------------------------
# load UNIQUE columns hash
#-------------------------------------------------------------------------------
#	hash->{column_name}->{value}
#
sub load_unique_hash {
	my $self  = shift;
	my $table = shift;

	if ($IndexCache{"$table.unique-cache"}) {
		return $IndexCache{"$table.unique-cache"};
	}

	# load UNIQUE columns
	my @unique_cols = keys(%{ $self->{"$table.unique"} });
	my ($line0, $line1, $line2);
	foreach(0..$#unique_cols) {
		my $col = $unique_cols[$_];
		$col =~ s/\W//g;
		$line0 .= "my \%h$_;";
		$line1 .= "\$h${_}{\$_->{'$col'}}=1;";
		$line2 .= "'$col'=>\\\%h$_,";
	}
	chop($line2);
	my $conv_hash_func = <<FUNC;
	sub {
		my \$db = shift;
		$line0
		foreach(\@\$db) {
			$line1
		}
		return { $line2 };
	}
FUNC
	$conv_hash_func = $self->eval_and_cache($conv_hash_func);

	my $db = $self->{"$table.tbl"};
	my $unique_hash = &$conv_hash_func( $db );
	$IndexCache{"$table.unique-cache"} = $unique_hash;
	return $unique_hash;
}

#-------------------------------------------------------------------------------
# add to UNIQUE hash
#-------------------------------------------------------------------------------
sub add_unique_hash {
	my $self  = shift;
	my ($table, $h) = @_;

	my @cols = keys(%{ $self->{"$table.unique"} });
	if (!@cols) { return; }

	my $uh = $self->load_unique_hash($table);
	foreach(@cols) {
		$uh->{ $_ }->{ $h->{$_} } = 1;
	}
}

#-------------------------------------------------------------------------------
# delete from UNIQUE hash
#-------------------------------------------------------------------------------
sub delete_unique_hash {
	my $self  = shift;
	my ($table, $h) = @_;

	my @cols = keys(%{ $self->{"$table.unique"} });
	if (!@cols) { return; }

	my $uh = $self->load_unique_hash($table);
	foreach(@cols) {
		delete $uh->{ $_ }->{ $h->{$_} };
	}
}

#-------------------------------------------------------------------------------
# clear UNIQUE hash's cache
#-------------------------------------------------------------------------------
sub clear_unique_cache {
	my ($self, $table) = @_;
	delete $IndexCache{"$table.unique-cache"};
}

################################################################################
# transaction
################################################################################
# Only supported: insert/update/delete
#
sub begin {
	my $self = shift;
	if ($self->{begin}) {
		$self->error("there is already a transaction in progress");
		return ;
	}
	$self->{begin} = 1;
	$self->{transaction} = {};
	$self->{trace} = {}
}
sub rollback {
	my $self = shift;
	if ($self->{begin}) {
		$self->error("there is no transaction in progress");
		return ;
	}
	$self->{begin} = 0;

	# do rollback
	my $trans = $self->{transaction};
	foreach(keys(%$trans)) {
		$self->edit_index_exit($_);
		$self->clear_cache($_);

		# free transaction lock
		close($self->{"$_.lock-tr"});
		delete $self->{"$_.lock-tr"};
	}
	$self->{transaction}={};
	$self->{trace}={};
	return -1;
}
sub commit {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	if ($self->{begin}<0) {		# error occurred
		return $self->rollback();
	}
	$self->{begin} = 0;		# for save_index()

	# write internal data to file
	my $trans = $self->{transaction};
	foreach my $table (keys(%$trans)) {
		# update information for the specified table
		my $trace = $self->load_trace_ary($table);
		my %write;
		my %del;
		foreach(@$trace) {
			if (ref($_)) { # update
				my $pkey = $_->{pkey};
				$write{$pkey}=$_;
				delete $del{$pkey};
				next;
			}
			# del
			$del{$_}=1;
			delete $write{$_};
		}
		# write
		foreach(values(%write)) {
			$self->write_rowfile($table, $_);
		}
		foreach(keys(%del)) {
			$self->delete_rowfile($table, $_);
		}

		if ($self->{"$table.lock"}) {
			$ROBJ->write_lock($self->{"$table.lock"});
		}
		$self->save_index($table);

		# free table lock
		if ($self->{"$table.lock-tr"}) {
			close ($self->{"$table.lock-tr"});
			delete $self->{"$table.lock-tr"};
		}
	}
	$self->{transaction}={};
	$self->{trace}={};
	return 0;
}

#-------------------------------------------------------------------------------
# load table's transaction data
#-------------------------------------------------------------------------------
sub load_trace_ary {
	my ($self, $table) = @_;

	# check transaction
	if (! $self->{transaction}->{$table}) { return '[load_trace_ary] error'; }

	if ($self->{trace}->{$table}) {
		return $self->{trace}->{$table};
	}
	return ($self->{trace}->{$table} = []);
}

################################################################################
# Check column data type for insert(), update_match()
################################################################################
sub check_column_type {
	my ($self, $table, $h, $is_update) = @_;
	my $ROBJ = $self->{ROBJ};
	my $cols       = $self->{"$table.cols"};
	my $str_cols   = $self->{"$table.str"};
	my $int_cols   = $self->{"$table.int"};
	my $float_cols = $self->{"$table.float"};
	my $flag_cols  = $self->{"$table.flag"};

	# check columns
	my %new_hash;
	foreach (keys(%$h)) {
		if (! $cols->{$_}) {
			$self->error("On '%s' table, not exists '%s' column", $table, $_);
			return;
		}
		my $v = $h->{$_};
		if ($v eq '') {			# keep null
			$new_hash{$_} = '';

		} elsif ($int_cols->{$_})  {
			if ($v !~ /^[\+\-]?\d+\.?$/) {
				$self->error("On '%s' table, '%s' column's value is not %s: %s", $table, $_, 'integer', $v);
				return;
			}
			$new_hash{$_} = int($v);
		} elsif ($float_cols->{$_}) {
			if ($v !~ /^[\+\-]?\d+(?:\.\d*)?(?:[Ee][\+\-]?\d+)?$/) {
				$self->error("On '%s' table, '%s' column's value is not %s: %s", $table, $_, 'number', $v);
				return;
			}
			$new_hash{$_} = $v + 0;

		} elsif ($flag_cols->{$_}) {
			if ($v ne '0' && $v ne '1') {
				$self->error("On '%s' table, '%s' column's value is not %s: %s", $table, $_, 'flag', $v);
				return;
			}
			$new_hash{$_} = $v;

		} else {	# string
			$new_hash{$_} = $v;
		}
	}
	# check not null
	my $notnull_cols = $self->{"$table.notnull"};
	my @check_columns_ary = $is_update ? keys(%new_hash) : keys(%$notnull_cols);	# update or insert
	foreach (@check_columns_ary) {
		if (!$notnull_cols->{$_}) { next; }
		if (!$is_update && $_ eq 'pkey') { next; }
		if (!defined $h->{$_}) {
			$self->error("On '%s' table, '%s' column is constrained not null", $table, $_);
			return;
		}
	}
	return \%new_hash;
}

################################################################################
# generate where for update_match(), delete_match()
################################################################################
sub load_and_generate_where {
	my $self = shift;
	my $table= shift;
	my $ROBJ = $self->{ROBJ};

	my $idx  = $self->{"$table.idx"} || $self->load_index($table);
	my $cols = $self->{"$table.cols"};
	my $str  = $self->{"$table.str"};

	# parse condition
	my $load_all;
	my @cond;
	my %in;
	while(@_) {
		my $col = shift;
		my $val = shift;
		my $not = 0;
		if (!defined $col) { last; }

		# negative logic?
		if (substr($col,0,1) eq '-') {
			$col = substr($col,1);
			$not = 1;
		}

		# check column
		if (! $cols->{$col}) {
			$self->edit_index_exit($table);
			$self->error("On '%s' table, not exists '%s' column", $table, $col);
			return (undef,undef,undef);
		}
		if (! $idx->{$col}) { $load_all=1; }	# need row file data

		# generate function
		if (ref($val) eq 'ARRAY') {
			# multiple values
			$in{$col} = { map {$_=>1} @$val };
			push(@cond, ($not ? '!' : '') . "exists\$in->{$col}->{\$h->{$col}}");
			next;
		}
		if ($str->{$col}) {
			# string
			$val =~ s/([\\'])/\\$1/g;
			push(@cond, $not ? "\$h->{$col}ne'$val'" : "\$h->{$col}eq'$val'");
			next;
		}
		if (1) {
			# other (int/number/flag)
			$val += 0;
			push(@cond, $not ? "\$h->{$col}!=$val" : "\$h->{$col}==$val");
			next;
		}
	}

	# compile
	my $func;
	if (@cond) {
		my $cond = join('&&', @cond);
		$func = "sub { my (\$h,\$in)=\@_; return $cond; }";
		$func = $self->eval_and_cache($func);
	} else {
		$func = sub { return 1; };
	}

	# need row file data
	if ($load_all) { $self->load_allrow($table); }

	return ($func, $self->{"$table.tbl"}, \%in);
}

################################################################################
# Subroutines
################################################################################
#-------------------------------------------------------------------------------
# save index file
#-------------------------------------------------------------------------------
sub save_index {
	my ($self, $table, $force) = @_;
	my $ROBJ = $self->{ROBJ};

	# Do not write in transaction
	if (!$force && $self->{begin}) {
		$self->{transaction}->{$table}=1;
		return 0;
	}

	my $db        = $self->{"$table.tbl"};			# table array ref
	my $idx_cols  = $self->{"$table.idx"};			# index array ref
	my $idx_only  = $self->{"$table.index_only"};		# index only flag
	my $serial    = int($self->{"$table.serial"});		# serial

	my @lines;
	push(@lines, "5\n");					# LINE 01: DB file version
	push(@lines, "R" . $ROBJ->{TM} . rand(1) . "\n");	# LINE 02: random signature
	push(@lines, "0$serial\n");				# LINE 03: Serial number for pkey
	# *** When rewriting the top 3 lines, also rewrite generate_pkey() ***

	my @allcols = sort(keys(%{ $self->{"$table.cols"} }));				# LINE 04: all colmuns
	push(@lines, join("\t", @allcols) . "\n");
	push(@lines, join("\t", sort(keys(%{ $self->{"$table.int"}     }))) . "\n");	# LINE 05: int colmuns
	push(@lines, join("\t", sort(keys(%{ $self->{"$table.float"}   }))) . "\n");	# LINE 06: number columns
	push(@lines, join("\t", sort(keys(%{ $self->{"$table.flag"}    }))) . "\n");	# LINE 07: flag columns
	push(@lines, join("\t", sort(keys(%{ $self->{"$table.str"}     }))) . "\n");	# LINE 08: string columns
	push(@lines, join("\t", sort(keys(%{ $self->{"$table.unique"}  }))) . "\n");	# LINE 09: UNIQUE columns
	push(@lines, join("\t", sort(keys(%{ $self->{"$table.notnull"} }))) . "\n");	# LINE 10: NOT NULL columns
	my $de = $self->{"$table.default"};
	push(@lines, join("\t", map { $de->{$_} } @allcols) . "\n");			# LINE 11: default values

	# sort all lines order by pkey
	my @new_db = sort { $a->{pkey} <=> $b->{pkey} } @$db;
	$self->{"$table.tbl"} = \@new_db;
	$IndexCache{$table}   = \@new_db;

	# index colmuns
	my @idx_cols = do {
		my %h = %$idx_cols;
		delete $h{pkey};
		('pkey', sort(keys(%h)));
	};
	push(@lines, join("\t", @idx_cols) . "\n");					# LINE 12: index colmuns

	#-----------------------------------------
	# generate row composition function
	#-----------------------------------------
	my $hash2line='';
	foreach(@idx_cols) {
		$_ =~ s/\W//g;
		$hash2line .= "\$h->{$_}\0";
	}
	chop($hash2line);

	# replace TAB and LF to space in index.
	# if save "\0" to the index, that row will be destroyed.
	my $line_func=<<FUNC;
	sub {
		my (\$ary,\$h) = \@_;
		my \$s = "$hash2line";
		\$s =~ tr/\t\n/  /;
		\$s =~ tr/\0/\t/;
		push(\@\$ary, \$s."\n");
	}
FUNC
	$line_func = $self->eval_and_cache($line_func);
	foreach(@new_db) {
		&$line_func(\@lines, $_);
	}

	#-----------------------------------------
	# save
	#-----------------------------------------
	my $dir   = $self->{dir} . $table . '/';
	my $index = $dir . $self->{index_file};

	my $r;
	if (exists $self->{"$table.lock"}) {
		$r = $ROBJ->fedit_writelines($self->{"$table.lock"}, \@lines);
		delete $self->{"$table.lock"};	# unlock
	} else {
		$ROBJ->fwrite_lines($index, \@lines);
	}

	if ($r) {	# fail
		$self->clear_cache($table);
		return $r;
	}

	# renew cache
	$IndexCache{$table} = $self->{"$table.tbl"};
	return 0;
}

#-------------------------------------------------------------------------------
# discard index edit
#-------------------------------------------------------------------------------
sub edit_index_exit {
	my ($self, $table) = @_;
	if ($self->{begin}) {		# do not write in transaction
		$self->{begin}=-1;	# set error flag
		return 0;
	}
	if (defined $self->{"$table.lock"}) {
		my $index_file = $self->{dir} . $table . '/' . $self->{index_file};
		$self->{ROBJ}->fedit_exit($self->{"$table.lock"});
		delete $self->{"$table.lock"};
	}

	$self->clear_cache($table);
}

#-------------------------------------------------------------------------------
# save row file
#-------------------------------------------------------------------------------
sub write_rowfile {
	my $self = shift;
	my ($table, $h) = @_;

	# transaction
	if ($self->{begin}) {
		my $ary = $self->load_trace_ary($table);
		push(@$ary, $h);	# hash
		$h->{'*'}=1;		# set loaded flag
		return 0;
	}

	# save
	my $ROBJ = $self->{ROBJ};
	my $ext  = $self->{ext};
	my $dir  = $self->{dir} . $table . '/';

	delete $h->{'*'};	# delete loaded flag
	my $r = $ROBJ->fwrite_hash($dir . sprintf($FileNameFormat, $h->{pkey}). $ext, $h);
	$h->{'*'}=1;		# save loaded flag
	return $r;
}

#-------------------------------------------------------------------------------
# delete row file
#-------------------------------------------------------------------------------
sub delete_rowfile {
	my $self = shift;
	my ($table, $pkey) = @_;
	if (ref $pkey) { $pkey=$pkey->{pkey}; }

	# transaction
	if ($self->{begin}) {
		my $ary = $self->load_trace_ary($table);
		push(@$ary, $pkey);	# save pkey
		return 0;
	}

	my $ROBJ = $self->{ROBJ};
	my $ext  = $self->{ext};
	my $dir  = $self->{dir} . $table . '/';
	return $ROBJ->remove_file($dir . sprintf($FileNameFormat, $pkey). $ext);
}

#-------------------------------------------------------------------------------
# clear cache data
#-------------------------------------------------------------------------------
sub clear_cache {
	my $self  = shift;
	my $table = shift;

	delete $self->{"$table.tbl"};
	delete $self->{"$table.load_all"};
	delete $IndexCache{$table};
	delete $IndexCache{"$table.rand"};
	delete $IndexCache{"$table.load_all"};
	delete $IndexCache{"$table.unique-cache"};
}

1;
