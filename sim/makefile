###############################################################################
##
##       filename: makefile
##    description:
##        created: 2026/04/04
##         author: ticktechman
##
###############################################################################
.PHONY: all build test install doc hawks falcon

QUIET       := @
MAKEFLAGS   += -s
RUNNER      :=
ROOT_DIR    := $(dir $(CURDIR))
TEST_DIR    := $(ROOT_DIR)software/test
HEX_FILES   := $(wildcard $(TEST_DIR)/riscv-tests/hawks/*.hex | sort)
HEX_FPU     := $(shell find $(TEST_DIR)/testfloat/testcases/build -name *.hex | sort)
HAWKS_FLAGS := -LDFLAGS "-lelf" -CFLAGS "-I/opt/homebrew/include" -j 0 --timing --binary

#------------------
# verilator build deps($2) top module($1) and output $3
#------------------
define sim-build
	@echo "> building $(notdir $3) ..."
	@verilator $(HAWKS_FLAGS) --trace $(2) --top-module $1 -o $(notdir $(3))
	@echo ""
endef

all: hawks falcon

#------------------
# linux
#------------------
linux: obj_dir/linux
	# @$< +verilator+quiet +elf="$(TEST_DIR)/isa/build/sbi"

obj_dir/linux: hawks.sv hawks.cc
	@$(call sim-build,linux,$^,$@)

#------------------
# falcon dev
#------------------
falcon: obj_dir/falcon
falcon.test: falcon.runner $(HEX_FILES:.hex=.run)
hawks.fpu: falcon.runner $(HEX_FPU:.hex=.fputest)

#------------------
# hawks dev
#------------------
hawks: obj_dir/hawks
hawks.test: hawks.runner $(HEX_FILES:.hex=.run)
hawks.fpu: hawks.runner $(HEX_FPU:.hex=.fputest)

#------------------
# RULES
#------------------
%.runner: obj_dir/%
	$(eval RUNNER = obj_dir/$* +verilator+quiet)

%.one: $(TEST_DIR)/riscv-tests/hawks/rv64si-p-dirty obj_dir/%
	@obj_dir/$* +verilator+quiet +elf="$<"
	@echo "\n>> [$*] $(subst $(TEST_DIR)/,,$<)\n"

obj_dir/%: %.sv %.cc
	@$(call sim-build,top,$^,$@)

$(TEST_DIR)/testfloat/testcases/build/%.fputest: obj_dir/hawks
	@printf "%20s " "$*: "
	-@$(RUNNER) +elf="$(@:.fputest=)"

%.run: $(RUNNER)
	@printf "%28s" "$(notdir $*): "
	-@$(RUNNER) +elf="$*"

clean:
	rm -rf obj_dir

###############################################################################
