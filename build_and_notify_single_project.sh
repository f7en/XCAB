#!/bin/sh

days=21 # don't build things more than 21 days old

my_dir="`dirname \"$0\"`"
if [ ! -d "$my_dir" ] ; then
	echo "Could not find directory $my_dir" >&2
	exit 5
fi

. $my_dir/functions.sh

usage() {
	echo "Usage: $0 [-c xcodebuild configuration] [ -d date as string ] [ -i NOTIFY,TESTFLIGHT,RSYNC ] [-m mobileprovision file] [-n newer than] [-p xcodeproj file ] [-t build target] <Project Name>" >&2
	echo "	-c xcodebuild configuration: Default is 'Debug'" >&2
	echo "	-d date as string: Default is output of 'date +%Y%m%d%H%M%S'" >&2
	echo "	-i ignore/skip post processing.  Comma separated list (no spaces) of NOTIFY,TESTFLIGHT,RSYNC" >&2
	echo "	-m mobileprovision file: Default is most recent Team Provisioning Profile in $HOME/Library/MobileDevice/Provisioning Profiles" >&2
	echo "	-n newer than: only build branches with commits newer than this. Default is unix (date +%s) style for 21 days ago" >&2
	echo "	-p xcodeproj file: Default is <Project Name>.xcodeproj" >&2
	echo "	-s sdk: Default the last sdk on a line that starts with iOS in the output of 'xcodebuild -showsdks''" >&2
	echo "	-t built target: Default is first target found in the output of 'xcodebuild -list'" >&2
	exit 3
}

while getopts "c:d:m:n:p:s:t:" optionName; do
	case "$optionName" in
		c) configuration="$OPTARG";;
		d) build_time_human="$OPTARG";;
		i) ignore_opts="$OPTARG";;
		m) provprofile="$OPTARG";;
		n) cutoff_time="$OPTARG";;
		p) projectFile="$OPTARG";;
		s) use_sdk="$OPTARG";;
		t) build_target="$OPTARG";;
		h) usage;;
	esac
done

if [ $OPTIND -gt 1 ]; then
  #still arguments to parse
  shift $(($OPTIND - 1))
fi

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
	echo "Could not get correct number of arguments (arguments are $@)"
	usage
fi

target="$1"

#Setup Defaults
if [ -z "$configuration" ] ; then
	configuration="Debug"
fi
if [ -z "$projectFile" ] ; then
	projectFile="${target}.xcodeproj"
fi
if [ -z "$ignore_opts" ] ; then
	ignore_opts="NONE"
fi

if [ -z "$provprofile" ] ; then
	#Find the most recent automatically generated provisioning profile
	for f in `ls -1tr "$HOME/Library/MobileDevice/Provisioning Profiles/"`; do 
		grep -l 'Team Provisioning Profile: *' "$HOME/Library/MobileDevice/Provisioning Profiles/$f" > /dev/null 2>&1
		if [ $? -eq 0 ]; then
			provprofile="$HOME/Library/MobileDevice/Provisioning Profiles/$f"
		fi
	done
fi

if [ -z "$provprofile" ] ; then
	echo "Error: Could not find a provisioning profile. Please consider specifying one with the -m option to $0" >&2
	usage
	exit 3
fi

if [ ! -d "$SCM_WORKING_DIR/$target" ] ; then
	echo "Error: Could not find directory for project in $SCM_WORKING_DIR/$target" >&2
	echo "Usage: $0 <Project Name>" >&2
	exit 3
fi

cd "$SCM_WORKING_DIR/$target"

#Bring the local repo up to date
# But if we can't talk to the server, ignore the error
#TODO make sure that, if there is an error, it's only
#  a connection error before we ignore it
git fetch > /dev/null 2>&1

if [ -z "$build_time_human" ] ; then
  build_time_human="`date +%Y%m%d%H%M%S`"
fi

now="`date '+%s'`"
cutoff_window="`expr $days \* 24 \* 60 \* 60`" 
if [ -z "$cutoff_time" ] ; then
  cutoff_time="`expr $now - $cutoff_window`"
fi

if [ -z "$use_sdk" ] ; then
	use_sdk="`xcodebuild -showsdks | grep -- '-sdk' | grep -iv 'Simulator' | grep iOS | tail -1 | awk '{print $NF}'`"
fi
already_built="`cat $OVER_AIR_INSTALLS_DIR/$target/*/sha.txt 2>/dev/null`"

for candidate in `git branch -a | sed -e 's/^..//' -e 's/ ->.*$//' -e 's,^remotes/,,' | sort -t / -k 2 -k 1 -k 3` ; do
	sha="`git rev-parse $candidate`"
	commit_time="`git log -1 --pretty=format:"%ct" $sha`"
	if [ "$commit_time" -gt "$cutoff_time" ] ; then
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
			if [ -z "$build_target" ] ; then
				build_target=`xcodebuild -list -project $projectFile | awk '$1=="Targets:",$1==""' | grep -v "Targets:" | grep -v "^$" | sed -e 's/^  *//' | head -1`
			fi
			
			#TODO need to make sure we're building for the device
			xcodebuild build -target $build_target -configuration $configuration -project $projectFile -sdk "$use_sdk" > "$OVER_AIR_INSTALLS_DIR/$target/$build_time_human/${build_target}_xcodebuild_output.txt" 2> "$OVER_AIR_INSTALLS_DIR/$target/$build_time_human/${build_target}_xcodebuild_error.txt"
			if [ $? -ne 0 ] ; then
			  cat "$OVER_AIR_INSTALLS_DIR/$target/$build_time_human/${build_target}_xcodebuild_output.txt"
			  cat "$OVER_AIR_INSTALLS_DIR/$target/$build_time_human/${build_target}_xcodebuild_error.txt" >&2
				echo "Build Failed" >&2
				echo "$sha" > "$OVER_AIR_INSTALLS_DIR/$target/$build_time_human/sha.txt" #Don't try to build this again - it would fail over and over
				rm -rf "$OVER_AIR_INSTALLS_DIR/$target/tmp/$build_time_human/"
				exit 3
			fi
			cat "$OVER_AIR_INSTALLS_DIR/$target/$build_time_human/${build_target}_xcodebuild_output.txt"
		  cat "$OVER_AIR_INSTALLS_DIR/$target/$build_time_human/${build_target}_xcodebuild_error.txt" >&2
		  
			#Don't build this again this run if more than one branch points at same sha
			already_built="$already_built $sha"
			
			App_location="`grep 'iphoneos.*\\.app\"$' $OVER_AIR_INSTALLS_DIR/$target/$build_time_human/${build_target}_xcodebuild_output.txt | grep '^ */usr/bin/codesign' | sed -e 's/\"[^\"]*\$//' -e 's/^.*\"//'`"
			App_name="`echo \"${App_location}\" | sed -e 's,^.*/,,' -e 's/\.app$//'`"
			
			echo "Built App named '${App_name}' in relative location '${App_location}'"
			
			if [ -d "${App_location}" ] ; then
				xcrun -sdk iphoneos PackageApplication "${App_location}" -o "$OVER_AIR_INSTALLS_DIR/$target/tmp/$build_time_human/${App_name}.ipa" --sign "iPhone Developer" --embed "$provprofile"
			else
				echo "Could not find app '${App_name}' at relative location '${App_location}' full path '`pwd`/${App_location}'"
				rm -rf "$OVER_AIR_INSTALLS_DIR/$target/tmp/$build_time_human/${App_name}.ipa"
				echo "Package Failed" >&2
				echo "$sha" > "$OVER_AIR_INSTALLS_DIR/$target/$build_time_human/sha.txt" #Don't try to build this again - it would fail over and over
				rm -rf "$OVER_AIR_INSTALLS_DIR/$target/tmp/$build_time_human/"
				exit 3
			fi
			
			if [ $? -ne 0 ] ; then
				rm -rf "$OVER_AIR_INSTALLS_DIR/$target/tmp/$build_time_human/${App_name}.ipa"
				echo "Package Failed" >&2
				echo "$sha" > "$OVER_AIR_INSTALLS_DIR/$target/$build_time_human/sha.txt" #Don't try to build this again - it would fail over and over
				rm -rf "$OVER_AIR_INSTALLS_DIR/$target/tmp/$build_time_human/"
				exit 3
			fi
						
			if [ ! -z "${XCAB_WEB_ROOT}" -a -f "/Applications/BetaBuilder for iOS Apps.app/Contents/MacOS/BetaBuilder for iOS Apps" ] ; then
				echo "running /Applications/BetaBuilder for iOS Apps.app/Contents/MacOS/BetaBuilder for iOS Apps" -ipaPath="$OVER_AIR_INSTALLS_DIR/$target/tmp/$build_time_human/${App_name}.ipa" -outputDirectory="$OVER_AIR_INSTALLS_DIR/$target/$build_time_human" -webserver="${XCAB_WEB_ROOT}/${target}/$build_time_human"
				
				"/Applications/BetaBuilder for iOS Apps.app/Contents/MacOS/BetaBuilder for iOS Apps" -ipaPath="$OVER_AIR_INSTALLS_DIR/$target/tmp/$build_time_human/${App_name}.ipa" -outputDirectory="$OVER_AIR_INSTALLS_DIR/$target/$build_time_human" -webserver="${XCAB_WEB_ROOT}/${target}/$build_time_human"
				if [ $? -ne 0 ] ; then
					rm -rf "$OVER_AIR_INSTALLS_DIR/$target/tmp/$build_time_human/${App_name}.ipa"
					echo "BetaBuilder for iOS Apps Failed" >&2
					echo "$sha" > "$OVER_AIR_INSTALLS_DIR/$target/$build_time_human/sha.txt" #Don't try to build this again - it would fail over and over
					rm -rf "$OVER_AIR_INSTALLS_DIR/$target/tmp/$build_time_human/"
					exit 3
				fi
				
				#Save off the symbols, too
				if [ -d "${App_location}.dSYM" ] ; then
					tar czf "$OVER_AIR_INSTALLS_DIR/$target/$build_time_human/${App_name}.app.dSYM.tar.gz" "${App_location}.dSYM"
				fi

				if [ ! -z "$TESTFLIGHT_API_TOKEN" -a ! -z "$TESTFLIGHT_TEAM" ] ; then
					if [ ! -z "$TESTFLIGHT_DIST" ] ; then
						TESTFLIGHT_NOTIFY="-F notify=True  -F distribution_lists=\"$TESTFLIGHT_DIST\""
					else
						TESTFLIGHT_NOTIFY="-F notify=False"
					fi
					if [ -z "`echo $ignore_opts | grep -i testflight`" ] ; then
					  curl http://testflightapp.com/api/builds.json -F file=@"$OVER_AIR_INSTALLS_DIR/$target/$build_time_human/${App_name}.ipa"  -F api_token="$TESTFLIGHT_API_TOKEN" -F team_token="$TESTFLIGHT_TEAM" -F notes='New ${target} Build was uploaded via the upload API' $TESTFLIGHT_NOTIFY 
				  fi
				fi
				
				#Clean up temp dir
				rm -rf "$OVER_AIR_INSTALLS_DIR/$target/tmp/$build_time_human/${App_name}.ipa"
		
		    if [ -z "`echo $ignore_opts | grep -i rsync`" ] ; then
  				if [ ! -z "$RSYNC_USER" ] ; then
  					#If we're not using Dropbox's public web server, run rsync now
  					rsync -r "${OVER_AIR_INSTALLS_DIR} ${RSYNC_USER}@${XCAB_WEBSERVER_HOSTNAME}:${XCAB_WEBSERVER_XCAB_DIRECTORY_PATH}"
  				fi
  			fi
		
		    if [ -z "`echo $ignore_opts | grep -i notify`" ] ; then
		
  				wait_for_idle_dropbox
			
  				#Wait to make sure the file has appeared on the server
  				IPA_STATUS="`curl -sI -X HEAD \"${XCAB_WEB_ROOT}/${target}/$build_time_human/${App_name}.ipa\" | grep HTTP/1.1 | awk '{print $2}'`"
  				PLIST_STATUS="`curl -sI -X HEAD \"${XCAB_WEB_ROOT}/${target}/$build_time_human/manifest.plist\" | grep HTTP/1.1 | awk '{print $2}'`"
  				INDEX_STATUS="`curl -sI -X HEAD \"${XCAB_WEB_ROOT}/${target}/$build_time_human/index.html\" | grep HTTP/1.1 | awk '{print $2}'`"
  				RETRY_COUNT=0
  				while [ "$IPA_STATUS" != "200"  -o "$PLIST_STATUS" != "200"  -o "$INDEX_STATUS" != "200" ] ; do
  					#Wait and try again
  					sleep 15
  					IPA_STATUS="`curl -sI -X HEAD \"${XCAB_WEB_ROOT}/${target}/$build_time_human/${App_name}.ipa\" | grep HTTP/1.1 | awk '{print $2}'`"
  					PLIST_STATUS="`curl -sI -X HEAD \"${XCAB_WEB_ROOT}/${target}/$build_time_human/manifest.plist\" | grep HTTP/1.1 | awk '{print $2}'`"
  					INDEX_STATUS="`curl -sI -X HEAD \"${XCAB_WEB_ROOT}/${target}/$build_time_human/index.html\" | grep HTTP/1.1 | awk '{print $2}'`"
  					RETRY_COUNT="`expr $RETRY_COUNT + 1`"
  					if [ "$RETRY_COUNT" -gt 30 ] ; then
  						echo "Timeout waiting for web server to become ready" >&2
  						$my_dir/notify_with_boxcar.sh "notification[source_url]=${XCAB_WEB_ROOT}/$target/$build_time_human/index.html" "notification[message]=ERROR+Timeout+Waiting+For+Webserver+For+${target}+Build"
  						echo "$sha" > "$OVER_AIR_INSTALLS_DIR/$target/$build_time_human/sha.txt" #Don't try to build this again - it would generate timeouts over and over if the web server is down
							rm -rf "$OVER_AIR_INSTALLS_DIR/$target/tmp/$build_time_human/"
							exit 4
  					fi
  				done
			
  				#We're making the implicit assumption here that there aren't 
  				#  going to be a bunch of new changes per run
  				#   so it won't spam the user to notify for each one
  				#Notify with Boxcar
  				$my_dir/notify_with_boxcar.sh "notification[source_url]=${XCAB_WEB_ROOT}/$target/$build_time_human/index.html" "notification[message]=New+${target}+Build+available"
  		  fi
			else
				#Put in the permenant location
				cp "$OVER_AIR_INSTALLS_DIR/$target/tmp/$build_time_human/${App_name}.ipa" "$OVER_AIR_INSTALLS_DIR/$target/$build_time_human/${App_name}.ipa"
				
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
					if [ -z "`echo $ignore_opts | grep -i testflight`" ] ; then
  				  curl http://testflightapp.com/api/builds.json -F file=@"$OVER_AIR_INSTALLS_DIR/$target/$build_time_human/${App_name}.ipa"  -F api_token="$TESTFLIGHT_API_TOKEN" -F team_token="$TESTFLIGHT_TEAM" -F notes='New ${target} Build was uploaded via the upload API' $TESTFLIGHT_NOTIFY 
				  fi
				else
					echo "ipa saved to $OVER_AIR_INSTALLS_DIR/$target/$build_time_human/" >&2
					echo "but TestFlight credentials not defined and Beta Builder not installed (or web root not configured)" >&2
					echo "So it's not very useful, except maybe as a backup for your app builds.  Consider adding one of those services" >&2
				fi
				
			fi

			echo "$sha" > "$OVER_AIR_INSTALLS_DIR/$target/$build_time_human/sha.txt"
			rm -rf "$OVER_AIR_INSTALLS_DIR/$target/tmp/$build_time_human/"
		fi
	fi
done
