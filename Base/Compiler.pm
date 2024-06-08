use strict;
#-------------------------------------------------------------------------------
# skeleton compiler
#						(C)2006-2024 nabe@abk
#-------------------------------------------------------------------------------
package Sakia::Base::Compiler;
our $VERSION = '3.13';
use Sakia::AutoLoader;
################################################################################
# constructor
################################################################################
sub new {
	my $self = bless({}, shift);
	$self->{ROBJ}       = shift;
	$self->{__CACHE_PM} = 1;

	return $self;
}

################################################################################
# compile function
################################################################################
# compile( \@lines, 'source file name', 'debug file name' );
#
sub compile {
	my ($self, $lines, $src_file, $logfile) = @_;

	if (ref $lines ne 'ARRAY') {
		$self->error_from(undef, 'Only arrays can be compiled.');	## mskip
		return (-1);
	}

	# for error process
	$self->{errors}     = undef;
	$self->{src_file}   = $src_file;

	# save status
	my $st = $self->{st} = {};

	$lines = $self->preprocessor($st, $lines);
	$logfile && $self->save_log($st, $lines, $logfile . '_01.log');

	$lines = $self->convert_reversed_poland($st, $lines);
	$logfile && $self->save_log($st, $lines, $logfile . '_02.log');

	$lines = $self->parse_block($st, $lines);
	$logfile && $self->save_log($st, $lines, $logfile . '_03.log');

	$lines = $self->poland_to_expression($st, $lines);
	$logfile && $self->save_log($st, $lines, $logfile . '_04.log');

	$lines = $self->process_block($st, $lines);
	$logfile && $self->save_log($st, $lines, $logfile . '_05.log');

	$lines = $self->post_process($st, $lines);
	$logfile && $self->save_log($st, $lines, $logfile . '_06.log');

	$self->{ROBJ}->{CompilerTest} && $self->save_log($st, $lines);

	return ($self->{errors}, [ join('',@$lines) ]);
}

################################################################################
# define
################################################################################
# special character memo
#
#	\x00(\d+)\x00	is string buffer index.
#	\x01<(\d+)>	is reference variable in string. ex) "abc<@var>efg"
#	\x01begin.12	marking of "begin" with block number.
#
#-------------------------------------------------------------------------------
# Internal variables
#-------------------------------------------------------------------------------
my $NO_ARG   = '_.none._';

my $VAR_ROOT = '$R';
my $VAR_OUT  = '$$O';
my $VAR_LNUM = '$$L';
my $SUB_HEAD = <<'SUB_HEAD';
sub {
	my ($R,$O,$L)=@_;
	my $v=$R->{v}; $_[3]=\$v;
SUB_HEAD
my $SUB_FUNC_ADD = '	$R->{IsFunction}=1;' . "\n";
my $DefaultIndentTAB = 1;

my %ReservedVars = map { $_ => 1 } qw(R O L v argv myself myself2);

#-------------------------------------------------------------------------------
# Forced to be considered a function, not a variable
#-------------------------------------------------------------------------------
my %SpecialFunctions = (
	continue=> $NO_ARG,
	break	=> $NO_ARG,
	shift	=> 'argv',	# default argument, 'shift' to 'shift(argv)'
	next	=> $NO_ARG,
	last	=> $NO_ARG,
);

#-------------------------------------------------------------------------------
# other setting
#-------------------------------------------------------------------------------
my %Unit2Num = (K => 1024, M => 1024*1024, G => 1024*1024*1024, T => 1024*1024*1024*1024,
		week => 3600*24*7, day => 3600*24, hour => 3600, min => 60, sec => 1);

#///////////////////////////////////////////////////////////////////////////////
# BlockStatements
#///////////////////////////////////////////////////////////////////////////////
# There are not allow nest.
#	<$call("test", ifexec(...))>
#	<$x = foreach(...)>
#
my %BlockStatement = map { $_ => 1} qw(
	forexec
	foreach
	foreach_hash
	foreach_keys
	foreach_num
	ifexec
);

#///////////////////////////////////////////////////////////////////////////////
# inline functions
#///////////////////////////////////////////////////////////////////////////////
# arg = minimal arguments
#
my %InlineFuncs = (
	match	=>	{ f=>'#0 =~ m!%1! ? [$&,$1,$2,$3,$4,$5,$6,$7,$8,$9] : undef', arg=>2, min=>'?', max=>'=~' },
	replace =>	{ f=>'#0 =~ s!%1!%2!rg',arg=>3, min=>'=~', max=>'=~' },
	replace_dest =>	{ f=>'#0 =~ s!%1!%2!g',	arg=>3, min=>'=~', max=>'=~' },

	is_int	=> { f=>'#0 =~ /^-?\d+$/',	arg=>1, min=>'=~', max=>'=~' },
	is_array=> { f=>"ref(#0) eq 'ARRAY'",	arg=>1, min=>'eq' },
	is_hash => { f=>"ref(#0) eq 'HASH'",	arg=>1, min=>'eq' },
	from_to => { f=>'[#0..#1]',		arg=>2, max=>'..' },
	into    => { f=>'%{#0}=(%{#0},%{#1})',	arg=>2, min=>'='  },

	file_exists =>	{ f=>'-e #0', arg=>1, min=>'-e', max=>'-e' },
	file_readable=>	{ f=>'-r #0', arg=>1, min=>'-r', max=>'-r' },
	file_writable=>	{ f=>'-w #0', arg=>1, min=>'-w', max=>'-w' },
	file_size =>	{ f=>'-s #0', arg=>1, min=>'-s', max=>'-s' },

	sref	=> { f=>'\(my $Z = #0)', arg=>1, min=>'=', max=>'='},
	weaken	=> { f=>'Scalar::Util::weaken(#0)', arg=>1 }
);

#///////////////////////////////////////////////////////////////////////////////
# inline if() functions
#///////////////////////////////////////////////////////////////////////////////
#	'ifxxx(exp, a, b, ... )' rewrite to 'if(exp) { xxx(a, b, ...); }'
#
my %InlineIf = map { $_ => 1} qw(
	ifbreak ifcontinue ifbreak_clear ifsuperbreak ifsuperbreak_clear
	ifjump ifjump_clear ifsuperjump ifsuperjump_clear
	ifcall ifredirect ifform_error ifform_clear
	ifmsg ifmessage ifnotice

	ifpush ifpop ifshift ifunshift
	ifpush_hash ifunshift_hash ifdelete_hash

	ifset_cookie ifclear_cookie
	ifset_header ifset_lastmodified
	ifset_content_type ifset_status

	ifnext iflast ifreturn ifumask ifprint
);

#///////////////////////////////////////////////////////////////////////////////
# Perl's core functions
#///////////////////////////////////////////////////////////////////////////////
# values)
#	0	: normal
#	bit 0	: argument is only one
#	bit 1	: return value is array
#	bit 2	: control syntax. ex) last, next
#	bit 4-6	: 1st(-3rd) argument is array
#	bit 7	: 4th and after argument is array
#	bit 8-11: 1st(-4th) argument is hash
#	bit12-15: maximum arguments
#
my %CoreFuncs = (undef=>0, defined=>1, length=>1, sprintf=>0, join=>0xe0, split=>2,
index=>0, rindex=>0, shift=>0x10, unshift=>0x10, pop=>0x10, push=>0x10,
int=>1, abs=>1, sin=>1, cos=>1, log=>1, exp=>1, sqrt=>1, rand=>0x1000,
undef=>0, substr=>0, chop=>0, chomp=>0, chr=>1, ord=>1, print=>0,
uc=>1, lc=>1, keys=>0x103, values=>0x103, ref=>0, delete=>0, splice=>0x12,
keys=>0x103, values=>0x103,
next=>4, last=>4, exists=>1, reverse=>0xf2, return=>0, umask=>1, sleep=>1);

use constant CF_arg_one		=> 1;
use constant CF_return_array	=> 2;
use constant CF_control		=> 4;

#///////////////////////////////////////////////////////////////////////////////
# builtin functions
#///////////////////////////////////////////////////////////////////////////////
my %BuiltinFunc; my $B=\%BuiltinFunc;
#---------------------------------------------------------------------
# string functios
#---------------------------------------------------------------------
$B->{string2ordary}=<<'FUNC';
	my $txt = shift;
	return [ map { ord($_) } split('', $txt) ];
FUNC

$B->{grep}=<<'FUNC';
	my $x = shift;
	my $ary = $_[0];
	if (ref($ary) ne 'ARRAY') {
		$ary = \@_;
	}
	return [ grep {/$x/} @$ary ];
FUNC

#---------------------------------------------------------------------
# hash functions
#---------------------------------------------------------------------
$B->{array2flag}=<<'FUNC';
	my $ary = shift;
	if (!$ary || !@$ary) { return {} };
	my %h = map {$_ => 1} @$ary;
	return \%h;
FUNC

$B->{arrayhash2hash}=<<'FUNC';
	my ($ary, $key) = @_;
	if (!$ary || !@$ary) { return {} };
	my %h = map {$_->{$key} => $_} @$ary;
	return \%h;
FUNC

$B->{push_hash}=<<'FUNC';
	my ($h, $key, $val) = @_;
	if (ref($h) ne 'HASH') { return; };
	if (!exists($h->{$key}) && $h->{_order}) {
		push(@{$h->{_order}}, $key);
	}
	$h->{$key} = $val;
	return $h;
FUNC

$B->{unshift_hash}=<<'FUNC';
	my ($h, $key, $val) = @_;
	if (ref($h) ne 'HASH') { return; };
	if (!exists($h->{$key}) && $h->{_order}) {
		unshift(@{$h->{_order}}, $key);
	}
	$h->{$key} = $val;
	return $h;
FUNC

$B->{delete_hash}=<<'FUNC';
	my ($h, $key) = @_;
	if (ref($h) ne 'HASH') { return; };
	if (exists($h->{$key}) && $h->{_order}) {
		$h->{_order} = [ grep { $_ ne $key } @{$h->{_order}} ];
	}
	delete $h->{$key};
	return $h;
FUNC

#---------------------------------------------------------------------
# sort
#---------------------------------------------------------------------
$B->{sort_num}=<<'FUNC';
	my ($ary,$key) = @_;
	if ($key eq '') { return [ sort {$a<=>$b} @$ary ]; }
	return [ sort {$a->{$key} <=> $b->{$key}} @$ary ];
FUNC

$B->{sort_str}=<<'FUNC';
	my ($ary,$key) = @_;
	if ($key eq '') { return [ sort {$a cmp $b} @$ary ]; }
	return [ sort {$a->{$key} cmp $b->{$key}} @$ary ];
FUNC

#---------------------------------------------------------------------
# other
#---------------------------------------------------------------------
$B->{esc_csv}=<<'FUNC';
	my $val = shift;
	if (substr($val,0,1) ne '"' && $val !~ /[\n,]/) { return $val; }
	$val =~ s/"/""/g;
	return '"' . $val . '"';
FUNC

$B->{concat}=<<'FUNC';
	my @ary;
	foreach(@_) { push(@ary, @$_); }
	return \@ary;
FUNC

#-------------------------------------------------------------------------------
# operators
#-------------------------------------------------------------------------------
my %OPR;
my %OPR_formal;		# to formal name
# bit 0	- right to left
# bit 1 - unary operator
# bit 2 - unary right join operator for "x++/x--"
# bit 3 -
# bit 4-  priority (higher is first)
use constant OPL_right_to_left	=> 0x01;
use constant OPL_unary		=> 0x02;
use constant OPL_unary_right	=> 0x04;
use constant OPL_max		=> 0x1000;

$OPR{'('}  =  0x00;
$OPR{')'}  =  0x00;
$OPR{'{'}  =  0x00;
$OPR{'}'}  =  0x00;
$OPR{'['}  =  0x00;
$OPR{']'}  =  0x00;
$OPR{';'}  =  0x00;
$OPR{','}  =  0x10;	# special handling
$OPR{'=>'} =  0x10;
$OPR{'='}  =  0x21;
$OPR{'+='} =  0x21;
$OPR{'-='} =  0x21;
$OPR{'*='} =  0x21;
$OPR{'/='} =  0x21;
$OPR{'%='} =  0x21;
$OPR{'&='} =  0x21;
$OPR{'|='} =  0x21;
$OPR{'.='} =  0x21;
$OPR{'**='}=  0x21;
$OPR{'<<='}=  0x21;
$OPR{'>>='}=  0x21;
$OPR{'&&='}=  0x21;
$OPR{'||='}=  0x21;
$OPR{'?'}  =  0x30;	# not use
$OPR{'..'} =  0x40;
$OPR{'||'} =  0x50; $OPR_formal{'||'}  = ' || ';	# for readability
$OPR{'&&'} =  0x60; $OPR_formal{'&&'}  = ' && ';	#
$OPR{'|'}  =  0x70;
$OPR{'^'}  =  0x80;
$OPR{'&'}  =  0x90;
$OPR{'=='} =  0xa0;
$OPR{'!='} =  0xa0;
$OPR{'<=>'}=  0xa0;
$OPR{'eq'} =  0xa0; $OPR_formal{'eq'} = ' eq ';
$OPR{'ne'} =  0xa0; $OPR_formal{'ne'} = ' ne ';
$OPR{'<'}  =  0xb0;
$OPR{'>'}  =  0xb0;
$OPR{'<='} =  0xb0;
$OPR{'>='} =  0xb0;
$OPR{'defined'}=0xc2;
$OPR{'-e'} =  0xc2; $OPR_formal{'-e'} = '-e ';
$OPR{'-r'} =  0xc2; $OPR_formal{'-r'} = '-r ';
$OPR{'-w'} =  0xc2; $OPR_formal{'-w'} = '-w ';
$OPR{'-s'} =  0xc2; $OPR_formal{'-s'} = '-s ';
$OPR{'>>'} =  0xd0;
$OPR{'<<'} =  0xd0;
$OPR{'+'}  =  0xe0;
$OPR{'-'}  =  0xe0;
$OPR{'.'}  =  0xe0; $OPR_formal{'.'}  = ' . ';	# need space ex) 123 .'abc'
$OPR{'*'}  =  0xf0;
$OPR{'/'}  =  0xf0;
$OPR{'%'}  =  0xf0;
$OPR{'%x'} =  0xf0; $OPR_formal{'%x'} = ' x ';
$OPR{'=~'} = 0x100;
$OPR{'!~'} = 0x100;
$OPR{'!'}  = 0x112;
$OPR{'~'}  = 0x112;
$OPR{'**'} = 0x126;
$OPR{'++'} = 0x132;
$OPR{'--'} = 0x132;
$OPR{'++r'}= 0x136; $OPR_formal{'++r'} = '++'; # x++
$OPR{'--r'}= 0x136; $OPR_formal{'--r'} = '--'; # x++

# Under operators is special handling
$OPR{'%r'} = 0x200;
$OPR{' '}  = 0x200;
$OPR{'#'}  = 0x200;				# ref to an array element
$OPR{'->'} = 0x200;				# ref to an hash element
$OPR{'%f'} = 0x200;				# ref to an object method for call
$OPR{'%%'} = 0x202; $OPR_formal{'%%'} = '%';	# dereference hash
$OPR{'@'}  = 0x202;				# dereference array
$OPR{'##'} = 0x202; 				# last index of array
$OPR{'%m'} = 0x202; $OPR_formal{'%m'} = '-';	# minus number

#-------------------------------------------------------------------------------
# pragma
#-------------------------------------------------------------------------------
my %PRAGMA = (
	rm_sp_begin	=> 0x0001,	# If the line begins with only spaces before the first command, delete it.
	rm_crlf_trail	=> 0x0002,	# Remove trailing CR/LF from command-only line, if there are no spaces at the end of the line.
	rm_blank_fc	=> 0x0004,	# Remove blank lines following command-only line.
	rm_blank	=> 0x0008,	# Remove blank lines.
	rm_crlf		=> 0x0010,	# Remove CR/LF.
	rm_any		=> 0x0020,	# Remove anything except commands.
	function	=> 0x0040,	# The skeleton is function.

	strict		=> 0x0100	# strict mode
);
my $DEFAULT_PRAGMA = 0x107;

################################################################################
# [01] preprocessor
################################################################################
sub preprocessor {
	my $self = shift;
	my ($st, $lines) = @_;

	my $P      = $st->{pragma} = {};
	my $strbuf = $st->{strbuf} = [];	# string buffer
	my $p_def  = defined($self->{default_pragma}) ? $self->{default_pragma} : $DEFAULT_PRAGMA;
	unshift(@$lines, sprintf("<\@%x>\n", $p_def));

	my $prev_cmd_only = 0;	# The previous line is a command only
	my $chain_line    = 0;
	my $sharp_comment = 0;

	my $lnum = -1;		# line number counter, -1 for default pragma
	my @out;
	foreach(@$lines) {
		$lnum++;

		# Lines starting with '#' are considered comments
		if ($_ =~ /^<\@\#>/)   { $sharp_comment = 1; next; }	# on
		if ($_ =~ /^<\@\-\#>/) { $sharp_comment = 0; next; }	# off
		if ($sharp_comment && $_ =~ /^\s*\#/) { next; }

		# Line concatenation
		my $data =  $_;
		if ($chain_line) {
			$data =~ s/^\s+//;
			$chain_line = 0;
		}
		# Concatenate the next line when "<@\>" is at the end of the line
		if ($data =~ /^(.*?)\s*<\@\\>\r?\n$/) {
			$data = $1;
			$chain_line = 1;
		}

		#---------------------------------------------------------------
		# Pragma
		#---------------------------------------------------------------
		my $is_pragma;
		while ($data =~ /^<(?:\@(\d[0-9A-Fa-f]*)(?:\.\w+)?|\$'([\+\-])?(\w+)')>\s*(.*)/) {
			$is_pragma = 1;
			$data = $5;
			if ($1 ne '') {		# ex) <@06> <@20>
				my $n = hex($1);
				foreach(keys(%PRAGMA)) {
					$P->{$_} = $n & $PRAGMA{$_};
				}

			} else {		# ex <$'strict'> <$'+rm_sp_begin'> <$'-rm_blank'>
				if ($PRAGMA{$3}) {
					$P->{$3} = $2 eq '-' ? 0 : 1;
				} else {
					my $h = { lnum => $lnum };
					$self->error_from($h, 'Unknown pragma: %s', $3);
				}
			}
		}
		if ($is_pragma) { next; }

		if ($P->{rm_blank}    && $data =~ /^\r?\n$/                  ) { next; }
		if ($P->{rm_blank_fc} && $data =~ /^\r?\n$/ && $prev_cmd_only) { next; }
		if ($P->{rm_crlf}) { $data =~ s/\r?\n$//; }

		# Remove line break, when end of the line is "<$end>"
		$data =~ s/(<[\$\@]end(?:\.\w+)?>)\r?\n$/$1/;

		#---------------------------------------------------------------
		# comment
		#---------------------------------------------------------------
		if ($data =~ /^(.*?)<\@>/) {
			$data = $1;
			if ($data =~ /^\s*$/) { next; }
		}

		#---------------------------------------------------------------
		# command
		#---------------------------------------------------------------
		$data =~ s/[\x00-\x01]//g;	# remove special character (use by this compiler)
		$data =~ s|</\$>|<\$\$>|g;	# </$> to <$$>

		my $exists_string = 0;		# Flag: when exists other than a command
		my $command_c     = 0;		# command counter
		my $c_chain       = 0;		# command line chain counter

		while ($data =~ /^(.*?)<([\$\@\#])(.*)/s) {	# find command
			$command_c++;
			my $prev = $1;
			my $mode = $2;
			my $tmp  = $3;
			if ($command_c==1) {	# First command
				if ($P->{rm_sp_begin} && $prev =~ /^\s+$/) { $prev=''; }
			}

			if ($prev ne '') {
				$exists_string ||= $prev !~ /^\s*$/;
				push(@out, {
					data	=> $prev,
					delete	=> $P->{rm_any},
					lnum	=> $lnum
				});
			}

			# push line data
			my $line = { lnum => $lnum+$c_chain, replace => $2 eq '@' };
			push(@out, $line);

			# <@@xxx>, <@@xxx> is stop "rm_spaces_ac"
			if ($mode eq '@' && substr($tmp,0,1) eq '@') {
				$tmp = substr($tmp,1);
				$exists_string = 1;
			}

			my $cmd = '';
			my $paren    = 0;	# ( ) counter
			my $bracket  = 0;	# { } counter
			my $sbracket = 0;	# [ ] counter
			my $success;

			while ($tmp =~ /^(.*?)([>\"\'\(\)\{\}\[\]\\])(.*)/s) {
				$cmd .= $1;
				if ($2 eq '>') {
					$tmp = $3;
					if ($paren != 0 || $bracket != 0 || $sbracket != 0) {
						$cmd .= $2;
						next;
					}
					$success=1;
					last;	# end of command
				}
				if ($2 ne '"' && $2 ne "'") {
					if ($2 eq '(') { $paren++; }
					if ($2 eq ')') { $paren--; }
					if ($2 eq '{') { $bracket++; }
					if ($2 eq '}') { $bracket--; }
					if ($2 eq '[') { $sbracket++; }
					if ($2 eq ']') { $sbracket--; }
					if ($2 eq "\\" && $3 eq '' || $3 eq "\n") {	# command line chain
						$cmd =~ s/\s*$//;
						my $l=$lnum + $c_chain;
						$tmp = $lines->[$l] =~ s/^\s*//r;
						$lines->[$l] = '';
						$c_chain++;
						next;
					}
					$cmd .= $2;
					$tmp  = $3;
					next;
				}

				#-----------------------------------------------
				# string
				#-----------------------------------------------
				my $single = $2 eq "'";
				my $double = $2 eq '"';
				my $str    = $3;
				if ($single && $str !~ /^((?:\\.|[^\\'])*)\'(.*)/s 
				 || $double && $str !~ /^((?:\\.|[^\\"])*)\"(.*)/s) {
					$self->error_from($line, 'String format error: %s', $tmp);
					$cmd ='';
					$tmp ='';
					last;
				}
				$str = $1;	# string
				$tmp = $2;	# remain

				if ($single && substr($cmd,-1) eq '#') {	# #'string' conver to "string"
					chop($cmd);
					$single = 0;
					$double = 1;
				}

				if ($single) {
					push(@$strbuf, "'$str'");
					$cmd .= "\x00$#$strbuf\x00";

				} elsif ($double) {
					$str =~ s/\\([\"\\\$\@])/"\\x" . unpack('H2', $1)/eg;	# escape special character
					$str =~ s/"/\\"/g;					# escape double quote
					$str =~ s/<@([\w\.]+?(\#\d+)?)>/\x01$1\x01/g;		# replace variable "val=<@val>"
					$str =~ s/([\$\@])/\\$1/g;				# escape '$' and '@'

					push(@$strbuf, "\"$str\"");
					$cmd .= "\x00$#$strbuf\x00";
				} else {
					die "Internal Error";
				}
			}
			if ($success) {
				if ($mode eq '$') {
					if ($cmd eq '')  { $line->{com_start} = 1; }
					if ($cmd eq '$') { $line->{com_end}   = 1; }
				}
				if ($cmd ne '') {
					if ($mode eq '#') {		# comment outed command
						pop(@out);
					} else {
						$line->{cmd}=$cmd;
					}
				}

			} elsif(!$line->{error}) {
				$self->error_from($line, 'Command broken: %s', $cmd);
			}
			$data = $tmp;
		}
		# $data does not contain commandv

		if ($P->{rm_crlf_trail} && $command_c && !$exists_string) {
			if ($data =~ /^\r?\n$/) { $data=''; }
		}
		if ($data ne '') {
			if ($data !~ /^\s+$/) { $exists_string=1; }
			push(@out,{
				data	=> $data,
				delete	=> $P->{rm_any},
				lnum	=> $lnum
			});
		}
		$prev_cmd_only = !$exists_string;
	}
	return \@out;
}

################################################################################
# [02] convert to revsered poland
################################################################################
sub convert_reversed_poland {
	my $self = shift;
	my ($st, $lines) = @_;

	my $strbuf = $st->{strbuf};
	my $com_flag;

	foreach(@$lines) {
		if ($_->{com_start}) { $_=undef; $com_flag=1; next; }	# start comment
		if ($_->{com_end})   { $_=undef; $com_flag=0; next; }	# end comment
		if ($com_flag)       { $_=undef; next; }

		my $cmd = $_->{cmd};
		if ($cmd eq '') { next; }		# not command

		#---------------------------------------------------------------
		# <@\n>, <@\r>, <@\ >, <@\t>, <@\v>, <@\f>, <@\e>
		#---------------------------------------------------------------
		if ($cmd =~ /^\\([nr tvfe])$/) {
			my %h = ('n'=>"\n",'r'=>"\r",' '=>" ",'t'=>"\t",'v'=>"\v",'f'=>"\f",'e'=>"\e");
			$_->{data} = $h{$1};
			next;
		}

		#---------------------------------------------------------------
		# format command
		#---------------------------------------------------------------
		$cmd =~ s/%([A-Za-z][\w\.])/%%$1/g;	# dereference hash
		# $cmd =~ s/(\W)x(\W)/$1%x$2/g;		# (void) if set valid, do not use "var x".
		$cmd =~ s/\.\(/->(/g;			# "x.()" to "x->()"
		$cmd =~ s/\)\./)->/g;			# "().y" to "()->y"

		$cmd =~ s!->(\w+(?:[\.\w+])*)(\s*\()?!	# (a)->b.c   to (a)->('b')->('c')
			my $x='';			# (a)->b.c() to (a)->('b') %f c %r()
			my $cfunc;
			my @ary = split(/\./, $1);
			if ($2) {
				$cfunc = pop(@ary);
			}
			foreach(@ary) {
				push(@$strbuf, "'$_'");
				$x .= "->(\x00$#$strbuf\x00)";
			}
			$cfunc eq '' ? $x : "$x%f$cfunc%r(";	# %f is hash method name
		!eg;

		$cmd =~ s!(array|hash|flag)q\(\s*([^\(\)]*?)\s*\)!
			my $c = $1;
			my @a = $self->array2quoted_string(split(/\s*,\s*|\s+/, $2));
			foreach(@a) {
				if ($_ =~ /^'(\x00\d+\x00)'$/) { $_=$1; next; }
				push(@$strbuf, $_);
				$_ = "\x00$#$strbuf\x00";
			}
			my $x=join(',', @a);
			"$c($x)";
		!eg;

		$cmd =~ s/(\x00\d+\x00)/ $1 /g;			# string with space
		$cmd =~ s/\s+/ /g;
		$cmd =~ s/shift\( ?\)/shift(argv)/g;		# shift() to shift(argv)
		$cmd =~ s/\( ?\)/($NO_ARG)/g;			# ()
		$cmd =~ s/\[ ?\]/[$NO_ARG]/g;			# []
		$cmd =~ s/\{ ?\}/{$NO_ARG}/g;			# {}

		$cmd =~ s/\b(-?(?:[1-9]\d*|0)(?:\.\d+)?[Ee])([-+]?)(\d+)/
			$1 . ($2 eq '-' ? 'm' : '') . $3	# ex) 10.7e-5
		/eg;

		use constant DEBUG_PL => 0;

		DEBUG_PL && print "\n$cmd\n";
		#---------------------------------------------------------------
		# split operators
		#---------------------------------------------------------------
		my @buf;
		$cmd .= ' ';
		while ($cmd =~ /^(.*?)([=,\.\(\)\[\]\{\}\+\-<>\^\*\/&|%!;\#\@\ ])(.*)/s) {
			my $prev = $1;
			if ($prev ne '') {
				push(@buf, $prev);
			}
			if ($2 eq ' ') {
				$cmd = $3;
				next;
			}

			my $op = $2;
			if (length($3) >1 && exists $OPR{$op . substr($3, 0, 2)}) {	# 3 characters oprator
				$op .= substr($3, 0, 2);
				$cmd = substr($3, 2);
			} elsif ($3 ne '' && exists $OPR{$op . substr($3, 0, 1)}) {	# 2 characters oprator
				$op .= substr($3, 0, 1);
				$cmd = substr($3, 1);
			} else {
				$cmd = $3;
			}

			if ($op eq '.') {
				if ($prev =~ /\w$/ && $cmd =~ /^(\w(?:\w|\.\w)*)(.*)/) {	# \w.\w
					$buf[$#buf] .= '.' . $1;
					$cmd = $2;
					next;
				}
				if ($prev =~ /^\d+$/) {		# 01234.+
					$buf[$#buf] .= '.';
					next
				}
				if ($cmd =~ /^(\d+)(.*)/) {	# -.1234
					push(@buf, ".$1");
					$cmd = $2;
					next
				}
			}
			push(@buf, $op);
		}

		DEBUG_PL && print "buf[0-" . ($#buf) . "]: ", join(' ', @buf), "\n";
		#---------------------------------------------------------------
		# convert loop
		#---------------------------------------------------------------
		my @poland;
		my @op  = ('(');	# operator stack
		my @opl = ( 0 );	# operator stack priority
		push(@buf, ')');
		my $prev_is_op;

		while(@buf) {
			my $x    = shift(@buf);
			my $next = $buf[0];

			if ($SpecialFunctions{$x} && $next ne '(') {
				# break --> break(), shift --> shift(argv)
				unshift(@buf, '(', $SpecialFunctions{$x}, ')');
			}

			my $opl = $OPR{$x};
			if (!defined $opl) {
				push(@poland, $x);
				$prev_is_op=0;
				next;
			}

			my $op = $x;
			if ($op eq '-'  &&  $prev_is_op) { $op='%m'; }	# minus number
			if ($op eq '++' && !$prev_is_op) { $op='++r'; }	# x++
			if ($op eq '--' && !$prev_is_op) { $op='--r'; }	# x--

			# $op  operator
			# $opl operator priority

			if ($op eq '(') {
				push(@op, '('); push(@opl, 0);
				if ($prev_is_op eq '0') {		# xxx() is function call
					push(@op, '%r');
					push(@opl, 0);
				}
				$prev_is_op = 1;

			} elsif ($op eq '[' || $op eq '{') {
				push(@op, $op); push(@opl, 0);
				if ($prev_is_op eq '0') { last; }	# xxx[] xxx{} is error
				push(@poland,  $op eq '[' ? 'array' : 'hashx');
				push(@op, '%r');
				push(@opl, 0);
				$prev_is_op = 1;

			} else {
				my $z = $opl & 1;		# $z=1 if operator from right
				if ($opl[$#opl] & $opl & 2) {	# stack top and current operator is unary operator
					# not pop operator

				} else {
					while ($#opl>=0 && $opl[$#opl] >= $opl + $z) {
						my $op0   = pop(@op);
						my $level = pop(@opl);
						if ($op0 eq '(' && $op eq ')') { last; }
						if ($op0 eq '[' && $op eq ']') { last; }
						if ($op0 eq '{' && $op eq '}') { last; }

						# Outputs an operator with a lower priority than the current operator
						push(@poland, $op0);
					}
				}
				# push new operator
				if ($op eq ')' || $op eq ']' || $op eq '}') {
					$prev_is_op = 0;
				} else {
					$prev_is_op = 1;
					push(@op,  $op);
					push(@opl, $opl);
				}
			}
			DEBUG_PL && print "poland   : ", join(' ', @poland, $#poland), "\n";
			DEBUG_PL && print "op stack : ", join(' ', @op), "\n";
		}

		#---------------------------------------------------------------
		# convert finish
		#---------------------------------------------------------------
		if (@buf || $#op >= 0) {	# remain @buf or remain stack
			$self->error_from($_, 'Syntax error: %s', $_->{cmd});
			next;
		}
		if (@poland) {
			$_->{poland} = \@poland;	# save
		}
	}
	if ($com_flag) {
		$self->error_from(undef, "Comment(<\$>) is not closed." . $lines->[$#$lines]);
	}

	return [ grep { $_ } @$lines ];
}

################################################################################
# [03] parse block
################################################################################
sub parse_block {
	my $self = shift;
	my ($st, $lines) = @_;

	my $block_lv  = 0;	# block nest level
	my $block_cnt = 0;	# block counter
	my $in_code   = 1;
	my $blk = {
		cnt	=> $block_cnt,
		lv 	=> $block_lv,
		code	=> $in_code
	};
	my @blocks;

main:	foreach my $line (@$lines) {
		$line->{block_lv} = $block_lv;

		my $po = $line->{poland};
		if (!$po) { next; }

		#---------------------------------------------------------------
		# analyze poland
		#---------------------------------------------------------------
		my $polen = $#$po +1;
		my $po0   = $po->[0];

		#---------------------------------------------------------------
		# <$elsif(...)>
		#---------------------------------------------------------------
		if ($po0 eq 'elsif') {
			if (!$blk->{ifexec}) {
				$self->error_from($line, 'Exists "%s" without "%s".', $po0, 'ifexec');
				next;
			} elsif ($blk->{ifexec}->{else}) {
				$self->error_from($line, 'Exists "%s" after "%s".', $po0, 'else');
				next;

			}

			# save ifexec info
			$blk->{ifexec}->{elsif} = 1;

			# save line info
			$line->{elsif}     = 1;
			$line->{block_end} = $blk->{cnt};
			$line->{block_lv}  = $block_lv-1;

			# generate new block
			$blk->{cnt} = ++$block_cnt;
		}

		#---------------------------------------------------------------
		# <$else>
		#---------------------------------------------------------------
		if ($po0 =~ /^else(|\.\w+)$/) {
			my $label = $1;

			if ($label ne $blk->{label} || !$blk->{ifexec}) {
				$self->error_from($line, 'Exists "%s" without "%s".', $po0, 'ifexec');
				delete $line->{poland};
				next;
			} elsif ($blk->{ifexec}->{else}) {
				$self->error_from($line, 'Exists "%s" duplicate in "ifexec".', $po0);
				delete $line->{poland};
				next;
			}

			# save ifexec info
			$blk->{ifexec}->{else} = 1;

			# save line info
			$line->{else}      = 1;
			$line->{block_end} = $blk->{cnt};
			$line->{block_lv}  = $block_lv-1;

			if ($blk->{comple}) {	# else block without begin
				$blk->{cnt} = ++$block_cnt;

			} elsif (0<=$#blocks && !$blocks[$#blocks]->{ifexec}) {
				$self->error_from($line, 'Exists "%s" without "%s".', $po0, 'ifexec');
				delete $line->{poland};
				next;

			} else {
				$blk      = pop(@blocks);
				$block_lv = $blk->{lv};
			}

			$line->{block_lv} = $block_lv-1;
			next;
		}
		#---------------------------------------------------------------
		# <$end>
		#---------------------------------------------------------------
		if ($polen==1 && $po0 =~ /^end(_\w+)?(\.\w+)?$/) {
			my $type  = $1;
			my $label = $2;

			if ($blk->{lv}==0 || $type && $type ne $blk->{type} || $label ne $blk->{label}) {
				$self->error_from($line, 'Exists "%s" without "%s".', $po0, 'begin');
				delete $line->{poland};
				next;
			}
			if ($blk->{ifexec}) {
				if ($blk->{ifexec}->{end}) {
					$self->error_from($line, 'Exists "%s" duplicate in "ifexec".', $po0);
					delete $line->{poland};
					next;
				}
				$blk->{ifexec}->{end} = 1;
			}

			# save line info
			$line->{end}       = 1;
			$line->{end_code}  = $blk->{code};
			$line->{block_end} = $blk->{cnt};
			$line->{block_lv}  = $block_lv-1;

			$blk      = pop(@blocks);
			$block_lv = $blk->{lv};
			next;
		}

		#---------------------------------------------------------------
		# complement begin
		#---------------------------------------------------------------
		my $comple;
		if ($BlockStatement{$po0} && 2<$polen) {
			# example)
			#	foreach ... %r
			#	foreach ... begin , %r
			my $x = $po->[$polen-3];
			my $y = $po->[$polen-2];
			my $z = $po->[$polen-1];
			if ($z eq '%r' && ($y ne ',' || $x !~ /^begin(\.\w+)?$/)) {
				pop(@$po);
				push(@$po, 'begin', ',', $z);
				$comple=1;
			}
		}

		#---------------------------------------------------------------
		# detect illegal else/end
		#---------------------------------------------------------------
		foreach(0..$polen) {
			if ($po->[$_] =~ /^(else|end|elsif)(?:\.\w+)?$/) {
				if ($_ == 0 && $1 eq 'elsif') { next; }

				$self->error_from($line, 'Illegal location for "%s".', $po->[$_]);
				delete $line->{poland};
				next main;
			}
		}

		#---------------------------------------------------------------
		# detect begin
		#---------------------------------------------------------------
		my $find;
		my $non_code = !$blk->{code};
		my $ifexec   = $po0 eq 'ifexec' ? {} : undef;
		foreach(reverse(0..$polen)) {
			if ($po->[$_] !~ /^begin(_\w+)?(\.\w+)?$/) { next; }

			if ($non_code) {
				$self->error_from($line, '"%s" cannot be written in non-code blocks.', $po->[$_]);
				delete $line->{poland};
				last;
			}

			if (!$find) {
				$find = 1;
				$block_lv++;
			}

			push(@blocks, $blk);	# save current block
			$blk = {
				orig	=> $po->[$_],
				cnt	=> ++$block_cnt,
				lv	=> $block_lv,
				type	=> $1,
				code	=> $1 eq '' || $1 eq '_func',
				label	=> $2,
				ifexec	=> $ifexec,
				comple	=> $comple,
				line	=> $line
			};
			$line->{block_state}= $BlockStatement{$po0};
			$line->{ifexec}     = $ifexec;

			$po->[$_] = "\x01begin" . $1 . '.' . $block_cnt;	# append block number
		}
	}

	foreach(@blocks, $blk) {
		if ($_->{lv} == 0) { next; }
		$self->error_from($_->{line}, 'Not found "end" corresponding to "%s".', $_->{orig});
		delete $_->{poland};
	}

	# Rewrite "ifexec(x, begin, begin)" to "ifexec(x, begin)"
	foreach(@$lines) {
		my $po = $_->{poland};
		if (!$po || $po->[0] ne 'ifexec' || $#$po<6) { next; }

		# ifexec ... begin.6 , begin.5 , %r
		my @x = splice(@$po, -5);
		if ($x[1] eq ',' && $x[3] eq ',' && $x[4] eq '%r'
		 && $x[0] =~ /^\x01begin\.\d+$/ && $x[2] =~ /^\x01begin\.\d+$/) {
			push(@$po, $x[0], $x[1], $x[4]);
		 	next;
		}
	 	push(@$po, @x);
	}

	return $lines;
}

################################################################################
# [04] revsered poland to perl expression
################################################################################
sub poland_to_expression {
	my $self = shift;
	my ($st, $lines) = @_;

	$st->{const}    = {};		# constant
	$st->{local}    = { v => 1 };	# local variables hash
	$st->{local_st} = [];		# local variables stack
	$st->{builtin}  = {};		# used builtin functions

	my $const = $st->{const};

	use constant DEBUG_CV => 0;	# convert main
	use constant DEBUG_LV => 0;	# local var stack

	foreach my $line (@$lines) {
		my $po = $line->{poland};
		if (!$po) { next; }

		DEBUG_LV && print "cmd = $line->{cmd}\n";
		DEBUG_CV && print "poland: " . join(' ', @$po) . "\n";

		#---------------------------------------------------------------
		# special lines
		#---------------------------------------------------------------
		if ($line->{else} || $line->{end_code}) {
			$self->pop_localvar_stack($st, $line->{else});
			DEBUG_LV && $self->dump_localvar_stack($st, "pop");

			$line->{exp}  = $line->{else} ? '} else {' : '}';
			$line->{code} = 1;
			next;
		}
		if ($line->{end}) {
			next;
		}
		if ($line->{elsif}) {
			$self->pop_localvar_stack($st, 1);
			DEBUG_LV &&  $self->dump_localvar_stack($st, "pop");
		}

		#---------------------------------------------------------------
		# convert main
		#---------------------------------------------------------------
		my $strict =$st->{pragma}->{strict};
		my $ref_obj=$st->{ref_obj}={};	# reference objects
		my $stack  =$st->{stack} = [];	# stack machine
		my $stype  =$st->{stype} = [];	# stack element type
		my $sopl   =$st->{sopl}  = [];	# stack minimal operator level
		my $poland =$st->{poland}= [];	# hack for inline functions
	
		my $local     = $st->{local};
		my %local_bak = %$local;
		$st->{begin_code}= 0;

		my @err;
		p2e: foreach(0..$#$po) {
			@$poland = ($po->[$_]);
			while(@$poland) {
				my ($el, $type) = $self->get_element_type($st, shift(@$poland));
				if (DEBUG_CV) {
					print "  dump stack : ", join(' ', map { ref($_) ? '['.join(',',@$_).']' : $_ } @$stack), "\n";
					print "  type stack : ", join(' ', map { ref($_) ? '['.join(',',@$_).']' : $_ } @$stype), "\n";
					print "   opl stack : ", join(' ', map { ref($_) ? '['.join(',',@$_).']' : $_ } @$sopl),  "\n";
					print "  ele / type : $el / $type / " . $OPR{$el} . "\n\n";
				}
				if ($type eq 'op') {
					$st->{line}    = $line;
					$st->{last_op} = ($_ == $#$po);
					my ($a, $at, $opl);
					($a, $at, $opl, @err) = $self->p2e_operator($st, $el);
					push(@$stack, $a);
					push(@$stype, $at  || '*');
					push(@$sopl,  $opl || OPL_max);
					if (@err) { last p2e; }

				} elsif ($type eq 'error') {
					@err = ('Unknown element: %s', $po->[$_]);	## msg
					last p2e;

				} else {
					push(@$stack, $el);
					push(@$stype, $type);
					push(@$sopl,  OPL_max);
				}
			}
		}

		#---------------------------------------------------------------
		# error trap
		#---------------------------------------------------------------
		if (!@err && $#$stack != 0) {
			@err = ('Syntax error: %s', $line->{cmd});	## msg
		}
		my $exp  = !@err && pop(@$stack);
		my $type = !@err && pop(@$stype);
		my $opl  = !@err && pop(@$sopl);

		if (!@err && $strict) {
			if ($type eq 'obj') { $self->get_object($st, $exp); }
			foreach(keys(%$ref_obj)) {
				if ($_ !~ /^[a-z_]/)   { next; }
				if ($ReservedVars{$_}) { next; }
				@err = ('Strict mode not access to lowercase global variable: %s', $ref_obj->{$_});	## msg
			}
		}

		#---------------------------------------------------------------
		# local var stack process
		#---------------------------------------------------------------
		if ($line->{elsif}) {
			my %h = %$local;
			$local->{_bak} = \%h;	# renew backup for else
		}
		if ($st->{begin_code}) {
			my $c = $st->{begin_code};

			if ($line->{block_state}) {
				# block_state is 'ifexec()/foreach()'.
				# Local variables on the block statement are valid only within the block.
				$st->{local} = \%local_bak;
				$self->push_localvar_stack($st, $local, 1);
				$c--;
			}
			$self->push_localvar_stack($st, \%local_bak, $c);
			DEBUG_LV &&  $self->dump_localvar_stack($st, "push $c");
		}

		#---------------------------------------------------------------
		# error handle / Must be executed after block processing!
		#---------------------------------------------------------------
		if (@err) {
			$self->error_from($line, @err);

			if ($line->{elsif}) {
				$line->{out_with_code} = '} elsif(0) { ';
			} elsif ($st->{begin_code}) {
				$line->{out_with_code} = 'if(0) { ';
			}
			next;
		}

		#---------------------------------------------------------------
		# save perl expression
		#---------------------------------------------------------------
		if (ref $exp eq 'ARRAY') {
			$exp = join(',', $self->get_objects_array($st, $exp, $type));
			$type = "*";
			$opl  = $OPR{','};
		}

		if (!$line->{replace} && ($type eq 'obj' || $type eq 'const')) {
			$line->{out}    = '';	# no output
			$line->{delete} = 1;
			next;
		}
		if ($type eq 'obj') {
			$exp = $self->get_object($st, $exp);
			$line->{var_exp} = 1;	# simple var replace
		}
		if ($type eq 'const') {
			$line->{data} = eval($exp);
			next;
		}
		$line->{exp} = $exp;
		$line->{opl} = $opl;
	}

	return [ grep { $_ } @$lines ];
}

sub push_localvar_stack {
	my $self = shift;
	my ($st, $org, $c) = @_;

	my %bak = %$org;	# copy
	foreach(1..$c) {
		my %h = %$org;
		$h{_bak} = \%bak;	# backup for else/elsif
		push(@{$st->{local_st}}, $st->{local});
		$st->{local} = \%h;
	}
}
sub pop_localvar_stack {
	my $self = shift;
	my ($st, $else) = @_;
	if (!$else) {
		$st->{local} = pop(@{$st->{local_st}});
		return;
	}
	my %h = %{$st->{local}->{_bak} || {}};
	$st->{local} = \%h;
}

#-------------------------------------------------------------------------------
# poland to expression, operator
#-------------------------------------------------------------------------------
sub p2e_operator {
	my $self = shift;
	my ($st, $el) = @_;

	my $stack = $st->{stack};
	my $stype = $st->{stype};
	my $sopl  = $st->{sopl};

	# ex) $OPR_formal{'%x'} to 'x'
	my $op  = exists($OPR_formal{$el}) ? $OPR_formal{$el} : $el;
	my $opl = $OPR{$el};

	if ($#$stack<0) { return (0,0,0, 'Syntax error: %s', $st->{line}->{cmd}); }		## msg
	my $x  = pop(@$stack);
	my $xt = pop(@$stype);
	my $xl = pop(@$sopl);

	my ($y, $yt, $yl);
	if ((~$opl) & OPL_unary) {	# is binary operator
		if ($#$stack<0) { return (0,0,0, 'Syntax error: %s', $st->{line}->{cmd}); }	## msg
		$y  = pop(@$stack);
		$yt = pop(@$stype);
		$yl = pop(@$sopl);
	}

	#-------------------------------------------------------
	# constant
	#-------------------------------------------------------
	if ($yt eq 'const_var') {
		if ($op ne '=' || $xt ne 'const') {
			return (0,0,0, 'The value assigned to const(%s) is not a constant', $y);
		}
		$st->{const}->{$y} = $x;
		return ($x, 'const');
	}

	#-------------------------------------------------------
	# function
	#-------------------------------------------------------
	if ($op eq '%r') {
		return $self->p2e_function($st, $x, $xt, $xl, $y, $yt, $yl);
	}

	#-------------------------------------------------------
	# object method
	#-------------------------------------------------------
	if ($op eq '%f')  {
		return ("$y\-\>$x", 'object-method');
	}

	#-------------------------------------------------------
	# Commas are arrayed
	#-------------------------------------------------------
	if ($op eq ',' || $op eq '=>')  {
		if (ref($yt) eq 'ARRAY') {
			push(@$y,  $x);
			push(@$yt, $xt);
			push(@$yl, $xl);
		} else {
			$y  = [$y,  $x];
			$yt = [$yt, $xt];
			$yl = [$yl, $xl];
		}
		if ($op eq '=>') {
			my $p = $#$yt-1;
			if ($yt->[$p] eq 'obj') {
				$y->[$p]  = "'$y->[$p]'";
				$yt->[$p] = 'const';
			}
		}
		return ($y, $yt, $yl);
	}

	#-------------------------------------------------------
	# other
	#-------------------------------------------------------
	if ($xt eq 'obj') { $x = $self->get_object($st, $x); }
	if ($yt eq 'obj') { $y = $self->get_object($st, $y); }
	$xl = ref($xl) ? $OPR{','} : $xl;
	$yl = ref($yl) ? $OPR{','} : $yl;
	if (!ref($x) && $xl < $opl) { $x = "($x)"; }
	if (!ref($y) && $yl < $opl) { $y = "($y)"; }

	if ($op eq '#')  {			# array element. ex) argv#0, array#1
		if ($x =~ /^\-\d+$/) {		# array#-1
			$x++;
			$x = $x<0 ? $x : '';
			return ("$y\-\>[\$#$y$x]");
		}
		return ("$y\-\>[$x]");
	}

	if ($op eq '->')  {			# hash element
		if ($x =~ /^([\"\'])([A-Za-z_]\w*)\1$/) {
			$x = $2;		# dequote "aaa" -> aaa
		}
		if ($yt eq 'string') {
			return ("${VAR_ROOT}->{$y}\-\>{$x}");
		}
		return ("$y\-\>{$x}");
	}

	if ($op eq '@')  { return ("\@\{$x\}");   }	# dereference array
	if ($op eq '##') { return ("\$\#\{$x\}"); }	# array maximum element index

	#-------------------------------------------------------
	# array assignment. ex) (x,y,z) = func()
	#-------------------------------------------------------
	if ($op eq '=' && ref($y) eq 'ARRAY')  {
		if (grep { $_ != 'obj'} @$yt) {
			return (0,0,0, "Left array contains other than object: %s", join(',', @$y));
		}

		my @ary = $self->get_objects_array($st, $y, $yt);
		$y = "(" . join(',', @ary) . ")";

		# (x,y,z) = (1,2,3) : arrar to array
		if (ref($x) eq 'ARRAY') {
			$x = "(". join(',', @$x) . ")";
		}
		return ("$y=$x");
	}

	#-------------------------------------------------------
	# general unary operator
	#-------------------------------------------------------
	if (ref $x eq 'ARRAY') {
		$x  = '(' . join(',', $self->get_objects_array($st, $x, $xt)) . ')';
	}
	if ($opl & OPL_unary) {
		my $a  = ($opl & OPL_unary_right) ? "$x$op" : "$op$x";
		my $at = '';
		if ($xt eq 'const') {
			$a  = eval($a);
			if ($a =~ /[^\-\d\.]/) { $a = $self->into_single_quot($a); }
			if ($a eq '') { $a="''"; }
			$at = 'const';
		}
		return ($a, $at, $opl);
	}

	#-------------------------------------------------------
	# general binary operator
	#-------------------------------------------------------
	if ($opl & OPL_right_to_left && $op =~ /=$/ && $yt eq 'const') {	# "a=b" assignment
		return (0,0,0, "Can not modify constant");
	}
	if (!ref($x) && $xl==$opl && (~$opl & OPL_right_to_left)) { $x = "($x)"; }
	if (!ref($y) && $yl==$opl && ( $opl & OPL_right_to_left)) { $y = "($y)"; }

	my $a  = "$y$op$x";
	my $at = '';
	if ($xt eq 'const' && $yt eq 'const') {
		$a  = eval($a);
		if ($a =~ /[^\-\d\.]/) { $a = $self->into_single_quot($a); }
		if ($a eq '') { $a="''"; }
		$at = 'const';
	}
	if ($op eq '..') {
		$a   = "[$a]";
		$opl = OPL_max;
	}
	return ($a, $at, $opl);
}

#-------------------------------------------------------------------------------
# poland to expression, function
#-------------------------------------------------------------------------------
sub p2e_function {
	my $self = shift;
	my ($st, $x, $xt, $xl, $y, $yt, $yl) = @_;
	my $local = $st->{local};

	#-----------------------------------------------------------------------
	# 入れ子を許可しない関数
	#-----------------------------------------------------------------------
	if (!$st->{last_op} && $BlockStatement{$y}) {
		$self->error_from($st->{line}, '"%s" cannot be written inside an expression.', $y);
		return;
	}

	#-----------------------------------------------------------------------
	# local variable declaration
	#-----------------------------------------------------------------------
	if ($y eq 'local') {
		my $x2 = ref($x)  ? $x  : [$x];
		   $xt = ref($xt) ? $xt : [$xt];
		my %h;
		foreach(@$x2) {
			my $t = shift(@$xt);
			if ($t eq 'const')	{ return (0,0,0, 'Illegal local variable with constant: %s', $_); }	## msg
			if ($t ne 'obj')	{ return (0,0,0, 'Illegal local variable format.'); }			## msg
			if ($_ !~ /^[a-z_]\w*$/){ return (0,0,0, 'Illegal local variable name: %s', $_); }		## msg
			if ($ReservedVars{$_})	{ return (0,0,0, 'This name is reserved: %s', $_); }			## msg
			if ($h{$_})		{ return (0,0,0, 'Duplicate variable name in one local(): %s', $_); }	## msg
			$h{$_} = 1;
		}

		if (!ref($x)) {
			$local->{$x}=1;
			return ("my \$$x", 'local_var');
		}
		my $vars='';
		foreach(@$x2) {
			$local->{$_}=1;
			$vars .= "\$$_,";
		}
		chop($vars);
		return ("my($vars)", 'local_var');
	}

	#-------------------------------------------------------
	# constant variable declaration
	#-------------------------------------------------------
	if ($y eq 'const' || $y eq 'constant') {
		if ($xt ne 'obj')		{ return (0,0,0, 'Illegal constant format.'); }		## msg
		if ($ReservedVars{$x})		{ return (0,0,0, 'This name is reserved: %s', $x); }	## msg
		if ($x !~ /^[A-Za-z_]\w*$/)	{ return (0,0,0, 'Illegal constant name: %s', $x); }	# not needs
		if ($st->{local}->{$x})		{ return (0,0,0, 'Already used as a local variable: %s', $x); }	## msg
		return ($x, 'const_var');
	}

	#-----------------------------------------------------------------------
	# ifexec
	#-----------------------------------------------------------------------
	if ($y eq 'ifexec') {
		my @ary = $self->get_objects_array($st, $x, $xt);
		if (2<$#ary) {
			return (0,0,0, 'Few many arguments: %s', $y);	## msg
		}
		if ($#ary <= 2 && $ary[1] !~ /^\x01begin\.\d+$/ || $#ary == 2 && $ary[2] !~ /^\x01begin\.\d+$/) {
			return (0,0,0, 'Illegal arguments: %s', $y);	## msg
		}
		$st->{line}->{code} = 1;
		return ("if ($ary[0]) {");
	}
	if ($y eq 'elsif') {
		my @ary = $self->get_objects_array($st, $x, $xt);
		if ($#ary != 0) {
			return (0,0,0, '"%s" must have one argument.', $y);	## msg
		}
		$st->{line}->{code} = 1;
		return ("} elsif ($ary[0]) {");
	}

	#-----------------------------------------------------------------------
	# foreach
	#-----------------------------------------------------------------------
	if ($y eq 'forexec' && $st->{pragma}->{strict}) {
		return (0,0,0, "Can't be used in strict mode: %s", $y);		## msg
	}
	if ($y =~ /^foreach(?:|_hash|_keys|_num)/ || $y eq 'forexec') {
		$st->{line}->{save_lnum} = 1;
		$st->{line}->{code}      = 1;

		my ($var, @arg) = $self->get_objects_array($st, $x, $xt);
		my $is_arg2 = ($#arg == 1 && $arg[1] =~ /^\x01begin\.\d+$/);
		my $is_arg3 = ($#arg == 2 && $arg[2] =~ /^\x01begin\.\d+$/);

		my $ax = ref($x)  ? $x  : [ $x  ];
		my $at = ref($xt) ? $xt : [ $xt ];
		my $at0= $at->[0];

		my $foreach = 'foreach';
		my $after   = " $var=\$_;";
		if ($at0 eq 'local_var' && $var !~ /,/ || $at0 eq 'obj' && $st->{local}->{$ax->[0]}) {
			$foreach = "foreach $var ";
			$after   = '';

		} elsif ($at0 ne 'obj') {
			return (0,0,0, 'Requires loop variable as first argument: %s', $y);	## msg
		}

		if ($is_arg2 && ($y eq 'foreach' || $y eq 'forexec')) {
			my $ary = $self->dereference_array($arg[0]);
			return ("$foreach($ary) {$after");
		}

		if ($is_arg2 && $y eq 'foreach_hash') {
			return ("my \$H=$arg[0]; my \$K=\$H->{_order} || [keys(\%\$H)]; foreach(\@\$K) { "
				. "$var={key=>\$_,val=>\$H->{\$_}};");
		}

		if ($is_arg2 && $y eq 'foreach_keys') {
			my $ary = '$H->{_order} ? @{$H->{_order}} : keys(%$H)';
			return ("my \$H=$arg[0]; $foreach($ary) {$after");
		}

		if ($is_arg2 && $y eq 'foreach_num') {
			return ("$foreach(1..int($arg[0])) {$after");
		}
		if ($is_arg3 && $y eq 'foreach_num') {
			return ("$foreach(int($arg[0])..int($arg[1])) {$after");
		}

		return (0,0,0, 'Illegal arguments: %s', $y);	## msg
	}

	#-----------------------------------------------------------------------
	# ifxxx()
	#-----------------------------------------------------------------------
	if ($InlineIf{$y}) {
		my $func = substr($y, 2);
		my $ax = ref($x)  ? $x  : [$x];
		my $at = ref($xt) ? $xt : [$xt];
		my $xl = ref($xl) ? $xl : [$xl];

		# stack: $y=ifnext $x=array[]
		#   ---> if ary[0] next array[1..]
		push(@{$st->{stack}},  'if', shift(@$ax), $func);
		push(@{$st->{stype}}, 'obj', shift(@$at), 'obj');
		push(@{$st->{sopl}},OPL_max, shift(@$xl), OPL_max);
		unshift(@{$st->{poland}}, '%r', ',', '%r');

		if (!@$ax) { return ('', 'none'); }
		return 0<$#$ax ? ($ax, $at, $xl) : ($ax->[0], $at->[0], $xl->[0]);
	}

	if ($y eq 'if' || $y eq 'ifset') {
		my @arg = $self->get_objects_array($st, $x, $xt);
		my $axl = ref($xl) ? $xl : [$xl];

		my $parentheses = sub {
			my $opl = shift;
			foreach(0..$#arg) {
				if ($axl->[$_]<$opl) { $arg[$_]="($arg[$_])"; }
			}
		};

		if ($y eq 'if') {
			if ($#arg==1 || $#arg==2) {
				&$parentheses($OPR{'?'});	# <<:higher op / vv: lower op
				my $else = $#arg==2 ? $arg[2] : 'undef';
				return ("$arg[0] ? $arg[1] : $else", '', $OPR{'?'});
			}
		}
		if ($y eq 'ifset') {
			&$parentheses($OPR{'&&'});
			if ($#arg==3) {
				return ("$arg[1] = $arg[0] ? $arg[2] : $arg[3]", '', $OPR{'='});
			} elsif ($#arg==2) {
				return ("$arg[0] && ($arg[1]=$arg[2])", '', $OPR{'&&'});
			}
		}
		return (0,0,0, 'Illegal arguments: %s', $y);	## msg
	}

	#-----------------------------------------------------------------------
	# array/hash/flag
	#-----------------------------------------------------------------------
	if ($y eq 'array') {
		# array (a, b, c, ...) to [a, b, c]
		# arrayq(a, b, c, ...) to ['a', 'b', 'c']
		my @ary = $self->get_objects_array($st, $x, $xt);
		$x = join(',', @ary);
		return ("[$x]", 'array');
	}

	if ($y eq 'hash' || $y eq 'hashx') {
		# hash (a1, b1, a2, b2, ...) to {a1=>b1, a2=>b2}
		# hashq(a1, b1, a2, b2, ...) to {'a1'=>'b1', 'a2'=>'b2'}
		#      {a1, b1, a2, b2, ...} to {'a1'=>b1, 'a2'=>b2}	// = hashx()
		my @ary;
		if ($y eq 'hash') {
			@ary = $self->get_objects_array($st, $x, $xt);
		} else {
			my $at= ref($xt) ? $xt : [$xt];
			my @a = $self->array2quoted_string(ref($x) ? @$x : $x);
			my @b = $self->get_objects_array($st, $x, $xt);
			if (@b) {			# for none argument, ex) "{}"
				foreach(0..$#a) {
					push(@ary, (($_ & 1 || $at->[$_] eq 'const') ? $b[$_] : $a[$_]));
				}
			}
		}
		my $x='';
		@ary = grep { $_ ne '' } @ary;
		while(@ary) {
			my $a=shift(@ary);
			my $b=shift(@ary) || '';
			$x .= "$a=>$b,";
		}
		chop($x);
		return("{$x}", 'hash');
	}

	if ($y eq 'flag') {
		# flag (a, b, c, ...) to {a=>1, b=>1, ...}
		# flagq(a, b, c, ...) to {'a'=>1, 'b'=>1, ...}
		my @ary = $self->get_objects_array($st, $x, $xt);
		if (@ary) {
			$x = "{" . join('=>1,', @ary) . "=>1}";
		} else {
			$x='{}';
		}
		return ($x, 'hash');
	}

	#-----------------------------------------------------------------------
	# function need save line number
	#-----------------------------------------------------------------------
	$st->{line}->{save_lnum} = 1;

	#-----------------------------------------------------------------------
	# perl's core functions
	#-----------------------------------------------------------------------
	if (exists $CoreFuncs{$y}) {
		my $c   = $CoreFuncs{$y};
		my @arg = $self->get_objects_array($st, $x, $xt);

		my $max = ($c & 0xf000)>>12;
		if (($c & CF_arg_one) && $#arg != 0 || $c==CF_control && @arg
		 || $max && $max<=$#arg) {
			return (0,0,0, 'Illegal arguments: %s', $y);	## msg
		}
		if ($c == CF_control) { return ($y) }	# next, last

		foreach(0..3) {
			if ($c & ( 0x10<<$_) && defined $arg[$_]) { $arg[$_] = $self->dereference_array($arg[$_]); }
			if ($c & (0x100<<$_) && defined $arg[$_]) { $arg[$_] = "\%{$arg[$_]}"; }
		}
		if ($c & 0x80) {
			foreach(4..$#arg) { $arg[$_] = "\@{$arg[$_]}"; }
		}
		my $a = join(',', @arg);
		if ($c & CF_return_array) {
			return ("[$y($a)]");
		}
		return ("$y($a)");
	}

	#-----------------------------------------------------------------------
	# inline functions
	#-----------------------------------------------------------------------
	# is_int => { f=>'#0 =~ /^-?\d+$/', min=>'=~', max=>'=~' },
	if ($InlineFuncs{$y}) {
		my $h = $InlineFuncs{$y};
		my @arg = $self->get_objects_array($st, $x, $xt);
		my $args= $h->{arg};
		if ($#arg+1 < $args) {
			return (0,0,0, 'Illegal arguments: %s', $y);	## msg
		}
		my $func = $h->{f};

		my @par;
		if ($func =~ /%\d/) {	# replace(a,b,c,mod) f=>'#0 =~ s|%1|%2|g" to "a =~ s!b!c!mod"
			my $at = ref($xt) ? $xt : [$xt];
			@par = @arg;

			my $mod = $par[$args];
			if ($mod ne '') {
				if ($xt->[$args] ne 'const') {
					return (0,0,0, '%d-th argument must be a string: %s', $args+1, $y);	## msg
				}
			}
			$func .= ($mod =~ s/[^a-df-qs-z]//rg);		# exclude 'e' and 'r'

			foreach(0..$#par) {
				if (index($func, "%$_")<0) { next; }
				my $t = $xt->[$_];

				if ($t eq 'obj') { next; }
				if (($t eq 'string' || $t eq 'const') && $par[$_] =~ /^"(.*)"$/) {
					$par[$_]=$1;	# "xxx" to xxx
					next;
				}
				if ($t eq 'const') {
					$par[$_]=eval($par[$_]);
					next;
				}
				return (0,0,0, "%d-th's argument must be strings or variable or constant: %s", , $_+1, $y);	## msg
			}
			foreach(@par) {
				$_ =~ s/((?:\\.|[^\\!\@])*)([\\!\@])?/$1 . ($2 ? "\\$2" : '')/seg;
			}
		}

		my $al  = ref($xl) ? $xl : [$xl];
		my $opl = $OPR{$h->{max}} || 0;
		foreach(0..$#arg) {
			if ($al->[$_]<$opl) { $arg[$_]="($arg[$_])"; }
		}
		$func =~ s/#(\d+)/$arg[$1]/g;
		$func =~ s/%(\d+)/$par[$1]/eg;
		return ($func, $OPR{$h->{min}} || OPL_max);
	}

	#-----------------------------------------------------------------------
	# builtin functions
	#-----------------------------------------------------------------------
	if ($BuiltinFunc{$y}) {
		$st->{builtin}->{$y} = 1;
		my @arg = $self->get_objects_array($st, $x, $xt);
		my $a   = join(',', @arg);
		return ("&$y($a)");
	}

	#-----------------------------------------------------------------------
	# general function call
	#-----------------------------------------------------------------------
	if ($yt eq 'obj') {
		my ($class, $func) = $self->get_object_separate($st, $y, 1);
		my $xo = join(',', $self->get_objects_array($st, $x, $xt));
		return("$class\-\>$func($xo)");
	}
	# call object method
	if ($yt eq 'object-method') {
		$st->{line}->{check_break} = 1;
		my $xo = join(',', $self->get_objects_array($st, $x, $xt));
		return ("$y($xo)");
	}

	#-----------------------------------------------------------------------
	# error
	#-----------------------------------------------------------------------
	return (0,0,0, "Illegal function: %s", "$y()");		## msg
}

#-------------------------------------------------------------------------------
# Evaluate element
#-------------------------------------------------------------------------------
sub get_element_type {
	my $self = shift;
	my $st   = shift;
	my $el   = shift;	# element

	if (exists $OPR{$el}) { return ($el, 'op'); }	# operator

	if ($el =~ /^\x00(\d+)\x00$/) {			# string
		my $str  = $st->{strbuf}->[$1];
		my $type = substr($str,0,1) eq "'" ? 'const' : 'string';
		if ($type eq 'string') {
			my $local = $st->{local};
			my $const = $st->{const};
			my $exists_var;
			$str =~ s!\x01(.*?)(?:#(\d+))?\x01!
				my $num  = $2;
				my $data = $self->get_object($st, $1);
				if ($data =~ /^\'(.*)\'$/) {
					$data = $1;	# variable name is constant
				} else {
					$exists_var = 1;
					$data =~ s/^\$(\w+)$/\${$1}/;
				}
				$data;
			!eg;
			if (!$exists_var) { $type='const'; }
		}
		return ($str, $type);
	}

	if ($el =~ /^(\d+|\d+\.\d+|\d*\.\d+)([KMGT]|week|day|hour|min|sec)$/) {		# Number with unit
		$el = $1 * $Unit2Num{$2};
		return ($el, 'const');
	}
	if ($el =~ /^\d+(?:\.\d+)?(?:[Ee]m?\d+)?$/) {
		$el =~ tr/m/-/;
		return ($el, 'const');			# is number
	}
	if ($el =~ /^0[xb][\dA-Fa-f]+$/) {		# binary, hex
		return (oct($el), 'const');
	}

	if ($el =~ /^\x01begin(?:_func)?\.\d+$/) {	# code block
		$st->{begin_code}++;
		return ($el, 'code');
	}
	if ($el =~ /^\x01begin_(\w*).\d+$/) {
		if ($1 eq 'array')  { return ($el, 'array');  }
		if ($1 eq 'string') { return ($el, 'string'); }
		if ($1 eq 'hash' || $1 eq 'hash_order') {
			return ($el, 'hash');
		}
		return (0, 'error');
	}

	if ($el =~ /^(\d+)\.[A-Za-z_]\w*$/) {	# Integer with text. ex) 10.is_cache_on
		return ($1, 'const');
	}

	if ($el eq 'true'  || $el eq 'yes') { return (1, 'const'); }
	if ($el eq 'false' || $el eq 'no' ) { return (0, 'const'); }

	if ($el eq $NO_ARG)     { return ('',      'none'); }
	if ($el eq 'undef')     { return ('undef', 'const'); }
	if ($el eq 'new.array') { return ('[]',    'hash'); }
	if ($el eq 'new' || $el eq 'new.hash') { return ('{}', 'hash'); }

	if (exists($st->{const}->{$el})) {		# constant
		return ($st->{const}->{$el}, 'const');
	}
	if ($el =~ /^[A-Za-z_]\w*(?:\.\w+)*$/) {
		return ($el, 'obj');
	}

	return (0, 'error');
}

#-------------------------------------------------------------------------------
# object name to object
#-------------------------------------------------------------------------------
# ex) a.b to $R->{a}->{b}
#
sub get_object {
	my $self = shift;
	my ($st, $name, $in_string) = @_;
	my $local = $st->{local};
	my $const = $st->{const};
	if (exists($const->{$name})) { return $const->{$name}; }

	if ($local->{$name}) {
		return $in_string ? "\${$name}" : "\$$name";
	}
	my ($class, $name) = $self->get_object_separate($st, $name);
	return "$class\-\>{$name}";
}

sub get_object_separate {
	my $self  = shift;
	my ($st, $name, $is_func) = @_;
	my $local = $st->{local};

	my @ary   = split(/\./, $name);
	my $obj   = $VAR_ROOT;
	my $first = $ary[0];
	if ($local->{$first}) {
		$obj="\$$first"; shift(@ary);
	} elsif (!$is_func) {
		$st->{ref_obj}->{$first} = $name;
	}

	@ary = map {
		(index($_, '.')>=0 || $_ =~ /^\d/) ? "'$_'" : $_
	} @ary;

	my $last = pop(@ary);
	foreach(@ary) {
		$obj .= "->{$_}";
	}
	return ($obj, $last);
}

sub get_objects_array {
	my $self  = shift;
	my $st    = shift;
	my $names = ref($_[0]) ? shift : [shift];
	my $types = ref($_[0]) ? shift : [shift];

	my @ary;
	foreach(0..$#$names) {
		my $name = $names->[$_];
		my $type = $types->[$_];
		if ($type eq 'none') { next; }
		if ($type eq 'obj') {
			$name = $self->get_object($st, $name);
		}
		push(@ary, $name);
	}
	return @ary;
}

#-------------------------------------------------------------------------------
# arrayq(aa,bb) to array('aa','bb')
#-------------------------------------------------------------------------------
sub array2quoted_string {
	my $self = shift;
	my @ary;
	foreach(@_) {
		my $x = $_;
		$x =~ s/\\/\\\\/g;
		$x =~ s/'/\\'/g;
		push(@ary, "'$x'");
	}
	return @ary;
}

#-------------------------------------------------------------------------------
# [1,2,3] to (1,2,3), $var to @{$var}
#-------------------------------------------------------------------------------
sub dereference_array {
	my $self = shift;
	my $ary  = shift;
	return $ary =~ /^\[(.*)\]$/ ? "$1" : "\@{$ary}";
}

################################################################################
# [05] process block
################################################################################
sub process_block {
	my $self = shift;
	my ($st, $lines) = @_;

	push(@$lines, { block_end => -1 });
	return $self->splice_block($st, $lines, -1);
}

sub splice_block {
	my $self = shift;
	my ($st, $lines, $num) = @_;

	my @buf;
	while(@$lines) {
		my $line = shift(@$lines);
		if ($line->{block_end} == $num) { last; }

		push(@buf, $line);
		if (!exists($line->{exp})) { next; }

		while($line->{exp} =~ /^(.*?)\x01begin(?:_(\w+))?\.(\d+)(.*)$/) {
			my $left = $1;
			my $type = $2;
			my $func = $type eq 'func';
			my $right= $4;
			my $ary  = $self->splice_block($st, $lines, $3);

			if ($type ne '' && !$func) {		# non code block
				my ($x, @err) = $self->rewrite_block_non_code($st, $ary, $type);
				if (@err) {
					$self->error_from($line, @err);
				}
				$line->{exp} = $left . $x . $right;
				next;
			}

			# rewrite to code block
			my @sub = split(/\n/, $SUB_HEAD . ($func ? $SUB_FUNC_ADD : ''));
			my $sub = shift(@sub);
			foreach(@sub) {
				my %h = %$line;		# copy line
				$h{exp}  = $_;
				$h{code} = 1;
				$h{save_lnum} = 0;
				push(@buf, \%h);
			}
			my %h = %$line;	# copy
			$line->{exp}  = (!$line->{code} && $line->{replace} ? "$VAR_OUT.=" : '') . $left . $sub;
			$line->{code} = 1;
			push(@buf, @$ary);

			$h{exp}     = '}' . $right;
			$h{replace} = 0;
			$h{save_lnum} = 0;
			unshift(@$lines, \%h);
		}
	}
	return \@buf;
}

#-------------------------------------------------------------------------------
# rewrite block to array/hash/string
#-------------------------------------------------------------------------------
sub rewrite_block_non_code {
	my $self = shift;
	my ($st, $lines, $type) = @_;

	my @expbuf;
	my @buf;
	my $lnum = -1;
	foreach(@$lines) {
		my $data = $_->{data};
		if (exists($_->{exp})) {
			my $exp=$_->{exp};
			if ($_->{replace}) {
				push(@expbuf, $_->{opl} < $OPR{'.'} ? "($exp)" : $exp);
			} else {
				push(@expbuf, "(($_->{exp}),'')");
			}
			$data = "\x00$#expbuf\x00";
		}
		if ($lnum == $_->{lnum}) {
			$buf[$#buf] .= $data;
			next;
		}
		$lnum=$_->{lnum};
		push(@buf, $data);
	}

	# preprocess
	if (@buf && $buf[0]     =~ /^\s*$/) { shift(@buf); }
	if (@buf && $buf[$#buf] =~ /^\s*$/) { pop(@buf);   }

	# Remove spaces at the beginning and end of each line.
	if ($type ne 'string') {
		foreach(@buf) {
			$_ =~ s/^\s+//;
			$_ =~ s/\s+$//;
		}
	}

	if ($type eq 'string') {
		my $str = join('', @buf);
		return $self->rb_squot(\@expbuf, $str);
	}

	if ($type eq 'array') {
		my @x = map { $self->rb_squot(\@expbuf, $_) } @buf;
		return '[' . join(',', @x) . ']';
	}

	if ($type ne 'hash' && $type ne 'hash_order') {
		return "'<!-- begin type error -->'";
	}

	# begin_hash, begin_hash_order
	my %h;
	my @order;
	my @out;
	my $use_order = $type eq 'hash_order';
	my $cmd_in_key;
	foreach(@buf) {
		if ($_ =~ /^\s*$/) { next; }

		if ($_ !~ /^(.*?)\s*=\s*(.*)/) {
			$self->error_from($st->{line}, 'Illegal hash format: %s (in %s)', $_, "begin_$type");
			next;
		}
		my $key = $1;
		my $val = $2;
		if ($key eq '_order' && $val) { $use_order=$val; next; }

		if (exists($h{$key})) {
			$self->error_from($st->{line}, 'Duplicate hash key: %s (in %s)', $key, "begin_$type");
			next;
		}
		$cmd_in_key ||= $key =~ /\x00/;

		$h{$key}=1;
		$key = $self->rb_squot(\@expbuf, $key);
		$val = $self->rb_squot(\@expbuf, $val);
		push(@order, $key);
		push(@out,  "$key=>$val");
	}
	if ($use_order && $cmd_in_key) {
		return(0, 'Variables cannot be used as keys in ordered hash: %s', "begin_$type");	## msg
	}
	if ($use_order) {
		my $ord = join(',',@order);
		push(@out, "_order=>[$ord]");	# 出力
	}
	return '{' . join(',', @out) . '}';
}

sub rb_squot {
	my $self = shift;
	my $exp  = shift;
	my @ary  = split(/\x00/, shift);
	my $o = '';
	while(@ary) {
		my $x = shift(@ary);
		if ($x ne '') { $o .= '.' . $self->into_single_quot($x); }
		my $y = shift(@ary);
		if ($y ne '') {
			$y = $exp->[$y];
			if ($y ne '') { $o .= ($o =~ /\.\d+$/ ? ' ' : '') . ".$y"; }
		}
	}
	if ($o eq '') { return "''"; }
	return $o =~ s/^\.//r;
}


################################################################################
# [06] post process
################################################################################
sub post_process {
	my $self = shift;
	my ($st, $lines) = @_;

	#----------------------------------------------------------------------
	# chain line
	#----------------------------------------------------------------------
	my @buf;
	my $prev;
	foreach(@$lines) {
		if ($_->{delete}) { next; }
		if (!exists($_->{exp}) && !exists($_->{out_with_code})) {
			$_->{out} = exists($_->{out}) ? $_->{out} : $_->{data};
			if (exists($prev->{out})) {
				$prev->{out} .= $_->{out};
				next;
			}
		}
		push(@buf, $_);
		$prev = $_;
	}

	#----------------------------------------------------------------------
	# write code
	#----------------------------------------------------------------------
	my @out = ($SUB_HEAD);
	my $tab = "\t" x $DefaultIndentTAB;

	my $is_func = $st->{pragma}->{function};
	$is_func && push(@out, $tab . "${VAR_ROOT}->{IsFunction}=1;\n");

	foreach(keys(%{$st->{builtin}})) {
		my @lines = split(/\n/, $BuiltinFunc{$_});
		push(@out, $tab . "sub $_ {\n");
		foreach(@lines) {
			push(@out, "$tab$_\n");
		}
		push(@out, $tab . "}\n");
	}
	push(@out, "\n");

	# main code
	foreach(@buf) {
		my $tab = "\t" x ($_->{block_lv} + $DefaultIndentTAB);
		if (exists($_->{out})) {
			if ($is_func) { next; }

			my $text = $_->{out};
			if ($text eq '') { next; }
			if ($text =~ /^[\s]+$/) {
				$text = '"' . ($text =~ s/\n/\\n/rg) . '"';
			} else {
				$text = $self->into_single_quot($text);
			}

			push(@out, $tab . "$VAR_OUT.=$text;\n");
			if ($_->{out_with_code}) {
				push(@out, $tab . "$_->{out_with_code}\n");
			}
			next;
		}
		# code
		my $lnum = $_->{save_lnum} ? "$VAR_LNUM=" . int($_->{lnum}) . ';' : '';
		if ($_->{code}) {
			push(@out, $tab . $lnum . $_->{exp} . "\n");	# no semicolon
		} elsif (!$is_func && $_->{replace}) {
			my $exp = $_->{opl} <= $OPR{'.='} ? "($_->{exp})" : $_->{exp};		# ".=" is right to left, include equal
			push(@out, $tab . $lnum . "$VAR_OUT.=" . $exp . ";\n");
		} else {
			push(@out, $tab . $lnum . $_->{exp} . ";\n");
		}
	}
	$is_func && push(@out, $tab . "return;\n");
	push(@out, "}\n");
	return \@out;
}

################################################################################
# subroutine
################################################################################
#-------------------------------------------------------------------------------
# string data into ''
#-------------------------------------------------------------------------------
sub into_single_quot {
	my $self = shift;
	foreach(@_) {
		if ($_ =~ /^[1-9]\d+$/) { next; }	# 1234
		if ($_ =~ /^\d+\.\d*$/) { next; }	# 12.34
		$_ =~ s/([\\'])/\\$1/g;
		$_ = "'$_'";
	}
	return $_[0];
}

1;
