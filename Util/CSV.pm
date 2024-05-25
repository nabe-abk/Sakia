use strict;
#-------------------------------------------------------------------------------
# CSV parser
#							(C)2022 nabe@abk
#-------------------------------------------------------------------------------
package Sakia::Util::CSV;
our $VERSION = '1.10';
################################################################################
# constructor
################################################################################
sub new {
	my $class = shift;
	return bless({ROBJ => shift, __CACHE_PM => 1}, $class);
}

#-------------------------------------------------------------------------------
# parse
#-------------------------------------------------------------------------------
sub parse {
	my $self = ref($_[0]) eq __PACKAGE__ && shift;
	my @ary  = split(/\r?\n/, shift);
	my $func = shift;			# colum name replace function
	my $head = &parse_line(shift(@ary));

	if ($func) {	# colum name replace
		foreach(@$head) {
			$_ = &$func($_);
		}
	}

	my @lines;
	foreach(@ary) {
		if ($_ =~ /^\s*$/) { next; }
		my $x = &parse_line($_);
		my %h;
		foreach(@$head) {
			$h{$_} = shift(@$x);
		}
		push(@lines, \%h);
	}
	return \@lines;
}

sub parse_line {
	my $line = shift;

	my @ary;
	$line =~ s!(?:^|,)(?:"((?|""|[^"])*)"|([^,\"]+|))!
		my $x = $1 ne '' ? $1 =~ s/""/\"/gr : $2;
		$x =~ tr/\x00/"/;
		push(@ary, $x);
	!eg;
	return \@ary;
}

1;
