use strict;
#-------------------------------------------------------------------------------
# SMTP module
#						(C)2006-2026 nabe / nabe@abk
#-------------------------------------------------------------------------------
# Support IPv4 only.
# Do not send large file.
#
package Sakia::Net::SMTP;
our $VERSION = '1.52';
#-------------------------------------------------------------------------------
use Socket;
use Fcntl;
################################################################################
# constructor
################################################################################
my %Auth;
#-------------------------------------------------------------------------------
sub new {
	my $self = bless({}, shift);
	my $ROBJ = $self->{ROBJ} = shift;

	$self->{code}    = $ROBJ->{SystemCode} || 'utf-8';
	$self->{mailer} = "Sakia-Net-Mail Version $VERSION";

	$self->{DEBUG}   = 0;
	$self->{TIMEOUT} = 5;

	if (!%Auth) {
		$Auth{PLAIN} = \&auth_plain;
		$Auth{LOGIN} = \&auth_login;
		eval {
			require Digest::HMAC_MD5;
			$Auth{'CRAM-MD5'} = \&auth_cram_md5;
		};
	}
	return $self;
}

################################################################################
# main routine
################################################################################
#-------------------------------------------------------------------------------
# send mail
#-------------------------------------------------------------------------------
# smtp_auth parameter: auth_name / auth_pass
# 
sub send_mail {
	my $self = shift;
	my $h    = shift;
	my $attaches = ref($_[0]) eq 'ARRAY' ? shift : ($_[0] ? \@_ : undef);
	my $ROBJ = $self->{ROBJ};

	my $to    = $self->check_mail_addresses($h->{to});
	my $cc    = $self->check_mail_addresses($h->{cc});
	my $bcc   = $self->check_mail_addresses($h->{bcc});
	my $from  = $self->check_mail_address($h->{from}) || ($h->{from} =~ /^[-\w\.]+$/ ? $h->{from} : undef);
	my $repto = $self->check_mail_address($h->{reply_to});
	my $retph = $self->check_mail_address($h->{return_path});

	## if (!$to) { $ROBJ->msg('"To" is invalid'); return 1; }

	#-----------------------------------------------------------------------
	# message body
	#-----------------------------------------------------------------------
	my $header='';
	{
		my $to_name   = ref($h->{to_name})   ? $h->{to_name}        : [ $h->{to_name} ];
		my $cc_name   = ref($h->{cc_name})   ? $h->{cc_name}        : [ $h->{cc_name} ];
		my $from_name = ref($h->{from_name}) ? $h->{from_name}->[0] : $h->{from_name};

		my $subject = $h->{subject};
		$subject =~ s/[\x00-\x08\x0a-\x1f]//g;		# exclusive TAB

		# To, Cc Headers
		$header .= $self->make_to_header('To', $to, $to_name);
		$header .= $self->make_to_header('Cc', $cc, $cc_name);

		if ($from) {
			if ($from_name ne '') {
				$header .= "From: " . $self->mime_encode($from_name) . " <$from>\r\n";
			} else {
				$header .= "From: $from\r\n";
			}
		}
		if ($repto) { $header .= "Reply-To: $repto\r\n"; }
		if ($retph) { $header .= "Return-Path: $retph\r\n"; }
		$header .= "Subject:" . $self->mime_encode($subject)        . "\r\n";
		$header .= "Date: "   . $self->mail_date_local($ROBJ->{TM}) . "\r\n";
		$header .= "MIME-Version: 1.0\r\n";
		$header .= "X-Mailer: $self->{mailer}\r\n";
	}

	#-----------------------------------------------------------------------
	# message data
	#-----------------------------------------------------------------------
	my @contents;
	if ($h->{text} ne '') {
		push(@contents, {
			plain=> 1,
			type => "text/plain; charset=\"$self->{code}\"",
			data => $h->{text}
		});
	}
	if ($h->{html} ne '') {
		push(@contents, {
			plain=> 1,
			type => "text/html; charset=\"$self->{code}\"",
			data => $h->{html}
		});
	}
	my $multi_type='alternative';
	if ($attaches && @$attaches) {
		$multi_type='mixed';
		push(@contents, @$attaches);
	}

	#-----------------------------------------------------------------------
	# multipart
	#-----------------------------------------------------------------------
	my $boundary;
	if (0<$#contents) {
		foreach(0..100) {
			my $b  = '------==' . substr(rand(),2);
			my $ok = 1;
			foreach(@contents) {
				if (!$_->{plain}) { next; }
				if (0<=index($_->{data}, $b)) {
					$ok=0;
					last;
				}
			}
			if ($ok) {
				$boundary=$b;
				last;
			}
		}
		if (!$boundary) {
			$ROBJ->msg("Failed to generate the boundary.");		## mskip
			return 10;
		}

		$header  .= "Content-Type: multipart/$multi_type; boundary=\"$boundary\"\r\n";
		$boundary = '--' . $boundary;
	}

	#-----------------------------------------------------------------------
	# mail server
	#-----------------------------------------------------------------------
	my $host = $h->{host};
	my $port = $h->{port};
	if ($host =~ /^(.*):(\d+)$/) {
		$host = $1;
		$port = $port || $2;
	}
	$host ||= '127.0.0.1';
	$port ||= 25;

	#-----------------------------------------------------------------------
	# original SMTP
	#-----------------------------------------------------------------------
	my $sock;
	{
		my $ip_bin = inet_aton($host);
		if ($ip_bin eq '') {
			$ROBJ->msg("Can't find host: %s", $host);
			return 20;
		}
		my $addr = pack_sockaddr_in($port, $ip_bin);
		socket($sock, Socket::PF_INET(), Socket::SOCK_STREAM(), 0);
		{
			local $SIG{ALRM} = sub { close($sock); };
			alarm( $self->{TIMEOUT} );
			my $r = connect($sock, $addr);
			alarm(0);
			if (!$r) {
				close($sock);
				$ROBJ->msg("Can't connect host: %s", $host);
				return 21;
			}
		}
		binmode($sock);
	}
	$self->{buf}='';
	eval {
		$self->status_check($sock, 220);
		my $status = $self->send_ehlo($sock, 'localhost.localdomain');
		if ($h->{auth_name} ne '') {
			my $type;
			foreach(split(/ /, $status->{AUTH})) {
				if ($Auth{$_}) {
					$type = $_;
					last;
				}
			}
			if (!$type) {
				my $mechanisms = join(', ', sort(keys(%Auth)));
				die("AUTH mechanisms miss match! client support: $mechanisms, server support: $status->{AUTH}");
			}
			my $str = $self->send_data_check($sock, "AUTH $type", 334);
			eval {
				$str =~ s/^\d+ //;
				&{ $Auth{$type} }($self, $sock, $h->{auth_name}, $h->{auth_pass}, $str);
			};
			if ($@) {
				die("AUTH $type failed: \"$h->{auth_name}\" / \"$h->{auth_pass}\" : $@")
			}
		}
		$from ||= $to;
		$self->send_data_check($sock, "MAIL FROM:$from", 250);
		foreach(@$to,@$cc,@$bcc) {
			$self->send_data_check($sock, "RCPT TO:$_", 250);
		}
		$self->send_data_check($sock, "DATA", 354);

		#---------------------------------------------------------------
		# send message data
		#---------------------------------------------------------------
		local ($SIG{PIPE}) = sub { close($sock); die "PIPE broken"; };

		$self->send_data($sock, $header . ($boundary ? "\r\n" : ''));

		foreach(@contents) {
			my $c_header = '';
			if ($boundary) {
				$c_header .= $boundary . "\r\n";
			}

			if ($_->{plain}) {
				$c_header .= 'Content-Type: ' . $_->{type} . "\r\n";
				$self->send_data($sock, $c_header . "\r\n");

				my $msg = $_->{data};
				$msg =~ s/[\x00-\x08\x0b\x0c\x0e-\x1f]//g;	# exclusive TAB, LF, CR
				$msg =~ s/(^|\n)\./$1../g;
				$msg =~ s/[\r\n]*$/\r\n/;

				$self->send_data($sock, $msg);
				next;
			}

			#-------------------------------------------------------
			# base64
			#-------------------------------------------------------
			my $file  = $_->{file};
			my $type  = $_->{type} =~ s/[\x00-\x1f]//rg;
			my $fname = $_->{filename} =~ s/[\x00-\x1f]//rg;
			if ($fname eq '' && $file ne '') {
				$fname = $file =~ s|^.*[\/\\]||r;
			}
			if ($fname ne '') {
				$fname =~ s/[\x00-\x1f]//rg;
				$fname =~ tr/"/'/;
				$fname =~ s![\\/:\*\?<>\|]!_!g;
			}
			if ($type eq '') {
				my $mime = $ROBJ->loadpm('Util::MIME');
				$type = $mime->get_type($fname);
			}
			if ($type ne '') {
				$c_header .= 'Content-Type: ' . $type . "\r\n";
			}
			$c_header .= 'Content-Disposition: attachment;'
				  . ($fname ne '' ? ' filename="' .  $self->mime_encode($fname) . '"' : '')
				  . "\r\n";
			$c_header .= "Content-Transfer-Encoding: base64\r\n";

			$self->send_data($sock, $c_header . "\r\n");

			if ($file ne '') {
				sysopen(my $fh, $file, O_RDONLY) || die("file open failed: $file");
				while(1) {
					sysread($fh, my $data, 57) || last;
					$self->send_data($sock, $self->base64encode($data) . "\r\n");
				}
				close($fh);
			} else {
				my $len = length($_->{data});
				for(my $p=0; $p<$len; $p+=57) {
					my $data = substr($_->{data}, $p, 57);
					$self->send_data($sock, $self->base64encode($data) . "\r\n");
				}
			}
		}
		if ($boundary) {
			$self->send_data($sock, "\r\n" . $boundary . "--\r\n");
		}

		$self->send_data_check($sock, ".", 250);
		$self->send_quit($sock);
	};

	close($sock);
	if ($@) {
		$ROBJ->msg('SMTP Error: %s', $@);	## mskip
		return 200;
	}
	return 0;
}

sub make_to_header {
	my $self = shift;
	my $type = shift;
	my $adr  = shift || [];
	my $name = shift || [];
	my @ary;
	foreach(0..$#$adr) {
		my $a = $adr ->[$_];
		my $n = $name->[$_];
		if ($a eq '') { next; }
		if ($n eq '') {
			push(@ary, $a);
			next;
		}
		# exists name
		$n =~ s/[\x00-\x1f<>\"]//g;
		$self->mime_encode($n);
		push(@ary, "$n <$a>");
	}
	if (!@ary) { return ''; }
	return "$type: " . join(",\r\n\t", @ary) . "\r\n";
}

#-------------------------------------------------------------------------------
# socket
#-------------------------------------------------------------------------------
sub send_ehlo {
	my $self = shift;
	my $sock = shift;
	my $host = shift;
	$self->send_data_check($sock, "EHLO $host", 250);

	my $in='';
	my $fno = fileno($sock);
	vec($in, $fno, 1) = 1;
	my %h;
	while(1) {
		if ($self->{buf} eq '') {
			select(my $x = $in, undef, undef, 0);
			if (!vec($x, $fno, 1)) { last; }
		}

		my ($code, $y) = $self->recive_line($sock);
		if (!$code) { die("broken response! / EHLO"); }

		$y =~ s/^\d+[ \-]//;
		$y =~ s/[\r\n]//g;
		my ($a,$b) = split(/ /, $y, 2);
		$h{$a} = $b || 1;
	}
	return \%h;
}

sub send_data {
	my $self = shift;
	my $sock = shift;
	my $r = syswrite($sock, $_[0], length($_[0]));
	if ($r != length($_[0])) { die "Send data failed!"; }
	return $r;
}

sub send_data_check {
	my $self = shift;
	my $sock = shift;
	my $data = shift;
	my $code = shift;
	$self->send_cmd($sock, $data);
	return $self->status_check($sock, $code, $data);
}

sub send_cmd {
	my $self = shift;
	my $sock = shift;
	my $data = (shift) . "\r\n";
	$self->{DEBUG} && $self->debug("--> $data");
	syswrite($sock, $data, length($data));
}

sub status_check {
	my $self = shift;
	my $sock = shift;
	my $code = shift;
	my $data = shift;
	my ($c, $line) = $self->recive_line($sock);
	if ($c == $code) { return $line; }

	$self->send_quit($sock);
	die ($data ? "$line / $data" : $line);
}

sub send_quit {
	my $self = shift;
	my $sock = shift;
	my $quit = "QUIT\r\n";
	$self->{DEBUG} && $self->debug("--> $quit");
	syswrite($sock, $quit, length($quit));
}

sub recive_line {
	my $self = shift;
	my $sock = shift;

	my $buf = $self->{buf};
	if ($buf eq '') {
		vec(my $in, fileno($sock), 1) = 1;
		my $r = select($in, undef, undef, $self->{TIMEOUT});
		if ($r <= 0) { return; }
		if (!sysread($sock, $buf, 4096, length($buf))) { return; }
	}
	my $line;
	{
		my $x = index($buf, "\n");
		if ($x < 0) { return; }
		$line = substr($buf, 0, $x);
		$line =~ s/\r//;
		$self->{buf} = substr($buf, $x+1);
	}
	$self->{DEBUG} && $self->debug("<-- $line\n");
	my $code;
	if ($line =~ /^(\d+)/) { $code=$1; }
	return wantarray ? ($code, $line) : $code;
}

#-------------------------------------------------------------------------------
# Authentication
#-------------------------------------------------------------------------------
sub auth_plain {
	my $self = shift;
	my $sock = shift;
	my $user = shift;
	my $pass = shift;

	my $plain = $self->base64encode("\0$user\0$pass");
	$self->send_data_check($sock, $plain, 235);
}

sub auth_login {
	my $self = shift;
	my $sock = shift;
	my $user = shift;
	my $pass = shift;

	$self->send_data_check($sock, $self->base64encode($user), 334);
	$self->send_data_check($sock, $self->base64encode($pass), 235);
}

sub auth_cram_md5 {
	my $self = shift;
	my $sock = shift;
	my $user = shift;
	my $pass = shift;
	my $str  = $self->base64decode(shift);

	my $md5 = Digest::HMAC_MD5::hmac_md5_hex($str,$pass);

	$self->send_data_check($sock, $self->base64encode("$user $md5"), 235);
}

################################################################################
# subroutine
################################################################################
sub check_mail_address {
	my $self = shift;
	my $adr  = shift;
	if ($adr !~ /^[-\w\.]+\@(?:[-\w]+\.)+[-\w]+$/) { return; }
	return $adr;
}
sub check_mail_addresses {
	my $self = shift;
	my $adr  = shift;

	my $ary  = ref($adr) ? $adr : [ split(/\s*,\s*/, $adr) ];
	if (!@$ary) { return; }
	foreach(@$ary) {
		if ($_ !~ /^[-\w\.]+\@(?:[-\w]+\.)+[-\w]+$/) { return; }
	}
	return \@$ary;
}

sub get_timezone {
	require Time::Local;
	my @tm = (0,0,0,1,0,100);	# 2000-01-01
	my $d  = Time::Local::timegm(@tm) - Time::Local::timelocal(@tm);
	my $pm = ($d<0) ? '-' : '+';
	$d = ($d<0) ? -$d : $d;

	my $m = int($d/60);
	my $h = int($m/60);
	$m = $m - $h*60;
	return $pm . substr("0$h", -2) . substr("0$m", -2);
}

# Sun, 06 Nov 1994 08:49:37 +0900
sub mail_date_local {
	my $self = shift;
	my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(shift);

	my($wd, $mn);
	$wd = substr('SunMonTueWedThuFriSat',$wday*3,3);
	$mn = substr('JanFebMarAprMayJunJulAugSepOctNovDec',$mon*3,3);

	return sprintf("$wd, %02d $mn %04d %02d:%02d:%02d %s",
		, $mday, $year+1900, $hour, $min, $sec, $self->get_timezone());
}

################################################################################
# BASE64
################################################################################
my $base64table = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
my @base64ary = (
 0, 0, 0, 0,  0, 0, 0, 0,   0, 0, 0, 0,  0, 0, 0, 0,	# 0x00〜0x1f
 0, 0, 0, 0,  0, 0, 0, 0,   0, 0, 0, 0,  0, 0, 0, 0,	# 0x10〜0x1f
 0, 0, 0, 0,  0, 0, 0, 0,   0, 0, 0,62,  0,62, 0,63,	# 0x20〜0x2f
52,53,54,55, 56,57,58,59,  60,61, 0, 0,  0, 0, 0, 0,	# 0x30〜0x3f
 0, 0, 1, 2,  3, 4, 5, 6,   7, 8, 9,10, 11,12,13,14,	# 0x40〜0x4f
15,16,17,18, 19,20,21,22,  23,24,25, 0,  0, 0, 0,63,	# 0x50〜0x5f
 0,26,27,28, 29,30,31,32,  33,34,35,36, 37,38,39,40,	# 0x60〜0x6f
41,42,43,44, 45,46,47,48,  49,50,51, 0,  0, 0, 0, 0	# 0x70〜0x7f
);

#-------------------------------------------------------------------------------
# BASE64 encode
#-------------------------------------------------------------------------------
sub mime_encode {
	my $self = shift;
	foreach(@_) {
		$_ =~ s/([^\x00-\x7f]+)(?:(\s+)(?=[^\x00-\x7f]))?/ "=?$self->{code}?B?" . $self->base64encode($1 . $2) . '?=' /eg;
	}
	return $_[0];
}
sub base64encode {
	my $self = shift;
	my $str  = shift;
	my $ret;

	# 2 : 0000_0000 1111_1100
	# 4 : 0000_0011 1111_0000
	# 6 : 0000_1111 1100_0000
	my ($i, $j, $x);
	for($i=$x=0, $j=2; $i<length($str); $i++) {
		$x    = ($x<<8) + ord(substr($str,$i,1));
		$ret .= substr($base64table, ($x>>$j) & 0x3f, 1);

		if ($j != 6) { $j+=2; next; }
		# j==6
		$ret .= substr($base64table, $x & 0x3f, 1);
		$j    = 2;
	}
	if ($j != 2)    { $ret .= substr($base64table, ($x<<(8-$j)) & 0x3f, 1); }
	if ($j == 4)    { $ret .= '=='; }
	elsif ($j == 6) { $ret .= '=';  }

	return $ret;
}
#-------------------------------------------------------------------------------
# BASE64 decode
#-------------------------------------------------------------------------------
# used by cram_md5
sub base64decode {	# 'normal' or 'URL safe'
	my $self = shift;
	my $str  = shift;

	my $ret;
	my $buf;
	my $f;
	$str =~ s/[=\.]+$//;
	for(my $i=0; $i<length($str); $i+=4) {
		$buf  = ($buf<<6) + $base64ary[ ord(substr($str,$i  ,1)) ];
		$buf  = ($buf<<6) + $base64ary[ ord(substr($str,$i+1,1)) ];
		$buf  = ($buf<<6) + $base64ary[ ord(substr($str,$i+2,1)) ];
		$buf  = ($buf<<6) + $base64ary[ ord(substr($str,$i+3,1)) ];
		$ret .= chr(($buf & 0xff0000)>>16) . chr(($buf & 0xff00)>>8) . chr($buf & 0xff);

	}
	my $f = length($str) & 3;	# mod 4
	if ($f >1) { chop($ret); }
	if ($f==2) { chop($ret); }
	return $ret;
}

1;
