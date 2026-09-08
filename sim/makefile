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

all: hawks

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

clean:
	rm -rf obj_dir
###############################################################################
