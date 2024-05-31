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
<$v=Main=loadapp('<@LIB_NAME>')>

# <$v=Main=loadapp('<@LIB_NAME>', DB)>

<$v.title = '<@NAME>'>

<$v.data_dir   = data_dir>
<$v.theme_dir  = theme_dir>
<$v.script_dir = script_dir>

#-------------------------------------------------------------------------------
# Form setting
#-------------------------------------------------------------------------------
<$FormOptFunc = begin_func>
	<$resolve_host()>

	<$local(opt) = {}>
	<$opt.max_size = 256K>
	<$opt.str_max_chars = 64>	# word count
	<$opt.txt_max_chars = 0>	# 0 is no limit

	<$opt.allow_multi = false>
	<$opt.multi_max_size = 16M>
	<$return(opt)>
<$end>
