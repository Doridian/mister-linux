ROOT_DIR := $(dir $(realpath $(lastword $(MAKEFILE_LIST))))
INITRAMFS_BASE=$(ROOT_DIR)/out/initramfs

UBUNTU_SYSLINUX_ORIG=http://archive.ubuntu.com/ubuntu/pool/main/s/syslinux/syslinux_6.04~git20190206.bf6db5b4+dfsg1.orig.tar.xz
UBUNTU_SYSLINUX_PKG=http://archive.ubuntu.com/ubuntu/pool/main/s/syslinux/syslinux_6.04~git20190206.bf6db5b4+dfsg1-3ubuntu1.debian.tar.xz

LINUX_VERSION=6.7.5
LINUX_DIR=linux-$(LINUX_VERSION)
LINUX_TARBALL=$(LINUX_DIR).tar.xz
LINUX_KERNEL_URL=https://cdn.kernel.org/pub/linux/kernel/v6.x/$(LINUX_TARBALL)

BUSYBOX_DIR=busybox-1.36.1
BUSYBOX_TARBALL=$(BUSYBOX_DIR).tar.bz2
BUSYBOX_URL=https://busybox.net/downloads/$(BUSYBOX_TARBALL)

GENTOO_STAGE3_URL=https://distfiles.gentoo.org/releases/x86/autobuilds/20240226T170403Z/stage3-i486-systemd-mergedusr-20240226T170403Z.tar.xz

.PHONY: all clean

all: stamp/fetch-kernel \
	 stamp/fetch-busybox

	-mkdir -p stamp
	echo "Starting build ..."

stamp/download-kernel:
	-mkdir -p dist src stamp
	cd dist && wget $(LINUX_KERNEL_URL)
	touch stamp/download-kernel

stamp/fetch-kernel: stamp/download-kernel
	cd src && tar -xvf ../dist/$(LINUX_TARBALL)

	touch stamp/fetch-kernel

stamp/download-busybox:
	-mkdir -p dist src stamp
	cd dist && wget $(BUSYBOX_URL)
	touch stamp/download-busybox

stamp/fetch-busybox: stamp/download-busybox
	cd src && tar -xvf ../dist/$(BUSYBOX_TARBALL)
	touch stamp/fetch-busybox

stamp/download-syslinux:
	-mkdir -p dist src stamp
	cd dist && wget $(UBUNTU_SYSLINUX_ORIG) -O syslinux_orig.tar.xz
	cd dist && wget $(UBUNTU_SYSLINUX_PKG) -O syslinux_pkg.tar.xz
	touch stamp/download-syslinux		

stamp/fetch-syslinux: stamp/download-syslinux
	-mkdir -p dist src stamp
	cd src && tar -xvf ../dist/syslinux_orig.tar.xz
	cd src && mv syslinux-6.04~git20190206.bf6db5b4 syslinux
	cd src/syslinux && tar -xvf ../../dist/syslinux_pkg.tar.xz
	cd src/syslinux && QUILT_PATCHES=debian/patches quilt push -a
	cd src/syslinux && patch -p1 < ../../patches/0030-fix-e88.patch
	touch stamp/fetch-syslinux		

kernelmenuconfig: stamp/fetch-kernel
	cp config/kernel.config src/$(LINUX_DIR)/.config
	cd src/$(LINUX_DIR) && make ARCH=x86 CROSS_COMPILE=i486-linux-musl- menuconfig
	cp src/$(LINUX_DIR)/.config config/kernel.config

busyboxmenuconfig: stamp/fetch-busybox
	cp config/busybox.config src/$(BUSYBOX_DIR)/.config
	cd src/$(BUSYBOX_DIR) && make ARCH=x86 CROSS_COMPILE=i486-linux-musl- menuconfig
	cp src/$(BUSYBOX_DIR)/.config config/busybox.config

build-syslinux: stamp/fetch-syslinux
	mkdir -p out/cdroot/isolinux
	cd src/syslinux && make bios PYTHON=python3 ARCH=x86 CROSS_COMPILE=i486-linux-musl- CC=i486-linux-musl-gcc LD=i486-linux-musl-ld OBJCOPY=i486-linux-musl-objcopy LD_LIBRARY_PATH=/opt/musl-cross/i486-linux-musl
	cd src/syslinux && make bios install PYTHON=python3 ARCH=x86 CROSS_COMPILE=i486-linux-musl- CC=i486-linux-musl-gcc LD=i486-linux-musl-ld OBJCOPY=i486-linux-musl-objcopy INSTALLROOT=`pwd`/../../out/isolinux
	cp out/isolinux/usr/share/syslinux/isolinux.bin out/cdroot/isolinux/
	cp out/isolinux/usr/share/syslinux/ldlinux.c32 out/cdroot/isolinux/
	cp config/isolinux.cfg out/cdroot/isolinux.cfg

download-all: stamp/download-kernel stamp/download-busybox stamp/download-syslinux
	echo OK

build-kernel: stamp/fetch-kernel
	-mkdir out
	-mkdir -p out/initramfs
	cp config/kernel.config src/$(LINUX_DIR)/.config
	cd src/$(LINUX_DIR) && $(MAKE) -j4 ARCH=x86 CROSS_COMPILE=i486-linux-musl-
	cp src/$(LINUX_DIR)/arch/x86/boot/bzImage out/cdroot/bzImage
	cd src/$(LINUX_DIR) && INSTALL_MOD_PATH=../../out/initramfs $(MAKE) ARCH=x86 CROSS_COMPILE=i486-linux-musl- modules_install
	depmod -b out/initramfs $(LINUX_VERSION)

build-busybox: stamp/fetch-busybox
	-mkdir -p out/rootfsinitramfs
	cp config/busybox.config src/$(BUSYBOX_DIR)/.config
	cd src/$(BUSYBOX_DIR) && $(MAKE) ARCH=x86 CROSS_COMPILE=i486-linux-musl-
	cd src/$(BUSYBOX_DIR) && $(MAKE) ARCH=x86 CROSS_COMPILE=i486-linux-musl- install
	cp -rv src/$(BUSYBOX_DIR)/_install/* out/initramfs

build-initramfs: build-busybox
	-mkdir -p out/cdroot

	-rm -rf out/initramfs/dev
	-mkdir -p out/initramfs/dev
	mknod -m 660 out/initramfs/dev/console c 5 1
	mknod -m 600 out/initramfs/dev/tty0 c 4 0
	mknod -m 600 out/initramfs/dev/tty1 c 4 1
	mknod -m 600 out/initramfs/dev/tty2 c 4 2

	-rm -rf out/initramfs/sys
	-mkdir -p out/initramfs/sys

	-rm -rf out/initramfs/proc
	-mkdir -p out/initramfs/proc

	-rm -rf out/initramfs/root
	-mkdir -p out/initramfs/root
	chmod 700 out/initramfs/root

	-rm -rf out/initramfs/overlay
	-mkdir -p out/initramfs/overlay/floppy out/initramfs/overlay/tmpfs
	chmod 700 out/initramfs/overlay out/initramfs/overlay/floppy out/initramfs/overlay/tmpfs

	-rm -rf out/initramfs/home
	-mkdir -p out/initramfs/home

	-rm -rf out/initramfs/tmp
	-mkdir -p out/initramfs/tmp
	chmod 1777 out/initramfs/tmp

	-rm -rf out/initramfs/var/run
	-mkdir -p out/initramfs/var/run

	-rm -rf out/initramfs/run
	ln -sf var/run out/initramfs/run

	mkdir -p out/initramfs/etc/init.d/ out/initramfs/etc/network/

	cp etc/rc out/initramfs/etc/init.d/rc
	chmod 755 out/initramfs/etc/init.d/rc

	cp etc/inittab out/initramfs/etc/inittab
	chmod 755 out/initramfs/etc/inittab

	cp /opt/musl-cross/i486-linux-musl/lib/libc.so out/initramfs/lib/libc.so
	ln -sf libc.so out/initramfs/lib/ld-musl-i486.so.1
	ln -sf libc.so out/initramfs/lib/ld-musl-i486.so

	cp etc/passwd out/initramfs/etc/passwd
	chmod 644 out/initramfs/etc/passwd

	cp etc/group out/initramfs/etc/group
	chmod 644 out/initramfs/etc/group

	cp etc/hosts out/initramfs/etc/hosts
	chmod 644 out/initramfs/etc/hosts

	cp etc/hostname out/initramfs/etc/hostname
	chmod 644 out/initramfs/etc/hostname

	echo '#!/bin/sh' > out/initramfs/usr/bin/run-parts
	echo 'exit 0' >> out/initramfs/usr/bin/run-parts
	chmod 755 out/initramfs/usr/bin/run-parts
 
	cp etc/passwd out/initramfs/etc/passwd
	chmod 644 out/initramfs/etc/passwd

	cp etc/shadow out/initramfs/etc/shadow
	chmod 600 out/initramfs/etc/shadow

	cp etc/network/interfaces out/initramfs/etc/network/interfaces
	chmod 644 out/initramfs/etc/network/interfaces
 
	-mkdir -p out/initramfs/usr/share/udhcpc
	cp etc/udhcpc.script out/initramfs/usr/share/udhcpc/default.script
	chmod 755 out/initramfs/usr/share/udhcpc/default.script

	cp bin/*.sh out/initramfs/bin
	chmod 755 out/initramfs/bin/*.sh

	cd out/initramfs && \
	find . | cpio -o -H newc | gzip > $(ROOT_DIR)/out/cdroot/initrd.gz

build-cdrom: build-kernel build-initramfs build-syslinux
	#-rm -f out/cdroot/stage3.tar.xz
	#wget $(GENTOO_STAGE3_URL) -O out/cdroot/stage3.tar.xz
	rm -f out/cdroot/isolinux.tar.gz
	tar -cvzf out/cdroot/isolinux.tar.gz out/isolinux
	rm -f out/cdroot/modules.tar.gz
	tar -cvzf out/cdroot/modules.tar.gz -C out/initramfs ./lib/modules
	mkisofs -o ./mister_linux.iso \
		-b isolinux/isolinux.bin \
		-c isolinux/boot.cat \
		-no-emul-boot -boot-load-size 4 -boot-info-table \
		./out/cdroot
	#-c out/isolinux/usr/share/syslinux/boot.cat \

clean:
	echo "Making a fresh build ..."
	-rm -rf src dist stamp out
