###############################################################################
##
##       filename: makefile
##    description:
##        created: 2026/04/04
##         author: ticktechman
##
###############################################################################
.PHONY: all build test install doc

HEX_FILES := $(wildcard $(CURDIR)/riscv-tests/*.hex)

define gen-args
$(eval SIM_ARGS := )

$(eval _DATA_SIZE := $(shell riscv-none-elf-objdump -h $(1) | grep '\.data' | awk '{print $$3}'))
$(eval _DATA_BASE := $(shell riscv-none-elf-objdump -h $(1) | grep '\.data' | awk '{print $$4}'))
$(eval SIM_ARGS += $(if $(strip $(_DATA_SIZE)),$(if $(strip $(_DATA_BASE)),+data.size=$(_DATA_SIZE) +data.base=$(_DATA_BASE))))

$(eval _TEXT_INIT_SIZE := $(shell riscv-none-elf-objdump -h $(1) | grep '\.text\.init' | awk '{print $$3}'))
$(eval _TEXT_INIT_BASE := $(shell riscv-none-elf-objdump -h $(1) | grep '\.text\.init' | awk '{print $$4}'))
$(eval SIM_ARGS += $(if $(strip $(_TEXT_INIT_SIZE)),$(if $(strip $(_TEXT_INIT_BASE)),+text_init.size=$(_TEXT_INIT_SIZE) +text_init.base=$(_TEXT_INIT_BASE))))

$(eval _TOHOST_SIZE := $(shell riscv-none-elf-objdump -h $(1) | grep '\.tohost' | awk '{print $$3}'))
$(eval _TOHOST_BASE := $(shell riscv-none-elf-objdump -h $(1) | grep '\.tohost' | awk '{print $$4}'))
$(eval SIM_ARGS += $(if $(strip $(_TOHOST_SIZE)),$(if $(strip $(_TOHOST_BASE)),+tohost.size=$(_TOHOST_SIZE) +tohost.base=$(_TOHOST_BASE))))

$(eval SIM_ARGS += +hex_file=$(1).hex)
endef

V_FLAGS = --timing --cc --exe --trace --build -I../
SV_SRCS = \
		top.sv \
		../rtl/soc/soc.sv \
		../rtl/soc/uart.sv \
		../rtl/soc/bootrom.sv \
		../rtl/core/corepkg.sv \
		../rtl/core/ifstage.sv \
		../rtl/core/idstage.sv \
		../rtl/core/exstage.sv \
		../rtl/core/memstage.sv \
		../rtl/core/wbstage.sv \
		../rtl/core/regfile.sv \
		../rtl/core/core.sv

SIM = obj_dir/Vtop

all: $(SIM)

mini: obj_dir/Vmini
mini.run: obj_dir/Vmini
	$(call gen-args,$(CURDIR)/riscv-tests/rv64si-p-dirty)
	$< +verilator+quiet $(SIM_ARGS)

mini.test: $(HEX_FILES:.hex=.run)
%.run: obj_dir/Vmini
	$(call gen-args,$*)
	-@obj_dir/Vmini +verilator+quiet $(SIM_ARGS)


.PHONY: mini.test

$(SIM): $(SV_SRCS) main.cpp
	verilator $(V_FLAGS) $(SV_SRCS) main.cpp --top-module top

obj_dir/Vmini: minisoc.sv
	@verilator -j 0 --timing --binary --trace minisoc.sv --top-module top -o Vmini

run: $(SIM)
	@$(SIM) +verilator+quiet

clean:
	rm -rf obj_dir

###############################################################################
