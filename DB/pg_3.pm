use strict;
package Sakia::DB::pg;
use Sakia::DB::share_3;
################################################################################
# manupilate table
################################################################################
#-------------------------------------------------------------------------------
# create table
#-------------------------------------------------------------------------------
sub create_table {
	my ($self, $table, $columns) = @_;
	$table =~ s/\W//g;
	if ($table eq '') {
		$self->error('Called create_table() with null table name.');
		return 8;
	}

	#-----------------------------------------
	# table columns
	#-----------------------------------------
	my @cols = ('pkey SERIAL PRIMARY KEY');
	my @vals;
	my @index_cols;
	foreach(@$columns) {
		if ($_->{name} eq 'pkey') {
			if    ($_->{type} =~ /^bigserial$/i) { $cols[0] = 'pkey BIGSERIAL PRIMARY KEY'; }
			elsif ($_->{type} !~ /^serial$/i) {
				$self->error('The pkey column type is invalid: %s', $_->{type});
				return 9;
			}
			next;
		}
		my ($col, $sql, @ary) = $self->parse_column($_);
		if (!$col) { return 10; }	# error

		push(@cols, $sql);
		push(@vals, @ary);

		if (!$_->{unique} && $_->{index}) {
			# UNIQUE column is auto index -> not need "create index"
			push(@index_cols, $col);
		}
	}

	#-----------------------------------------
	# create
	#-----------------------------------------
	my $sth = $self->do_sql("CREATE TABLE $table(" . join(",\n ", @cols) . ')');
	if (!$sth) {
		return 1;
	}

	#-----------------------------------------
	# CREATE INDEX
	#-----------------------------------------
	foreach(@index_cols) {
		my $sth = $self->do_sql("CREATE INDEX ${table}_${_}_idx ON $table($_)");
		if (!$sth) {
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
	my $sql;
	my @vals;

	my $t = $h->{type} =~ tr/A-Z/a-z/r;
	if    ($t eq 'int')	{ $sql .= "$col INT";     }
	elsif ($t eq 'bigint')	{ $sql .= "$col BIGINT";  }
	elsif ($t eq 'float')	{ $sql .= "$col FLOAT";   }
	elsif ($t eq 'boolean')	{ $sql .= "$col BOOLEAN"; }
	elsif ($t eq 'text')	{ $sql .= "$col TEXT";    }
	elsif ($t eq 'ltext')	{ $sql .= "$col TEXT";    }
	elsif ($t eq 'date')	{ $sql .= "$col DATE";    }
	elsif ($t eq 'timestamp' || $t eq 'timestamp(0)'){ $sql .= "$col TIMESTAMP(0)"; }
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

	return ($col, $sql, @vals);
}

#-------------------------------------------------------------------------------
# drop table
#-------------------------------------------------------------------------------
sub drop_table {
	my ($self, $table) = @_;
	$table =~ s/\W//g;
	if ($table eq '') { return 9; }

	my $sth = $self->do_sql("DROP TABLE $table");
	if (!$sth) {
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
	$table =~ s/\W//g;
	if ($table eq '') { return 9; }

	my ($col, $sql, @vals) = $self->parse_column($h);
	if (!$col) { return 10; }	# error

	# ALTER TABLE
	my $sth = $self->do_sql("ALTER TABLE $table ADD COLUMN $sql", @vals);
	if (!$sth) {
		return 1;
	}

	# CREATE INDEX table_colname_idx ON table (colname);
	if (!$h->{unique} && $h->{index}) {
		my $sth = $self->do_sql("CREATE INDEX ${table}_${col}_idx ON $table($col)");
		if (!$sth) {
			return 2;
		}
	}
	return 0;
}

#-------------------------------------------------------------------------------
# drop column
#-------------------------------------------------------------------------------
sub drop_column {
	my ($self, $table, $col) = @_;
	$table =~ s/\W//g;
	$col   =~ s/\W//g;
	if ($table eq '' || $col eq '' || $col =~ /^pkey$/i) { return 9; }

	my $sth = $self->do_sql("ALTER TABLE $table DROP COLUMN $col");

	return $sth ? 0 : 1;
}

#-------------------------------------------------------------------------------
# create index
#-------------------------------------------------------------------------------
sub create_index {
	my ($self, $table, $col) = @_;
	$table =~ s/\W//g;
	$col   =~ s/\W//g;
	if ($table eq '' || $col eq '' || $col =~ /^pkey$/i) { return 9; }

	my $sth = $self->do_sql("CREATE INDEX ${table}_${col}_idx ON $table($col)");

	return $sth ? 0 : 1;
}

#-------------------------------------------------------------------------------
# drop index
#-------------------------------------------------------------------------------
sub drop_index {
	my ($self, $table, $col) = @_;
	$table =~ s/\W//g;
	$col   =~ s/\W//g;
	if ($table eq '' || $col eq '' || $col =~ /^pkey$/i) { return 9; }

	my $sth = $self->do_sql("DROP INDEX ${table}_${col}_idx");

	return $sth ? 0 : 1;
}

#-------------------------------------------------------------------------------
# set not null
#-------------------------------------------------------------------------------
sub set_not_null {
	my ($self, $table, $col) = @_;
	$table =~ s/\W//g;
	$col   =~ s/\W//g;
	if ($table eq '' || $col eq '' || $col =~ /^pkey$/i) { return 9; }

	my $sth = $self->do_sql("ALTER TABLE $table ALTER $col SET NOT NULL");

	return $sth ? 0 : 1;
}

#-------------------------------------------------------------------------------
# drop not null
#-------------------------------------------------------------------------------
sub drop_not_null {
	my ($self, $table, $col) = @_;
	$table =~ s/\W//g;
	$col   =~ s/\W//g;
	if ($table eq '' || $col eq '' || $col =~ /^pkey$/i) { return 9; }

	my $sth = $self->do_sql("ALTER TABLE $table ALTER $col DROP NOT NULL");

	return $sth ? 0 : 1;
}

#-------------------------------------------------------------------------------
# set default
#-------------------------------------------------------------------------------
sub set_default {
	my ($self, $table, $col, $val, $sqlv) = @_;
	$table =~ s/\W//g;
	$col   =~ s/\W//g;
	if ($table eq '' || $col eq '' || $col =~ /^pkey$/i) { return 9; }

	my $sv  = $sqlv ne '';
	my @ary = $sv ? ()    : ($val eq '' ? undef : $val);
	$val    = $sv ? $sqlv : '?';
	my $sth = $self->do_sql("ALTER TABLE $table ALTER $col SET DEFAULT $val", @ary);

	return $sth ? 0 : 1;
}

#-------------------------------------------------------------------------------
# drop default
#-------------------------------------------------------------------------------
sub drop_default {
	my ($self, $table, $col) = @_;
	$table =~ s/\W//g;
	$col   =~ s/\W//g;
	if ($table eq '' || $col eq '' || $col =~ /^pkey$/i) { return 9; }

	my $sth = $self->do_sql("ALTER TABLE $table ALTER $col DROP DEFAULT");

	return $sth ? 0 : 1;
}

################################################################################
# admin functions
################################################################################
#-------------------------------------------------------------------------------
# get DB Version
#-------------------------------------------------------------------------------
sub db_version {
	my $self = shift;
	my $dbh  = $self->{dbh};

	my $sth = $self->do_sql("SELECT version()");
	if (!$sth) {
		return '';
	}
	return $sth->fetchrow_array;
}

#-------------------------------------------------------------------------------
# get table list
#-------------------------------------------------------------------------------
sub get_tables {
	my $self = shift;

	my $sth = $self->do_sql("SELECT tablename FROM pg_catalog.pg_tables WHERE schemaname NOT LIKE 'pg_%' AND schemaname != 'information_schema'");
	if (!$sth) {
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
	$table  =~ s/\W//g;
	if ($table eq '') { return 9; }

	my $DB_NAME = $self->{ID} =~ /database=(\w+)/ ? $1 : undef;
	my $cols= 'column_name, data_type, column_default, is_nullable, datetime_precision';
	my $sth = $self->do_sql("SELECT $cols FROM information_schema.columns WHERE table_catalog=? and table_name=? ORDER BY ordinal_position", $DB_NAME, $table);
	if (!$sth) {
		return;
	}
	my $cols = $sth->fetchall_arrayref({});

	my $sth = $self->do_sql("SELECT indexname,indexdef FROM pg_indexes WHERE tablename=?", $table);
	if (!$sth) {
		return;
	}
	my $ary = $sth->fetchall_arrayref({});

	my %h;
	foreach(@$ary) {
		if ($_->{indexdef} =~ /\((\w+)\)$/) { $h{$1}=$_; }
	}
	foreach(@$cols) {
		my $x = $h{$_->{column_name}} || {};
		$_->{indexname} = $x->{indexname};
		$_->{indexdef}  = $x->{indexdef};
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

	my @str;
	$sql =~ s/\0//g;
	$sql =~ s/\s+--.*//g;
	$sql =~ s!('(?:[^']|'')*')!push(@str, $1), "\0$#str\0"!eg;

	my @result;
	my @log;
	foreach(split(/\s*;\s*/, $sql)) {
		$_ =~ s/\0(\d+)\0/$str[$1]/g;

		my $sth = $dbh->prepare($_);
		$sth && $sth->execute();
		if (!$sth || $dbh->err) {
			push(@log, split(/\n/, $dbh->errstr));
			next;
		}
		if (0 <= $sth->rows) {
			push(@log, "rows: " . $sth->rows);
		}
		if ($sth->rows) {
			my $ary = $sth->fetchall_arrayref({});
			if (@$ary) {
				push(@result, $ary);
			}
		}
	}
	return (\@result, \@log);
}

1;
