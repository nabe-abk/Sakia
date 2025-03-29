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

	$table =~ s/\W//g;
	if ($table eq '') {
		$self->error('Called create_table() with null table name');
		return 9;
	}

	#--------------------------------------------------
	# check table name
	#--------------------------------------------------
	my $dir = $self->{dir} . $table . '/';
	if (!-e $dir && !mkdir($dir)) {
		$self->error("mkdir \"$dir\" error: $!");
		return 30;
	}
	if (-e "$dir$self->{index_backup}") {
		$self->error('"%s" table already exists', $table);
		return 31;
	}
	if ($table =~ /^\d/) {
		$self->error("To be a 'a-z' or '_' at the first character of a table name: %s", $table);
		rmdir($dir);
		return 32;
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

	my %save;

	my $col = $h->{name} =~ tr/A-Z/a-z/r;
	if ($col eq '' || $col =~ /\W/ || $col !~ /^[a-z_]/) {
		$self->error('Illegal column name: %s', $col);
		return 7;
	}

	# check column
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
	$save{cols} = $info;

	if ($h->{unique})   { $save{unique}  = 1; }
	if ($h->{not_null}) { $save{notnull} = 1; }
	if ($h->{index} || $h->{index_tbl} || $h->{unique}) {
		$save{index} = 1;	# unique require index!
	}

	#
	# default value
	#
	my $v = $self->check_default_value($table, $col, $info, $h->{default}, $h->{default_sql});
	if (!defined $v) {
		return;
	}
	$save{default} = $v;

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
		$save{ref} = $t eq $table ? $c : $ref;
	}

	# save to internal memory
	foreach(keys(%save)) {
		$self->{"$table.$_"}->{$col} = $save{$_};
	}

	return wantarray ? (0, $col) : 0;
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

	# load index
	$table =~ s/\W//g;
	my $db = $self->load_index_for_edit($table);
	if (!defined $db) {
		$self->edit_index_exit($table);
		$self->error("Can't find '%s' table", $table);
		return 7;
	}

	# check not null, unique
	my $rows      = $#$db+1;
	my $exists_de = $h->{default} ne '' || $h->{default_sql} !~ /^(?:|null)$/i;

	if ($h->{not_null} && 0<$rows && !$exists_de) {
		$self->edit_index_exit($table);
		$self->error("Column can not be added due to NOT NULL constraint. rows=%d", $rows);
		return 8;
	}

	if ($h->{unique} && 1<$rows && $exists_de) {
		$self->edit_index_exit($table);
		$self->error("Column can not be added due to UNQIUE constraint. rows=%d", $rows);
		return 9;
	}

	# save
	my ($r, $col) = $self->parse_column($table, $h);
	if ($r) { return $r; }

	if ($rows) {
		my $de  = $self->{"$table.default"}->{$col};
		my $val = $de eq '' ? '' : (ord($de)==0x23 ? substr($de,1) : $self->load_sql_context($table, $col, $de));

		# add column from all row data
		my $all = $self->load_allrow($table);
		foreach(@$all) {
			$_->{$col} = $val;
			$self->write_rowfile($table, $_);
		}
	}

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
	$table  =~ s/\W//g;
	$col    =~ s/\W//g;
	if ($table eq '' || $col eq '' || $col eq 'pkey') { return 7; }

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
		$self->error("Can't find '%s' column in table '%s'", $col, $table);
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
	my $all = $self->load_allrow($table);
	foreach(@$all) {
		delete $_->{$col};
		$self->write_rowfile($table, $_);
	}

	$self->save_index($table);
	$self->save_backup_index($table);
	$self->clear_cache($table);

	return 0;
}

#-------------------------------------------------------------------------------
# create index
#-------------------------------------------------------------------------------
sub create_index {
	my $self = shift;
	my $table= shift =~ tr/A-Z/a-z/r;
	my $col  = shift =~ tr/A-Z/a-z/r;
	if ($col eq 'pkey') { return 7; }

	# load index
	$table =~ s/\W//g;
	my $db = $self->load_index_for_edit($table);
	if (!defined $db) {
		$self->edit_index_exit($table);
		$self->error("Can't find '%s' table", $table);
		return 9;
	}

	# check
	my $cols = $self->{"$table.cols"};
	my $idx  = $self->{"$table.index"};
	if (!$cols->{$col}) {
		$self->edit_index_exit($table);
		$self->error($ErrNotFoundCol, $table, $col);
		return 11;
	}
	if ($idx->{$col}) {
		$self->edit_index_exit($table);
		$self->error('In "%s" table, already exists index of "%s".', $table, $col);
		return 12;
	}

	# update table info
	$idx->{$col}=1;

	$self->load_allrow($table);
	$self->save_index($table);
	$self->save_backup_index($table);

	return 0;
}

#-------------------------------------------------------------------------------
# drop index
#-------------------------------------------------------------------------------
sub drop_index {
	my $self = shift;
	my $table= shift =~ tr/A-Z/a-z/r;
	my $col  = shift =~ tr/A-Z/a-z/r;
	if ($col eq 'pkey') { return 7; }

	# load index
	$table =~ s/\W//g;
	my $db = $self->load_index_for_edit($table);
	if (!defined $db) {
		$self->edit_index_exit($table);
		$self->error("Can't find '%s' table", $table);
		return 9;
	}

	# check
	my $cols = $self->{"$table.cols"};
	my $idx  = $self->{"$table.index"};
	my $uniq = $self->{"$table.unique"};
	if (!$cols->{$col}) {
		$self->edit_index_exit($table);
		$self->error($ErrNotFoundCol, $table, $col);
		return 11;
	}
	if (!$idx->{$col}) {
		$self->edit_index_exit($table);
		$self->error('In "%s" table, not found index of "%s".', $table, $col);
		return 12;
	}
	if ($uniq->{$col}) {
		$self->edit_index_exit($table);
		$self->error('In "%s" table, due to the unique constraint, the "%s" column needs an index.', $table, $col);
		return 13;
	}

	# update table info
	delete $idx->{$col};

	$self->save_index($table);
	$self->save_backup_index($table);

	return 0;
}

#-------------------------------------------------------------------------------
# set not null
#-------------------------------------------------------------------------------
sub set_not_null {
	my $self = shift;
	my $table= shift =~ tr/A-Z/a-z/r;
	my $col  = shift =~ tr/A-Z/a-z/r;
	if ($col eq 'pkey') { return 7; }

	# load index
	$table =~ s/\W//g;
	my $db = $self->load_index_for_edit($table);
	if (!defined $db) {
		$self->edit_index_exit($table);
		$self->error("Can't find '%s' table", $table);
		return 9;
	}

	# check
	my $cols = $self->{"$table.cols"};
	my $notn = $self->{"$table.notnull"};
	if (!$cols->{$col}) {
		$self->edit_index_exit($table);
		$self->error($ErrNotFoundCol, $table, $col);
		return 11;
	}
	if ($notn->{$col}) {
		$self->edit_index_exit($table);
		return 0;				# Success
	}

	my $list = $self->load_allrow($table);
	foreach(@$list) {
		if ($_->{$col} ne '') { next; }

		$self->error('In "%s" table, null data exists "%s" column', $table, $col);
		return 12;
	}

	# update table info
	$notn->{$col}=1;

	$self->save_index($table);
	$self->save_backup_index($table);

	return 0;
}

#-------------------------------------------------------------------------------
# drop not null
#-------------------------------------------------------------------------------
sub drop_not_null {
	my $self = shift;
	my $table= shift =~ tr/A-Z/a-z/r;
	my $col  = shift =~ tr/A-Z/a-z/r;
	if ($col eq 'pkey') { return 7; }

	# load index
	$table =~ s/\W//g;
	my $db = $self->load_index_for_edit($table);
	if (!defined $db) {
		$self->edit_index_exit($table);
		$self->error("Can't find '%s' table", $table);
		return 9;
	}

	# check
	my $cols = $self->{"$table.cols"};
	my $notn = $self->{"$table.notnull"};
	if (!$cols->{$col}) {
		$self->edit_index_exit($table);
		$self->error($ErrNotFoundCol, $table, $col);
		return 11;
	}
	if (!$notn->{$col}) {
		$self->edit_index_exit($table);
		return 0;				# Success
	}

	# update table info
	delete $notn->{$col};

	$self->save_index($table);
	$self->save_backup_index($table);

	return 0;
}

#-------------------------------------------------------------------------------
# set default
#-------------------------------------------------------------------------------
sub set_default {
	my $self = shift;
	my $table= shift =~ tr/A-Z/a-z/r;
	my $col  = shift =~ tr/A-Z/a-z/r;
	my $val  = shift;
	my $sqlv = shift;		# SQL value
	if ($col eq 'pkey') { return 7; }

	# load index
	$table =~ s/\W//g;
	my $db = $self->load_index_for_edit($table);
	if (!defined $db) {
		$self->edit_index_exit($table);
		$self->error("Can't find '%s' table", $table);
		return 9;
	}

	# check
	my $cols = $self->{"$table.cols"};
	my $de   = $self->{"$table.default"};
	my $info = $cols->{$col};
	if (!$info) {
		$self->edit_index_exit($table);
		$self->error($ErrNotFoundCol, $table, $col);
		return 11;
	}

	my $v = $self->check_default_value($table, $col, $info, $val, $sqlv);
	if (!defined $v) {
		$self->edit_index_exit($table);
		return 12;
	}

	# update table info
	$de->{$col}=$v;

	$self->save_index($table);
	$self->save_backup_index($table);

	return 0;
}

sub check_default_value {
	my $self = shift;
	my $table= shift;
	my $col  = shift;
	my $info = shift;
	my $val  = shift;
	my $sqlv = shift;	# SQL value

	if ($sqlv =~ /^NULL$/i) {
		return '';
	}

	if ($sqlv ne '') {
		my $v = $self->load_sql_context($table, $col, $sqlv);
		if (!defined $v) {
			return;
		}
		if ($v ne '' && &{$info->{check}}($v) eq '') {
			$self->error('Column "%s %s" have invalid default value: %s', $col, $info->{type}, $sqlv);
			return;
		}
		return $sqlv =~ tr/a-z/A-Z/r;
	}

	if ($val ne '') {
		my $v = $val;
		if ($v ne '' && &{$info->{check}}($v) eq '') {
			$self->error('Column "%s %s" have invalid default value: %s', $col, $info->{type}, $val);
			return;
		}
		return '#' . $val;
	}
	return '';
}

#-------------------------------------------------------------------------------
# drop default
#-------------------------------------------------------------------------------
sub drop_default {
	my $self = shift;
	my $table= shift =~ tr/A-Z/a-z/r;
	my $col  = shift =~ tr/A-Z/a-z/r;
	if ($col eq 'pkey') { return 7; }

	# load index
	$table =~ s/\W//g;
	my $db = $self->load_index_for_edit($table);
	if (!defined $db) {
		$self->edit_index_exit($table);
		$self->error("Can't find '%s' table", $table);
		return 9;
	}

	# check
	my $cols = $self->{"$table.cols"};
	my $de   = $self->{"$table.default"};
	if (!$cols->{$col}) {
		$self->edit_index_exit($table);
		$self->error($ErrNotFoundCol, $table, $col);
		return 11;
	}
	if ($de->{$col} eq '') {
		$self->edit_index_exit($table);
		return 0;				# Success
	}

	# update table info
	$de->{$col}=undef;

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
		my $x = $_ eq 'pkey' ? '(serial)' : $default->{$_};
		push(@cols, {
			name	=> $_,
			type	=> $cols->{$_}->{type},
			unique	=> $unique->{$_}  ? 'YES' : 'NO',
			notnull	=> $notnull->{$_} ? 'YES' : 'NO',
			default	=> $x =~ /^#(.*)/ ? ($1+0 eq $1 ? $1 : "'$1'") : $x,
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
# index file functions
################################################################################
sub save_backup_index {
	my $self  = shift;
	my $table = shift;

	local ($self->{index_file})   = $self->{index_backup};
	local ($self->{"$table.tbl"}) = [];
	$self->save_index($table, 1);
	return 0;
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
