use strict;
#-------------------------------------------------------------------------------
# Buffered Read
#						(C)2006-2023 nabe@abk
#-------------------------------------------------------------------------------
package Sakia::Base::BufferedRead;
our $VERSION = '1.20';
################################################################################
# constructor
################################################################################
sub new {
	my $self = bless({}, shift);
	$self->{ROBJ} = shift;

	$self->{fh}       = shift || *STDIN;	# read from
	$self->{read_max} = int(shift);
	$self->{buf_size} = int(shift) || 256*1024;

	$self->{buf}        = '';
	$self->{buf_offset} = 0;
	$self->{read_bytes} = 0;
	$self->{out_bytes}  = 0;
	$self->{end_stream} = 0;	# end of input stream
	$self->{end}        = 0;	# end of read data

	return $self;
}

################################################################################
# main
################################################################################
sub read {
	my $self  = shift;
	my $bound = shift;
	my $out   = '';
	$self->read_to_file(\$out, $bound, @_);
	return $out;
}
sub read_to_var {
	return &read_to_file(@_);
}
sub read_to_file {
	my $self  = shift;
	my $out   = shift;
	my $bound = shift;
	if (ref($out) ne 'SCALAR' && fileno($out) == -1) { return; }

	my $read_bytes = $self->{read_bytes};
	my $read_max   = $self->{read_max};
	my $rbuf       = \($self->{buf});
	my $offset     = $self->{buf_offset};
	my $buf_size   = $self->{buf_size};

	my $bound_size = length($bound);
	if ($buf_size <= $bound_size) { die "Too small buffer size"; }

	my $start_out_bytes = $self->{out_bytes};

	while (1) {
		my $find = index($$rbuf, $bound, $offset);
		if ($find >= 0) {
			my $size = $find - $offset;
			$self->output($out, $rbuf, $offset, $size);
			$offset += $size + $bound_size;
			last;
		}

		#-------------------------------------------
		# End of data
		#-------------------------------------------
		if ($self->{end_stream}) {
			my $size = length($$rbuf) - $offset;
			$self->output($out, $rbuf, $offset, $size);

			$$rbuf='';
			$offset=0;
			$self->{end}=1;
			last;
		}

		#-------------------------------------------
		# Append stream reads
		#-------------------------------------------
		if ($$rbuf ne '') {
			my $buf_len = length($$rbuf);
			my $remain  = $buf_len - $offset;
			if ($bound_size < $remain) {
				my $out_size = $remain - $bound_size;
				$self->output($out, $rbuf, $offset, $out_size);
				$remain = $bound_size;
			}
			$$rbuf = substr($$rbuf, $buf_len - $remain);	# copy to buf's top, DO NOT REWRITE "-$remain"(-0 is not working)
			$offset = 0;
		}

		my $buf_len  = length($$rbuf);
		my $try_size = $buf_size - $buf_len;
		if ($read_max && ($read_max < $read_bytes + $try_size)) {
			$try_size = $read_max - $read_bytes;
			$self->{end_stream} = 1;
		}

		my $bytes = read($self->{fh}, $$rbuf, $try_size, $buf_len);
		if ($bytes < $try_size) {
			$self->{end_stream} = 1;
		}
		$read_bytes += $bytes;
	}

	$self->{buf_offset} = $offset;
	$self->{read_bytes} = $read_bytes;
	return $self->{out_bytes} - $start_out_bytes;
}

sub output {
	my ($self, $out, $rbuf, $offset, $size) = @_;
	if ($size < 1) { return 0; }

	if (ref($out) eq 'SCALAR') {
		$$out .= substr($$rbuf, $offset, $size);
	} else {
		syswrite($out, $$rbuf, $size, $offset);
	}
	$self->{out_bytes} += $size;
	return $size;
}

1;
