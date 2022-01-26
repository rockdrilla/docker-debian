#!/bin/sh
# SPDX-License-Identifier: BSD-3-Clause
# (c) 2022, Konstantin Demin

set -ef

## go to directory where current script lands
w=$(dirname "$0") ; : "${w:?}" ; cd "$w"

export DEB_BUILD_OPTIONS='hardening=+all'
export DEB_CFLAGS_STRIP='-g'
export DEB_CFLAGS_APPEND='-g0'
export DEB_CPPFLAGS_APPEND='-Werror -Wall -Wextra -Wno-unused-parameter'
export DEB_LDFLAGS_APPEND='-s'

eval "$(dpkg-buildflags --export=sh)"

rm -f x0
(
	set -x
	gcc -o x0 x0.c ${CFLAGS} ${CPPFLAGS} ${LDFLAGS}
)
chmod 0755 x0
./x0
stat -c '%A %s %n' "${PWD}/x0"
