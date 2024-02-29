#!/bin/sh
mkdir -p /cd /amiga /gentoo

mount /dev/sdb /cd
mount /dev/sda1 /amiga
mount /dev/sda2 /gentoo

gzip -k -d /cd/vmlinux.gz -c > /amiga/LoadLin/vmlinux

rm -rf /gentoo/lib/modules
cd /gentoo
tar -xvf /cd/modules.*

cd /
umount /cd
umount /amiga
umount /gentoo

echo DONE
