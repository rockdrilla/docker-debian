#!/bin/sh
# SPDX-License-Identifier: BSD-3-Clause
# (c) 2022, Konstantin Demin

t=$(mktemp) ; : "${t:?}"

( "$@" ; ) </dev/null > "$t" 2> "$t"
r=$?
if [ $r != 0 ] ; then
	printf '# command:' ; env printf ' %q' "$@" ; echo
	echo "# return code: $r"
	if [ -s "$t" ] ; then
		echo "# output:"
		sed -E 's/^(.+)$/#>| \1/;s/^$/#=|/' < "$t"
	fi
fi 1>&2

rm -f "$t"
exit $r
