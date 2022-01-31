#!/bin/sh
# SPDX-License-Identifier: BSD-3-Clause
# (c) 2021-2022, Konstantin Demin

set -e

## mmdebstrap companion
tf=tarfilter
if ! command -v ${tf} >/dev/null ; then
	## try Debian one
	tf=mmtarfilter
	command -v ${tf} >/dev/null
fi

if [ -n "${TARBALL_ONLY}" ] ; then
	[ -n "$2" ]
	[ -w "$2" ] || touch "$2"
fi

if [ -n "${SOURCE_DATE_EPOCH}" ] ; then
	ts="${SOURCE_DATE_EPOCH}"
else
	ts=$(date -u '+%s')
	export SOURCE_DATE_EPOCH=${ts}
fi

dir0=$(dirname "$0")
dir0=$(readlink -f "${dir0}")
name0=$(basename "$0")

distro=$(echo "${name0}" | sed -E 's/\.[^.]+$//')
image="${distro}-minbase"

## resolve real file
name0=$(readlink -e "$0")
name0=$(basename "${name0}")

sha256() { sha256sum -b "$1" | sed -En '/^([[:xdigit:]]+).*$/{s//\L\1/;p;}' ; }

get_meta() { "${dir0}/../distro-info/simple-csv.sh" "$@" ; }
suite_from_meta() { cut -d ',' -f 1 | cut -d ' ' -f 1 ; }
meta=
suite=
case "${distro}" in
debian)
	suite=unstable
	meta=$(get_meta "${distro}" "${suite}")
	;;
ubuntu)
	meta=$(get_meta "${distro}" | tail -n 1)
	suite=$(echo "${meta}" | suite_from_meta)
	;;
esac
[ -n "${meta}" ]
[ -n "${suite}" ]

if [ "${distro}|$1" != "debian|${suite}" ] ; then
	if [ -n "$1" ] ; then
		x=$(get_meta "${distro}" "$1" | tail -n 1)
		y=$(echo "$x" | suite_from_meta)
		if [ -n "$x" ] ; then
			meta="$x"
			suite="$y"
		else
			echo "parameter '$1' looks spoiled, defaulting to '${suite}'" 1>&2
		fi
	fi
fi

reldate=$(echo "${meta}" | cut -d ',' -f 2)
reldate=$(date -u -d "${reldate}" '+%s')
export SOURCE_DATE_EPOCH=${reldate}

tag="${suite}-"$(date '+%Y%m%d%H%M%S' -d "@${ts}")

## hack for mmdebstrap and libpam-tmpdir:
## we need 'shared' /tmp not per-user one :)
orig_tmp="${TMPDIR}"
export TMPDIR=/tmp TEMPDIR=/tmp TMP=/tmp TEMP=/tmp

tarball=$(mktemp -u)'.tar'

uid=$(ps -n -o euid= -p $$)
gid=$(ps -n -o egid= -p $$)

comps=''
case "${distro}" in
debian) comps='main,contrib,non-free' ;;
ubuntu) comps='main,restricted,universe,multiverse' ;;
esac

mmdebstrap \
  --format=tar \
  --variant=apt \
 '--include=apt-utils,ca-certificates' \
  ${comps:+"--components=${comps}"} \
  --aptopt="${dir0}/setup/apt.conf" \
  --dpkgopt="${dir0}/setup/dpkg.cfg" \
  --customize-hook='chroot "$1" mkdir /x' \
  --customize-hook="sync-in '${dir0}/x' /x" \
  --customize-hook="sync-in '${dir0}/crt' /usr/local/share/ca-certificates" \
  --customize-hook="sync-in '${dir0}/opt' /opt" \
  --customize-hook="'${dir0}/setup/mmdebstrap.sh' \"\$1\" ${distro} ${suite} ${uid} ${gid}" \
  --skip=cleanup/apt \
  --skip=cleanup/tmp \
  "${suite}" "${tarball}" || true

## restore per-user /tmp (if any)
if [ -n "${orig_tmp}" ] ; then
	export TMP="${orig_tmp}"
	export TMPDIR="${TMP}" TEMPDIR="${TMP}" TEMP="${TMP}"
fi

if ! tar -tf "${tarball}" >/dev/null ; then
	rm -f "${tarball}"
	exit 1
fi

## filter out tarball
tarball_new=$(mktemp)
${tf} \
	--path-exclude='/dev/*' \
	--path-exclude='/proc/*' \
	--path-exclude='/sys/*' \
< "${tarball}" \
> "${tarball_new}"

if ! tar -tf "${tarball_new}" >/dev/null ; then
	rm -f "${tarball}" "${tarball_new}"
	exit 1
fi

rm -f "${tarball}"
tarball="${tarball_new}"
unset tarball_new

if [ -n "${TARBALL_ONLY}" ] ; then
	cat < "${tarball}" > "$2"
	rm -f "${tarball}"
	touch -m -d "@${ts}" "$2"
	exit
fi

tar_sha256=$(sha256 "${tarball}")

export BUILDAH_FORMAT=docker

c=$(buildah from scratch || true)
if [ -z "$c" ] ; then
	rm -f "${tarball}"
	exit 1
fi

buildah add "$c" "${tarball}" /
rm -f "${tarball}" ; unset tarball

f=$(printf 'bc() { buildah config "$@" %s ; }' "$c")
eval "$f" ; unset f

bc --hostname "${distro}"
bc --label "tarball.ts=${ts}"
bc --label "tarball.hash=${tar_sha256}"
bc --entrypoint '["/x/bin/dumb-init", "--"]'
bc --workingdir /work
bc --cmd /bin/sh

t_env=$(mktemp)
grep -Ev '^\s*(#|$)' < "${dir0}/env.sh" > "${t_env}"
while read -r L ; do bc --env "$L" ; done < "${t_env}"
rm -f "${t_env}"

buildah commit --squash --timestamp "${ts}" "$c" "${image}:${tag}" || true

buildah rm "$c"

echo "${image}:${tag} has been built successfully" 1>&2
