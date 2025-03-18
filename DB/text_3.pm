use strict;
package Sakia::DB::text;
use Sakia::DB::share_3;
#-------------------------------------------------------------------------------
our $VERSION;
our %IndexCache;
our $ErrNotFoundCol;
our $ErrInvalidVal;
our %TypeInfo;
my %TypeInfoAlias = (
	bigint	=> 'int',
	boolean	=> 'flag',
	ltext	=> 'text',
	'timestamp(0)' => 'timestamp'
);
################################################################################
# manupilate table
################################################################################
#-------------------------------------------------------------------------------
# create table
#-------------------------------------------------------------------------------
sub create_table {
	my $self = shift;
	my $table= shift =~ tr/A-Z/a-z/r;
	my $_cols= shift;
	my $ROBJ = $self->{ROBJ};

	$table =~ s/\W//g;
	if ($table eq '') { $self->error('Called create_table() with null table name'); return 9; }

	#--------------------------------------------------
	# check table name
	#--------------------------------------------------
	my $dir = $self->{dir} . $table . '/';
	if (!-e $dir) {
		if (!$ROBJ->mkdir($dir)) { $self->error("mkdir '$dir' error : $!"); }
	}
	if (-e "$dir$self->{index_backup}") {
		$self->error("'%s' table already exists", $table);
		return 30;
	}
	if ($table =~ /^\d/) {
		$self->error("To be a 'a-z' or '_' at the first character of a table name : '%s'", $table);
		rmdir($dir);
		return 30;
	}

	#--------------------------------------------------
	# parse columns
	#--------------------------------------------------
	$self->{"$table.cols"}    = { 'pkey'=>$TypeInfo{int} };
	$self->{"$table.unique"}  = { 'pkey'=>1 };	# UNIQUE
	$self->{"$table.notnull"} = { 'pkey'=>1 };	# NOT NULL
	$self->{"$table.index"}   = { 'pkey'=>1 };	# index
	$self->{"$table.default"} = {};			# Default value
	$self->{"$table.ref"}     = {};			# Referential constraints
	$self->{"$table.serial"}  = 0;

	foreach(@$_cols) {
		if ($_->{name} eq 'pkey') { next; }	# skip
		my $err = $self->parse_column($table, $_, 'create');
		if ($err) {
			rmdir($dir);
			return $err;
		}
	}

	# chcek ref
	my $cols = $self->{"$table.cols"};
	my $ref  = $self->{"$table.ref"};
	foreach(keys(%$ref)) {
		my $c = $ref->{$_};
		if ($c eq '' || $c =~ /\./) { next; }

		my $type = $cols->{$_}->{type};
		my $i    = $cols->{$c};
		if (!$i) {
			$self->error('Colmun "%s" of table "%s" not found referenced by column "%s".', $c, $table, $_);
			return 33;
		}
		if ($i->{type} ne $type) {
			$self->error('Colmun "%s %s" of table "%s" not match type referenced by column "%s %s".', $c, $i->{type}, $table, $_, $type);
			return 34;
		}
	}

	$self->{"$table.tbl"} = [];	# table array ref, save table exists

	$self->save_index($table);
	$self->save_backup_index($table);

	return 0;
}

sub parse_column {
	my $self = shift;
	my $table= shift;
	my $h    = shift;
	my $is_create = shift;

	my $col = $h->{name} =~ tr/A-Z/a-z/r;
	$col =~ s/\W//g;
	if ($col eq '') {
		$self->error('Illegal column name: %s', $col);
		return 7;
	}

	# check column name
	my $cols = $self->{"$table.cols"};
	if ($cols->{$col}) {
		$self->error("Column '%s' is already exists in table '%s'", $col, $table);
		return 8;
	}
	# column info
	my $type = $h->{type} =~ tr/A-Z/a-z/r;
	$type = $TypeInfoAlias{$type} || $type;
	my $info = $TypeInfo{$type};
	if (!$info) {
		$self->error('Column "%s" have invalid type "%s"', $col, $h->{type});
		return 10;
	}
	$self->{"$table.cols"}->{$col}=$info;

	if ($h->{unique})   { $self->{"$table.unique"} ->{$col}=1; }	# UNIQUE
	if ($h->{not_null}) { $self->{"$table.notnull"}->{$col}=1; }	# NOT NULL
	if ($h->{index} || $h->{index_tbl} || $h->{unique}) {
		$self->{"$table.index"}->{$col}=1;	# unique require index!
	}

	#
	# default value
	#
	if ($h->{default_sql} =~ /^NULL$/i) {
		$self->{"$table.default"}->{$col} = '';

	} elsif ($h->{default_sql} ne '') {
		my $org = $h->{default_sql};
		my $v   = $self->load_sql_context($table, $col, $org);
		if (!defined $v) {
			return 21;
		}
		if ($v ne '' && &{$info->{check}}($v) eq '') {
			$self->error('Column "%s %s" have invalid default value: %s', $col, $h->{type}, $org);
			return 22;
		}
		$self->{"$table.default"}->{$col} = $org =~ tr/a-z/A-Z/r;

	} elsif ($h->{default} ne '') {
		my $v = $h->{default};
		if ($v ne '' && &{$info->{check}}($v) eq '') {
			$self->error('Column "%s %s" have invalid default value: %s', $col, $h->{type}, $h->{default});
			return 22;
		}
		$self->{"$table.default"}->{$col} = '#' . $v;
	}

	#
	# Referential constraints
	#
	if ($h->{ref}) {
		my $ref = $h->{ref} =~ tr/A-Z/a-z/r;
		if ($ref !~ /^(\w+)\.(\w+)/) {
			$self->error('Column "%s" have invalid refernce: %s', $col, $h->{ref});
			return 31;
		}
		my $t = $1;
		my $c = $2;
		if (!$is_create || $t ne $table) {	# skip check when same table ref on create table.
			if (!$self->load_index($t)) {
				$self->error('Table "%s" not found referenced by column "%s".', $t, $col);
				return 32;
			}
			my $i = $self->{"$t.cols"}->{$c};
			if (!$i) {
				$self->error('Colmun "%s" of table "%s" not found referenced by column "%s".', $c, $t, $col);
				return 33;
			}
			if ($i->{type} ne $type) {
				$self->error('Colmun "%s %s" of table "%s" not match type referenced by column "%s %s".', $c, $i->{type}, $t, $col, $type);
				return 34;
			}
		}
		$self->{"$table.ref"}->{$col} = $t eq $table ? $c : $ref;
	}

	return 0;
}

#-------------------------------------------------------------------------------
# drop table
#-------------------------------------------------------------------------------
sub drop_table {
	my $self = shift;
	my $table= shift =~ tr/A-Z/a-z/r;
	my $ROBJ = $self->{ROBJ};
	$table =~ s/\W//g;

	my $dir = $self->{dir} . $table . '/';
	if (!-e $dir) { return 1; }	# Not found

	my $files = $ROBJ->search_files($dir);
	my $flag = 0;
	foreach(@$files) {
		if (! unlink("$dir$_")) { $flag += 2; }
	}
	if (!rmdir($dir)) { $flag+=10000; }

	$self->clear_cache($table);

	return $flag;		# 0 is success
}

#-------------------------------------------------------------------------------
# rebuild index file
#-------------------------------------------------------------------------------
sub rebuild_index {
	my ($self, $table) = @_;
	my $ROBJ = $self->{ROBJ};
	$table =~ s/\W//g;

	my $dir = $self->{dir} . $table . '/';
	my $index_backup = $dir . $self->{index_backup};
	if (!-r $index_backup) { return 1; }

	# load backup file
	my $index_file_orig = $self->{index_file};
	$self->{index_file} = $self->{index_backup};
	my $db = $self->load_index($table);
	$self->{index_file} = $index_file_orig;

	# load column data files
	my $files = $ROBJ->search_files($dir);
	my $ext   = $self->{ext};
	my @files = grep(/^\d+$ext$/, @$files);
	my @db;
	my $serial = 0;
	foreach(@files) {
		my $h = $ROBJ->fread_hash($dir . $_);
		push(@db, $h);
		if ($serial < $h->{pkey}) { $serial = $h->{pkey}; } 
	}

	$self->clear_cache($table);

	$self->{"$table.serial"} = $serial;
	$self->{"$table.tbl"}    = \@db;
	$IndexCache{$table}      = \@db;
	$self->save_index($table, 'force flag');
}

################################################################################
# support functions
################################################################################
#-------------------------------------------------------------------------------
# get DB Version
#-------------------------------------------------------------------------------
sub db_version {
	my $self = shift;
	return $self->{DBMS} . ' Version ' . $VERSION;
}

#-------------------------------------------------------------------------------
# add column
#-------------------------------------------------------------------------------
sub add_column {
	my $self = shift;
	my $table= shift =~ tr/A-Z/a-z/r;
	my $h    = shift;
	my $ROBJ = $self->{ROBJ};

	# load index
	$table =~ s/\W//g;
	my $db = $self->load_index_for_edit($table);
	if (!defined $db) {
		$self->edit_index_exit($table);
		$self->error("Can't find '%s' table", $table);
		return 7;
	}

	my $r = $self->parse_column($table, $h);
	if ($r) { return $r; }

	$self->save_index($table);
	$self->save_backup_index($table);
	$self->clear_cache($table);

	return 0;
}

#-------------------------------------------------------------------------------
# drop column
#-------------------------------------------------------------------------------
sub drop_column {
	my $self = shift;
	my $table= shift =~ tr/A-Z/a-z/r;
	my $col  = shift =~ tr/A-Z/a-z/r;
	my $ROBJ = $self->{ROBJ};
	$table  =~ s/\W//g;
	$col    =~ s/\W//g;
	if ($table eq '' || $col eq '') { return 7; }

	# load index
	$table =~ s/\W//g;
	my $db = $self->load_index_for_edit($table);
	if (!defined $db) {
		$self->edit_index_exit($table);
		$self->error("Can't find '%s' table", $table);
		return 8;
	}

	# column exists?
	if (! $self->{"$table.cols"}->{$col}) {
		$self->edit_index_exit($table);
		$self->error("Can't find '%s' column in relation '%s'", $col, $table);
		return 9;
	}

	# update table info
	delete $self->{"$table.cols"}->{$col};
	delete $self->{"$table.unique"}->{$col};
	delete $self->{"$table.notnull"}->{$col};
	delete $self->{"$table.index"}->{$col};
	delete $self->{"$table.default"}->{$col};
	delete $self->{"$table.ref"}->{$col};

	# delete column from all row data
	$self->load_allrow($table);
	my $all = $self->{"$table.tbl"};
	foreach(@$all) {
		if ($_->{$col} eq '') { next; }

		delete $_->{$col};
		$self->write_rowfile($table, $_);
	}

	$self->save_index($table);
	$self->save_backup_index($table);
	$self->clear_cache($table);

	return 0;
}

#-------------------------------------------------------------------------------
# add index
#-------------------------------------------------------------------------------
sub add_index {
	my $self = shift;
	my $table= shift =~ tr/A-Z/a-z/r;
	my $col  = shift =~ tr/A-Z/a-z/r;
	my $ROBJ = $self->{ROBJ};

	# load index
	$table =~ s/\W//g;
	my $db = $self->load_index_for_edit($table);
	if (!defined $db) {
		$self->edit_index_exit($table);
		$self->error("Can't find '%s' table", $table);
		return 9;
	}

	# update table info
	my $cols = $self->{"$table.cols"};
	my $idx  = $self->{"$table.index"};
	if (! grep { $_ eq $col } @$cols) {	# not exists
		$self->edit_index_exit($table);
		$self->error($ErrNotFoundCol, $table, $col);
		return 8;
	}
	if (! grep { $_ eq $col } @$idx) {	# add to index
		push(@$idx, $col);
		my $dir = $self->{dir} . $table . '/';
		my $ext = $self->{ext};
		$self->load_allrow($table);
	}

	$self->save_index($table);
	$self->save_backup_index($table);

	return 0;
}

################################################################################
# admin functions
################################################################################
#-------------------------------------------------------------------------------
# get table list
#-------------------------------------------------------------------------------
sub get_tables {
	my $self = shift;
	my $dir  = $self->{dir};
	my $ROBJ = $self->{ROBJ};

	my $list = $ROBJ->search_files($dir, { dir_only=>1 });
	return [ grep { $self->find_table($_) } map { s|/$||r } @$list ];
}

#-------------------------------------------------------------------------------
# get table columns
#-------------------------------------------------------------------------------
sub get_colmuns_info {
	my $self = shift;
	my $table= shift =~ tr/A-Z/a-z/r;

	$table =~ s/\W//g;
	if (! $self->load_index($table)) { return; }

	my $cols    = $self->{"$table.cols"};
	my $unique  = $self->{"$table.unique"};
	my $notnull = $self->{"$table.notnull"};
	my $default = $self->{"$table.default"};
	my $ref     = $self->{"$table.ref"};
	my $index   = $self->{"$table.index"};

	my @cols;
	foreach(keys(%$cols)) {
		my $x = $default->{$_};
		push(@cols, {
			name	=> $_,
			type	=> $cols->{$_}->{type},
			unique	=> $unique->{$_}  ? 'YES' : 'NO',
			notnull	=> $notnull->{$_} ? 'YES' : 'NO',
			default	=> $x =~ /^#(.*)/ ? "'$1'" : $x,
			ref	=> $ref->{$_},
			index	=> $index->{$_}   ? 'YES' : 'NO'
		});
	}
	return \@cols;
}

#-------------------------------------------------------------------------------
# SQL console
#-------------------------------------------------------------------------------
sub sql_console {
	return &sql_emulator(@_);
}

################################################################################
# update backup index file
################################################################################
sub save_backup_index {
	my $self  = shift;
	my $table = shift;

	local ($self->{index_file})   = $self->{index_backup};
	local ($self->{"$table.tbl"}) = [];
	$self->save_index($table, 1);
	return 0;
}

################################################################################
# old functions
################################################################################
sub parse_old_index {
	my $self  = shift;
	my $table = shift;
	my $index = shift;	# index file
	my $ver   = shift;	# Version
	my $lines = shift;	# file lines ary

	# LINE 01: DB index file version
	# my $ver = $self->{"$table.version"} = int(shift(@$lines));	# Version

	# LINE 02: Random string
	my $random;
	if ($ver > 3) {
		$random = $self->{"$table.rand"} = shift(@$lines);
	} else {
	    	$random = $self->{ROBJ}->get_lastmodified($index);
		shift(@$lines);	# Read off index only flag
	}
	$self->{"$table.serial"} = int(shift(@$lines));			# LINE 03: Serial number for pkey (current max)
	my @allcols = split(/\t/, shift(@$lines));			# LINE 04: all colmuns

	my %types;
	if ($ver > 3) {
		foreach(split(/\t/, shift(@$lines))) { $types{$_}='int';   }	# LINE 05: integer columns
		foreach(split(/\t/, shift(@$lines))) { $types{$_}='float'; }	# LINE 06: float columns
		foreach(split(/\t/, shift(@$lines))) { $types{$_}='flag';  }	# LINE 07: flag columns
		foreach(split(/\t/, shift(@$lines))) { $types{$_}='text';  }	# LINE 08: string columns

		# LINE 09: UNQUE columns
		$self->{"$table.unique"}  = { map { $_ => 1} split(/\t/, shift(@$lines)) };
		# LINE 10: NOT NULL columns
		$self->{"$table.notnull"} = { map { $_ => 1} split(/\t/, shift(@$lines)) };
	} else {
		foreach(split(/\t/, shift(@$lines))) { $types{$_}='int';  }
		foreach(split(/\t/, shift(@$lines))) { $types{$_}='flag'; }
		foreach(@allcols) {
			if ($types{$_}) { next; }
			$types{$_} = 'text';	# default type is 'text'
		}
		$self->{"$table.unique"}  = { pkey=>1 };
		$self->{"$table.notnull"} = { pkey=>1 };
	}
	$self->{"$table.cols"} = { map { $_ => $TypeInfo{$types{$_}} } @allcols };

	if ($ver > 4) {
		# LINE 11: default values
		my @ary  = split(/\t/, shift(@$lines));
		$self->{"$table.default"} = { map { $_ => ($ary[0] ne '' ? '#' : '') . shift(@ary) } @allcols };
	} else {
		$self->{"$table.default"} = {};
	}
	#
	# LINE 12: index columns
	#
	return $random
}

1;
