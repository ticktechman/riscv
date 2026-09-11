#!/usr/bin/env bash
###############################################################################
##
##       filename: build.sh
##    description:
##        created: 2026/09/11
##         author: ticktechman
##
##   NOTICE: NEED TO BE BUILD ON LINUX
###############################################################################

MAKE="make ARCH=riscv CROSS_COMPILE=riscv64-linux-gnu-"

bbox.download() {
  echo "start downloading ..." &&
    wget https://busybox.net/downloads/busybox-1.38.0.tar.bz2 &&
    tar jxvf busybox-1.38.0.tar.bz2 &&
    echo "=> downloaded." || echo "=> failed."
}

bbox.build() {
  echo "start building..." &&
    cp ./hawks_defconfig busybox-1.38.0/configs/ &&
    cd ./busybox-1.38.0 &&
    $MAKE hawks_defconfig &&
    $MAKE -j4 &&
    echo "=> build succ" || echo "=> build failed."
}

bbox.install() {
  echo "start installing..." &&
    cd ./busybox-1.38.0 &&
    sudo $MAKE CONFIG_PREFIX=../initrd install &&
    echo "=> done" || echo "=> install failed"
}

bbox.cpio() {
  echo "start packing cpio..." &&
    cd initrd &&
    [[ -e dev/hvc0 ]] || sudo mknod dev/hvc0 c 229 0 &&
    [[ -e dev/console ]] || sudo mknod dev/console c 5 1 &&
    sudo chown root:root -R * &&
    sudo find . -print0 | sudo cpio --null -ov --format=newc >../initramfs.cpio &&
    echo "=> cpio done." || echo "=> pack cpio failed"
}

# bbox.download
# bbox.build
# bbox.install
# bbox.cpio
###############################################################################
