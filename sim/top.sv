`timescale 1ns / 1ps
`include "rtl/inc/log.svh"
module top (
  input logic clk,
  input logic rst_n
);

  initial begin
    $timeformat(-9, 3, "", 9);
  end

  // top level hardware instances
  soc #(
    .ROM("./hello/hello.hex")
  ) soc1 (
    .clk(clk),
    .rst_n(rst_n)
  );

endmodule
