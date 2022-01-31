#!/bin/sh
# SPDX-License-Identifier: BSD-3-Clause
# (c) 2021-2022, Konstantin Demin

## script parameters:
## $1 - chroot path
## $2 - distro name
## $3 - suite name
## $4 - uid
## $5 - gid

set -e

if [ -d "$1" ] ; then
	dir0=$(dirname "$0")

	## read environment from file (except PATH)
	f_env="${dir0}/../env.sh"
	t_env=$(mktemp)
	grep -Ev '^\s*(#|$)' < "${f_env}" > "${t_env}"
	while read -r L ; do
		case "$L" in
		PATH=*) ;;
		*) export "${L?}" ;;
		esac
	done < "${t_env}"
	rm -f "${t_env}"

	## copy self inside chroot
	c='/opt/mmdebstrap-setup.sh'
	cp "$0" "$1$c"

	## reexec within chroot
	chroot "$1" sh "$c" "$@"
	rm "$1$c"
	exit
fi

## remove docs (if any)
find /x -name '*.md' -type f -delete
find /opt -name '*.md' -type f -delete || :

## rename apt/dpkg configuration
mv /etc/apt/apt.conf.d/99mmdebstrap  /etc/apt/apt.conf.d/docker
mv /etc/dpkg/dpkg.cfg.d/99mmdebstrap /etc/dpkg/dpkg.cfg.d/docker

## generic configuration
. /x/aux/initial-setup.sh

## approach to minimize manually installed packages list
dpkg-query -W \
	-f='${db:Status-Abbrev}|${Essential}|${binary:Package}|${Version}\n' \
> /tmp/pkg.all

mawk -F '|' '{ if ($1 ~ "^[hi]i ") print $0;}' \
< /tmp/pkg.all \
> /tmp/pkg.good

mawk -F '|' '{ if ($2 == "yes") print $3;}' \
< /tmp/pkg.good \
| cut -d : -f 1 \
| sort -V \
> /tmp/pkg.essential

apt-mark showmanual \
| cut -d : -f 1 \
| sort -V \
> /tmp/pkg.manual

grep -Fvx -f /tmp/pkg.essential \
< /tmp/pkg.manual \
> /tmp/pkg.manual.regular

## apt is manually installed (by mmdebstrap but it doesn't matter)
## ${pkg_aux} is defined in /x/aux/initial-setup.sh to avoid duplication
echo apt ${pkg_aux} \
| tr ' ' '\n' \
| grep -Fvx -f - /tmp/pkg.manual.regular \
| xargs -r /x/quiet apt-mark auto

## fix ownership:
## mmdebstrap's actions 'sync-in' and 'copy-in' preserves source user/group
fix_ownership() {
	s="${1%%|*}" ; a="${1##*|}"
	## sysroot_skiplist='^/(dev|proc|run|sys)$'
	find / -regextype egrep \
	  -regex '^/(dev|proc|run|sys)$' -prune -o \
	  '(' \
	  $s -exec $a '{}' '+' \
	  ')'
}

[ "$4" = 0 ] || fix_ownership "-uid $4|chown -h 0"
[ "$5" = 0 ] || fix_ownership "-gid $5|chgrp -h 0"

## run cleanup
exec /x/cleanup
