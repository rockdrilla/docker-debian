#!/bin/sh
# SPDX-License-Identifier: BSD-3-Clause
# (c) 2022, Konstantin Demin

chmod 0755 "${bin}"
test_bin .
cp -f "${bin}" "${dst_dir}/"
stat -c '%A %s %n' "${dst_dir}/${bin}"

cd /
rm -rf "$w"
