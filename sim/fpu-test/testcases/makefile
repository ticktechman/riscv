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
HEXS = $(SRCS:.S=.hex)
ELFS = $(SRCS:.S=)

all: $(HEXS)

%.hex: %.S data/%.txt.S
	@$(RISCV_PREFIX)gcc $(CFLAGS) -o $(<:.S=) $<
	@riscv-none-elf-objcopy -O verilog --verilog-data-width=1 -j .data --change-section-address .data=0 --no-change-warnings $(<:.S=) $(<:.S=).data >/dev/null
	@riscv-none-elf-objcopy -O verilog --verilog-data-width=1 -j .text.init --change-section-address .text.init=0 $(<:.S=) $(<:.S=).hex >/dev/null

	@echo "> $@"

clean:
	rm -rf *.hex *.data $(ELFS)

###############################################################################
