#!/bin/sh

my_dir="`dirname \"$0\"`"
cd "$my_dir"
if [ $? -ne 0 ] ; then
	echo "Could not cd to $my_dir" >&2
	exit 5
fi

. $my_dir/XCAB.settings
. $my_dir/functions.sh

#Find the most recent automatically generated provisioning profile
for f in `ls -1tr "$HOME/Library/MobileDevice/Provisioning Profiles/"`; do 
	grep -l 'Team Provisioning Profile: *' "$HOME/Library/MobileDevice/Provisioning Profiles/$f" > /dev/null 2>&1
	if [ $? -eq 0 ]; then
		provprofile="$HOME/Library/MobileDevice/Provisioning Profiles/$f"
	fi
done

if [ ! -z "$CODESIGNING_KEYCHAIN" -a ! -z "$CODESIGNING_KEYCHAIN_PASSWORD" -a -f "$CODESIGNING_KEYCHAIN" ] ; then
	security list-keychains -s $CODESIGNING_KEYCHAIN
	security unlock-keychain -p $CODESIGNING_KEYCHAIN_PASSWORD $CODESIGNING_KEYCHAIN
	if [ $? -ne 0 ] ; then
		echo "Error unlocking $CODESIGNING_KEYCHAIN keychain" >&2
		exit 4
	fi
else
	echo "Please enter your password to allow access to your code signign keychain"
	security list-keychains -s $HOME/Library/Keychains/login.keychain
	security unlock-keychain $HOME/Library/Keychains/login.keychain
	if [ $? -ne 0 ] ; then
		echo "Error unlocking login keychain" >&2
		exit 4
	fi
fi


if [ ! -d "$OVER_AIR_INSTALLS_DIR" ] ; then
	mkdir -p "$OVER_AIR_INSTALLS_DIR" 2>/dev/null
fi

build_time_human="`date +%Y%m%d%H%M%S`"

now="`date '+%s'`"
days=21 # don't build things more than 2 days old
cutoff_window="`expr $days \* 24 \* 60 \* 60`" 
cutoff_time="`expr $now - $cutoff_window`"

cd $XCAB_HOME

for target in *; do
	$my_dir/build_and_notify_single_project.sh $target
done

if [ ! -z "$RSYNC_USER" ] ; then
	#One more Sync just to be sure If we're not using Dropbox's public web server, run rsync now
	rsync -r ${OVER_AIR_INSTALLS_DIR} ${RSYNC_USER}@${XCAB_WEBSERVER_HOSTNAME}:${XCAB_WEBSERVER_XCAB_DIRECTORY_PATH}
fi
