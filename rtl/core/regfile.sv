/*
 *******************************************************************************
 *
 *        filename: regfile.sv
 *     description:
 *         created: 2026/04/28
 *          author: ticktechman
 *
 *******************************************************************************
 */

`include "rtl/inc/log.svh"

module regfile (
  input logic clk,
  input logic rst_n,

  // read inteface
  input  logic [ 4:0] r1_i,
  input  logic [ 4:0] r2_i,
  output logic [63:0] r1_o,
  output logic [63:0] r2_o,

  // write interface
  input logic we_i,
  input logic [4:0] rd_i,
  input logic [63:0] wdata_i
);

  localparam int unsigned REGCNT = 32;
  logic [63:0] regs[REGCNT];

  assign r1_o = regs[r1_i];
  assign r2_o = regs[r2_i];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int i = 0; i < REGCNT; i++) begin
        regs[i] <= '0;
      end
    end else begin
      if (we_i && rd_i > 0 && int'(rd_i) < REGCNT) begin
        regs[rd_i] <= wdata_i;
      end
    end
  end

endmodule
/******************************************************************************/
