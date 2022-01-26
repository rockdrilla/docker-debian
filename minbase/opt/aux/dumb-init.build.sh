#!/bin/sh
# SPDX-License-Identifier: BSD-3-Clause
# (c) 2022, Konstantin Demin

set -ef

## temp directory
w=$(mktemp -d) ; : "${w:?}" ; cd "$w"

export DEB_BUILD_OPTIONS='hardening=+all'
export DEB_CFLAGS_STRIP='-g'
export DEB_CFLAGS_APPEND='-g0'
export DEB_CPPFLAGS_APPEND='-Werror -Wall -Wextra -Wno-unused-parameter'
export DEB_LDFLAGS_APPEND='-s'

eval "$(dpkg-buildflags --export=sh)"

DUMB_INIT_VERSION='v1.2.5'
DUMB_INIT_URI="https://github.com/Yelp/dumb-init/raw/${DUMB_INIT_VERSION}"
DUMB_INIT_FILES='dumb-init.c VERSION.h'
for i in ${DUMB_INIT_FILES} ; do
	curl -sSL -o "$i" "${DUMB_INIT_URI}/$i"
done

(
	set -x
	gcc -o dumb-init dumb-init.c ${CFLAGS} ${CPPFLAGS} ${LDFLAGS}
)
chmod 0755 dumb-init
./dumb-init -V 2>/dev/null
cp -f dumb-init /
stat -c '%A %s %n' /dumb-init

cd /
rm -rf "$w"
