#!/usr/bin/env bash
###############################################################################
##
##       filename: build-env.sh
##    description:
##        created: 2026/08/18
##         author: ticktechman
##
###############################################################################

download_pkg() {
  curl -O http://www.jhauser.us/arithmetic/SoftFloat-3e.zip
  curl -O http://www.jhauser.us/arithmetic/TestFloat-3e.zip
  unzip SoftFloat-3e.zip
  unzip TestFloat-3e.zip
}

build_pkg() {
  old_dir="$(pwd)"
  echo "==> start building..."
  cd ./SoftFloat-3e/build/Linux-ARM-VFPv2-GCC/ && make &&
    cd "$old_dir" &&
    cd ./TestFloat-3e/build/Linux-ARM-VFPv2-GCC/ && make &&
    cd "$old_dir" || exit 0
  echo "==> build succ"
}

generate_tc() {
  operators="add sub mul div sqrt mulAdd rem"
  types="f64 f32"
  for typ in $types; do
    for op in $operators; do
      one="${typ}_${op}"
      ./TestFloat-3e/build/Linux-ARM-VFPv2-GCC/testfloat_gen -level 1 "$one" >"$one".txt
      echo "${one}.txt"
    done
  done
}

# download_pkg
# build_pkg
# generate_tc

###############################################################################
