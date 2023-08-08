use strict;
#-------------------------------------------------------------------------------
# OAuthモジュール
#						(C)2010-2015 nabe / nabe@abk
#-------------------------------------------------------------------------------
# HMAC-SHA1 専用
#
package Sakia::Net::OAuth;
our $VERSION = '0.95';
################################################################################
# ■基本処理
################################################################################
#-------------------------------------------------------------------------------
# ●【コンストラクタ】
#-------------------------------------------------------------------------------
sub new {
	my $self = bless({}, shift);
	$self->{ROBJ} = shift;

	$self->{oauth_ver} = "1.0";
	$self->{signature_method} = 'HMAC-SHA1';
	return $self;
}

################################################################################
# ■メインルーチン
################################################################################
#-------------------------------------------------------------------------------
# ●相手サーバにリクエストを送信
#-------------------------------------------------------------------------------
sub request_token {
	my $self = shift;
	my $h    = shift;
	my $url  = shift || $h->{callback_url};
	my $ROBJ = $self->{ROBJ};

	my $oauth = {
		oauth_consumer_key => $h->{consumer_key},
		oauth_nonce        => $self->generate_nonce(),
		oauth_timestamp    => $ROBJ->{TM},
		oauth_version      => $self->{oauth_ver},
		oauth_signature_method => $self->{signature_method}
	};
	if ($url) {
		$oauth->{oauth_callback} = $url;
	};
	$oauth->{oauth_signature} = $self->generate_signature(
		'GET',
		$h->{request_token_path},
	 	$self->generate_msg($oauth),
		$h->{consumer_secret}
	);

	my $http = $ROBJ->loadpm('Base::HTTP');
	$http->{error_to_root} = 1;
	my $res = $http->get($h->{request_token_path}, {
		Authorization => $self->generate_auth($oauth)
	});

	if (!ref($res)) { return undef; }	# error
	my $res = $self->parse_response( $http, join('', @$res) );
	if ($res->{oauth_callback_confirmed} ne 'true') {
		$ROBJ->error("OAuth request_token response error: $res->{error}\n");	## mskip
		return undef;
	}
	return $res;
}

#-------------------------------------------------------------------------------
# ●認証用Queryの生成
#-------------------------------------------------------------------------------
sub request_access_token {
	my $self = shift;
	my $h = shift;
	my $ROBJ = $self->{ROBJ};

	my $oauth = {
		oauth_consumer_key => $h->{consumer_key},
		oauth_nonce        => $self->generate_nonce(),
		oauth_timestamp    => $ROBJ->{TM},
		oauth_token        => $h->{token},
		oauth_verifier     => $h->{verifier},
		oauth_version      => $self->{oauth_ver},
		oauth_signature_method => $self->{signature_method}
	};
	$oauth->{oauth_signature} = $self->generate_signature(
		'GET',
	 	$h->{access_token_path},
	 	$self->generate_msg($oauth),
		$h->{consumer_secret},
		$h->{token_secret}
	);

	my $http = $ROBJ->loadpm('Base::HTTP');
	$http->{error_to_root} = 1;
	my $res = $http->get($h->{access_token_path}, {
		Authorization => $self->generate_auth($oauth)
	});

	if (!ref($res)) { return undef; }	# error
	return $self->parse_response( $http, join('', @$res) );
}

#-------------------------------------------------------------------------------
# ●OAuth GET/POST
#-------------------------------------------------------------------------------
sub get {
	my $self = shift;
	return $self->request('GET',  @_);
}
sub post {
	my $self = shift;
	return $self->request('POST', @_);
}
sub request {
	my $self = shift;
	my ($method, $h, $url, $req) = @_;
	my $ROBJ = $self->{ROBJ};

#  GET /photos?file=vacation.jpg&size=original HTTP/1.1
#  Host: photos.example.net
#  Authorization: OAuth realm="Photos",
#     oauth_consumer_key="dpf43f3p2l4k3l03",
#     oauth_token="nnch734d00sl2jdk",
#     oauth_signature_method="HMAC-SHA1",
#     oauth_timestamp="137131202",
#     oauth_nonce="chapoH",
#     oauth_signature="MdpQcU8iPSUjWoN%2FUDMsK2sui9I%3D"

	my $oauth = {
		oauth_consumer_key => $h->{consumer_key},
		oauth_nonce        => $self->generate_nonce(),
		oauth_timestamp    => $ROBJ->{TM},
		oauth_token        => $h->{access_token},
		oauth_version      => $self->{oauth_ver},
		oauth_signature_method => $self->{signature_method}
	};
	my %msg = %$oauth;

	# フォーム値の追加
	my $jcode;
	if ($ROBJ->{SystemCode} ne 'UTF-8') {
		$jcode = $ROBJ;
	}
	foreach(keys(%$req)) {
		my $v = $req->{$_};
		if ($jcode) {
			$jcode->from_to(\$v, $ROBJ->{SystemCode}, 'UTF-8');
		}
		$self->oauth_encode_uricom($v);
		$msg{$_} = $v;
	}

	# 署名生成
	$oauth->{oauth_signature} = $self->generate_signature(
		$method,
		$url,
		$self->generate_msg(\%msg),
		$h->{consumer_secret},
		$h->{access_token_secret}
	);
	my $header = {
		Authorization => $self->generate_auth($oauth)
	};

	my $http = $ROBJ->loadpm('Base::HTTP');
	my $res;
	if ($method eq 'POST') {
		$res = $http->post($url, $header, $req);
	} elsif ($method eq 'GET') {
		if ($req) {
			my $par='';
			foreach(keys(%$req)) {
				$par .= "$_=$req->{$_}&";
			}
			chop($par);
			$url .= '?' . $par;
		}
		$res = $http->get($url, $header);
	} else {
		return;			# error
	}

	if (!ref($res)) { return; }	# error
	my $text = join('', @$res);
	my $data = $self->parse_json( $text );
	return wantarray ? ($data, $text) : $data;
}

################################################################################
# ■サブルーチン
################################################################################
#-------------------------------------------------------------------------------
# ●http://～:xxx/～ のパース
#-------------------------------------------------------------------------------
sub parse_host_path {
	my $self = shift;
	my $url = shift;
	if ($url !~ m|^http://([^/:]*)(?::(\d+))?(.*)$|) {
		return undef;
	}
	return ($1, $3);
}

#-------------------------------------------------------------------------------
# ●nonceの生成
#-------------------------------------------------------------------------------
sub generate_nonce {
	my $self = shift;
	my $nonce = $self->{ROBJ}->generate_nonce(20);
	$nonce =~ s/[^\w\-]//g;
	return $nonce;
}

#-------------------------------------------------------------------------------
# ●nonceの生成
#-------------------------------------------------------------------------------
sub generate_nonce {
	my $self = shift;
	my $nonce = $self->{ROBJ}->generate_nonce(20);
	$nonce =~ s/[^\w\-]//g;
	return $nonce;
}

#-------------------------------------------------------------------------------
# ●OAuthメッセージの生成
#-------------------------------------------------------------------------------
sub generate_msg {
	my $self = shift;
	my $h = shift;
	my @ary = sort {$a cmp $b} keys(%$h);
	my $msg = '';
	foreach(@ary) {
		$msg .= "$_=$h->{$_}&";
	}
	chop($msg);
	return $msg;
}

#-------------------------------------------------------------------------------
# ●Authorizationヘッダの生成
#-------------------------------------------------------------------------------
sub generate_auth {
	my $self  = shift;
	my $h     = shift;
	my $realm = shift || '';

	my @ary = sort {$a cmp $b} keys(%$h);
	my $auth = "OAuth realm=\"$h->{realm}\",\n";
	foreach(@ary) {
		$auth .= " $_=\"$h->{$_}\",\n";
	}
	chop($auth);
	chop($auth);
	return $auth;
}

#-------------------------------------------------------------------------------
# ●HMAC-SHA1の生成
#-------------------------------------------------------------------------------
sub hmac_sha1 {
	my $self = shift;
	my ($key, $msg) = @_;
	my $sha1;
	if ($Digest::SHA::PurePerl::VERSION) {
		$sha1 = Digest::SHA::PurePerl->new(1);
	} else {
		eval {
			require Digest::SHA1;
			$sha1 = Digest::SHA1->new;
		};
		if ($@) {
			require Digest::SHA::PurePerl;
			$sha1 = Digest::SHA::PurePerl->new(1);
		}
	}

	my $bs = 64;
	if (length($key) > $bs) {
		$key = $sha1->add($key)->digest;
		$sha1->reset;
	}
	my $k_opad = $key ^ ("\x5c" x $bs);
	my $k_ipad = $key ^ ("\x36" x $bs);
	$sha1->add($k_ipad);
	$sha1->add($msg);
	my $hk_ipad = $sha1->digest;
	$sha1->reset;
	$sha1->add($k_opad, $hk_ipad);

	my $b64d = $sha1->b64digest;
	$b64d = substr($b64d.'====', 0, ((length($b64d)+3)>>2)<<2);
	return $b64d;
}

#-------------------------------------------------------------------------------
# ●署名の生成
#-------------------------------------------------------------------------------
sub generate_signature {
	my $self = shift;
	my ($method, $url, $msg, $secret1, $secret2) = @_;

	# signatureの生成
	$self->oauth_encode_uri($url, $msg);
	my $sig = $self->hmac_sha1("$secret1&$secret2", "$method&$url&$msg");
	$sig =~ s/=/%3D/g;
	$sig =~ s/\+/%2B/g;
	return $sig;
}

#-------------------------------------------------------------------------------
# ●URIエンコード
#-------------------------------------------------------------------------------
sub oauth_encode_uri {
	my $self = shift;
	foreach(@_) {
		$_ =~ s|([^\w\-\.\~])|
			my $x = '%' . unpack('H2', $1);
			$x =~ tr/a-f/A-F/;
			$x;
		|eg;
	}
}
sub oauth_encode_uricom {
	my $self = shift;
	foreach(@_) {
		$_ =~ s|([^\w!\(\)\*\-\.\~\/:])|
			my $x = '%' . unpack('H2', $1);
			$x =~ tr/a-f/A-F/;
			$x;
		|eg;
	}
}

#-------------------------------------------------------------------------------
# ●レスポンスフォームのパース
#-------------------------------------------------------------------------------
sub parse_response {
	my $self = shift;
	my $http = shift;
	my $res  = shift;
	my %h;
	$h{status} = $http->{status};

	if ($http->{status} >= 400) {
		if ($res =~ m|<error\s+(?:code="(\d+)")?>([^<]*)</error>|i) {
			my $err = $2 . ($1 ? " (code=$1)" : '');
			$h{error} = $err;
		}
		return \%h;
	}
	foreach(split(/&/, $res)) {
		my ($k, $v) = split(/=/, $_, 2);
		$v =~ tr/+/ /;
		$v =~ s/%([0-9a-fA-F][0-9a-fA-F])/chr(hex($1))/eg;
		$v =~ s/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]//g;	# TAB LF CR以外の制御コードを除去
		$h{$k} = $v;
	}
	return \%h;
}

#-------------------------------------------------------------------------------
# ●JSONのパース（正しいもののみ正しくパースされる）
#-------------------------------------------------------------------------------
my %json_esc = (
'/' => '/',
'"' => '"',
"\\" => "\\",
"b" => "\x08",
"f" => "\x0c",
"n" => "\n",
"r" => "\r",
"t" => "\t"
);
my %json_val = (
'true'  => $Sakia::Boolean::true,
'false' => $Sakia::Boolean::false,
'null'  => undef
);
sub parse_json {
	my $self = shift;
	my $json = shift;
	if ($json =~ /^\s*$/) { return ; }
	my @str;
	# $self->{ROBJ}->debug($json);
	$json =~ s/[\x00-\x01]//g;
	$json =~ s/\\"/\x01/g;
	$json =~ s/"([^"]*)"/push(@str,$1),"\x00$#str\x00"/eg;
	# 文字列の処理
	foreach(@str) {
		$_ =~ s|\\([/\\bfnrt])|$json_esc{$1}|g;
		$_ =~ s/\x01/"/g;
		$_ =~ s/\\u([0-9A-Za-z][0-9A-Za-z][0-9A-Za-z][0-9A-Za-z])/
			my $x = hex($1);
			if ($x < 2) { 
				"";
			} elsif ($x < 0x100) { 
				chr($x);
			} else {
				# UTF-16 to UTF-8
				  chr(0xE0 | (($x>>12) & 0x0f))
				. chr(0x80 | (($x>> 6) & 0x3f))
				. chr(0x80 | ( $x      & 0x3f));
			}
		/eg;
	}
	$json =~ s/\s*//g;
	#---------------------------------------------------
	# JSON解析
	#---------------------------------------------------
	my @ary;
	foreach(split(/,/, $json)) {
		while($_ =~ /^(.*?)([\[\]\{\}])(.*)$/) {
			if ($1 ne '') { push(@ary, $1); }
			push(@ary, $2);
			$_ = $3;
		}
		if ($_ ne '') { push(@ary, $_); }
	}
	my @stack;
	my $ret = (shift(@ary) eq '{') ? {} : [];
	my $c = $ret;
	eval {
	while(@ary) {
		my $v = shift(@ary);
		if ($v eq '}' || $v eq ']') {
			$c = pop(@stack);
			next;
		}
		# ハッシュの場合
		if (ref($c) eq 'HASH') {
			my $x = index($v, ':');
			my $key = substr($v, 0, $x);
			my $val = substr($v, $x+1);
			$key =~ s/^\x00(\d+)\x00$/$str[$1]/;
			if (exists $json_val{$val}) {
				$val = $json_val{$val};
			} else {
				$val =~ s/^\x00(\d+)\x00$/$str[$1]/;
			}
			if ($ary[0] eq '{') {
				shift(@ary);
				push(@stack, $c);
				$c = $c->{$key} = {};
			} elsif ($ary[0] eq '[') {
				shift(@ary);
				push(@stack, $c);
				$c = $c->{$key} = [];
			} else {
				$c->{$key} = $val;
			}
			next;
		}
		# 配列の場合
		if ($v eq '{') {
			push(@stack, $c);
			push(@$c, {});
			$c = $c->[ $#$c ];
		} elsif ($v eq '[') {
			push(@stack, $c);
			push(@$c, []);
			$c = $c->[ $#$c ];
		} elsif (exists $json_val{$v}) {
			push(@$c, $json_val{$v});
		} else {
			$v =~ s/^\x00(\d+)\x00$/$str[$1]/;
			push(@$c, $v);
		}
	}
	}; # eval
	return $ret;
}

1;
