/*
 *******************************************************************************
 *
 *        filename: memstage.sv
 *     description:
 *         created: 2026/04/28
 *          author: ticktechman
 *
 *******************************************************************************
 */

`include "rtl/inc/log.svh"

module memstage (
  input logic clk,
  input logic rst_n,
  input corepkg::ex_ctrl_t ctrl_i,
  output corepkg::mem_ctrl_t ctrl_o
);

  import corepkg::*;
  mem_ctrl_t ctrl;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      ctrl_o <= '0;
    end else begin
      ctrl <= '0;
      if (ctrl_i.valid) begin
        ctrl.valid <= 1'b1;
        ctrl.alu_result <= ctrl_i.alu_result;
        ctrl.reg_src <= ctrl_i.reg_src;
        ctrl.reg_write <= ctrl_i.reg_write;
        ctrl.rd <= ctrl_i.rd;
      end
      ctrl_o <= ctrl;
    end
  end

endmodule

/******************************************************************************/
