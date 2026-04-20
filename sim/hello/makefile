###############################################################################
##
##       filename: makefile
##    description:
##        created: 2026/04/20
##         author: ticktechman
##
###############################################################################
.PHONY: all build test install doc

RISCV_PREFIX = /opt/riscv/bin/riscv-none-elf-
CFLAGS = -march=rv64ima -mabi=lp64 -nostdlib -Wl,-T link.ld -Wl,-melf64lriscv
V_FLAGS = --cc --exe --trace --build

SIM = obj_dir/Vtop

all: hex

hex: hello.hex

%.hex: %.S
	@$(RISCV_PREFIX)gcc $(CFLAGS) -o $(patsubst %.S, %.elf, $^) $^
	@$(RISCV_PREFIX)objcopy -O verilog --verilog-data-width=4 $(patsubst %.S, %.elf, $^) $@

clean:
	rm -rf *.hex *.elf

###############################################################################
