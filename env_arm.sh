COMPILER_PATH=${HOME}/dev/toolchains/arm-buildroot-linux-uclibcgnueabi_sdk-buildroot/bin
CROSS_COMPILE=arm-buildroot-linux-uclibcgnueabi-
ARCH=arm

export PATH=${COMPILER_PATH}:${PATH}
export ARCH=${ARCH}
export CROSS_COMPILE=${CROSS_COMPILE}
export STAGING_DIR=/tmp
