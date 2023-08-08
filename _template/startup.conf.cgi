<$'rm_any'>	Ignore non-command.
<@#>		Treat lines starting with '#' as comments.
################################################################################
# <@NAME> startup skeleton
################################################################################

# Comment out for release
<$Develop=1>

#-------------------------------------------------------------------------------
# Directories
#-------------------------------------------------------------------------------
# public directory
<$constant(script_dir) = 'js/'>
<$constant(theme_dir)  = 'theme/'>

# private directory
<$constant(data_dir) = 'data/'>

# skeleton directory
<$regist_skeleton('skel/')>

#-------------------------------------------------------------------------------
# Init
#-------------------------------------------------------------------------------
# umask setting
<$ifumask(HTTPD || UID ne '' && UID<101, 0000)>

#-------------------------------------------------------------------------------
# Database
#-------------------------------------------------------------------------------
#<$DB = loadpm('DB_text', "<@data_dir>db")>

#-------------------------------------------------------------------------------
# Load main system
#-------------------------------------------------------------------------------
<$v=Main=loadapp('<@NAME>')>

# <$v=Main=loadapp('<@NAME>', DB)>

<$v.title = '<@NAME>'>

<$v.data_dir   = data_dir>
<$v.theme_dir  = theme_dir>
<$v.script_dir = script_dir>

#-------------------------------------------------------------------------------
# Form setting
#-------------------------------------------------------------------------------
<$If_post_exec_pre = begin>
	<$Form_options.total_max_size = 256K>
	<$Form_options.str_max_chars  =   80>	# word count
	<$Form_options.txt_max_chars  =    0>	# 0 is no limit

	<$Form_options.allow_multipart = false>

	<$resolve_host()>
<$end>
