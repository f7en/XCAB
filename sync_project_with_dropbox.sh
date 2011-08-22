#!/bin/sh

my_dir="`dirname \"$0\"`"
cd "$my_dir"
if [ $? -ne 0 ] ; then
	echo "Could not cd to $my_dir" >&2
	exit 5
fi

. $my_dir/functions.sh

#Need to get current project directory name and URL from the command line
if [ $# -ne 2 ] ; then
	echo "Usage: $0 <Project Name> <Project URL>" >&2
	exit 3
fi

src_dir="$1"
origin_url="$2"

if [ -z "$SCM_WORKING_DIR" -o ! -d "$SCM_WORKING_DIR" ] ; then
	echo "Undefined or incorrect SCM_WORKING_DIR variable.  Please check your XCAB.settings file or environment" >&2
	exit 3
fi

#If we don't have a copy of this project in our SCM Working Dir, check it out
if [ ! -d "${SCM_WORKING_DIR}/$src_dir" ] ; then
	echo "Checking out into working dir"
	cd "${SCM_WORKING_DIR}"
	git clone $origin_url $src_dir
fi

#Get the latest updates from source control
cd "${SCM_WORKING_DIR}/$src_dir"
git fetch >/dev/null 2>&1

#If this project doesn't have a corresponding folder in Dropbox, make one
if [ ! -d "${XCAB_HOME}/$src_dir" ] ; then
	mkdir "${XCAB_HOME}/$src_dir"
	#Generate the list of available branches so the user can find them by looking at Dropbox - 
	# sort these so the local branches go first, and then are sorted by branch name
	git branch -a | sed -e 's/^..//' -e 's/ ->.*$//' -e 's,^remotes/,,' | grep -v '/HEAD$' | sort -t / -k 2 -k 1 -k 3 > "${SCM_WORKING_DIR}/${src_dir}_branches.txt"
	git tag -l | sort > "${SCM_WORKING_DIR}/${src_dir}_tags.txt"
	#Let the user know their branches list is up to date now
	$my_dir/notify_with_boxcar.sh  "notification[message]=New+${src_dir}+Project+${entry}+Directory+Added+To+Dropbox"
else
	#Update the list of available tags so the user can find them by looking at Dropbox - 
	git branch -a | sed -e 's/^..//' -e 's/ ->.*$//' -e 's,^remotes/,,' | grep -v '/HEAD$' | sort -t / -k 2 -k 1 -k 3 > "${SCM_WORKING_DIR}/${src_dir}_branches.txt"
	git tag -l | sort > "${SCM_WORKING_DIR}/${src_dir}_tags.txt"
fi

#Generate the list of available projects so the user can find them by looking at Dropbox - 
find . -name \*.xcodeproj -print | sort -u > "${SCM_WORKING_DIR}/${src_dir}_projects.txt"

if [ -s "${SCM_WORKING_DIR}/${src_dir}_projects.txt" ] ; then
	#Generate the list of available targets from all the projects we found so the user can find them by looking at Dropbox - 
	rm "${SCM_WORKING_DIR}/${src_dir}_targets_unsorted.txt"
	touch "${SCM_WORKING_DIR}/${src_dir}_targets_unsorted.txt"
	for project_munged in `sed -e 's/ /___space___/g' "${SCM_WORKING_DIR}/${src_dir}_projects.txt"`; do
		#restore the spaces if there are any
		project="`echo $project_munged | sed -e 's/___space___/ /g'`"
		xcodebuild -list -project "$project"| awk '$1=="Targets:",$1==""' | grep -v "Targets:" | grep -v "^$" | sed -e 's/^  *//' >> "${SCM_WORKING_DIR}/${src_dir}_targets_unsorted.txt"
	done
	sort -u "${SCM_WORKING_DIR}/${src_dir}_targets_unsorted.txt" > "${SCM_WORKING_DIR}/${src_dir}_targets.txt"
fi

#Only stick it in Dropbox if it's changed.  No reason to make Dropbox upload an identical file again
diff "${SCM_WORKING_DIR}/${src_dir}_targets.txt" "${XCAB_HOME}/$src_dir/targets.txt"  >/dev/null 2>&1
if [ $? -ne 0 ] ; then
	cp "${SCM_WORKING_DIR}/${src_dir}_targets.txt" "${XCAB_HOME}/$src_dir/targets.txt"
fi
diff "${SCM_WORKING_DIR}/${src_dir}_projects.txt" "${XCAB_HOME}/$src_dir/projects.txt"  >/dev/null 2>&1
if [ $? -ne 0 ] ; then
	cp "${SCM_WORKING_DIR}/${src_dir}_projects.txt" "${XCAB_HOME}/$src_dir/projects.txt"
fi
diff "${SCM_WORKING_DIR}/${src_dir}_branches.txt" "${XCAB_HOME}/$src_dir/branches.txt" >/dev/null 2>&1
if [ $? -ne 0 ] ; then
	cp "${SCM_WORKING_DIR}/${src_dir}_branches.txt" "${XCAB_HOME}/$src_dir/branches.txt"
fi
diff "${SCM_WORKING_DIR}/${src_dir}_tags.txt" "${XCAB_HOME}/$src_dir/tags.txt"  >/dev/null 2>&1
if [ $? -ne 0 ] ; then
	cp "${SCM_WORKING_DIR}/${src_dir}_tags.txt" "${XCAB_HOME}/$src_dir/tags.txt"
fi
	
cd "${XCAB_HOME}/$src_dir"

for entry in * ; do
	active_branch=""
	GIT_DIR="${SCM_WORKING_DIR}/$src_dir/.git"
	export GIT_DIR
	
	if [ -d "$entry" ] ; then
		#This is a directory - we need to decide if we need to do anything with this
		cd "${XCAB_HOME}/$src_dir/$entry"
		item_count="`ls -1 | wc -l | sed -e 's/[^0-9]//g'`"
		
		if [ "$item_count" == "0" ] ; then
			#Empty directory, need to check the correct branch out into it
			
			cd "${XCAB_HOME}/$src_dir"
			rm -rf tmp_checkout_dir
			mv $entry tmp_checkout_dir
			cd tmp_checkout_dir				
			
			#Now we need to figure out the right branch
			#First check to see if entry is already a valid reference 
			git rev-parse $entry > /dev/null 2>&1
			if [ $? -eq 0 ] ; then
				#Branch already exists, this is the one we want
				active_branch="$entry"
			else
				git rev-parse "origin/$entry" > /dev/null 2>&1
				if [ $? -eq 0 ] ; then
					#Branch exists, but is remote
					active_branch="$entry"
					echo "Creating Local branch '$entry' from remote branch 'origin/$entry'"
					git branch "$entry" "origin/$entry"
				else 
					#directory doesn't match an existing branch
					for potential_branch in `grep -v '/' "${XCAB_HOME}/$src_dir/branches.txt"`; do
						substring_match=`echo $entry | grep "^$potential_branch"`
						if [ x"$substring_match" != "x" ] ; then
							active_branch=$potential_branch
						fi
					done
					if [ x"$active_branch" != "x" ] ; then
						git branch "$entry" "$active_branch"
						active_branch="$entry"
					else
						#Do the same thing with remote branches
						for potential_branch in `grep '/' "${XCAB_HOME}/$src_dir/branches.txt"`; do
							localized_potential_branch="`echo $potential_branch | sed -e 's,^[^/]*/,,'`"
							substring_match=`echo $entry | grep "^$localized_potential_branch"`
							if [ x"$substring_match" != "x" ] ; then
								active_branch=$potential_branch
							fi
						done
						if [ x"$active_branch" != "x" ] ; then
							git branch "$entry" "$active_branch"
							active_branch="$entry"
						fi
					fi
				fi
			fi
			if [ x"$active_branch" == "x" ] ; then
				echo "Could not figure out an active branch - using master"
				git branch "$entry" master
				active_branch="$entry"
			fi
			git checkout -f $active_branch
			git reset --hard $active_branch
			cd ..
			
			wait_for_idle_dropbox
			
			mv tmp_checkout_dir "$entry"
			cd "$entry"

			wait_for_idle_dropbox
			#Let the user know that we have filled their new directory
			$my_dir/notify_with_boxcar.sh "notification[message]=New+${src_dir}+Branch+${entry}+Checked+Out+To+Dropbox"
			
			#Record what we put into Dropbox so if the repo advances, we know the differences aren't the user updating dropbox
			our_sha="`git rev-parse HEAD`"
			echo "$our_sha" > "${XCAB_HOME}/$src_dir/last_checkout_sha_${entry}.txt"
			
			git branch -a | sed -e 's/^..//' -e 's/ ->.*$//' -e 's,^remotes/,,' | sort -t / -k 2 -k 1 -k 3 > "${XCAB_HOME}/$src_dir/branches.txt"
		else
			#This directory has files in it, see if any of them have changed
			our_status="`git status | grep 'nothing to commit'`"
			if [ x"$our_status" == "x" ] ; then
				#Something has changed. See if this tree has been checked in from Dropbox already.
				#	if so, the branch was advanced on the repo, and we need to update Dropbox to match the repo
				#	if this tree hasn't been checked in, then we check in the state of Dropbox
				last_sha="`cat \"${XCAB_HOME}/$src_dir/last_checkout_sha_${entry}.txt\"`"
				our_diff="`git diff $last_sha 2>&1`"
				if [ -z "$our_diff" ]; then
					#These files have been checked in, but don't match the current HEAD, so update them to current HEAD
					cd "${XCAB_HOME}/$src_dir"
					rm -rf tmp_checkout_dir
					mv $entry tmp_checkout_dir
					cd tmp_checkout_dir				
					
					git reset --hard HEAD
					cd ..
					
					wait_for_idle_dropbox

					mv tmp_checkout_dir "$entry"
					cd "$entry"

					#Record what we put into Dropbox so if the repo advances, we know the differences aren't the user updating dropbox
					our_sha="`git rev-parse HEAD`"
					echo "$our_sha" > "${XCAB_HOME}/$src_dir/last_checkout_sha_${entry}.txt"
					
					
				else
					#Something changed and this hasn't been checked in before, check it in
					git checkout "$entry"
					#Skip comments if they aren't preceded by whitespace (so we don't consider URLs comments)
					#Strip out comment characters in comments
					#Squish whitespace in comments and remove newlines/non-printables
					comment="`git diff | grep '^\+[^+]' | sed -e 's/^\+//' | egrep '^[ 	]*(#|//|/\*|\*/)' | sed -e 's/^[ 	]*#//' | sed -e 's,^[ 	]*/[\*/],,'`"
					git add .
					#TODO: Make comment understand other comment styles like in between /* */ or # only for other languages
					if [ x"$comment" == "x" ] ; then
						comment="Checked in from Dropbox on `date`"
					fi
					git commit -a -m "$comment"
					
					#Record what we checked in from Dropbox so if the repo advances, we know the differences aren't the user updating dropbox
					our_sha="`git rev-parse HEAD`"
					echo "$our_sha" > "${XCAB_HOME}/$src_dir/last_checkout_sha_${entry}.txt"
					#Check to see if we have a writeable origin
					#  Grab the push origin url and check to see if it starts with 
					#    ssh:// or a username-looking-string folowed by an @ sign
					origin_path="`git remote -v | grep origin | grep push | awk '$1=="origin" && $3=="(push)" {print $2}' | egrep '^(ssh://|file://|[A-Za-z0-9][A-Za-z0-9]*@)'`"
					
					if [ -s "$origin_path" ] ; then
						git push origin ${entry}
					fi
				fi
			fi
		fi
	fi
	unset GIT_DIR
	cd "${XCAB_HOME}/$src_dir"
done 
