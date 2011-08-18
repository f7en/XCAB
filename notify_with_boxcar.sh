#!/bin/sh

my_dir="`dirname \"$0\"`"
cd "$my_dir"
if [ $? -ne 0 ] ; then
	echo "Could not cd to $my_dir" >&2
	exit 5
fi

. $my_dir/functions.sh

if [ -z "$BOXCAR_EMAIL" -o -z "$BOXCAR_PASSWORD" ] ; then
	echo "Undefined or incorrect Boxcar credentials, skipping notification." >&2
	exit 0
fi

#Need to get current project directory name and URL from the command line
if [ $# -lt 1 ] ; then
	echo "Usage: $0 <notification to post> [notification2  [notification3]]" >&2
	exit 3
fi

#This is hacky, so sue me.  
if [ $# -eq 1 ] ; then
	curl -d "$1" --user "${BOXCAR_EMAIL}:${BOXCAR_PASSWORD}" https://boxcar.io/notifications
elif [ $# -eq 2 ] ; then
	curl -d "$1"  -d "$2" --user "${BOXCAR_EMAIL}:${BOXCAR_PASSWORD}" https://boxcar.io/notifications
elif [ $# -eq 3 ] ; then
	curl -d "$1"  -d "$1"  -d "$2"  -d "$3" --user "${BOXCAR_EMAIL}:${BOXCAR_PASSWORD}" https://boxcar.io/notifications
fi
