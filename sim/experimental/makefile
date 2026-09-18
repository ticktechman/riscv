###############################################################################
##
##       filename: makefile
##    description:
##        created: 2026/09/17
##         author: ticktechman
##
###############################################################################
.PHONY: all build test install doc

VERILATOR := verilator -j 0  --timing --binary --trace --top-module top

all: mini

mini: obj_dir/mini
	@./$<

obj_dir/mini: mini.sv
	@$(VERILATOR) $^ -o $(notdir $@)

clean:
	@rm -rf obj_dir
###############################################################################
