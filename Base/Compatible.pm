use strict;
#-------------------------------------------------------------------------------
# Base system compatible functions
#						(C)2023 nabe@abk
#-------------------------------------------------------------------------------
package Sakia::Base::Compatible;
our $VERSION = '1.00';
################################################################################
# constructor
################################################################################
sub new {
	my $self = bless({}, shift);
	my $ROBJ = $self->{ROBJ} = shift;

	$self->compatible_base();

	return $self;
}

################################################################################
# compatible base system
################################################################################
sub compatible_base {
	my $_self= shift;
	my $ROBJ = $_self->{ROBJ};

	$ROBJ->{System_coding}	= $ROBJ->{SystemCode};
	$ROBJ->{CGI_mode}	= $ROBJ->{CgiMode};
	$ROBJ->{CGI_cache}	= $ROBJ->{CgiCache};
	$ROBJ->{Messages}	= $ROBJ->{Msgs};

	require Sakia::Base_2;

	*Sakia::Base::tm_printf	= \&Sakia::Base::print_tmf;
	*Sakia::Base::check_skeleton	= \&Sakia::Base::find_skeleton;
	*Sakia::Base::delete_skeleton = \&Sakia::Base::unregist_skeleton;
	*Sakia::Base::load_codepm		= sub { return $_[0] };
	*Sakia::Base::load_codepm_if_needs	= sub { return $_[0] };
	*Sakia::Base::jsubstr		= \&Sakia::Base::mb_substr;
	*Sakia::Base::jlength		= \&Sakia::Base::mb_length;
	*Sakia::Base::tag_escpae	= \&Sakia::Base::esc_dest;
	*Sakia::Base::tag_escape_amp	= \&Sakia::Base::esc_amp_dest;
	*Sakia::Base::tag_delete	= \&Sakia::Base::delete_tag;

	*Sakia::Base::file_symlink	= \&Sakia::Base::symlink;
	*Sakia::Base::file_move	= \&Sakia::Base::move_file;
	*Sakia::Base::file_copy	= \&Sakia::Base::copy_file;
	*Sakia::Base::file_delete	= \&Sakia::Base::remove_file;
	*Sakia::Base::dir_copy	= \&Sakia::Base::copy_dir;
	*Sakia::Base::dir_delete	= \&Sakia::Base::remove_dir;

	*Sakia::Base::read_path_info = sub {
		my $self = shift;
		my ($dummy, @pinfo) = split('/', $ENV{PATH_INFO} . "\0");
		if (@pinfo) { chop($pinfo[$#pinfo]); }

		return ($self->{Pinfo} = \@pinfo);
	};

	*Sakia::get_relative_path = sub {
		my ($self, $base, $file) = @_;
		if ($file =~ m|^/|) { return $file; }
		my $x = rindex($base, '/');
		if ($x<0) { return $file; }
		return substr($base, 0, $x+1) . $file;
	};

	*Sakia::fread_skeleton = sub {
		my $self = shift;
		my $file = $self->find_skeleton( @_ );
		if (!$file) { return; }
		return $self->fread_lines( $file );
	};

	*Sakia::get_lastmodified_in_dir = sub {
		my $self = shift;
		my $dir  = shift =~ s|/*$|/|r;

		opendir(my $fh, $dir) || return ;
		my $max = $self->get_lastmodified($dir);
		foreach(readdir($fh)) {
			if ($_ eq '.' || $_ eq '..' )  { next; }
			my $t = $self->get_lastmodified("$dir$_");
			if ($max<$t) { $max=$t; }
		}
		closedir($fh);
		return $max;
	};

	*Sakia::crypt_by_string_nosalt = sub {
		my $self = shift;
		my $str  = $self->crypt_by_string(@_);
		return $str =~ /^\$\d\$.*?\$(.*)/ ? $1 : substr($str, 2);
	};
}
1;
