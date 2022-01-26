#!/bin/sh
# SPDX-License-Identifier: BSD-3-Clause
# (c) 2022, Konstantin Demin

set -ef

## internal methods
case "$1" in
--begin)
	## begin "build session"
	shift

	w=$(mktemp -d) ; : "${w:?}"

	/opt/apt.sh list-installed > "$w/installed.0"
	/opt/apt.sh list-manual    > "$w/manual.0"

	if [ -z "$*" ] ; then
		echo 'nothing was selected as build-deps' 1>&2
	else
		if ! ( /opt/apt.sh ${BUILD_DEP_METHOD:-install} $* ; ) </dev/null 1>&2 ; then
			rm -rf "$w"
			exit 1
		fi

		/opt/apt.sh list-installed > "$w/installed.1"
		/opt/apt.sh list-manual    > "$w/manual.1"
	fi

	echo "$w"
	exit 0
;;
--end)
	## end "build session"
	shift

	w="$1"

	ok=
	while : ; do
		[ -d "$w" ]             || break
		[ -s "$w/installed.0" ] || break
		[ -s "$w/manual.0" ]    || break
		ok=1 ; break
	done
	if [ -z "${ok}" ] ; then
		echo 'wrong state!' 1>&2
		exit 1
	fi

	/opt/apt.sh list-installed > "$w/installed.2"
	/opt/apt.sh list-manual    > "$w/manual.2"

	set +e

	x="$w/installed.1"
	if ! [ -s "$x" ] ; then x="$w/installed.2" ; fi
	grep -Fxv -f "$w/installed.0" \
	"$x" \
	> "$w/installed.diff"

	x="$w/manual.1"
	if ! [ -s "$x" ] ; then x="$w/manual.0" ; fi
	grep -Fxv -f "$x" \
	"$w/manual.2" \
	> "$w/manual.diff"

	if [ -s "$w/manual.diff" ] ; then
		grep -Fxv -f "$w/manual.diff" \
		"$w/installed.diff"
	else
		cat "$w/installed.diff"
	fi \
	> "$w/pkg.remove"

	xargs -r /opt/apt.sh purge < "$w/pkg.remove" 1>&2

	rm -rf "$w"
	exit 0
;;
esac

w=$("$0" --begin ${BUILD_DEP})

set +e
"$@"
r=$?

"$0" --end "$w"

exit $r
