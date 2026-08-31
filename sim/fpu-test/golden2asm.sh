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
  local dest="testcases/${1}.S"
  local dir="$(dirname $dest)"
  [[ -d $dir ]] || mkdir -p $dir

  awk 'BEGIN{tn=2} {
    printf "\n/* N=%d */\n", tn
    for (i = 1; i <= NF; i++) {
      if (length($i) == 16)
        printf ".dword 0x%s\n", $i
      else
        printf ".word 0x%s\n", $i
    }
    printf ".word %d\n", tn
    tn++
  }' "$1" >$dest
  printf "%30s > %-40s\n" "$1" "$dest"
}

gen_all() {
  find golden/ -name "*.txt" -print0 | while IFS= read -r -d '' file; do
    gen_one "$file"
  done
}

gen_all
# gen_one golden/rtz/f32_to_i32.txt

###############################################################################
