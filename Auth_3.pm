use strict;
package Sakia::Auth;
################################################################################
# Management
################################################################################
sub add_user {
	my ($self, $form, $ext) = @_;
	my $ROBJ = $self->{ROBJ};
	my $DB   = $self->{DB};
	if (! $self->{isadmin}) {
		return { ret=>1, msg => $ROBJ->translate('Operation not permitted.') };
	}

	my $data = $self->check_user_data($form, $ext, 'new');
	if (!$data) {
		return { ret=>10, errs => $ROBJ->form_err() };
	}

	my $r = $DB->insert($self->{table}, $data);
	if ($r) {
		$self->save_log($data->{id}, 'regist');
		return { ret => 0 };
	}
	return { ret => -1, msg => 'Internal Error' };
}

#-------------------------------------------------------------------------------
# edit
#-------------------------------------------------------------------------------
sub edit_user {
	my ($self, $form, $ext) = @_;
	my $ROBJ = $self->{ROBJ};
	my $DB   = $self->{DB};
	if (! $self->{isadmin}) {
		return { ret=>1, msg => $ROBJ->translate('Operation not permitted.') };
	}

	my $id = $form->{id};
	if (! $DB->select_match_pkey1($self->{table}, 'id', $id)) {
		return { ret=>2, msg => $ROBJ->translate('Not found account: %s', $id) };
	}

	$form->{isadmin} ||= 0;
	$form->{disable} ||= 0;

	return $self->update_user_data($id, $form, $ext);
}

#-------------------------------------------------------------------------------
# delete
#-------------------------------------------------------------------------------
sub delete_user {
	my $self = shift;
	my $del  = shift;
	my $ROBJ = $self->{ROBJ};
	my $DB   = $self->{DB};
	my $table= $self->{table};
	if (! $self->{isadmin}) {
		return { ret=>1, msg => $ROBJ->translate('Operation not permitted.') };
	}

	if (!ref($del)) {
		my $h = $DB->select_match_pkey1($table, 'id', $del);
		if (!$h) {
			return { ret=>2, msg => $ROBJ->translate('Not found account: %s', $del) };
		}
		$del = [ $del ];

	} elsif (!@$del) {
		return { ret=>3, msg => $ROBJ->translate('No assignment delete account.') };
	}

	$DB->begin();
	$DB->delete_match("${table}_sid", 'id', $del);
	my $r = $DB->delete_match($table, 'id', $del);
	if ($r != $#$del+1) {
		$DB->rollback();
		return { ret=>20, msg => "[Auth] DB delete error: $r / " . ($#$del+1) };
	}
	if ($DB->commit()) {
		$DB->rollback();
		return { ret=>21, msg => '[Auth] DB Internal error' };
	}

	foreach(@$del) {
		$self->save_log($_, 'delete');
	}
	return { ret => 0 };
}

################################################################################
# Self edit user data
################################################################################
sub change_info {
	my ($self, $form, $ext) = @_;
	my $ROBJ = $self->{ROBJ};

	if (! $self->{ok}) { return { ret=>1, msg => $ROBJ->translate('No login.') }; }
	if ($self->{auto}) { return { ret=>2, msg => $ROBJ->translate("Can't execute with 'root*'.") }; }

	my %up;
	my $ary = $self->{user_change_cols};
	foreach(@$ary) {
		if (exists($form->{$_})) {
			$up{$_} = $form->{$_};
		}
	}

	if ($form->{now_pass} ne '') {
		if (! $self->check_pass_by_id($self->{id}, $form->{now_pass})) {
			return { ret=>10, msg => $ROBJ->translate('Incorrect password.') };
		}
		if (exists($form->{pass} )) { $up{pass}  = $form->{pass};  }
		if (exists($form->{pass2})) { $up{pass2} = $form->{pass2}; }
	}

	return $self->update_user_data($self->{id}, \%up, $ext);
}

################################################################################
# for skeleton
################################################################################
#-------------------------------------------------------------------------------
# [admin] load all users
#-------------------------------------------------------------------------------
sub load_users {
	my ($self, $sort) = @_;
	if (!$self->{isadmin}) { return []; }
	my $DB = $self->{DB};

	my $list = $DB->select_match($self->{table}, '*sort', $sort || 'id');
	foreach(@$list) {
		delete $_->{pass};
	}
	return $list;
}

#-------------------------------------------------------------------------------
# [admin] load user info
#-------------------------------------------------------------------------------
sub load_info {
	my $self = shift;
	my $id   = shift;
	my $col  = shift || 'id';
	if (!$self->{isadmin}) { return; }

	my $DB = $self->{DB};
	my $h  = $DB->select_match_limit1( $self->{table}, $col, $id );
	if (!$h) { return; }

	delete($h->{pass});
	return $h;
}

#-------------------------------------------------------------------------------
# load log
#-------------------------------------------------------------------------------
sub load_logs {
	my $self  = shift;
	my $query = shift;
	my $DB    = $self->{DB};
	my $table = $self->{table} . '_log';

	my %h = (
		limit	=> int($query->{limit}) || 100,
		sort	=> $query->{sort} || '-tm'
	);

	if ($query->{id}) {
		$h{match}->{id} = $query->{id};
	}
	if ($query->{q}) {
		$h{search_words} = [ split(/\s+/, $query->{q}) ];
		$h{search_cols}  = [ 'ip', 'host' ];
		$h{search_equal} = [ 'id' ];
	}

	my $y = int($query->{year});
	my $m = int($query->{mon});
	(1969<$y) && eval {
		require Time::Local;
		if (0<$m && $m<13) {
			$h{min}->{tm} = Time::Local::timelocal(0,0,0,1,$m-1,$y-1900);
			if ($m==12) { $m=1; $y++; }
			$h{max}->{tm} = Time::Local::timelocal(0,0,0,1,$m,  $y-1900) -1;
		} else {
			$h{min}->{tm} = Time::Local::timelocal(0,0,0,1,1,$y-1900);
			$h{max}->{tm} = Time::Local::timelocal(0,0,0,1,1,$y-1900 +1);
		}
	};

	return $DB->select($table, \%h);
}

################################################################################
# subroutine
################################################################################
#-------------------------------------------------------------------------------
# update user data
#-------------------------------------------------------------------------------
sub update_user_data {
	my ($self, $id, $form, $ext) = @_;
	my $ROBJ = $self->{ROBJ};

	$ROBJ->clear_form_err();

	my $up = $self->check_user_data($form, $ext);
	if (!$up) {
		return { ret=>10, errs => $ROBJ->form_err() };
	}

	my $DB = $self->{DB};
	my $r  = $DB->update_match($self->{table}, $up, 'id', $id);
	if ($r != 1) {
		return { ret=>-1, msg => '[Auth] DB update error.' };
	}
	if ($up->{pass}) {
		$DB->delete_match($self->{table} . '_sid', 'id', $id, '-pkey', $self->{sid_pkey});
	}
	if ($up->{disable}) {
		$DB->delete_match($self->{table} . '_sid', 'id', $id);
	}

	$self->save_log($id, 'update');
	return { ret => 0 };
}

#-------------------------------------------------------------------------------
# Check user's data
#-------------------------------------------------------------------------------
sub check_user_data {
	my ($self, $form, $ext, $new) = @_;
	my $ROBJ = $self->{ROBJ};
	my $DB   = $self->{DB};

	$ROBJ->clear_form_err();

	my %up;
	#---------------------------------------------------
	# ID
	#---------------------------------------------------
	if ($new) {
		my $id = $form->{id};
		$id =~ s/[\x00-\x1f]//g;
		$ROBJ->trim_dest($id);
		if ($id eq '') {
			$ROBJ->form_err('id', 'ID is empty.');

		} elsif ($self->{uid_match} && $id !~ /$self->{uid_match}/) {
			$ROBJ->form_err('id', 'ID is incorrect: %s', $id);

		} elsif (length($id) > $self->{uid_max_len}) {
			$ROBJ->form_err('id', 'Too long ID (max %d characters): %s', $self->{uid_max_len}, $id);

		} elsif ($DB->select_match_pkey1($self->{table}, 'id', $id)) {
			$ROBJ->form_err('id', 'ID already exists: %s', $id);
		}
		$up{id} = $id;
	}

	#---------------------------------------------------
	# name
	#---------------------------------------------------
	if ($new || exists($form->{name})) {
		my $name = $form->{name};
		$ROBJ->trim_dest($name);
		$name =~ s/[\r\n\0]//g;

		if ($name eq '') {
			$ROBJ->form_err('name', 'Name is empty.');
		} 
		if ($self->{name_notag} && $name =~ /[\"\'<>]/) {
			$ROBJ->form_err('name', 'The name cannot contain ", \', <, >.');
		}
		if ($ROBJ->mb_length($name) > $self->{name_max_len}) {
			$ROBJ->form_err('name', 'Too long name (max %d characters).', $self->{name_max_len});
		}
		$up{name} = $name;
	}

	#---------------------------------------------------
	# pass
	#---------------------------------------------------
	if ($new && $form->{pass} eq '' && $form->{crypted_pass} eq '') {
		$ROBJ->form_err('pass', 'Password is empty.');
	}

	if ($form->{pass} ne '') {
		my $pass = $form->{pass};
		if ($self->{pass_ignore} && $pass =~ /$self->{pass_ignore}/) {
			$ROBJ->form_err('pass', 'password is ignore: %s', $pass);

		} elsif (length($pass) < $self->{pass_min}) {
			$ROBJ->form_err('pass', 'Too short password (min %d characters).', $self->{pass_min});

		} elsif (defined $form->{pass2} && $pass ne $form->{pass2}) {
			$ROBJ->form_err('pass2', 'Mismatch password and retype password.');

		} else {
			$pass = $ROBJ->crypt_by_rand($pass);
			$up{pass} = $pass;
		}
	}
	if ($form->{crypted_pass}) { $up{pass}=$form->{crypted_pass}; }
	if ($form->{disable_pass}) { $up{pass}='*'; }

	#---------------------------------------------------
	# email
	#---------------------------------------------------
	if (exists($form->{email})) {
		my $email = $ROBJ->trim($form->{email});
		if ($email ne '' && $email !~ /^[\w\.\-\+]+\@[\w\-\+]+(?:\.[\w\-\+]+)*$/) {
			$ROBJ->form_err('email', "E-mail is incorrect: %s", $email);
		}
		$up{email} = $email;
	}

	#---------------------------------------------------
	# other
	#---------------------------------------------------
	if ($ext) {
		my %h = map { $_ => 1 } @{ $self->load_main_table_cols() };
		foreach(keys(%$ext)) {
			if ($h{$_}) {
				$ROBJ->form_err('', "'%s' cannot be used as extended columns.", $_);
				next;
			}
			$up{$_} = $ext->{$_};
		}
	}

	if ($ROBJ->form_err()) { return; }	# error exit

	if ($new) {
		$up{login_c} = 0;
		$up{fail_c}  = 0;
		$up{isadmin} = $form->{isadmin} ? 1 : 0;
		$up{disable} = $form->{disable} ? 1 : 0;
	} else {
		if (exists($form->{isadmin})) { $up{isadmin} = $form->{isadmin} ? 1 : 0; }
		if (exists($form->{disable})) { $up{disable} = $form->{disable} ? 1 : 0; }
	}

	return \%up;
}

sub check_pass_by_id {
	my ($self, $id, $pass) = @_;
	my $DB = $self->{DB};

	my $h = $DB->select_match_limit1($self->{table}, 'id', $id, '*cols', 'pass');
	if (!$h || $h->{'pass'} eq '*') { return; }
	return $self->check_pass($h->{'pass'}, $pass);
}

sub sudo {
	my $self = shift;
	my $func = shift;
	my @bak = ($self->{ok}, $self->{isadmin});
	$self->{ok} = $self->{isadmin} = 1;
	my $r = $self->$func(@_);
	($self->{ok}, $self->{isadmin}) = @bak;
	return $r;
}

################################################################################
# create database table
################################################################################
sub load_main_table_cols {
	my $self = shift;
	return [ qw(pkey id name pass email login_c login_tm fail_c fail_tm  disable isadmin) ];
}
sub create_user_table {
	my $self  = shift;
	my $DB    = $self->{DB};
	my $table = $self->{table};

	$DB->begin();

	my %cols;
	$cols{text}    = [ qw(id name pass email) ];
	$cols{int}     = [ qw(login_c login_tm fail_c fail_tm) ];
	$cols{flag}    = [ qw(disable isadmin) ];
	$cols{idx}     = [ qw(id email isadmin) ];
	$cols{unique}  = [ qw(id email) ];
	$cols{notnull} = [ qw(id name) ];
	$DB->create_table_wrapper($table, \%cols);

	undef %cols;
	$cols{text}    = [ qw(id sid) ];
	$cols{int}     = [ qw(login_tm) ];
	$cols{flag}    = [ qw() ];
	$cols{idx}     = [ qw(id sid login_tm) ];
	$cols{unique}  = [ qw() ];
	$cols{notnull} = [ qw(id sid login_tm) ];
	$cols{ref}     = { id => "$table.id" };
	$DB->create_table_wrapper("${table}_sid", \%cols);

	undef %cols;
	$cols{text}    = [ qw(id type msg ip host agent) ];
	$cols{int}     = [ qw(tm) ];
	$cols{flag}    = [ qw() ];
	$cols{idx}     = [ qw(id type ip tm) ];
	$cols{unique}  = [ qw() ];
	$cols{notnull} = [ qw(tm) ];
	# $cols{ref}     = { id => "$table.id" };	# Do not set, for illeagl ID.
	$DB->create_table_wrapper("${table}_log", \%cols);

	$DB->commit();
}

1;
