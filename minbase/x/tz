#!/bin/sh
# SPDX-License-Identifier: BSD-3-Clause
# (c) 2021-2022, Konstantin Demin

set -ef

[ -n "$1" ]

TZDIR=${TZDIR:-/usr/share/zoneinfo}

v=$1
v=${v#"${TZDIR}/"}

IFS=/ read -r area zone <<EOF
$v
EOF

[ -n "${area}" ]
[ -n "${zone}" ]

file="${TZDIR}/$v"

[ -f "${file}" ]
[ -s "${file}" ]

echo "$v" > /etc/timezone
ln -fs "${file}" /etc/localtime

debconf-set-selections <<-EOF
	tzdata  tzdata/Areas          select  ${area}
	tzdata  tzdata/Zones/${area}  select  ${zone}
EOF
