use strict;
package Sakia::DB::sql_emulator;
our $VERSION = '0.10';
################################################################################
# constructor
################################################################################
sub new {
	my $class = shift;
	return bless({ ROBJ => shift, __CACHE_PM => 1 }, $class);
}

################################################################################
# main
################################################################################
sub sql_emulator {
	my $self = shift;
	my $DB   = shift;
	my $sql  = shift;
	my $opt  = shift || {};
	my $ROBJ = $self->{ROBJ};

	my $log = [ "***SQL emulator Version $VERSION***" ];

	$self->{log} = $log;
	$sql = $self->save_string($sql);	# init $self->{str}

	local($DB->{error_hook}) = sub {
		return $self->error(@_);
	};
	local($DB->{trace_hook}) = sub {
		return $self->log(@_);
	};
	local($DB->{TRACE})=1 if ($opt->{trace});

	my $result;
	foreach my $line (split(/;/, $sql)) {
		if ($line =~ /^\s*$/) { next; }
		$line =~ s/^ //;
		$line =~ s/ $//;

		$self->{words} = [ split(/ /, $line) ];

		my $cmd = $self->next_word();
		if ($cmd eq '\D')       { $cmd='SHOW'; }
		if ($cmd eq 'DESCRIBE') { $cmd='SHOW'; }

		if    ($cmd eq 'SELECT') { $result=$self->sql_emu_select($DB); }
		elsif ($cmd eq 'INSERT') { $self->sql_emu_insert($DB); }
		elsif ($cmd eq 'UPDATE') { $self->sql_emu_update($DB); }
		elsif ($cmd eq 'DELETE') { $self->sql_emu_delete($DB); }
		elsif ($cmd eq 'CREATE') { $self->sql_emu_create($DB); }
		elsif ($cmd eq 'DROP')   { $self->sql_emu_drop  ($DB); }
		elsif ($cmd eq 'ALTER')  { $self->sql_emu_alter ($DB); }
		elsif ($cmd eq 'BEGIN')  { $DB->begin();  }
		elsif ($cmd eq 'COMMIT') { $DB->commit(); }
		elsif ($cmd eq 'ROLLBACK'){$DB->rollback(); }

		elsif ($cmd eq 'GEN')    { $self->sql_emu_gen($DB); }
		elsif ($cmd eq 'SHOW')   { $result=$self->sql_emu_show($DB); }
		else {
			$self->error('Unknown command: %s', $cmd);
		}
	}

	$self->restore_string(@$log);

	return ($result, $log);
}

#-------------------------------------------------------------------------------
# select
#-------------------------------------------------------------------------------
sub sql_emu_select {
	my $self = shift;
	my $DB   = shift;

	my $cols = $self->next_value();
	if ($cols eq '') {
		$self->error('SELECT need table name');
		return;
	}
	if ($cols =~ /^version\(\)$/) {
		$self->log('DB Version = %s', $DB->db_version());
		return;
	}

	my %h;
	my @cols;
	my $group_cols=0;
	foreach(split(/ ?, ?/, $cols)) {
		if ($_ eq '*') {
			push(@cols, '*');
			next;
		}
		my $c = $_;
		my $n = '';
		if ($c =~ /^(.*)( \w+)$/) {		# col name
			$c = $1;
			$n = $2;
		}
		$c =~ s/ //g;

		if ($c =~ /^\w+\(([^\)]*)\)$/i) {	# func(col)
			$c = $1;
			$group_cols++;
		}
		if ($c !~ /^\w+(?:\.(?:\w+|\*))?$/) {
			return $self->error('SELECT colmuns error: %s', $_);
		}
		push(@cols, "$c$n");
	}
	if ($#cols!=0 || $cols[0] ne '*') {
		$h{cols} = \@cols;
	}

	if (! $self->next_word_is('FROM')) { return; }

	my $table = $self->next_value_is_table_with_name();
	if (!$table) { return; }

	my $words = $self->{words};
	my %exists;
	while(@$words) {
		my $w = $self->next_word();

		if ($w eq 'LEFT') {
			if ($exists{WHERE} || $exists{GROUP} || $exists{ORDER} || $exists{OFFSET} || $exists{LIMIT}) {
				return $self->error('SQL error: %s', $w);
			}

			if (! $self->next_word_is('JOIN')) { return; }

			my $jt = $self->next_value_is_table_with_name();
			if (!$jt) { return; }

			#---------------------------------------------
			# search join table's colmuns from @cols 
			#---------------------------------------------
			my $jn = $jt =~ /^\w+ (\w+)$/ ? $1 : $jt;
			my @jcols;
			foreach(@cols) {
				if ($_ !~ /^(\w+)\.(.*)/ || $1 ne $jn) { next; }
				push(@jcols, $2);
				$_ = undef;
			}
			@cols = grep { defined $_ } @cols;

			#---------------------------------------------
			# join on
			#---------------------------------------------
			if (! $self->next_word_is('ON')) { return; }
			$w = 'ON';

			my $v = $self->next_value();
			if ($v !~ /^(\w+\.\w+) ?= ?(\w+\.\w+)$/) {
				return $self->error('SQL error: %s %s', $w, $v);
			}

			my $lj = $h{ljoin} ||= [];
			push(@$lj, {
				table	=> $jt,
				left	=> $1,
				right	=> $2,
				cols	=> \@jcols
			});

		} elsif ($w eq 'WHERE') {
			if ($exists{WHERE} || $exists{GROUP} || $exists{ORDER} || $exists{OFFSET} || $exists{LIMIT}) {
				return $self->error('SQL error: %s', $w);
			}
			if (! $self->parse_where(\%h)) { return; }

		} elsif ($w eq 'GROUP') {
			if ($exists{GROUP} || $exists{ORDER} || $exists{OFFSET} || $exists{LIMIT}) {
				return $self->error('SQL error: %s', $w);
			}

			if (! $self->next_word_is('BY')) { return; }
			my $w2 = $w . ' BY';

			my $gcol = $self->next_value();
			if ($gcol !~ /^(\w+(?:\.\w+)?)$/) {
				return $self->error('SQL error: %s %s', $w2, $gcol);
			}
			$h{group_by} = $gcol;

		} elsif ($w eq 'ORDER') {
			if ($exists{ORDER} || $exists{OFFSET} || $exists{LIMIT}) {
				return $self->error('SQL error: %s', $w);
			}

			if (! $self->next_word_is('BY')) { return; }
			my $w2 = $w . ' BY';

			my @ary = split(/ ?, ?/, $self->next_value());
			foreach(@ary) {
				if ($_ !~ /^(\w+(?:\.\w+)?)( DESC)?$/i) {
					return $self->error('SQL error: %s %s', $w2, $_);
				}
				$_ = ($2 ? '-' : '') . $1;
			}
			$h{sort} = \@ary;

		} elsif ($w eq 'OFFSET') {
			if ($exists{OFFSET} || $exists{LIMIT}) {
				return $self->error('SQL error: %s', $w);
			}

			my $v = $self->next_value();
			if ($v !~ /^(\+|\-|)\d+$/) {
				return $self->error('SQL error: %s %s', $w, $v);
			}
			$h{offset} = int($v);

		} elsif ($w eq 'LIMIT') {
			if ($exists{LIMIT}) {
				return $self->error('SQL error: %s', $w);
			}

			my $v = $self->next_value();
			if ($v !~ /^(\+|\-|)\d+$/) {
				return $self->error('SQL error: %s %s', $w, $v);
			}
			$h{limit} = int($v);
		} else {
			return $self->error('SQL error: %s', $w);
		}

		$exists{$w}=1;
	}

	#---------------------------------------------------
	# group by checker
	#---------------------------------------------------
	my $func = 'select';
	if (exists($h{group_by})) {
		$func = 'select_by_group';

	} elsif($group_cols) {
		return $self->error('func() column requires a "GROUP BY": %s', $cols);
	}

	return $DB->$func($table, \%h);
}

#-------------------------------------------------------------------------------
# INSERT
#-------------------------------------------------------------------------------
sub sql_emu_insert {
	my $self = shift;
	my $DB   = shift;
	if (! $self->next_word_is('INTO')) { return; }

	my $sql = $self->get_remain();
	if ($sql !~ /^(\w+) ?\( ?([^\)]*?) ?\) ?(.*)/) {
		return $self->error('SQL error: %s', $sql);
	}
	my $table = $1;
	my $cols  = $2;

	$sql = $3;
	if ($sql !~ /^values\( ?([^\)]*?) ?\)$/i) {
		return $self->error('Not found VALUES(): %s', $sql);
	}
	my $vals = $1;

	my @ary = split(/ ?, ?/, $cols);
	my @val = split(/ ?, ?/, $vals);
	if ($#ary != $#val) {
		return $self->error('Not match colmuns and values.');
	}

	my %h;
	foreach(@ary) {
		if ($_ !~ /^\w+$/) {
			return $self->error('SQL error: %s', $_);
		}
		my $vi      = shift(@val);
		my ($r, $v) = $self->check_insert_value($vi);
		if (!defined $r) {
			return $self->error('SQL error: %s', $vi);
		}

		my $col = ($r ? '*' : '') . $_;
		$h{$col}= $v;
	}

	my $r = $DB->insert($table, \%h);
	if ($r) {
		$self->log('INSERT success: pkey=%d', $r);
	} else {
		$self->log('INSERT fail');
	}
}

sub check_insert_value {
	my $self = shift;
	my $v    = shift;

	if ($v =~ /^\0#\d+$/) {
		return (0, $self->load_string($v));
	}
	if ($v+0 eq $v) {	# is Number
		return (0, $v);
	}
	if ($v =~ /\0#/ || $v =~ /[^\w\+\-\*\/\%\(\)\|\&\~<> ]/) {
		return;		# error
	}
	return ('*', $v);
}

#-------------------------------------------------------------------------------
# UPDATE
#-------------------------------------------------------------------------------
sub sql_emu_update {
	my $self = shift;
	my $DB   = shift;

	my $table = $self->next_value_is_table();
	if (!$table) { return; }

	if (! $self->next_word_is('SET')) { return; }

	my %h;
	my $set = $self->next_value();
	foreach(split(/ ?, ?/, $set)) {
		if ($_ !~ /^(\w+) ?= ?(.*)/) {
			return $self->error('SQL error: %s', $_);
		}
		my $col = $1;
		my $vi  = $2;
		my ($r, $v) = $self->check_insert_value($vi);
		if (!defined $r) {
			return $self->error('SQL error: %s', $vi);
		}

		$col = ($r ? '*' : '') . $col;
		$h{$col}= $v;
	}

	my $ary = [];

	my $w = $self->next_word();
	if ($w eq 'WHERE') {
		$ary = $self->parse_where_for_match();
		if (!$ary) { return; }
	} elsif ($w ne '') {
		return $self->error('SQL error: %s', $w);
	}

	my $r = $DB->update_match($table, \%h, @$ary);
	$self->log('UPDATE %d rows', $r);
}

#-------------------------------------------------------------------------------
# DELETE
#-------------------------------------------------------------------------------
sub sql_emu_delete {
	my $self = shift;
	my $DB   = shift;
	if (! $self->next_word_is('FROM')) { return; }

	my $table = $self->next_value_is_table();
	if (!$table) { return; }

	my $ary = [];

	my $w = $self->next_word();
	if ($w eq 'WHERE') {
		$ary = $self->parse_where_for_match();
		if (!$ary) { return; }
	} elsif ($w ne '') {
		return $self->error('SQL error: %s', $w);
	}

	my $r = $DB->delete_match($table, @$ary);
	$self->log('DELETE %d rows', $r);
}

#-------------------------------------------------------------------------------
# CREATE
#-------------------------------------------------------------------------------
sub sql_emu_create {
	my $self = shift;
	my $DB   = shift;

	my $w = $self->next_word();
	if ($w eq 'TABLE') {
		my $sql = $self->get_remain();
		if ($sql !~ /^(\w+) ?\( ?(.*?) ?\)$/) {
			return $self->error('SQL error: %s', substr($sql, 0, 20));
		}
		my $table = $1;
		my $cols  = $2 =~ s/ ?, ?/\n/gr;
		$self->restore_string($cols);

		my $r = $DB->create_table_wrapper($table, $cols);
		$self->log('CREATE TABLE ' . ($r ? 'fail' : 'success'));

	} elsif ($w eq 'INDEX') {
		my $sql = $self->get_remain();
		if ($sql !~ /^(\w+) ?\( ?(\w+) ?\)$/) {
			$self->error('SQL error: %s', substr($sql, 0, 20));
			$self->log('example: CREATE INDEX table(col)');
			return;
		}
		my $r = $DB->create_index($1, $2);
		$self->log('CREATE INDEX ' . ($r ? 'fail' : 'success'));

	} else {
		$self->error('SQL error: %s', $w);
	}
}

#-------------------------------------------------------------------------------
# DROP
#-------------------------------------------------------------------------------
sub sql_emu_drop {
	my $self = shift;
	my $DB   = shift;

	my $w = $self->next_word();
	if ($w eq 'TABLE') {
		my $table = $self->get_remain();
		if ($table !~ /^(\w+)$/) {
			return $self->error('SQL error: %s', $table);
		}
		my $r = $DB->drop_table($table);
		$self->log('DROP TABLE ' . ($r ? 'fail' : 'success'));

	} elsif ($w eq 'INDEX') {
		my $sql = $self->get_remain();
		if ($sql !~ /^(\w+) ?\( ?(\w+) ?\)$/) {
			$self->error('SQL error: %s', substr($sql, 0, 20));
			$self->log('example: DROP INDEX table(col)');
			return;
		}
		my $r = $DB->drop_index($1, $2);
		$self->log('DROP INDEX ' . ($r ? 'fail' : 'success'));

	} else {
		$self->error('SQL error: %s', $w);
	}
}

#-------------------------------------------------------------------------------
# ALTER TABLE
#-------------------------------------------------------------------------------
sub sql_emu_alter {
	my $self = shift;
	my $DB   = shift;
	if (! $self->next_word_is('TABLE')) { return; }

	my $table = $self->next_value_is_table();
	if (!$table) { return; }

	my $w = $self->next_word();
	if ($w eq 'ALTER') {
		return $self->sql_emu_alter_colmun($DB, $table);

	} elsif ($w eq 'ADD') {
		my $col = $self->next_word_is_colmun();
		if (!$col) { return; }

		my %h;
		$h{name} = $col;
		$h{type} = $self->next_word();

		while(1) {
			my $s = $self->next_word();
			if ($s eq '') { last; }
			if ($s eq 'UNIQUE')    { $h{unique}    = 1; next; }
			if ($s eq 'INDEX')     { $h{index}     = 1; next; }
			if ($s eq 'INDEX_TDB') { $h{index_tdb} = 1; next; }

			if ($s eq 'NOT') {
				if (! $self->next_word_is('NULL')) { return; }
				$h{not_null} = 1;
				next;
			}
			if ($s eq 'DEFAULT') {
				if (!$self->get_words_len()) {
					return $self->error('Need default value');
				}
				my $val = $self->next_value();
				my ($r, $v) = $self->check_insert_value($val);
				if (!defined $r) {
					return $self->error('SQL error: %s', $val);
				}
				if ($r) {
					$h{default_sql} = $v;
				} else {
					$h{default} = $v;
				}
				next;
			}
			if ($s eq 'REFERENCES' || $s eq 'REF') {
				my $val = $self->next_value();
				if ($val !~ /^(\w+) ?\((\w+)\)$/) {
					return $self->error('SQL error: %s', $val);
				}
				$h{ref} = "$1.$2";
				next;
			}
			return $self->error('SQL error: %s', $s);
		}

		my $r = $DB->add_column($table, \%h);
		$self->log('ADD COLUMN ' . ($r ? 'fail' : 'success'));

	} elsif ($w eq 'DROP') {
		my $col = $self->next_word_is_colmun();
		if (!$col) { return; }

		my $r = $DB->drop_column($table, $col);
		$self->log('DROP COLUMN ' . ($r ? 'fail' : 'success'));

	} else {
		$self->error('SQL error: %s', $w);
	}
}

#-------------------------------------------------------------------------------
# ALTER TABLE tbl ALTER column
#-------------------------------------------------------------------------------
sub sql_emu_alter_colmun {
	my $self = shift;
	my $DB   = shift;
	my $table= shift;

	my $col = $self->next_word_is_colmun();
	if (!$col) { return; }

	#
	# ALTER TABLE $table ALTER $col
	#
	my $w = $self->next_word();
	if ($w eq 'SET') {
		my $w2 = $self->next_word();
		if ($w2 eq 'NOT') {
			my $val = $self->get_remain();
			if ($val !~ /^NULL$/i) {
				return $self->error('SQL error: %s', $val);
			}
			my $r = $DB->set_not_null($table, $col);
			$self->log('SET NOT NULL ' . ($r ? 'fail' : 'success'));

		} elsif ($w2 eq 'DEFAULT') {
			if (!$self->get_words_len()) {
				return $self->error('Need default value');
			}
			my $val = $self->get_remain();
			my ($r, $v) = $self->check_insert_value($val);
			if (!defined $r) {
				return $self->error('SQL error: %s', $val);
			}
			my $r = $DB->set_default($table, $col, $r ? undef : $v, $r ? $v : undef);
			$self->log('SET DEFAULT ' . ($r ? 'fail' : 'success'));

		} else {
			$self->error('SQL error: %s', $w2);
		}

	} elsif ($w eq 'DROP') {
		my $w2 = $self->next_word();
		if ($w2 eq 'NOT') {
			my $val = $self->get_remain();
			if ($val !~ /^NULL$/i) {
				return $self->error('SQL error: %s', $val);
			}
			my $r = $DB->drop_not_null($table, $col);
			$self->log('DROP NOT NULL ' . ($r ? 'fail' : 'success'));

		} elsif ($w2 eq 'DEFAULT') {
			if (!$self->remain_is_null()) { return; }

			my $r = $DB->drop_default($table, $col);
			$self->log('DROP DEFAULT ' . ($r ? 'fail' : 'success'));

		} else {
			$self->error('SQL error: %s', $w2);
		}

	} else {
		$self->error('SQL error: %s', $w);
	}
}


################################################################################
# original function
################################################################################
#-------------------------------------------------------------------------------
# GEN
#-------------------------------------------------------------------------------
sub sql_emu_gen {
	my $self = shift;
	my $DB   = shift;

	my $w = $self->next_word();
	if ($w eq 'PKEY') {
		my $table = $self->get_remain();
		if ($table !~ /^(\w+)$/) {
			return $self->error('SQL error: %s', $table);
		}
		my $pkey = $DB->generate_pkey($table);
		$self->log("Genereate pkey on %s = %d", $table, $pkey);

	} else {
		$self->error('SQL error: %s', $w);
		$self->log('example: GEN PKEY table');
	}
}

#-------------------------------------------------------------------------------
# SHOW
#-------------------------------------------------------------------------------
sub sql_emu_show {
	my $self = shift;
	my $DB   = shift;

	my $table = $self->get_remain();
	if ($table !~ /^\w+(?:\.\w+)?$/) {
		return $self->error('SHOW need table name: %s', $table);
	}
	return $DB->get_colmuns_info($table);
}

################################################################################
# parse WHERE
################################################################################
my %CHANGE_LR = (
	'='	=> '=',
	'!='	=> '!=',
	'>'	=> '<',
	'>='	=> '<=',
	'<'	=> '=',
	'<='	=> '<='
);
my %OP_to_KEY = (
	'='	=> 'match',
	'!='	=> 'not_match',
	'>'	=> 'gt',
	'>='	=> 'min',
	'<'	=> 'lt',
	'<='	=> 'max',

	'!!='	=> 'match',
	'!>'	=> 'max',
	'!>='	=> 'lt',
	'!<'	=> 'min',
	'!<='	=> 'gt'
);

sub parse_where {
	my $self = shift;
	my $h    = shift || {};		# $DB->select() argument
	my $cond = $self->next_value();

	if ($cond =~ / OR /i) {
		return $self->error('Not support "OR" condition: %s', $cond);
	}
	if ($cond eq '') {
		return $self->error('"WHERE" is need argument');
	}

	my %cols;
	my @ary = split(/ AND ?/i, $cond);
	my $exists_like;
	foreach(@ary) {
		my $x   = $_;
		my $not = 0;
		if ($x =~ /^NOT (.*)/i) {
			$not = 1;
			$x   = $1;
		}

		#-----------------------------------------------------
		# true and false
		#-----------------------------------------------------
		if ($x =~ /^true$/i  || $not && $x =~ /^false$/i) {
			next;
		}
		if ($x =~ /^false$/i || $not && $x =~ /^true$/i) {
			$h->{match}->{pkey}     = 0;
			$h->{not_match}->{pkey} = 0;
			next;
		}

		#-----------------------------------------------------
		# LIKE and ILIKE
		#-----------------------------------------------------
		if ($x =~ / ILIKE /i) {
			return $self->error('ILIKE is not support.');
		}
		if ($x =~ /^(.*) LIKE (.*)$/i) {
			my $l = $1;
			my $r = $2;
			if ($exists_like) {
				return $self->error("Only one LIKE is allowed.\n"
					. "[Hint] (col1, col2, =col3, ==col4) LIKE (\'word1\', \'word2\', not \'word3\')\n"
					. '	"=col" and "==col" is colmun matching. "==col" is case sensitive.'
				);
			}
			$exists_like=1;

			my @lary = $l =~ /^\( ?([^\)]+?) ?\)$/ ? split(/ ?, ?/, $1) : $l;
			my @rary = $r =~ /^\( ?([^\)]+?) ?\)$/ ? split(/ ?, ?/, $1) : $r;

			my $cols  = $h->{search_cols}  = [];
			my $match = $h->{search_match} = [];
			my $equal = $h->{search_equal} = [];
			foreach(@lary) {
				if ($_ !~ /^(=)?(=)?(\w+(?:\.\w+)?)$/) { return $self->error('SQL error: %s', $_); }
				my $ary = $2 ? $equal : ($1 ? $match : $cols);
				push(@$ary,$3);
			}

			my $words     = $h->{search_words} = [];
			my $not_words = $h->{search_not}   = [];
			foreach(@rary) {
				my $w   = $_;
				my $ary = $words;
				if ($w =~ /^NOT (.*)/i) {
					$ary = $not_words;
					$w = $1;
				}
				$w = $self->load_string_only($w);
				if (!defined $w) {
					return $self->error('SQL error: %s', $_);
				}
				$w =~ s/^%//;
				$w =~ s/%$//;
				push(@$ary, $w);
			}
			next;
		}

		#-----------------------------------------------------
		# "10 < colname" to "colname > 10"
		#-----------------------------------------------------
		my $col;
		$x =~ s/ ?(=|!=|>=|>|<|<=) ?/$1/g;

		if ($x =~ /^(\w+(?:\.\w+)?) ?(.*)/) {
			$col = $1;
			$x   = $2;

		} elsif ($x =~ /^(.*?)(=|!=|>=|>|<|<=)(\w+(?:\.\w+)?)$/) {
			$col = $3;
			$x   = $CHANGE_LR{$2} . $1;
		} else {
			return $self->error('Non-column conditions unsupported: %s', $_);
		}

		#-----------------------------------------------------
		# "colname" or "not colname"
		#-----------------------------------------------------
		if ($x eq '') {
			$h->{flag}->{$col} = $not ? 0 : 1;
			next;
		}

		#-----------------------------------------------------
		# "colname is null" or "colname is not null"
		#-----------------------------------------------------
		if ($x =~ /^IS( NOT)? NULL$/i) {
			$not = $1 ? !$not : $not;
			my $k = $not ? 'not_null' : 'is_null';
			my $a = $h->{$k} ||= [];
			push(@$a, $col);
			next;
		}

		#-----------------------------------------------------
		# boolean operator
		#-----------------------------------------------------
		if ($x =~ /^== ?true$/i) {
			$h->{boolean}->{$col} = 1;
			next;
		}
		if ($x =~ /^== ?false$/i) {
			$h->{boolean}->{$col} = 0;
			next;
		}

		#-----------------------------------------------------
		# general operator
		#-----------------------------------------------------
		if ($x =~ /^(=|!=|>=|>|<|<=)(.*)$/) {
			my $op = ($not ? '!' : '') . $1;
			my $v  = $2;
			if (!$self->check_and_restore_value($v)) { return; }

			my $k = $OP_to_KEY{$op};
			if ($h->{$k}->{$col}) {
				return $self->error('Duplicate "%s%s" conditions.', $col, $op);
			}
			$h->{$k}->{$col} = $v;
			next;
		}

		#-----------------------------------------------------
		# in (x,y,z)
		#-----------------------------------------------------
		if ($x =~ /^in ?\( ?([^\)]*?) ?\)$/) {
			my @arg = split(/ ?, ?/, $1);
			if (!$self->check_and_restore_value(@arg)) { return; }

			my $k = $not ? 'not_match' : 'match';
			$h->{$k}->{$col} = \@arg;
			next;
		}

		return $self->error('SQL error: %s', $_);
	}
	return $h;
}

sub check_and_restore_value {
	my $self = shift;
	my $str  = $self->{str_buf};

	foreach(@_) {
		if ($_ =~ /^\0#(\d+)$/) {
			$_ = $str->[$1];
			next;
		}
		my $c = $_ + 0;
		if ($c eq $_) { next; }

		return $self->error('SQL error: %s', $_);
	}
	return 1;
}

sub parse_where_for_match {
	my $self = shift;

	my $h = $self->parse_where();
	if (!$h) { return; }

	my @ary;

	my $match   = $h->{match}	|| {};
	my $n_match = $h->{not_match}	|| {};
	my $null    = $h->{is_null}	|| [];
	my $n_null  = $h->{not_null}	|| [];
	foreach(keys(%$match)) {
		push(@ary, $_, $match->{$_});
	}
	foreach(keys(%$n_match)) {
		push(@ary, "-$_", $match->{$_});
	}
	foreach(@$null) {
		push(@ary, $_, '');
	}
	foreach(@$n_null) {
		push(@ary, "-$_", '');
	}

	delete $h->{match};
	delete $h->{not_match};
	delete $h->{is_null};
	delete $h->{not_null};
	if (%$h) {
		return $self->error('UPDATE and DELETE can only use "=", "!=", "is null", "is not null", and "col in (v1,v2,...)".');
	}
	return \@ary;
}

################################################################################
# subroutine
################################################################################
my %KEYWORDS = map { $_ => 1} qw(
	SELECT
	INSERT
	UPDATE
	DELETE
	DROP
	ALTER
	BEGIN
	COMMIT
	ROLLBACK
	GEN

	FROM
	WHERE
	LEFT
	ON
	JOIN
	ORDER
	BY
	GROUP
	OFFSET
	LIMIT

	TABLE
	INDEX
	INTO
	ADD
	SET
	REFERENCES
	REF
);

sub get_words_len {
	my $self = shift;
	my $words= $self->{words};
	return $#$words+1;
}

sub next_word {
	my $self = shift;
	my $words= $self->{words};
	return shift(@$words) =~ tr/a-z/A-Z/r;
}

sub next_word_is {
	my $self = shift;
	my $check= shift;
	my $word = $self->next_word();
	if ($word ne $check) {
		return $self->error('SQL error: %s', $word);
	}
	return $word;
}

sub next_word_is_colmun {
	my $self = shift;
	my $word = $self->next_word() =~ tr/A-Z/a-z/r;
	if ($word !~ /^\w+$/) {
		return $self->error('colmun name error: %s', $word);
	}
	return $word;
}

sub next_value {
	my $self = shift;
	my $words= $self->{words};

	my @val;
	while(@$words) {
		my $v = shift(@$words);
		my $k = $v =~ tr/a-z/A-Z/r;
		if ($KEYWORDS{$k}) {
			unshift(@$words, $v);
			last;
		}
		push(@val, $v);
	}
	return join(' ', @val);
}

sub next_value_is_table {
	my $self = shift;
	my $val  = $self->next_value(@_);
	if ($val !~ /^\w+$/) {
		return $self->error('table name error: %s', $val);
	}
	return $val;
}

sub next_value_is_table_with_name {
	my $self = shift;
	my $val  = $self->next_value(@_);
	if ($val !~ /^\w+(?: \w+)?$/) {
		return $self->error('table name error: %s', $val);
	}
	return $val;
}

sub get_remain {
	my $self = shift;
	my $words= $self->{words};
	return join(' ', @$words);
}

sub remain_is_null {
	my $self = shift;
	my $words= $self->{words};
	if (@$words) {
		return $self->error('SQL error: %s', $words->[0]);
	}
	return 1;
}

#-------------------------------------------------------------------------------
# string save/restore
#-------------------------------------------------------------------------------
sub save_string {
	my $self = shift;
	my $sql  = shift;
	my $str  = $self->{str_buf} = [];

	$sql =~ s/\0//g;
	$sql =~ s/\s+--.*//g;
	$sql =~ s!'((?:[^']|'')*)'!push(@$str, $1 =~ s/''/'/rg), " \0#$#$str "!eg;
	$sql =~ s/\s+/ /g;
	return $sql;
}

sub restore_string {
	my $self = shift;

	my $str = $self->{str_buf};
	foreach(@_) {
		$_ =~ s/\0#(\d+)/'$str->[$1]'/g;
	}
	return $_[0];
}

sub load_string {
	my $self = shift;
	my $val  = shift;
	if ($val =~ /^\0#(\d+)$/) {
		return $self->{str_buf}->[$1];
	}
	return $val;
}

sub load_string_only {
	my $self = shift;
	my $val  = shift;
	if ($val =~ /^\0#(\d+)$/) {
		return $self->{str_buf}->[$1];
	}
	return;
}

#-------------------------------------------------------------------------------
# error
#-------------------------------------------------------------------------------
sub log {
	return &error(@_);
}
sub error {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	my $log  = $self->{log};
	my @ary  = split(/\n/, $ROBJ->translate(@_));
	push(@$log, @ary);

	return;
}

1;
