use 5.8.1;
use strict;
#-------------------------------------------------------------------------------
# <@NAME>
#						(C)<@YEAR> AUTHOR NAME
#-------------------------------------------------------------------------------
package SakiaApp::<@LIB_NAME>;
use Sakia::AutoLoader;
#-------------------------------------------------------------------------------
our $VERSION = '0.01';
################################################################################
# Constructor
################################################################################
sub new {
	my $self = bless({}, shift);
	$self->{ROBJ} = shift;
	$self->{DB}   = shift;
	$self->{VERSION} = $VERSION;

	$self->{main_skel}  = '_main';
	$self->{frame_skel} = '_frame';

	return $self;
}

################################################################################
# main
################################################################################
sub main {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};

	$ROBJ->read_query();
	$ROBJ->read_form();

	#-------------------------------------------------------------
	# POST action
	#-------------------------------------------------------------
	if ($ROBJ->{POST}) {
		my $action = $ROBJ->{Form}->{action};
		if ($action =~ /^(?:\w+_)?_ajax_\w+$/) {
			my $data = $self->ajax_function( $action );

			# Append debug message
			if ($ROBJ->{Develop} && ref($data) eq 'HASH'
			&& (my $err = $ROBJ->clear_error() . $ROBJ->clear_msg() . $ROBJ->clear_debug()) ) {
				$data->{_debug} = $err;
			}

			$self->{action_data} = $ROBJ->generate_json( $data );
		}
	}

	#-------------------------------------------------------------
	# call skeleton
	#-------------------------------------------------------------
	my $skel = $self->select_skeleton( substr($ENV{PATH_INFO},1) );

	$self->output_html( $skel );
}

#-------------------------------------------------------------------------------
# select skeleton
#-------------------------------------------------------------------------------
sub select_skeleton {
	my $self = shift;
	my $skel = shift;
	my $ROBJ = $self->{ROBJ};

	my ($dir,$file) = $self->parse_skel( $skel );
	my $skel = "$dir$file" || $self->{main_skel};

	if ($skel ne '' && !$ROBJ->find_skeleton($skel)) {
		$ROBJ->redirect( $ROBJ->{myself} );
	}

	$self->{skeleton}  = $skel;
	$self->{skel_dir}  = $dir;
	$self->{skel_name} = $file;
	$self->{thisurl}   = $ROBJ->{myself2} . $skel;
	return $skel;
}
sub parse_skel {
	my ($self, $str) = @_;
	if ($str =~ m|\.\.|) { return '-error-'; }	# safety
	if ($str !~ m|^((?:[A-Za-z0-9][\w\-]*/)*)([A-Za-z0-9][\w\-]*)?$|) { return '-error-'; }
	my $b = ($1 ne '' && $2 eq '') ? 'index' : $2;
	return wantarray ? ($1,$b) : "$1$b";
}

#-------------------------------------------------------------------------------
# output html
#-------------------------------------------------------------------------------
sub output_html {
	my $self = shift;
	my $skel = shift;
	my $ROBJ = $self->{ROBJ};

	my $out;
	if ($self->{action_is_main}) {
		$out = $self->{action_data};
	} else {
		$out = $ROBJ->call( $skel );
	}

	my $frame = $self->{frame_skel};
	if ($frame) {
		$out = $ROBJ->call($frame, $out);
	}
	$ROBJ->output($out);
}

#-------------------------------------------------------------------------------
# Ajax
#-------------------------------------------------------------------------------
sub ajax_function {
	my $self = shift;
	$self->json_mode();

	my $h = $self->do_ajax_function(@_);
	if (!ref($h)) { return { ret => $h } }
	if (ref($h) ne 'ARRAY') { return $h; }

	my %r = (ret => shift(@$h));
	if (@$h) {
		my $v = shift(@$h);
		$r{ref($v) ? 'errs' : 'msg'} = $v;
	}
	if (@$h) { $r{data} = shift(@$h); }
	return \%r;
}

sub do_ajax_function {
	my $self = shift;
	my $func = shift;
	my $ROBJ = $self->{ROBJ};

	# if ($func ne '_ajax_login' && !$ROBJ->{Auth}->{ok}) {
	#	return [ -99.1, 'require login' ];
	# }

	my $r;
	eval { $r = $self->$func( $ROBJ->{Form} ); };
	if (!$@) { return $r; }

	# eval error
	return [ -99.9, $@ ];
}

#-------------------------------------------------------------------------------
# json_mode
#-------------------------------------------------------------------------------
sub json_mode {
	my $self = shift;
	$self->{action_is_main} = 1;
	$self->{frame_skel} = undef;
}

################################################################################
# functions
################################################################################
sub _ajax_test {
	my $self = shift;
	my $form = shift;
	my $ROBJ = $self->{ROBJ};

	my $a = $form->{a};
	my $b = $form->{b};
	my $c = $form->{c};
	$ROBJ->clear_form_err();

	if ($a !~ /^[\+\-]?(\d+|\d*\.\d+)$/) {
		$ROBJ->form_err('a', '"a" is not a number!');
	}
	if ($b !~ /^[\+\-]?(\d+|\d*\.\d+)$/) {
		$ROBJ->form_err('b', '"b" is not a number!');
	}
	if ($c !~ /^[\+\-]?(\d+|\d*\.\d+)$/) {
		$ROBJ->form_err('c', '"c" is not a number!');
	}
	if ($ROBJ->form_err()) {
		return [ 10, $ROBJ->form_err() ]
	}

	my $y = $b*$b - 4*$a*$c;
	if ($y<0) {
		return [ 20, '"x" does not exist in real number.' ];
	}

	my $z  = sqrt($y);
	my $x0 = (-$b+$z) / (2*$a);
	my $x1 = (-$b-$z) / (2*$a);

	if ($y==0) {
		return { ret => 0, result => "x = $x0" };
	}
	return { ret => 0, result => "x = $x0, $x1" };
}




1;
