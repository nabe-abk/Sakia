use strict;
package Sakia::DB::mysql;
use Sakia::DB::share_3;
################################################################################
# manupilate table
################################################################################
#-------------------------------------------------------------------------------
# create table
#-------------------------------------------------------------------------------
sub create_table {
	my ($self, $table, $columns) = @_;
	my $dbh  = $self->{dbh};
	my $ROBJ = $self->{ROBJ};
	$table =~ s/\W//g;
	if ($table eq '') {
		$self->error('Called create_table() with null table name.');
		return 8;
	}

	#-----------------------------------------
	# table columns
	#-----------------------------------------
	my @cols = ('pkey int NOT NULL AUTO_INCREMENT PRIMARY KEY');
	# Do not change to "SERIAL", for compatibility with other RDBMS.
	# MySQL's "SERIAL" is "bigint unsgined".
	# In a standard RDBMS, "SERIAL" is "int".

	my @vals;
	my @index_cols;
	my %text_col;
	foreach(@$columns) {
		if ($_->{name} eq 'pkey') {
			if    ($_->{type} =~ /^bigserial$/i) { $cols[0] = 'pkey bigint NOT NULL AUTO_INCREMENT PRIMARY KEY'; }
			elsif ($_->{type} !~ /^serial$/i) {
				$self->error('The pkey column type is invalid: %s', $_->{type});
				return 9;
			}
			next;
		}
		my ($col, $sql, $is_text, @ary) = $self->parse_column($_);
		if (!$col) { return 10; }	# error

		push(@cols, $sql);
		push(@vals, @ary);
		if ($is_text) {
			$text_col{$col} = 1;
		}

		if (!$_->{unique} && $_->{index}) {
			# UNIQUE column is auto index -> not need "create index"
			push(@index_cols, $col);
		}
	}

	#-----------------------------------------
	# create
	#-----------------------------------------
	my $sql = "CREATE TABLE $table(" . join(",\n ", @cols) . ')';
	if ($self->{engine}) {	# DB Engine
		$sql .= " ENGINE=" . ($self->{engine} =~ s/\W//rg);
	}
	my $sth = $dbh->prepare($sql);
	$self->trace($sql);
	$sth && $sth->execute(@vals);
	if (!$sth || $dbh->err) {
		$self->error($sql);
		$self->error($dbh->errstr);
		return 1;
	}

	#-----------------------------------------
	# CREATE INDEX
	#-----------------------------------------
	# Note: (length) prefix required for text column. This is not required on MariaDB.
	foreach(@index_cols) {
		my $length = $text_col{$_} ? "(". int($self->{text_index_size}) .")" : '';
		my $sql = "CREATE INDEX ${table}_${_}_idx ON $table($_$length)";
		$dbh->do($sql);
		$self->trace($sql);
		if ($dbh->err) {
			$self->error($sql);
			$self->error($dbh->errstr);
			return 2;
		}
	}
	return 0;
}

sub parse_column {
	my $self = shift;
	my $h    = shift;

	my $col = $h->{name} =~ s/\W//rg;
	if ($col eq '') {
		$self->error('Column name is null');
		return;
	}

	my $sql='';
	my @vals;
	my $is_text;

	my $t = $h->{type} =~ tr/A-Z/a-z/r;
	if    ($t eq 'int')	{ $sql .= "$col INT";     }
	elsif ($t eq 'bigint')	{ $sql .= "$col BIGINT";  }
	elsif ($t eq 'float')	{ $sql .= "$col FLOAT";   }
	elsif ($t eq 'flag')	{ $sql .= "$col BOOLEAN"; }
	elsif ($t eq 'boolean')	{ $sql .= "$col BOOLEAN"; }
	elsif ($t eq 'text') {
	  if ($h->{unique} || $h->{ref}){ $sql .= "$col VARCHAR(" . int($self->{unique_text_size} || 255) .")"; }
		else			{ $sql .= "$col TEXT"; $is_text=1; }
	}
	elsif ($t eq 'ltext')	{ $sql .= "$col MEDIUMTEXT"; }
	elsif ($t eq 'date')	{ $sql .= "$col DATE";    }
	elsif ($t eq 'timestamp' || $t eq 'timestamp(0)'){ $sql .= "$col DATETIME(0)"; }
	else {
		$self->error('Column "%s" have invalid type "%s"', $col, $h->{type});
		return;
	}

	if ($h->{unique})   { $sql .= ' UNIQUE';   }
	if ($h->{not_null}) { $sql .= ' NOT NULL'; }
	if ($h->{default_sql} ne '') {
		my $v = $h->{default_sql};
		$sql .= " DEFAULT " . ($v =~ /^\w+$/ ? $v : '*error*');
	} elsif ($h->{default} ne '') {
		$sql .= " DEFAULT ?";
		push(@vals, $h->{default});
	}
	if ($_->{ref}) {
		# foreign key（table_name.col_name）
		my ($ref_table, $ref_col) = split(/\./, $h->{ref} =~ s/[^\w\.]//rg);
		$sql .= " REFERENCES $ref_table($ref_col) ON UPDATE CASCADE";
	}

	return ($col, $sql, $is_text, @vals);
}

#-------------------------------------------------------------------------------
# drop table
#-------------------------------------------------------------------------------
sub drop_table {
	my ($self, $table) = @_;
	my $dbh  = $self->{dbh};
	my $ROBJ = $self->{ROBJ};
	$table =~ s/\W//g;

	my $sql = "DROP TABLE $table";
	$dbh->do($sql);
	if ($dbh->err) {
		$self->error($sql);
		$self->error($dbh->errstr);
		return 1;
	}

	# delete from cache
	my $cache    = $self->{exists_table_cache};
	my $cache_id = $self->{db_id} . $table;
	delete $cache->{$cache_id};

	return 0;
}

################################################################################
# support functions
################################################################################
#-------------------------------------------------------------------------------
# add column
#-------------------------------------------------------------------------------
sub add_column {
	my ($self, $table, $h) = @_;
	my $dbh  = $self->{dbh};
	my $ROBJ = $self->{ROBJ};

	$table =~ s/\W//g;
	if ($table eq '') { return 9; }

	my ($col, $sql, $is_text, @vals) = $self->parse_column($h);
	if (!$col) { return; }	# error

	# ALTER TABLE
	$sql = "ALTER TABLE $table ADD COLUMN $sql";
	my $sth = $dbh->prepare($sql);
	$self->trace($sql);
	$sth && $sth->execute(@vals);
	if (!$sth || $dbh->err) {
		$self->error($sql);
		$self->error($dbh->errstr);
		return 1;
	}

	# CREATE INDEX table_colname_idx ON table (colname);
	if (!$h->{unique} && $h->{index}) {
		my $length = $is_text ? "(". int($self->{text_index_size}) .")" : '';
		my $sql = "CREATE INDEX ${table}_${col}_idx ON $table($col$length)";
		$dbh->do($sql);
		$self->trace($sql);
		if ($dbh->err) {
			$self->error($sql);
			$self->error($dbh->errstr);
			return 2;
		}
	}
	return 0;
}

#-------------------------------------------------------------------------------
# drop column
#-------------------------------------------------------------------------------
sub drop_column {
	my ($self, $table, $column) = @_;
	my $dbh  = $self->{dbh};
	my $ROBJ = $self->{ROBJ};
	$table  =~ s/\W//g;
	$column =~ s/\W//g;
	if ($table eq '' || $column eq '') { return 9; }

	my $sql = "ALTER TABLE $table DROP COLUMN $column";
	my $sth = $dbh->prepare($sql);
	$self->trace($sql);
	$sth && $sth->execute();
	if (!$sth || $dbh->err) {
		$self->error($sql);
		$self->error($dbh->errstr);
		return 1;
	}
	return 0;
}

#-------------------------------------------------------------------------------
# add index
#-------------------------------------------------------------------------------
sub add_index {
	my ($self, $table, $column) = @_;
	my $dbh  = $self->{dbh};
	my $ROBJ = $self->{ROBJ};
	$table  =~ s/\W//g;
	$column =~ s/\W//g;
	if ($table eq '' || $column eq '') { return 9; }

	my $sql = "CREATE INDEX ${table}_${column}_idx ON $table($column)";
	my $sth = $dbh->prepare($sql);
	$self->trace($sql);
	$sth && $sth->execute();
	if (!$sth || $dbh->err) {
		$self->error($sql);
		$self->error($dbh->errstr);
		return 1;
	}

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
	my $dbh  = $self->{dbh};

	my $sql = "SHOW TABLES";
	my $sth = $dbh->prepare($sql);
	$self->trace($sql);
	$sth && $sth->execute();
	if (!$sth || $dbh->err) {
		$self->error($sql);
		$self->error($dbh->errstr);
		return;
	}

	my $ary = $sth->fetchall_arrayref();
	return [ map { $_->[0] } @$ary ];
}

#-------------------------------------------------------------------------------
# get table columns
#-------------------------------------------------------------------------------
sub get_colmuns_info {
	my $self = shift;
	my $table= shift;
	my $dbh  = $self->{dbh};
	$table  =~ s/\W//g;
	if ($table eq '') { return 9; }

	my $sql = "SHOW COLUMNS FROM $table";
	my $sth = $dbh->prepare($sql);
	$self->trace($sql);
	$sth && $sth->execute();
	if (!$sth || $dbh->err) {
		$self->error($sql);
		$self->error($dbh->errstr);
		return;
	}
	my $cols = $sth->fetchall_arrayref({});

	my $sql = "SHOW INDEX FROM $table";
	my $sth = $dbh->prepare($sql);
	$self->trace($sql);
	$sth && $sth->execute();
	if (!$sth || $dbh->err) {
		$self->error($sql);
		$self->error($dbh->errstr);
		return;
	}
	my $ary = $sth->fetchall_arrayref({});
	my %h   = map { $_->{Column_name} => $_ } @$ary;
	foreach(@$cols) {
		my $x = $h{$_->{Field}} || {};
		$_->{Key_name}   = $x->{Key_name};
		$_->{Index_type} = $x->{Index_type};
	}
	return $cols;
}

#-------------------------------------------------------------------------------
# SQL console
#-------------------------------------------------------------------------------
sub sql_console {
	my $self = shift;
	my $sql  = shift;
	my $dbh  = $self->{dbh};
	if (!$self->{admin}) { return; }

	my @log;

	my $sth = $dbh->prepare($sql);
	$sth && $sth->execute();
	if (!$sth || $dbh->err) {
		push(@log, split(/\n/, $dbh->errstr));
		return (undef, \@log);
	}
	push(@log, "Success");

	if (0 <= $sth->rows) {
		push(@log, "rows: " . $sth->rows);
	}
	my $ary = $sth->fetchall_arrayref({});
	return ($ary, \@log);
}

1;
