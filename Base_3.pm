use strict;
package Sakia::Base;
################################################################################
# for normal fcgi
################################################################################
sub init_for_fastcgi {
	my $self = shift;
	$self->{FcgiReq}  = shift;
	$self->{CgiMode}  = 'FastCGI';
	$self->{CgiCache} = 1;
	$self->{FastCGI}  = 1;
}

################################################################################
# for httpd deamon
################################################################################
sub init_for_httpd {
	my $self  = shift;
	$self->{HTTPD_state} = shift;
	my $path  = shift || '/';

	$self->{CgiMode}  = 'httpd';
	$self->{CgiCache} = 1;
	$self->{HTTPD}    = 1;

	$self->{InitPath}   = 1;
	$self->{Basepath}   = $path;
	$self->{ModRewrite} = 1;

	$self->{myself}  = $path;
	$self->{myself2} = $path;

	my $port = int($ENV{SERVER_PORT});
	my $protocol = ($port == 443) ? 'https://' : 'http://';
	$self->{ServerURL} = $protocol . $ENV{SERVER_NAME} . (($port != 80 && $port != 443) ? ":$port" : '');
}

################################################################################
# safety fork
################################################################################
sub fork {
	my $self = shift;
	my $ssid = shift;
	my $fcgi = $self->{FcgiReq};
	$fcgi && $fcgi->Detach();

	my $fork = fork();
	if ($fork) {
		# parent
		$fcgi && $fcgi->Attach();
		return $fork;
	}
	if (defined $fork) {
		# child
		close(STDIN);
		close(STDOUT);
		## close(STDERR);	# Error on FastCGI

		$self->{Shutdown} = 1;
		$ssid && eval {
			require	POSIX;
			POSIX::setsid();
		};
	}
	return $fork;
}

################################################################################
# for system check
################################################################################
sub get_system_info {
	my $self = shift;
	my %h;
	my $v = $];
	$v =~ s/(\d+)\.(\d\d\d)(\d\d\d)/$1.'.'. ($2+0).'.'.($3+0)/e;
	$h{perl_version} = $v;
	$h{perl_cmd}     = $^X;
	return \%h;
}

sub check_lib {
	my $self = shift;
	my $lib  = shift;
	my $pm = $lib =~ s|::|/|rg;
	eval { require "$pm.pm"; };
	if ($@) { return; }
	my $ver = do {
		no strict "refs";
		${$lib . '::VERSION'};
	};
	return $ver ? $ver : '?.??';
}

sub check_cmd {
	my $self = shift;
	my $cmd  = shift;
	foreach(split(/:/, $ENV{PATH})) {
		if (-x "$_/$cmd") { return 1; }
	}
	return;
}

################################################################################
# dump
################################################################################
sub dump {
	my $self = shift;
	my $data = shift;
	my $tab  = shift || '    ';
	my $br   = shift || "\n";
	my $indent = shift || '';
	my $safety = shift || {};

	my $ref = $self->get_ref_type($data);
	if ($ref eq 'SCALAR') {
		return "\\\"$$data\"";
	}
	if (!$ref) {
		return $data . $br;
	}
	my $is_array = $ref eq 'ARRAY';

	if ($safety->{$data}) { return '***circular reference***'; }
	$safety->{$data}=1;

	my $ret = $is_array ? '[' : '{';
	my @ary = $is_array ? @$data : sort(keys(%$data));
	if (@ary) { $ret .= $br; }
	foreach(@ary) {
		my $k = $is_array ? '' : "$_ => ";
		my $v = $is_array ? $_ : $data->{$_};

		if (ref($v)) {
			$v = $self->dump($v, $tab, $br, "$tab$indent", $safety);
		}
		$ret .= "$indent$tab$k$v$br";
	}
	return $ret . (@ary ? $indent : '') . ($is_array ? ']' : '}');
}

sub get_ref_type {
	my $self = shift;
	my $v    = shift;
	my $ref  = ref($v);
	if ($ref && $v =~ /=/) { return Scalar::Util::reftype($v); }
	return $ref;
}

1;
