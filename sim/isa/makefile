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
# CFLAGS = -march=rv64ima_zicsr -mabi=lp64 -nostdlib -Wl,-T link.ld -Wl,-melf64lriscv
CFLAGS = -march=rv64imafd_zicsr -mabi=lp64d -nostdlib -Wl,-T link.ld -Wl,-melf64lriscv
COPYFLAGS = -O verilog --verilog-data-width=1
SRCS = $(wildcard *.S)
HEXS = $(addprefix build/,$(SRCS:.S=.hex))

SIM = obj_dir/Vtop

all: $(HEXS)

build/%.hex: %.S
	@[[ -d ./build ]] || mkdir ./build
	@$(RISCV_PREFIX)gcc $(CFLAGS) -o ./build/$(^:.S=) $^
	@$(RISCV_PREFIX)objcopy $(COPYFLAGS) ./build/$(^:.S=) $@
	@echo "> $@"

clean:
	rm -rf build

###############################################################################
