/*
 *******************************************************************************
 *
 *        filename: idstage.sv
 *     description:
 *         created: 2026/04/26
 *          author: ticktechman
 *
 *******************************************************************************
 */

module idstage (
  input logic clk,
  input logic rst_n,
  input logic [31:0] instr_i,

  output logic [4:0] rs1_o,
  output logic [4:0] rs2_o,
  output logic [4:0] rd_o,
  output logic [63:0] imm_o,
  output logic error_o
);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
    end else begin
    end
  end

endmodule

/******************************************************************************/
