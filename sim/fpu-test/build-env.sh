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
  wget https://github.com/ticktechman/berkeley-testfloat-3/archive/refs/tags/1.0.zip -O berkeley-testfloat-3.zip
  wget https://github.com/ticktechman/berkeley-softfloat-3/archive/refs/tags/1.0.zip -O berkeley-softfloat-3.zip
  unzip berkeley-testfloat-3.zip && mv berkeley-testfloat-3-1.0 berkeley-testfloat-3
  unzip berkeley-softfloat-3.zip && mv berkeley-softfloat-3-1.0 berkeley-softfloat-3
}

build_pkg() {
  old_dir="$(pwd)"
  echo "==> start building..."
  cd ./berkeley-softfloat-3/build/macos-arm64/ && make &&
    cd "$old_dir" &&
    cd ./berkeley-testfloat-3/build/macos-arm64/ && make &&
    cd "$old_dir" || exit 0
  echo "==> build succ"
}

##
# *  -rnear_even      --Round to nearest/even.
#    -rminMag         --Round to minimum magnitude (toward zero).
#    -rmin            --Round to minimum (down).
#    -rmax            --Round to maximum (up).
#    -rnear_maxMag    --Round to nearest/maximum magnitude (nearest/away).
##
declare -A rmodes=(
  ["-rnear_even"]="rne"
  ["-rminMag"]="rtz"
  ["-rmin"]="rdn"
  ["-rmax"]="rup"
  ["-rnear_maxMag"]="rmm"
)
itypes="i32 i64 ui32 ui64"
ftypes="f64 f32"
TFGEN="./berkeley-testfloat-3/build/macos-arm64/testfloat_gen"
GLD="./golden"

generate_x2x() {
  ## int <-> float
  for rmode in "${!rmodes[@]}"; do
    local dirname="$GLD/${rmodes[$rmode]}"
    [[ -d "$dirname" ]] || mkdir -p $dirname
    for itype in $itypes; do
      for ftype in $ftypes; do
        i2f="${itype}_to_${ftype}"
        f2i="${ftype}_to_${itype}"

        $TFGEN -level 1 "$rmode" -exact $i2f >"$dirname/${i2f}.txt"
        echo "> $dirname/${i2f}.txt"
        $TFGEN -level 1 "$rmode" -exact $f2i >"$dirname/${f2i}.txt"
        echo "> $dirname/${f2i}.txt"
      done
    done
  done

  ## f32 <-> f64
  for rmode in "${!rmodes[@]}"; do
    local dirname="$GLD/${rmodes[$rmode]}"
    [[ -d "$dirname" ]] || mkdir -p $dirname
    for f1 in $ftypes; do
      for f2 in $ftypes; do
        [[ "$f1" != "$f2" ]] || continue
        f2f="${f1}_to_${f2}"
        $TFGEN -level 1 "$rmode" $f2f >"$dirname/${f2f}.txt"
        echo "> $dirname/${f2f}.txt"
      done
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
  operators="add sub mul div sqrt mulAdd eq le lt"

  for rmode in "${!rmodes[@]}"; do
    local dirname="$GLD/${rmodes[$rmode]}"
    [[ -d "$dirname" ]] || mkdir -p $dirname
    for typ in $ftypes; do
      for op in $operators; do
        one="${typ}_${op}"
        $TFGEN -level 1 "$rmode" "$one" >"${GLD}/${rmodes[$rmode]}/$one".txt
        if [[ $op == "mulAdd" ]]; then
          head -50000 "${GLD}/${rmodes[$rmode]}/$one".txt >a.txt
          mv a.txt "${GLD}/${rmodes[$rmode]}/$one".txt
        fi
        echo "> $dirname/${one}.txt"
      done
    done
  done
}

# download_pkg
# build_pkg
generate_tc
# generate_x2x

###############################################################################
