use strict;
#-------------------------------------------------------------------------------
# データベースモジュール、共通ルーチン
#							(C)2020-2022 nabe@abk
#-------------------------------------------------------------------------------
package Sakia::DB::share;
our $VERSION = '1.11';

use Exporter 'import';
our @EXPORT = qw(
	select_match_pkey1 select_match_limit1 select_match
	select_where_pkey1 select_where_limit1 select_where
	set_debug debug warning error
);

################################################################################
# ■selectの拡張
################################################################################
#-------------------------------------------------------------------------------
# ●データの取得
#-------------------------------------------------------------------------------
sub select_match_pkey1 {
	my $h = &select_match(@_, '*limit', 1, '*cols', 'pkey')->[0];
	return $h && $h->{pkey};
}
sub select_match_limit1 {
	return &select_match(@_, '*limit', 1)->[0];
}
sub select_match {
	my $self  = shift;
	my $table = shift;
	my %h;
	while(@_) {
		my $col = shift;
		my $val = shift;
		if ($col eq '*limit') { $h{limit}=$val; next; }
		if ($col eq '*cols' ) { $h{cols} =$val; next; }
		if ($col eq '*sort' ) { $h{sort} =$val; next; }
		if ($col eq '*no_error') { $h{no_error}=$val; next; }
		if (ord($col) == 0x2d) {	# == '-'
			$h{not_match}->{substr($col,1)}=$val;
			next;
		}
		# default
		$h{match}->{$col}=$val;
	}
	return $self->select($table, \%h);
}

#-------------------------------------------------------------------------------
# ●for RDB
#-------------------------------------------------------------------------------
sub select_where_pkey1 {
	my $self  = shift;
	my $table = shift;
	my $where = shift;
	my $h = $self->select($table, { RDB_where=>$where, RDB_values=>\@_, limit => 1, cols => 'pkey' })->[0];
	return $h && $h->{pkey};
}
sub select_where_limit1 {
	my $self  = shift;
	my $table = shift;
	my $where = shift;
	return $self->select($table, { RDB_where=>$where, RDB_values=>\@_, limit => 1 })->[0];
}
sub select_where {
	my $self  = shift;
	my $table = shift;
	my $where = shift;
	return $self->select($table, { RDB_where=>$where, RDB_values=>\@_ });
}

################################################################################
# ■エラー処理
################################################################################
#-------------------------------------------------------------------------------
# ●デバッグ処理
#-------------------------------------------------------------------------------
sub set_debug {
	my ($self, $flag) = @_;
	my $r = $self->{DEBUG};
	$self->{DEBUG} = defined $flag ? $flag : 1;
	return $r;
}
sub debug {
	my $self = shift;
	if (!$self->{DEBUG}) { return; }

	my $sql  = shift;
	my @ary  = @{ shift || [] };
	my $ROBJ = $self->{ROBJ};

	$sql =~ s/\?/@ary ? ($ary[0] =~ m|^\d+$| ? shift(@ary) : "'" . shift(@ary) . "'") : '?'/eg;
	$ROBJ->_debug('['.$self->{DBMS}.'] '.$sql, 1);	## safe
}
sub error {
	my $self = shift;
	my $err  = shift;
	my $ROBJ = $self->{ROBJ};
	if ($self->can('error_hook')) {
		$self->error_hook(@_);
	}
	my $func = $self->{no_error} ? 'warning' : 'error';
	$ROBJ->$func('['.$self->{DBMS}.'] '.$err, @_);
}

1;
