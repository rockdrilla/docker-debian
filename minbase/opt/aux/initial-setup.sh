#!/bin/sh
# SPDX-License-Identifier: BSD-3-Clause
# (c) 2021-2022, Konstantin Demin

set -e

## auxiliary packages to be installed AND marked as 'manual'
## NB: don't remove "ca-certificates"
pkg_aux='apt-utils ca-certificates less lsof netbase ncurses-base procps psmisc tzdata vim-tiny'

## remove "keep" files (if any)
rm -f /usr/local/share/ca-certificates/.keep
find /opt /x -name .keep -type f -delete

_q() { /opt/quiet-if-ok.sh "$@" ; }

## $1 - path
## $2 - install symlink to another file (optional)
divert() {
	if ! [ -f "$1" ] ; then
		env printf "won't divert (missing): %q\\n" "$1" 1>&2
		return 0
	fi
	__suffix=$(dpkg-query --search "$1" || echo local)
	__suffix="${__suffix%%:*}"
	_q dpkg-divert --divert "$1.${__suffix}" --rename "$1"
	ln -s "${2:-/bin/true}" "$1"
}

find_fast() {
	find "$@" -printf . -quit | grep -Fq .
}

## update ca certificates (if necessary)
if find_fast -L /usr/local/share/ca-certificates -mindepth 1 -type f ; then
	update-ca-certificates
fi

## strip apt keyrings from sources.list:
sed -i -E 's/ \[[^]]+]//' /etc/apt/sources.list

## apt/dpkg/debconf related env:
export DEBCONF_NONINTERACTIVE_SEEN=true
export DEBIAN_FRONTEND=noninteractive
export DEBIAN_PRIORITY=critical
export TERM=linux

## debconf itself:
debconf-set-selections <<-EOF
	debconf  debconf/frontend  select  Noninteractive
	debconf  debconf/priority  select  critical
EOF

## prevent services from auto-starting, part 1
s='/usr/sbin/policy-rc.d'
## remove file
rm -f "$s"
## provide real script in another location
x='/usr/bin/policy-rc.d'
cat > "$x" <<-EOF
	#!/bin/sh
	exit 101
EOF
chmod 0755 "$x"
## install as symlink
ln -s "$x" "$s"
unset s x

## prevent services from auto-starting, part 2
b='/sbin/start-stop-daemon'
r="$b.REAL"
## undo mmdebstrap hack (if any)
if [ -f "$r" ] ; then mv -f "$r" "$b" ; fi
## rename via dpkg-divert and symlink to /bin/true
divert "$b"
unset b r

## always report that we're in chroot (oh God, who's still using ischroot?..)
divert /usr/bin/ischroot

## man-db:
debconf-set-selections <<-EOF
	man-db  man-db/auto-update     boolean  false
	man-db  man-db/install-setuid  boolean  false
EOF
rm -rf /var/lib/man-db/auto-update /var/cache/man

## hide systemd helpers
divert /usr/bin/deb-systemd-helper
divert /usr/bin/deb-systemd-invoke

## forced apt/dpkg cleanup
/opt/cleanup.d/apt-dpkg-related
## update package lists and install auxiliary packages
Q=1 /opt/apt.sh install ${pkg_aux}
## mark them as manual
_q apt-mark manual ${pkg_aux}

## install vim-tiny as variant for vim
vim=/usr/bin/vim
_q update-alternatives --install ${vim} vim ${vim}.tiny 1
## quirk for vim-tiny
find /usr/share/vim/ -name debian.vim \
| sed 's/debian.vim/defaults.vim/' \
| xargs -d '\n' -r touch

## timezone
[ -z "${TZ}" ] || /opt/tz.sh "${TZ}"

## build supplemental utilities

w=$(Q=1 /opt/build-dep.sh --begin curl dpkg-dev gcc libc6-dev)

## build dumb-init
/opt/aux/dumb-init.build.sh

## build su-exec
/opt/aux/su-exec.build.sh

## build own supplemental utility
/opt/aux/x0.build.sh

Q=1 /opt/build-dep.sh --end "$w"

## list packages with unusual state (if any)
/opt/apt.sh list-martians

## like '/workspace' in kaniko, but less letters to type :)
install -d -m 01777 /work
