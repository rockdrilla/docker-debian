#!/bin/sh
# SPDX-License-Identifier: BSD-3-Clause
# (c) 2021-2022, Konstantin Demin

set -ef

export DEBCONF_NONINTERACTIVE_SEEN=true
export DEBIAN_FRONTEND=noninteractive
export DEBIAN_PRIORITY=critical
export TERM=linux

act=update
for i ; do
	case "$i" in
	-*) ;;
	*) act="$i" ; break ;;
	esac
done

## WIP:
## try guess whether better to use apt instead of aptitude
## or vice versa
flavour=apt
if [ -z "${WITH}" ] ; then
	case "${act}" in
	install|purge|reinstall|remove|search)
			## traverse arguments
			for i ; do
				case "$i" in
				## aptitude's flags
				-r|-R) flavour=aptitude ; break ;;
				## skip other flags
				-*) ;;
				## aptitude's selectors and modifiers
				*[?~\&]*) flavour=aptitude ; break ;;
				*+M)      flavour=aptitude ; break ;;
				*[-_=:])  flavour=aptitude ; break ;;
				esac
			done
	;;
	esac
fi
## honour provided flavour value
flavour="${WITH:-$flavour}"
## except for these
case "${act}" in
## apt only
autoremove|download|satisfy|update|upgrade)
	flavour=apt
;;
## aptitude only
autoclean|build-dep|build-depends|forbid-version|forget-new|hold|keep-all|markauto|safe-upgrade|unhold|unmarkauto)
	flavour=aptitude
;;
## builtin actions
install-aptitude)
	flavour=aptitude
;;
install-*|list-*)
	flavour=apt
;;
esac
## sanity check
case "${flavour}" in
apt|aptitude) ;;
*)
	env printf "%q: unknown backend: %q\\n" "$0" "${flavour}" 1>&2
	exit 1
;;
esac

## make script quiet as possible/desired
_q() { /opt/quiet-if-ok.sh "$@" ; }
_cq=
if [ -n "$Q" ] ; then _cq=_q ; fi

find_fresh_ts() {
	{
		find "$@" -exec stat -c '%Y' '{}' '+' 2>/dev/null || :
		## duck and cover
		echo 1
	} | sort -rn | head -n 1
}

apt_update() {
	## update package lists; may fail sometimes,
	## e.g. soon-to-release channels like Debian "bullseye" @ 22.04.2021
	if [ $# = 0 ] ; then
		## (wannabe) smart package list update
		ts_sources=$(find_fresh_ts /etc/apt -name '*.list' -type f)
		ts_lists=$(find_fresh_ts /var/lib/apt/lists/ -maxdepth 1 -name '*_Packages' -type f)
		if [ ${ts_sources} -gt ${ts_lists} ] ; then
			_q apt -qq -y update
		fi
	else
		${_cq} apt "$@"
	fi
}

apt_dpkg_avail_hack() {
	release=$( ( . /etc/os-release ; echo "${VERSION_CODENAME}" ; ) )
	dpkg_avail='/var/lib/dpkg/available'
	## if ${release} is empty then we're on Debian sid or so :)
	case "${release}" in
	stretch|buster|bionic|focal)
		## ref: https://unix.stackexchange.com/a/271387/49297
		if [ -s "${dpkg_avail}" ] ; then
			return
		fi
		_q /usr/lib/dpkg/methods/apt/update /var/lib/dpkg apt apt
	;;
	*)
		touch "${dpkg_avail}"
	;;
	esac
}

apt_install_aptitude() {
	if command -v aptitude >/dev/null ; then
		return 0
	fi

	_q apt -qq -y install aptitude
}

dpkg_list_installed() {
	dpkg-query -W \
		-f='${binary:Package}:${Architecture}|${db:Status-Abbrev}\n' \
	| mawk -F '|' '{ if ($2 ~ "^[hi]i ") print $1;}' \
	| cut -d : -f 1-2 \
	| sort -V
}

dpkg_list_martians() {
	dpkg-query -W \
	    -f='${binary:Package} ${Version}|${db:Status-Abbrev}\n' \
	| mawk -F '|' '{ if ($2 != "ii ") print $1 ", state=\"" $2 "\"" ; }' \
	| sort -V \
	| sed -E '1i \## "martian" packages (unusual state):'
}

apt_list_auto() {
	w=$(mktemp -d) ; : "${w:?}"

	mawk '
	/^Package:/,/^$/ {
	    if ($1 == "Package:")        { pkg = $2; }
	    if ($1 == "Architecture:")   { arch = $2; }
	    if ($1 == "Auto-Installed:") { is_auto = $2; }
	    if ($0 == "") {
	        if (is_auto == 1) { print pkg":"arch; }
	    }
	}
	' /var/lib/apt/extended_states \
	| sort -V \
	> "$w/auto"

	## fix:
	## /var/lib/apt/extended_states stores (some) arch:all entries as arch:native
	dpkg_list_installed \
	| grep -F ':all' \
	| cut -d : -f 1 \
	| xargs -r printf '/^(%s):.+$/{s//\\1:all/}\n' \
	> "$w/auto.sed"
	sed -E -f "$w/auto.sed" "$w/auto"

	rm -rf "$w"
}

apt_list_manual() {
	w=$(mktemp -d) ; : "${w:?}"

	dpkg_list_installed > "$w/all"
	"$0" list-auto > "$w/auto"

	grep -Fxv -f "$w/auto" \
	"$w/all"

	rm -rf "$w"
}

case "${act}" in
install|upgrade|safe-upgrade|full-upgrade)
	apt_update
;;
esac

if [ "${flavour}" = aptitude ] ; then
	apt_update
	apt_dpkg_avail_hack
	apt_install_aptitude
fi

case "${act}" in
list-installed)
	dpkg_list_installed
;;
list-martians)
	dpkg_list_martians
;;
list-auto)
	apt_list_auto
;;
list-manual)
	apt_list_manual
;;
install-aptitude)
;;
list-*|install-*)
	env printf "unknown action: %q" "${act}" 1>&2
	exit 1
;;
update)
	apt_update "$@"
;;
*)
	case "${flavour}" in
	apt)
		${_cq} apt -qq -y "$@"
	;;
	aptitude)
		${_cq} aptitude -y "$@"
	;;
	esac
;;
esac
