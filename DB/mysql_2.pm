use strict;
package Sakia::DB::mysql;
################################################################################
# ■データの挿入・削除
################################################################################
#-------------------------------------------------------------------------------
# ●データの挿入
#-------------------------------------------------------------------------------
sub insert {
	my ($self, $table, $h) = @_;
	my $dbh  = $self->{dbh};
	my $ROBJ = $self->{ROBJ};
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

	# pkey保存 insert
	my $pkey = int($h->{pkey});
	if (exists $h->{pkey} && $pkey<1) {
		$self->error("pkey=$pkey error on $table");
		return 0;
	}

	# SQL 発行
	my $sql = "INSERT INTO $table($cols) VALUES($vals)";
	my $sth = $dbh->prepare($sql);
	$self->debug($sql, \@ary);	## safe
	$sth && $sth->execute(@ary);
	if (!$sth || $dbh->err) {
		$self->error($sql);
		$self->error($dbh->errstr);
		return 0;
	}
	if ($sth->rows != 1) { return 0; }

	# 成功した場合 pkey を返す
	if ($pkey) { return $pkey; }
	return $sth->{mysql_insertid};	# auto_increment の値
}

#-------------------------------------------------------------------------------
# ●pkeyの生成
#-------------------------------------------------------------------------------
sub generate_pkey {
	my ($self, $table) = @_;
	my $dbh  = $self->{dbh};
	my $ROBJ = $self->{ROBJ};
	$table =~ s/\W//g;

	# not nullカラムを探し、適当なデフォルト値を生成する
	my $sql = "show columns FROM $table WHERE `Null`='NO' AND `Key`!='PRI' AND `Default` is null";
	my $sth = $dbh->prepare($sql);
	$self->debug($sql);	## safe
	$sth && $sth->execute();
	if (!$sth || $dbh->err) {
		$self->error($sql);
		$self->error($dbh->errstr);
		return 0;
	}
	my @cols;
	my @vals;
	{
		my $ary = $sth->fetchall_arrayref({});
		foreach(@$ary) {
			push(@cols, "`$_->{Field}`");
			my $type = $_->{Type};
			if ($type =~ /int|float|boolean/i) {
				push(@vals, 0);
			} else {
				push(@vals, "''");
			}
		}
	}

	# ダミーデータを挿入し削除する
	my $sql = "INSERT INTO $table(" . join(',', @cols) . ") VALUES(" . join(',', @vals) . ")";
	my $sth = $dbh->prepare($sql);
	$self->debug($sql);	## safe
	$sth && $sth->execute();
	if (!$sth || $dbh->err) {
		$self->error($sql);
		$self->error($dbh->errstr);
		return 0;
	}

	# pkey保存
	my $pkey=$sth->{mysql_insertid};

	# 挿入データの削除
	$sql = "DELETE FROM $table WHERE pkey=$pkey";
	$sth = $dbh->prepare($sql);
	$self->debug($sql);	## safe
	$sth && $sth->execute();

	return $pkey;	# pkey
}

#-------------------------------------------------------------------------------
# ●データの更新
#-------------------------------------------------------------------------------
sub update_match {
	my $self = shift;
	my $table= shift;
	my $h    = shift;
	my $dbh  = $self->{dbh};
	my $ROBJ = $self->{ROBJ};
	$table =~ s/\W//g;

	# 更新データSQL
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

	# 条件部SQL
	my $where = $self->generate_where(\@ary, @_);

	# SQL 発行
	my $sql = "UPDATE $table SET $cols$where";
	my $sth = $dbh->prepare($sql);
	$self->debug($sql, \@ary);	## safe
	$sth && $sth->execute( @ary );
	if (!$sth || $dbh->err) {
		$self->error($sql);
		$self->error($dbh->errstr);
		return 0;
	}
	return $sth->rows;	# 更新した行数
}

#-------------------------------------------------------------------------------
# ●データの削除
#-------------------------------------------------------------------------------
sub delete_match {
	my $self = shift;
	my $table= shift;
	my $dbh  = $self->{dbh};
	my $ROBJ = $self->{ROBJ};
	$table =~ s/\W//g;

	# 条件部SQL
	my @ary;
	my $where = $self->generate_where(\@ary, @_);

	# SQL 発行
	my $sql = "DELETE FROM $table$where";
	my $sth = $dbh->prepare($sql);
	$self->debug($sql, \@ary);	## safe
	$sth && $sth->execute( @ary );
	if (!$sth || $dbh->err) {
		$self->error($sql);
		$self->error($dbh->errstr);
		return 0;
	}

	return $sth->rows;
}

################################################################################
# ■データの集計
################################################################################
#-------------------------------------------------------------------------------
# ●テーブルの情報を集計
#-------------------------------------------------------------------------------
sub select_by_group {
	my ($self, $table, $h, $w) = @_;
	my $dbh  = $self->{dbh};
	my $ROBJ = $self->{ROBJ};
	$table     =~ s/\W//g;

	my $sum_cols = ref($h->{sum_cols}) ? $h->{sum_cols} : ($h->{sum_cols} eq '' ? [] : [ $h->{sum_cols} ]);
	my $max_cols = ref($h->{max_cols}) ? $h->{max_cols} : ($h->{max_cols} eq '' ? [] : [ $h->{max_cols} ]);
	my $min_cols = ref($h->{min_cols}) ? $h->{min_cols} : ($h->{min_cols} eq '' ? [] : [ $h->{min_cols} ]);

	#-----------------------------------------
	# SQLを実行
	#-----------------------------------------
	my $sel = 'count(pkey) AS _count';
	foreach(@$sum_cols) {
		my $c = $_;
		$c =~ s/\W//g;
		$sel .= ", sum($c) AS ${c}_sum";
	}
	foreach(@$max_cols) {
		my $c = $_;
		$c =~ s/\W//g;
		$sel .= ", max($c) AS ${c}_max";
	}
	foreach(@$min_cols) {
		my $c = $_;
		$c =~ s/\W//g;
		$sel .= ", min($c) AS ${c}_min";
	}

	# group by
	my $group_by;
	my $group_col = $h->{group_by};
	if ($group_col ne '') {
		$group_col =~ s/\W//g;
		$group_by  = " GROUP BY $group_col";
		$sel .= ", $group_col";
	}

	# where処理
	my ($where, $ary) = $self->generate_select_where($h);

	# ソート処理
	my $order_by = $self->generate_order_by($h);

	#-----------------------------------------
	# SQLを発行
	#-----------------------------------------
	my $sql = "SELECT $sel FROM $table$where$group_by$order_by";
	my $sth = $dbh->prepare($sql);
	$self->debug($sql, $ary);	## safe
	$sth && $sth->execute(@$ary);
	if (!$sth || $dbh->err) {
		$self->error($sql);
		$self->error($dbh->errstr);
		return [];
	}
	return $sth->fetchall_arrayref({});
}

################################################################################
# ■トランザクション
################################################################################
# DBによっては、実装されてないかも知れない。
sub begin {
	my $self = shift;
	my $dbh  = $self->{dbh};
	$self->{begin} = 1;
	$self->debug('BEGIN');		## safe
	$dbh->begin_work();
}
sub commit {
	my $self = shift;
	my $dbh  = $self->{dbh};
	if ($self->{begin}<0) {
		return $self->rollback();
	}
	$self->{begin} = 0;
	$self->debug('COMMIT');		## safe
	$dbh->commit();
	return 0;
}
sub rollback {
	my $self = shift;
	my $dbh  = $self->{dbh};
	$self->{begin} = 0;
	$self->debug('ROLLBACK');	## safe
	$dbh->rollback();
	return -1;
}

################################################################################
# ■サブルーチン
################################################################################
#-------------------------------------------------------------------------------
# ●whereの生成
#-------------------------------------------------------------------------------
sub generate_where {
	my $self = shift;
	my $ary  = shift;

	# ハッシュ引数を書き換え
	if ($#_ == 0 && ref($_[0]) eq 'HASH') {
		my $h = shift;
		foreach(sort(keys(%$h))) {
			push(@_, $_);
			push(@_, $h->{$_});
		}
	}

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
		# 値が配列のとき
		if (!@$val) {	# 空の配列
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

#-------------------------------------------------------------------------------
# ●SQLの実行
#-------------------------------------------------------------------------------
sub do_sql {
	my $self = shift;
	my $sql  = shift;
	my $ROBJ = $self->{ROBJ};

	my @ary = @_;

	my $dbh = $self->{dbh};
	$self->debug($sql, \@ary);	## safe
	my $sth = $dbh->prepare($sql);
	$sth && $sth->execute(@ary);
	if (!$sth || $dbh->err) {
		$self->error($sql);
		$self->error($dbh->errstr);
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

#-------------------------------------------------------------------------------
# ●dbhのロード
#-------------------------------------------------------------------------------
sub load_dbh {
	my $self = shift;
	return $self->{dbh};
}

#-------------------------------------------------------------------------------
# ●prepare
#-------------------------------------------------------------------------------
sub prepare {
	my $self = shift;
	my $sql  = shift;
	my $dbh  = $self->{dbh};
	$self->debug($sql);	## safe
	return $dbh->prepare($sql);
}

1;
