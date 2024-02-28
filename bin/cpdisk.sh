#!/bin/sh
set -eux

DISKDEV="$1"
shift 1
echo "Copying disk image from $DISKDEV to /"

TMPDIR="$(mktemp -d)"
safe_exit() {
    cd /
    umount "$TMPDIR" || true
    rmdir "$TMPDIR"
}
trap 'safe_exit' EXIT
trap 'exit 1' INT

mount -o ro "$DISKDEV" "$TMPDIR"
mount -o remount,ro "$TMPDIR"
cp -a "$@" "$TMPDIR/." /
