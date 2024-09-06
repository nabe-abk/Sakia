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
	my ($table, $ci, $ext) = @_;
	my %cols;
	foreach(@{$ci->{flag}})    { $cols{$_} = {name => $_, type => 'flag'}; }	# boolean
	foreach(@{$ci->{text}})    { $cols{$_} = {name => $_, type => 'text'}; }	# text
	foreach(@{$ci->{ltext}})   { $cols{$_} = {name => $_, type => 'ltext'};}	# large text
	foreach(@{$ci->{int}})     { $cols{$_} = {name => $_, type => 'int'};  }	# int
	foreach(@{$ci->{float}})   { $cols{$_} = {name => $_, type => 'float'};}	# float
	foreach(@{$ci->{idx}})     { $cols{$_}->{index}    = 1; }			# index
	foreach(@{$ci->{idx_tdb}}) { $cols{$_}->{index_tdb}= 1; }			# index for Text-DB
	foreach(@{$ci->{unique}})  { $cols{$_}->{unique}   = 1; }			# unique
	foreach(@{$ci->{notnull}}) { $cols{$_}->{not_null} = 1; }			# NOT NULL
	while(my ($k, $v) = each(%{ $ci->{default} })) {		# default
		$cols{$k}->{default}  = $v;
	}
	while(my ($k, $v) = each(%{ $ci->{ref} })) {			# foreign key
		$cols{$k}->{ref} = $v;
	}
	my @cols;
	while(my ($k,$v) = each(%cols)) { push(@cols, $v); }
	foreach (@{$ext || []}) {
		push(@cols, $_);
	}

	return $self->create_table($table, \@cols);
}

1;
