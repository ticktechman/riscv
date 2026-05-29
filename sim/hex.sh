#!/usr/bin/env bash
###############################################################################
##
##       filename: hex.sh
##    description:
##        created: 2026/05/29
##         author: ticktechman
##
###############################################################################

for one in $(ls -1 ./riscv-tests/rv64* | grep -v .hex); do
  riscv-none-elf-objcopy -O verilog --verilog-data-width=4 -j .text.init --change-section-address .text.init=0 $one $one.hex
  riscv-none-elf-objcopy -O verilog --verilog-data-width=1 -j .data --change-section-address .data=0 $one $one.hex.data
done

find ./riscv-tests -size 0 | xargs rm -f

###############################################################################
