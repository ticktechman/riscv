#!/usr/bin/env bash
###############################################################################
##
##       filename: hex.sh
##    description:
##        created: 2026/05/29
##         author: ticktechman
##
###############################################################################

rm -f ./riscv-tests/{*.hex,*.data}
for one in $(ls -1 ./riscv-tests/rv64*); do
  echo "> $one"
  riscv-none-elf-objcopy -O verilog --verilog-data-width=1 -j .text.init --change-section-address .text.init=0 $one $one.hex >/dev/null
  riscv-none-elf-objcopy -O verilog --verilog-data-width=1 -j .data --change-section-address .data=0 --no-change-warnings $one $one.data >/dev/null
done

find ./riscv-tests -size 0 | xargs rm -f

###############################################################################
