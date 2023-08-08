use strict;
use Time::HiRes();
#-------------------------------------------------------------------------------
# Timer
#						(C)2023 nabe@abk
#-------------------------------------------------------------------------------
package Sakia::TimerWrapper;
our $VERSION = '1.00';
################################################################################
# constructor
################################################################################
sub new {
	my $class = shift;
	my $ROBJ  = shift;
	my $obj   = ref($_[0]) ? shift : $ROBJ->loadpm(@_);
	$obj->{__timer} = 1;
	bless([ $obj, 0 ], $class);
}

# Referencing "$obj" in dereferences
use overload (
	"%{}"	 => sub { $_[0]->[0]; },
	fallback => 1
);

################################################################################
# main
################################################################################
our $AUTOLOAD;

sub AUTOLOAD {
	my $x    = rindex($AUTOLOAD, '::');
	my $func = substr($AUTOLOAD, $x+2);

	my $self = shift;
	my $obj  = $self->[0];
	my $st   = Time::HiRes::time();
	my @r;
	wantarray ? (@r=$obj->$func(@_)) : ($r[0]=$obj->$func(@_));

	$self->[1] += Time::HiRes::time() - $st;

	return wantarray ? @r : $r[0];
}

sub __timer {
	my $self = shift;
	return $self->[1];
}

1;
