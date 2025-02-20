use strict;
package Sakia::DB::text;
use Sakia::DB::share_3;
#-------------------------------------------------------------------------------
our $FileNameFormat;
our %IndexCache;
################################################################################
# manupilate table
################################################################################
#-------------------------------------------------------------------------------
# create table
#-------------------------------------------------------------------------------
sub create_table {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	my ($table, $colums) = @_;
	$table =~ s/\W//g;
	$table =~ tr/A-Z/a-z/;
	if ($table eq '') { $self->error('Called create_table() with null table name'); return 9; }

	#--------------------------------------------------
	# check table name
	#--------------------------------------------------
	my $dir = $self->{dir} . $table . '/';
	if (!-e $dir) {
		if (!$ROBJ->mkdir($dir)) { $self->error("mkdir '$dir' error : $!"); }
	}
	if ($table =~ /^\d/) {
		$self->error("To be a 'a-z' or '_' at the first character of a table name : '%s'", $table);
		return 30;
	}
	my $index = $dir . $self->{index_file};
	if (-e $index) {
		$self->error("'%s' table already exists", $table);
		return 40;
	}

	#--------------------------------------------------
	# parse columns
	#--------------------------------------------------
	$self->{"$table.cols"}    = { 'pkey'=>1 };	# all
	$self->{"$table.idx"}     = { 'pkey'=>1 };	# index
	$self->{"$table.int"}     = { 'pkey'=>1 };	# integer
	$self->{"$table.float"}   = {};			# number
	$self->{"$table.flag"}    = {};			# flag(boolean)
	$self->{"$table.str"}     = {};			# string
	$self->{"$table.unique"}  = { 'pkey'=>1 };	# UNIQUE
	$self->{"$table.notnull"} = { 'pkey'=>1 };	# NOT NULL
	$self->{"$table.default"} = {};			# Default value
	$self->{"$table.serial"}  = 0;

	foreach(@$colums) {
		my $err = $self->parse_column($table, $_);
		if ($err) {
			return $err;
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

	my $col = $h->{name};
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
	if    ($h->{type} eq 'int')    { $self->{"$table.int"}  ->{$col}=1; }
	elsif ($h->{type} eq 'bigint') { $self->{"$table.int"}  ->{$col}=1; }	# work on 64bit perl
	elsif ($h->{type} eq 'float')  { $self->{"$table.float"}->{$col}=1; }
	elsif ($h->{type} eq 'flag')   { $self->{"$table.flag"} ->{$col}=1; }
	elsif ($h->{type} eq 'boolean'){ $self->{"$table.flag"} ->{$col}=1; }
	elsif ($h->{type} eq 'text')   { $self->{"$table.str"}  ->{$col}=1; }
	elsif ($h->{type} eq 'ltext')  { $self->{"$table.str"}  ->{$col}=1; }
	else {
		$self->error('Column "%s" have invalid type "%s"', $col, $h->{type});
		return 10;
	}
	$self->{"$table.cols"}->{$col}=1;
	if ($h->{unique})  { $self->{"$table.unique"} ->{$col}=1; }	# UNIQUE
	if ($h->{notnull}) { $self->{"$table.notnull"}->{$col}=1; }	# NOT NULL
	if ($h->{index} || $h->{index_tbl} || $h->{unique}) {
		$self->{"$table.idx"}->{$col}=1;
	}
	if ($h->{default} ne '') {
		$self->{"$table.default"}->{$col} = $h->{default};
	}

	return 0;
}

#-------------------------------------------------------------------------------
# drop table
#-------------------------------------------------------------------------------
sub drop_table {
	my ($self, $table) = @_;
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

	# バックアップの読み込み
	my $index_file_orig = $self->{index_file};
	$self->{index_file} = $self->{index_backup};
	my $db = $self->load_index($table);
	$self->{index_file} = $index_file_orig;

	# ファイルリスト取得
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
# optional functions
################################################################################
#-------------------------------------------------------------------------------
# add column
#-------------------------------------------------------------------------------
sub add_column {
	my ($self, $table, $h) = @_;
	my $ROBJ = $self->{ROBJ};

	# load index
	$table =~ s/\W//g;
	my $db = $self->load_index_for_edit($table);
	if (!defined $db) {
		$self->edit_index_exit($table);
		$self->error("Can't find '%s' table", $table);
		return 7;
	}

	my $col = $h->{name};
	$col =~ s/\W//g;
	if ($col eq '') { return 8; }

	# check column name
	my $cols = $self->{"$table.cols"};
	if ($cols->{$col}) {
		$self->edit_index_exit($table);
		$self->error("'%s' is already exists in relation '%s'", $col, $table);
		return 8;
	}
	# update table info
	if    ($h->{type} eq 'int')   { $self->{"$table.int"}  ->{$col}=1; }
	elsif ($h->{type} eq 'float') { $self->{"$table.float"}->{$col}=1; }
	elsif ($h->{type} eq 'flag')  { $self->{"$table.flag"} ->{$col}=1; }
	elsif ($h->{type} eq 'boolean'){$self->{"$table.flag"} ->{$col}=1; }
	elsif ($h->{type} eq 'text')  { $self->{"$table.str"}  ->{$col}=1; }
	elsif ($h->{type} eq 'ltext') { $self->{"$table.str"}  ->{$col}=1; }
	else {
		$self->error('Column "%s" have invalid type "%s"', $col, $h->{type});
		return 10;
	}
	$self->{"$table.cols"}->{$col}=1;
	if ($h->{unique})  { $self->{"$table.unique"} ->{$col}=1; }	# UNIQUE
	if ($h->{notnull}) { $self->{"$table.notnull"}->{$col}=1; }	# NOT NULL
	if ($h->{index} || $h->{unique}) { $self->{"$table.idx"}->{$col}=1; }

	$self->save_index($table);
	$self->save_backup_index($table);
	$self->clear_cache($table);

	return 0;
}

#-------------------------------------------------------------------------------
# drop column
#-------------------------------------------------------------------------------
sub drop_column {
	my ($self, $table, $column) = @_;
	my $ROBJ = $self->{ROBJ};
	$table  =~ s/\W//g;
	$column =~ s/\W//g;
	if ($table eq '' || $column eq '') { return 7; }

	# load index
	$table =~ s/\W//g;
	my $db = $self->load_index_for_edit($table);
	if (!defined $db) {
		$self->edit_index_exit($table);
		$self->error("Can't find '%s' table", $table);
		return 8;
	}

	# column exists?
	if (! $self->{"$table.cols"}->{$column}) {
		$self->edit_index_exit($table);
		$self->error("Can't find '%s' column in relation '%s'", $column, $table);
		return 9;
	}

	# update table info
	delete $self->{"$table.cols"}->{$column};
	delete $self->{"$table.int"}->{$column};
	delete $self->{"$table.float"}->{$column};
	delete $self->{"$table.flag"}->{$column};
	delete $self->{"$table.str"}->{$column};
	delete $self->{"$table.unique"}->{$column};
	delete $self->{"$table.notnull"}->{$column};
	delete $self->{"$table.idx"}->{$column};

	# delete column from all row data
	$self->load_allrow($table);
	my $all = $self->{"$table.tbl"};
	foreach(@$all) {
		if ($_->{$column} eq '') { next; }

		delete $_->{$column};
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
	my ($self, $table, $column) = @_;
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
	my $idx  = $self->{"$table.idx"};
	if (! grep { $_ eq $column } @$cols) {	# not exists
		$self->edit_index_exit($table);
		$self->error("On '%s' table, not exists '%s' column", $table, $column);
		return 8;
	}
	if (! grep { $_ eq $column } @$idx) {	# add to index
		push(@$idx, $column);
		my $dir     = $self->{dir} . $table . '/';
		my $ext = $self->{ext};
		$self->load_allrow($table);
	}

	$self->save_index($table);
	$self->save_backup_index($table);

	return 0;
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

1;
