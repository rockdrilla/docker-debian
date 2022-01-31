#!/bin/sh
# SPDX-License-Identifier: BSD-3-Clause
# (c) 2021-2022, Konstantin Demin

if [ -z "${ZAP_WORKER}" ] ; then
	if [ -z "${NPROC}" ] ; then
		NPROC=$(nproc)
		NPROC=$(( NPROC + (NPROC + 1)/2 ))
	fi

	for i ; do
		for k in $i ; do
			printf '%s\n' "$k"
		done
	done \
	| sort -uV \
	| ZAP_WORKER=1 xargs -d '\n' -r -n 1 -P "${NPROC}" "$0"

	exit
fi

set -f

find_fast() {
	find "$@" -printf . -quit | grep -Fq .
}

for i ; do
	[ -d "$i" ] || continue

	if find_fast "$i" -mindepth 1 '!' -type d ; then
		ZAP=1 find "$i" -mindepth 1 -maxdepth 1 -type d -exec "$0" '{}' '+'

		[ "${ZAP}" != 1 ] && continue

		find_fast "$i" -mindepth 1 -maxdepth 1 || rmdir "$i"
	else
		if [ "${ZAP}" = 1 ] ; then
			rm -rf "$i"
		else
			find "$i" -mindepth 1 -maxdepth 1 -type d -exec rm -rf '{}' '+'
		fi
	fi
done
