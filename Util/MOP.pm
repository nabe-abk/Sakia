use strict;
#-------------------------------------------------------------------------------
# A anonymouse class module
#					(C)2013-2017 nabe@abk
#-------------------------------------------------------------------------------
package Sakia::Util::MOP;
our $VERSION = '1.01';
our $AUTOLOAD;
#-------------------------------------------------------------------------------
# constructor
#-------------------------------------------------------------------------------
sub new {
	my $class = shift;
	return bless({ROBJ => shift, _FILENAME => shift, __FINISH => 1}, $class);
}
sub FINISH {
	my $self = shift;
	my $func = $self->{'FINISH'};
	if (ref($func) eq 'CODE') { return &$func($self,@_); }
}

#-------------------------------------------------------------------------------
# call method
#-------------------------------------------------------------------------------
sub AUTOLOAD {
	if ($AUTOLOAD eq '') { return; }
	my $self = shift;
	my $name = substr($AUTOLOAD, rindex($AUTOLOAD, '::')+2);
	my $func = $self->{ $name };
	if (ref($func) eq 'CODE') { return &$func($self,@_); }

	# error
	my ($pack, $file, $line) = caller;
	if ($self->{_FILENAME}) { $file = $self->{_FILENAME}; }
	die "[MOP] Can't find method '$name' at $file line $line";
}

1;
