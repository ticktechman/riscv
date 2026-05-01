/*
 *******************************************************************************
 *
 *        filename: exstage.sv
 *     description:
 *         created: 2026/04/27
 *          author: ticktechman
 *
 *******************************************************************************
 */

`include "rtl/inc/log.svh"

module exstage (
  input logic clk,
  input logic rst_n,
  input logic [4:0] rs1_i,
  input logic [4:0] rs2_i,
  input logic [4:0] rd_i,
  input logic [63:0] r1_i,
  input logic [63:0] r2_i,
  input logic [63:0] imm_i,
  input logic [63:0] pc_i,
  input corepkg::id_ctrl_t ctrl_i,
  output corepkg::ex_ctrl_t ctrl_o
);

  import corepkg::*;

  ex_ctrl_t ctrl;

  logic [63:0] op1 = 64'b0;
  logic [63:0] op2 = 64'b0;

  function void exec_alu();
    `LOGI("exec alu");
    op1 = ctrl_i.op1 == OP1_RS1 ? r1_i : pc_i;
    op2 = ctrl_i.op2 == OP2_RS2 ? r2_i : imm_i;
    case (ctrl_i.alu_op)
      ALU_ADD: ctrl.alu_result = op1 + op2;
      ALU_SUB: `LOGI("ALU_SUB");
      default: ;
    endcase
    ctrl.reg_src = 0;
  endfunction

  function void exec_sys();
    `LOGI("exec sys");
    case (ctrl_i.sys_op)
      SYS_EBREAK: $finish;
      default: ;
    endcase
  endfunction

  function void exec_fence();
    `LOGI("exec fence");
    case (ctrl_i.fence_op)
      default: ;
    endcase
  endfunction

  function void exec_loadstore();
    `LOGI("exec_loadstore");
    case (ctrl_i.lsu_op)
      default: ;
    endcase
  endfunction

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      ctrl_o <= '0;
    end else begin
      ctrl <= '0;
      if (ctrl_i.valid) begin
        ctrl.valid <= 1;
        if (ctrl_i.alu_op != ALU_NONE) begin
          exec_alu();
        end
        if (ctrl_i.sys_op != SYS_NONE) begin
          exec_sys();
        end
        if (ctrl_i.fence_op != FENCE_NONE) begin
          exec_fence();
        end
        if (ctrl_i.lsu_op != LSU_NONE) begin
          exec_loadstore();
        end
        ctrl.reg_write <= ctrl_i.reg_write;
        ctrl.rd <= rd_i;
      end
      ctrl_o <= ctrl;
    end
  end

endmodule

/******************************************************************************/
