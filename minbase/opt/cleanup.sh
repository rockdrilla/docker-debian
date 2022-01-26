#!/bin/sh
# SPDX-License-Identifier: BSD-3-Clause
# (c) 2021-2022, Konstantin Demin

## reset locale to default one
unset LANGUAGE LC_CTYPE LC_NUMERIC LC_TIME LC_COLLATE LC_MONETARY LC_MESSAGES
unset LC_PAPER LC_NAME LC_ADDRESS LC_TELEPHONE LC_MEASUREMENT LC_IDENTIFICATION
export LANG=C.UTF-8
export LC_ALL=C.UTF-8

## setup various environment variables representing temporary directory
export TMPDIR=/tmp
export TMP=/tmp
export TEMPDIR=/tmp
export TEMP=/tmp

du -xsh /

run-parts ${VERBOSE:+--verbose} --exit-on-error /opt/cleanup.d
r=$?

/opt/aux/flush-run.sh
/opt/aux/flush-tmp.sh

## list stalled configs (if any)
/opt/aux/list-stalled-configs.sh

## list broken symlinks (if any)
/opt/aux/list-broken-symlinks.sh

du -xsh /

exit $r
