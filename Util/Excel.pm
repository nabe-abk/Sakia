use strict;
#-------------------------------------------------------------------------------
# Excel file manipulation
#							(C)2020-2023 nabe@abk
#-------------------------------------------------------------------------------
# Use commands: rm zip unzip and shell
#
package Sakia::Util::Excel;
our $VERSION = '1.26';
#-------------------------------------------------------------------------------
use Fcntl;
## mskip-all: for message checker
################################################################################
# constructor
################################################################################
sub new {
	my $self = bless({
		maxSheets => 65000
	}, shift);
	my $ROBJ = $self->{ROBJ} = ref($_[0]) ? shift : undef;

	my $file = shift;
	my $tmp  = shift ||
		 ($ROBJ ? $ROBJ->get_tmpdir() : $ENV{TMPDIR} || $ENV{TEMP} || $ENV{TMP} || '/tmp');
	$tmp =~ s|/+$||;

	$self->{tmp}   = $tmp;
	$self->{DEBUG} = shift;

	#-------------------------------------------------------------
	# init working directory
	#-------------------------------------------------------------
	my $wd = $tmp;
	{
		my $f = $file;
		if ($f !~ m|([^/]+)\.xlsx|i) {
			return $self->error("Compatible for '.xlsx' file only: $file");
		}
		$wd .= '/' . $1;
		my $ext;
		if ($self->{DEBUG}) {
			$ext = '0';
			system("rm -rf '$wd.$ext'");
		} else {
			foreach(1..100) {
				$ext = int(rand(100000000));
				if (!-e "$wd.$ext") { last; }
			}
		}
		$wd .= ".$ext";
		if (!$self->{DEBUG} && !mkdir($wd) || !-r $wd || !-w $wd || !-x $wd) {
			return $self->error("working direcotry '$wd' error!");
		}
	}
	$self->{wd} = $wd;

	#-------------------------------------------------------------
	# extract file
	#-------------------------------------------------------------
	$self->extract($file, $wd);
	if (!-r $wd) {
		return $self->error("unzip failed!");
	}

	#-------------------------------------------------------------
	# parse xlsx
	#-------------------------------------------------------------
	$self->parse();

	return $self;
}
#-------------------------------------------------------------------------------
# destoractor
#-------------------------------------------------------------------------------
sub DESTROY {
	my $self = shift;
	my $wd   = $self->{wd};

	if ($self->{DEBUG} || !$wd || !-d $wd) { last; }
	system("rm -rf '$wd'");
}

################################################################################
# main
################################################################################
#-------------------------------------------------------------------------------
# parse Excel XML
#-------------------------------------------------------------------------------
sub parse {
	my $self = shift;
	my $wd   = $self->{wd};

	$self->{file_wb_rels}   = "xl/_rels/workbook.xml.rels";
	$self->{file_workbook}  = "xl/workbook.xml";
	$self->{file_calcChain} = "xl/calcChain.xml";
	$self->{file_strings}   = "xl/sharedStrings.xml";

	#-------------------------------------------------------------
	# _rels/workbook.xml.rels
	#-------------------------------------------------------------
	my $rels = $self->{rels} = {};
	{
		my $wb_rels  = $self->load_file( $self->{file_wb_rels} );
		if ($wb_rels !~ m|(.*?<Relationship[^>]*>)(.*)</Relationships>|s) {
			return $self->error("format error: _rels/workbook.xml.rels");
		}
		$self->{wb_rels_header} = $1;
		$self->{wb_rels_footer} = '</Relationships>';

		my $str = $2;
		my @ary;
		$str =~ s!<Relationship (.+?) ?/>!push(@ary, $1)!eg;
		foreach(@ary) {
			my %at;
			$_ =~ s!([^ =]+)="([^\"]+)"!$at{$1}=$2!eg;
			$rels->{ $at{Id} } = \%at;
		}
	}

	#-------------------------------------------------------------
	# sharedStrings.xml
	#-------------------------------------------------------------
	my $strings = [];
	{
		my $strdata = $self->load_file( $self->{file_strings} );
		if ($strdata =~ m|^(.*?)(<si>.*</si>)(.*?)$|s) {
			$self->{strings_header} = $1;
			$self->{strings_footer} = $3;

			my $data = $2;
			$data =~ s|(<si>.*?<t[^>]*>(.*?)</t>.*?</si>)|
				push(@$strings, $1);
				'';
			|sreg;
			foreach(@$strings) {
				$_ =~ s|<rPh[^>]*>.*?</rPh>||g;		# remove ruby
			}

			$self->{DEBUG} && print "Found: " . ($#$strings+1) . " strings in $self->{file_strings}\n";
		} else {
			$self->{strings_header} = '<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="0" uniqueCount="0">';
			$self->{strings_footer} = '</sst>';
		}
		$self->{strings_header} =~ s/ count="\d+"//;		# remove Count
		$self->{strings_header} =~ s/ uniqueCount="\d+"//;	# remove uniqueCount
	}

	#-------------------------------------------------------------
	# workbook.xml and sheet.xml
	#-------------------------------------------------------------
	my $sheets  = $self->{sheets} = [];
	my $sheetId = {};
	{
		my $wb_xml = $self->load_file( $self->{file_workbook} );
		$wb_xml =~ s|(<workbookView .*?activeTab=")\d+(")|${1}0$2|;

		my %print_area;
		if ($wb_xml =~ m|^(.*?)<definedNames>(.*?)</definedNames>(.*)$|s) {
			$wb_xml = "$1$3";
			my $buf = $2;
			$buf =~ s|<definedName\b[^>]*\bname="_xlnm.Print_Area"[^>]*>([^!]+)!(\$[A-Z]+\$\d+:\$[A-Z]+\$\d+)</definedName>|
				$print_area{$1}=$2
			|eg;
		}

		my $sheet_data;
		if ($wb_xml =~ m|(.*)<sheets>(.*?)</sheets>(.*)|s) {
			$self->{"workbook.xml"}  = $wb_xml;
			$self->{workbook_header} = $1;
			$self->{workbook_footer} = $3;
			$sheet_data = $2;
		} else {
			return $self->error("sheet not found: workbook.xml");
		}

		my @ary;
		$sheet_data =~ s!<sheet (.+?) ?/>!push(@ary, $1)!seg;

		foreach(@ary) {
			my %sh = (__excel_sheet => 1);
			my %at;
			$_ =~ s!([^ =]+)="([^\"]+)"!$at{$1}=$2!eg;
			$sh{attr}       = \%at;
			$sh{name}       = $at{name};
			$sh{print_area} = $print_area{$at{name}};
			my $sid   = $at{sheetId};
			my $rid   = $at{'r:id'};
			my $file  = $rels->{$rid}->{Target};

			my $sheet_file = "xl/$file";
			my $rels_file  = $self->file_to_rels( $sheet_file );
			$sh{data} = $self->load_file( $sheet_file );
			$sh{rels} = $self->load_file( $rels_file  );
			$sh{cc}   = {};
			$sh{wbrel}= $rels->{$rid};
			delete $rels->{$rid};
			unlink( $sheet_file );
			unlink( $rels_file  );

			push(@$sheets, \%sh);
			$sheetId->{$sid} = \%sh;

			$self->{DEBUG} && print "Load: xl/$file name=$sh{name} rid=$rid id=$sid\n";

			# replace string data
			#	<v></v> to <si></si>
			$sh{data} =~ s|(<c [^>]* t="s"[^>]*>.*?)<v>(\d+)</v>(.*?</c>)|$1<_s>$strings->[$2]</_s>$3|g;
		}
	}
	#-------------------------------------------------------------
	# calcChain.xml
	#-------------------------------------------------------------
	my $calc_xml = $self->load_file( $self->{file_calcChain} );
	if ($calc_xml ne '') {
		if ($calc_xml !~ m|(.*?<calcChain[^>]*>)(.*)</calcChain>|s) {
			return $self->error("format error: calcChain.xml");
		}
		$self->{calcChain_header} = $1;
		$self->{calcChain_footer} = '</calcChain>';

		my $str = $2;
		my @ary;
		$str =~ s!<c (.+?) ?/>!push(@ary, $1)!eg;
		foreach(@ary) {
			my %at;
			$_ =~ s!([^ =]+)="([^\"]+)"!$at{$1}=$2!eg;
			my $id = $at{i};
			my $sc = $sheetId->{$id}->{cc};
			$sc->{$at{r}} = \%at;
		}
	}
}
#-------------------------------------------------------------------------------
# write new XLSX
#-------------------------------------------------------------------------------
sub write {
	my $self = shift;
	my $file = shift;
	if ($self->{write}) {
		return $self->error(__PACKAGE__ . " is write() once only!");
	}
	$self->{write}=1;

	$self->rewrite_xml();
	$self->pack($file);
}

#-------------------------------------------------------------------------------
# rewrite Excel XML
#-------------------------------------------------------------------------------
sub rewrite_xml {
	my $self = shift;
	my $wd   = $self->{wd};

	#-------------------------------------------------------------
	# workbook.xml and worksheets/sheet?.xml
	#-------------------------------------------------------------
	my $sheets = $self->{sheets};
	my $rels   = $self->{rels};
	my @strings;
	{
		my $data = $self->{workbook_header};
		$data =~ s|(<bookViews>.*?</bookViews>)|
			my $x=$1;
			$x =~ s/ xr2:uid="[\w\-]*"//gr;		# remove bookViews UID
		|e;
		### DO NOT REMOVE <bookViews>, DO NOT PRINT WHEN DELETE <bookViews>!!

		my $strh     = {};
		my $sheetIds = {};
		my %sheetNames;
		my $sheetsXML = '';
		my $printArea = '';
		foreach(0..$#$sheets) {
			my $sh  = $sheets->[$_];
			my $rel = $sh->{wbrel};
			my $rid = $self->generate_rid( $rel );
			my $sid = $self->generate_sheetId( $sheetIds );
			$rel->{Id}     = $rid;
			$rel->{Target} = $sh->{file} = 'worksheets/sheet' . ($_+1) . '.xml';
			$sh->{id} = $sid;

			my $name  = ($sh->{name} ne '' ? $sh->{name} : "s$sid");
			if ($sheetNames{$name}) { $name .= $sid; }
			$sheetNames{$name} = 1;

			$sheetsXML .= "<sheet name=\"$name\" sheetId=\"$sid\" r:id=\"$rid\"/>";
			if ($sh->{print_area}) {
				$printArea .= "<definedName name=\"_xlnm.Print_Area\" localSheetId=\"$_\">$name!$sh->{print_area}</definedName>";
			}

			# replace string data
			$sh->{data} =~ s!<_s>(.*?)</_s>!
				my $num = $strh->{$1} || (push(@strings, $1) -1);
				$strh->{$1} = $num;
				"<v>$num</v>";
			!seg;

			# remove tabSelected
			$sh->{data} =~ s|<sheetView ([^>]*)tabSelected="1"|<sheetView $1|;

			$self->write_file( "xl/$sh->{file}", $sh->{data});
			$self->write_file( $self->file_to_rels("xl/$sh->{file}"), $sh->{rels});

			$self->{DEBUG} && print "Write: xl/$sh->{file} name=$name rid=$rid id=$sid\n";
		}
		$data .= "<sheets>$sheetsXML</sheets>";
		if ($printArea) {
			$data .= "<definedNames>$printArea</definedNames>";
		}
		$data .= $self->{workbook_footer};
		$self->write_file($self->{file_workbook}, $data);
	}

	#-------------------------------------------------------------
	# _rels/workbook.xml.rels
	#-------------------------------------------------------------
	{
		my $data = $self->{wb_rels_header};

		foreach my $rel (values(%$rels)) {
			my $at = '';
			foreach(keys(%$rel)) {
				$at .= " $_=\"$rel->{$_}\"";
			}
			$data .= "<Relationship$at/>";
		}
		$data .= $self->{wb_rels_footer};
		$self->write_file($self->{file_wb_rels}, $data);
	}

	#-------------------------------------------------------------
	# calcChain.xml
	#-------------------------------------------------------------
	if ($self->{calcChain_header}) {
		my $data = $self->{calcChain_header};

		foreach my $sh (@$sheets) {
			my $cc = $sh->{cc};
			my $id = $sh->{id};
			foreach my $k (sort(keys(%$cc))) {	# sort() for to prevent open errors
				my $c  = $cc->{$k};
				my $at = '';
				$c->{i} = $id;
				foreach(keys(%$c)) {
					$at .= " $_=\"$c->{$_}\"";
				}
				$data .= "<c$at/>";
			}
		}
		$data .= $self->{calcChain_footer};
		$self->write_file($self->{file_calcChain}, $data);
	}
	#-------------------------------------------------------------
	# sharedStrings.xml
	#-------------------------------------------------------------
	{
		my $data = $self->{strings_header}
			 . join('', @strings)
			 . $self->{strings_footer};

		$self->{DEBUG} && print "Write: $self->{file_strings}, " . ($#strings+1) . " strings\n";

		$self->write_file($self->{file_strings}, $data);
	}
}

################################################################################
# sheet functions
################################################################################
#-------------------------------------------------------------------------------
# sheet name
#-------------------------------------------------------------------------------
sub get_sheet_name($) {
	my $self  = shift;
	my $sheet = $self->get_sheet( shift );
	return $self->unesc_xml( $sheet->{name} );
}

sub set_sheet_name($,$) {
	my $self  = shift;
	my $sheet = $self->get_sheet( shift );
	my $name  = shift =~ s/[\x00-\x1f]//rg;
	$sheet->{name} = $self->esc_xml( $name );
}

#-------------------------------------------------------------------------------
# set sheetView
#-------------------------------------------------------------------------------
sub set_sheet_view($) {
	my $self  = shift;
	my $sheet = $self->get_sheet( shift );
	my $cell  = shift || 'A1';
	if ($cell !~ /^[A-Z]+\d+$/) {
		return $self->error("Illegal sheet view cell: $cell");
	}
	$sheet->{data} =~ s|(<sheetViews>[^/]*)<selection ([^>]*)/>|
		my $prev = $1;
		my $attr = $2;
		$attr =~ s/sqref="[\w:]+"/sqref="$cell"/;
		$attr =~ s/activeCell="\w+"/activeCell="$cell"/;
		"$prev<selection $attr/>";
	|eg;
	$sheet->{data} =~ s|(<sheetViews>[^/]*)<sheetView ([^>]*)>|
		my $prev = $1;
		my $attr = $2;
		$attr =~ s/topLeftCell="[\w:]+"/topLeftCell="$cell"/;
		"$prev<sheetView $attr>";
	|eg;
	return $sheet;
}

#-------------------------------------------------------------------------------
# copy sheet
#-------------------------------------------------------------------------------
sub clone_sheet($) {
	my $self  = shift;
	my $sheet = $self->get_sheet( shift );

	my $csh = $self->clone_hash( $sheet );
	my $uid = $self->generate_uid();
	$csh->{data} =~ s|xr:uid="[^\"]+"|xr:uid="{$uid}"|;

	return $csh;
}

#-------------------------------------------------------------------------------
# copy sheet, push, unshift 
#-------------------------------------------------------------------------------
sub get_all_sheets() {
	my $self = shift;
	return $self->{sheets};
}
sub push_sheet {
	my $self = shift;
	push(@{$self->{sheets}}, @_);
}
sub unshift_sheet {
	my $self = shift;
	unshift(@{$self->{sheets}}, @_);
}

#-------------------------------------------------------------------------------
# remove sheet
#-------------------------------------------------------------------------------
sub remove_sheet($) {
	my $self   = shift;
	my $num    = shift;
	my $sheets = $self->{sheets};
	if ($num !~ /^\d+$/ || $num<0 || $#$sheets<$num) {
		return;
	}

	my $sheet = splice(@$sheets, $num, 1);
	return $sheet;
}
sub remove_all_sheets() {
	my $self   = shift;
	my $sheets = $self->{sheets};
	$self->{sheets} = [];
	return $sheets;
}

#-------------------------------------------------------------------------------
# Replace
#-------------------------------------------------------------------------------
sub replace_cells($$) {
	my $self   = shift;
	my $sheet  = $self->get_sheet( shift );
	my $h      = shift;

	#-----------------------------------------------------------------------
	# remove "<v>" cache from <f></f><v></v>
	#-----------------------------------------------------------------------
	$sheet->{data} =~ s!(<f[^>]*>[^<]*</f>|<f[^>]*/>)<v>[^<]+</v>!$1!g;

	#-----------------------------------------------------------------------
	# un shared <f>
	#-----------------------------------------------------------------------
	# <c><f ref="AQ53:AQ66" t="shared" si="0">"$QT$"</f><v>$QT$</v></c>
	# <c r="AQ55" s="8" t="str"><f t="shared" si="0"/><v>$QT$</v>
	#
	my %rep;
	$sheet->{data} =~ s!<f ([^>]*)(t="shared") ([^>]*)(ref="(\w+:\w+)")!<f $1$4 $3$2!g;
	$sheet->{data} =~ s!<f ([^>]*)ref="(\w+:\w+)" ([^>]*)t="shared"([^>]*)>([^>]*"\$[^\$]+\$"[^>]*)</f>!
		my $f = "$1$3$4";
		my $r = $2;
		my $v = $5;
		if ($r =~ /^([A-Z]+)(\d+):\1(\d+)$/) {
			my $x = $1;
			my $y = $3;
			for(my $i=$2; $i<=$3; $i++) {
				$rep{"$x$i"} = $v;
			}
		}
		"<f $f>$v</f>";
	!eg;

	$sheet->{data} =~ s!(<c [^>]*r="(\w+)"[^>]*>)(<f ([^>]*)t="shared"([^>]*)/>)!
		if (exists($rep{$2})) {
			"$1<f $4$5>$rep{$2}</f>";
		} else {
			"$1$3";
		}
	!eg;

	#-----------------------------------------------------------------------
	# do replace
	#-----------------------------------------------------------------------
	my $cc = $sheet->{cc};	# calcChain

	my %c;
	my $do_replace = sub {
		my $replace;
		$_[0] =~ s{(\"?)\$(\w+)(?::(\d+)(?::(\d+))?)?(?:([\?\!,])((?:[^\$]|\$\w+\$)+))?\$\1}{
			$replace = 1;
			my $v = $h->{$2};
			if (ref($v)) {
				# line load once
				$v = $c{$2} = exists($c{$2}) ? $c{$2} : shift(@$v);
			}
			if ($3 ne '') {
				$v = $4 ne '' ? substr($v, $3, $4) : substr($v, $3);
			}
			$v =~ s/&/&amp;/g;
			$v =~ s/</&lt;/g;
			$v =~ s/>/&gt;/g;
			$v =~ s/"/&quote;/g;
			$v =~ s/'/&apos;/g;

			my $symbol  = $5;
			my $default = $6;
			$default =~ s!\$(\w+)\$!
				my $x = $h->{$1};
				if (ref($x)) {
					$v = $c{$1} = exists($c{$1}) ? $c{$1} : shift(@$x);
				}
				$x =~ s/&/&amp;/g;
				$x =~ s/</&lt;/g;
				$x =~ s/>/&gt;/g;
				$x =~ s/"/&quote;/g;
				$x =~ s/'/&apos;/g;
				$x;
			!eg;

			# $xxx?yyy$ if (xxx) 'yyy' else ''
			# $xxx!yyy$ if (xxx) ''    else 'yyy'
			# $xxx,yyy$ if (xxx) 'xxx' else 'yyy'
			   if ($symbol eq '?') { $v = $v ne '' ? $default : ''; }
			elsif ($symbol eq '!') { $v = $v eq '' ? $default : ''; }
			elsif ($symbol eq ',') { $v = $v ne '' ? $v       : $default; }

			$v;
		}seg;
		return $replace;
	};

	$sheet->{data} =~ s{(</row>)|<c(| [^>]*[^/])>(.*?)</c>}{
		my $at   = $2;
		my $cell = $3;
		if ($1) {	# detection row end
			%c = ();
			$1;

		} elsif ($at =~ /t="s"/) {
			#-------------------------------------------------------
			# replace String
			# <c r="J15" s="8" t="s"><_s><si><t>$STR1$と$STR2$</t></si></_s></c>
			#-------------------------------------------------------
			&$do_replace($cell);
			"<c$at>$cell</c>";

		} elsif ($cell =~ m|^(.*?)<f([^>]*)>(.*?)</f>(.*)$|) {
			#-------------------------------------------------------
			# replace Function
			# <c r="J16" s="14" t="str"><f>"$UNIT1$"</f><v>$UNIT1$</v></c>
			#-------------------------------------------------------
			my $before = $1;
			my $fat    = $2;
			my $f      = $3;
			my $after  = $4;
			my $replace_only = ($f =~ m|^(?:"\$\w+(?::\d+(?::\d+)?)?(?:[\?\!,][^\$]+)?\$")+$|);

			my $replace = &$do_replace($f);

			if (!$replace) {
				"<c$at>$cell</c>";

			} elsif (!$replace_only) {
				"<c$at>$before<f$fat>$f</f>$after</c>";

			} else {
				# rewrite attribute
				if ($f =~ /^-?\d+(?:\.\d+)?$/) {
					$at =~ s/ t="str"//;
				} else {
					$f  = "\"$f\"";		# string
				}

				if ($f eq '' && $at =~ /r="([A-Z]+\d+)"/) {
					delete $cc->{$1};
					"<c$at/>";
				} else {
					"<c$at>$before<f$fat>$f</f>$after</c>";
				}
			}
		} else {
			"<c$at>$cell</c>";
		}
	}seg;
	#-----------------------------------------------------------------------
	return $sheet;
}

#-------------------------------------------------------------------------------
# get sheet
#-------------------------------------------------------------------------------
sub get_sheet {
	my $self = shift;
	my $num  = shift;
	my $sheets = $self->{sheets};
	if (ref($num) && $num->{__excel_sheet}) {
		return $num;
	}

	my $sheets = $self->{sheets};
	if ($num !~ /^\d+$/ || $num<0 || $#$sheets<$num) {
		die "Illegal sheet number: $num";
	}
	return $sheets->[$num];
}

################################################################################
# subroutine
################################################################################
#-------------------------------------------------------------------------------
# get tmp/working dir
#-------------------------------------------------------------------------------
sub get_working_dir {
	my $self = shift;
	return $self->{wd};
}
sub get_tmp_dir {
	my $self = shift;
	return $self->{tmp};
}

#-------------------------------------------------------------------------------
# rmdir
#-------------------------------------------------------------------------------
sub rmdir {
	my $self = shift;
	my $dir  = shift;
	$dir =~ s/[\x00-\x1f\\"'\$]//g;
	system("rm -rf '$dir'");
}

#-------------------------------------------------------------------------------
# File IO
#-------------------------------------------------------------------------------
sub load_file {
	my $self = shift;
	my $file = shift;
	$file = $self->{wd} . '/' . $file;

	my $fh;
	if ( !sysopen($fh, $file, O_RDONLY) ) { return''; }
	my $data;
	sysread($fh, $data, 0x1000000);		# 1MB
	close($fh);
	return $data;
}

sub write_file {
	my $self = shift;
	my $file = shift;
	my $data = shift;
	$file = $self->{wd} . '/' . $file;

	if ($data eq '') {
		unlink($file);
		return;
	}
	my $fh;
	if ( !sysopen($fh, $file, O_CREAT | O_WRONLY | O_TRUNC) ) {
		return $self->error("File open error: $file");
	}
	my $r = syswrite($fh, $data);
	close($fh);
	return $r;
}

#-------------------------------------------------------------------------------
# extract/pack with unzip/zip command
#-------------------------------------------------------------------------------
sub extract {
	my $self = shift;
	my $file = shift;
	my $dir  = shift;
	$dir =~ s/\.xlsx//g;

	$dir =~ s/[\x00-\x1f\\"'\$]//g;

	$self->rmdir($dir);
	system("unzip '$file' -d '$dir' >>/dev/null");
	return "$dir/";
}

sub pack {
	my $self = shift;
	my $file = shift;
	my $dir  = $self->{wd};

	$file =~ s/[\x00-\x1f\\"'\$]//g;
	$dir  =~ s/[\x00-\x1f\\"'\$]//g;

	unlink($file);
	system("wd=`pwd` && cd '$dir' && zip \"\$wd/$file\" -r ./ >>/dev/null");
	if (! $self->{DEBUG}) {
		$self->rmdir($dir);
	}
	if (!-r $file) {
		return $self->error("ZIP packaging error: $file");
	}
}

#-------------------------------------------------------------------------------
# hash clone
#-------------------------------------------------------------------------------
sub clone_hash {
	my $self = shift;
	my $ref  = shift;

	my %h = %$ref;
	foreach(keys(%h)) {
		if (ref($h{$_}) eq 'ARRAY') {
			$h{$_} = $self->clone_array( $h{$_} );
		}
		if (ref($h{$_}) eq 'HASH') {
			$h{$_} = $self->clone_hash( $h{$_} );
		}
	}
	return \%h;
}
sub clone_array {
	my $self = shift;
	my $ref  = shift;

	my @a = @$ref;
	foreach(@a) {
		if ($_ eq 'ARRAY') {
			$_ = $self->clone_array( $_ );
		}
		if ($_ eq 'HASH') {
			$_ = $self->clone_hash( $_ );
		}
	}
	return \@a;
}

#-------------------------------------------------------------------------------
# generate sheet id
#-------------------------------------------------------------------------------
sub generate_rid {
	my $self = shift;
	my $rel  = shift;
	my $rels = $self->{rels};
	foreach(1..$self->{maxSheets}) {
		my $id = "rId$_";
		if (!exists($rels->{$id})) {
			$rels->{$id} = $rel;
			return $id;
		}
	}
	return $self->error("genereate rId failed!");
}

sub generate_sheetId {
	my $self = shift;
	my $sIds = shift;
	foreach(1..$self->{maxSheets}) {
		if (!exists($sIds->{$_})) {
			$sIds->{$_} = 1;
			return $_;
		}
	}
	return $self->error("genereate sheetId failed!");
}

sub generate_uid {
	my $self = shift;
	return sprintf("%08X-%04X-%04X-%04X-%06X%06X",
		int(rand(0x100000000)),
		int(rand(0x10000)),
		int(rand(0x10000)),
		int(rand(0x10000)),
		int(rand(0x1000000)), int(rand(0x1000000))
	);
}

#-------------------------------------------------------------------------------
# file name to rels file name
#-------------------------------------------------------------------------------
sub file_to_rels {
	my $self = shift;
	my $file = shift;
	$file =~ s|/([^/]+)$|/_rels/$1.rels|;
	return $file;
}

#-------------------------------------------------------------------------------
# escape xml tag
#-------------------------------------------------------------------------------
my %TAGESC = ('<'=>'&lt;', '>'=>'&gt;', '"'=>'&quot;', "'"=>'&apos;', '&'=>'&amp;');
my %UNESC  = reverse(%TAGESC);

sub esc_xml {
	my $self = shift;
	my $text = shift;
	$text =~ s/(&|<|>|"|')/$TAGESC{$1}/g;
	return $text;
}
sub unesc_xml {
	my $self = shift;
	my $text = shift;
	$text =~ s/&(amp|lt|gt|quot|apos);/$UNESC{"&$1;"}/g;
	return $text;
}

#-------------------------------------------------------------------------------
# error
#-------------------------------------------------------------------------------
sub error {
	my $self = shift;
	my $msg  = shift;
	my $ROBJ = $self->{ROBJ};
	$self->{error_msg} = $msg;
	if ($ROBJ) {
		$ROBJ->error('[' . __PACKAGE__  . "] $msg");
	} else {
		print STDERR "$msg\n";	## safe
	}
	return;
}

