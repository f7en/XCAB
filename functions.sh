
#This file defines several functions used by XCAB. It should not need to be customized

my_dir="`dirname \"$0\"`"
cd "$my_dir"
if [ $? -ne 0 ] ; then
	echo "Could not cd to $my_dir" >&2
	exit 5
fi

if [ -z "$SCM_WORKING_DIR" -o ! -d "$SCM_WORKING_DIR" ] ; then
    #Only source the settings file if it looks like we haven't, yet
    . $my_dir/XCAB.settings
fi

wait_for_idle_dropbox() {

    if [ ! -z "$DROPBOX_HOME" -a -d "$DROPBOX_HOME" ] ; then
        DB_PID="`cat $HOME/.dropbox/dropbox.pid`"
        
        #wait for Dropbox to finish syncing anything that might be in progress
        DB_OPEN_FILES="`/usr/sbin/lsof -p $DB_PID | grep ' REG ' | grep \" ${DROPBOX_HOME}/\" | wc -l`"

        while [ "$DB_OPEN_FILES" -ne 0 ] ; do
            sleep 3
            DB_OPEN_FILES="`/usr/sbin/lsof -p $DB_PID | grep ' REG ' | grep \" ${DROPBOX_HOME}/\" | wc -l`"
        done
    fi
}