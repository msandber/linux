# This uses the cross compiler from kernel.org
# Taken from
# https://mirrors.edge.kernel.org/pub/tools/crosstool/files/bin/x86_64/8.1.0/
ARCH		?= arm
CROSS_COMPILE	:= arm-buildroot-linux-uclibcgnueabi-
MACHINE		:= orion5x
build_dir       := $(CURDIR)/build-armv5
output_dir	:= $(HOME)
rootfs		:= $(CURDIR)/initramfs_arm.txt
install_dir     := $(build_dir)/install
config_file     := $(build_dir)/.config
makejobs	:= $(shell grep '^processor' /proc/cpuinfo | sort -u | wc -l)
makethreads	:= $(shell dc -e "$(makejobs) 1 + p")
rootfsbase	:= $(shell basename $(rootfs))
dtb		:= $(build_dir)/arch/$(ARCH)/boot/dts/orion5x-dlink-dns323a1.dtb

cmdline		:= "console=ttyS0,115200 rootfstype=ramfs"

make_options := -f Makefile \
		-j$(makethreads) -l$(makejobs) \
		ARCH=$(ARCH) \
		CROSS_COMPILE=$(CROSS_COMPILE) \
		KBUILD_OUTPUT=$(build_dir)

.PHONY: help
help:
	@echo "****  Common Makefile  ****"
	@echo "make config [PLATFORM=foo] - configure for platform \"foo\""
	@echo "make build - build the kernel and produce a RAMdisk image"
	@echo
	@echo "example:"
	@echo "make -f armv5.mak config"
	@echo "make -f armv5.mak build"

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
	$(MAKE) $(make_options) $(MACHINE)_defconfig

config-disabled: config-base
	# Disable what's not needed
	$(CURDIR)/scripts/config --file $(config_file) \
	--disable WIRELESS \
	--disable WLAN \
	--disable USB_NET_DRIVERS \
	--disable MODULES \
	--disable PRINTK_TIME

config-initramfs: config-base
	# Configure in the initramfs
	$(CURDIR)/scripts/config --file $(config_file) \
	--enable PRINTK_TIME \
	--enable BLK_DEV_INITRD \
	--set-str INITRAMFS_SOURCE $(rootfsbase) \
	--enable KERNEL_XZ \
	--enable INITRAMFS_COMPRESSION_XZ \
	--enable CMDLINE_BOOL \
	--set-str CMDLINE $(cmdline) \
	--enable TMPFS \
	--enable DEVTMPFS \
	--enable SYSFS \
	--enable DEBUG_FS \

config-devicetree: config-base
	# Configure in the optional device tree if available
	if [ $(dtb) != "" ] ; then \
	$(CURDIR)/scripts/config --file $(config_file) \
	--enable USE_OF \
	--enable ARM_APPENDED_DTB \
	--enable MTD_PHYSMAP_OF \
	--enable PROC_DEVICETREE ; \
	fi

config-dns323: config-base
	$(CURDIR)/scripts/config --file $(config_file) \
	--enable KEXEC \
	--enable MEMORY \
	--enable ARCH_ORION5X \
	--enable MACH_DNS323_DT \
	--enable WATCHDOG \
	--enable ORION_WATCHDOG \
	--enable SENSORS_G760A \
	--enable SENSORS_LM75 \
	--enable POWER_RESET \
	--enable POWER_RESET_GPIO

config-raid: config-base
	$(CURDIR)/scripts/config --file $(config_file) \
	--enable MD \
	--enable BLK_DEV_MD \
	--enable MD_LINEAR \
	--enable MD_RAID0 \
	--enable MD_RAID1 \
	--enable MD_RAID456

config-openwrt: config-base
	$(CURDIR)/scripts/config --file $(config_file) \
	--enable PARTITION_ADVANCED \
	--enable EXT4_FS \
	--enable EXT4_POSIX_ACL \
	--enable SQUASHFS \
	--enable SQUASHFS_XZ \
	--enable OVERLAY_FS \
	--enable CGROUPS \
	--enable INOTIFY_USER \
	--enable SIGNALFD \
	--enable TIMERFD \
	--enable EPOLL \
	--enable NET \
	--enable UNIX

# do this and bring sources from drivers/mdt/mtdsplit
#	--enable MTD_ROOTFS_ROOT_DEV \
#	--enable MTD_SPLIT \
#	--set-str MTD_SPLIT_FIRMWARE_NAME firmware \
#	--enable MTD_SPLIT_SQUASHFS_ROOT \
#	--enable MTD_SPLIT_SUPPORT \

#config: config-base config-initramfs config-devicetree config-openwrt
config: config-base config-initramfs config-devicetree config-disabled config-dns323
	yes "" | make $(make_options) oldconfig

menuconfig: FORCE
	$(MAKE) $(make_options) menuconfig

#saveconfig: config-base
saveconfig:
	yes "" | make $(make_options) oldconfig
	$(MAKE) $(make_options) savedefconfig
	cp $(build_dir)/defconfig arch/$(ARCH)/configs/$(MACHINE)_defconfig

update-rootfs: FORCE
	@echo "Update rootfs image"
	@cp -r $(rootfs) $(build_dir)/$(rootfsbase)

build-zimage: have-crosscompiler update-rootfs
	$(MAKE) $(make_options) zImage CONFIG_DEBUG_SECTION_MISMATCH=y

build-dtbs: FORCE
	$(MAKE) $(make_options) dtbs CONFIG_DEBUG_SECTION_MISMATCH=y

build: build-zimage build-dtbs
	@echo "Copy zImage to $(output_dir)/zImage..."
	@if [ -r $(build_dir)/arch/arm/boot/zImage ] ; then \
	    cp $(build_dir)/arch/arm/boot/zImage $(output_dir)/zImage ; \
	fi
	@if [ -r $(dtb) ] ; then \
	   echo "Catenate DTB onto zImage ... $(dtb)" ; \
	   cat $(dtb) >> $(output_dir)/zImage ; \
	fi
	# Generate uImage
	mkimage \
		-A arm \
		-O linux \
		-T kernel \
		-C none \
		-a 0x00008000 \
		-e 0x00008000 \
		-n "Maukka Linux kernel" \
		-d $(output_dir)/zImage \
		$(output_dir)/uImage
	# If we have a TFTP boot directory
	@if [ -w /tftp ] ; then \
	  echo "copy uImage to /tftp/boot.bin" ; \
	  cp $(output_dir)/uImage /tftp/boot.bin ; \
	fi

clean:
	$(MAKE) -f Makefile clean
	rm -rf $(build_dir)

# Rules without commands or prerequisites that do not match a file name
# are considered to always change when make runs. This means that any rule
# that depends on FORCE will always be remade also.
FORCE:
