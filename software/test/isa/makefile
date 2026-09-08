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
CFLAGS = -march=rv64imafd_zicsr -mabi=lp64d -nostdlib -Wl,-T link.ld -Wl,-melf64lriscv
COPYFLAGS = -O verilog --verilog-data-width=1
SRCS = $(wildcard src/*.S)
HEXS = $(patsubst src/%.S, build/%.hex, $(SRCS))

all: $(HEXS)

build/%.hex: src/%.S
	@[[ -d ./build ]] || mkdir ./build
	@$(RISCV_PREFIX)gcc $(CFLAGS) -o $(@:.hex=) $^
	@$(RISCV_PREFIX)objcopy $(COPYFLAGS) $(@:.hex=) $@
	@echo "> $@"

clean:
	rm -rf build

###############################################################################
