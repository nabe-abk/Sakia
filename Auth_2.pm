use strict;
package Sakia::Auth;
################################################################################
# Initalize
################################################################################
sub init {
	my $self = shift;
	my $DB   = $self->{DB};
	if ($self->{init}) { return; }
	$self->{init} = 1;

	if ($self->{auto_login}) {
		my $pkey = $DB->select_match_pkey1($self->{table}, 'isadmin', 1, 'disable', 0, '*no_error', 1, '*cols', 'pkey', '*no_error', 1);
		if ($pkey) { return; }		# exists admin
		$self->{allow_auto_login} = 1;
	}
	if (!$DB->find_table($self->{table})) {
		$self->create_user_table();
	}
}

################################################################################
# login, logout
################################################################################
sub login {
	my $self   = shift;
	my $id     = shift;
	my $pass   = shift;
	my $secret = shift;
	my $ROBJ   = $self->{ROBJ};
	my $DB     = $self->{DB};
	$self->init();

	if ($self->{ok}) { $self->logout(); }

	if (($self->{allow_ip} || $self->{allow_host}) && !$ROBJ->check_ip_host($self->{allow_ip}, $self->{allow_host})) {
		$self->save_log($id, 'login', 'fail (IP/Host)');
		return { ret=>1, msg=>'security error' };
	}

	if ($self->{allow_auto_login}) {
		$self->auto_login();
		$self->save_log('root*', 'login');
		return { ret=>0, sid=>'auth (no exist user)' };
	}

	my $table = $self->{table};
	my $h     = $DB->select_match_limit1($table, $self->{alt_uid} || 'id', $id);
	if (!$h) {
		$self->save_log($id, 'login', 'failure');
		return { ret=>10, msg => $ROBJ->translate('Incorrect ID or password.') };
	}
	my $id = $h->{id};

	#---------------------------------------------------
	# fail counter
	#---------------------------------------------------
	my $cnt = $h->{fail_c};
	if ($h->{fail_tm} + $self->{fail_sleep_min} < $ROBJ->{TM}) { $cnt=0; }

	if ($cnt > $self->{fail_limit}) {
		return { ret=>11, msg => $ROBJ->translate('Too many failures. Please try again later.') };
	}
	if ($h->{disable} || !$self->check_pass($h->{pass}, $pass)) {
		$cnt++;
		$DB->update_match($table, {fail_c => $cnt, fail_tm => $ROBJ->{TM}}, 'id', $id);
		$self->save_log($id, 'login', 'failure');
		return { ret=>10, msg => $ROBJ->translate('Incorrect ID or password.') };
	}

	#---------------------------------------------------
	# login success
	#---------------------------------------------------
	my $ary = $DB->select_match($table.'_sid', 'id', $id);
	my $max = $self->{max_sessions}-1;
	if (0<=$max && $max <= $#$ary) {
		$ary = [ sort {$b->{login_tm} <=> $a->{login_tm}} @$ary ];
		splice(@$ary, 0, $max);
		@$ary && $DB->delete_match($table.'_sid', 'pkey', [ map { $_->{pkey} } @$ary ]);
	}

	my $sid = $ROBJ->generate_nonce(32);
	my $pkey= $DB->insert("${table}_sid", {
		id       => $id,
		sid      => $sid,
		login_tm => $ROBJ->{TM},
	});
	$self->{sid_pkey} = $pkey;

	my $login_c = ++$h->{login_c};
	$DB->update_match($table, { login_c=>$login_c, login_tm=>$ROBJ->{TM}, fail_c=>0 }, 'id', $id);

	$self->set_login_info($h, $secret);
	$self->save_log($id, 'login');

	return { ret=>0, sid=>$sid };
}

sub set_login_info {
	my ($self, $h, $secret) = @_;
	my $ROBJ = $self->{ROBJ};
	my $id   = $h->{id};

	$self->{ok}   = 1;
	$self->{pkey} = $h->{pkey};
	$self->{id}   = $id;
	$self->{name} = $h->{name};
	$self->{isadmin}  = $h->{isadmin};
	$self->{disadmin} = 0;		# disabled admin

	my %ext = %$h;
	delete $ext{pass};
	$self->{ext} = \%ext;
	if (!$self->{isadmin}) { return; }

	#---------------------------------------------------
	# check admin limiter
	#---------------------------------------------------
	if ($self->{admin_list} && ! $self->{admin_list}->{$id}) {
		$self->{isadmin} = 0;
		return;
	}
	if ($self->{admin_secret} ne '' && $self->{admin_secret} eq $secret) { return; }
	if (!$self->{admin_allow_ip} && !$self->{admin_allow_host}) { return; }
	if ($ROBJ->check_ip_host($self->{admin_allow_ip}, $self->{admin_allow_host})) { return; }

	# Not allow admin
	$self->{isadmin}  = 0;
	$self->{disadmin} = 1;
}

sub auto_login {
	my $self = shift;
	$self->{ok}   = 1;
	$self->{pkey} = 0;
	$self->{id}   = "root*";
	$self->{name} = "root*";
	$self->{auto} = 1;
	$self->{isadmin} = 1;	# 管理者権限
	$self->{sid_pkey}= 0;
	$self->{ext}  = {};
}

sub logout {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	my $DB   = $self->{DB};
	my $id   = $self->{id};
	my $spkey= $self->{sid_pkey};

	foreach(qw(ok pkey id name auto isadmin sid_pkey)) {
		$self->{$_}=undef;
	}
	$self->{ext} = {};
	if ($id eq '') { return; }

	my $table = $self->{table} . '_sid';
	if ($self->{logout_all} || $self->{max_sessions} < 2) {
		$DB->delete_match($table, 'id', $id);
	} else {
		$DB->delete_match($table, 'id', $id, 'pkey', $spkey);
	}
	$self->save_log($id, 'logout');
}

################################################################################
# auth session
################################################################################
sub auth_session {
	my ($self, $id, $sid, $secret) = @_;
	my $ROBJ = $self->{ROBJ};
	my $DB   = $self->{DB};

	if ($sid eq '') { return; }
	if (($self->{allow_ip} || $self->{allow_host}) && !$ROBJ->check_ip_host($self->{allow_ip}, $self->{allow_host})) { return; }

	my $ss = $DB->select_match_limit1($self->{table}.'_sid', 'id', $id, 'sid', $sid, '*no_error', 1);
	if (!$ss) {
		$self->init();
		if ($self->{allow_auto_login}) {
			$self->auto_login();
			return -1;
		}
		return;
	}

	my $expires = $self->{expires};
	if (0<$expires && $ss->{login_tm} + $expires < $ROBJ->{TM}) {
		$DB->delete_match($self->{table}.'_sid', 'pkey', $ss->{pkey});
		return;
	}

	my $h = $DB->select_match_limit1($self->{table}, 'id', $id);
	if (!$h || $h->{disable}) { return; }

	$self->set_login_info($h, $secret);
	$self->{sid_pkey} = $ss->{pkey};

	return $h->{pkey};
}

################################################################################
# subroutine
################################################################################
sub save_log {
	my $self = shift;
	if ($self->{log_func}) {
		&{ $self->{log_func} }(@_);
	}
	if ($self->{stop_log}) { return; }

	my $id   = shift;
	my $type = shift;
	my $msg  = shift;
	my $DB   = $self->{DB};
	my $ROBJ = $self->{ROBJ};

	my $h = {id => $id, type => $type, msg => $msg};
	$h->{agent} = $ENV{HTTP_USER_AGENT};
	$h->{ip}    = $ENV{REMOTE_ADDR};
	$h->{host}  = $ENV{REMOTE_HOST};
	$h->{tm}    = $ROBJ->{TM};

	foreach(keys(%$h)) {
		$h->{$_} = substr($h->{$_}, 0, $self->{log_text_max});
		$ROBJ->esc_dest($h->{$_});
	}

	$DB->insert($self->{table} . '_log', $h);
}

sub check_pass {
	my ($self, $crypted, $plain) = @_;
	return crypt($plain, $crypted) eq $crypted;	# Ture is auth
}

1;
