#!/bin/sh
# SPDX-License-Identifier: BSD-3-Clause
# (c) 2021-2022, Konstantin Demin

set -ef

[ $# -ne 0 ]

has_file=1
if ! command -v file >/dev/null ; then
	has_file=0
	/x/apt install file >/dev/null 2>&1
fi

ldd_out=$(mktemp)

for i ; do
	[ -n "$i" ] || continue

	if [ -f "$i" ] ; then
		printf '%s\0' "$i"
		continue
	fi
	if [ -d "$i" ] ; then
		find -L "$i/" -type f -print0
		continue
	fi
	echo "don't know how to handle '$i', skipping" 1>&2
done \
| sort -zuV \
| xargs -0 -r file -L -N -F '|' -p -S -P bytes=2048 \
| mawk -F '|' '{ if ($2 ~ "^ ?ELF ") print $1 ; }' \
| xargs -d '\n' -r ldd \
| grep -F '=>' \
| sed -E 's/^\s+//' \
| tr -s '\t' ' ' \
> "${ldd_out}"

ldd_notfound=$(mktemp)
grep -F ' => not found' \
< "${ldd_out}" \
| cut -d ' ' -f 1 \
| sort -uV \
> "${ldd_notfound}"

grep -Fv ' => not found' \
< "${ldd_out}" \
| mawk '{ NF-- ; print substr($0, index($0, $3)); }' \
| sort -uV \
| xargs -r dpkg-query -S \
| sed -E 's/^(.+): .*$/\1/' \
| sort -uV

rm "${ldd_out}"

if [ ${has_file} = 0 ] ; then
	/x/apt remove file >/dev/null 2>/dev/null
fi

ldd_unresolved=0
if [ -s "${ldd_notfound}" ] ; then
	ldd_unresolved=1

	exec 1>&2
	echo "unresolved dependencies:"
	sed -E 's/^/\t/' < "${ldd_notfound}"
fi

rm "${ldd_notfound}"

return ${ldd_unresolved}
