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

		# parse line
		my ($name, $type, $opt) = split(/\s+/, $x, 3);
		my $c = { name => $name, type => $type };
		$cref{$name} = $c;

		# escape string
		my @str;
		$opt =~ s!'((?:[^']|'')*)'!push(@str, $1 =~ s/''/'/rg), "#$#str"!eg;

		my @opt = split(/\s+/, $opt);
		while(@opt) {
			my $o  = shift(@opt) =~ tr/A-Z/a-z/r;;
			my $o1 = $opt[0]     =~ tr/A-Z/a-z/r;
			if ($o eq 'not' && $o1 eq 'null') {
				shift(@opt);
				$c->{not_null} = 1;
				next;
			}
			if ($o eq 'unique') {
				$c->{unique} = 1;
				next;
			}
			if ($name eq 'pkey' && $o eq 'primary' && $o1 eq 'key') {
				shift(@opt);
				next;
			}
			if ($o eq 'default') {
				my $v  = shift(@opt);
				my $vn = $v + 0;
				
				if ($v =~ /^#(\d+)$/) {		# default 'value'
					$v = $str[$1];
				} elsif ($vn != 0 && $v eq $vn) {
					$v = $vn;
				} elsif ($v =~ /^\w+$/) {
					$c->{default_sql} = $v;
					$v = '';
				} else {
					$self->error("Unknown default value in column '%s' in table '%s': %s", $name, $table, $v);
					$err=1;
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
