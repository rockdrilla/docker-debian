#!/bin/sh
# SPDX-License-Identifier: BSD-3-Clause
# (c) 2022, Konstantin Demin

: "${XROOT:=/x}"

: "${bin:=$(basename "$0")}"
: "${dst_dir:=${XROOT}/bin}"
: "${src_dir:=${XROOT}/aux/src/${bin}}"

if test_bin "${dst_dir}" ; then
	exit
fi

## temp directory
w=$(mktemp -d) ; : "${w:?}" ; cd "$w"

export DEB_BUILD_OPTIONS='hardening=+all'
export DEB_CFLAGS_STRIP='-g'
export DEB_CFLAGS_PREPEND='-g0'
export DEB_CPPFLAGS_PREPEND="-I${src_dir} -Werror -Wall -Wextra -Wno-unused-parameter -Wno-unused-function"
export DEB_LDFLAGS_PREPEND='-s'

eval "$(dpkg-buildflags --export=sh)"
