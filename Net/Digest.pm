use strict;
#-------------------------------------------------------------------------------
# Digest Authenticate module
#							(C)2024 nabe@abk
#-------------------------------------------------------------------------------
#
package Sakia::Net::Digest;
our $VERSION = '0.10';
#-------------------------------------------------------------------------------
use Digest::SHA;
################################################################################
# constructor
################################################################################
sub new {
	my $class= shift;
	my $ROBJ = shift;
	my $opt  = shift || {};
	my $self = { %$opt,
		realm		=> 'realm',
		algorithm	=> 'SHA-256',
		nonce_timeout	=> 60
	};
	$self->{ROBJ} = $ROBJ;

	return bless($self, $class);
}

################################################################################
# Auth
################################################################################
sub auth {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	my $r = $self->do_auth(@_);

	if ($r) {
		my $tm = time();
		$ROBJ->set_status(401);
		$ROBJ->set_header('WWW-Authenticate', "Digest realm=\"$self->{realm}\", algorithm=\"$self->{algorithm}\", nonce=\"$tm\"");
		return $r;
	}
	return 0;
}

sub do_auth {
	my $self = shift;
	my $func = shift;
	my $ROBJ = $self->{ROBJ};

	if (ref($func) ne 'CODE') {
		$ROBJ->msg("auth() need argument id to pass function.");
		return -1;
	}

	# Digest username="fasd", realm="realm", nonce="1719048031", uri="/path/", algorithm=SHA-256, response="9e5...957"
	# Digest username="aaa\"bbb", algorithm=MD5   // not support

	my $auth = $ENV{HTTP_AUTHORIZATION};
	if (!$auth) {
		return 1;
	}
	if ($auth !~ /^Digest +(.*)/i) {
		return 2;
	}
	my @ary = split(/\s*,\s*/, $1);
	my %opt;
	foreach(@ary) {
		if ($_ =~ /^([^=]+)="((?:[^\"]+|[\w\-]+))"$/) {
			my $k = $1;
			$k =~ tr/A-Z/a-z/;
			$opt{$k} = $2;
		}
	}

	if ($opt{realm} ne $self->{realm})    { return 3; }
	if ($opt{uri}   ne $ENV{REQUEST_URI}) { return 4; }
	my $tm = time();
	if ($opt{nonce} < ($tm - $self->{nonce_timeout}) || $tm<$opt{nonce}) {
		return 5;
	}

	# get user password
	my $id   = $opt{username};
	my $pass = &$func($id);
	if ($id =~ /\W/) { return 6; }
	if ($pass eq '') { return 7; }

	my $ha1 = Digest::SHA::sha256_hex("$id:$opt{realm}:$pass");
	my $ha2 = Digest::SHA::sha256_hex("$ENV{REQUEST_METHOD}:$opt{uri}");
	my $res = Digest::SHA::sha256_hex("$ha1:$opt{nonce}:$ha2");

	if ($opt{response} ne $res) { return 10; }

	$self->{id} = $id;
	return 0;
}

1;
