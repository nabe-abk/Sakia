use strict;
package Sakia::DB::pg;
################################################################################
# insert, update, delete
################################################################################
#-------------------------------------------------------------------------------
# insert
#-------------------------------------------------------------------------------
sub insert {
	my ($self, $table, $h) = @_;
	$table =~ s/\W//g;

	my ($cols, $vals);
	my @ary;
	foreach(sort(keys(%$h))) {
		if ($_ !~ /^(\*?)(\w+)$/) { next; }
		$cols .= "$2,";
		my $v = $h->{$_};
		if ($1) {
			# $v =~ s![^\w\+\-\*\/\%\(\)\|\@\&\~<>]!!g;
			$vals .= "$v,";
		} else {
			$vals .= '?,';
			if ($v eq '') { undef $v; }
			push(@ary, $v);
		}
	}
	chop($cols); chop($vals);

	# insert with pkey
	my $pkey = int($h->{pkey});
	if (exists $h->{pkey}) {
		if ($pkey<1) {
			$self->error("pkey=$pkey error on $table");
			return 0;
		}
	}

	# execute
	my $sth = $self->do_sql("INSERT INTO $table($cols) VALUES($vals)", @ary);
	if (!$sth || $sth->rows != 1) {
		return 0;
	}

	# if insert with pkey, set serial value
	if ($pkey) {
		$self->do_sql("SELECT setval(pg_catalog.pg_get_serial_sequence('$table', 'pkey'), (SELECT max(pkey) FROM $table))");
		return $pkey;
	}

	# if success return pkey
	my $sth = $self->do_sql("SELECT lastval()");
	if (!$sth) {
		return 0;
	}

	return $sth->fetchrow_array;
}

#-------------------------------------------------------------------------------
# generate pkey
#-------------------------------------------------------------------------------
sub generate_pkey {
	my ($self, $table) = @_;
	$table =~ s/\W//g;

	my $sth = $self->do_sql("SELECT nextval(pg_catalog.pg_get_serial_sequence('$table', 'pkey'))");
	if (!$sth) {
		return 0;
	}

	return $sth->fetchrow_array;
}

#-------------------------------------------------------------------------------
# update
#-------------------------------------------------------------------------------
sub update_match {
	my $self = shift;
	my $table= shift;
	my $h    = shift;
	$table =~ s/\W//g;

	# for set values
	my $cols;
	my @ary;
	foreach(sort(keys(%$h))) {
		if ($_ !~ /^(\*?)(\w+)$/) { next; }
		my $k = $2;
		my $v = $h->{$_};
		if ($1) {
			# $v =~ s![^\w\+\-\*\/\%\(\)\|\@\&\~<>]!!g;
			$cols .= "$k=$v,";
		} else {
			$cols .= "$k=?,";
			if ($v eq '') { undef $v; }
			push(@ary, $v);
		}
	}
	chop($cols);
	if ($cols eq '') { return 0; }

	my $where = $self->generate_where(\@ary, @_);
	my $sth   = $self->do_sql("UPDATE $table SET $cols$where", @ary);
	if (!$sth) {
		return 0;
	}
	return $sth->rows;
}

#-------------------------------------------------------------------------------
# delete
#-------------------------------------------------------------------------------
sub delete_match {
	my $self = shift;
	my $table= shift;
	$table =~ s/\W//g;

	my @ary;
	my $where = $self->generate_where(\@ary, @_);
	my $sth   = $self->do_sql("DELETE FROM $table$where", @ary);
	if (!$sth) {
		return 0;
	}
	return $sth->rows;
}

################################################################################
# transaction
################################################################################
sub begin {
	my $self = shift;
	my $dbh  = $self->{dbh};
	$self->{begin} = 1;
	$self->trace('BEGIN');
	$dbh->begin_work();
}
sub commit {
	my $self = shift;
	my $dbh  = $self->{dbh};
	if ($self->{begin}<0) {		# set by error() in share.pm
		return $self->rollback();
	}
	$self->{begin} = 0;
	$self->trace('COMMIT');
	return !$dbh->commit();
}
sub rollback {
	my $self = shift;
	my $dbh  = $self->{dbh};
	$self->{begin} = 0;
	$self->trace('ROLLBACK');
	$dbh->rollback();
	return -1;
}

################################################################################
# generate where for update_match(), delete_match()
################################################################################
sub generate_where {
	my $self = shift;
	my $ary  = shift;

	my $where;
	while(@_) {
		my $col = shift;
		my $val = shift;
		if (!defined $col) { last; }

		my $not = substr($col,0,1) eq '-' ? 1 : 0;
		$col =~ s/[^\w\.]//g;
		if ($val eq '') {
			$where .= " AND $col IS " . ($not ? 'NOT NULL' : 'NULL');
			next;
		}
		if (ref($val) ne 'ARRAY') {
			$where .= $not ? " AND $col!=?" :" AND $col=?";
			push(@$ary, $val);
			next;
		}
		# $val is array

		if (!@$val) {
			$where .= $not ? '' : ' AND false';
			next;
		}
		my $w = '?,' x ($#$val+1);
		chop($w);
		$where .= $not ? " AND not $col in ($w)" : " AND $col in ($w)";
		push(@$ary, @$val);
	}
	$where = substr($where, 5);
	if ($where ne '') { $where = " WHERE $where"; }
	return $where;
}

################################################################################
# direct SQL
################################################################################
sub do_sql {
	my $self = shift;
	my $sql  = shift;
	my $dbh = $self->{dbh};
	$self->trace($sql, \@_);

	my $sth = $dbh->prepare($sql);
	$sth && $sth->execute(@_);
	if (!$sth || $dbh->err) {
		$self->error($sql);
		$self->error($dbh->errstr);
		return;
	}
	return $sth;
}
sub do_sql_rows {
	my $self = shift;
	my $sth  = $self->do_sql(@_);
	return $sth ? $sth->rows : undef;
}
sub select_sql {
	my $self = shift;
	my $sth  = $self->do_sql(@_);
	if (!$sth) { return []; }
	return $sth->fetchall_arrayref({});
}

sub load_dbh {
	my $self = shift;
	return $self->{dbh};
}

sub prepare {
	my $self = shift;
	my $sql  = shift;
	my $dbh  = $self->{dbh};
	$self->trace($sql);
	return $dbh->prepare($sql);
}

1;
