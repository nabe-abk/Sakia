use strict;
#-------------------------------------------------------------------------------
# common routine for database module
#							(C)2020-2024 nabe@abk
#-------------------------------------------------------------------------------
package Sakia::DB::share;
our $VERSION = '1.20';

use Exporter 'import';
our @EXPORT = qw(
	select_match_pkey1 select_match_limit1 select_match
	select_where_pkey1 select_where_limit1 select_where
	set_trace trace warning error
);

################################################################################
# Easy select functions
################################################################################
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
		if (ord($col) == 0x2a) { $h{substr($col,1)}=$val; next; }		# *keyword
		if (ord($col) == 0x2d) { $h{not_match}->{substr($col,1)}=$val; next; }	# -colname
		# default
		$h{match}->{$col}=$val;
	}
	return $self->select($table, \%h);
}

#-------------------------------------------------------------------------------
# for RDB
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
# Error and Trace
################################################################################
sub set_trace {
	my ($self, $flag) = @_;
	my $r = $self->{TRACE};
	$self->{TRACE} = defined $flag ? $flag : 1;
	return $r;
}
sub trace {
	my $self = shift;
	if (!$self->{TRACE}) { return; }

	my $sql  = shift;
	my @ary  = ref($_[0]) ? @{shift()} : @_;
	my $ROBJ = $self->{ROBJ};

	$sql =~ s/\?/@ary ? ($ary[0] =~ m|^\d+$| ? shift(@ary) : "'" . shift(@ary) . "'") : '?'/eg;
	$sql =~ s/\t/    /g;
	if ($self->{trace_hook}) { return &{$self->{trace_hook}}($sql); }

	$ROBJ->_debug('['.$self->{DBMS}.'] '.$sql, 1);	## safe
}
sub error {
	my $self = shift;
	my $err  = shift;
	my $ROBJ = $self->{ROBJ};
	if ($self->{begin}) {
		$self->{begin}=-1;	# error
	}
	if ($self->{error_hook}) { return &{$self->{error_hook}}($err, @_); }

	my $func = $self->{ignore_error} ? 'warning' : 'error';
	$ROBJ->$func('['.$self->{DBMS}.'] '.$err, @_);
}

1;
