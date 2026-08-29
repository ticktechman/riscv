#!/usr/bin/env bash
###############################################################################
##
##       filename: gen_asm.sh
##    description:
##        created: 2026/08/18
##         author: ticktechman
##
###############################################################################

gen_one() {
  local filename="$(basename $1)"
  local dest="./testcases/golden/${filename}.S"

  awk 'BEGIN{tn=2} {
    printf "\n  /* TESTNUM=%d */\n", tn
    for (i = 1; i <= NF; i++) {
      if (length($i) == 16)
        printf "  .dword 0x%s\n", $i
      else
        printf "  .word 0x%s\n", $i
    }
    printf "  .word %d\n", tn
    tn++
}' "$1" >$dest
  echo "> $1 -> $dest"
}

# for one in ./golden/*.txt; do
#   gen_one "$one"
# done

gen_one ./golden/f64_to_i64.txt
gen_one ./golden/f64_to_ui64.txt
gen_one ./golden/f64_to_i32.txt
gen_one ./golden/f64_to_ui32.txt

###############################################################################
