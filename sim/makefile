###############################################################################
##
##       filename: makefile
##    description:
##        created: 2026/04/04
##         author: ticktechman
##
###############################################################################
.PHONY: all build test install doc hawks

HEX_FILES := $(wildcard $(CURDIR)/riscv-tests/*.hex)
HEX_FPU := $(shell find fpu-test/testcases/build -name *.hex | sort)

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


hawks: obj_dir/hawks
hawks.test: $(HEX_FILES:.hex=.run)
hawks.fpu: $(HEX_FPU:.hex=.fputest)
hawks.one: obj_dir/hawks
	@$< +verilator+quiet +elf="./fpu-test/testcases/build/rup/f64_add"

obj_dir/hawks: hawks.sv hawks.cpp
	@verilator $(HAWKS_FLAGS) --trace $^ --top-module top -o $(shell basename $@)


%.fputest: obj_dir/hawks
	@printf "%45s " "$(patsubst %.fputest,%,$@): "
	-@obj_dir/hawks +verilator+quiet +elf="$(patsubst %.fputest,%,$@)"

%.run: obj_dir/hawks
	@printf "%28s" "$(shell basename $*): "
	-@obj_dir/hawks +verilator+quiet +elf="riscv-tests/$(shell basename $*)"

$(SIM): $(SV_SRCS) main.cpp
	verilator $(V_FLAGS) $(SV_SRCS) main.cpp --top-module top

run: $(SIM)
	@$(SIM) +verilator+quiet

clean:
	rm -rf obj_dir

###############################################################################
