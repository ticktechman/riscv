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

itypes="i32 i64 ui32 ui64"
ftypes="f64 f32"
TFGEN="./TestFloat-3e/build/Linux-ARM-VFPv2-GCC/testfloat_gen"
GLD="./golden"

generate_x2x() {
  ## int <-> float
  for itype in $itypes; do
    for ftype in $ftypes; do
      i2f="${itype}_to_${ftype}"
      f2i="${ftype}_to_${itype}"

      $TFGEN -level 1 $i2f >"$GLD/${i2f}.txt"
      echo "> $GLD/${i2f}.txt"
      $TFGEN -level 1 $i2f >"$GLD/${f2i}.txt"
      echo "> $GLD/${f2i}.txt"
    done
  done

  ## f32 <-> f64
  for f1 in $ftypes; do
    for f2 in $ftypes; do
      [[ "$f1" != "$f2" ]] || continue
      f2f="${f1}_to_${f2}"
      $TFGEN -level 1 $f2f >"$GLD/${f2f}.txt"
      echo "> $GLD/${f2f}.txt"
    done
  done
}

generate_tc() {
  # <int>_to_<float>     <float>_add      <float>_eq
  # <float>_to_<int>     <float>_sub      <float>_le
  # <float>_to_<float>   <float>_mul      <float>_lt
  # <float>_roundToInt   <float>_mulAdd   <float>_eq_signaling
  #                      <float>_div      <float>_le_quiet
  #                      <float>_rem      <float>_lt_quiet
  #                      <float>_sqrt
  operators="add sub mul div sqrt mulAdd rem"
  operators="roundToInt eq le lt eq_signaling le_quiet lt_quiet"

  [[ -d "$GLD" ]] || mkdir $GLD
  for typ in $ftypes; do
    for op in $operators; do
      one="${typ}_${op}"
      $TFGEN -level 1 "$one" >"${GLD}/$one".txt
      echo "> $GLD/${one}.txt"
    done
  done
}

# download_pkg
# build_pkg
# generate_tc
# generate_x2x

###############################################################################
