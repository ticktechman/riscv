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
COPYFLAGS = -O verilog --verilog-data-width=1 --no-change-warnings
SRCS = $(wildcard src/*.S)
# HEXS = $(addprefix build/,$(SRCS:.S=.hex))
HEXS = $(patsubst src/%.S, build/%.hex, $(SRCS))

all: $(HEXS)

build/%.hex: src/%.S golden/%.txt.S
	@[ ! -d build ] && mkdir build || touch build/
	@$(RISCV_PREFIX)gcc $(CFLAGS) -o $(@:.hex=) $<
	@$(RISCV_PREFIX)objcopy $(COPYFLAGS) -j .data --change-section-address .data=0 $(@:.hex=) $(@:.hex=).data >/dev/null
	@$(RISCV_PREFIX)objcopy $(COPYFLAGS) -j .text.init --change-section-address .text.init=0 $(@:.hex=) $(@:.hex=).hex >/dev/null

	@echo "> $@"

clean:
	rm -rf build

###############################################################################
