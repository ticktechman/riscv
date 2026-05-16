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
CFLAGS = -march=rv64ima_zicsr -mabi=lp64 -nostdlib -Wl,-T link.ld -Wl,-melf64lriscv
COPYFLAGS = -O verilog --verilog-data-width=4
SRCS = $(wildcard *.S)
HEXS = $(SRCS:.S=.hex)

SIM = obj_dir/Vtop

all: $(HEXS)

%.hex: %.S
	@$(RISCV_PREFIX)gcc $(CFLAGS) -o $(^:.S=.elf) $^
	@$(RISCV_PREFIX)objcopy $(COPYFLAGS) $(^:.S=.elf) $@
	@echo "> $@"

clean:
	rm -rf *.hex *.elf

###############################################################################
