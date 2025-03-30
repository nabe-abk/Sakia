use strict;
#-------------------------------------------------------------------------------
# Text database
#						(C)2005-2025 nabe@abk
#-------------------------------------------------------------------------------
# Note) Avoid destroying the internal hash array $db when returning values.
#
# Note:JP) 値を返すとき、内部ハッシュ配列 $db を破壊されないようにすること。
#
package Sakia::DB::text;
use Sakia::AutoLoader;
use Sakia::DB::share;
#-------------------------------------------------------------------------------
our $VERSION = '1.80';
our %IndexCache;
our $ErrNotFoundCol = 'In "%s" table, not found "%s" column.';
our $ErrInvalidVal  = 'In "%s" table, invalid value of "%s" column. "%s" is not %s.';
################################################################################
# type define
################################################################################
my @MDAYS = (0,31,0,31,30,31,30,31,31,30,31,30,31);
sub check_timestmap {
	my $fmt = shift;
	if (shift !~ /^(\d+)\-(\d\d?)\-(\d\d?)(?: (\d\d?):(\d\d?):(\d\d?))?$/) { return; }
	if ($1<0  || $2<1  || 12<$2) { return; }
	if (23<$4 || 59<$5 || 59<$6) { return; }
	my ($y,$m,$d)=($1,$2,$3);
	my $days = $2 != 2 ? $MDAYS[$2] : ((($1 % 4) || (!($1 % 100) && ($1 % 400))) ? 28 : 29);
	return 0<$3 && $3<=$days ? sprintf($fmt,$1,$2,$3,$4,$5,$6) : undef;
}

our %TypeInfo = (
	int  => { type=>'int',   check=>sub{ my $v=shift; $v eq int($v) } },
	float=> { type=>'float', check=>sub{ my $v=shift; $v eq ($v+0)  } },
	flag => { type=>'flag',  check=>sub{ my $v=shift; $v eq '0' || $v eq '1'} },
	text => { type=>'text', is_str=>1, check=> sub { 1; } },
	date => { type=>'date', is_str=>1, check=> sub {
		$_[0] = &check_timestmap('%04d-%02d-%02d', $_[0])
	}},
	timestamp=>{ type=>'timestamp',	is_str=>1, check=> sub {
		$_[0] = &check_timestmap('%04d-%02d-%02d %02d:%02d:%02d', $_[0])
	}}
);

################################################################################
# constructor
################################################################################
sub new {
	my $class = shift;
	my ($ROBJ, $dir, $opt) = @_;

	my $ext  = $opt->{ext} || '.dat';
	my $self = bless({
		ext		=> $ext,
		dir		=> $dir,
		index_file	=> "#index$ext",
		index_backup	=> "#index.backup$ext",
		filename_format	=> '%05d',

		%{ $opt || {}},		# options
		ROBJ	=> $ROBJ,
		DBMS	=> 'TextDB',
		ID	=> "text.$dir",
		is_TDB	=> 1
	}, $class);

	if (!-e $dir && !mkdir($dir)) {
		die "Unable to create TextDB directory: $dir";
	}

	return $self;
}

################################################################################
# find table
################################################################################
sub find_table {
	my $self = shift;
	my $table = shift;
	if ($table =~ /\W/) { return 0; }	# Not Found(error)

	my $dir   = $self->{dir} . $table . '/';
	my $index = $dir . $self->{index_file};
	if (-e $index || -e "$dir$self->{index_backup}") { return 1; }	# Found
	return 0;	# Not found
}

################################################################################
# select
################################################################################
sub select {
	my $self = shift;
	my $_tbl = shift;
	my $arg  = shift;
	my $ROBJ = $self->{ROBJ};

	my @tables;	# table names
	my %names;	# table name  to real name

	#-----------------------------------------------------------------------
	# load tables infomation
	#-----------------------------------------------------------------------
	my ($table, $tname) = $self->parse_table_name($_tbl);
	$names{$tname} = $table;
	push(@tables, $tname);

	my $db = $self->load_index($table);
	if ($#$db < 0) { return []; }
	my $db_orig = $db;

	my $ljoins = [];
	if ($arg->{ljoin}) {
		$ljoins = ref($arg->{ljoin}) eq 'ARRAY' ? $arg->{ljoin} : [ $arg->{ljoin} ];
	}
	foreach(@$ljoins) {
		my $jtable   = $_->{table};
		my ($jt,$jn) = $self->parse_table_name($jtable);
		if ($jt eq '' || $jn eq '' || !$self->find_table($jt)) {
			$self->error('Table not found: %s', $jtable);
			return [];
		}
		if (exists($names{$jn})) {
			$self->error('Table name is duplicate: %s', $jn);
			return [];
		}
		# pre load
		$self->load_index($jt);
		# save table names
		$names{$jn}=$jt;
		push(@tables, $jn);
	}

	#-----------------------------------------------------------------------
	# check columns
	#-----------------------------------------------------------------------
	my %selany;
	my %colinfo;
	foreach my $tn (@tables) {
		my $t    = $names{$tn};
		my $cols = $self->{"$t.cols"};
		foreach(keys(%$cols)) {
			my $h = $colinfo{"$tn.$_"} = {
				%{$cols->{$_}},		# copy from original colinfo
				table	=> $t,
				tname	=> $tn,
				cname	=> $_,
				fullname=> "$tn.$_"
			};
			$selany{$_} = $colinfo{$_} = $colinfo{$_} ? { %$h, dup=>1 } : $h;
		}
	}

	my $g_col = $arg->{group_by};
	if ($g_col ne '') {
		my $ci = $self->load_colinfo(\%colinfo, $g_col);
		if (!$ci) { return; }

		$g_col = $ci->{fullname};
	}

	my %selinfo;	# select infomation by keys of the returned hash
	my @selcols;	# select column full names
	#
	# Ex) SELECt x y, sum(x) z FROM tbl t
	#	$selinfo{y} = { col=>'t.x' };
	#	$selinfo{z} = { col=>'t.x', func=>'sum' };
	#	@selcols    = ('t.x');
	#
	my $arg_cols = $arg->{cols} // ($g_col ? $g_col : '*');
	if ($arg_cols) {
		my $exists_func;
		my %sel;
		my $ary = ref($arg_cols) ? $arg_cols : [ $arg_cols ];
		foreach(@$ary) {
			if ($g_col && $_ =~ /\*$/) {
				$self->error('SELECT colmun error, not allow with "group by": %s', $_);
				return [];
			}
			if ($_ eq '*') {
				foreach(keys(%selany)) {
					my $fn = $colinfo{$_}->{fullname};
					$sel{$fn}    = 1;
					$selinfo{$_} = { col=>$fn };
				}
				next;
			}
			my $c = $_ =~ tr/A-Z/a-z/r;
			my $n;
			if ($c =~ /^(.*) +(\w+)$/) {		# col name
				$c = $1;
				$n = $2;
				if ($n !~ /^[a-z_]/) {
					$self->error('SELECT colmun error, illegal colmun name: %s', $_);
					return [];
				}
			}
			$c =~ s/\s//g;

			my $func;
			if ($c =~ /^(\w+)\(([^\)]*)\)$/) {	# func(col)
				$func = $1;
				$c    = $2;
				if ($func !~ /^(?:count|min|max|sum)$/) {
					$self->error('SELECT colmun error, "%s()" not support: %s', $func, $_);
					return [];
				}
				$exists_func=1;
			}
			if ($c !~ /^(?:(\w+)\.)?(\w+|\*)$/) {
				$self->error('SELECT colmun error: %s', $_);
				return [];
			}
			$n ||= $func ? "${func}_$2" : $2;

			if ($1 eq '') {
				my $ci = $self->load_colinfo(\%colinfo, $2);
				if (!$ci) { return; }

				$c = $ci->{fullname};

			} else {
				my $t = $names{$1};
				if (!$t) {
					$self->error('SELECT colmun error, table name not found: %s', $_);
					return [];
				}
				if ($2 eq '*') {
					my @ary = keys(%{$self->{"$t.cols"}});
					foreach(@ary) {
						my $fn = "$1.$_";
						$sel{$fn}    = 1;
						$selinfo{$_} = { col=>$fn };
					}
					next;
				}
				if (!$colinfo{$c}) {
					$self->error('SELECT colmun not found: %s', $_);
					return [];
				}
			}

			if ($g_col && !$func && $c ne $g_col) {
				$self->error('SELECT colmun error, not allow with "group by": %s', $_);
				return [];
			}

			$sel{$c}     = 1;
			$selinfo{$n} = { col=>$c, func=>$func };
		}
		@selcols = keys(%sel);

		if ($exists_func && !$g_col) {
			foreach(@$ary) {
				if ($_ =~ /^\w+\s*\(/) { next; }
				$self->error('SELECT colmun error, can not be specified along with aggregate functions: %s', $_);
				return [];
			}
			$g_col='*';
		}
	}

	#-----------------------------------------------------------------------
	# parse left join
	#-----------------------------------------------------------------------
	my %join_map;		# main table pkey to join table's line hash data
	my @maps_arg;		# map table list
	my $maps_arg_code='';	# map table access variables
	if (@$ljoins) {
		my $jary    = ref($arg->{ljoin}) eq 'ARRAY' ? $arg->{ljoin} : [ $arg->{ljoin} ];
		my @lr_cols = map { $_->{left}, $_->{right} } @$jary;

		foreach(@$ljoins) {
			my ($jtable,$jn) = $self->parse_table_name($_->{table});
			my $idx = $self->{"$jtable.index"};
			my $all = $self->{"$jtable.cols"};

			#---------------------------------------------
			# check join condition
			#---------------------------------------------
			my $left  = $_->{left}  =~ tr/A-Z/a-z/r;
			my $right = $_->{right} =~ tr/A-Z/a-z/r;
			if ($right =~ /^(\w+)/ && $1 ne $jn) {	# swap L/R if right is base table
				my $x = $left;
				$left = $right;
				$right= $x;
			}
			my ($ln, $lc) = $left  =~ /^(\w+)\.(\w+)$/ ? ($1,$2) : undef;
			my ($rn, $rc) = $right =~ /^(\w+)\.(\w+)$/ ? ($1,$2) : undef;

			if ($ln eq '' || $rn eq '' || $ln eq $jn || $rn ne $jn) {
				$self->error('Illegal join rule on "%s": left=%s, right=%s', $_->{table}, $left, $right);
				return [];
			}
			my $ltable = $names{$ln};
			if (!$ltable || !$self->{"$ltable.cols"}->{$lc}) {
				$self->error('"%s" column is not exists on join target "%s" table', $left, $ltable);
				return [];
			}
			if (!$self->{"$jtable.cols"}->{$rc}) {
				$self->error('"%s" column is not exists on join target "%s" table', $right, $jtable);
				return [];
			}
			# $rn=$tn

			#---------------------------------------------
			# join
			#---------------------------------------------
			my %h;
			my $jdb = $self->load_tbl_by_cols($jtable, $rc);
			foreach(@$jdb) {
				$h{$_->{$rc}} = $_;
			}
			delete $h{''};		# delete null

			my $map = {};
			if ($ln eq $tname) {	# left is main table
				foreach(@$db) {
					my $z = $h{$_->{$lc}};
					$map->{$_->{pkey}} = $z;
				}
			} else {
				$self->load_tbl_by_cols($ltable, $lc);
				my $lmap = $join_map{$ln};
				foreach(@$db) {
					my $l = $lmap->{$_->{pkey}};
					my $z = $h{$l->{$lc}};
					$map->{$_->{pkey}} = $z;
				}
			}
			$join_map{$jn} = $map;		# save mapping
			push(@maps_arg, $map);
			$maps_arg_code .= ',$map' . $jn;
		}
	}

	#-----------------------------------------------------------------------
	# limit
	#-----------------------------------------------------------------------
	my $limit  = int($arg->{limit});
	my $offset = int($arg->{offset});
	if ($arg->{limit} ne '' && !$limit) { return []; }	# limit is 0
	if ($offset<0) {
		$self->error('Offset must not be negative: %s', $arg->{offset});
		return [];
	}

	my $limit_check_code='';
	if (!wantarray && $limit && $limit < $#$db+1) {		# wantarray is require hits
		my $x = $offset + $limit-1;
		$limit_check_code = "if (\$#ary >= $x) { last; }";
	}

	#-----------------------------------------------------------------------
	# check column
	#-----------------------------------------------------------------------
	my $check_col = sub {
		my $ci = $self->load_colinfo(\%colinfo, shift);
		if (!$ci) { return; }

		my $t  = $ci->{table};
		my $tn = $ci->{tname};
		my $c  = $ci->{cname};

		# main table
		if ($tn eq $tname) {
			if (!$self->{"$t.index"}->{$c}) {
				foreach(@$db) {
					$self->read_rowfile_override($table, $_);
				}
			}
			return ($ci, "\$_->{$c}", "\$*->{$c}");
		}

		# join table
		if (!$self->{"$t.index"}->{$c}) {
			my $map = $join_map{$tn};
			foreach(@$db) {
				my $h = $map->{$_->{pkey}};
				if (!$h) { next; }
				$self->read_rowfile_override($t, $h);
			}
		}
		return ($ci, "\$map$tn\->{\$pkey}->{$c}", "(\$map$tn\->{\$*->{pkey}} || {})->{$c}");
	};

	#-----------------------------------------------------------------------
	# sort
	#-----------------------------------------------------------------------
	my $arg_sort  = $arg->{sort} && (ref($arg->{sort}) ? $arg->{sort} : [ $arg->{sort} ]);
	my $sort_func = !$g_col && $arg_sort && sub {
		my $list = shift;

		my @cond;
		foreach(@$arg_sort) {
			my $c = $_;
			my $rev = ord($c) == 0x2d;		# '-colname'
			if ($rev) { $c = substr($c, 1); }

			my ($ci, $_code, $scolcode) = &$check_col($c);
			if (!$ci) { return; }			# error exit

			my $left  = $scolcode =~ tr/*/a/r;
			my $right = $scolcode =~ tr/*/b/r;
			my $op    = $ci->{is_str} ? 'cmp' : '<=>';
			push(@cond, $rev ? "$right$op$left" : "$left$op$right");
		}

		my $cond = join(' || ', @cond);
		my $func = "sub { my (\$db$maps_arg_code)=\@_; "
			 . "return [ sort { $cond } \@\$db ] }";
		$func = $self->eval_and_cache($func);

		return &$func($list, @maps_arg);
	};

	if ($sort_func && $limit_check_code) {
		$db = &$sort_func($db);
		if (!$db) { return []; }	# error
		$sort_func = undef;		# sorted
	}

	#-----------------------------------------------------------------------
	# where: non text search
	#-----------------------------------------------------------------------
	my @condlist = (
		{
			key 	=> 'match',
			array	=> 'm',
			num	=> '==',
			str	=> 'eq'
		},{
			key 	=> 'not_match',
			array	=> 'n',
			not	=> '!',
			num	=> '!=',
			str	=> 'ne'
		},
		{ key => 'min', num => '>=', str => 'ge' },
		{ key => 'max', num => '<=', str => 'le' },
		{ key => 'gt',  num => '>',  str => 'gt' },
		{ key => 'lt',  num => '<',  str => 'lt' },
		{ key => 'flag',    num => '==', flag=>1 },
		{ key => 'boolean', num => '==', flag=>1 },
		{ key => 'is_null',   is => "eq''" },
		{ key => 'not_null',  is => "ne''" }
	);
	my @cond;
	my %in;
	my $err;
	foreach my $cn (@condlist) {
		my $key = $cn->{key};
		my $h   = $arg->{$key};
		if (!$h) { next; }

		my $is  = $cn->{is};
		my $ary = $is ? $h : [ sort(keys(%$h)) ];	# sort() is required for "eval_and_cache".
		foreach(@$ary) {
			my ($ci, $colcode) = &$check_col($_);
			if (!$ci) { $err=1; next; }

			if ($is) {				# is null / is not null
				push(@cond, $colcode . $is);
				next;
			}

			if ($cn->{flag}) {
				if ($ci->{type} ne 'flag') {
					$self->error('The "%s" column is not boolean: %s', $_, $ci->{type});
					$err=1;
					next;
				}
			}
			#
			# compare with value
			#
			my $v  = $h->{$_};
			my $ar = $cn->{array};
			if ($ar) {
				$v = $self->check_value_for_match($ci->{table}, $_, $v, $ci);
				if (!defined $v) { $err=1; next; }

				if (ref($v) eq 'ARRAY') {
					my $inkey = $ar . $ci->{cname};
					$in{$inkey} = { map {$_=>1} @$v };
					push(@cond, "$cn->{not}exists\$in{$inkey}->{$colcode}");
					next;
				}
			} elsif (! &{$ci->{check}}($v)) {
				$self->error($ErrInvalidVal, $table, $_, $h->{$_}, $ci->{type});
				$err=1;
				next;
			}
			#
			# save condition
			#
			push(@cond, $colcode . ($ci->{is_str} || $v eq '' ? "$cn->{str}'$v'" : "$cn->{num}$v"));
		}
	}
	if ($err) { return []; }

	#
	# Execute non text search
	#
	my $load_pkey_code = %join_map ? 'my $pkey=$_->{pkey};' : '';
	if (@cond) {
		my $cond = join(' && ', @cond);
		my $func = <<FUNCTION;
sub {
	my (\$db,\$in$maps_arg_code) = \@_;
	my \@ary;
	foreach(\@\$db) {
		$load_pkey_code
		if (!($cond)) { next; }
		push(\@ary, \$_);
		$limit_check_code
	}
	return \\\@ary;
}
FUNCTION
		if ($self->{TRACE}) { $func =~ s/\t+\n//g; }
		$func = $self->eval_and_cache($func);
		$db = &$func($db, \%in, @maps_arg);
	}

	#-----------------------------------------------------------------------
	# where: text search
	#-----------------------------------------------------------------------
	undef @cond;
	my $s_words = $arg->{search_words} || [];
	my $s_not   = $arg->{search_not}   || [];
	if (@$s_words || @$s_not) {
		my $cols  = $arg->{search_cols}  || [];
		my $match = $arg->{search_match} || [];
		my $equal = $arg->{search_equal} || [];

		foreach(@$s_words) {
			if ($_ eq '') { next; }
			my $x = $_ =~ s/([\\\"])/\\$1/rg;
			my $r = $_ =~ s/([^0-9A-Za-z\x80-\xff])/"\\x" . unpack('H2',$1)/reg;

			my @ary;
			foreach (@$equal) {
				push(@ary, "\$_->{$_} eq \"$x\"");
			}
			foreach (@$cols) {
				push(@ary, "\$_->{$_} =~ /$r/i");
			}
			foreach (@$match) {
				push(@ary, "\$_->{$_} =~ /^$r\$/i");
			}
			push(@cond, '(' . join(' || ', @ary) . ')');
		}

		my @not_words_reg;
		foreach(@$s_not) {
			if ($_ eq '') { next; }
			my $x = $_ =~ s/([\\\"])/\\$1/rg;
			my $r = $_ =~ s/([^0-9A-Za-z\x80-\xff])/"\\x" . unpack('H2',$1)/reg;

			my @ary;
			foreach (@$equal) {
				push(@ary, "\$_->{$_} ne \"$x\"");
			}
			foreach (@$cols) {
				push(@ary, "\$_->{$_} !~ /$r/i");
			}
			foreach (@$match) {
				push(@ary, "\$_->{$_} !~ /^$r\$/i");
			}
			push(@cond, join(' && ', @ary));
		}
	}
	#
	# Execute text search
	#
	if (@cond) {
		my $cond = join(' && ', @cond);
		my $func = <<FUNCTION;
sub {
	my (\$db$maps_arg_code) = \@_;
	my \@ary;
	foreach(\@\$db) {
		$load_pkey_code
		if (!($cond)) { next; }
		push(\@ary, \$_);
		$limit_check_code
	}
	return \\\@ary;
}
FUNCTION
		if ($self->{TRACE}) { $func =~ s/\t+\n//g; }
		$func = $self->eval_and_cache($func);
		$db = &$func($db, @maps_arg);
	}

	#-----------------------------------------------------------------------
	# group by
	#-----------------------------------------------------------------------
	if ($g_col) {
		my %funcs = (
			min => sub {
				my $x = shift;
				my $y = shift;
				if ($x eq '') { return $y; }
				if ($y eq '') { return $x; }
				return $x<$y ? $x : $y;
			},
			max => sub {
				my $x = shift;
				my $y = shift;
				if ($x eq '') { return $y; }
				if ($y eq '') { return $x; }
				return $x>$y ? $x : $y;
			},
			sum => sub {
				my $x = shift;
				my $y = shift;
				if ($x eq '') { return $y; }
				if ($y eq '') { return $x; }
				return $x+$y;
			},
			count => sub {
				my $x = shift || 0;
				my $y = shift;
				if ($y eq '') { return $x; }
				return $x+1;
			}
		);

		my ($gci, $gcolcode) = $g_col eq '*' ? ({}, "''") : &$check_col($g_col);
		my $save_gcol_code = '';
		my @mapcode;
		foreach my $n (keys(%selinfo)) {
			my $si = $selinfo{$n};
			my ($ci, $colcode) = &$check_col($si->{col});
			if ($si->{func}) {
				push(@mapcode, "\$h->{$n}=&{\$f->{$si->{func}}}(\$h->{$n}, $colcode);");
				next;
			}
			$save_gcol_code .= "\$h->{$n}=$colcode;";
		}

		my $mapcode = join("\n\t\t", @mapcode);
		my $func = <<FUNCTION;
sub {
	my (\$db,\$f$maps_arg_code) = \@_;
	my \@ary;
	my \%gh;
	foreach(\@\$db) {
		my \$gv = $gcolcode;
		my \$h  = \$gh{\$gv};
		if (!\$h) {
			push(\@ary, \$h = \$gh{\$gv} = {});
			$save_gcol_code
		}
		$mapcode
	}
	return \\\@ary;
}
FUNCTION
		$func = $self->eval_and_cache($func);
		$db = &$func($db, \%funcs, @maps_arg);
	}

	#-----------------------------------------------------------------------
	# sort
	#-----------------------------------------------------------------------
	if ($g_col && $arg_sort) {
		my @cond;
		foreach(@$arg_sort) {
			my $c = $_;
			my $rev = ord($c) == 0x2d;		# '-colname'
			if ($rev) { $c = substr($c, 1); }

			my $si=$selinfo{$c};
			if (!$si) {
				$self->error("Not found select colmun name with aggregate: %s", $c);
				return [];
			}
			my $is_str = $si->{func} ? 0 : $colinfo{$si->{col}}->{is_str};
			my $op     = $is_str ? 'cmp' : '<=>';
			push(@cond, $rev ? "\$b->{$c}$op\$a->{$c}" : "\$a->{$c}$op\$b->{$c}");
		}

		my $cond = join(' || ', @cond);
		my $func = "sub { return [ sort { $cond } \@{(shift)} ] }";
		$func = $self->eval_and_cache($func);
		$db = &$func($db);

	} elsif ($sort_func) {
		$db = &$sort_func($db);
		if (!$db) { return []; }	# error
		$sort_func = undef;		# sorted
	}

	#-----------------------------------------------------------------------
	# save hits
	#-----------------------------------------------------------------------
	my $hits = $#$db +1;

	#-----------------------------------------------------------------------
	# limit and offset
	#-----------------------------------------------------------------------
	if (0 < $offset) {
		splice(@$db, 0, $offset);
	}
	if ($limit) {
		splice(@$db, $limit);
	}

	#-----------------------------------------------------------------------
	# make return data
	#-----------------------------------------------------------------------
	if ($g_col) {
		# maked

	} elsif (!%join_map && (!ref($arg_cols) && $arg_cols eq '*' || ref($arg_cols) && $#$arg_cols==0 && $arg_cols->[0] eq '*')) {
		#
		# single table and load all colmun data
		# copy all row data
		#
		foreach(@selcols) {
			&$check_col($_);	# load row data if need
		}
		$db = [ map { my %x=%$_; delete $x{'*'}; \%x } @$db ];

	} else {
		# join or "as name"
		#	$selinfo{name} = { col => 'col' }
		#	-->> select col as name
		#
		my @mapcode;
		foreach my $n (keys(%selinfo)) {
			my $si = $selinfo{$n};
			my ($ci, $colcode) = &$check_col($si->{col});
			if ($si->{func} eq 'count') {
				push(@mapcode, "$n=>($colcode eq '' ? '' : 1)");
				next;
			}
			push(@mapcode, "$n=>$colcode");
		}

		my $func= "sub { my (\$db$maps_arg_code)=\@_; "
			. "return [ map { $load_pkey_code\{" . join(',', @mapcode) . "} } \@\$db ]; }";
		$func = $self->eval_and_cache($func);
		$db = &$func($db, @maps_arg);
	}

	return wantarray ? ($db,$hits) : $db;
}

################################################################################
# subrotine for select
################################################################################
#-------------------------------------------------------------------------------
# check select table name
#-------------------------------------------------------------------------------
sub parse_table_name {
	my $self = shift;
	my $tbl  = shift =~ tr/A-Z/a-z/r;
	my $names= shift;
	if ($tbl =~ /^(\w+) +(\w+)$/) {
		return ($1, $2);
	}
	$tbl =~ s/\W//g;
	return ($tbl, $tbl);
}

#-------------------------------------------------------------------------------
# load colinfo
#-------------------------------------------------------------------------------
sub load_colinfo {
	my $self = shift;
	my $h    = shift;
	my $col  = shift;

	my $ci = $h->{$col};
	if (!$ci) {
		$self->error('Not found column: %s', $col);
		return;
	}
	if ($ci->{dup}) {
		$self->error('There are multiple corresponding columns: %s', $col);
		return;
	}
	return $ci;
}

#-------------------------------------------------------------------------------
# check value for matching
#-------------------------------------------------------------------------------
sub check_value_for_match {
	my $self = shift;
	my $table= shift;
	my $col  = shift;
	my $v    = shift;
	my $info = shift;
	my $check= $info->{check};

	if ($v eq '') { return ''; }	# is null

	if (ref($v) eq 'ARRAY') {
		my @ary = @$v;
		foreach(@ary) {
			my $org = $_;
			if (!&$check($_)) {
				$self->error($ErrInvalidVal, $table, $col, $org, $info->{type});
				return;
			}
		}
		return \@ary;
	}

	my $org = $v;
	if (!&$check($v)) {
		$self->error($ErrInvalidVal, $table, $col, $org, $info->{type});
		return;
	}
	return $v;
}

#-------------------------------------------------------------------------------
# load target table row data by require columns
#-------------------------------------------------------------------------------
sub load_tbl_by_cols {
	my $self = shift;
	my $table= shift;
	if ($self->{"$table.load_all"}) {
		return $self->{"$table.tbl"};
	}
	my $idx = $self->{"$table.index"};
	foreach(@_) {
		if ($idx->{$_}) { next; }
		return $self->load_allrow($table, 'read_rowfile_override');
	}
	return $self->{"$table.tbl"};
}

################################################################################
# load table data functions
################################################################################
#-------------------------------------------------------------------------------
# load table index with table infomation
#-------------------------------------------------------------------------------
sub load_index_for_edit {
	my ($self, $table) = @_;
	return $self->load_index($table, 1);
}
sub load_index {
	my ($self, $table, $edit) = @_;
	my $ROBJ = $self->{ROBJ};

	if (! $edit && defined $self->{"$table.tbl"}) {
		return $self->{"$table.tbl"};
	}
	$self->trace("load index on '$table' table" . ($edit ? ' (for edit)' : ''));

	# prepare
	my $dir   = $self->{dir} . $table . '/';
	my $index = $dir . $self->{index_file};
	if (!-e $index) {
		if (-e $dir) { $self->rebuild_index( $table ); }
		else {
			$self->error("Table '$table' not found!");
			return;
		}
	}

	# load file
	my ($fh, $lines);
	if ($edit) {
		my $opt={};
		if ($self->{begin}) {
			# A transaction has already started on this table
			if ($self->{transaction}->{$table}) {
				return $self->{"$table.tbl"};
			}
			# Start transaction. Lock "#index.backup.dat"
			my $fh = $ROBJ->file_lock($dir . $self->{index_backup}, 'write_lock_nb' );
			if (!$fh) {
				# If another transaction already has the lock,
				# this transaction will result in an error.
				# DO NOT WAIT FOR LOCKS to prevent deadlocks.
				return undef;
			}
			$self->{"$table.lock-tr"} = $fh;
			$self->{transaction}->{$table}=1;

			# Lock the index file to prevent it from being edited.
			$opt->{read_lock}=1;
		}
		($fh, $lines) = $ROBJ->fedit_readlines($index, $opt);
		if ($#$lines < 0) {
			$ROBJ->fedit_exit($fh);
			delete $self->{transaction}->{$table};
			return undef;
		}
		$self->{"$table.lock"} = $fh;
	} else {
		$lines = $ROBJ->fread_lines_cached($index, {no_error => $self->{no_error}});
		if ($#$lines < 0) { return undef; }
	}

	# delete "\n"
	map { chop($_) } @$lines;

	#-------------------------------------------------------------
	# parse index file
	#-------------------------------------------------------------
	# LINE 01: DB index file version
	my $ver = $self->{"$table.version"} = int(shift(@$lines));	# Version
	my $random;
	if ($ver > 6) {
		die "TextDB Ver.$VERSION is DB file version $ver not support."
	} elsif ($ver < 6) {
		# Index parser for version 3 to 5.
		$random = $self->parse_old_index($table, $index, $ver, $lines);
	} else {
		$self->{"$table.rand"} = $random = shift(@$lines);	# LINE 02: Random string
		$self->{"$table.serial"} = int(shift(@$lines));		# LINE 03: Serial number for pkey (current max)

		my @allcols = split(/\t/, shift(@$lines));		# LINE 04: all colmuns
		my @types   = split(/\t/, shift(@$lines));		# LINE 05: colmuns type
		my %cols = map { $_ => $TypeInfo{shift(@types)} } @allcols;
		$self->{"$table.cols"} = \%cols;

		$self->{"$table.unique"}  = { map { $_ => 1} split(/\t/, shift(@$lines)) };	# LINE 06: UNQIUE columns
		$self->{"$table.notnull"} = { map { $_ => 1} split(/\t/, shift(@$lines)) };	# LINE 07: NOT NULL columns

		# LINE 08: default values
		# LINE 09: refernces
		my @de  = split(/\t/, shift(@$lines));
		my @ref = split(/\t/, shift(@$lines));
		$self->{"$table.default"} = { map { $_ => shift(@de)  } @allcols };
		$self->{"$table.ref"}     = { map { $_ => shift(@ref) } @allcols };
	}

	# LINE 10: index columns
	my @idx_cols = split(/\t/, shift(@$lines));
	$self->{"$table.index"} = { map { $_ => 1} @idx_cols };

	#-------------------------------------------------------------
	# parse index data
	#-------------------------------------------------------------
	# check cache
	if ($IndexCache{"$table.rand"} eq $random) {
		$self->{"$table.load_all"} = $IndexCache{"$table.load_all"};
		return ($self->{"$table.tbl"} = $IndexCache{$table});
	}
	# clear cahce
	if( exists($IndexCache{$table}) ) { $self->clear_cache($table); }

	my $parse_func='sub{return{ ';	# last space for chop()
	foreach (0..$#idx_cols) {
		my $col=$idx_cols[$_];
		$col =~ s/\W//g;
		$parse_func.="$col=>\$_[$_],";
	}
	chop($parse_func);
	$parse_func.='}}';
	$parse_func = $self->eval_and_cache($parse_func);

	# index data parse loop
	foreach(@$lines) {
		$_ = &$parse_func(split("\t", $_));
	}

	$self->{"$table.tbl"} = $lines;		# save table data
	$IndexCache{$table}   = $lines;		# save cache
	$IndexCache{"$table.rand"} = $random;
	return $lines;
}

#-------------------------------------------------------------------------------
# load row data file
#-------------------------------------------------------------------------------
sub read_rowfile {
	my ($self, $table, $h) = @_;
	if ($h->{'*'}) { return $h; }	# loaded flag
	my $ROBJ = $self->{ROBJ};

	my $ext = $self->{ext};
	my $dir = $self->{dir} . $table . '/';
	my $h = $ROBJ->fread_hash_cached($dir . sprintf($self->{filename_format}, $h->{pkey}). $ext);
	$h->{'*'}=1;			# loaded flag
	return $h;
}

sub read_rowfile_override {
	my ($self, $table, $h) = @_;
	if ($h->{'*'}) { return $h; }	# loaded flag
	my $ROBJ = $self->{ROBJ};

	my $ext = $self->{ext};
	my $dir = $self->{dir} . $table . '/';
	my $h2 = $ROBJ->fread_hash_cached($dir . sprintf($self->{filename_format}, $h->{pkey}). $ext);
	foreach(keys(%$h2)) {
		$h->{$_}=$h2->{$_};	# override
	}
	$h->{'*'}=1;			# loaded flag
	return $h;
}

#-------------------------------------------------------------------------------
# load all row data file
#-------------------------------------------------------------------------------
sub load_allrow {
	my $self  = shift;
	my $table = shift;
	my $row_fn= shift || 'read_rowfile';
	if ($self->{"$table.load_all"}) { return $self->{"$table.tbl"}; }

	$self->trace("load all data on '$table'");
	my $ext = $self->{ext};
	my $dir = $self->{dir} . $table . '/';
	$self->{"$table.tbl"} = [ map { $self->$row_fn($table, $_) } @{$self->{"$table.tbl"}} ];
	$self->{"$table.load_all"} = 1;
	$IndexCache{"$table.load_all"} = 1;
	return ($IndexCache{$table} = $self->{"$table.tbl"});
}

################################################################################
# common subroutins
################################################################################
#-------------------------------------------------------------------------------
# eval and cache
#-------------------------------------------------------------------------------
my %function_cache;
sub eval_and_cache {
	my $self=shift;
	my $functext=shift;
	if (exists $function_cache{$functext}) {
		return $function_cache{$functext};
	}
	# trace
	if ($self->{TRACE}) { $self->trace('[eval] ' . $functext); }

	# function compile
	my $func;
	eval "\$func=$functext";
	if ($@) {
		my ($pack, $file, $line) = caller();
		die "[$self->{DBMS}] in eval_and_cache() $@ (from $file at $line)";
	}
	return ($function_cache{$functext} = $func);
}

1;
