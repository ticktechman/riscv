/*
 *******************************************************************************
 *
 *        filename: mini.sv
 *     description: mini verilog.
 *         created: 2026-05-01
 *          author: ticktechman
 *
 *******************************************************************************
 */

// build:  verilator -j 0 --timing --binary --trace -o mini --top-module top mini.sv && ./obj_dir/mini

`timescale 1ns / 100ps

`define COLOR_NONE "\033[0m"
`define COLOR_RED "\033[31m"
`define COLOR_GREEN "\033[32m"
`define COLOR_YELLOW "\033[33m"
`define LOGI(msg) $display("[I|%9t|%m.%0d] %s", $realtime, `__LINE__, msg)
`define LOGW(msg) $display("%s[W|%9t|%m.%0d] %s%s", `COLOR_YELLOW, $realtime, `__LINE__, msg, `COLOR_NONE)
`define LOGE(msg) $display("%s[E|%9t|%m.%0d] %s%s", `COLOR_RED, $realtime, `__LINE__, msg, `COLOR_NONE)

//-------------------------------------
// Testbench
//-------------------------------------
module top ();
  logic clk, rst_n;

  initial begin
    $dumpfile("mini.vcd");
    $dumpvars(0, top);
    $timeformat(-9, 3, "", 9);
  end

  clkgen clock (
    .clk(clk),
    .rst_n(rst_n)
  );

  mini m1 (
    .clk(clk),
    .rst_n(rst_n)
  );

endmodule

//-------------------------------------
// clock gen
//-------------------------------------
module clkgen #(
  parameter COUNTER = 10
) (
  output logic clk,
  output logic rst_n
);
  initial begin
    clk   = 0;
    rst_n = 0;
    #1.5 rst_n = 1;
    repeat (COUNTER) @(negedge clk);
    #0.5 rst_n = 0;
    #0.1 $finish;
  end

  always #1 clk = ~clk;
endmodule

//-------------------------------------
// clock gen
//-------------------------------------
module mini (
  input logic clk,
  input logic rst_n
);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      `LOGW("reset");
    end else begin
      `LOGI("hello");
    end
  end

endmodule

/******************************************************************************/
