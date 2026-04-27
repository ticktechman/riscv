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

module exstage (
  input logic clk,
  input logic rst_n,
  input corepkg::id_ctrl_t id_ctrl_i
);

  import corepkg::*;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
    end else begin
      case (id_ctrl_i.sys_op)
        SYS_EBREAK: $finish;
        default: ;
      endcase
    end
  end

endmodule

/******************************************************************************/
