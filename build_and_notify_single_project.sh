#!/bin/sh

my_dir="`dirname \"$0\"`"
cd 
if [ ! -d "$my_dir" ] ; then
	echo "Could not find directory $my_dir" >&2
	exit 5
fi

. $my_dir/functions.sh

if [ -z "$SCM_WORKING_DIR" -o ! -d "$SCM_WORKING_DIR" ] ; then
	echo "Undefined or incorrect SCM_WORKING_DIR variable.  Please check your XCAB.settings file or environment" >&2
	exit 3
fi

if [ -z "$OVER_AIR_INSTALLS_DIR" -o ! -d "$OVER_AIR_INSTALLS_DIR" ] ; then
	echo "Undefined or incorrect OVER_AIR_INSTALLS_DIR variable.  Please check your XCAB.settings file or environment" >&2
	exit 3
fi

#Need to get current project directory name and URL from the command line
if [ $# -ne 1 ] ; then
	echo "Usage: $0 <Project Name>" >&2
	exit 3
fi

target="$1"

if [ ! -d "$SCM_WORKING_DIR/$target" ] ; then
	echo "Error: Could not find directory for project in $SCM_WORKING_DIR/$target" >&2
	echo "Usage: $0 <Project Name>" >&2
	exit 3
fi

#Find the most recent automatically generated provisioning profile
for f in `ls -1tr "$HOME/Library/MobileDevice/Provisioning Profiles/"`; do 
	grep -l 'Team Provisioning Profile: *' "$HOME/Library/MobileDevice/Provisioning Profiles/$f" > /dev/null 2>&1
	if [ $? -eq 0 ]; then
		provprofile="$HOME/Library/MobileDevice/Provisioning Profiles/$f"
	fi
done

cd "$SCM_WORKING_DIR/$target"

#Bring the local repo up to date
# But if we can't talk to the server, ignore the error
#TODO make sure that, if there is an error, it's only
#  a connection error before we ignore it
git fetch > /dev/null 2>&1

if [ x"`ls -1d *xcodeproj 2>/dev/null`" == x ] ; then
	#Not an iphone dir
	continue
fi

build_time_human="`date +%Y%m%d%H%M%S`"

now="`date '+%s'`"
days=21 # don't build things more than 21 days old
cutoff_window="`expr $days \* 24 \* 60 \* 60`" 
cutoff_time="`expr $now - $cutoff_window`"

already_built="`cat $OVER_AIR_INSTALLS_DIR/$target/*/sha.txt 2>/dev/null`"

for candidate in `git branch -a | sed -e 's/^..//'` ; do
	sha="`git rev-parse $candidate`"
	commit_time="`git log -1 --pretty=format:"%ct" $sha`"
	if [ $commit_time -gt $cutoff_time ] ; then
		is_built="`echo $already_built | grep $sha`"
		if [ -z "$is_built" ] ; then
			if [ ! -z "`echo "$candidate" | grep '/'`" ] ; then
				#remote branch
				local_candidate="`echo $candidate | sed -e 's,^.*/,,'`"
				git checkout -f $local_candidate
				if [ $? -ne 0 ] ; then
					git checkout -f -b $local_candidate $candidate
				fi
			else
				git checkout -f $candidate
			fi
			git reset --hard $candidate
			git clean -d -f -x
			mkdir -p "$OVER_AIR_INSTALLS_DIR/$target/$build_time_human/"
			mkdir -p "$OVER_AIR_INSTALLS_DIR/$target/tmp/$build_time_human/"
			#TODO need to figure out a way to indicate that the user wants to build other targets
			build_target=`xcodebuild -list | awk '$1=="Targets:",$1==""' | grep -v "Targets:" | grep -v "^$" | sed -e 's/^  *//' | head -1`
			#TODO need to make sure we're building for the device
			xcodebuild build -target $build_target -configuration Debug > "$OVER_AIR_INSTALLS_DIR/$target/$build_time_human/${build_target}_output.txt" 2> "$OVER_AIR_INSTALLS_DIR/$target/$build_time_human/${build_target}_error.txt"
			if [ $? -ne 0 ] ; then
				echo "Build Failed" >&2
				echo "$sha" > "$OVER_AIR_INSTALLS_DIR/$target/$build_time_human/sha.txt" #Don't try to build this again - it would fail over and over
				rm -rf "$OVER_AIR_INSTALLS_DIR/$target/tmp/$build_time_human/"
				exit 3
			fi
			
			App_location="`grep ${build_target}.app $OVER_AIR_INSTALLS_DIR/$target/$build_time_human/${build_target}_output.txt | grep '^CodeSign' | sed -e 's/^CodeSign //'`"
			
			if [ -d "${App_location}" ] ; then
				xcrun -sdk iphoneos PackageApplication "${App_location}" -o "$OVER_AIR_INSTALLS_DIR/$target/tmp/$build_time_human/${build_target}.ipa" --sign "iPhone Developer" --embed "$provprofile"
			fi
			
			if [ $? -ne 0 ] ; then
				rm -rf $OVER_AIR_INSTALLS_DIR/$target/tmp/$build_time_human/${build_target}.ipa
				echo "Package Failed" >&2
				echo "$sha" > "$OVER_AIR_INSTALLS_DIR/$target/$build_time_human/sha.txt" #Don't try to build this again - it would fail over and over
				rm -rf "$OVER_AIR_INSTALLS_DIR/$target/tmp/$build_time_human/"
				exit 3
			fi
			
			"/Applications/BetaBuilder for iOS Apps.app/Contents/MacOS/BetaBuilder for iOS Apps" -ipaPath="$OVER_AIR_INSTALLS_DIR/$target/tmp/$build_time_human/${build_target}.ipa" -outputDirectory="$OVER_AIR_INSTALLS_DIR/$target/$build_time_human" -webserver="${XCAB_WEB_ROOT}/${target}/$build_time_human"
			if [ $? -ne 0 ] ; then
				rm -rf $OVER_AIR_INSTALLS_DIR/$target/tmp/$build_time_human/${build_target}.ipa
				echo "BetaBuilder for iOS Apps Failed" >&2
				echo "$sha" > "$OVER_AIR_INSTALLS_DIR/$target/$build_time_human/sha.txt" #Don't try to build this again - it would fail over and over
				rm -rf "$OVER_AIR_INSTALLS_DIR/$target/tmp/$build_time_human/"
				exit 3
			else
				#Save off the symbols, too
				if [ -d "${App_location}.dSYM" ] ; then
					tar czf "$OVER_AIR_INSTALLS_DIR/$target/$build_time_human/${build_target}.app.dSYM.tar.gz" "${App_location}.dSYM"
				fi

				if [ ! -z "$TESTFLIGHT_API_TOKEN" -a ! -z "$TESTFLIGHT_TEAM" ] ; then
					if [ ! -z "$TESTFLIGHT_DIST" ] ; then
						TESTFLIGHT_NOTIFY="-F notify=True  -F distribution_lists=\"$TESTFLIGHT_DIST\""
					else
						TESTFLIGHT_NOTIFY="-F notify=False"
					fi
					curl http://testflightapp.com/api/builds.json -F file=@"$OVER_AIR_INSTALLS_DIR/$target/tmp/$build_time_human/${build_target}.ipa"  -F api_token="$TESTFLIGHT_API_TOKEN" -F team_token="$TESTFLIGHT_TEAM" -F notes='New ${target} Build was uploaded via the upload API' $TESTFLIGHT_NOTIFY 
				fi
				
				rm -rf "$OVER_AIR_INSTALLS_DIR/$target/tmp/$build_time_human/${build_target}.ipa"
				
				if [ ! -z "$RSYNC_USER" ] ; then
					#If we're not using Dropbox's public web server, run rsync now
					rsync -r ${OVER_AIR_INSTALLS_DIR} ${RSYNC_USER}@${XCAB_WEBSERVER_HOSTNAME}:${XCAB_WEBSERVER_XCAB_DIRECTORY_PATH}
				fi
			
				wait_for_idle_dropbox
				
				#Wait to make sure the file has appeared on the server
				IPA_STATUS="`curl -sI -X HEAD \"${XCAB_WEB_ROOT}/${target}/$build_time_human/${build_target}.ipa\" | grep HTTP/1.1 | awk '{print $2}'`"
				PLIST_STATUS="`curl -sI -X HEAD \"${XCAB_WEB_ROOT}/${target}/$build_time_human/manifest.plist\" | grep HTTP/1.1 | awk '{print $2}'`"
				INDEX_STATUS="`curl -sI -X HEAD \"${XCAB_WEB_ROOT}/${target}/$build_time_human/index.html\" | grep HTTP/1.1 | awk '{print $2}'`"
				RETRY_COUNT=0
				while [ "$IPA_STATUS" != "200"  -o "$PLIST_STATUS" != "200"  -o "$INDEX_STATUS" != "200" ] ; do
					#Wait and try again
					sleep 15
					IPA_STATUS="`curl -sI -X HEAD \"${XCAB_WEB_ROOT}/${target}/$build_time_human/${build_target}.ipa\" | grep HTTP/1.1 | awk '{print $2}'`"
					PLIST_STATUS="`curl -sI -X HEAD \"${XCAB_WEB_ROOT}/${target}/$build_time_human/manifest.plist\" | grep HTTP/1.1 | awk '{print $2}'`"
					INDEX_STATUS="`curl -sI -X HEAD \"${XCAB_WEB_ROOT}/${target}/$build_time_human/index.html\" | grep HTTP/1.1 | awk '{print $2}'`"
					RETRY_COUNT="`expr $RETRY_COUNT + 1`"
					if [ "$RETRY_COUNT" -gt 30 ] ; then
						echo "Timeout waiting for web server to become ready" >&2
						$my_dir/notify_with_boxcar.sh "notification[source_url]=${XCAB_WEB_ROOT}/$target/$build_time_human/index.html" "notification[message]=ERROR+Timeout+Waiting+For+Webserver+For+${target}+Build"
						exit 4
					fi
				done
				
				#We're making the implicit assumption here that there aren't 
				#  going to be a bunch of new changes per run
				#   so it won't spam the user to notify for each one
				#Notify with Boxcar
				$my_dir/notify_with_boxcar.sh "notification[source_url]=${XCAB_WEB_ROOT}/$target/$build_time_human/index.html" "notification[message]=New+${target}+Build+available"
			fi
								
			echo "$sha" > "$OVER_AIR_INSTALLS_DIR/$target/$build_time_human/sha.txt"
			rm -rf "$OVER_AIR_INSTALLS_DIR/$target/tmp/$build_time_human/"
		fi
	fi
	#Don't build this again if more than one branch points at same sha
	already_built="$already_built $sha"
done
