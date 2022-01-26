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

SU_EXEC_VERSION='212b75144bbc06722fbd7661f651390dc47a43d1'
SU_EXEC_URI="https://github.com/ncopa/su-exec/raw/${SU_EXEC_VERSION}"
SU_EXEC_FILES='su-exec.c'
for i in ${SU_EXEC_FILES} ; do
	curl -sSL -o "$i" "${SU_EXEC_URI}/$i"
done

(
	set -x
	gcc -o su-exec su-exec.c ${CFLAGS} ${CPPFLAGS} ${LDFLAGS}
)
chmod 0755 su-exec
./su-exec >/dev/null
cp -f su-exec /usr/local/bin/
stat -c '%A %s %n' /usr/local/bin/su-exec

cd /
rm -rf "$w"
