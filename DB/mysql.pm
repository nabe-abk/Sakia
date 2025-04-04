use strict;
#-------------------------------------------------------------------------------
# database module for MariaDB/MySQL
#						(C)2006-2025 nabe@abk
#-------------------------------------------------------------------------------
package Sakia::DB::mysql;
use Sakia::AutoLoader;
use Sakia::DB::share;
use DBI ();
#-------------------------------------------------------------------------------
our $VERSION = '1.81';
my %DB_attr = (AutoCommit => 1, RaiseError => 0, PrintError => 0, PrintWarn => 0);
################################################################################
# constructor
################################################################################
sub new {
	my $class = shift;
	my ($ROBJ, $db, $id, $pass, $opt) = @_;
	my $self = bless({
		unique_text_size=> 128,		# max 255
		text_index_size	=> 32,		
		engine		=> '',		# DB engine

		%{ $opt || {}},			# options
		ROBJ	=> $ROBJ,
		__FINISH=> 1,
		DBMS	=> 'MySQL',
		ID	=> "my.$db",
		exists_table_cache => {}
	}, $class);

	# connect
	my $con = $self->{Pool} ? 'connect_cached' : 'connect';
	my $dbh = DBI->$con("DBI:mysql:$db", $id, $pass, \%DB_attr);
	if (!$dbh) { die "Database '$db' Connection faild"; }

	# set charset
	my $code = exists($self->{charset}) ? $self->{charset} : 'utf8mb4';
	if ($code) {
		$code =~ s/[^\w]//g;
		my $sql = "SET NAMES $code";
		$self->trace($sql);
		$dbh->do($sql);
	}

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
	my $sql = "SHOW TABLES LIKE ?";
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
	my ($self, $_table, $h) = @_;
	my $dbh  = $self->{dbh};
	my $ROBJ = $self->{ROBJ};

	#-----------------------------------------
	# parse
	#-----------------------------------------
	my $table = $self->parse_table_name($_table);
	my $ljoin = $self->generate_left_join($h);
	my ($where, $ary) = $self->generate_select_where($h);

	my $group_by='';
	my $gcol = $h->{group_by} =~ s/[^\w\.]//rg;
	if ($gcol ne '') {
		$group_by  = " GROUP BY $gcol";
	}

	#-----------------------------------------
	# select cols
	#-----------------------------------------
	my $cols = $gcol ? $gcol : '*';
	if ($h->{cols}) {
		$cols='';
		my $ary = ref($h->{cols}) ? $h->{cols} : [ $h->{cols} ];
		foreach(@$ary) {
			my $c = $_;
			my ($n, $f);
			if ($c =~ s/^(.*?)\s+(\w+)$//) {		# "col name"
				$c = $1;
				$n = $2;
			}
			if ($c =~ /^(\w+)\s*\(\s*([^\)]*?)\s*\)$/) {	# func(col)
				$f = $1 =~ tr/A-Z/a-z/r;
				$c = $2;
				if ($f !~ /^(?:count|min|max|sum)$/) {
					$self->error('Colmun format error, "%s()" not support: %s', $f, $_);
					return [];
				}
			}
			if ($c !~ /^(?:\w+\.)?(\w+|\*)?$/) {		# func(col)
				$self->error("Column format error: %s", $_);
				return [];
			}
			$cols .= $_ . ($f && !$n ? " ${f}_$1," : ',');
		}
		chop($cols);
	}

	#-----------------------------------------
	# make SQL
	#-----------------------------------------
	my $rows= wantarray ? 'SQL_CALC_FOUND_ROWS ' : '';
	my $sql = "SELECT $rows$cols FROM $table"
		. $ljoin . $where . $group_by
		. $self->generate_order_by($h);

	#-----------------------------------------
	# limit and offset
	#-----------------------------------------
	my $offset = int($h->{offset});
	my $limit;
	if ($h->{limit} ne '') { $limit = int($h->{limit}); }
	if ($offset > 0) {
		if ($limit eq '') { $limit = 0x7fffffff; }
		$sql .= " LIMIT $offset,$limit";
	} elsif ($limit ne '') { $sql .= ' LIMIT ' . $limit;  }

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
		$sql = 'SELECT FOUND_ROWS()';
		$sth = $dbh->prepare($sql);
		$self->trace($sql);
		$sth && $sth->execute();
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
		return "$1 $2";
	}
	return $table =~ s/\W//rg;
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
	foreach(keys(%{ $h->{boolean} })) {
		my $k = $_;
		$k =~ s/[^\w\.]//g;
		$where .= " AND " . ($h->{boolean}->{$_} ? '' : 'not ') . $k;
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
				push(@x, "$_=?");
				push(@ary, $w);
			}
			$w =~ s/([\\%_])/\\$1/rg;
			$w =~ tr/A-Z/a-z/;
			foreach (@{ $h->{search_match} || [] }) {
				$_ =~ s/[^\w\.]//g;
				push(@x, "lower($_) LIKE ?");
				push(@ary, $w);
			}
			$w = "%$w%";
			foreach (@{ $h->{search_cols}  || [] }) {
				$_ =~ s/[^\w\.]//g;
				push(@x, "lower($_) LIKE ?");
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
		$sql .= " $col IS NULL, $col " . ($rev ? 'DESC,' : ',');
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
	if (!$lj) { return ''; }
	my $ary = ref($lj) eq 'ARRAY' ? $lj : [ $lj ];

	my $sql='';
	foreach(@$ary) {
		my $tbl = $self->parse_table_name($_->{table});
		my $l = $_->{left}  =~ s/[^\w\.]//rg;
		my $r = $_->{right} =~ s/[^\w\.]//rg;
		if (!$tbl) { next; }

		my $on = ($l && $r) ? "$l=$r" : 'false';
		$sql .= " LEFT JOIN $tbl ON $on";
	}
	return $sql;
}

1;
