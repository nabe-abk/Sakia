use strict;
#-------------------------------------------------------------------------------
package Sakia::DB::share_3;
our $VERSION = $Sakia::DB::share::VERSION;

use Exporter 'import';
our @EXPORT = qw(
	get_options
	create_table_wrapper
);

################################################################################
# optional functions
################################################################################
my @optional_methods = qw(add_column drop_column add_index);

sub get_options {
	my $self=shift;
	my %h;
	foreach(@optional_methods) {
		if ($self->can($_)) { $h{$_}=1; }
	}
	return \%h;
}

################################################################################
# create table wrapper
################################################################################
sub create_table_wrapper {
	my $self = shift;
	my ($table, $lines, $ext) = @_;

	$lines = ref($lines) ? $lines : [ split(/\n/, $lines) ];

	my @cols;
	my %cref;
	my $err;
	foreach my $l (@$lines) {
		my $x = $l =~ s/^\s+//r;
		$x =~ s/^((?:'[^']*'|[^'])*?)\s*#.*$/$1/;
		if ($x =~ /^\s*$/) { next; }

		if ($x =~ /^INDEX(_TDB)?(?:\s+(.*?))?\s*$/) {
			my $tdb = $1 ? '_tdb' : '';
			my $col = $2;
			my @c = split(/\s*,\s*/, $col);
			if (!@c) {
				$self->error("Column name not found in INDEX row in table '%s'.", $table);
				$err=1;
				next;
			}
			if (!$tdb && $#c != 0) {
				$self->error("Multi-column indexes are not supported in table '%s': %s", $table, $col);
				$err=1;
				next;
			}
			foreach(@c) {
				my $h = $cref{$_};
				if (!$h) {
					$self->error("Illegal index column in table '%s': %s", $table, $_);
					$err=1;
					next;
				}
				$h->{"index$tdb"}=1;
			}
			next;
		}

		# escape string
		my @str;
		$x =~ s!'((?:[^']|'')*)'!push(@str, $1 =~ s/''/'/rg), "#$#str"!eg;
		$x =~ tr/A-Z/a-z/;

		# parse line
		my ($name, $type, @opt) = split(/\s+/, $x);
		if ($name eq 'pkey') { next; }

		my $c = { name => $name, type => $type };
		$cref{$name} = $c;

		while(@opt) {
			my $o = shift(@opt);
			if ($o eq 'not' && $opt[0] eq 'null') {
				shift(@opt);
				$c->{not_null} = 1;
				next;
			}
			if ($o eq 'unique') {
				$c->{unique} = 1;
				next;
			}
			if ($o eq 'default') {
				my $v = shift(@opt);
				if ($v =~ /^#(\d+)$/) {		# default 'Value'
					$v = $str[$1];
				} elsif ($v =~ /\d/) {
					$v = $v + 0;
				} else {
					$v = '';
				}
				$c->{default} = $v;
				next;
			}
			if ($o =~ /^ref\((\w+\.\w+)\)$/) {
				$c->{ref} = $1;
				next;
			}

			$self->error("Unknown option in column '%s' in table '%s': %s", $name, $table, $o);
			$err=1;
		}
		push(@cols, $c);
	}
	if ($err) { return 999; }

	# ext columns
	push(@cols, @{$ext || []});

	return $self->create_table($table, \@cols);
}

1;
