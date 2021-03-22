# This uses the cross compiler from kernel.org
# Taken from
# https://mirrors.edge.kernel.org/pub/tools/crosstool/files/bin/x86_64/8.1.0/
CROSS_COMPILE	:= mips-openwrt-linux-
# capcella, e55, mpc30x, ci20...
MIPSMACHINE	:= ath79
build_dir       := $(CURDIR)/build-mips
output_dir	:= $(HOME)
#rootfs		:= $(HOME)/rootfs-mips.cpio.gz
rootfs		:= $(CURDIR)/initramfs.txt
install_dir     := $(build_dir)/install
config_file     := $(build_dir)/.config
rootfsbase	:= $(shell basename $(rootfs))
dtb		:= $(build_dir)/arch/mips/boot/dts/qca/ar9132_buffalo_wzr-hp-g300nh-s.dtb

cmdline		:= "console=ttyS0,115200 rootfstype=ramfs"

make_options := -f Makefile \
                ARCH=mips \
                CROSS_COMPILE=$(CROSS_COMPILE) \
                KBUILD_OUTPUT=$(build_dir)

.PHONY: help
help:
	@echo "****  Common Makefile  ****"
	@echo "make config [PLATFORM=foo] - configure for platform \"foo\""
	@echo "make build - build the kernel and produce a RAMdisk image"
	@echo
	@echo "example:"
	@echo "make -f mips.mak config"
	@echo "make -f mips.mak build"

.PHONY: have-rootfs
have-rootfs:
	@if [ ! -d $(rootfs) ] ; then \
	     echo "ERROR: no rootfs at $(rootfs)" ; \
	     echo "This is needed to boot the system." ; \
	     echo "ABORTING." ; \
	     exit 1 ; \
	else \
	     echo "Rootfs available at $(rootfs)" ; \
	fi
	@if [ ! -r $(rootfs) ] ; then \
	     echo "ERROR: rootfs at $(rootfs) not readable" ; \
	     echo "ABORTING." ; \
	     exit 1 ; \
	fi

.PHONY: have-crosscompiler
have-crosscompiler:
	@echo -n "Check that $(CROSS_COMPILE)gcc is available..."
	@which $(CROSS_COMPILE)gcc > /dev/null ; \
	if [ ! $$? -eq 0 ] ; then \
	   echo "ERROR: cross-compiler $(CROSS_COMPILE)gcc not in PATH=$$PATH!" ; \
	   echo "ABORTING." ; \
	   exit 1 ; \
	else \
	   echo "OK" ;\
	fi

.PHONY: config-base
config-base: FORCE
	@mkdir -p $(build_dir)
	@cp -r $(rootfs) $(build_dir)/$(rootfsbase)
	$(MAKE) $(make_options) $(MIPSMACHINE)_defconfig

config-initramfs: config-base
	# Configure in the initramfs
	$(CURDIR)/scripts/config --file $(config_file) \
	--enable BLK_DEV_INITRD \
	--set-str INITRAMFS_SOURCE $(rootfsbase) \
	--enable RD_GZIP \
	--enable INITRAMFS_COMPRESSION_GZIP \
	--enable CMDLINE_BOOL \
	--set-str CMDLINE $(cmdline) \
	--enable CMDLINE_OVERRIDE \
	--disable MIPS_CMDLINE_FROM_BOOTLOADER \
	--disable MIPS_CMDLINE_FROM_DTB \
	--enable PRINTK_TIME

config-openwrt: config-base
	$(CURDIR)/scripts/config --file $(config_file) \
	--enable MIPS_ELF_APPENDED_DTB \
	--enable PARTITION_ADVANCED \
	--enable EXT4_FS \
	--enable EXT4_POSIX_ACL \
	--enable SQUASHFS \
	--enable SQUASHFS_XZ \
	--enable OVERLAY_FS \
	--enable DEVTMPFS \
	--enable CGROUPS \
	--enable INOTIFY_USER \
	--enable SIGNALFD \
	--enable TIMERFD \
	--enable EPOLL \
	--enable NET \
	--enable UNIX \
	--enable SYSFS \
	--enable CONFIG_GPIO_MUX_INPUT

# do this and bring sources from drivers/mdt/mtdsplit
#	--enable MTD_ROOTFS_ROOT_DEV \
#	--enable MTD_SPLIT \
#	--set-str MTD_SPLIT_FIRMWARE_NAME firmware \
#	--enable MTD_SPLIT_SQUASHFS_ROOT \
#	--enable MTD_SPLIT_SUPPORT \


config: config-base config-initramfs config-openwrt
	yes "" | make $(make_options) oldconfig

menuconfig: FORCE
	$(MAKE) $(make_options) menuconfig

#saveconfig: config-base
saveconfig:
	yes "" | make $(make_options) oldconfig
	$(MAKE) $(make_options) savedefconfig
	cp $(build_dir)/defconfig arch/mips/configs/$(MIPSMACHINE)_defconfig

update-rootfs: FORCE
	@echo "Update rootfs image"
	@cp -r $(rootfs) $(build_dir)/$(rootfsbase)

build-vmlinux: have-crosscompiler update-rootfs
	$(MAKE) $(make_options) -j9 vmlinux

build-dtbs: FORCE
	$(MAKE) $(make_options) dtbs W=1

build-vmlinux-dt: build-vmlinux build-dtbs
	@if [ ! -r $(dtb) ] ; then \
	   echo "NO DTB in $(dtb)!" ; \
	   exit 1 ; \
	fi
	@echo "Concatenate DTB onto vmlinux $(build_dir)/vmlinux..."
	${CROSS_COMPILE}objcopy --update-section .appended_dtb=$(dtb) $(build_dir)/vmlinux

build-uimage: build-vmlinux-dt
	
	$(MAKE) $(make_options) -j9 uImage
	
#	@echo "Copy uImage to $(output_dir)/uImage"
#	cp $(build_dir)/arch/mips/boot/uImage $(output_dir)/uImage

	# If we have a TFTP boot directory
	@if [ -w /tftp ] ; then \
	  echo "copy uImage to /tft/boot.img" ; \
	  cp $(build_dir)/arch/mips/boot/uImage /tftp/boot.bin ; \
	fi

build: build-uimage
	@echo "complete."

clean:
	$(MAKE) -f Makefile clean
	rm -rf $(build_dir)

# Rules without commands or prerequisites that do not match a file name
# are considered to always change when make runs. This means that any rule
# that depends on FORCE will always be remade also.
FORCE:
