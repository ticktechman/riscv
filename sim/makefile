###############################################################################
##
##       filename: makefile
##    description:
##        created: 2026/04/04
##         author: ticktechman
##
###############################################################################
.PHONY: all build test install doc

V_FLAGS = --cc --exe --trace --build
SV_SRCS = top.sv

SIM = obj_dir/Vtop

all: $(SIM)

$(SIM): $(SV_SRCS)
	verilator $(V_FLAGS) $(SV_SRCS) main.cpp --top-module top

clean:
	rm -rf obj_dir

###############################################################################
