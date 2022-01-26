#!/bin/sh
# SPDX-License-Identifier: BSD-3-Clause
# (c) 2022, Konstantin Demin

set -ef

_printf() { env printf "$@" ; }
_msg() {  _printf "$0: ${__PRINTF_FMT}\n" "$@" 1>&2 ; }
msg() {
	export __PRINTF_FMT="$1" ; shift
	_msg "$@"
}

if ! command -v setpriv >/dev/null ; then
	msg "system warning: \`setpriv' is missing, running with \`su-exec'"
	exec su-exec "$@"
fi

is_option() {
	case "$1" in
	-d|--dump|-h|--help|--list-caps|-V|--version)
	;;
	--clear-groups|--init-groups|--keep-groups|--no-new-privs|--reset-env)
	;;
	--ambient-caps=*|--apparmor-profile=*|--bounding-set=*|--egid=*|--euid=*|--groups=*|--inh-caps=*|--pdeathsig=*|--regid=*|--reuid=*|--rgid=*|--ruid=*|--securebits=*|--selinux-label=*)
	;;
	--ambient-caps|--apparmor-profile|--bounding-set|--egid|--euid|--groups|--inh-caps|--pdeathsig|--regid|--reuid|--rgid|--ruid|--securebits|--selinux-label)
	;;
	*)
		return 1
	;;
	esac
	return 0
}

option_has_arg() {
	case "$1" in
	--ambient-caps|--apparmor-profile|--bounding-set|--egid|--euid|--groups|--inh-caps|--pdeathsig|--regid|--reuid|--rgid|--ruid|--securebits|--selinux-label)
		return 0
	;;
	esac
	return 1
}

is_id() {
	echo "$1" | grep -Eq '^(0|[1-9][0-9]*)$'
}

etcfile_has() {
	grep -Fxq "$2" <<-EOF
	$(cut -d : -f "$1" "$3")
	EOF
}

etcfile_get() {
	## mawk -F : "{ if (\$$1 == \"$2\") { print \$$3; } }" "$4"
	while read -r __n ; do
		[ -n "${__n}" ] || continue
		mawk -F : "NR==${__n} { print \$$3; }" "$4"
	done <<-EOF
	$(cut -d : -f "$1" "$4" | grep -Fxn "$2" | cut -d : -f 1)
	EOF
}

etc_passwd_has() { etcfile_has "$1" "$2" /etc/passwd ; }
etc_passwd_get() { etcfile_get "$1" "$2" "$3" /etc/passwd ; }
etc_group_has()  { etcfile_has "$1" "$2" /etc/group ; }
etc_group_get()  { etcfile_get "$1" "$2" "$3" /etc/group ; }

has_user()  { etc_passwd_has 1 "$1" ; }
has_uid()   { etc_passwd_has 3 "$1" ; }
has_group() { etc_group_has 1 "$1" ; }
has_gid()   { etc_group_has 3 "$1" ; }

get_name_by_uid()  { etc_passwd_get 3 "$1" 1 ; }
get_gid_by_user()  { etc_passwd_get 1 "$1" 4 ; }
get_home_by_user() { etc_passwd_get 1 "$1" 6 ; }

## dry run:
## (fast) verify options
## handle '--dump', '--help', '--list-caps' and '--version'
skip_arg=
for i ; do
	if [ -n "${skip_arg}" ] ; then
		skip_arg=
		continue
	fi

	case "$i" in
	-d|--dump|-h|--help|--list-caps|-V|--version)
		exec setpriv "$i"
		exit 127
	;;
	esac

	if is_option "$i" ; then
		if option_has_arg "$i" ; then
			skip_arg=1
		fi
		continue
	fi

	case "$i" in
	--) break ;;
	-*)
		msg "options error: unrecognized option %q" "$i"
		exit 1
	;;
	*) break ;;
	esac
done

## begin work

w=$(mktemp -d) ; : "${w:?}"

touch "$w/opt.pre"
touch "$w/opt.post"
touch "$w/param.pre"
touch "$w/param.post"

## options
o_spec=
o_groups=
o_caps=
o_env=

## counters
c_arg=0
c_param=0

## parse all options and arguments
o_arg=
a_act=
want_spec=
want_param=
for i ; do
	if [ -n "${want_spec}" ] ; then
		want_spec=
		want_param=1
		o_spec="$i"
		continue
	fi

	if [ -n "${want_param}" ] ; then
		if [ ${c_param} = 0 ] ; then
			case "$i" in
			-*)
				msg "parameter warning: parameter %q looks like option" "$i"
			;;
			esac
		fi
		c_param=$(( c_param + 1 ))
		printf '%s\0' "$i" >> "$w/param.post"
		continue
	fi

	if [ -n "${o_arg}" ] ; then
		case "${a_act}" in
		keep)
			case "$i" in
			--*)
				msg "option %q: argument %q looks like option but will be passed anyway" "${o_arg}" "$i"
			;;
			esac

			case "${o_arg}" in
			--clear-groups|--init-groups|--keep-groups)
				o_groups=1
			;;
			--ambient-caps|--bounding-set|--inh-caps)
				o_caps=1
			;;
			esac

			c_arg=$(( c_arg + 1 ))
			printf '%s\0' "$i" >> "$w/opt.post"
		;;
		skip) ;;
		*)
			msg "option %q: argument action '%q' will be handled as 'skip'" "${o_arg}" "${a_act}"
		;;
		esac
		o_arg=
		a_act=
		continue
	fi

	## handle offending options
	o_offend=
	case "$i" in
	--egid=*|--regid=*|--rgid=*)
		o_offend=group
	;;
	--egid|--regid|--rgid)
		o_offend=group
		o_arg="$i"
		a_act=skip
	;;
	--euid=*|--reuid=*|--ruid=*)
		o_offend=user
	;;
	--euid|--reuid|--ruid)
		o_offend=user
		o_arg="$i"
		a_act=skip
	;;
	esac
	if [ -n "${o_offend}" ] ; then
		msg "options warning: ignoring offending option %q" "${o_offend}"
		msg "use classic behavior or call \`setpriv' directly."
		continue
	fi

	## handle rest options
	if is_option "$i" ; then
		if option_has_arg "$i" ; then
			o_arg="$i"
			a_act=keep
		fi

		case "$i" in
		--reset-env)
			o_env=1
		;;
		--clear-groups=*|--init-groups=*|--keep-groups=*)
			o_groups=1
		;;
		--clear-groups|--init-groups|--keep-groups)
			o_groups=1
		;;
		--ambient-caps=*|--bounding-set=*|--inh-caps=*)
			o_caps=1
		;;
		--ambient-caps|--bounding-set|--inh-caps)
			o_caps=1
		;;
		esac

	else
		case "$i" in
		--)
			want_spec=1
			continue
		;;
		*)
			want_spec=1
		;;
		esac
	fi

	if [ -n "${want_spec}" ] ; then
		want_spec=
		want_param=1
		o_spec="$i"
		continue
	fi

	c_arg=$(( c_arg + 1 ))
	printf '%s\0' "$i" >> "$w/opt.post"
done

## sanity check
if [ -n "${o_arg}" ] ; then
	msg "options error: expected but missing value for option %q" "${o_arg}"
	rm -rf "$w"
	exit 1
fi

## normalize spec
o_spec_real="${o_spec}"
o_spec=$(echo "${o_spec}" | sed -E 's/::+/:/g;s/^:+//;s/:$//;')

if [ -z "${o_spec}" ] ; then
	msg "'user:group' spec error: expected but empty."
	msg "  original spec: %q" "${o_spec_real}"
	rm -rf "$w"
	exit 1
fi

user=
group=

IFS=':' read -r user group xtra <<-EOF
${o_spec}
EOF

if [ -n "${xtra}" ] ; then
	msg "'user:group' spec warning: extra data: %q" "${xtra}"
	msg "  original spec: %q" "${o_spec_real}"
fi

if [ -z "${user}" ] ; then
	msg "'user:group' spec error: 'user' expected but empty."
	msg "report this bug to developer ASAP."
	rm -rf "$w"
	exit 1
fi

if has_user "${user}" || has_uid "${user}" || is_id "${user}" ; then
	printf '%s\0' "--reuid=${user}" >> "$w/opt.pre"
else
	msg "'user:group' spec error: 'user' is malformed - not exist nor numeric."
	msg "  original spec: %q" "${o_spec_real}"
	rm -rf "$w"
	exit 1
fi

if has_uid "${user}" ; then
	user=$(get_name_by_uid "${user}")
fi

if [ -z "${group}" ] ; then
	if has_user "${user}" ; then
		group=$(get_gid_by_user "${user}")
	else
		group=nogroup
	fi
	printf '%s\0' "--regid=${group}" >> "$w/opt.pre"

	if [ -z "${o_groups}" ] ; then
		if has_user "${user}" ; then
			printf '%s\0' "--init-groups" >> "$w/opt.pre"
		else
			printf '%s\0' "--clear-groups" >> "$w/opt.pre"
		fi
	fi
else
	if has_group "${group}" || has_gid "${group}" || is_id "${group}" ; then
		printf '%s\0' "--regid=${group}" >> "$w/opt.pre"

		if [ -z "${o_groups}" ] ; then
			printf '%s\0' "--clear-groups" >> "$w/opt.pre"
		fi
	else
		msg "'user:group' spec error: 'group' is malformed - not exist nor numeric."
		msg "  original spec: %q" "${o_spec_real}"
		rm -rf "$w"
		exit 1
	fi
fi

if [ -z "${o_caps}" ] ; then
	printf '%s\0' "--inh-caps=-all" >> "$w/opt.pre"
fi

## aggregate options
{
	cat "$w/opt.pre" "$w/opt.post"
	printf '%s\0' '--'
} > "$w/opt"
rm "$w/opt.pre" "$w/opt.post"

## handle working directory
homedir='/work'
username='__non_existent_user__'
if has_user "${user}" ; then
	username="${user}"
	homedir=$(get_home_by_user "${user}")
fi

cwd=
for i in "${PWD}" "${homedir}" /work / ; do
	[ -d "$i" ] || continue

	{
		cat "$w/opt"
		printf '%s\0' test -r "$i"
	} > "$w/cmd.test"

	if xargs -0 -r setpriv < "$w/cmd.test" ; then
		if [ "$i" != "${PWD}" ] ; then
			msg "working directory: will be changed to %q" "$i"
		fi

		cwd="$i"
		break
	else
		msg "working directory: warning: user %q can't access %q" "${user}" "$i"
	fi
done
if [ -z "${cwd}" ] ; then
	msg "working directory: error: unable to find appropriate location."
	rm -rf "$w"
	exit 1
fi

printf '%s\0' env -C "${cwd}" -- > "$w/param.pre"

## handle basic environment
if [ -z "${o_env}" ] ; then
	printf '%s\0' \
		"HOME=${homedir}" \
		"LOGNAME=${username}" \
		"SHELL=/bin/sh" \
		"USER=${username}" \
	>> "$w/param.pre"
fi

if [ ${c_param} = 0 ] ; then
	msg "argument warning: nothing was passed - do 'semi-dry' run:"
	echo "  - print options/parameters"
	echo "  - run \`id'"

	echo ; echo "options:"
	xargs -0 printf '%q ' < "$w/opt"
	echo

	if [ -s "$w/param.pre" ] ; then
		echo ; echo "parameters:"
		xargs -0 printf '%q ' < "$w/param.pre"
		echo
	fi

	echo

	printf 'id\0' > "$w/param.post"
fi 1>&2

## aggregate parameters
{
	cat "$w/param.pre" "$w/param.post"
} > "$w/param"
rm "$w/param.pre" "$w/param.post"

cmd=$(mktemp)
cat "$w/opt" "$w/param" > "${cmd}"
rm -rf "$w"

#( sleep 5 ; rm -f "${cmd}" ; ) &
# exec xargs -0 -a "${cmd}" setpriv

## x0 is responsible for ${cmd} deletion
exec /opt/aux/x0 setpriv "${cmd}"
