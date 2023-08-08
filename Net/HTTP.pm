use strict;
#-------------------------------------------------------------------------------
# HTTP module
#							(C)2006-2023 nabe@abk
#-------------------------------------------------------------------------------
# - support Cookie (ignore 2nd level domain)
# - support https, if exists Net::SSLeay v1.50 or later
# - support IPv6
#
package Sakia::Net::HTTP;
our $VERSION = '2.00';
#-------------------------------------------------------------------------------
use Socket;
################################################################################
# constructor
################################################################################
sub new {
	my $class = shift;
	my $self = {
		ROBJ	=> shift,

		status		=> -1,
		errstr		=> undef,

		header		=> {},			# Response header
		cookie		=> {},
		use_cookie	=> 0,
		cookie_domain	=> {},			# Allow cookie's domain
		timeout		=> 30,
		auto_redirect	=> 5,
		error_stop	=> 0,			# Stop error to $ROBJ->error()

		use_sni		=> 1,			# use SNI
		ipv6		=> 1,			# use IPv6
		ipv6_preferred	=> 0,
		# debug_log	=> '',			# debug log file

		max_header_size	=> 16 *1024,		# 16KB
		max_size	=> 64 *1024*1024,	# 64MB

		agent		=> shift // "Simple-HTTP/$VERSION"
	};
	return bless($self, $class);
}

################################################################################
# GET/POST
################################################################################
sub get {
	my $self = shift;
	return $self->request('GET',  @_);
}
sub post {
	my $self = shift;
	return $self->request('POST', @_);
}

sub request {
	my $self   = shift;
	my $method = shift;
	my $url    = shift;

	my $data;
	foreach(0..$self->{auto_redirect}) {
		$data = $self->send_request($method, $url, @_);
		if (!$data) { return; }

		my $status = $self->{status};
		if (300<=$status && $status<400 && $self->{header}->{location}) {
			if ($status == 303) { $method='GET'; }

			my $lo = $self->{header}->{location};
			$url = ($lo =~ m|^https?://?|i) ? $lo : (($url =~ s|^(\w+://[^/]*).*|$1|sr) . $lo);
			last;
		}
		return $data;
	}
	return $data;
}


################################################################################
# Request
################################################################################
sub send_request {
	my ($self, $method, $url, $_header, $body) = @_;
	my $ROBJ  = $self->{ROBJ};
	my $https = ($url =~ m|^https://|i);

	$self->{errstr} = undef;
	$self->{status} = -1;

	if ($url !~ m|^https?://(\[[0-9A-Fa-f:]+\])(:(\d+))?(.*)|i	# IPv6 ex) https://[fe80::1]/
	 && $url !~ m|^https?://([^/:]*)(:(\d+))?(.*)|i
	) {
		return $self->error('Invalid URL format: %s', $url);
	}
	my $host = $1;
	my $port = $3 || ($https ? 443 : 80);
	my $path = $4 || '/';
	$host =~ s/\.+$//;

	#-----------------------------------------------------------------------
	# init header
	#-----------------------------------------------------------------------
	my %header = ((
		Host		=> $host,
		'User-Agent' 	=> $self->{agent}
	), %{$_header || {}});

	#-----------------------------------------------------------------------
	# Cookie
	#-----------------------------------------------------------------------
	my $cookie = $self->{cookie};
	my $time   = $self->{use_cookie} && time();
	if ($self->{use_cookie}) {
		my $line='';
		my @ary;
		my $x = $host;
		my %hosts;	# www.example.com and example.com and com
		while($x ne '') {
			$hosts{$x}=1;
			$x =~ s/^[^\.]+(?:\.|$)//;
		}
		while(my ($k,$v) = each(%$cookie)) {
			my ($dom, $cpath, $name) = split(/;/, $k, 3);
			if ($hosts{$dom}) {
			 	if ($v->{_exp} && $v->{_exp}<=$time) { next; }
			 	if (index($path, $cpath) != 0) { next; }
			 	if ($v->{secure} && !$https) { next; }

				push(@ary, "$name=$v->{value}");
			}
		}
		if (@ary) { $header{Cookie} = join('; ', @ary) }
	}

	#-----------------------------------------------------------------------
	# POST body
	#-----------------------------------------------------------------------
	if ($method eq 'POST') {
		if (ref($body) eq 'HASH') {
			my $h = $body;
			$body='';
			while(my ($k,$v) = each(%$h)) {
				$ROBJ->encode_uricom($k,$v);
				$body .= "$k=$v&";
			}
			chop($body);
		}
		$header{'Content-Length'} = length($body);
		$header{'Content-Type'} ||= 'application/x-www-form-urlencoded';
	} else {
		$body = '';
	}

	#-----------------------------------------------------------------------
	# make header
	#-----------------------------------------------------------------------
	my $header='';
	foreach(keys(%header)) {
		if ($_ eq '' || $_ =~ /[^\w\-]/) { next; }
		my $v = $header{$_};
		$v =~ s/^\s*//;
		$v =~ s/[\r\n]//g;
		$header .= "$_: $v\r\n";
	}
	$header .= "Connection: close\r\n";

	#-----------------------------------------------------------------------
	# Send request
	#-----------------------------------------------------------------------
	my $res = do {
		my $request = "$method $path HTTP/1.1\r\n$header\r\n$body";
		undef $header;
		undef $body;
		$self->send_data($https, $host, $port, $request);
	};
	if (!$res) { return; }

	$self->save_log($self->{header_txt});

	#-----------------------------------------------------------------------
	# parse Header
	#-----------------------------------------------------------------------
	my %h;
	my ($st,@ary) = split(/\r\n/, $self->{header_txt});
	if ($st !~ m|^HTTP/\d.\d (\d\d\d)|) {
		return $self->error("Illegal response from: %s %s", $url, $st);
	}
	my $status = $self->{status} = $1;
	pop(@ary);

	my @cookies;
	foreach(@ary) {
		if ($_ !~ /^([\w\-]+):\s*(.*)/) {
			return $self->error("Illegal response from: %s %s", $url, "($status)");
		}
		my $k = $1 =~ tr/A-Z/a-z/r;
		if ($k eq 'set-cookie') {
			if ($self->{use_cookie}) { push(@cookies, $2); }
			next;
		}
		$h{$k}=$2;
	}
	$self->{header} = \%h;

	#-----------------------------------------------------------------------
	# cookie
	#-----------------------------------------------------------------------
	foreach my $c (@cookies) {
		my @ary     = split(/\s*;\s*/, $c);
		my ($n, $v) = split('=', shift(@ary), 2);
		my %h = (value => $v);

		my $domain = $host;
		my $path   = $path =~ s|[^/]+$||r;
		my $exp;
		my $mage;
		foreach(@ary) {
			$_ =~ tr/A-Z/a-z/;
			if ($_ eq 'httponly' || $_ eq 'secure') { $h{$_}=1; next; }

			if ($_ !~ /^([A-Za-z][\w\-\.]*)=(.*)$/) { next; }
			if ($1 eq 'domain') {
				my $ddom = ($2 =~ s/^\.*/./r) =~ s/\.+$//r;
				my $dom  = substr($ddom,1);
				if (0<=index($host, $ddom) && (exists($self->{cookie_domain}->{$dom}) || $ddom =~ m|^(\.[\w\-]+){3,}$|)) {
					$domain = $dom;
				}
				next;
			}
			if ($1 eq 'path') {
				my $p = $2 =~ s|/*$|/|r;
				if ($p =~ m|^/|) { $path=$p; }
				next;
			}
			if ($1 eq 'expires') {
				if ($mage) { next; }
				$exp = $self->parse_rfc_date($2);
				next;
			}
			if ($1 eq 'max-age') {	# priority to max-age
				$mage= 1;
				$exp = $2 ne '' ? $time + int($2) : undef;
				next;
			}
			$h{$1} = $2;
		}

		my $key = "$domain;$path;$n";
		if ($exp) {
			if ($exp<=$time) {
				delete $cookie->{$key};
				next;
			}
			$h{_exp} = $exp;
		}
		$cookie->{$key} = \%h;
	}

	return $res;
}

################################################################################
# TCP or SSL connection
################################################################################
sub send_data {
	my $self  = shift;
	my $https = shift;
	my $host  = shift;
	my $port  = shift;

	$self->save_log_spliter();

	my $sock;
	my $alarm;
	local $SIG{ALRM} = sub { $alarm=1; if ($sock) { close($sock); } };
	local $SIG{PIPE} = $SIG{ALRM};
	alarm( $self->{timeout} );

	my $sock = $self->connect_host($host, $port);
	if ($alarm || !defined $sock) { return; }
	binmode($sock);

	$self->save_log($_[0]);

	my $func = $https ? 'send_over_ssl' : 'send_over_tcp';
	my $data = $self->$func($sock, $host, @_);
	close($sock);
	if ($alarm || !$data) { return; }

	return $data;
}

#-------------------------------------------------------------------------------
# Connect
#-------------------------------------------------------------------------------
sub connect_host {
	my ($self, $host, $port) = @_;

	if ($self->{ipv6} && $host =~ /\[(.*)\]/) {	# http://[fe80::1]/
		return $self->connect_host6($1, $port);
	}
	if ($self->{ipv6} && $self->{ipv6_preferred}) {
		return $self->connect_host6($host, $port, 'to_v4');
	}
	return $self->connect_host4($host, $port, 'to_v6');
}

sub connect_host4 {
	my ($self, $host, $port, $to_v6) = @_;

	my $ip_bin = inet_aton($host);
	if ($ip_bin eq '') {
		if ($to_v6) { return $self->connect_host6($host, $port); }
		return $self->error("Can't find host: %s", $host);
	}
	my $sockaddr = pack_sockaddr_in($port, $ip_bin);
	my $sock;
	if (! socket($sock, &Socket::PF_INET, &Socket::SOCK_STREAM, 0)) {
		return $self->error("Can't open socket.");
	}
	if (!connect($sock, $sockaddr)) {
		return $self->error("Can't connect host: %s", $host);
	}
	if ($self->{debug_log}) {
		my $ip = inet_ntoa($ip_bin);
		$self->save_log("Connect to $ip:$port\n");
	}
	return $sock;
}

sub connect_host6 {
	my ($self, $host, $port, $to_v4) = @_;

	my ($err,@res) = Socket::getaddrinfo($host,$port);
	@res = grep { $_->{addr} } @res;
	if (!@res) {
		if ($to_v4) { return $self->connect_host4($host, $port); }
		return $self->error("Can't find host: %s", $host);
	}
	my $sockaddr = $res[0]->{addr};
	my $sock;
	if (! socket($sock, &Socket::PF_INET6, &Socket::SOCK_STREAM, 0)) {
		return $self->error("Can't open socket.");
	}
	if (!connect($sock, $sockaddr)) {
		return $self->error("Can't connect host: %s", $host);
	}
	if ($self->{debug_log}) {
		my $ip = Socket::inet_ntop(&Socket::AF_INET6, (unpack_sockaddr_in6($sockaddr))[1]);
		$self->save_log("Connect to $ip:$port\n");
	}
	return $sock;
}

#-------------------------------------------------------------------------------
# Send over TCP
#-------------------------------------------------------------------------------
sub send_over_tcp {
	my $self = shift;
	my $sock = shift;
	my $host = shift;
	my $req  = shift;
	my $len  = length($req);

	if (syswrite($sock, $req, $len) != $len) { return; }

	my $header='';
	my $size  = 0;
	while(<$sock>) {
		if ($_ eq "\r\n") { last; }
		$size += length($_);
		if ($size>$self->{max_header_size}) { return; }
		$header .= $_;
	}
	$self->{header_txt} = $header;

	read($sock, my $data, $self->{max_size});
	return $data;
}

#-------------------------------------------------------------------------------
# Send over SSL
#-------------------------------------------------------------------------------
sub send_over_ssl {
	my $self = shift;
	my $sock = shift;
	my $host = shift;
	my $req  = shift;

	eval { require Net::SSLeay; };
	if ($@) {
		return $self->error("Not found Net::SSLeay (please install this server).");
	}
	my $ver = $Net::SSLeay::VERSION;
	if ($ver<1.50) {
		return $self->error("Net::SSLeay Ver$ver not support SNI.");
	}
	#-----------------------------------------------------------------------
	# SSL
	#-----------------------------------------------------------------------
	my ($header, $data, $err);
	my ($ctx, $ssl);
	ssl: while(1) {
		$ctx = Net::SSLeay::new_x_ctx();
		if ($err = Net::SSLeay::print_errs('CTX_new') || !$ctx) { last; }

		Net::SSLeay::CTX_set_options($ctx, &Net::SSLeay::OP_ALL);
		if ($err = Net::SSLeay::print_errs('CTX_set_options')) { last; }

		$ssl = Net::SSLeay::new($ctx);
		if ($err = Net::SSLeay::print_errs('SSL_new') || !$ssl) { last; }

		if (!Net::SSLeay::set_tlsext_host_name($ssl, $host)) { $err='set_tlsext_host_name()'; last; }

		Net::SSLeay::set_fd($ssl, fileno($sock));
		if ($err = Net::SSLeay::print_errs('set_fd')) { last; }

		Net::SSLeay::connect($ssl);
		if ($err = Net::SSLeay::print_errs('SSL_connect')) { last; }

		my $server_cert = Net::SSLeay::get_peer_certificate($ssl);
		if ($err = Net::SSLeay::print_errs('get_peer_certificate')) { last; }

		if ($err = (Net::SSLeay::ssl_write_all($ssl, $req))[1]) { last; }

		my $size=0;
		while(1) {
			my $x = Net::SSLeay::ssl_read_CRLF($ssl, $self->{max_header_size});
			if ($x eq '') { last ssl; }
			if ($x eq "\r\n") { last; }

			$size++;
			if ($size>$self->{max_header_size}) { last ssl; }
			$header .= $x;
		}

		$data = Net::SSLeay::read($ssl, $self->{max_size});
		last;
	}
	if ($ssl) { Net::SSLeay::free($ssl);     }
	if ($ctx) { Net::SSLeay::CTX_free($ctx); }

	if ($err) {
		return $self->error("Net::SSLeay's error: %s", $err);	# mskip
	}

	$self->{header_txt} = $header;
	return $data;
}


################################################################################
# Accessor
################################################################################
sub status { my $self=shift; return $self->{status}; }
sub errstr { my $self=shift; return $self->{errstr}; }
sub cookie { my $self=shift; return $self->{cookie}; }
sub header {
	my $self = shift;
	return @_ ? $self->{header}->{$_[0]} : $self->{header};
}
sub agent {
	my $self = shift;
	if (@_) { $self->{agent}=shift; }
	return $self->{agent};
}
sub is_success {
	my $self = shift;
	my $st   = $self->{status};
	return 200<=$st && $st<=299;
}

################################################################################
# cookie
################################################################################
sub enable_cookie {
	my $self = shift;
	$self->{use_cookie} = 1;
}

sub disable_cookie {
	my $self = shift;
	$self->{use_cookie} = 0;
}
sub load_cookie {
	my $self = shift;
	my $file = shift;
	my $ROBJ = $self->{ROBJ};
	$self->{use_cookie} = 1;
	$self->{cookie} = $ROBJ->fread_json_cached($file) || {};
}

sub save_cookie {
	my $self = shift;
	my $file = shift;
	my $ROBJ = $self->{ROBJ};

	my %h;
	my $c  = $self->{cookie};
	my $tm = time;
	foreach(keys(%$c)) {
		my $exp = $c->{$_}->{_exp};
		if (!$exp || $exp<=$tm) { next; }
		$h{$_} = $c->{$_};
	}

	$ROBJ->fwrite_json($file, \%h);
}

################################################################################
# subroutine
################################################################################
sub set_timeout {
	my ($self, $timeout) = @_;
	$self->{timeout} = int($timeout) || 30;
}
sub set_agent {
	my $self = shift;
	$self->{agent} = shift || "SimpleHTTP/$VERSION";
}

sub save_log {
	my $self = shift;
	my $file = $self->{debug_log};
	if (!$file) { return; }
	$self->{ROBJ}->fappend_lines($file, join('', @_));
}
sub save_log_spliter {
	my $self = shift;
	$self->save_log("\n" . ('-' x 80) . "\n");
}

my @DayOfYear = (0,31,59,90,120,151,181,212,243,273,304,334);
sub parse_rfc_date {
	my $self = shift;
	my $date = shift;
	if ($date !~ /^\w\w\w, (\d\d) (\w\w\w) (\d\d\d\d) (\d\d):(\d\d):(\d\d) GMT$/i) { return; }
	my $t = $6 + $5*60 + $4*3600;
	my $y = $3;
	my $m = index('janfebmaraprmayjunjulaugsepoctnovdec', $2)/3;
	my $d = $1;
	if ($y<1970 || $m<0) { return; }

	# Leap years up to 1970 have 477 days.
	return $t + ($d-1 + $DayOfYear[$m] + ($y-1970)*365 + $self->count_leap_year($y, $m) - 477)*86400;
}
sub count_leap_year {
	my ($self, $y, $m) = @_;
	if ($m<2) { $y--; }
	return int($y/4) - int($y/100) + int($y/400);
}

################################################################################
# Error
################################################################################
sub error {
	my $self = shift;
	my $err  = shift;
	my $ROBJ = $self->{ROBJ};

	$err = $ROBJ->translate($err, @_);
	if (!$self->{error_stop}) { $ROBJ->error_from('', $err); }

	$self->{errstr} = $err;
	$self->save_log("\n[ERROR] $err\n");
	return undef;
}

1;
