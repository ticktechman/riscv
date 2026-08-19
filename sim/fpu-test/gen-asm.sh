#!/usr/bin/env bash
###############################################################################
##
##       filename: gen_asm.sh
##    description:
##        created: 2026/08/18
##         author: ticktechman
##
###############################################################################

f64_5() {
  local filename="$1"
  awk 'BEGIN{tn=2} {
    printf "\n  /* TESTNUM=%d */\n", tn
    printf "  .dword 0x%s\n", $1
    printf "  .dword 0x%s\n", $2
    printf "  .dword 0x%s\n", $3
    printf "  .dword 0x%s\n", $4
    printf "  .word 0x%s\n", $5
    printf "  .word %d\n", tn
    tn++
}' $filename >"${filename}.S"
}

f64_4() {
  local filename="$1"
  awk 'BEGIN{tn=2} {
    printf "\n  /* TESTNUM=%d */\n", tn
    printf "  .dword 0x%s\n", $1
    printf "  .dword 0x%s\n", $2
    printf "  .dword 0x%s\n", $3
    printf "  .word 0x%s\n", $4
    printf "  .word %d\n", tn
    tn++
}' $filename >"${filename}.S"
}

f64_3() {
  local filename="$1"
  awk 'BEGIN{tn=2} {
    printf "\n  /* TESTNUM=%d */\n", tn
    printf "  .dword 0x%s\n", $1
    printf "  .dword 0x%s\n", $2
    printf "  .word 0x%s\n", $3
    printf "  .word %d\n", tn
    tn++
}' $filename >"${filename}.S"
}

f32_5() {
  local filename="$1"
  awk 'BEGIN{tn=2} {
    printf "\n  /* TESTNUM=%d */\n", tn
    printf "  .word 0x%s\n", $1
    printf "  .word 0x%s\n", $2
    printf "  .word 0x%s\n", $3
    printf "  .word 0x%s\n", $4
    printf "  .word 0x%s\n", $5
    printf "  .word %d\n", tn
    tn++
}' $filename >"${filename}.S"
}

f32_4() {
  local filename="$1"
  awk 'BEGIN{tn=2} {
    printf "\n  /* TESTNUM=%d */\n", tn
    printf "  .word 0x%s\n", $1
    printf "  .word 0x%s\n", $2
    printf "  .word 0x%s\n", $3
    printf "  .word 0x%s\n", $4
    printf "  .word %d\n", tn
    tn++
}' $filename >"${filename}.S"
}

f32_3() {
  local filename="$1"
  awk 'BEGIN{tn=2} {
    printf "\n  /* TESTNUM=%d */\n", tn
    printf "  .word 0x%s\n", $1
    printf "  .word 0x%s\n", $2
    printf "  .word 0x%s\n", $3
    printf "  .word %d\n", tn
    tn++
}' $filename >"${filename}.S"
}

gen_one() {
  filename="$1"
  line="$(head -1 $filename)"
  fields=$(echo "$line" | awk '{print NF}')
  chars=$(echo "$line" | awk '{print length($1)}')

  funcname=""
  if ((chars == 8)); then
    funcname="f32_$fields"
  else
    funcname="f64_$fields"
  fi

  $funcname $filename
}

# f32="f32_add.txt f32_div.txt f32_mul.txt f32_mulAdd.txt f32_rem.txt f32_sqrt.txt f32_sub.txt"
f32=""
# f64="f64_add.txt f64_div.txt f64_mul.txt f64_mulAdd.txt f64_rem.txt f64_sqrt.txt f64_sub.txt"
f64="f64_mulAdd.txt"

for one in $f32; do
  echo $one
  gen_one $one
done
for one in $f64; do
  echo $one
  gen_one $one
done

###############################################################################
