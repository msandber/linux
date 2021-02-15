COMPILER_PATH=${HOME}/dev/toolchains/toolchain-mips_24kc_gcc-8.4.0_musl/bin
CROSS_COMPILE=mips-openwrt-linux-
ARCH=mips
MACH=ath79

export PATH=${COMPILER_PATH}:${PATH}
export ARCH=${ARCH}
export MACH=${MACH}
export CROSS_COMPILE=${CROSS_COMPILE}
export STAGING_DIR=/tmp
