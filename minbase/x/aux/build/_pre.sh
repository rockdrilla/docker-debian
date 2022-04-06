#!/bin/sh
# SPDX-License-Identifier: BSD-3-Clause
# (c) 2022, Konstantin Demin

: "${bin:=$(basename "$0")}"
: "${dst_dir:=/x/bin}"
: "${src_dir:=/x/aux/src/${bin}}"

if test_bin "${dst_dir}" ; then
	exit
fi

## temp directory
w=$(mktemp -d) ; : "${w:?}" ; cd "$w"

export DEB_BUILD_OPTIONS='hardening=+all'
export DEB_CFLAGS_STRIP='-g'
export DEB_CFLAGS_PREPEND='-g0'
export DEB_CPPFLAGS_PREPEND='-Werror -Wall -Wextra -Wno-unused-parameter'
export DEB_CPPFLAGS_APPEND="-I${src_dir}"
export DEB_LDFLAGS_PREPEND='-s'

eval "$(dpkg-buildflags --export=sh)"
