#!/usr/bin/perl
use v5.14;
use strict;
#-------------------------------------------------------------------------------
# Sakia system - startup routine (for FastCGI)
#					Copyright (C)2005-2026 nabe@abk
#-------------------------------------------------------------------------------
# Last Update : 2026-02-21
#
BEGIN {
	unshift(@INC, './lib');
	$0 =~ m|^(.*?)[^/]*$|;
	chdir($1);
}
use FCGI;
use Sakia::Base ();
use Sakia::AutoReload ();
BEGIN {
	if ($ENV{SakiaTimer}) { require Sakia::Timer; }
}

$SIG{CHLD} = 'IGNORE';	# for fork()

#-------------------------------------------------------------------------------
# socket open?
#-------------------------------------------------------------------------------
my $Socket;
my $Threads = int($ARGV[1]) || 10;
if ($Threads<1) { $Threads=1; }
{
	my $path = $ARGV[0];
	if ($path) {
		$Socket  = FCGI::OpenSocket($path, $ARGV[2] || 100);
		if ($path =~ /\.sock$/ && -S $path) {	# UNIX domain socket?
			chmod(0777, $path);
		}
	}
}

#-------------------------------------------------------------------------------
# Normal mode
#-------------------------------------------------------------------------------
if (!$Socket) {
	&fcgi_main_loop();
	exit(0);
}

#-------------------------------------------------------------------------------
# Socket/thread mode
#-------------------------------------------------------------------------------
{
	require threads;
	&create_threads( $Threads, $Socket );

	while(1) {
		sleep(3);
		my $exit_threads = $Threads - $#{[ threads->list() ]} - 1;
		if (!$exit_threads) { next; }

		&create_threads( $Threads, $Socket );
	}
}
exit(0);

sub create_threads {
	my $num  = shift;
	my $sock = shift;

	foreach(1..$num) {
		my $thr = threads->create(sub {
			my $sock = shift;
			my $req  = FCGI::Request( \*STDIN, \*STDOUT, \*STDERR, \%ENV, $sock );

			&fcgi_main_loop($req, 1);
			threads->detach();
		}, $sock);
		if (!defined $thr) { die "threads->create fail!"; }
	}
}

################################################################################
# FastCGI main loop
################################################################################
sub fcgi_main_loop {
	my $req    = shift || FCGI::Request();
	my $deamon = shift;

	my $modtime = (stat($0))[9];
	my $shutdown;
	while($req->Accept() >= 0) {
		eval {
			#-----------------------------------------------------
			# Timer start
			#-----------------------------------------------------
			my $timer;
			if ($ENV{SakiaTimer} ne '0' && $Sakia::Timer::VERSION) {
				$timer = Sakia::Timer->new();
				$timer->start();
			}

			#-----------------------------------------------------
			# update check
			#-----------------------------------------------------
			my $flag = &Sakia::AutoReload::check_lib();
			if ($flag) {
				$Sakia::Base::RELOAD = 1;
				require Sakia::Base;
				$Sakia::Base::RELOAD = 0;
			}

			#-------------------------------------------------------
			# init FastCGI
			#-------------------------------------------------------
			my $ROBJ = Sakia::Base->new();
			$ROBJ->{Timer}      = $timer;
			$ROBJ->{AutoReload} = $flag;
			$ROBJ->{ModRewrite} = $deamon;

			$ROBJ->init_for_fastcgi($req);

			#-----------------------------------------------------
			# main
			#-----------------------------------------------------
			$ROBJ->start();
			$ROBJ->finish();

			$shutdown = $ROBJ->{Shutdown};
		};
		#-----------------------------------------------------
		# error
		#-----------------------------------------------------
		if ($@ && !$ENV{SakiaExit}) {
			print <<HTML;
Status: 500 Internal Server Error
Content-Type: text/plain; charset=UTF8
X-FCGI-Br: <br>

$@
HTML
		}
		if ($shutdown) { last; }
		&Sakia::AutoReload::save_lib();

		#-----------------------------------------------------
		# self update check
		#-----------------------------------------------------
		if ($modtime != (stat($0))[9]) { last; }
	}
	$req->Finish();
}
