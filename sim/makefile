###############################################################################
##
##       filename: makefile
##    description:
##        created: 2026/04/04
##         author: ticktechman
##
###############################################################################
.PHONY: all build test install doc

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

$(SIM): $(SV_SRCS) main.cpp
	verilator $(V_FLAGS) $(SV_SRCS) main.cpp --top-module top

obj_dir/Vmini: minisoc.sv
	@verilator --timing --binary --trace minisoc.sv --top-module mini

run: $(SIM)
	@$(SIM) +verilator+quiet

clean:
	rm -rf obj_dir

###############################################################################
