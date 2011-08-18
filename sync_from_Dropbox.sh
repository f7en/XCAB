#!/bin/sh

my_dir="`dirname \"$0\"`"
cd "$my_dir"
if [ $? -ne 0 ] ; then
	echo "Could not cd to $my_dir" >&2
	exit 5
fi

. $my_dir/XCAB.settings
. $my_dir/functions.sh

if [ ! -d "${XCAB_HOME}" ] ; then
	mkdir "${XCAB_HOME}"
fi

wait_for_idle_dropbox

#Make sure the XCAB_CONF File ends in a new line, otherwise, `while read line` won't get the last line
if [ -n "`tail -1c \"$XCAB_CONF\"`" ] ; then 
	echo "" >> "$XCAB_CONF"
fi
	
exec<$XCAB_CONF
while read line 
do
	
	#Ignore comments
	if [ ! -z "`echo $line | grep '^[ 	]*#'`" ] ; then
		continue
	fi

	#If there isn't an equals sign, treat it like a comment
	if [ -z "`echo $line | grep '='`" ] ; then
		continue
	fi
	
	src_dir="`echo $line | sed -e 's/=.*$//'`"
	origin_url="`echo $line | sed -e 's/^[^=]*=//'`"

	$my_dir/sync_project_with_dropbox.sh "$src_dir" "$origin_url"

done

