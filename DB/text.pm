use strict;
#-------------------------------------------------------------------------------
# Text database
#						(C)2005-2024 nabe@abk
#-------------------------------------------------------------------------------
# Note) Avoid destroying the internal hash array $db when returning values.
#
# Note:JP) 値を返すとき、内部ハッシュ配列 $db を破壊されないようにすること。
#
package Sakia::DB::text;
use Sakia::AutoLoader;
use Sakia::DB::share;
#-------------------------------------------------------------------------------
our $VERSION = '1.40';
our $FileNameFormat = "%05d";
our %IndexCache;
################################################################################
# constructor
################################################################################
sub new {
	my $class = shift;
	my ($ROBJ, $dir, $opt) = @_;

	my $ext  = $opt->{ext} || '.dat';
	my $self = bless({
		%{ $opt || {}},		# options
		ROBJ	=> $ROBJ,
		DBMS	=> 'STextDB',
		ID	=> "stext.$dir",

		ext		=> $ext,
		dir		=> $dir,
		index_file	=> "#index$ext",
		index_backup	=> "#index.backup$ext"
	}, $class);

	if (!-e $dir) { $ROBJ->mkdir($dir); }

	return $self;
}

################################################################################
# find table
################################################################################
sub find_table {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	my $table = shift;
	if ($table =~ /\W/) { return 0; }	# Not Found(error)

	my $dir   = $self->{dir} . $table . '/';
	my $index = $dir . $self->{index_file};
	if (!-e $index) {
		if (-e "$dir$self->{index_backup}") { return 1; }	# Found
		return 0;	# Not found
	}
	return 1;
}

################################################################################
# select
################################################################################
sub select {
	my $self = shift;
	my $_tbl = shift;
	my $h    = shift;
	my $ROBJ = $self->{ROBJ};

	my %names;	# table names

	#-----------------------------------------------------------------------
	# load table infomation
	#-----------------------------------------------------------------------
	my ($table, $tname) = $self->parse_table_name($_tbl);
	$names{$tname} = $table;

	my $db = $self->load_index($table);	# table array ref
	if ($#$db < 0) { return []; }
	my $db_orig = $db;

	my $dir = $self->{dir} . $table . '/';
	my $ext = $self->{ext};
	my $index_cols = $self->{"$table.idx"};
	my $all_cols   = $self->{"$table.cols"};
	my $load_cols  = $self->{"$table.load_all"} ? $all_cols : $index_cols;

	#-----------------------------------------------------------------------
	# check select columns
	#-----------------------------------------------------------------------
	my $sel_cols = $h->{cols};
	if ($sel_cols) {
		$sel_cols = ref($sel_cols) ? $sel_cols : [ $sel_cols ];
		if (my @ary = grep { !$all_cols->{$_} } @$sel_cols) {
			foreach(@ary) {
				$self->error('"%s" column is not exists (for %s)', $_, 'SELECT');
			}
			return [];
		}
	}

	#-----------------------------------------------------------------------
	# load conditions data
	#-----------------------------------------------------------------------
	my $flags = $h->{flag} || $h->{boolean};
	my @match    = sort( keys(%{ $h->{match}     }) );
	my @not_match= sort( keys(%{ $h->{not_match} }) );
	my @min      = sort( keys(%{ $h->{min}       }) );
	my @max      = sort( keys(%{ $h->{max}       }) );
	my @gt       = sort( keys(%{ $h->{gt}        }) );
	my @lt       = sort( keys(%{ $h->{lt}        }) );
	my @flag     = sort( keys(%{ $flags          }) );
	my $is_null  = $h->{is_null}      || [];
	my $not_null = $h->{not_null}     || [];
	my $s_cols   = $h->{search_cols}  || [];
	my $s_match  = $h->{search_match} || [];
	my $s_equal  = $h->{search_equal} || [];

	my @target_cols_L1 = (
		@match, @not_match, @min, @max, @gt, @lt, @flag,
		@$is_null, @$not_null
	);
	my @target_cols_L2 = (@$s_cols, @$s_match, @$s_equal);
	my @target_cols    = (@target_cols_L1, @target_cols_L2);

	#-----------------------------------------------------------------------
	# check sort
	#-----------------------------------------------------------------------
	my ($sort_func, $sort) = $self->generate_sort_func($table, $h, $tname);
	# removed "$tname.col" to "col" in @$sort
	#
	my $req_sort;		# require sort
	my $sort_req_load_all;	# all data required for sort
	#
	if (@$sort) {
		$req_sort = 1;
		foreach(@$sort) {
			if ($_ =~ /^(\w+)\.(\w+)$/) { next; }	# This column check by parse left join

			if (!$load_cols->{$_}) { $sort_req_load_all=1; }
			if (!$all_cols->{$_}) {
				$self->error('"%s" column is not exists (for %s)', $_, 'SORT');
				return [];
			}
		}
	}

	#-----------------------------------------------------------------------
	# limit
	#-----------------------------------------------------------------------
	my $limit  = int($h->{limit});
	my $offset = int($h->{offset});
	if ($h->{limit} ne '' && !$limit) { return []; }	# limit is 0
	if ($offset<0) {
		$self->error('Offset must not be negative: %s', $h->{offset});
		return [];
	}

	my $limit_of_search;
	if (!wantarray && $limit) {		# wantarray is require hits
		$limit_of_search = $limit + $offset;
	}

	#-----------------------------------------------------------------------
	# parse left join
	#-----------------------------------------------------------------------
	my %join_keymap;	# main table pkey to join table's line hash data
	my %join_req_all;	# require all the data from the joined table for return value
	my %join_colname;	# column name of return value to joined table's name and column
	if ($h->{ljoin}) {
		# copy all table data
		my @ary;
		foreach(@$db) {
			my %h=%$_;
			push(@ary, \%h);
		}
		$db = \@ary;

		my $jary    = ref($h->{ljoin}) eq 'ARRAY' ? $h->{ljoin} : [ $h->{ljoin} ];
		my @lr_cols = map { $_->{left}, $_->{right} } @$jary;

		foreach(@$jary) {
			my $jtable = $_->{table};
			my ($jt,$jn) = $self->parse_table_name($jtable);
			if ($jt eq '' || $jn eq '' || !$self->find_table($jt)) {
				$self->error('Table not found: %s', $jtable);
				return [];
			}
			if (exists($names{$jn})) {
				$self->error('Table name is duplicate: %s', $jn);
				return [];
			}
			#---------------------------------------------
			# join table infomation
			#---------------------------------------------
			$names{$jn}=$jt;
			my $jdb = $self->load_index($jt);
			my $idx = $self->{"$jt.idx"};
			my $all = $self->{"$jt.cols"};

			#---------------------------------------------
			# check join condition
			#---------------------------------------------
			my $left  = $_->{left};
			my $right = $_->{right};
			if ($right =~ /^(\w+)/ && $1 ne $jn) {	# swap L/R if right is base table
				my $x = $left;
				$left = $right;
				$right= $x;
			}
			my ($ln, $lc) = $left  =~ /^(\w+)\.(\w+)$/ ? ($1,$2) : undef;
			my ($rn, $rc) = $right =~ /^(\w+)\.(\w+)$/ ? ($1,$2) : undef;

			if ($ln eq '' || $rn eq '' || $ln eq $jn || $rn ne $jn) {
				$self->error('Illegal join rule on "%s": left=%s, right=%s', $jtable, $left, $right);
				return [];
			}
			my $ltable = $names{$ln};
			if (!$ltable || !$self->{"$ltable.cols"}->{$lc}) {
				$self->error('"%s" column is not exists on join target "%s" table', $left, $jtable);
				return [];
			}
			if (!$self->{"$jt.unique"}->{$rc}) {
				$ROBJ->warning('"%s" column is not unique on join target "%s" table', $rc, $jtable);
			}
			# $rn=$tn

			#---------------------------------------------
			# check join columns
			#---------------------------------------------
			my %jcols;
			my $req_all;
			foreach(@target_cols, @lr_cols, @$sort) {
				if ($_ !~ /^(\w+)\.(\w+)$/ || $1 ne $jn) { next; }

				if (!$all->{$2}) {
					$self->error('"%s" column is not exists on join target "%s" table', $_, $jtable);
					return [];
				}

				$jcols{$2}=1;
				if (!$idx->{$2}) { $req_all=1; }
			}
			if ($req_all && !$self->{"$jt.load_all"}) {
				$jdb = $self->load_allrow($jt);
			}

			#---------------------------------------------
			# join
			#---------------------------------------------
			my %h;
			foreach(@$jdb) {
				$h{$_->{$rc}}=$_;
			}
			my $mapfunc = "sub {\n\tmy (\$x,\$y)=\@_;\n";
			foreach(keys(%jcols)) {	# need columns for search and sort
				$mapfunc .= "\t\$x->{'$jn.$_'}=\$y->{$_};\n";
			}
			$mapfunc .= '}';
			my $func = $self->eval_and_cache($mapfunc);

			my $map = {};
			my $lcol= $ln eq $tname ? $lc : $left;
			foreach(@$db) {
				my $z = $h{$_->{$lcol}};
				$map->{$_->{pkey}} = $z;
				&$func($_, $z);
			}

			if ($_->{cols}) {
				$join_keymap{$jn} = $map;

				my $all = $self->{"$jt.cols"};
				foreach my $col (@{$_->{cols}}) {
					my ($c,$n) = $col =~ /^(\w+) +(\w+)$/ ? ($1,$2) : ($col,$col);
					if (!$all->{$c}) {
						$self->error('"%s" column is not exists on "%s" (for %s)', $c, $jtable, 'LEFT JOIN');
						return [];
					}
					$join_colname{$n} = { tname=>$jn, col=>$c };
					if (!$self->{"$jt.load_all"} && !$idx->{$c}) {
						$join_req_all{$jn}=1;
					}
				}
			}
		}
	}

	#-----------------------------------------------------------------------
	# search
	#-----------------------------------------------------------------------
	my $read_row_method = %join_keymap ? 'override_by_rowfile' : 'read_rowfile';
	#
	# if exists join table, keep joined column in row hash. (keep ex.) j.pkey, j.name
	#
	if (@target_cols) {
		my $req_load_all;
		foreach(@target_cols) {
			my ($tn,$c) = $_ =~ /^(\w+)\.(\w+)$/ ? ($1,$2) : ($tname,$_);

			if ($tn eq $tname && !$load_cols->{$_}) {
				$req_load_all = 1;
			}

			my $t=$names{$tn};
			if (!$t) {
				$self->error("Column's table name not defined: %s", $_);
				return [];
			}
			if (!$self->{"$t.cols"}->{$c}) {
				$self->error('"%s" column is not exists on "%s" (for %s)', $c, $t, 'SEARCH');
				return [];
			}
		}

		#---------------------------------------------------------------
		# load all for search
		#---------------------------------------------------------------
		my $load_before_L1 = '';
		my $load_before_L2 = '';
		if ($req_load_all) {
			#
			# require non index column for search
			#
			if ($limit_of_search && !$sort_req_load_all) {
				#
				# exists limit and can now sort
				#
				$db = [sort $sort_func @$db];
				$req_sort = 0;

				$load_before_L1 = 1;
				if (!(grep {! $load_cols->{$_}} @target_cols_L1)) {
					$load_before_L1 = '';
					$load_before_L2 = 1;
				}
			} else {
				# - no limit
				# - limit and sort with non index column
				#
				my $db_all = $self->load_allrow($table);
				if (%join_keymap) {
					# override
					$db = [ map {{ %{$db->[$_]}, %{$db_all->[$_]} }} (0..$#$db) ];
				} else {
					$db = $db_all;
				}
				$load_cols = $all_cols;
				$sort_req_load_all = 0;
			}
		}

		#---------------------------------------------------------------
		# Level 1: non text search
		#---------------------------------------------------------------
		my $cond_L1='';
		my %match_h;
		my %not_match_h;
		if (@target_cols_L1) {
			my @cond;
			my $str = $self->{"$table.str"};
			foreach(@match) {
				my $v = $h->{match}->{$_};
				if (ref($v) eq 'ARRAY') {
					$match_h{$_} = { map {$_=>1} @$v };
					push(@cond, "exists\$match_h->{$_}->{\$_->{$_}}");
					next;
				}
				if ($str->{$_} || $v eq '') {	# $v eq '' is null
					$v =~ s/([\\'])/\\$1/g;
					push(@cond, "\$_->{$_}eq'$v'");
					next;
				}
				if (1) {
					# numeric
					$v += 0;
					if ($v ne $h->{match}->{$_}) { $self->error("'$v' ($_ column) is not number"); return []; }
					push(@cond, "\$_->{$_}==$v");
					next;
				}
			}
			foreach (@not_match) {
				my $v = $h->{not_match}->{$_};
				if (ref($v) eq 'ARRAY') {
					$not_match_h{$_} = { map {$_=>1} @$v };
					push(@cond, "!exists\$not_match_h->{$_}->{\$_->{$_}}");
					next;
				}
				if ($str->{$_} || $v eq '') {	# $v eq '' is null
					$v =~ s/([\\'])/\\$1/g;
					push(@cond, "\$_->{$_}ne'$v'");
					next;
				}
				if (1) {
					$v += 0;
					if ($v ne $h->{not_match}->{$_}) { $self->error("'$v' ($_ column) is not number"); return []; }
					push(@cond, "\$_->{$_}!=$v");
					next;
				}
			}
			foreach (@flag) {
				my $v = $flags->{$_};
				if ($v ne '0' && $v ne '1') { $self->error("'$v' ($_ column) is not flag(allowd '1' or '0')"); return []; }
				push(@cond, "\$_->{$_}==$v");
			}
			foreach (@min) {
				my $v = $h->{min}->{$_} + 0;
				if ($v != $h->{min}->{$_}) { $self->error("'$v' ($_ column) is not numeric"); return []; }
				push(@cond, "\$_->{$_}>=$v");
			}
			foreach (@max) {
				my $v = $h->{max}->{$_} + 0;
				if ($v != $h->{max}->{$_}) { $self->error("'$v' ($_ column) is not numeric"); return []; }
				push(@cond, "\$_->{$_}<=$v");
			}
			foreach (@gt) {
				my $v = $h->{gt}->{$_} + 0;
				if ($v != $h->{gt}->{$_}) { $self->error("'$v' ($_ column) is not numeric"); return []; }
				push(@cond, "\$_->{$_}>$v");
			}
			foreach (@lt) {
				my $v = $h->{lt}->{$_} + 0;
				if ($v != $h->{lt}->{$_}) { $self->error("'$v' ($_ column) is not numeric"); return []; }
				push(@cond, "\$_->{$_}<$v");
			}
			foreach (@$is_null) {
				push(@cond, "\$_->{$_}eq''");
			}
			foreach (@$not_null) {
				push(@cond, "\$_->{$_}ne''");
			}

			$cond_L1 = 'if (!(' . join(' && ', @cond) . ')) { next; }';
			$self->trace("select '$table' where L1: $cond_L1");
		}
		$cond_L1 =~ s/->\{((\w+)\.(\w+))\}/$2 eq $tname ? "->{$3}" : "->{'$1'}"/eg;

		#---------------------------------------------------------------
		# Level 2: text search
		#---------------------------------------------------------------
		my $cond_L2='';
		if (@target_cols_L2) {
			my $words = $h->{search_words} || [];
			my $not   = $h->{search_not}   || [];
			my $cols  = $s_cols;	# $h->{search_cols};
			my $match = $s_match;	# $h->{search_match};
			my $equal = $s_equal;	# $h->{search_equal};

			my @cond;
			foreach(@$words) {
				my $x = $_ =~ s/([\\\"])/\\$1/rg;
				my $r = $_ =~ s/([^0-9A-Za-z\x80-\xff])/"\\x" . unpack('H2',$1)/reg;

				my @ary;
				foreach (@$equal) {
					push(@ary, "\$_->{$_} eq \"$x\"");
				}
				foreach (@$cols) {
					push(@ary, "\$_->{$_} =~ /$r/i");
				}
				foreach (@$match) {
					push(@ary, "\$_->{$_} =~ /^$r\$/i");
				}
				push(@cond, '(' . join(' || ', @ary) . ')');
			}

			my @not_words_reg;
			foreach(@$not) {
				my $x = $_ =~ s/([\\\"])/\\$1/rg;
				my $r = $_ =~ s/([^0-9A-Za-z\x80-\xff])/"\\x" . unpack('H2',$1)/reg;

				my @ary;
				foreach (@$equal) {
					push(@ary, "\$_->{$_} ne \"$x\"");
				}
				foreach (@$cols) {
					push(@ary, "\$_->{$_} !~ /$r/i");
				}
				foreach (@$match) {
					push(@ary, "\$_->{$_} !~ /^$r\$/i");
				}
				push(@cond, join(' && ', @ary));
			}

			$cond_L2 = 'if (!(' . join(' && ', @cond) . ')) { next; }';
			$self->trace("select '$table' where L2: $cond_L2");
		}
		$cond_L2 =~ s/->\{((\w+)\.(\w+))\}/$2 eq $tname ? "->{$3}" : "->{'$1'}"/eg;

		#---------------------------------------------------------------
		# make search function
		#---------------------------------------------------------------
		if ($load_before_L1 || $load_before_L2) {
			$dir =~ s/\\\'//g;
			$ext =~ s/\\\'//g;
			my $load = "\$_ = \$self->$read_row_method('$table', \$_);";
			if ($load_before_L1) { $load_before_L1 = $load; }
				else         { $load_before_L2 = $load; }
		}
		my $limit_check='';
		if ($limit_of_search) {
			my $x = $limit_of_search-1;
			$limit_check = "if (\$#newary >= $x) { last; }";
		}
		my $func=<<FUNCTION_TEXT;
sub {
	my (\$self, \$db, \$match_h, \$not_match_h) = \@_;
	my \@newary;
	foreach(\@\$db) {
		$load_before_L1
		$cond_L1
		$load_before_L2
		$cond_L2
		push(\@newary, \$_);
		$limit_check
	}
	return \\\@newary;
}
FUNCTION_TEXT
		if ($self->{TRACE}) { $func =~ s/\t+\n//g; }

		$func = $self->eval_and_cache($func);
		$db = &$func($self, $db, \%match_h, \%not_match_h);

	} elsif ($db eq $db_orig) {
		# copy for save interrnal table data
		$db = [ my @newary = @$db ];
	}
	if ($#$db < 0) { return []; }

	#-----------------------------------------------------------------------
	# sort
	#-----------------------------------------------------------------------
	if ($req_sort) {
		if ($sort_req_load_all) {
			$db = [ map { $self->$read_row_method($table, $_) } @$db ];
			$load_cols = $all_cols;
		}
		$db = [sort $sort_func @$db];
	}

	#-----------------------------------------------------------------------
	# save hits
	#-----------------------------------------------------------------------
	my $hits = $#$db +1;

	#-----------------------------------------------------------------------
	# limit and offset
	#-----------------------------------------------------------------------
	if ($h->{offset} ne '') {
		splice(@$db, 0, int($h->{offset}));
	}
	if ($h->{limit} ne '') {
		splice(@$db, int($h->{limit}));
	}

	#-----------------------------------------------------------------------
	# all data load?
	#-----------------------------------------------------------------------
	if ($load_cols ne $all_cols) {
		my $cols = $sel_cols || [ keys(%{$self->{"$table.cols"}}) ];
		if (grep { !$load_cols->{$_} } @$cols) {
			foreach(@$db) {
				$_ = $self->$read_row_method($table, $_);
			}
		}
	}

	#-----------------------------------------------------------------------
	# join or make copy
	#-----------------------------------------------------------------------
	if (%join_keymap) {	# with join columns
		my $func = "sub {\n" . 'my ($self,$db,$map)=@_;' . "\n";
		foreach(keys(%join_keymap)) {		# $_ = table name
			$func .= "my \$m$_=\$map->{$_};\n";
		}
		$func .= 'foreach(@$db) {';
		$func .= 'my $pkey=$_->{pkey};' . "\n";

		foreach(keys(%join_req_all)) {			# require non index data
			$func .= "\$m$_\->{\$pkey} &&= \$self->read_rowfile('$names{$_}', \$m$_\->{\$pkey});\n";
		}
		if (!$sel_cols) {
			$func .= "delete \$_->{'*'};\n";	# if exists join $db is deep copy,
		}						# therfore can break data.
		$func .= '$_ = {' . "\n";
		if ($sel_cols) {
			foreach(@$sel_cols) {
				$func .= "$_=>\$_->{$_},\n";
			}
		} else {
			$func .= "\%\$_,\n";
		}
		foreach(keys(%join_colname)) {
			my $x  = $join_colname{$_};
			my $tn = $x->{tname};			# table name
			my $c  = $x->{col};
			$func .= "$_=>\$m$tn\->{\$pkey}->{$c},\n";
		}
		chop($func); chop($func);

		$func .= "\n}}}";
		$func = $self->eval_and_cache($func);
		&$func($self, $db, \%join_keymap);

	} elsif ($sel_cols) {
		my $func="sub {\n" . 'my $db = shift; foreach(@$db) {';
		$func .= '$_ = {';
		foreach(@$sel_cols) {
			$func .= "$_=>\$_->{$_},"
		}
		chop($func);
		$func .= '}}}';
		$func = $self->eval_and_cache($func);
		&$func($db);
	} else {
		foreach(@$db) {
			my %h = %$_;
			$_ = \%h;
			delete $h{'*'};		# loaded flag
		}
	}

	return wantarray ? ($db,$hits) : $db;
}


################################################################################
# subrotine for select
################################################################################
#-------------------------------------------------------------------------------
# check select table name
#-------------------------------------------------------------------------------
sub parse_table_name {
	my $self = shift;
	my $tbl  = shift;
	my $names= shift;
	if ($tbl =~ /^(\w+) +(\w+)$/) {
		return ($1, $2);
	}
	$tbl =~ s/\W//g;
	return ($tbl, $tbl);
}

#-------------------------------------------------------------------------------
# generate order by function
#-------------------------------------------------------------------------------
sub generate_sort_func {
	my ($self, $table, $h, $tname) = @_;
	my @sort = ref($h->{sort}    ) ? @{$h->{sort}    } : ($h->{sort}     eq '' ? () : ($h->{sort}    ));
	my @rev  = ref($h->{sort_rev}) ? @{$h->{sort_rev}} : ($h->{sort_rev} eq '' ? () : ($h->{sort_rev}));
	my $cols   = $self->{"$table.cols"};
	my $is_str = $self->{"$table.str"};
	my @cond;
	foreach(0..$#sort) {
		my $col = $sort[$_];
		my $rev = $rev [$_];
		if (ord($col) == 0x2d) {	# '-colname'
			$col = $sort[$_] = substr($col, 1);
			$rev = 1;
		}
		$col =~ s/[^\w\.]//g;
		if ($col eq '') { next; }
		if ($col =~ /^(\w+)\.(\w+)$/ && $1 eq $tname) {
			$col = $sort[$_] = $2;
		}

		my $op = $is_str->{$col} ? 'cmp' : '<=>';
		if ($col =~ /\./) { $col = "'$col'"; }
		push(@cond, $rev ? "\$b->{$col}$op\$a->{$col}" : "\$a->{$col}$op\$b->{$col}");
	}
	my $func = sub { 1; };
	if (@cond) {
		$func = 'sub{'. join('||',@cond) .'}';
		$func = $self->eval_and_cache($func);
	}

	return wantarray ? ($func, \@sort) : $func;
}

################################################################################
# load table data functions
################################################################################
#-------------------------------------------------------------------------------
# load table index with table infomation
#-------------------------------------------------------------------------------
sub load_index_for_edit {
	my ($self, $table) = @_;
	return $self->load_index($table, 1);
}
sub load_index {
	my ($self, $table, $edit) = @_;
	my $ROBJ = $self->{ROBJ};

	if (! $edit && defined $self->{"$table.tbl"}) {
		return $self->{"$table.tbl"};
	}
	$self->trace("load index on '$table' table".($edit ? ' (edit)':''));

	# prepare
	my $dir   = $self->{dir} . $table . '/';
	my $index = $dir . $self->{index_file};
	if (!-e $index) {
		if (-e $dir) { $self->rebuild_index( $table ); }
		else {
			$self->error("Table '$table' not found!");
			return;
		}
	}

	# load file
	my ($fh, $lines);
	if ($edit) {
		my $opt={};
		if ($self->{begin}) {
			# A transaction has already started on this table
			if ($self->{transaction}->{$table}) {
				return $self->{"$table.tbl"};
			}
			# Start transaction. Lock "#index.backup.dat"
			my $fh = $ROBJ->file_lock($dir . $self->{index_backup}, 'write_lock_nb' );
			if (!$fh) {
				# If another transaction already has the lock,
				# this transaction will result in an error.
				# DO NOT WAIT FOR LOCKS to prevent deadlocks.
				return undef;
			}
			$self->{"$table.lock-tr"} = $fh;
			$self->{transaction}->{$table}=1;

			# Lock the index file to prevent it from being edited.
			$opt->{read_lock}=1;
		}
		($fh, $lines) = $ROBJ->fedit_readlines($index, $opt);
		if ($#$lines < 0) {
			$ROBJ->fedit_exit($fh);
			delete $self->{transaction}->{$table};
			return undef;
		}
		$self->{"$table.lock"} = $fh;
	} else {
		$lines = $ROBJ->fread_lines_cached($index, {no_error => $self->{no_error}});
		if ($#$lines < 0) { return undef; }
	}

	# delete "\n"
	map { chop($_) } @$lines;

	# LINE 01: DB file Version
	my $version = $self->{"$table.version"} = int(shift(@$lines));	# Version

	# LINE 02: Random string
	my $random;
	if ($version > 3) {	# Exists since Ver4
		$random = $self->{"$table.rand"} = shift(@$lines);
	} else {		# Substitute with last modofied
		$random = $ROBJ->get_lastmodified($index);
		shift(@$lines);	# Read off index only flag
	}

	# LINE 03: Serial number for pkey (current max)
	$self->{"$table.serial"} = int(shift(@$lines));
	# LINE 04: all colmuns
	my @allcols = split(/\t/, shift(@$lines));
	$self->{"$table.cols"} = { map { $_ => 1} @allcols };
	# LINE 05: integer columns
	$self->{"$table.int"}  = { map { $_ => 1} split(/\t/, shift(@$lines)) };
	# LINE 06: float columns
	if ($version > 3) {
		$self->{"$table.float"}= { map { $_ => 1} split(/\t/, shift(@$lines)) };
	} else {
		$self->{"$table.float"} = {};
	}
	# LINE 07: flag(boolean) columns
	$self->{"$table.flag"} = { map { $_ => 1} split(/\t/, shift(@$lines)) };

	if ($version > 3) {
		# LINE 08: string columns
		$self->{"$table.str"}     = { map { $_ => 1} split(/\t/, shift(@$lines)) };
		# LINE 09: UNQUE columns
		$self->{"$table.unique"}  = { map { $_ => 1} split(/\t/, shift(@$lines)) };
		# LINE 10: NOT NULL columns
		$self->{"$table.notnull"} = { map { $_ => 1} split(/\t/, shift(@$lines)) };
	} else {
		my %cols = %{ $self->{"$table.cols"} };
		map { delete $cols{$_} } (keys(%{$self->{"$table.int"}}), keys(%{$self->{"$table.flag"}}) );
		$self->{"$table.str"}     = \%cols;
		$self->{"$table.unique"}  = { pkey=>1 };
		$self->{"$table.notnull"} = { pkey=>1 };
	}
	if ($version > 4) {
		# LINE 11: default values
		my @ary  = split(/\t/, shift(@$lines));
		$self->{"$table.default"} = { map { $_ => shift(@ary) } @allcols };
	}
	# LINE 12: index columns
	my @idx_cols = split(/\t/, shift(@$lines));
	$self->{"$table.idx"} = { map { $_ => 1} @idx_cols };

	# check cache
	if ($IndexCache{"$table.rand"} eq $random) {
		$self->{"$table.load_all"} = $IndexCache{"$table.load_all"};
		return ($self->{"$table.tbl"} = $IndexCache{$table});
	}
	# clear cahce
	if( exists($IndexCache{$table}) ) { $self->clear_cache($table); }

	my $parse_func='sub{return{ ';	# last space for chop()
	foreach (0..$#idx_cols) {
		my $col=$idx_cols[$_];
		$col =~ s/\W//g;
		$parse_func.="$col=>\$_[$_],";
	}
	chop($parse_func);
	$parse_func.='}}';
	$parse_func = $self->eval_and_cache($parse_func);

	# index data parse loop
	foreach(@$lines) {
		$_ = &$parse_func(split("\t", $_));
	}

	$self->{"$table.tbl"} = $lines;		# save table data
	$IndexCache{$table}   = $lines;		# save cache
	$IndexCache{"$table.rand"} = $random;
	return $lines;
}

#-------------------------------------------------------------------------------
# load row data file
#-------------------------------------------------------------------------------
sub read_rowfile {
	my ($self, $table, $h) = @_;
	if ($h->{'*'}) { return $h; }	# loaded flag
	my $ROBJ = $self->{ROBJ};

	my $ext = $self->{ext};
	my $dir = $self->{dir} . $table . '/';
	my $h = $ROBJ->fread_hash_cached($dir . sprintf($FileNameFormat, $h->{pkey}). $ext);
	$h->{'*'}=1;			# loaded flag
	return $h;
}

sub override_by_rowfile {		# keep original hash data
	my ($self, $table, $h) = @_;
	if ($h->{'*'}) { return $h; }
	my $ROBJ = $self->{ROBJ};

	my $ext = $self->{ext};
	my $dir = $self->{dir} . $table . '/';
	my $x = $ROBJ->fread_hash_cached($dir . sprintf($FileNameFormat, $h->{pkey}). $ext);
	return { %$h, %$x, '*'=>1 };
}

#-------------------------------------------------------------------------------
# load all row data file
#-------------------------------------------------------------------------------
sub load_allrow {
	my $self  = shift;
	my $table = shift;
	my $ROBJ  = $self->{ROBJ};
	if ($self->{"$table.load_all"}) { return $self->{"$table.tbl"}; }

	$self->trace("load all data on '$table'");
	my $ext = $self->{ext};
	my $dir = $self->{dir} . $table . '/';
	$self->{"$table.tbl"} = [ map { $self->read_rowfile($table, $_) } @{$self->{"$table.tbl"}} ];
	$self->{"$table.load_all"} = 1;
	$IndexCache{"$table.load_all"} = 1;
	return ($IndexCache{$table} = $self->{"$table.tbl"});
}

################################################################################
# common subroutins
################################################################################
#-------------------------------------------------------------------------------
# eval and cache
#-------------------------------------------------------------------------------
my %function_cache;
sub eval_and_cache {
	my $self=shift;
	my $functext=shift;
	if (exists $function_cache{$functext}) {
		return $function_cache{$functext};
	}
	# trace
	if ($self->{TRACE}) { $self->trace('[eval] ' . $functext); }

	# function compile
	my $func;
	eval "\$func=$functext";
	if ($@) { die "[$self->{DBMS}] in eval_and_cache() $@"; }
	return ($function_cache{$functext} = $func);
}

1;

