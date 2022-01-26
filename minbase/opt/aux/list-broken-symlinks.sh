#!/bin/sh
# SPDX-License-Identifier: BSD-3-Clause
# (c) 2022, Konstantin Demin

[ -z "${VERBOSE}" ] || set -xv

## list broken symlinks (if any)
{
	## sysroot_skiplist='^/(dev|proc|run|sys)$'
	find -L / -regextype egrep \
	  -regex '^/(dev|proc|run|sys)$' -prune -o \
	  '(' \
	  -type l -print \
	  ')'
} \
| sort -V \
| sed -E '1i \## broken symlinks:' 1>&2

exit 0
