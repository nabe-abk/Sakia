use strict;
#-------------------------------------------------------------------------------
package Sakia::Base::Compiler;
use Fcntl;
################################################################################
# error process
################################################################################
sub error_from {
	my $self = shift;
	my $h    = shift;
	my $ROBJ = $self->{ROBJ};
	$self->{errors}++;
	my $msg = $ROBJ->translate(@_);

	my $strbuf = $self->{st}->{strbuf};
	$msg =~ s/\x00(\d+)\x00/$strbuf->[$1]/g;
	$msg =~ s/[\x00-\x01]//g;

	my ($pack, $file, $line) = caller;
	if ($file =~ /AutoLoader\.pm$/) {
		($pack, $file, $line) = caller(1);
	}
	$file =~ s|.*/||;
	my $src = $self->{src_file} . ($h ? " line $h->{lnum}" : '');

	$ROBJ->error_from("$src, $file $line", "[Compiler] $msg");	## mskip
	$h->{error} = 1;
	$h->{out}   = "<!-- [Compiler] " . $ROBJ->esc($msg =~ s/--/==/rg) . " at $src -->";
}

################################################################################
# debug process
################################################################################
sub save_log {
	my $self = shift;
	my ($st, $lines, $file) = @_;
	my $ROBJ = $self->{ROBJ};

	my $strbuf = $st->{strbuf};

	my $fh = *STDOUT;
	if ($file ne '') {
		$fh=undef;
		sysopen($fh, $file, O_CREAT | O_WRONLY | O_TRUNC);
	}

	foreach(@$lines) {
		if (!ref($_)) {
			print $fh "$_";
			next;
		}
		my $m = $_->{replace} ? '@' : '$';
		my $type;
		my $msg;
		my $blv = exists($_->{block_lv}) ? "bl=$_->{block_lv} " : '';

		if (exists($_->{out})) {
			if ($_->{out} eq '') { next; }
			$type = 'out';
			$msg  = $_->{out};

		} elsif (exists($_->{exp})) {
			$type = $m . 'exp';
			$msg  = $_->{exp};

		} elsif ($_->{poland}) {
			$type = $m . 'pol';
			$msg  = join(' ', @{$_->{poland}});

		} elsif (exists($_->{cmd})) {
			$type = $m . 'cmd';
			$msg  = $_->{cmd};

		} elsif ($_->{data} ne '') {
			$type = $_->{delete} ? 'del' : 'data';
			$msg  = $_->{data};
		}
		$msg =~ s/\x00(\d+)\x00/$strbuf->[$1]/g;
		$msg =~ s/[\x00-\x01]//g;
		$msg =~ s/\n/\\n/g;

		my @info;
		if ($_->{block_end}) { push(@info, "end=$_->{block_end}"); }
		if (@info) {
			$msg .= "\t# " . join(' ', @info);
		}

		printf($fh "%04d %s) %s%s\n", $_->{lnum}, substr("    $type",-4), $blv, $msg);
	}
	if ($file ne '') { close($fh); }
}

#-------------------------------------------------------------------------------
# debug functions
#-------------------------------------------------------------------------------
sub dump_localvar_stack {
	my $self = shift;
	my $st   = shift;
	my $msg  = shift;
	my $ls   = $st->{local_st} || [];
	$msg && print "\t$msg\n";
	foreach(0..$#$ls) {
		print "\t[lv-stack($_)] " . join(' ', keys(%{$ls->[$_]})) . "\n";
	}
	print "\t[lv-stack(" . ($#$ls+1) . ")] " . join(' ', keys(%{$st->{local} || {}})) . "\n";
}

sub dump_current_localvar {
	my $self = shift;
	my $st   = shift;
	my $ls   = $st->{local_st} || [];
	print "\t[lv-stack(" . ($#$ls+1) . ")] " . join(' ', keys(%{$st->{local} || {}})) . "\n";
}


1;
