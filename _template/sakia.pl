#!/usr/bin/perl
use strict;
#-------------------------------------------------------------------------------
# Sakia initalizer
#						Copyright (C)2026 nabe@abk
#-------------------------------------------------------------------------------
my $LastUpdate = '2026.02.21';
################################################################################
# Default setting
################################################################################
my $BASE = './';
my $NAME;
my $LIB_NAME;
my $FORCE;
my $README=1;
my $UPDATE;

my $GIT_SAKIA = 'git@github.com:nabe-abk/Sakia.git';
#-------------------------------------------------------------------------------
# parse options
#-------------------------------------------------------------------------------
{
	my @ary;
	my $HELP = !@ARGV;
	my $err  = '';
	while(@ARGV) {
		my $x = shift(@ARGV);
		if ($x eq '-b') { $BASE=shift(@ARGV); next; }
		if ($x eq '-f') { $FORCE =1; next; }
		if ($x eq '-n') { $README=0; next; }
		if ($x eq '-h') { $HELP  =1; next; }
		if ($x eq '-u') { $UPDATE=1; next; }
		push(@ary, $x);
	}
	$NAME = shift(@ary);

	if ($HELP) {
		print STDERR <<HELP;
Usage: $0 [options] <project-name>

Available options are:
  -b		Base directory (default: ./)
  -f		Force overwrite
  -u		Update existing .cgi/.fcgi/.httpd.pl files
  -n		No README file
  -h		View this help
HELP
		exit;
	}

	if ($NAME eq './') {
		require Cwd;
		my $dir = Cwd::getcwd();
		$NAME   = $dir =~ m|([^/]+)$| ? $1 : '';
		print "Auto detect project name: $NAME\n";
		chdir('..');
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

$LIB_NAME = $NAME =~ s/-/_/rg;

################################################################################
# main start
################################################################################
my $TARDIR = $BASE . $NAME;
if ($UPDATE) {
	&update();
	exit;
}
if (!-d $TARDIR) {
	print "create directory: $TARDIR\n";
	mkdir($TARDIR);
}
#--------------------------------------------------------------------------------
# clone Sakia runtime from github
#--------------------------------------------------------------------------------
my $LIBDIR = "$TARDIR/lib";
&make_dir("lib");

if (!-d "$LIBDIR/Sakia/.git" && !-r "$TARDIR/.git/modules/lib/Sakia/index") {
	my $cmd;
	if (-d "$TARDIR/.git") {
		# clone for submodule
		print "submodule clone from $GIT_SAKIA\n";
		$cmd = "git -C '$TARDIR' submodule add $GIT_SAKIA lib/Sakia";
	} else {
		print "clone from $GIT_SAKIA\n";
		$cmd = "git -C '$LIBDIR' clone $GIT_SAKIA";
	}
	print "$cmd\n";
	system($cmd) && exit;
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
print "copy startup script:";
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
&copy_file("app.pm",         "lib/SakiaApp/$LIB_NAME.pm");
&copy_file("_htaccess_deny", "lib/.htaccess");
&copy_file("_htaccess_deny", "lib/.htaccess");

&make_dir ('__cache', 0777);
&make_file('__cache/README', "Skeleton cache directory.\n\nNEVER ACCESS THIS from the web.\n");
&copy_file("_htaccess_deny", "__cache/.htaccess");

&make_dir ('skel');
&copy_file('_htaccess_deny', 'skel/.htaccess');
my $files = $ROBJ->search_files("$TPLDIR/", { ext => '.html' });
foreach(@$files) {
	&copy_file($_, "skel/$_");
}

&make_dir ('data', 0777);
&make_file('data/README',    "Private data directory.\n\nNEVER ACCESS THIS from the web.\n");
&copy_file('_htaccess_deny', 'data/.htaccess');

&make_dir ('pub', 0777);
&make_file('pub/README',   "Public data directory.\n");
&make_file('pub/.gitkeep', '');

&make_dir ('js');
&make_dir ('theme');
&make_file('theme/README', "CSS directory.\n");
&copy_file('theme.css',    'theme/theme.css');

&copy_file('_htaccess_root', '.htaccess');
&copy_file('_gitignore',     '.gitignore');

################################################################################
# update mode
################################################################################
sub update {
	print "Update startup scripts.\n";
	# over write startup script
	my $TPLDIR = "$TARDIR/lib/Sakia/_template";

	foreach(qw(.cgi .fcgi .httpd.pl)) {
		my $src = "$TPLDIR/startup$_";
		my $des = "$TARDIR/$NAME$_";
		if (!-e $des) { next; }

		print " $des ";
		my ($smod, $ssize) = &get_lastmodified($src);
		my ($dmod, $dsize) = &get_lastmodified($des);
		if ($smod == $dmod && $ssize == $dsize) {
			print "skip\n";
			next;
		}
		system("cp -p '$src' '$des'");
		chmod(0755, $des);
		print "update\n";
	}
}

################################################################################
# subroutine
################################################################################
sub make_dir {
	my $dir = shift;
	my $mod = shift;
	if (-d "$TARDIR/$dir") { return; }

	print "create directory: $dir\n";
	mkdir("$TARDIR/$dir");
	if ($mod) {
		chmod($mod, "$TARDIR/$dir");
	}
}

sub copy_file {
	my $src = shift;
	my $des = shift;
	if (!$FORCE && -e "$TARDIR/$des") {
		print "already exists  : $des\n";
		return;
	}
	print "create file     : $des\n";

	my $lines = $ROBJ->fread_lines("$TPLDIR/$src");
	my $year  = (localtime())[5] + 1900;
	foreach(@$lines) {
		$_ =~ s/<\@NAME>/$NAME/g;
		$_ =~ s/<\@LIB_NAME>/$LIB_NAME/g;
		$_ =~ s/<\@YEAR>/$year/g;
	}
	$ROBJ->fwrite_lines("$TARDIR/$des", $lines);
}

sub make_file {
	my $file  = shift;
	my $lines = shift;
	if (!$README && $file =~ m|/README|) { return; }	# not create readme

	if (!$FORCE && -e "$TARDIR/$file") {
		print "already exists  : $file\n";
		return;
	}
	print "create file     : $file\n";
	$ROBJ->fwrite_lines("$TARDIR/$file", $lines);
}

sub get_lastmodified {
	my @st   = stat(shift);
	my $mod  = $st[9];		# last modified
	my $size = $st[7];
	return ($mod, $size);
}
