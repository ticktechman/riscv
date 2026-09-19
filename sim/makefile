###############################################################################
##
##       filename: makefile
##    description:
##        created: 2026/04/04
##         author: ticktechman
##
###############################################################################
.PHONY: all build test install doc hawks falcon

QUIET := @
MAKEFLAGS += -s

ROOT_DIR := $(dir $(CURDIR))
TEST_DIR := $(ROOT_DIR)software/test
HEX_FILES := $(wildcard $(TEST_DIR)/riscv-tests/hawks/*.hex | sort)
HEX_FPU := $(shell find $(TEST_DIR)/testfloat/testcases/build -name *.hex | sort)

HAWKS_FLAGS = -LDFLAGS "-lelf" -CFLAGS "-I/opt/homebrew/include" -j 0 --timing --binary
V_FLAGS = --timing --cc --exe --trace --build -I../

all: hawks falcon

#------------------
# linux
#------------------
linux: obj_dir/linux
	@$< +verilator+quiet +elf="$(TEST_DIR)/isa/build/sbi"

obj_dir/linux: hawks.sv hawks.cc
	@verilator $(HAWKS_FLAGS) --trace $^ --top-module linux -o $(notdir $@)

#------------------
# falcon dev
#------------------
falcon: obj_dir/falcon
falcon.test: $(HEX_FILES:.hex=.run)

#------------------
# hawks dev
#------------------
hawks: obj_dir/hawks
hawks.test: $(HEX_FILES:.hex=.run)
hawks.fpu: $(HEX_FPU:.hex=.fputest)

%.one: $(TEST_DIR)/riscv-tests/hawks/rv64mi-p-csr obj_dir/%
	@obj_dir/$* +verilator+quiet +elf="$<"
	@echo "\n>> [$*] $(notdir $<)\n"

obj_dir/%: %.sv %.cc
	@echo "> building $* ..."
	@verilator $(HAWKS_FLAGS) --trace $^ --top-module top -o $(notdir $@)
	@echo ""

$(TEST_DIR)/testfloat/testcases/build/%.fputest: obj_dir/hawks
	@printf "%20s " "$*: "
	-@obj_dir/hawks +verilator+quiet +elf="$(@:.fputest=)"

%.run: obj_dir/falcon
	@printf "%28s" "$(notdir $*): "
	-@obj_dir/falcon +verilator+quiet +elf="$*"

clean:
	rm -rf obj_dir
###############################################################################
