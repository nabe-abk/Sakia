#!/usr/bin/perl
use strict;
#-------------------------------------------------------------------------------
# Sakia initalizer
#						Copyright (C)2023 nabe@abk
#-------------------------------------------------------------------------------
my $LastUpdate = '2023.08.08';
################################################################################
# Default setting
################################################################################
my $BASE = './';
my $NAME;

my $GIT_SAKIA = 'git@github.com:nabe-abk/Sakia.git';
my $GIT_ASYS  = 'https://github.com/nabe-abk/asys.js';
#-------------------------------------------------------------------------------
# parse options
#-------------------------------------------------------------------------------
{
	my @ary;
	my $HELP = !@ARGV;
	my $err  = '';
	while(@ARGV) {
		my $x = shift(@ARGV);
		if ($x eq '-b') { $BASE =shift(@ARGV); next; }
		if ($x eq '-h') { $HELP =1; next; }
		push(@ary, $x);
	}
	$NAME = shift(@ary);

	if ($HELP) {
		print STDERR <<HELP;
Usage: $0 [options] <project-name>

Available options are:
  -b		Base directory (default: ./)
  -h		View this help
HELP
		exit;
	}

	if ($NAME eq '') {
		$err .= "Require project name argument.\n";
	}
	if ($NAME =~ /[^\w\-]/) {
		$err .= "Require name contains characters that cannot be used. [A-Za-z0-9_-]\n";
	}
	if ($err) {
		print STDERR $err;
		exit(1);
	}
}
print "Sakia system initalizer - (C)$LastUpdate nabe\@abk\n\n";

################################################################################
# main start
################################################################################
my $TARDIR = $BASE . $NAME;
if (!-d $TARDIR) {
	print "create directory: $TARDIR\n";
	mkdir($TARDIR);
}
#--------------------------------------------------------------------------------
# clone Sakia runtime from github
#--------------------------------------------------------------------------------
my $LIBDIR = "$TARDIR/lib";
&make_dir("lib");

if (!-d "$LIBDIR/Sakia/.git") {
	print "clone from $GIT_SAKIA\n";
	system("git -C '$LIBDIR' clone $GIT_SAKIA") && exit;
}
my $TPLDIR = "$LIBDIR/Sakia/_template";

#--------------------------------------------------------------------------------
# load Sakia lib
#--------------------------------------------------------------------------------
unshift(@INC, $LIBDIR);
require Sakia::Base;
my $ROBJ = new Sakia::Base;

#--------------------------------------------------------------------------------
# copy startup scripts
#--------------------------------------------------------------------------------
print "startup script copy:";
foreach(qw(.cgi .fcgi .httpd.pl)) {
	my $src = "$TPLDIR/startup$_";
	my $des = "$TARDIR/$NAME$_";
	print " $NAME$_";
	system("cp -p '$src' '$des'");
	chmod(0755, $des);
}
print "\n";
&copy_file('startup.conf.cgi', "$NAME.conf.cgi");

#--------------------------------------------------------------------------------
# copy other files
#--------------------------------------------------------------------------------
&make_dir ("lib/SakiaApp");
&copy_file("app.pm", "lib/SakiaApp/$NAME.pm");

&make_dir ('__cache', 0777);
&make_file('__cache/README', "Skeleton cache directory.\n\nNEVER ACCESS THIS from the web.\n");
&copy_file("htaccess_deny",  "__cache/.htaccess");

&make_dir ('skel');
&copy_file('htaccess_deny', 'skel/.htaccess');
&copy_file('_frame.html',   'skel/_frame.html');
&copy_file('_main.html',    'skel/_main.html');
&copy_file('test.html',     'skel/test.html');

&make_dir ('data', 0777);
&make_dir ('data/README',   "Private data directory.\n\nNEVER ACCESS THIS from the web.\n");
&copy_file('htaccess_deny', 'data/.htaccess');

&make_dir ('pub', 0777);
&make_file('pub/README', "Public data directory.\n");

&make_dir ('js');
&make_dir ('theme');
&make_file('theme/README', "CSS directory.\n");
&copy_file('theme.css',    'theme/theme.css');

&copy_file('htaccess_root', '.htaccess');


################################################################################
# subroutine
################################################################################
sub make_dir {
	my $dir = shift;
	my $mod = shift;
	print "create directory: $dir\n";
	mkdir("$TARDIR/$dir");
	if ($mod) {
		chmod($mod, "$TARDIR/$dir");
	}
}

sub copy_file {
	my $src = shift;
	my $des = shift;
	print "create file     : $des\n";

	my $lines = $ROBJ->fread_lines("$TPLDIR/$src");
	foreach(@$lines) {
		$_ =~ s/<\@NAME>/$NAME/g;
	}
	$ROBJ->fwrite_lines("$TARDIR/$des", $lines);
}

sub make_file {
	my $file  = shift;
	my $lines = shift;
	print "create file     : $file\n";
	$ROBJ->fwrite_lines("$TARDIR/$file", $lines);
}

