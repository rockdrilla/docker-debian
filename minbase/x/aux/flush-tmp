#!/bin/sh
# SPDX-License-Identifier: BSD-3-Clause
# (c) 2021-2022, Konstantin Demin

[ -z "${VERBOSE}" ] || set -xv

find /tmp -mindepth 1 ${VERBOSE:+-ls} -delete

set -e
cd /tmp

install -d -m 01777 \
	.ICE-unix \
	.Test-unix \
	.X11-unix \
	.XIM-unix \
	.font-unix \

exit 0
