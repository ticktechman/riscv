/*
 *******************************************************************************
 *
 *        filename: wbstage.sv
 *     description:
 *         created: 2026/04/28
 *          author: ticktechman
 *
 *******************************************************************************
 */

`include "rtl/inc/log.svh"

module wbstage (
  input logic clk,
  input logic rst_n,
  input corepkg::mem_ctrl_t ctrl_i,
  output corepkg::wb_ctrl_t ctrl_o
);

  import corepkg::*;

  localparam int REGCNT = 32;
  logic [63:0] regs[REGCNT];

  wb_ctrl_t ctrl;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      ctrl_o <= '0;
    end else begin
      ctrl.we <= 1'b0;
      if (ctrl_i.valid && ctrl_i.reg_write) begin
        if ((int'(ctrl_i.rd)) < REGCNT && (int'(ctrl_i.rd)) > 0) begin
          ctrl.we <= 1'b1;
          ctrl.rd <= ctrl_i.rd;
          unique case (ctrl_i.reg_src)
            0: ctrl.wdata <= ctrl_i.alu_result;
            1: ctrl.wdata <= ctrl_i.mem_result;
          endcase
        end
      end
      ctrl_o <= ctrl;
    end
  end

endmodule

/******************************************************************************/
