#!/bin/sh
# SPDX-License-Identifier: BSD-3-Clause
# (c) 2021-2022, Konstantin Demin

set -f

######################################################################
## script internals

## special magic with separator for sed "s" command
## char 027 (0x17) seems to be safe separator for sed "s" command;
## idea taken from Debian src:nginx/debian/dh_nginx
X=$(env printf '\027')

## $1 - match
## $2 - replacement
## $3 - flags (optional)
repl() { env printf "s${X}%s${X}%s${X}%s" "$1" "$2" "$3" ; }

##                  what          with   flag(s)
esc_dots=$(   repl  '\.'          '\\.'  g )
esc_qmarks=$( repl  '([^\]|^)\?'  '\1.'  g )

##                what                     with         flag(s)
esc_head=$( repl  '^\*{2}/'                '.+/'        g )
esc_tail=$( repl  '/\*{2}$'                '(/.+)?'     g )
esc_mid=$(  repl  '(/|^)\*{2}(/|$)'        '\1(.+\2)?'  g )
esc_any=$(  repl  '([^*]|^)\*{2}([^*]|$)'  '\1.+\2'     g )

esc_double_star="${esc_head};${esc_tail};${esc_mid};${esc_any}"

##               what                  with         flag(s)
esc_mid=$( repl  '(/|^)\*(/|$)'        '\1[^/]+\2'  g )
esc_any=$( repl  '([^*]|^)\*([^*]|$)'  '\1[^/]*\2'  g )

esc_single_star="${esc_mid};${esc_any}"

esc_stars="${esc_double_star};${esc_single_star}"

##                     what      with    flag(s)
dedup_slashes=$( repl  '//+'     '/'     g )
add_anchors=$(   repl  '^(.+)$'  '^\1$'  g )

## TODO: discover more cases

esc_all="${esc_dots};${esc_qmarks};${esc_stars};${dedup_slashes}"

rx_glob_esc() { printf '%s' "$1" | sed -E "${esc_all};" ; }

## set sail... or not :D
rx_glob_moor() { printf '%s' "$1" | sed -E "${add_anchors};" ; }

rx_glob() { printf '%s' "$1" | sed -E "${esc_all};${add_anchors};" ; }

test_regex() { sed -En "\\${X}$1${X}p" </dev/null ; }

######################################################################
## script itself

cfg_stanza='^(delete|keep)=(.+)$'

## internal methods
case "$1" in
--delete|--keep)
	## turn glob to regex and then into file list
	## (symlinks are listed too!)

	## $1 - action (delete / keep)
	## $2 - path glob (one argument!)

	## append / to TOPMOST_D if missing
	case "${TOPMOST_D}" in
	*/) ;;
	*) TOPMOST_D="${TOPMOST_D}/" ;;
	esac

	action="${1#--}"
	path_glob="$2"

	## prepend TOPMOST_D to path_glob if leading slash is missing
	case "${path_glob}" in
	/*) ;;
	*) path_glob="${TOPMOST_D}${path_glob}" ;;
	esac

	path_regex=$(rx_glob "${path_glob}")
	if ! test_regex "${path_regex}" ; then
		cat 1>&2 <<-EOF
		Bad regex was produced from glob:
		  directory: ${TOPMOST_D}
		  glob: $2
		  regex: ${path_regex}

		Please report this case to developers.
		EOF
		exit 1
	fi

	type_selector='! -type d'
	if [ "${XGLOB_DIRS}" = '1' ] ; then
		type_selector=''
	fi

	result=$(mktemp -p "${RESULT_D}/${action}")

	## sysroot_skiplist='^/(dev|proc|run|sys)$'
	find "${TOPMOST_D}" -regextype egrep \
	  -regex '^/(dev|proc|run|sys)$' -prune -o \
	  '(' \
	  -regex "${path_regex}" ${type_selector} -print \
	  ')' \
	> "${result}"

	exit 0
;;
esac

topmost="$1" ; shift

## work directory
w=$(mktemp -d) ; : "${w:?}"

## reformat rules like:
##   "delete={selector}" => "--delete\n{selector}\n"
##   "keep={selector}"   => "--keep\n{selector}\n"
{
	## deal with remaining arguments (if any)
	stdin_read=0
	files_read=0

	## process remaining arguments
	for i ; do
		## skip empty argument
		[ -n "$i" ] || continue

		case "$i" in
		-|/dev/stdin|/proc/self/fd/0)
			[ "${stdin_read}" = 1 ] && continue

			## little fixture
			i='-'

			stdin_read=1
			files_read=$(( files_read + 1 ))
		;;
		*)
			## we may skip non-regular files (this is acceptable IMO)
			[ -s "$i" ] || continue

			files_read=$(( files_read + 1 ))
		;;
		esac

		grep -E "${cfg_stanza}" "$i"
	done

	## if no files were read then try stdin as last resort
	if [ "${files_read}" = 0 ] ; then
		grep -E "${cfg_stanza}" -
	fi
} \
| sort -uV \
| sed -En '/'"${cfg_stanza}"'/{s//--\1\n\2/;p;}' \
> "$w/rules.script"

## nothing to filter at all
if ! [ -s "$w/rules.script" ] ; then
	rm -rf "$w"
	exit 0
fi

if [ -z "${NPROC}" ] ; then
	NPROC=$(nproc)
	NPROC=$(( NPROC + (NPROC + 1)/2 ))
fi

mkdir -p "$w/rules.d/keep" "$w/rules.d/delete"

## invoke internal method
TOPMOST_D="${topmost}" RESULT_D="$w/rules.d" \
xargs -d '\n' -n 2 -P "${NPROC}" "$0" \
< "$w/rules.script"

rm -f "$w/rules.script"

## merge results to "save list"
find "$w/rules.d/keep" -mindepth 1 -type f -exec cat '{}' '+' \
| sort -uV > "$w/keep"

## merge results to "remove list"
find "$w/rules.d/delete" -mindepth 1 -type f -exec cat '{}' '+' \
| sort -uV > "$w/delete"

rm -rf "$w/rules.d"

## nothing to filter at all (again)
if ! [ -s "$w/delete" ] ; then
	rm -rf "$w"
	exit 0
fi

## filter out files in "save list"
if [ -s "$w/keep" ]
then grep -Fxv -f "$w/keep"
else cat
fi < "$w/delete" > "$w/list"

rm -f "$w/keep" "$w/delete"

## nothing to filter at all (again?)
if ! [ -s "$w/list" ] ; then
	rm -rf "$w"
	exit 0
fi

## list files if required or remove them otherwise
if [ -n "${XGLOB_PIPE}" ] ; then
	cat
else
	xargs -d '\n' -r rm -rf
fi < "$w/list"

rm -rf "$w"
