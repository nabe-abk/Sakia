use strict;
#-------------------------------------------------------------------------------
package Sakia::Auth;
use Sakia::AutoLoader;
our $VERSION = '3.03';
################################################################################
# constructor
################################################################################
sub new {
	my $class = shift;
	my $self = {
		ROBJ	=> shift,
		DB	=> shift,

		table		=> 'usr',
		expires		=> 365*86400,	# 1 year
		pass_min	=> 8,
		pass_ignore	=> '^\d+$',
		uid_match	=> '^[a-z][0-9a-z_]*$',
		uid_max_len	=> 16,
		name_max_len	=> 32,
		name_notag	=> 1,

		# security
		max_sessions	=> 1,
		logout_all	=> 0,
		fail_limit	=> 10,
		fail_sleep	=> 10*60,
		auto_login	=> 1,		# When not exists admin, allow auto login

	#	allow_ip	=> [],
	#	allow_host	=> [],
	#	admin_list	=> [],		# Can be administrators list
	#	admin_allow_ip	=> [],
	#	admin_allow_host=> [],
	#	admin_secret	=> undef,
	#	admin_max_sessions => undef,	# undef is same {max_sessions}

		# log
	#	stop_log	=> undef,	# Stop log to "$self->{table}_log" table.
	#	log_func	=> undef,	# External log
		log_text_max	=> 128,

		# extend
		user_change_cols=> ['name', 'email'],
		alt_uid		=> undef	# Column to use instead of login ID.
	};
	return bless($self, $class);
}

1;
