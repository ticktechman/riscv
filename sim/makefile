###############################################################################
##
##       filename: makefile
##    description:
##        created: 2026/04/04
##         author: ticktechman
##
###############################################################################
.PHONY: all build test install doc hawks

ROOT_DIR := $(dir $(CURDIR))
TEST_DIR := $(ROOT_DIR)/software/test
HEX_FILES := $(wildcard $(TEST_DIR)/riscv-tests/hawks/*.hex | sort)
HEX_FPU := $(shell find $(TEST_DIR)/testfloat/testcases/build -name *.hex | sort)

HAWKS_FLAGS = -LDFLAGS "-lelf" -CFLAGS "-I/opt/homebrew/include" -j 0 --timing --binary
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

#------------------
# linux
#------------------
linux: obj_dir/linux
	@$< +verilator+quiet +elf="$(TEST_DIR)/isa/build/sbi"

obj_dir/linux: hawks.sv hawks.cpp
	@verilator $(HAWKS_FLAGS) --trace $^ --top-module linux -o $(notdir $@)

#------------------
# hawks dev
#------------------
hawks: obj_dir/hawks
hawks.test: $(HEX_FILES:.hex=.run)
hawks.fpu: $(HEX_FPU:.hex=.fputest)
hawks.one: obj_dir/hawks
	@$< +verilator+quiet +elf="$(TEST_DIR)/riscv-tests/hawks/rv64uc-p-rvc"

obj_dir/hawks: hawks.sv hawks.cpp
	@verilator $(HAWKS_FLAGS) --trace $^ --top-module top -o $(notdir $@)

$(TEST_DIR)/testfloat/testcases/build/%.fputest: obj_dir/hawks
	@printf "%20s " "$*: "
	-@obj_dir/hawks +verilator+quiet +elf="$(@:.fputest=)"

%.run: obj_dir/hawks
	@printf "%28s" "$(notdir $*): "
	-@obj_dir/hawks +verilator+quiet +elf="$*"
#------------------

$(SIM): $(SV_SRCS) main.cpp
	verilator $(V_FLAGS) $(SV_SRCS) main.cpp --top-module top

run: $(SIM)
	@$(SIM) +verilator+quiet

clean:
	rm -rf obj_dir

###############################################################################
