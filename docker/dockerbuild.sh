#!/bin/bash
set -euo pipefail
set -x

# BEGIN syslinux
ln -s /opt/musl-cross/i486-linux-musl/lib/libc.so /lib/ld-musl-i386.so.1
ln -s /usr/include/uuid /opt/musl-cross/i486-linux-musl/include/uuid

mkdir -p /tmp/apk-download
cd /tmp/apk-download
OLD_ARCH="$(cat /etc/apk/arch)"
echo 'x86' > /etc/apk/arch
apk update --allow-untrusted
apk fetch libuuid --allow-untrusted
echo "$OLD_ARCH" > /etc/apk/arch
apk update

tar -xf libuuid-*.apk -C /opt/musl-cross/ lib/

ln -s ../../lib/libuuid.so.1 /opt/musl-cross/i486-linux-musl/lib/libuuid.so
# END syslinux
