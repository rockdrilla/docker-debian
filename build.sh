#!/bin/sh
# SPDX-License-Identifier: BSD-3-Clause
# (c) 2021-2022, Konstantin Demin

set -f

dir0=$(dirname "$0")
dir0=$(readlink -f "${dir0}")

SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-$(date -u '+%s')}
export SOURCE_DATE_EPOCH

## set by env, e.g.:
##   export CI_REGISTRY='docker.io'
##   export CI_DIRECTORY='rockdrilla'
REG_PATH="${CI_REGISTRY:?}/${CI_DIRECTORY:?}"
REG="docker://${REG_PATH}"

## NB: assume that we're already logged in registry

## --- distro-info functions

distro_info() {
	"${dir0}/distro-info/wrapper.sh" "$@"
}

## --- image functions

jq_field() {
	jq -r "select(has(\"$1\")) | .\"$1\""
}

json_tarball_hash() {
	jq_field Labels | jq_field tarball.hash
}

tarball_hash_local() {
	podman inspect "$1" \
	| jq -r '.[]' \
	| json_tarball_hash
}

tarball_hash_remote() {
	skopeo inspect "${REG}/$1" \
	| json_tarball_hash
}

list_images() {
	podman images --format '{{.Id}}|{{.Repository}}|{{.Tag}}' \
	| grep -E -e "$1"
}

## $1 - image id
## $2 - image name with tag
image_push() {
	if [ "${IMAGE_PUSH}" = n ] ; then
		{
		cat <<-EOF

		going to push image:
		  id "$1"
		  ->
		  "${REG_PATH}/$2"
		BUT push is disabled by env IMAGE_PUSH=${IMAGE_PUSH}

		EOF
		} | sed -E 's/^(.+)$/ # \1/' 1>&2
	else
		podman push "$1" "${REG}/$2"
	fi
}

image_rm() {
	if [ "${IMAGE_RM}" = n ] ; then
		{
		cat <<-EOF

		going to remove image(s):
		EOF
		printf '%s\n' "$@" | sed -E 's/^/- /'
		cat <<-EOF
		BUT image removal is disabled by env IMAGE_RM=${IMAGE_RM}

		EOF
		} | sed -E 's/^(.+)$/ # \1/' 1>&2
	else
		podman image rm "$@"
	fi
}

## -- code itself

WORKDIR=$(mktemp -d)
cd "${WORKDIR}" || exit 1

for distro in debian ubuntu ; do
	distro_info "${distro}" > "${distro}.meta"

	suites=$(cut -d ' ' -f 1 < "${distro}.meta")
	for suite in ${suites} ; do
		"${dir0}/minbase/${distro}.sh" "${suite}"

		name_local="${distro}-minbase"
		name_remote=${name_local}
		if [ -n "${BASE_NAME_FMT}" ] ; then
			## unjustified credulity :D
			# shellcheck disable=SC2059
			name_remote=$(printf "${BASE_NAME_FMT}" "${distro}")
		fi

		list_images "\|[^|]+/${name_local}\|${suite}" > "${distro}.image"
		while IFS='|' read -r id path tag ; do
			hash_local=$(tarball_hash_local "${id}")

			tags=$(grep -E "^${suite}( |\$)" < "${distro}.meta")
			for t in ${tags} ; do
				push=0
				if [ -n "${FORCE_REBUILD}" ] ; then
					push=1
				else
					hash_remote=$(tarball_hash_remote "${name_remote}:$t")
					if [ "${hash_remote}" != "${hash_local}" ] ; then
						push=1
					fi
				fi

				if [ "${push}" = 0 ] ; then
					continue
				fi

				image_push "${id}" "${name_remote}:$t"
			done

			## early image cleanup
			image_rm "${path}:${tag}"
		done < "${distro}.image"
	done
done

cd /
rm -rf "${WORKDIR}"
