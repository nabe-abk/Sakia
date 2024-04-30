use strict;
package Sakia::Base;
#-------------------------------------------------------------------------------
my $BASE64 = '8RfoZYxLBkqCuAyUDO9b/eQFMd0ln47IzcHKPvGgsXhj.pEmV3wSi5TrNt126JWa';
################################################################################
# Compile skeleton
################################################################################
sub compile {
	my ($self, $cache_file, $file, $skel, $file_tm) = @_;

	#-------------------------------------------------------------
	# log for debug
	#-------------------------------------------------------------
	my $logfile = $self->{CompilerLog};
	if ($logfile ne '' && (-d $logfile || $self->mkdir($logfile)) ) {
		my $file = $skel;
		$file =~ tr|/|-|;
		$file =~ s/[^\w\-\.~]/_/g;
		$logfile .= $file;
	} else {
		undef $logfile;
	}
	#-------------------------------------------------------------
	# compile
	#-------------------------------------------------------------
	if ($cache_file) { unlink($cache_file); }

	my $c = $self->loadpm('Base::Compiler' . $self->{CompilerVer});
	$c->{default_pragma} = $self->{DefaultPragma};

	my $lines = $self->fread_lines($file);
	my ($errors, $arybuf) = $c->compile($lines, $skel, $logfile);
	if ($errors) {
		$self->set_status(500);
	}

	if ($cache_file && $errors == 0) {
		$self->save_cache($cache_file, $file, $file_tm, $arybuf);
	}
	return $arybuf;
}

#-------------------------------------------------------------------------------
# save to cache file
#-------------------------------------------------------------------------------
sub save_cache {
	my ($self, $cache_file, $file, $file_tm, $arybuf) = @_;
	my @lines;
	my $tm = $self->{Timestamp} || "UTC:$self->{TM}";
	push(@lines, <<TEXT . "\0");
# $tm : Generate from '$file';
#-------------------------------------------------------------------------------
# [WARNING] Don't edit this file. If you edit this, will be occoued error.
#-------------------------------------------------------------------------------
TEXT
	push(@lines, "Version=3\n\0");
	push(@lines, ($self->{CompilerTM}) . "\0");
	push(@lines, $file_tm . "\0");

	foreach (@$arybuf) {
		$_ =~ s/\0//g;		# Just in case
		push(@lines, "$_\0");	# routines
	}
	$self->fwrite_lines($cache_file, \@lines);
}

################################################################################
# Read form
################################################################################
# call from read_form in Base.pm
#
#	opt.max_size		Max form size (byte)
#	opt.str_max_chars	A wide character is one character
#	opt.txt_max_chars	
#	opt.allow_multi		Allow multipart
#	opt.multi_max_size	Max multipart form size
#	opt.multi_buf_size	Data read buffer size
#	opt.use_temp		Store file data to temporary
#
sub _read_form {
	my $self = shift;
	if ($self->{POST_ERR}) { return; }
	if ($self->{Form}) { return $self->{Form}; }

	my $opt = shift || ($self->{FormOpt} ||= $self->{FormOptFunc} && $self->execute($self->{FormOptFunc}));
	if ($self->{POST_ERR}) {
		return $self->_read_form_exit($self->{POST_ERR});
	}

	my $ctype = $ENV{CONTENT_TYPE};
	my $multi = $ctype =~ m|^multipart/form-data;|;
	if ($multi) {
		if (exists($opt->{allow_multi}) && !$opt->{allow_multi}) {
			return $self->_read_form_exit('Not allow multipart/form-data.');
		}
	}
	my $length = int($ENV{CONTENT_LENGTH});
	my $max    = $multi ? $opt->{multi_max_size} : $opt->{max_size};
	if ($max && $length > $max) {
		return $self->_read_form_exit('Form data too large (max %.1fMB).', $max/1048576);
	}
	if ($multi) {
		return $self->_read_multipart_form($opt, $ctype, $length);
	}

	# x-www-form-urlencoded
	my $h = $self->{Form} ={};

	read($self->{STDIN}, my $data, $ENV{CONTENT_LENGTH});
	foreach(split(/&/, $data)) {
		my ($k, $v) = split(/=/, $_, 2);
		$k =~ tr/+/ /;
		$k =~ s/%([0-9a-fA-F][0-9a-fA-F])/chr(hex($1))/eg;
		$v =~ tr/+/ /;
		$v =~ s/%([0-9a-fA-F][0-9a-fA-F])/chr(hex($1))/eg;
		$self->check_form_data($h, $opt, $k, $v);
	}
	$self->{POST} = 1;
	return $h;
}

sub _read_form_exit {
	my $self = shift;
	$self->{POST_ERR} ||= 1;
	$self->msg(@_);

	my $size = $ENV{CONTENT_LENGTH};
	while(0<$size) {
		# Prevent borken pipe
		read($self->{STDIN}, my $x, 256*1024);
		$size -= 256*1024;
	}
	return;
}

#-------------------------------------------------------------------------------
# Check form data
#-------------------------------------------------------------------------------
sub check_form_data {
	my ($self, $form, $opt, $k, $v) = @_;

	my $is_ary = ($k =~ s/^(.+)(?:_ary|\[\])$/${1}_ary/);
	my $type   = substr($is_ary ? $1 : $k,-4);

	if (!ref($v) && $type ne '_bin') {		# ref($v) is file
		$self->from_to( \$v );			# check char code
		$v =~ s/[\x00-\x08\x0B-\x1F\x7F]//g;	# remove ctrl code except TAB LF

		my $max = $type eq '_txt' ? $opt->{txt_max_chars} : $opt->{str_max_chars};
		if ($max && $max<$self->mb_length($v)) {
			$self->msg("Form data '%s' is too long and has been limited to %d characters.", $k, $max);
			$v = $self->mb_substr($v, 0, $max);
		}
	}

	if ($is_ary) {
		push(@{$form->{$k} ||= [] }, $v);
	} else {
		$form->{$k} = $v;
	}
}

#-------------------------------------------------------------------------------
# multipart/form-data  RFC1867, RFC2388
#-------------------------------------------------------------------------------
sub _read_multipart_form {
	my ($self, $opt, $ctype, $clen) = @_;

	binmode($self->{STDIN});	# for Windows
	my $use_temp = $opt->{use_temp};

	if ($ctype !~ /boundary=("?)(.*)\1/) {
		return $self->_read_form_exit('Failed to load multipart form.');
	}
	my $bound = $2;

	my $buf = $self->loadpm('Base::BufferedRead', $self->{STDIN}, $clen, $opt->{multi_buf_size});
	$buf->read("--$bound\r\n");

	$bound = "\r\n--$bound";
	my $h = {};
	my $err = 1;
	while(!$buf->{end}) {
		my $key;
		my $fname;
		while(1) {
			my $line = $buf->read("\r\n");
			if ($line eq '') { last; }
			if ($line =~ /^Content-Disposition:(.*)$/i) {
				$line = $1;
				if    ($line =~ /name=([^\s\";]+)/i)      { $key = $1; }
				elsif ($line =~ /name="((?:\\\"|.)*?)"/i) { $key = $1 =~ s/\\"/"/rg; }
				if    ($line =~ /filename=([^\s\";]+)/i)      { $fname = $1; }
				elsif ($line =~ /filename="((?:\\\"|.)*?)"/i) { $fname = $1 =~ s/\\"/"/rg; }
			}
		}
		if (!defined $key) { next; }	# last data

		my $val;
		if (defined $fname) {
			$fname =~ s/=\?([\w\-]*)\?[Bb]\?([A-Za-z0-9\+\/=]*)\?=/
				require MIME::Base64;
				require Encode;
				my $mime_code = $1;
				my $str = MIME::Base64::decode_base64($2);
				Encode::from_to($str, $mime_code, $self->{SystemCode});
				$str
			/eg;
			$fname =~ tr|\\|/|;
			$fname =~ s|^.*/([^/]*)$|$1|;
			$fname =~ s/[\x00-\x08\x0A-\x1F\x7F\"]//g;	# Remove CTRL code and '"'

			if ($use_temp) {
				my ($fh, $file) = $self->open_tmpfile();
				if ($fh) {
					my $size = $buf->read_to_file($fh, $bound, $clen);
					close($fh);
					$val = {
						tmp	=> $file,	# tmp file name
						name	=> $fname,
						size	=> $size
					};
					if ($size==0) {
						unlink($file);
						delete $val->{tmp};
					}
				} else {
					$val = $buf->read($bound);	# Throw away file data
				}

			} else {	# Read file to var
				$val = {
					data	=> '',
					name	=> $fname
				};
				$val->{size} = $buf->read_to_var(\($val->{data}), $bound, $clen);
			}
		} else {
			# Normal value
			$val = $buf->read($bound);
		}
		$self->check_form_data($h, $opt, $key, $val);

		# check data end
		my $line = $buf->read("\r\n");
		if ($line eq '--') { $err=0; last; }
	}
	if ($err) {
		return $self->_read_form_exit('Failed to load multipart form.');
	}

	$self->{POST} = 1;
	$self->{Form} = $h;
	return $h;
}

################################################################################
# Form and Security
################################################################################
#-------------------------------------------------------------------------------
# Form error system
#-------------------------------------------------------------------------------
sub form_err {
	my $self = shift;
	if (!@_) { return $self->{FormErr}; }
	my $name = shift;
	my $msg  = $self->translate(@_);
	my $h = $self->{FormErr} ||= { _order => [] };
	if (!exists($h->{$name})) {
		push(@{$h->{_order}}, $name);
	}
	$h->{$name} = $msg;
}

sub clear_form_err {
	my $self = shift;
	my $err  = $self->{FormErr};
	$self->{FormErr} =undef;
	return $err;
}

#-------------------------------------------------------------------------------
# Rand string and nonce
#-------------------------------------------------------------------------------
sub generate_rand_string {
	my $self = shift;
	my $len  = shift || 20;
	my $func = shift;
	my $gen  = $ENV{REMOTE_ADDR};
	my $R    = $ENV{REMOTE_PORT} + rand(0xffffffff);
	my $str  ='';
	foreach(1..$len) {
		my $c = (ord(substr($gen, $_, 1)) + int(rand($R))) & 0xff;
		$str .= $func ? &$func($c) : chr($c);
	}
	return $str;
}
sub generate_nonce {
	my $self = shift;
	my $base = $BASE64 =~ tr|/.|-_|r;
	$self->generate_rand_string(shift, sub {
		my $c = shift;
		return substr($base, $c & 63, 1);
	});
}

#-------------------------------------------------------------------------------
# crypt
#-------------------------------------------------------------------------------
my @S_RAND = (0xb5d8f3c,0x96a4072,0x492c3e6,0x6053399,0xae5f1a8,0x5bf1227,0x02a7e6f,0x4b0bd91);

sub crypt_by_rand {
	my $self = shift;
	return $self->crypt_by_string($_[0], $self->generate_rand_string(20));
}

sub crypt_by_string {
	my ($self, $secret, $gen) = @_;

	my ($x,$y) = (0,0);
	my $len = length($gen);
	for(my $i=0; $i<$len; $i++) {
		my $c = ord(substr($gen, $i, 1));
		$x += $c * $S_RAND[  $i    & 7];
		$y += $c * $S_RAND[ ($i+4) & 7];
	}

	my $salt = '';		# 16 byte salt
	for(my $i=0; $i<48; $i+=6) {
		$salt .= substr($BASE64, ($x>>$i) & 63,1) . substr($BASE64, ($y>>$i) & 63,1)
	}
	return  $self->crypt($secret, $salt);
}

my $CryptMode;
sub crypt {
	my $self = shift;
	my ($x, $salt) = @_;
	if (substr($salt, 0, 1) eq '$') { return crypt($x, $salt); }

	if (!defined $CryptMode) {
		$CryptMode ||= 8<length(crypt('', '$6$')) ? '$6$' : 0;	# SHA512
		$CryptMode ||= 8<length(crypt('', '$5$')) ? '$5$' : 0;	# SHA256
		$CryptMode ||= 8<length(crypt('', '$1$')) ? '$1$' : 0;	# MD5
		$CryptMode ||= '';
	}
	return $CryptMode ? crypt($x, "$CryptMode$salt") : crypt($x, $salt);
}

################################################################################
# Cookie functions
################################################################################
sub clear_cookie {
	my $self = shift;
	my $name = shift;
	$self->set_cookie($name, '', -1, @_);
}

sub set_cookie {
	my ($self, $name, $val, $exp, $_opt) = @_;
	my $opt = {
		path	=> $self->{Basepath},
		samesite=> 'Lax',
		httponly=> 1,
		secure	=> $self->{ServerURL} =~ /^https/i,
	%{$_opt || {}} };

	if (ref($val) eq 'ARRAY') {
		$val = "\0\1\0" . join("\0", @$val);	# 0x00 0x01
	} elsif (ref($val) eq 'HASH') {
		$val = "\0\2\0" . join("\0", %$val);	# 0x00 0x02
	}
	$self->encode_uricom_dest($name, $val);
	my $c = "$name=$val";

	if ($exp ne '') {
		$c .= '; max-age='. int($exp);
	}
	$c .= '; path=' . $self->encode_uricom($opt->{path});

	if ($opt->{domain}) {
		$c .= '; domain=' . $self->esc($opt->{domain});
	}

	$c .= $opt->{httponly} ? '; httponly' :	'';
	$c .= $opt->{secure}   ? '; secure'   : '';
	$c .= $opt->{samesite} ? "; samesite=$opt->{samesite}" : '';
	if ($opt->{append}) {
		$c .= '; ' . $opt->{append};
	}

	$self->set_header('Set-Cookie', $c);
}

################################################################################
# Write file
################################################################################
sub fwrite_lines {
	my ($self, $file, $lines, $opt) = @_;
	if (ref $lines ne 'ARRAY') { $lines = [$lines]; }

	my $fail_flag=0;
	my $fh;
	my $append = $opt->{append} ? O_APPEND : 0;
	if ( !sysopen($fh, $file, O_CREAT | O_WRONLY | $append) ) {
		$self->error("Can't write file: %s", $file);
		close($fh);
		return 1;
	}
	binmode($fh);
	$self->write_lock($fh);
	if (! $append) {
		truncate($fh, 0);	# File size is 0
		seek($fh, 0, 0);
	}
	foreach(@$lines) {
		print $fh $_;
	}
	$self->remove_file_cache($file);
	close($fh);
	return;
}

sub fappend_lines {
	my ($self, $file, $lines, $opt) = @_;
	my %_opt = %{$opt || {}};
	$_opt{append} = 1;
	return $self->fwrite_lines($file, $lines, \%_opt);
}

#-------------------------------------------------------------------------------
# Write standard hash file
#-------------------------------------------------------------------------------
sub fwrite_hash {
	my ($self, $file, $h, $opt) = @_;

	my @ary;
	my $append = $opt->{append};
	foreach(keys(%$h)) {
		my $val = $h->{$_};
		if (ref $val || (!$append && $val eq '')) { next; }
		if ($_ =~ /[\r\n=]/ || substr($_,0,1) eq '*') { next; }
		if (0 <= index($val, "\n")) {
			my $bl = '__END_BLK__';
			while(0<=index($val,$bl)) {
				$bl = '__END_BLK_' . substr(rand(),2);
			}
			push(@ary, "*$_=<<$bl\n$val\n$bl\n");
		} else {
			push(@ary, "$_=$val\n");
		}
	}
	if ($file eq '') { return \@ary; }
	return $self->fwrite_lines($file, \@ary, $opt);
}

sub fappend_hash {
	my ($self, $file, $h, $opt) = @_;
	my %_opt = %{$opt || {}};
	$_opt{append}   = 1;
	$_opt{postproc} = \&parse_hash;
	return $self->fwrite_hash($file, $h, \%_opt);
}

#-------------------------------------------------------------------------------
# read/write JSON file
#-------------------------------------------------------------------------------
sub fread_json {
	my ($self, $file, $opt) = @_;
	my %_opt = %{$opt || {}};
	$_opt{postproc} = \&parse_json;
	return $self->fread_lines($file, \%_opt);
}

sub fread_json_cached {
	my ($self, $file, $opt) = @_;
	my %_opt = %{$opt || {}};
	$_opt{postproc} = \&parse_json;
	$_opt{clone} = 1;
	return $self->fread_lines_cached($file, \%_opt);
}

sub fwrite_json {
	my ($self, $file, $data, $opt) = @_;
	return $self->fwrite_lines($file, $self->generate_json($data), $opt);
}

################################################################################
# Edit file
################################################################################
sub fedit_readlines {
	my ($self, $file, $opt) = @_;

	my $fh;
	if ( !sysopen($fh, $file, O_CREAT | O_RDWR | ($opt->{append} ? O_APPEND : 0)) ) {
		my $err = $opt->{no_error} ? 'warning' : 'error';
		$self->error("Can't open file for %s: %s", 'edit', $file);
	}
	binmode($fh);

	# lock
	my $method = $opt->{non_block} ? 'write_lock_nb' : ($opt->{read_lock} ? 'read_lock' : 'write_lock');
	my $r = $self->$method($fh);
	if (!$r) { close($fh); return; }

	my @lines = <$fh>;
	$self->remove_file_cache($file);
	return ($fh, \@lines);
}

sub fedit_writelines {
	my ($self, $fh, $lines, $opt) = @_;
	if (ref $lines ne 'ARRAY') { $lines = [$lines]; }

	seek($fh, 0, 0);	# seek to file top
	foreach(@$lines) {
		print $fh $_;
	}
	truncate($fh, tell($fh));
	close($fh);
	return;
}

sub fedit_exit {
	my ($self, $fh) = @_;
	close($fh);
}

################################################################################
# File operations
################################################################################
sub symlink {
	my ($self, $src, $des) = @_;
	my $d2  = $des;
	while((my $x = index($src,'/')+1) > 0) {
		if(substr($src, 0, $x) ne substr($d2, 0, $x)) { last; }
		$src = substr($src, $x);
		$d2  = substr($d2,  $x);
	}
	if (ord($src) != 0x2f && substr($src,0,2) ne '~/') {
		$d2 =~ s|/| $src = "../$src";'/' |eg;
	}
	my $r = symlink($src, $des);
	if (!$r) {
		$self->error('Create symbolic link error: "%s" to "%s"', $src, $des);
		return 1;
	}
	return 0;
}

sub copy_file {
	my ($self, $src, $des) = @_;
	my ($data, $fh);

	if (!sysopen($fh, $src, O_RDONLY) ) {
		$self->error("Can't read file: %s", $src);
		return 1;
	}
	$self->read_lock($fh);
	my $size = (stat($fh))[7];
	sysread($fh, $data, $size);
	close($fh);

	if (!sysopen($fh, $des, O_WRONLY | O_CREAT | O_TRUNC) ) {
		$self->error("Can't write file: %s", $des);
		return 2;
	}
	$self->write_lock($fh);
	syswrite($fh, $data, $size);
	close($fh);
	return 0;
}

sub move_file {
	my ($self, $src, $des) = @_;
	if (!-f $src) { return 1; }
	if (rename($src, $des)) { return 0; }	# success

	# copy and delete
	my $r = $self->copy_file($src, $des);
	if (!$r) {
		$self->remove_file($src);
	}
	return $r;
}

sub remove_file {
	my $self = shift;
	return unlink( $_[0] );
}

################################################################################
# Directory functions
################################################################################
sub mkdir {
	my ($self, $dir) = @_;
	if (-e $dir) { return -1; }
	my $r = mkdir( $dir );		# 0:fail 1:Success
	if (!$r) {
		$self->error("Failed to make directory: %s", $dir);
	}
	return $r;
}

sub copy_dir {
	my ($self, $src, $des, $mode) = @_;
	if (substr($src, -1) ne '/') { $src .= '/'; }
	if (substr($des, -1) ne '/') { $des .= '/'; }
	return $self->_dir_copy($src, $des)
}
sub _copy_dir {		# Recursive func
	my ($self, $src, $des) = @_;
	$self->mkdir($des) || return -1;
	my $files = $self->search_files( $src, {dir=>1, all=>1} );
	my $error = 0;
	foreach(@$files) {
		my $file = $src . $_;
		if (-d $file) {
			$error += $self->_copy_dir( "$file", "$des$_" );
		} else {
			$error += $self->copy_file($file, "$des$_") && 1;
		}
	}
	return $error;
}

sub remove_dir {	# Recursive func
	my ($self, $dir) = @_;
	if ($dir eq '') { return; }
	if (substr($dir, -1) eq '/') { chop($dir); }
	if (-l $dir) {	# is symbolic link
		return unlink($dir);
	}

	$dir .= '/';
	my $files = $self->search_files( $dir, {dir=>1, all=>1});
	foreach(@$files) {
		my $file = $dir . $_;
		if (-d $file) { $self->dir_delete( $file ); }
		  else { unlink( $file ); }
	}
	return rmdir($dir);
}

################################################################################
# Temporary functions
################################################################################
sub get_tmpdir {
	my $self  = shift;
	my $dir = $self->{Temp} || $self->{CacheDir} . 'tmp';
	$dir =~ s|/*$|/|;
	if (!-d $dir) {
		$self->mkdir($dir);
	}
	$self->tmpwatch( $dir );
	return $dir;
}

sub open_tmpfile {
	my $self = shift;
	my $dir  = $self->get_tmpdir();
	if (!-w $dir && !$self->mkdir($dir)) {
		$self->error("Can't write temporary directory: %s", $dir);
		return ;
	}

	my $fh;
	my $file;
	my $tmp_file_base = $dir . $$ . '_' . ($ENV{REMOTE_PORT} +0) . '_';
	my $i;
	for($i=1; $i<100; $i++) {
		$file = $tmp_file_base . substr(rand(),2) . '.tmp';
		if (sysopen($fh, $file, O_CREAT | O_EXCL | O_RDWR)) {
			binmode($fh);
			$i=0; last;		# 作成成功
		}
	}
	if ($i) {
		$self->error("Can't open temporary file: %s", $file);
		return;
	}
	return wantarray ? ($fh, $file) : $fh;
}

sub tmpwatch {
	my $self = shift;
	my $dir  = shift;
	my $sec  = shift || $self->{TmpTimeout};
	my $opt  = shift || { dir => 1 };
	$dir = $dir ? $dir : $self->get_tmpdir();
	$dir =~ s|([^/])/*$|$1/|;
	if ($sec < 10) { $sec = 10; }

	my $check_tm = $self->{TM} - $sec;

	my $files = $self->search_files( $dir, $opt );
	my $c = 0;
	foreach(@$files) {
		my $file  = $dir . $_;
		if (-d $file) {
			$self->tmpwatch($file, $sec, $opt);
			$c += rmdir( $file ) ? 1 : 0;
		} else {
			if ((stat($file))[9] > $check_tm) { next; }
			$c += unlink( $file );
		}
	}
	return $c;
}

################################################################################
# Other file functions
################################################################################
sub file_lock {
	my ($self, $file, $type) = @_;

	my $fh;
	if ( !sysopen($fh, $file, O_RDONLY) ) {
		$self->error("Can't open file for %s: %s", 'lock', $file);
		return undef;
	}
	$type ||= 'write_lock';
	my $r = $self->$type($fh);
	if (!$r) { close($fh); return; }
	return $fh;
}

#-------------------------------------------------------------------------------
# File system's locale (mainly for Windows)
#-------------------------------------------------------------------------------
sub set_fslocale {
	my $self = shift;
	$self->{FsLocale} = shift;
	$self->init_fslocale();
}
sub init_fslocale {
	my $self = shift;
	my $fs   = $self->{FsLocale};
	if (!$fs || $fs =~ /utf-?8/i && $self->{SystemCode} =~ /utf-?8/i) {
		$self->{FsConvert}=0;
		return;
	}
	require Encode;
	$self->{FsConvert}=1;
}
sub fs_decode {
	my $self = shift;
	my $file = ref($_[0]) ? shift : \(my $x = shift);
	if (!$self->{FsConvert}) { return $$file; }
	Encode::from_to( $$file, $self->{FsLocale}, $self->{SystemCode});
	return $$file;
}
sub fs_encode {
	my $self = shift;
	my $file = ref($_[0]) ? shift : \(my $x = shift);
	if (!$self->{FsConvert}) { return $$file; }
	Encode::from_to( $$file, $self->{SystemCode}, $self->{FsLocale});
	return $$file;
}

################################################################################
# Network functions
################################################################################
#-------------------------------------------------------------------------------
# Redirect / RFC2616
#-------------------------------------------------------------------------------
sub redirect {
	my $self   = shift;
	my $uri    = shift;
	my $status = shift || '302 Moved Temporarily';

	$uri =~ s/[\x00-\x1f]//g;
	$self->set_header('Location', $uri);
	$self->set_status($status =~ s/^(\d+).*$/$1/sr);

	$self->esc_dest( $status, $uri );
	$self->output(<<HTML);
<!DOCTYPE html>
<html>
<head><title>$status</title></head>
<body>
<p><a href="$uri">Please move here</a>(redirect).</p>
</body></html>
HTML
	$self->superbreak_clear();
	$self->exit(0);
}

#-------------------------------------------------------------------------------
# Resolve host
#-------------------------------------------------------------------------------
sub resolve_host {
	my $self = shift;
	if (!@_) {
		# lookup REMOTE_ADDR
		if ($self->{Resolved}) { return $ENV{REMOTE_HOST}; }
		$self->{Resolved}=1;
		return ($ENV{REMOTE_HOST} = $self->resolve_host($ENV{REMOTE_ADDR},$ENV{REMOTE_HOST}));
	}
	my $ip   = shift;
	my $host = shift;
	if ($ip =~ /:/) { return; }

	# Reverse lookup
	my $ip_bin = pack('C4', split(/\./, $ip));
	if ($host eq '') {
		if ($ip eq '') { return; }
		$host = gethostbyaddr($ip_bin, 2);
		if ($host eq '') { return ; }
	}

	# Double lookup
	my @addr = gethostbyname($host);
	my $ok;
	foreach(4..$#addr) {
		if ($addr[$_] eq $ip_bin) { $ok=1; last; }
	}
	if (!$ok) { return; }
	return $host;
}

#-------------------------------------------------------------------------------
# Check IP/HOST list
#-------------------------------------------------------------------------------
sub check_ip_host {
	my $self = shift;
	my $ip_ary   = shift || [];
	my $host_ary = shift || [];
	if (!@$ip_ary && !@$host_ary) { return 1; }	# ok

	my $ip = $ENV{REMOTE_ADDR} . '.';
	foreach(@$ip_ary) {		# prefix match
		if ($_ eq '') { next; }
		my $z = substr($_,-1);
		my $x = $_ . ($z eq '.' || $z eq ':' ? '' : '.');
		if (0 == index($ip, $x)) { return 2; }
	}

	if (!@$host_ary) { return; }
	my $host = $self->resolve_host();
	if ($host eq '') { return; }
	foreach(@$host_ary) {
		if ($_ eq '') { next; }
		if ($_ eq $host) { return 3; }
		my $x = (substr($_,0,1) eq '.' ? '' : '.') . $_;
		if ($x eq substr($host,-length($x))) { return 4; }
	}
	return;
}

################################################################################
# Other functions
################################################################################
#-------------------------------------------------------------------------------
# remove '../' and './' and start's '/' and '~'
#-------------------------------------------------------------------------------
sub clean_path {
	my $self = shift;
	my $p    = shift;
	$p =~ s!/+!/!g;
	$p =~ s!(^|(?<=/))\.\.?/!$1!g;
	$p =~ s!^(~?/)+!!gr;
}

#-------------------------------------------------------------------------------
# clone, copy nested reference data
#-------------------------------------------------------------------------------
sub clone {
	my $self = shift;
	my $data = shift;
	my $r    = ref($data);
	if ($r eq 'ARRAY') {
		my @x = @$data;
		foreach(@x) {
			$_ = ref($_) ? $self->clone($_) : $_;
		}
		return \@x;
	}
	if ($r eq 'HASH') {
		my %h = %$data;
		foreach(values(%h)) {
			$_ = ref($_) ? $self->clone($_) : $_;
		}
		return \%h;
	}
	if ($r eq 'SCALAR') {
		return \(my $x = $$data);
	}
	return $data;
}

#-------------------------------------------------------------------------------
# debug
#-------------------------------------------------------------------------------
sub debug {
	my $self = shift;
	$self->_debug(join(' ', @_));	## safe
}
sub _debug {
	my $self = shift;
	my ($msg, $level) = @_;
	$self->esc_dest($msg);
	$msg =~ s/\n/<br>/g;
	$msg =~ s/ /&ensp;/g;
	my ($pack, $file, $line) = caller(int($level)+1);
	push(@{$self->{Debug}}, $msg . "<!-- in $file line $line -->");
}
sub clear_debug {
	my $self  = shift;
	return $self->_clear_msg('Debug', @_);
}

################################################################################
# JSON functions /  RFC 8259
################################################################################
my %JSON_ESC = (
	"\\"	=> "\\\\",
	"\n"	=> "\\n",
	"\t"	=> "\\t",
	"\r"	=> "\\r",
	"\x0b"	=> "\\b",	# Backspace
	"\f"	=> "\\f",	# HT
	"\""	=> "\\\""
);
my %JSON_UNESC = reverse(%JSON_ESC);

#-------------------------------------------------------------------------------
# JSON parser
#-------------------------------------------------------------------------------
sub parse_json {
	my $self  = shift;
	my $json  = ref($_[0]) ? join('',@{my $x=shift}) : shift;
	if ($json =~ /\x00/) { return; }

	my @buf;
	$json =~ s{"((?:\\.|[^\"\\\x00-\x1f])*)"}{
		my $x = $1;
		my $u16h=0;
		$x =~ s{\\u([0-9A-fa-f]{4})}{
			my $y=$1;
			if ($y =~ /^[dD][89abAB][0-9a-fA-F]{2}/) {	# high surrogate
				$u16h = (hex($y) - 0xD800)<<10;
				'';
			} elsif ($y =~ /^[dD][c-fC-F][0-9a-fA-F]{2}/) {	# low surrogate
				pack('U', 0x10000 + $u16h + hex($y) - 0xDC00);
			} else {
				pack('U', hex($y));
			}
		}eg;
		$x =~ s/(\\.)/
			my $y = $JSON_UNESC{$1};
			if (!$y) { return; }	# error
			$y;
		/eg;
		push(@buf,$x), "\0$#buf\0"
	}eg;

	if ($json =~ m![^\x00\w\+\-{}\[\]:\.,\s]!) { return; }	# error

	my @ary;
	$json .= ',';
	while($json =~ /\s*(.*?)\s*([{}\[\]:,])/g) {
		if ($1 eq '') {
			push(@ary,$2);
			next;
		}
		push(@ary, $1, $2);
	}
	pop(@ary);

	my $ret = eval {
		return $self->_parse_json(\@ary, \@buf);
	};
	return ($@ || @ary) ? undef : $ret;
}

sub _parse_json {
	my $self = shift;
	my $ary  = shift;
	my $buf  = shift;
	my $type = shift;

	my $is_ary  = $type eq '[';
	my $is_hash = $type eq '{';
	my $data;

	if ($is_ary || $is_hash) {
		$data = $is_ary ? [] : {};
		unshift(@$ary, ',');
	}

	while(@$ary) {
		my $x = shift(@$ary);
		if ($is_ary) {
			if ($x eq ']') { return $data; }
			if ($x ne ',') { die 'err'; }

			push(@$data, $self->_decode_json_val($ary, $buf, shift(@$ary)));

		} elsif ($is_hash) {
			if ($x eq '}') { return $data; }
			if ($x ne ',') { die 'err'; }
			   $x = shift(@$ary);
			my $y = shift(@$ary);
			if ($x !~ /^\0(\d+)\0$/ || $y ne ':') { die 'err'; }
			my $key = $buf->[$1];

			$data->{$key} = $self->_decode_json_val($ary, $buf, shift(@$ary));

		} else {
			return $self->_decode_json_val($ary, $buf, $x);
		}
	}
	die 'err';
}

sub _decode_json_val {
	my $self = shift;
	my $ary  = shift;
	my $buf  = shift;
	my $v    = shift;

	if ($v eq '[') { return $self->_parse_json($ary, $buf, '['); }
	if ($v eq '{') { return $self->_parse_json($ary, $buf, '{'); }
	if ($v =~ /^\0(\d+)\0$/) { return $buf->[$1]; }
	if ($v eq 'true' ) { return $self->true();  }
	if ($v eq 'false') { return $self->false(); }
	if ($v eq 'null' ) { return undef; }
	if ($v ne '-0' && $v =~ /^-?(?:[1-9]\d*|0)(?:\.\d+)?(?:[Ee][-+]?\d+)?$/) { return $v+0; }	# number
	die 'err';
}

#-------------------------------------------------------------------------------
# JSON generator
#-------------------------------------------------------------------------------
sub generate_json {
	my $self = shift;
	my $data = shift;
	my $opt  = shift || {};
	my $tab  = shift || '';

	my $cols = $opt->{cols};	# hash's data columns
	my $ren  = $opt->{rename};	# hash's column rename
	my $t = $opt->{strip} ? '' : $opt->{tab} || "\t";
	my $n = $opt->{strip} ? '' : "\n";
	my $s = $opt->{strip} ? '' : ' ';
	my @ary;

	my $is_ary = ref($data) eq 'ARRAY';
	my $dat = $is_ary ? $data : [$data];
	foreach(@$dat) {
		if (!defined $_)	{ push(@ary, 'null'); next; }
		if (!ref($_))		{ push(@ary, $self->_encode_json_val($_)); next; }
		if ($self->is_bool($_))	{ push(@ary, $_ ? 'true' : 'false');  next; }
		if (ref($_) eq 'SCALAR'){
			if ($$_ =~ /^true|false|null$/) { push(@ary, $$_); next; }			# true/false/null
			push(@ary, '"' . ($$_ =~ s/(\\|\n|\t|\r|\b|\f|\")/$JSON_ESC{$1}/rg) . '"');	# force string
			next;
		}

		if (ref($_) eq 'ARRAY') {
			push(@ary, $self->generate_json($_, $opt, "$t$tab"));
			next;
		}
		my @a;
		my @b;
		my $_cols = $cols ? $cols : [ keys(%$_) ];
		foreach my $x (@$_cols) {
			my $k = exists($ren->{$x}) ? $ren->{$x} : $x;
			my $v = $_->{$x};
			if (!ref($v)) {
				push(@a, "\"$k\":$s" . $self->_encode_json_val( $v ));
				next;
			}
			my $ch = $self->generate_json( $v, $opt, "$t$tab" );		# nest
			push(@b, "\"$k\": $ch");
		}
		push(@ary, $is_ary
			? "{"         . join(",$s"      , @a, @b) . "}"
			: "{$n$tab$t" . join(",$n$tab$t", @a, @b) . "$n$tab}"
		);
	}
	return $is_ary ? "[$n$t$tab" . join(",$n$t$tab", @ary) . "$n$tab]" : $ary[0];
}

sub _encode_json_val {
	my $self = shift;
	my $v    = shift;
	if ($v ne '-0' && $v =~ /^-?(?:[1-9]\d*|0)(?:\.\d+)?(?:[Ee][-+]?\d+)?$/) { return $v; }

	# string
	$v =~ s/(\\|\n|\t|\r|\x0b|\f|\")/$JSON_ESC{$1}/g;
	return '"' . ($v =~ s/([\x00-\x1f])/"\\u00" . unpack('H2',$1)/egr) . '"';
}

#-------------------------------------------------------------------------------
# Boolean
#-------------------------------------------------------------------------------
sub true  { $Sakia::boolean::true  }
sub false { $Sakia::boolean::false }
sub null  { undef; }
sub is_bool {
	my $self = shift;
	ref($_[0]) && UNIVERSAL::isa($_[0], 'Sakia::boolean');
}
#---------------------------------------
package Sakia::boolean;
#---------------------------------------
our $VERSION = '1.00';
our $true    = do { bless(\(my $b = 1), __PACKAGE__) };
our $false   = do { bless(\(my $b = 0), __PACKAGE__) };

use overload (
	"0+"	 => sub { ${$_[0]} },
	"%{}"	 => sub { {} },
	fallback => 1
);

################################################################################
# DO NOT WRITE BELOW THIS, "PACKAGE" IS INCORRECT!
################################################################################

1;
