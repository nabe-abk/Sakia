#!/usr/bin/perl
use strict;
unshift(@INC, './lib');
#-------------------------------------------------------------------------------
# Sakia Startup routine (for CGI)
#					Copyright (C)2005-2023 nabe@abk
#-------------------------------------------------------------------------------
# Last Update : 2023/02/21
#
BEGIN {
	if ($] < 5.014) {
		my $v = int($]); my $sb = int(($]-$v)*1000);
		print "Content-Type: text/html;\n\n";
		print "Do not work with <u>Perl $v.$sb</u>.<br>Requires <strong>Perl 5.14 or newer</strong>.";
		exit(-1);
	}
};
#-------------------------------------------------------------------------------
eval {
	#---------------------------------------------------
	# Start timer
	#---------------------------------------------------
	my $timer;
	if ($ENV{SakiaTimer}) {
		require Sakia::Timer;
		$timer = Sakia::Timer->new();
		$timer->start();
	}

	#---------------------------------------------------
	# main
	#---------------------------------------------------
	require Sakia::Base;
	my $ROBJ = Sakia::Base->new();
	$ROBJ->{Timer} = $timer;

	$ROBJ->start();
	$ROBJ->finish();
};

#-------------------------------------------------
# error
#-------------------------------------------------
if (!$ENV{SakiaExit} && $@) {
	print <<HTML;
Status: 500 Internal Server Error\r
Content-Type: text/plain; charset=UTF-8\r
X-Br: <br>\r
\r
$@
HTML
}

