###############################################################################
##
##       filename: makefile
##    description:
##        created: 2026/04/20
##         author: ticktechman
##
###############################################################################

#---------------
# src/xxx.S + golden/$frm/xxx.txt.S => build/$frm/{xxx, xxx.hex, xxx.data}
#---------------

.PHONY: all clean

RV_PREFIX = /opt/riscv/bin/riscv-none-elf-
CC = $(RV_PREFIX)gcc
OBJCOPY = $(RV_PREFIX)objcopy
CFLAGS = -march=rv64imafd_zicsr -mabi=lp64d -nostdlib -Wl,-T link.ld -Wl,-melf64lriscv
COPYFLAGS = -O verilog --verilog-data-width=1 --no-change-warnings
SRCS = $(notdir $(wildcard src/*.S))
FRMS = rne rtz rdn rup rmm

all:

define make-rules
build/$(1)/$(2).hex: src/$(2).S golden/$(1)/$(2).txt.S
	@mkdir -p $$(dir $$@)
	@$$(CC) $$(CFLAGS) -I src -I golden/$(1) -D_FRM=$(1) -o $$(@:.hex=) src/$(2).S
	@$$(OBJCOPY) $$(COPYFLAGS) -j .data --change-section-address .data=0 $$(@:.hex=) $$(@:.hex=).data >/dev/null
	@$$(OBJCOPY) $$(COPYFLAGS) -j .text.init --change-section-address .text.init=0 $$(@:.hex=) $$(@:.hex=).hex >/dev/null
	@echo "> $$@"

TARGETS += build/$(1)/$(2).hex
endef

$(foreach f,$(FRMS), $(foreach s,$(SRCS), $(eval $(call make-rules,$(f),$(basename $(s))))))

all: $(TARGETS)

clean:
	rm -rf build
###############################################################################
