use strict;
#-------------------------------------------------------------------------------
# Base system for Sakia-System
#						Copyright(C)2005-2025 nabe@abk
#-------------------------------------------------------------------------------
package Sakia::Base;
#-------------------------------------------------------------------------------
our $VERSION = '3.01';
our $RELOAD;
my %StatCache;
my $StatCacheTM;
#-------------------------------------------------------------------------------
# constant
#-------------------------------------------------------------------------------
my $BR_NORMAL = 1;
my $BR_SUPER  = 2;
my $BR_CLEAR  = 4;
#-------------------------------------------------------------------------------
use Sakia::AutoLoader;
use Fcntl;
use Scalar::Util();
################################################################################
# constructor
################################################################################
sub new {
	my $self = {
		VERSION	=> $VERSION,

		# Global vars
		ENV	=> \%ENV,
		INC	=> \%INC,
		ARGV	=> \@ARGV,
		UID	=> $<,
		GID	=> $(,
		PID	=> $$,
		CMD	=> $0,
		STDIN	=> *STDIN,
		IsWindows=>$^O eq 'MSWin32',
		G	=> {},

		# Internal vars
		Status		=> 200,
		Headers		=> [],
		ContentType	=> 'text/html',
		CgiMode		=> 'CGI-Perl',
		LoadpmCache	=> {},
		FinishObjs	=> [],

		TmpTimeout	=> 3600,	# Temporary file timeout

		# locale setting
		SystemCode	=> 'UTF-8',
		TM		=> time,
		LC_WDAY		=> ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'],
		LC_AMPM		=> ['AM','PM'],
		LC_TIMESTAMP	=> '%Y-%m-%d %H:%M:%S',

		# for skeleton
		SkelExt		=> '.html',
		SkelDirs	=> [],
		SkelJumpCount	=> 0,
		SkelNestCount	=> 0,
		SkelMaxNest	=> 99,

		# error / debug
		Msg	=> [],
		Error	=> [],
		Debug	=> [],
		FormErr	=> undef
	};

	# init
	bless($self, shift);
	$self->{ROBJ} = $self;
	Scalar::Util::weaken( $self->{ROBJ} );

	# STAT cache init
	if ($StatCacheTM != $self->{TM}) {
		undef %StatCache;
		$StatCacheTM = $self->{TM};
	}

	# Init cache directory
	my $dir = $self->{_CacheDir} = $ENV{SakiaCacheDir} || '__cache/';
	if (-d $dir && -w $dir) {
		$self->{CacheDir} = $dir;
	}
	return $self;
}

################################################################################
# main
################################################################################
my $PageCacheChecker;
#-------------------------------------------------------------------------------
# start
#-------------------------------------------------------------------------------
sub start {
	my $self = shift;
	if ($PageCacheChecker && &$PageCacheChecker($self)) {
		return;
	}

	my $cgi = $0;
	if ($self->{IsWindows}) { $cgi =~ tr|\\|/|; }

	my $env;
	my $conf;
	if ($cgi =~ m!(?:^|/)([^/\.]*)[^/]*$!) {
		$env  = $1 .  '.env.cgi';
		$conf = $1 . '.conf.cgi';
	} else {
		$env = $conf = '__(internal_error)__';
	}

	if (-r $env) { $self->_call($env); }				# run .env file
	$self->init_tm();
	$self->{ConfResult} = $self->_call($self->{ConfFile} || $conf);	# run .conf file
	$self->init_path();

	if (@{$self->{Error}}) {
		$self->set_status(500);
		$self->output_error('text/html');	## mskip
		$self->exit(-1);
	}

	# run main module
	my $main = $self->{Main};
	if ($main && $main->can('main')) {
		$main->main();
	} else {
		$self->output($self->{ConfResult});
	}
}

sub init_tm {
	my ($self, $tz) = @_;
	my $h = $self->time2hash( $self->{TM} );
	$self->{Now} = $h;
	$self->{Timestamp} = $self->print_ts($h->{_ary});
}

sub init_path {
	my $self = shift;
	$ENV{PATH_INFO} eq '/__getcpy' && $self->set_header('X-Sakia-System', "Ver$VERSION (C)nabe\@abk");

	if ($self->{InitPath} || !$ENV{REQUEST_URI}) { return; }
	$self->{InitPath} = 1;

	# ModRewrite flag
	my $rewrite = $self->{ModRewrite} ||= $ENV{ModRewrite};
	if (!defined $rewrite && exists $ENV{REDIRECT_URL} && $ENV{REDIRECT_STATUS}==200) {
		$self->{ModRewrite} = $rewrite = 1;
	}

	$ENV{QUERY_STRING}='';
	my $request = $ENV{REQUEST_URI};
	if ((my $x = index($request, '?')) >= 0) {
		$ENV{QUERY_STRING} = substr($request, $x+1);	# Apache's bug, treat "%3f" as "?"
		$request = substr($request, 0, $x);
	}
	if (index($request, '%') >= 0) {
		$request =~ s/%([0-9A-Fa-f][0-9A-Fa-f])/chr(hex($1))/eg;
	}

	# analyze Basepath
	my $script   = $ENV{SCRIPT_NAME};
	my $basepath = $self->{Basepath} ||= $ENV{Basepath};
	if (!defined $basepath) {
		my $path = $script;
		while($path ne '') {
			$path = substr($path, 0, rindex($path,'/')+1);
			if (index($request, $path) == 0) { last; }
			chop($path);
		}
		$self->{Basepath} = $basepath = $path;
	}

	# for Apache's bug, rewrite '//' to '/'
	$ENV{PATH_INFO_orig} = $ENV{PATH_INFO};
	$ENV{PATH_INFO} = substr($request, ($rewrite ? length($basepath)-1 : length($script)) );

	# set myself
	if (!exists $self->{myself}) {
		if ($rewrite) {
			$self->{myself}  = $self->{myself2} = $basepath;
		} elsif (index($request, $script) == 0) {
			$self->{myself}  = $script;
			$self->{myself2} = $script . '/';
		} else {
			# DirectoryIndex mode
			$self->{myself}  = $basepath;
			$self->{myself2} = $script . '/';
		}
	}

	# set ServerURL
	if (!$self->{ServerURL}) {
		my $port = int($ENV{SERVER_PORT});
		my $protocol = ($port == 443) ? 'https://' : 'http://';
		$self->{ServerURL} = $protocol . $ENV{SERVER_NAME} . (($port != 80 && $port != 443) ? ":$port" : '');
	} else {
		substr($self->{ServerURL},-1) eq '/' && chop($self->{ServerURL});
	}
}

################################################################################
# Finish
################################################################################
sub finish {
	my $self = shift;

	# Finish
	foreach my $obj (reverse(@{ $self->{FinishObjs} })) {
		$obj->FINISH();
	}

	if ($self->{Develop} && @{$self->{Error}}) {
		$self->output_error();
	}

	if (!$self->{CgiCache}) { return; }

	#-------------------------------------------------------------
	# memory limiter
	#-------------------------------------------------------------
	my $limit = $self->{MemoryLimit};
	if (!$limit) { return; }

	sysopen(my $fh, "/proc/$$/status", O_RDONLY) or return;
	<$fh> =~ /VmHWM:\s*(\d+)/;
	close($fh);

	my $size = ($1 || 0)<<10;
	if ($limit<$size) { $self->{Shutdown} = 1; }
}

#-------------------------------------------------------------------------------
# exit
#-------------------------------------------------------------------------------
sub exit {
	my $self = shift;
	my $ext  = shift;
	$self->{Exit}  = $ext;
	$self->{Break} = $BR_SUPER;
	$ENV{SakiaExit} = 1;
	die("exit($ext)");
}

################################################################################
# executor
################################################################################
sub execute {
	my $self = shift;
	my $sub  = shift;
	if (ref($sub) ne 'CODE') {
		my ($pack, $file, $line) = caller;
		$self->error_from("$file line $line: $self->{CurrentSrc}", "[executor] Can't execute: %s", $sub);
		return ;
	}

	#-------------------------------------------------------------
	# check nest
	#-------------------------------------------------------------
	$self->{SkelNestCount}++;
	if ($self->{SkelNestCount} > $self->{SkelMaxNest}) {
		my $err = $self->error_from('', '[executor] Too depth nested call() (max %d).', $self->{SkelMaxNest});
		$self->{SkelNestCount}--;
		$self->{Break} = $BR_SUPER;
		return "<b>$err</b>";
	}

	#-------------------------------------------------------------
	# execute
	#-------------------------------------------------------------
	my $output='';
	my $line;
	my $ret;
	local($self->{IsFunction});
	{
		my $v_ref;
		$ret = eval {
			return &$sub($self, \$output, \$line, $v_ref);
		};
		$v_ref && ($self->{v} = $$v_ref);
	}
	$self->{SkelNestCount}--;
	if ($ENV{SakiaExit}) { die("exit($self->{Exit})"); }

	#-------------------------------------------------------------
	# eval error
	#-------------------------------------------------------------
	my $break = int($self->{Break});
	if (!$break && $@) {
		$self->set_status(500);
		my $err = $@;
		foreach(split(/\n/, $err)) {
			$self->error_from("$self->{CurrentSrc} line $line", "[executor] $_");	## mskip
		}
	}

	#-------------------------------------------------------------
	# break
	#-------------------------------------------------------------
	if ($break) {
		$self->{Break} = undef;
		if ($break & $BR_CLEAR) { $output = ''; }
		if ($break & $BR_SUPER) { die "Break"; }

		if ($self->{JumpFile}) {
			my $file = $self->{JumpFile};
			my $skel = $self->{JumpSkel};
			$self->{JumpFile} = undef;
			$self->{JumpSkel} = undef;
			if (($self->{SkelJumpCount}++) < $self->{SkelMaxNest}) {
				$output .= $self->__call($file, $skel, $self->{JumpLevel}, @{ $self->{JumpArgv} });
			} else {
				my $err = $self->error_from('', "[executor] Too many jump() (max %d).", $self->{SkelMaxNest});
				$output .= "<b>$err</b>";
			}
		}
	}

	return $self->{IsFunction} ? $ret : $output;
}

################################################################################
# call
################################################################################
sub call {
	my $self = shift;
	my $skel = shift;
	if (substr($skel,0,2) eq './') {
		$skel = ($self->{CurrentSkel} =~ m|^(.*/)| ? $1 : '') . substr($skel,2);
	}
	my ($file, $level) = $self->find_skeleton($skel);
	if ($file eq '') {
		$self->error('%s() failed. File not found: %s', 'call', $skel);
		return;
	}
	return $self->__call($file, $skel, $level, @_);
}

sub _call {	# with file path
	my $self = shift;
	my $file = shift;
	return $self->__call($file, undef, undef, @_);
}

#-------------------------------------------------------------------------------
# low level call
#-------------------------------------------------------------------------------
my %SkelCache;
sub __call {
	my $self = shift;
	my $file = shift;
	my $skel = shift;
	my $level= shift;
	my $file_tm = ($StatCache{$file} ||= [ stat($file) ])->[9];

	my $cache_file = $self->{CacheDir} && $self->{CacheDir} . ($file =~ s/([^\w\.\#\x80-\xff])/'%' . unpack('H2', $1)/reg) . '.cache';
	if (!$file_tm) {
		if ($cache_file) { unlink($cache_file); }
		$self->error('%s() failed. File not found: %s', '__call', $file);
		return;
	}

	#-------------------------------------------------------------
	# load from cache
	#-------------------------------------------------------------
	my $com_tm = $self->{CompilerTM} ||= $self->get_lastmodified( 'lib/Sakia/Base/Compiler' . $self->{CompilerVer} . '.pm' );
	my $cache  = $SkelCache{$file} || {};

	# load from cache file
	if ($cache_file && ($cache->{file_tm} != $file_tm || $cache->{compiler_tm} != $com_tm)) {
		$cache = $self->load_cache($cache_file);

		if (!$cache || $cache->{file_tm} != $file_tm || $cache->{compiler_tm} != $com_tm) {
			unlink($cache_file);
			$cache = undef;
		}
	}

	#-------------------------------------------------------------
	# compile file to perl
	#-------------------------------------------------------------
	$cache = $cache || {
		arybuf		=> $self->compile($cache_file, $file, $skel, $file_tm),
		file_tm		=> $file_tm,
		compiler_tm	=> $com_tm
	};

	#-------------------------------------------------------------
	# compile stage 2
	#-------------------------------------------------------------
	my $arybuf = $cache->{arybuf};
	if (!$cache->{executable}) {
		my $error;
		foreach (@$arybuf) {
			$_ = eval $_;
			if ($@) { $self->error_from($file, "[perl-compiler] $@"); $error=1; }	## mskip
		}
		if ($error) { return; }
		$cache->{executable} = 1;

		if (-r $cache_file) {	# if not exist $cache_file, when occur error in compile()
			$SkelCache{$file} = $cache;
		}
	}

	#-------------------------------------------------------------
	# run
	#-------------------------------------------------------------
	local ($self->{argv}, $self->{CurrentSrc}, $self->{CurrentSkel}, $self->{CurrentNest});
	$self->{argv}        = \@_;
	$self->{CurrentSrc}  = $file;
	$self->{CurrentSkel} = $skel;
	$self->{CurrentNest} = $self->{SkelNestCount};
	$self->{CurrentLevel}= $level;

	return $self->execute( $arybuf->[0] );
}

#-------------------------------------------------------------------------------
# load from cache file
#-------------------------------------------------------------------------------
sub load_cache {
	my $self = shift;
	my $file = shift;
	if (!-r $file) { return; }

	local($/) = "\0";		# change delimiter
	my $lines = $self->fread_lines($file);
	foreach(@$lines) { chop(); }	# chop for delimiter

	shift(@$lines);			# discard warning message
	if (shift(@$lines) ne "Version=3\n") { return; }

	return {
		compiler_tm	=> shift(@$lines),
		file_tm		=> shift(@$lines),
		arybuf		=> $lines
	};
}

################################################################################
# control syntax
################################################################################
#-------------------------------------------------------------------------------
# break
#-------------------------------------------------------------------------------
sub break {
	my ($self, $break_level) = @_;
	$self->{Break} = int($break_level) || 1;
	die("Break");
}
sub break_clear {	# clear output
	my $self = shift;
	$self->{Break} = $BR_CLEAR;
	die("Break");
}
sub superbreak {	# exit call nest
	my $self = shift;
	$self->{Break} = $BR_SUPER;
	die("Break");
}
sub superbreak_clear {
	my $self = shift;
	$self->{Break} = $BR_CLEAR | $BR_SUPER;
	die("Break");
}

#-------------------------------------------------------------------------------
# jump
#-------------------------------------------------------------------------------
sub jump_clear {
	my $self = shift;
	$self->{Break} = $BR_CLEAR;
	return $self->jump(@_);
}
sub superjump {
	my $self = shift;
	$self->{Break} = $BR_SUPER;
	return $self->jump(@_);
}
sub superjump_clear {
	my $self = shift;
	$self->{Break} = $BR_CLEAR | $BR_SUPER;
	return $self->jump(@_);
}
sub jump {
	my $self = shift;
	my $skel = shift;
	$self->{Break} ||= 1;

	my ($file, $level) = $self->find_skeleton($skel);
	if ($file eq '') {
		return $self->error('%s() failed. File not found: %s', 'jump', $skel);
	}
	$self->{JumpFile} = $file;
	$self->{JumpSkel} = $skel;
	$self->{JumpArgv} = \@_;
	$self->{JumpLevel}= $level;
	die("Break");
}
sub _jump {
	my $self = shift;
	$self->{Break}    = 1;
	$self->{JumpFile} = shift;
	$self->{JumpSkel} = undef;
	$self->{JumpArgv} = \@_;
	$self->{JumpLevel}= undef;
	die("Break");
}

#-------------------------------------------------------------------------------
# exec begin block
#-------------------------------------------------------------------------------
sub exec {
	my $self = shift;
	my $code = shift;
	local ($self->{argv});
	$self->{argv} = \@_;
	return $self->execute($code);
}

#-------------------------------------------------------------------------------
# continue skeleton
#-------------------------------------------------------------------------------
sub continue {
	my $self = shift;
	my $skel = $self->{CurrentSkel};
	my $c_lv = $self->{CurrentLevel};
	if (!$skel || $c_lv eq '') {
		die "Can not continue($skel, $c_lv)";
	}
	my ($file, $level) = $self->find_skeleton($skel, $c_lv-1);
	if (!$file) {
		die "Can not find continue() file(level=$c_lv)";
	}

	$self->{Break}     = 1;
	$self->{JumpFile}  = $file;
	$self->{JumpSkel}  = $skel;
	$self->{JumpArgv}  = $self->{argv};
	$self->{JumpLevel} = $level;
	die("Break");
}

################################################################################
# Skeleton system
################################################################################
#-------------------------------------------------------------------------------
# Regist/Unregist skeleton dir
#-------------------------------------------------------------------------------
sub regist_skeleton {
	my $self = shift;
	my $dir  = shift;
	my $level= shift || 0;
	if ($dir eq '') { 
		$self->error("%s() failed. Illegal arguments: %s", 'regist_skeleton', join(', ', $dir,$level));
		return;
	}

	my $dirs = $self->{SkelDirs};
	push(@$dirs, { level=>$level, dir=>$dir });
	$self->{SkelDirs} = [ sort {$b->{level} <=> $a->{level}} @$dirs ];
}

sub unregist_skeleton {
	my $self = shift;
	my $lv   = shift;
	my $dirs = $self->{SkelDirs};
	$self->{SkelDirs} = [ grep { $_->{level} != $lv } @$dirs ];
	return grep { $_->{level}==$lv } @$dirs;
}

#-------------------------------------------------------------------------------
# Find skeleton
#-------------------------------------------------------------------------------
sub find_skeleton {
	my $self  = shift;
	my $name  = shift;
	my $level = defined $_[0] ? shift : 0x7fffffff;
	$name =~ s|//+|/|g;

	# relative path
	if ($name =~ m|^\.\.?/| && $self->{CurrentSkel} =~ m|^(.*/)|) {
		my $dir = $1;
		$dir =~ s|//+|/|g;
		while($name =~ m|^(\.\.?)/(.*)|) {
			$name = $2;
			if ($1 eq '.') { next; }
			if ($1 eq '..') {
				$dir =~ s|[^/]+/+$||;
			}
		}
		$name = $dir . $name;
	}
	if ($name =~ m|[^\w/\.\-\x80-\xff]| || $name =~ m|\.\./|) {
		$self->error('Not allow characters are used in skeleton name: %s', $name);
		return;
	}

	$name .= $self->{SkelExt};
	foreach(@{ $self->{SkelDirs} }) {
		my $lv = $_->{level};
		if ($lv > $level) { next; }
		my $file = $_->{dir} . $name;
		if (-r $file) {
			return wantarray ? ($file, $lv) : $file;
		}
	}
	return;		# not found
}

################################################################################
# output system
################################################################################
#-------------------------------------------------------------------------------
# headers
#-------------------------------------------------------------------------------
sub set_header {
	my ($self, $name, $val) = @_;
	if ($name eq 'Status') { $self->{Status} = $val; return; }
	push(@{ $self->{Headers} }, "$name: $val\r\n");
}
sub set_status {
	my $self = shift;
	$self->{Status} = shift;
}
sub set_lastmodified {
	my $self = shift;
	my $date = $self->rfc_date(shift);
	$self->{LastModified} = $date;
	$self->set_header('Last-modified', $date);
}
sub set_content_type {
	my $self = shift;
	$self->{ContentType} = shift;
}
sub set_charset {
	my $self = shift;
	$self->{Charset} = shift;
}

#-------------------------------------------------------------------------------
# output headers
#-------------------------------------------------------------------------------
sub output_http_headers {
	my $self = shift;
	print $self->http_headers(@_);
}
sub http_headers {
	my ($self, $ctype, $charset, $clen) = @_;
	if ($self->{No_httpheader}) { return''; }

	# Status
	my $header;
	my $status = $self->{Status};
	if ($self->{HTTPD}) {
		$header  = "HTTP/1.0 $status\r\n";
		my $st = $self->{HTTPD_state};
		$header .= "Connection: " . ($st->{keep_alive} ? 'keep-alive' : 'close') . "\r\n";
	} else {
		$header  = "Status: $status\r\n";
	}
	$header .= join('', @{ $self->{Headers} });

	# Content-Type;
	$ctype   ||= $self->{ContentType};
	$charset ||= $self->{SystemCode};
	if ($clen ne '') {
		$header .= "Content-Length: $clen\r\n";
	}
	$header .= <<HEADER;
Content-Type: $ctype; charset=$charset;\r
X-Content-Type-Options: nosniff\r
Cache-Control: no-cache\r
\r
HEADER
	return $header;
}

#-------------------------------------------------------------------------------
# output
#-------------------------------------------------------------------------------
sub output {
	my $self  = shift;
	my $body  = shift;
	my $ctype   = shift || $self->{ContentType};
	my $charset = shift || $self->{Charset};

	# Last-modified
	if ($self->{Status}==200 && $self->{LastModified} && $ENV{HTTP_IF_MODIFIED_SINCE} eq $self->{LastModified}) {
		$self->{Status}=304;
	}

	my $html = $self->http_headers($ctype, $charset, length($body));
	my $head = $ENV{REQUEST_METHOD} eq 'HEAD';
	if (!$head && $self->{Status} != 304) {
		$html .= $body;
		my $c = $self->{Status}==200 && $self->{OutputCache};
		if ($c) { $$c = $html; }
	}
	print $html;
}

#-------------------------------------------------------------------------------
# page cache system
#-------------------------------------------------------------------------------
sub regist_output_cache {
	my $self  = shift;
	$self->{OutputCache} = shift;
}
sub regist_cache_cheker {
	my $self  = shift;
	$PageCacheChecker = shift;
}

################################################################################
# Module functions
################################################################################
sub loadapp {
	my $self = shift;
	return $self->_loadpm('SakiaApp::' . shift, @_);
}

sub loadpm {
	my $self  = shift;
	my $pm    = shift;
	my $cache = $self->{LoadpmCache};
	if ($cache->{$pm}) { return $cache->{$pm}; }
	my $obj = $self->_loadpm('Sakia::' . $pm, @_);
	if (ref($obj) && $obj->{__CACHE_PM}) {
		$cache->{$pm} = $obj;
	}
	return $obj;
}

sub _loadpm {
	my $self = shift;
	my $pm   = shift;
	my $pm_file = $pm . '.pm';
	$pm_file =~ s|::|/|g;

	if (! $INC{$pm_file}) {
		eval { require $pm_file; };
		if ($@) { delete $INC{$pm_file}; die($@); }

		no strict 'refs';
		if (! *{"${pm}::debug"}{CODE}) {
			*{"${pm}::debug"}      = \&_export_debug;
			*{"${pm}::debug_json"} = \&_export_debug_json;
		}
	}

	my $obj = $pm->new($self, @_);
	if (ref($obj)) {
		$obj->{ROBJ}	&& Scalar::Util::weaken( $obj->{ROBJ} );	# Prevent circular reference
		$obj->{__FINISH}&& push(@{$self->{FinishObjs}}, $obj);
	}
	return $obj;
}

sub _export_debug {
	my $self = shift;
	$self->{ROBJ}->_debug(@_);						## safe
}
sub _export_debug_json {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	$ROBJ->_debug(map { ref($_) ? $ROBJ->generate_json($_) : $_ } @_);	## safe
}
################################################################################
# Query/Form
################################################################################
#-------------------------------------------------------------------------------
# Form
#-------------------------------------------------------------------------------
sub read_form {
	if ($ENV{REQUEST_METHOD} ne 'POST') { return; }
	return &_read_form(@_);		# in Base_2.pm
}

#-------------------------------------------------------------------------------
# Query
#-------------------------------------------------------------------------------
sub read_query {
	my $self = shift;
	if ($self->{Query}) { return $self->{Query}; }
	return ($self->{Query} = $self->parse_query($ENV{QUERY_STRING}, @_));
}
sub parse_query {
	my $self = shift;
	my $q    = shift;
	my $arykey = shift || {};
	my %h;
	foreach(split(/&/, $q)) {
		my ($key, $val) = split(/=/, $_, 2);
		$key =~ s|[\x00-\x20]||g;
		$val =~ tr/+/ /;
		$val =~ s/%([0-9a-fA-F][0-9a-fA-F])/chr(hex($1))/eg;

		$self->from_to(\$val);		# check code

		$val =~ s/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]//g;	# Except TAB LF CR
		$val =~ s/\r\n?/\n/g;
		if ($arykey->{$key} || substr($key,-4) eq '_ary') {
			my $a = $h{$key} ||= [];
			push(@$a, $val);
			next;
		}
		$h{$key} = $val;
	}
	return \%h;
}

#-------------------------------------------------------------------------------
# Make Query
#-------------------------------------------------------------------------------
sub make_query {
	return &_make_query(shift, '&', @_);
}
sub make_query_amp {
	return &_make_query(shift, '&amp;', @_);
}
sub _make_query {
	my $self = shift;
	my $amp  = shift;
	my $h    = ref($_[0]) ? shift : $self->{Query};
	my $add  = shift;
	my $q;
	foreach(keys(%$h)) {
		my $k = $_;
		my $v = $h->{$k};
		$self->encode_uricom($k);
		foreach(@{ ref($v) ? $v : [$v] }) {
			my $x = $_;
			$self->encode_uricom($x);
			$q .= ($q eq '' ? '' : $amp ) . "$k=$x";
		}
	}
	if ($add ne '') { $q .= "$amp$add"; }
	return $q;
}

################################################################################
# Cookie functions
################################################################################
sub get_cookie {
	my $self = shift;
	my %h;
	foreach (split(/; */, $ENV{HTTP_COOKIE})) {
		my ($key, $val) = split('=', $_, 2);
		$val =~ s/%([0-9A-Fa-f][0-9A-Fa-f])/chr(hex($1))/eg;
		if (ord($val)) {	# start char isn't 0x00
			$h{$key} = $val;

		} else {		# array or hash
			my ($flag, @ary) = split(/\0/, substr($val,1));
			$flag = ord($flag);
			if ($flag == 1) {	# array
				$h{$key} = \@ary;
			} elsif ($flag == 2) {	# hash
				$h{$key} = { my %x = @ary };
			}
		}
	}
	return ($self->{Cookie} = \%h);
}

################################################################################
# charset convert
################################################################################
#-------------------------------------------------------------------------------
# convert string
#-------------------------------------------------------------------------------
sub from_to {
	my $self = shift;
	my $str  = shift;
	my $from = shift || $self->{SystemCode};
	my $to   = shift || $self->{SystemCode};
	if (ref($str) ne 'SCALAR') { my $s=$str; $str=\$s; }
	if ($$str =~ /^[\x00-\x0D\x10-\x1A\x1C-\x7E]*$/) { return $$str; }

	$Encode::VERSION || require Encode;

	if ($from =~ /UTF.*8/i) {
		Encode::_utf8_on($$str);
		$$str = Encode::encode($to, $$str);
	} else {
		Encode::from_to($$str, $from, $to);
	}
	return $$str;
}

#-------------------------------------------------------------------------------
# mb_substr
#-------------------------------------------------------------------------------
sub mb_substr {
	my $self = shift;
	return $self->mb_substr_code($self->{SystemCode}, @_);
}
sub mb_substr_code {
	my $self = shift;
	my $code = shift;
	my $txt  = shift;
	my $substr = ($#_ == 0) ? sub { substr($_[0],$_[1]) } : sub { substr($_[0],$_[1],$_[2]) };
	if ($txt =~ /^[\x00-\x0D\x10-\x1A\x1C-\x7E]*$/) { return &$substr($txt, @_); }

	$Encode::VERSION || require Encode;

	if ($code !~ /^UTF.*8/i) {
		my $utf8 = Encode::decode($code, $txt);
		$utf8 = &$substr($utf8, @_);
		return Encode::encode($code, $utf8);
	}
	Encode::_utf8_on($txt);
	$txt = &$substr($txt, @_);
	Encode::_utf8_off($txt);
	return $txt;
}

#-------------------------------------------------------------------------------
# mb_length
#-------------------------------------------------------------------------------
sub mb_length {
	my $self = shift;
	return $self->mb_length_code($self->{SystemCode}, @_);
}
sub mb_length_code {
	my $self = shift;
	my $code = shift;
	my $txt  = shift;
	if ($txt !~ /[\x7f-\xff]/) { return length($txt); }

	$Encode::VERSION || require Encode;

	if ($code =~ /^UTF.*8/i) {
		Encode::_utf8_on($txt);
	} else {
		$txt = Encode::decode($code, $txt);
	}
	return length($txt);
}

################################################################################
# Locale
################################################################################
sub load_locale {
	my ($self, $file) = @_;
	my $h = $self->{MsgTrans} = $self->fread_hash_cached($file);

	$self->{LANG}    = $h->{LANG};
	$self->{LC_NAME} = $h->{LC_NAME};
	$self->{LC_WDAY} = [ split(/\s*,\s*/, $h->{LC_WDAY}) ];
	$self->{LC_AMPM} = [ split(/\s*,\s*/, $h->{LC_AMPM}) ];
	$self->{LC_TIMESTAMP} = $h->{LC_TIMESTAMP};
}

sub translate {
	my $self = shift;
	my $msg  = shift;
	$msg = $self->{MsgTrans}->{$msg} || $msg;
	if (@_) { return sprintf($msg, @_); }
	return $msg;
}

################################################################################
# Message System
################################################################################
sub msg {
	my $self = shift;
	my $msg  = $self->translate(@_);
	$self->esc_dest($msg);
	push(@{$self->{Msg}}, $msg);
	return $msg;
}
sub clear_msg {
	my $self = shift;
	return $self->_clear_msg('Msg', @_);
}
sub _clear_msg {
	my $self = shift;
	my $type = shift;
	my $ch   = shift || "<br>\n";
	my $msg  = $self->{$type};
	$self->{$type} = [];
	return $ch =~ /%m/ ? join('', map { $ch =~ s/%m/$_/rg } @$msg) : join($ch, @$msg);
}

sub warning {
	my $self = shift;
	my $msg  = $self->translate(@_);
	$self->esc_dest($msg);
	push(@{$self->{Debug}}, '[Warning] ' . $msg);
	return $msg;
}

#-------------------------------------------------------------------------------
# Fatal error
#-------------------------------------------------------------------------------
sub error {
	my $self = shift;
	return $self->error_from('', @_);
}
sub error_from {
	my $self = shift;
	my $from = shift || $self->make_call_from();
	my $msg  = $self->translate(@_) . " ($from)";
	$self->esc_dest($msg);
	push(@{$self->{Error}}, $msg);
	return $msg;
}
sub clear_error {
	my $self = shift;
	return $self->_clear_msg('Error', @_);
}

sub make_call_from {
	my $self = shift;
	my @froms;
	my $i=2;
	while(1) {
		my ($pack, $file, $line) = caller($i++);
		$file = substr($file, rindex($file, '/') +1);
		push(@froms, "$file $line");
		if (!($pack eq __PACKAGE__ || $pack =~ /::DB::/) || $i>9) { last; }
	}
	my $from = pop(@froms);
	while(@froms) {
		$from = pop(@froms) . " ($from)";
	}
	return $from;
}

sub output_error {
	my $self = shift;
	my $ctype= shift;
	if ($ENV{SERVER_PROTOCOL} && $ctype) {
		$self->output_http_headers($ctype, @_);
	}
	if ($ENV{SERVER_PROTOCOL} && $self->{ContentType} eq 'text/html') {
		print "<hr><strong>(ERROR)</strong><br>\n",$self->clear_error();
	} else {
		print "\n(ERROR) ",$self->clear_error("\n"),"\n";
	}
}

################################################################################
#
# Service functions
#
################################################################################
################################################################################
# Read file
################################################################################
#-------------------------------------------------------------------------------
# Read all lines from file
#-------------------------------------------------------------------------------
sub fread_lines {
	my ($self, $file, $opt) = @_;

	my $fh;
	my @lines;
	if ( !sysopen($fh, $file, O_RDONLY) ) {
		my $err = $opt->{no_error} ? 'warning' : 'error';
		$self->$err("File can't read '%s'", $file);
	} else {
		$self->read_lock($fh);
		@lines = <$fh>;
		close($fh);
	}

	my $lines = \@lines;
	if ($opt->{postproc}) {
		$lines = &{$opt->{postproc}}($opt->{self} || $self, $lines, $opt);
	}
	return $lines;
}

#-------------------------------------------------------------------------------
# Read standard hash file
#-------------------------------------------------------------------------------
sub fread_hash {
	my ($self, $file, $opt) = @_;
	my %_opt = %{$opt || {}};
	$_opt{postproc} = \&parse_hash;
	return $self->fread_lines($file, \%_opt);
}

sub parse_hash {
	my ($self, $lines, $opt) = @_;
	my ($blk, $prev, $key, $val);
	my %h;
	foreach(@$lines) {
		# Block mode
		if (defined $blk) {
			if ($_ eq $blk) {
				chomp($val);
				$h{$key} = $val;
				undef $blk;
			} else {
				$val .= $_;
			}
			next;
		}
		# Normal mode
		chomp($_);
		my $f = ord($_);
		if (!$f || $f == 0x23) { next; }		# '#' is comment
		if ($f==0x2a && (my $x=index($_, '=<<')) >0) {	# *data=<<__BLOCK is block
			$key = substr($_, 1, $x-1);
			$blk = substr($_, $x+3) . "\n";
			$val = '';
			next;
		}
		# key=val
		my $x = index($_, '=');
		if ($x == -1) { $prev=$_; next; }
		$key = $x==0 ? $prev : substr($_, 0, $x);
		$prev= undef;
		$h{$key} = substr($_, $x+1);
	}
	return \%h;
}

################################################################################
# Read file with cache
################################################################################
my %FileCache;

sub fread_lines_cached {
	my ($self, $file, $opt) = @_;

	my $cache = $FileCache{$file} ||= {};
	my $key   = join('//',$opt->{postproc},$opt->{self});
	my $c     = $cache->{$key} || {};

	my $st   = $StatCache{$file} ||= [ stat($file) ];
	my $size = $st->[7];
	my $mod  = $st->[9];

	my $lines;
	if ($self->{CgiCache} && 0<$mod && $mod == $c->{modified} && $size == $c->{size}) {
		$lines = $c->{lines};
	} else {
		$lines = $self->fread_lines( $file, $opt );
		$cache->{$key} = {lines => $lines, modified => $mod, size => $size };
	}
	if ($self->{CgiCache}) {
		if ($opt->{clone}) {
			return $self->clone($lines);
		}
		if (ref($lines) eq 'ARRAY') { return [ my @x = @$lines ]; }
		if (ref($lines) eq 'HASH' ) { return { my %x = %$lines }; }
	}
	return $lines;
}

sub fread_hash_cached {
	my ($self, $file, $opt) = @_;
	my %_opt = %{$opt || {}};
	$_opt{postproc} = \&parse_hash;
	return $self->fread_lines_cached($file, \%_opt);
}

sub remove_file_cache {
	my $self = shift;
	my $file = shift;

	delete $StatCache{$file};
	delete $FileCache{$file};
}

################################################################################
# Other file functions
################################################################################
sub get_lastmodified {
	my $self = shift;
	my $file = shift;
	return -r $file ? ($StatCache{$file} ||= [ stat($file) ])->[9] : undef;
}

sub touch {
	my $self = shift;
	my $file = shift;
	if (!-e $file) { $self->fwrite_lines($file, []); return; }
	my ($now) = $self->{TM};
	utime($now, $now, $file);
}

#-------------------------------------------------------------------------------
# lock
#-------------------------------------------------------------------------------
sub read_lock {
	my ($self, $fh) = @_;
	$self->flock($fh, $self->{IsWindows} ? &Fcntl::LOCK_EX : &Fcntl::LOCK_SH );
}
sub write_lock {
	my ($self, $fh) = @_;
	$self->flock($fh, &Fcntl::LOCK_EX );
}
sub write_lock_nb {
	my ($self, $fh) = @_;
	$self->flock($fh, &Fcntl::LOCK_EX | &Fcntl::LOCK_NB );
}
sub flock {
	my ($self, $fh, $mode) = @_;
	if ($self->{IsWindows}) {
		# Windows is not run double lock
		if ($self->{_WinLock}->{$fh}) { return 100; }
		$self->{_WinLock}->{$fh} = 1;
	}
	return flock($fh, $mode);
}

#-------------------------------------------------------------------------------
# Search files
#-------------------------------------------------------------------------------
#	$opt->{ext}		file's extension
#	$opt->{all}		include '.*' files
#	$opt->{dir}		include directory
#	$opt->{dir_only}	exclude non directory
#
sub search_files {
	my $self = shift;
	my $dir  = shift;
	my $opt  = shift || {};
	$opt->{dir} ||= $opt->{dir_only};

	opendir(my $fh, $dir) || return [];
	my $ext = $opt->{ext};
	if (ref($ext) eq  'ARRAY') {
		$ext = { map {$_ => 1} @$ext };
	} elsif ($ext ne '' && ref($ext) ne 'HASH') {
		$ext = { $ext => 1 };
	}

	my @filelist;
	foreach(readdir($fh)) {
		if ($_ eq '.' || $_ eq '..')  { next; }
		if (!$opt->{all} && substr($_,0,1) eq '.') { next; }
		my $isDir = -d "$dir$_";
		if ((!$opt->{dir} && $isDir) || ($opt->{dir_only} && !$isDir)) { next; }
		if ($ext && ($_ !~ /(\.\w+)$/ || !$ext->{$1})) { next; }
		push(@filelist, $_ . ($isDir ? '/' : ''));
	}
	closedir($fh);

	return \@filelist;
}

################################################################################
# String functions
################################################################################
#-------------------------------------------------------------------------------
# encode URI
#-------------------------------------------------------------------------------
sub encode_uri {
	my $self = shift;
	return $self->encode_uri_dest(join('',@_));
}
sub encode_uri_dest {
	my $self = shift;
	foreach(@_) {
		$_ =~ s/([^\w!\#\$\(\)\*\+,\-\.\/:;=\?\@\~&%])/'%' . unpack('H2',$1)/eg;
	}
	return join('',@_);
}

# compaitible encodeURIComponent() without '/', ':'.
sub encode_uricom {
	my $self = shift;
	return $self->encode_uricom_dest(join('',@_));
}
sub encode_uricom_dest {
	my $self = shift;
	foreach(@_) {
		$_ =~ s/([^\w!\(\)\*\-\.\~\/:])/'%' . unpack('H2',$1)/eg;
	}
	return join('',@_);
}

#-------------------------------------------------------------------------------
# escape html/xml tags
#-------------------------------------------------------------------------------
my %TAGESC = ('&'=>'&amp;', '<'=>'&lt;', '>'=>'&gt;', '"'=>'&quot;', "'"=>'&apos;');
my %UNESC  = reverse(%TAGESC);
sub esc {
	my $self = shift;
	return $self->esc_dest(join('',@_));
}
sub esc_amp {
	my $self = shift;
	return $self->esc_amp_dest(join('',@_));
}
sub esc_dest {
	my $self = shift;
	foreach(@_) {
		$_ =~ s/(<|>|"|')/$TAGESC{$1}/g;
	}
	return join('',@_);
}
sub esc_amp_dest {
	my $self = shift;
	foreach(@_) {
		$_ =~ s/(&|<|>|"|')/$TAGESC{$1}/g;
	}
	return join('',@_);
}
sub esc_xml {
	my $self = shift;
	return $self->esc_xml_dest(join('',@_));
}
sub esc_xml_dest {
	my $self = shift;
	foreach(@_) {
		$_ =~ s/&(amp|lt|gt|quot|apos|#\d+|#x[0-9A-Fa-f]+);/\x01$1;/g;
		$_ =~ s/(&|<|>|"|')/$TAGESC{$1}/g;
		$_ =~ tr/\x01/&/;
	}
	return join('',@_);
}

sub unesc {
	my $self = shift;
	return $self->unesc_dest(join('',@_));
}
sub unesc_dest {
	my $self = shift;
	foreach(@_) {
		$_ =~ s/&(amp|lt|gt|quot);/$UNESC{"&$1;"}/g;
	}
	return join('',@_);
}

#-------------------------------------------------------------------------------
# other
#-------------------------------------------------------------------------------
sub trim {
	my $self = shift;
	return $self->trim_dest(join('',@_));
}
sub trim_dest {
	my $self = shift;
	foreach(@_) {
		$_ =~ s/^\s+//;
		$_ =~ s/\s+$//;
	}
	return join('',@_);
}

sub normalize {
	my $self = shift;
	return $self->normalize_dest(join('',@_));
}
sub normalize_dest {
	my $self = shift;
	$self->trim_dest(@_);
	foreach(@_) {
		$_ =~ s/[ \t]+/ /g;
		$_ =~ s/[\x00-\x09\x0b-\x1f]//g;
	}
	return join('',@_);
}

sub join_msg {
	my $self = shift;
	my $ch   = shift;
	return join($ch, grep { $_ ne '' } @_);
}

################################################################################
# Date functions
################################################################################
#-------------------------------------------------------------------------------
# RFC date
#-------------------------------------------------------------------------------
# Sun, 06 Nov 1994 08:49:37 GMT  ; RFC 822, updated by RFC 2822
sub rfc_date {
	my $self = shift;
	my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime(shift);

	my($wd, $mn);
	$wd = substr('SunMonTueWedThuFriSat',$wday*3,3);
	$mn = substr('JanFebMarAprMayJunJulAugSepOctNovDec',$mon*3,3);

	return sprintf("$wd, %02d $mn %04d %02d:%02d:%02d GMT"
		, $mday, $year+1900, $hour, $min, $sec);
}

#-------------------------------------------------------------------------------
# W3C date
#-------------------------------------------------------------------------------
sub w3c_date {
	my $self = shift;
	my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime(shift);
	return sprintf("%04d-%02d-%02dT%02d:%02d:%02d+00:00"
		,$year+1900, $mon+1, $mday, $hour, $min, $sec);
}

#-------------------------------------------------------------------------------
# make time hash
#-------------------------------------------------------------------------------
sub time2hash {
	my $self = shift;
	my $tm   = shift || $self->{TM};

	my %h;
	$h{_ary} = [ localtime($tm) ];
	( $h{sec},  $h{min},  $h{hour},
	  $h{_day}, $h{_mon}, $h{year},
	  $h{_wday},$h{yday}, $h{isdst}) = @{$h{_ary}};
	$h{year} +=1900;
	$h{_mon} ++;
	$h{mon} = sprintf("%02d", $h{_mon});
	$h{day} = sprintf("%02d", $h{_day});
	return \%h;
}

#-------------------------------------------------------------------------------
# timestamp to UNIX time
#-------------------------------------------------------------------------------
my @UT_DAYS = (0,0,31,59,90,120,151,181,212,243,273,304,334,365,396);

sub ts2time {
	my $self = shift;
	if ($_[0] !~ /^(\d+)\-(\d+)\-(\d+)(?: (\d+):(\d+):(\d+))?/) { return; }
	return $self->tmlocal($1,$2,$3,$4,$5,$6);
}
sub tmlocal {
	my $self = shift;
	if (!defined $self->{TZ}) {	# if UTC+9 set TZ=9
		my @x = localtime(86400);
		$self->{TZ} = $x[2] - ($x[3]==1 ? 24 : 0);
	}
	my $y = $_[1]<3 ? $_[0]-1  : $_[0];
	my $m = $_[1]<3 ? $_[1]+12 : $_[1];
	my $z = int(($y-1968)/4) - ($y>2000 ? int(($y-2000)/100) : 0) + ($y>2000 ? int(($y-2000)/400) : 0);
	return (($y-1970)*365 + $UT_DAYS[$m] + $_[2] + $z -1)*86400 + $_[3]*3600 + $_[4]*60 + $_[5] - $self->{TZ}*3600;
}

#-------------------------------------------------------------------------------
# print formatted time
#-------------------------------------------------------------------------------
# print_ts($UTC);		# Standard SQL timestamp
# print_tm($UTC);		# local
# print_tmf($format, $UTC);	# with format
#
sub print_ts {
	my $self = shift;
	return $self->print_tmf('%Y-%m-%d %H:%M:%S', @_);
}
sub print_tm {
	my $self = shift;
	return $self->print_tmf($self->{LC_TIMESTAMP}, @_);
}
sub print_tmf {
	my $self = shift;
	my $fmt  = shift;
	my $tm   = shift // $self->{TM};

	# This macro like 'strftime(3)' function.
	# compatible : %Y %y %m %d %I %H %M %S %w %s %e and %a %p
	my ($s, $m, $h, $D, $M, $Y, $wd, $yd, $isdst) = ref($tm) ? @$tm : localtime($tm);
	my %h;
	$h{s} = $tm;
	$h{j} = $yd;
	$h{y} = sprintf("%02d", $Y % 100);
	$h{Y} = $Y + 1900;
	$h{m} = sprintf("%02d", $M+1);
	$h{d} = sprintf("%02d", $D);
	$h{H} = sprintf("%02d", $h);		# 00-23
	$h{M} = sprintf("%02d", $m);
	$h{S} = sprintf("%02d", $s);
	$h{I} = sprintf("%02d", $h % 12);	# 00-11

	$h{a}  = $self->{LC_WDAY}->[$wd];
	$h{p}  = $self->{LC_AMPM}->[ 12 <= $h ? 1 : 0 ];
	$fmt =~ s/%(\w)/$h{$1}/g;
	return $fmt;
}

1;
