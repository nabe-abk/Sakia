use strict;
#-------------------------------------------------------------------------------
# Manipulate JPEG Exif
#							(C)2015-2023 nabe@abk
#-------------------------------------------------------------------------------
package Sakia::Util::JpegExif;
our $VERSION = '1.01';
#-------------------------------------------------------------------------------
use Fcntl;
################################################################################
# constructor
################################################################################
sub new {
	my $class = shift;
	return bless({
		ROBJ		=> shift,
		check_size 	=> 4096,
		exif_max_size	=> 65536
	}, $class);
}

################################################################################
# main
################################################################################
#-------------------------------------------------------------------------------
# check exif
#-------------------------------------------------------------------------------
sub check {
	my $self = shift;
	my $file = shift;

	my $fh;
	my $head;
	sysopen($fh, $file, O_RDONLY);
	binmode($fh);
	sysread($fh, $head, $self->{check_size});
	close($fh);

	my $exif = ($head =~ /\xFF\xE1..Exif\x00\x00/s);
	return $exif;
}

#-------------------------------------------------------------------------------
# get exif info (easy implementation)
#-------------------------------------------------------------------------------
my @ifd_types = (
	{},
	{len => 1, sign => 0 }, 	# 01
	{len => 1 }, 			# 02
	{len => 2, sign => 0 }, 	# 03
	{len => 4, sign => 0 }, 	# 04
	{len => 8 },		 	# 05
	{len => 1, sign => 0x80 },	# 06
	{len => 1 },			# 07
	{len => 2, sign =>0x8000 },	# 08
	{len => 4, sign =>0x80000000 },	# 09
	{len => 8 },			# 0a
	{len => 4 }, 			# 0b
	{len => 8 } 			# 0c
);

sub get_info {
	my $self = shift;
	my $file = shift;

	my $fh;
	my $data;
	sysopen($fh, $file, O_RDONLY);
	binmode($fh);
	my $len = sysread($fh, $data, $self->{exif_max_size});
	close($fh);

	if ($data !~ /^(.*?)\xFF\xE1(.)(.)Exif\x00\x00/s) { return ; }
	my $p    = length($1)+10;
	my $size = (ord($2)<<8) + ord($3);

	# tiff header
	my $base = $p;
	my $tiff_h = substr($data, $p, 2);
	my $tiffR = sub {
		return &tunpack($tiff_h, substr($_[0], $_[1], $_[2]));
	};
	my $tiff_c = &$tiffR($data, $p+2, 2);
	if ($tiff_h ne 'MM' && $tiff_h ne 'II' or $tiff_c != 0x2a) {
		return ;
	}
	$p += &$tiffR($data, $p+4, 4);

	my %exif;
	my $exif_ifd;
	while($p < $len) {
		# Tags
		my $num = &$tiffR($data, $p, 2);
		$p+=2;
		for(my $i=0; $i<$num; $i++) {
			my $tag   = &$tiffR($data, $p  , 2);
			my $type  = &$tiffR($data, $p+2, 2);
			my $size  = &$tiffR($data, $p+4, 4);
			my $offset= &$tiffR($data, $p+8, 4);
			my $val   =  substr($data, $p+8, 4);
			$p+=12;

			if ($tag == 34665) {	# Exif IFD Found
				$exif_ifd = $base + $offset;
				next;
			}
			my $tinfo= $ifd_types[ $type ];
			my $unit = $tinfo->{len};
			my $bytes= $size*$unit;
			if ($bytes <= 4) {
				$val = substr($val, 0, $bytes);
			} else {
				$val = substr($data, $base + $offset, $size*$unit);
			}
			if (exists($tinfo->{sign})) {	# int
				$val = &tunpack($tiff_h, $val);
				if ($tinfo->{sign} && $val >= $tinfo->{sign}) {
					$val = $val - $tinfo->{sign} - $tinfo->{sign};
				}
			} elsif ($type == 2) {		# string
				if (substr($val,-1) eq "\x00") { chop($val); }
			} elsif ($type == 5 || $type == 0x0A) {	# fraction
				my $n1 = &$tiffR($val, 0, 4);
				my $n2 = &$tiffR($val, 4, 4);
				if ($type == 0x0A) {
					$n1 = ($n1<0x80000000) ? $n1 : ($n1 - 0x100000000);
					$n2 = ($n1<0x80000000) ? $n2 : ($n2 - 0x100000000);
				}
				while ($n1 =~ /^10+$/ && $n2 =~ /0$/) {
					$n1 /= 10;
					$n2 /= 10;
				}
				$val = "$n1/$n2";
				if ($n2 =~ /^10+$/) { $val = $n1/$n2; }
				
			} elsif ($type == 0x0B) {	# float
				eval { $val = unpack('F', $val); }
			} elsif ($type == 0x0C) {	# double
				eval { $val = unpack('D', $val); }
			}

			if ($tag == 33437) { $val = sprintf("%.1f", $val); }	# F value
			$exif{$tag} = $val;
		}
		if ($exif_ifd) {
			$p = $exif_ifd;
			$exif_ifd = 0;
			next;
		}
		last;
	}
	return \%exif;
}

sub tunpack {
	my $type = shift;
	my @ary = split('',shift);
	if ($type eq 'II') {
		@ary = reverse(@ary);
	}
	my $v=0;
	foreach(@ary) {
		$v = ($v<<8) + ord($_);
	}
	return $v;
}

#-------------------------------------------------------------------------------
# Delete exif
#-------------------------------------------------------------------------------
my %strip_markers = map { $_ => 1 } split('',
  "\xE1\xE2\xE3\xE4\xE5\xE6\xE7\xE8\xE9\xEA\xEB\xEC\xED\xEE\xEF\xFE"
);	# skip: APP1-15 and comment segment(0xFE)

sub strip {
	my $self = shift;
	my $file = shift;
	my $ROBJ = $self->{ROBJ};

	my $fh;
	my $data;
	sysopen($fh, $file, O_RDWR) || return -999;
	binmode($fh);
	$ROBJ->write_lock($fh);
	sysread($fh, $data, -s $fh);

	my $r=0;
	my @segs;
	my $require_strip;
	while(1) {
		if (substr($data, 0, 2) ne "\xFF\xD8") { $r=-1; last; }
		my $p   = 2;
		my $len = length($data);
		while($p < $len) {
			my %h;
			if (substr($data, $p, 1) ne "\xFF") { last; }	# err

			my $marker = substr($data, $p+1, 1);
			if ($strip_markers{$marker}) { $require_strip=1; }

			my %h;
			$h{marker} = $marker;
			$h{offset} = $p;
			$h{size}   = (ord(substr($data, $p+2, 1))<<8) + ord(substr($data, $p+3, 1)) +2;
			$p += $h{size};
			push(@segs, \%h);

			if ($marker ne "\xDA") { next; }	# \xDA: SOS marker (start of DATA)
			$h{size} = $h{size} + ($len -$p) +2;
			$p = $len-2;
			if (substr($data, $p, 2) eq "\xFF\xD9") { $p += 2; }	# EOI segment
			last;
		}
		if ($p != $len) { $r=-2; last; }
		if (!$require_strip) { last; }

		seek($fh, 2, 0);
		foreach(@segs) {
			if ($strip_markers{ $_->{marker} }) { next; }
			syswrite($fh, $data, $_->{size}, $_->{offset});
		}
		truncate($fh, sysseek($fh, 0, 1));	# Do not work "tell($fh)"
		last;
	}
	close($fh);
	return $r;
}

1;
