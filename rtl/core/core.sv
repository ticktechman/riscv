/*
 *******************************************************************************
 *
 *        filename: core.sv
 *     description:
 *         created: 2026/04/26
 *          author: ticktechman
 *
 *******************************************************************************
 */

module core (
  input logic clk,
  input logic rst_n,

  // instruction interface
  input logic [31:0] instr_i,
  input logic instr_error_i,
  input logic instr_ready_i,
  output logic [63:0] instr_addr_o,
  output logic instr_req_o
);

  ifstage ifstage1 (
    .clk(clk),
    .rst_n(rst_n),
    .instr_error_i(instr_error_i),
    .instr_ready_i(instr_ready_i),
    .instr_addr_o(instr_addr_o),
    .instr_req_o(instr_req_o)
  );

  logic [4:0] rs1, rs2, rd;
  logic [63:0] imm;
  logic iderror;
  idstage idstage1 (
    .clk(clk),
    .rst_n(rst_n),
    .instr_i(instr_i),
    .rs1_o(rs1),
    .rs2_o(rs2),
    .rd_o(rd),
    .imm_o(imm),
    .error_o(iderror)
  );

endmodule

/******************************************************************************/
