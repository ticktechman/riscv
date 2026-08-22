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
# HEXS = $(SRCS:.S=.hex)
HEXS = $(addprefix build/,$(SRCS:.S=.hex))
ELFS = $(SRCS:.S=)

all: $(HEXS)

build/%.hex: %.S golden/%.txt.S
	@[ ! -d build ] && mkdir build || touch build/
	@$(RISCV_PREFIX)gcc $(CFLAGS) -o ./build/$(<:.S=) $<
	@riscv-none-elf-objcopy -O verilog --verilog-data-width=1 -j .data --change-section-address .data=0 --no-change-warnings build/$(<:.S=) build/$(<:.S=).data >/dev/null
	@riscv-none-elf-objcopy -O verilog --verilog-data-width=1 -j .text.init --change-section-address .text.init=0 build/$(<:.S=) build/$(<:.S=).hex >/dev/null

	@echo "> $@"

clean:
	rm -rf build

###############################################################################
