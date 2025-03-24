use strict;
#-------------------------------------------------------------------------------
# database module for PostgreSQL
#						(C)2006-2025 nabe@abk
#-------------------------------------------------------------------------------
package Sakia::DB::pg;
use Sakia::AutoLoader;
use Sakia::DB::share;
use DBI ();
#-------------------------------------------------------------------------------
our $VERSION = '1.70';
my %DB_attr = (AutoCommit => 1, RaiseError => 0, PrintError => 0, PrintWarn => 0, pg_enable_utf8 => 0);
#-------------------------------------------------------------------------------
# check UTF8 bug
#-------------------------------------------------------------------------------
use DBD::Pg ();
BEGIN {
	my $v = $DBD::Pg::VERSION;
	if ($v !~ /^(\d+)\.(\d+)/ || $1<3 || $2<6) {
		die __PACKAGE__ . " requires DBD::Pg Version 3.6.0 or newer. (current: $v)";
	}
}

################################################################################
# constructor
################################################################################
sub new {
	my $class = shift;
	my ($ROBJ, $db, $id, $pass, $opt) = @_;
	my $self = bless({
		%{ $opt || {}},		# options
		ROBJ	=> $ROBJ,

		__FINISH=> 1,
		DBMS	=> 'PostgreSQL',
		ID	=> "pg.$db",
		exists_table_cache => {}
	}, $class);

	# connect
	my $con = $self->{Pool} ? 'connect_cached' : 'connect';
	my $dbh = DBI->$con("DBI:Pg:$db", $id, $pass, \%DB_attr);
	if (!$dbh) { die "Database '$db' Connection faild"; }

	$self->{dbh} = $dbh;
	return $self;
}

#-------------------------------------------------------------------------------
# destructor
#-------------------------------------------------------------------------------
sub FINISH {
	my $self = shift;
	if ($self->{begin}) { $self->rollback(); }
}

#-------------------------------------------------------------------------------
# reconnect
#-------------------------------------------------------------------------------
sub disconnect {
	my $self = shift;
	my $dbh  = $self->{dbh};
	return $dbh->disconnect();
}
sub reconnect {
	my $self = shift;
	my $force= shift;
	my $dbh  = $self->{dbh};
	if (!$force && $dbh->ping()) {
		return;
	}
	$self->{dbh} = $dbh->clone();
}

################################################################################
# find table
################################################################################
sub find_table {
	my ($self, $table) = @_;
	my $ROBJ = $self->{ROBJ};
	$table =~ s/\W//g;

	my $cache    = $self->{exists_table_cache};
	my $cache_id = $self->{db_id} . $table;
	if ($cache->{$cache_id}) { return $cache->{$cache_id}; }

	my $dbh = $self->{dbh};
	my $sql = "SELECT tablename FROM pg_tables WHERE tablename=? LIMIT 1";
	my $sth = $dbh->prepare($sql);
	$self->trace($sql);
	$sth && $sth->execute($table);

	if (!$sth || !$sth->rows || $dbh->err) { return 0; }	# error
	return ($cache->{$cache_id} = 1);			# found
}

################################################################################
# select
################################################################################
sub select {
	my ($self, $table, $h) = @_;
	my $dbh  = $self->{dbh};
	my $ROBJ = $self->{ROBJ};

	#-----------------------------------------
	# parse
	#-----------------------------------------
	my ($table, $as)   = $self->parse_table_name($table);
	my ($ljoin, $jcol) = $self->generate_left_join($h);
	my ($where, $ary)  = $self->generate_select_where($h);
	if ($ljoin && $as eq '') { $as=$table; }
	my $tname = $as ? "$as." : '';

	#-----------------------------------------
	# select cols
	#-----------------------------------------
	my $cols = $tname . '*';
	if ($h->{cols}) {
		my $x = ref($h->{cols}) ? $h->{cols} : [ $h->{cols} ];
		$cols = join(',', map { $tname . ($_ =~ s/\W//rg) } @$x);
	}

	#-----------------------------------------
	# make SQL
	#-----------------------------------------
	my $from = $table . $ljoin;
	my $sql  = "SELECT $cols$jcol FROM $from$where"
		 . $self->generate_order_by($h);

	#-----------------------------------------
	# limit and offset
	#-----------------------------------------
	my $offset = int($h->{offset});
	my $limit;
	if ($h->{limit} ne '') { $limit = int($h->{limit}); }
	if ($offset > 0)  { $sql .= ' OFFSET ' . $offset; }
	if ($limit ne '') { $sql .= ' LIMIT '  . $limit;  }

	#-----------------------------------------
	# execute
	#-----------------------------------------
	my $sth = $dbh->prepare($sql);
	$self->trace($sql, $ary);
	$sth && $sth->execute(@$ary);
	if (!$sth || $dbh->err) {
		$self->error($sql);
		$self->error($dbh->errstr);
		return $h->{want_sth} ? undef : [];
	}

	my $ret = $h->{want_sth} ? $sth : $sth->fetchall_arrayref({});
	if (!wantarray) { return $ret; }

	#-----------------------------------------
	# require hits
	#-----------------------------------------
	my $hits = $#$ret+1;
	if ($limit ne '' && $limit <= $hits) {
		my $sql = "SELECT count(*) FROM $from$where";
		my $sth = $dbh->prepare($sql);
		$self->trace($sql, $ary);
		$sth && $sth->execute(@$ary);
		if (!$sth || $dbh->err) {
			$self->error($sql);
			$self->error($dbh->errstr);
			return [];
		}
		$hits = $sth->fetchrow_array;
	}
	return ($ret,$hits);
}

################################################################################
# subrotine for select
################################################################################
#-------------------------------------------------------------------------------
# check select table name
#-------------------------------------------------------------------------------
sub parse_table_name {
	my $self = shift;
	my $table= shift;
	if ($table =~ /^(\w+) +(\w+)$/) {
		return ("$1 as $2", $2);
	}
	$table =~ s/\W//g;
	return ($table, '');
}

#-------------------------------------------------------------------------------
# generate where // called from outside the module
#-------------------------------------------------------------------------------
sub generate_select_where {
	my ($self, $h) = @_;

	my $where;
	my @ary;

	my $match = sub {
		my $k   = shift;
		my $v   = shift;
		my $not = shift;

		$k =~ s/[^\w\.]//g;
		if ($v eq '') {
			$where .= " AND $k is$not null";
			return;
		}
		if (ref($v) ne 'ARRAY') {
			$where .= $not ? " AND $k!=?" : " AND $k=?";
			push(@ary, $v);
			return;
		}
		#-----------------------------------------------------
		# $v is array ref
		#-----------------------------------------------------
		if (!@$v) {
			$where .= $not ? '' : ' AND false';
			return;
		}

		my $add='';
		if (grep {$_ eq ''} @$v) {
			$v = [ grep { $_ ne '' } @$v ];
			if (!@$v) {
				$where .= " AND $k is$not null";
				return;
			}
			if ($not) {
				$add = " AND $k is not null";
			} else {
				$add = " OR $k is null)";
				$k = "($k";
			}
		}
		my $w = '?,' x ($#$v+1);
		chop($w);
		$where .= " AND $k$not in ($w)$add";
		push(@ary, @$v);
	};

	foreach(keys(%{ $h->{match} })) {
		&$match($_, $h->{match}->{$_});
	}
	foreach(keys(%{ $h->{not_match} })) {
		&$match($_, $h->{not_match}->{$_}, ' not');
	}
	foreach(keys(%{ $h->{min} })) {
		my $k = $_;
		$k =~ s/[^\w\.]//g;
		$where .= " AND $k>=?";
		push(@ary, $h->{min}->{$_});
	}
	foreach(keys(%{ $h->{max} })) {
		my $k = $_;
		$k =~ s/[^\w\.]//g;
		$where .= " AND $k<=?";
		push(@ary, $h->{max}->{$_});
	}
	foreach(keys(%{ $h->{gt} })) {
		my $k = $_;
		$k =~ s/[^\w\.]//g;
		$where .= " AND $k>?";
		push(@ary, $h->{gt}->{$_});
	}
	foreach(keys(%{ $h->{lt} })) {
		my $k = $_;
		$k =~ s/[^\w\.]//g;
		$where .= " AND $k<?";
		push(@ary, $h->{lt}->{$_});
	}
	my $flags = $h->{flag} || $h->{boolean};
	foreach(keys(%$flags)) {
		my $k = $_;
		$k =~ s/[^\w\.]//g;
		$where .= " AND " . ($flags->{$_} ? '' : 'not ') . $k;
	}
	foreach(@{ $h->{is_null} }) {
		$_ =~ s/[^\w\.]//g;
		$where .= " AND $_ is null";
	}
	foreach(@{ $h->{not_null} }) {
		$_ =~ s/[^\w\.]//g;
		$where .= " AND $_ is not null";
	}
	if ($h->{search_cols} || $h->{search_match} || $h->{search_equal}) {
		my $search = sub {
			my $w   = shift;
			my $not = shift || '';
			my @x;
			foreach (@{ $h->{search_equal} || [] }) {
				$_ =~ s/[^\w\.]//g;
				push(@x, "$_\::text=?");
				push(@ary, $w);
			}
			$w =~ s/([\\%_])/\\$1/rg;
			foreach (@{ $h->{search_match} || [] }) {
				$_ =~ s/[^\w\.]//g;
				push(@x, "$_\::text ILIKE ?");
				push(@ary, $w);
			}
			$w = "%$w%";
			foreach (@{ $h->{search_cols}  || [] }) {
				$_ =~ s/[^\w\.]//g;
				push(@x, "$_\::text ILIKE ?");
				push(@ary, $w);
			}
			return @x ? " AND (" . join(' OR ', @x) . ")$not " : '';
		};
		foreach(@{ $h->{search_words} || [] }) {
			$where .= &$search($_);
		}
		foreach(@{ $h->{search_not} || [] }) {
			$where .= &$search($_, ' is not true');
		}
	}

	if ($h->{RDB_where} ne '') {		# RDBMS where
		my $add = $h->{RDB_where};
		$add =~ s/[\\;\x80-\xff]//g;
		my $c = ($add =~ tr/'/'/);	# count "'"
		if ($c & 1)	{		# if odd then all delete
			$add =~ s/'//g;
		}
		$where .= " AND ($add)";
		if ($h->{RDB_values}) {
			push(@ary, @{ $h->{RDB_values} });
		}
	}

	if ($where) { $where = ' WHERE' . substr($where, 4); }

	return ($where, \@ary);
}

#-------------------------------------------------------------------------------
# generate ORDER BY
#-------------------------------------------------------------------------------
sub generate_order_by {
	my ($self, $h) = @_;
	my $sort = ref($h->{sort}) ? $h->{sort} : [ $h->{sort} ];

	my $sql='';
	if ($h->{RDB_order} ne '') {
		$sql .= ' ' . $h->{RDB_order} . ',';
	}
	foreach(@$sort) {
		my $col = $_;
		my $rev = ord($col) == 0x2d;	# '-colname'
		$col =~ s/[^\w\.]//g;
		if ($col eq '') { next; }
		$sql .= ' ' . $col . ($rev ? ' DESC' : '') . ' NULLS LAST,';
	}
	chop($sql);
	return $sql ? ' ORDER BY' . $sql : '';
}

#-------------------------------------------------------------------------------
# generate LEFT JOIN
#-------------------------------------------------------------------------------
sub generate_left_join {
	my ($self, $h) = @_;

	my $lj = $h->{ljoin};
	if (!$lj) { return ('', ''); }
	my $ary = ref($lj) eq 'ARRAY' ? $lj : [ $lj ];

	my $sql='';
	my @cols;
	foreach(@$ary) {
		my ($tbl,$as) = $self->parse_table_name($_->{table});
		my $l   = $_->{left}  =~ s/[^\w\.]//rg;
		my $r   = $_->{right} =~ s/[^\w\.]//rg;
		if (!$tbl) { next; }

		my $c = $_->{cols};
		if ($c) {
			$as ||= $tbl;
			push(@cols, map { $_ =~ /^(\w+) +(\w+)$/ ? "$as.$1 as $2" : "$as." . ($_ =~ s/\W//rg) } @$c);
		}
		if ($as ne '') { $as = " as $as"; }
		my $on = ($l && $r) ? "$l=$r" : 'false';

		$sql .= " LEFT JOIN $tbl ON $on";
	}
	my $cols = @cols ? join(', ', '', @cols) : '';
	return ($sql, $cols);
}

1;
