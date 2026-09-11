#!/usr/bin/env bash
###############################################################################
##
##       filename: build.sh
##    description:
##        created: 2026/09/11
##         author: ticktechman
##
##       NEED TO BE BUILT ON LINUX
###############################################################################

linux.download() {
  echo "start downloading ..." &&
    wget https://www.kernel.org/pub/linux/kernel/v6.x/linux-6.12.39.tar.xz &&
    tar Jxvf linux-6.12.39.tar.xz &&
    echo "=> download succ." || echo "=> download failed"
}

linux.build() {
  echo "start building..." &&
    cp hawks_with_fpu_defconfig linux-6.12.39/.config &&
    make ARCH=riscv CROSS_COMPILE=riscv64-linux-gnu- -j4 &&
    echo "=> build succ." || echo "=> build failed"
}

# linux.download
# linux.build
###############################################################################
