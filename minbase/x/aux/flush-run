#!/bin/sh
# SPDX-License-Identifier: BSD-3-Clause
# (c) 2021-2022, Konstantin Demin

[ -z "${VERBOSE}" ] || set -xv

find /run -mindepth 1 ${VERBOSE:+-ls} -delete

set -e
cd /run

install -d -m 01777 \
	lock \
	screen \
	user \

exit 0
