use strict;
#-------------------------------------------------------------------------------
# adiary固有記法プラグイン
#                                                   (C)2018-2019 nabe@abk
#-------------------------------------------------------------------------------
package Sakia::TextParser::TagPlugin::Tag_adiary;
################################################################################
# ■基本処理
################################################################################
#-------------------------------------------------------------------------------
# ●コンストラクタ
#-------------------------------------------------------------------------------
sub new {
	my $class = shift;	# 読み捨て
	my $ROBJ  = shift;	# 読み捨て

	my $tags = shift;
	#---begin_plugin_info
	$tags->{"adiary:link"}->{data} = \&adiary_link;
	$tags->{"adiary:this"}->{data} = \&adiary_this;
	$tags->{"adiary:tm"}  ->{data} = \&adiary_tm;
	$tags->{"adiary:key"} ->{data} = \&adiary_key;
	$tags->{"adiary:id"}  ->{data} = \&adiary_key;
	$tags->{"adiary:day"} ->{data} = \&adiary_day;
	$tags->{"adiary:tag"} ->{data} = \&adiary_tag;
	#---end

	$tags->{"adiary:key"} ->{_key}  = 1;
	$tags->{"adiary:id"}  ->{_id}   = 1;

	return ;
}
################################################################################
# ■タグ処理ルーチン
################################################################################
#-------------------------------------------------------------------------------
# ●adiary link 記法
#-------------------------------------------------------------------------------
sub adiary_link {
	my ($pobj, $tag, $cmd, $ary) = @_;
	my $aobj    = $pobj->{aobj};
	my $replace = $pobj->{vars};

	my $link_key = shift(@$ary);
	my $ekey = $link_key;
	$aobj->link_key_encode($ekey);
	my $url  = $replace->{myself2} . $ekey;

	my $name = $link_key;
	#---------------------------
	# 記事タイトルの自動抽出
	#---------------------------
	my $title;
	{
		my $blogid=$aobj->{blogid};
		my $DB = $aobj->{DB};
		my $h = $DB->select_match_limit1("${blogid}_art", 'link_key', $link_key, '*cols', ['title']);
		if ($h) {
			$title = $h->{title};
		}
	}
	return &adiary_link_base($pobj, $tag, $url, $name, $ary, $title);
}
#-------------------------------------------------------------------------------
# ●adiary this 記法
#-------------------------------------------------------------------------------
sub adiary_this {
	my ($pobj, $tag, $cmd, $ary) = @_;

	my $url  = $pobj->{thisurl};
	return &adiary_link_base($pobj, $tag, $url, '', $ary);
}

#-------------------------------------------------------------------------------
# ●adiary key/id 記法
#-------------------------------------------------------------------------------
sub adiary_key {
	my ($pobj, $tag, $cmd, $ary) = @_;
	my $aobj    = $pobj->{aobj};
	my $replace = $pobj->{vars};

	# tm記法?
	my $tm = $ary->[0];
	if ($tag->{_key} && $tm =~ /^\d+$/ && 100000000<=$tm) { 
		return &adiary_tm($pobj, $tag, $cmd, $ary);
	}

	# ID記法
	my $url;
	my $name;
	my $blogid = $aobj->{blogid};
	if ($tag->{_id}) {
		$blogid = shift(@$ary);
		$url    = $aobj->get_blog_path($blogid);
		$name   = $blogid;
	} elsif ($tag->{_this}) {
		$url = $pobj->{thisurl};
	} else {
		$url = $replace->{myself2};
	}

	my $title;
	if ($tag->{_key} || $tag->{_id}) {
		# 記事 pkey/link_key 指定
		my $link_key = shift(@$ary);
		if ($link_key ne '') {
			$name .= (($name ne '')?':':'') . $link_key;
			if ($link_key =~ /^[\d]+$/) {
				$link_key = '0' . int($link_key);
				$url .= $link_key;
			} else {
				my $ekey = $link_key;
				$aobj->link_key_encode($ekey);
				$url .= $ekey;
			}
			#-------------------------
			# 記事タイトルの自動抽出
			#-------------------------
			# セキュリティの関係で同一ブログ内のみ参照可
			if ($blogid eq $aobj->{blogid}) {
				my $DB = $aobj->{DB};
				my $h = $DB->select_match_limit1("${blogid}_art", 'link_key', $link_key, '*cols', ['title']);
				if ($h) {
					$title = $h->{title};
				}
			}
		}
	}
	return &adiary_link_base($pobj, $tag, $url, $name, $ary, $title);
}

#-------------------------------------------------------------------------------
# ●adiary tm 記法
#-------------------------------------------------------------------------------
sub adiary_tm {
	my ($pobj, $tag, $cmd, $ary) = @_;
	my $aobj    = $pobj->{aobj};
	my $replace = $pobj->{vars};

	# 記事 tm 指定
	my $tm   = int(shift(@$ary));
	my $url  = $replace->{myself} . "?tm=$tm";
	my $name = $tm;

	#---------------------------
	# 記事タイトルの自動抽出
	#---------------------------
	my $title;
	{
		my $blogid = $aobj->{blogid};
		my $DB = $aobj->{DB};
		my $h = $DB->select_match_limit1("${blogid}_art", 'tm', $tm, '*cols', ['title']);
		if ($h) {
			$title = $h->{title};
		}
	}
	return &adiary_link_base($pobj, $tag, $url, $name, $ary, $title);
}

#-------------------------------------------------------------------------------
# ●adiary day 記法
#-------------------------------------------------------------------------------
sub adiary_day {
	my ($pobj, $tag, $cmd, $ary) = @_;
	my $ROBJ = $pobj->{ROBJ};
	my $aobj = $pobj->{aobj};
	my $replace = $pobj->{vars};

	# 記事の日付指定
	my $url = $replace->{myself} . '?d=';
	my $opt = shift(@$ary);
	my $name;
	if ($opt =~ m|^(\d\d\d\d)(\d\d)(\d\d?)$|
	 || $opt =~ m|^(\d\d\d\d)[-/](\d\d?)[-/](\d\d?)$|) {	# YYYYMM YYYYMMDD
		$name = $opt;
		$url .= sprintf("$1%02d%02d", $2, $3);
	} elsif ($opt =~ m|^(\d\d\d\d)[-/]?(\d\d)$|) {
		$name = $opt;
		$url .= sprintf("$1%02d", $2);
	} elsif ($opt =~ m|^(\d\d\d\d)$|) {
		$name = $opt;
		$url .= $opt;
	} else {
		return '[date:(format error)]';
	}

	return &adiary_link_base($pobj, $tag, $url, $name, $ary);
}

#-------------------------------------------------------------------------------
# ●adiary tag 記法
#-------------------------------------------------------------------------------
# [tag:import,tag::tag2,tag\:tag:リンク名]
sub adiary_tag {
	my ($pobj, $tag, $cmd, $ary) = @_;
	my $ROBJ = $pobj->{ROBJ};
	my $aobj = $pobj->{aobj};
	my $replace = $pobj->{vars};

	my $x = shift(@$ary);
	while(@$ary) {
		if (!($ary->[0] eq '' && $ary->[1] ne '')) {
			last;
		}
		shift(@$ary);
		$x .= '::' . shift(@$ary);
	}
	# $x = "import,tag::tag2,tag:tag"
	my @tags = split(',', $x);
	my $url = $replace->{myself} . '?&';
	foreach(@tags) {
		$ROBJ->encode_uricom_dest($_);
		$url .= "t=$_&";
	}
	chop($url);

	# 属性
	my $attr = $pobj->make_attr($ary, $tag);
	my $name = $pobj->make_name($ary, $x);

	return "<a href=\"$url\"$attr>$name</a>";
}

#-------------------------------------------------------------------------------
# ○adiary  記法のベース
#-------------------------------------------------------------------------------
sub adiary_link_base {
	my ($pobj, $tag, $url, $name, $ary, $title) = @_;

	# アンカー指定
	if ($ary->[0] =~ /^\#[\w\.\-]*$/) {
		$name .= $ary->[0];
		$url  .= shift(@$ary);
	}
	# title
	if ($title ne '') {
		$name = $title;
		unshift(@$ary, "title=$title");
	}
	# 属性
	my $attr = $pobj->make_attr($ary, $tag);
	# リンク名
	if ($ary->[0] ne '') { $name=join(':', @$ary); }
	return "<a href=\"$url\"$attr>$name</a>";
}

1;
