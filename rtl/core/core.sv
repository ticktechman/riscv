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
  corepkg::id_ctrl_t id_ctrl;
  idstage idstage1 (
    .clk(clk),
    .rst_n(rst_n),
    .instr_i(instr_i),
    .instr_ready_i(instr_ready_i),
    .rs1_o(rs1),
    .rs2_o(rs2),
    .rd_o(rd),
    .imm_o(imm),
    .ctrl_o(id_ctrl)
  );

  corepkg::ex_ctrl_t ex_ctrl;
  exstage exstage1 (
    .clk(clk),
    .rst_n(rst_n),
    .rs1_i(rs1),
    .rs2_i(rs2),
    .rd_i(rd),
    .r1_i(r1),
    .r2_i(r2),
    .pc_i(instr_addr_o),
    .imm_i(imm),
    .ctrl_i(id_ctrl),
    .ctrl_o(ex_ctrl)
  );

  corepkg::mem_ctrl_t mem_ctrl;
  memstage memstage1 (
    .clk(clk),
    .rst_n(rst_n),
    .ctrl_i(ex_ctrl),
    .ctrl_o(mem_ctrl)
  );

  logic [63:0] wdata;
  logic we;
  corepkg::wb_ctrl_t wb_ctrl;
  wbstage wbstage1 (
    .clk(clk),
    .rst_n(rst_n),
    .ctrl_i(mem_ctrl),
    .ctrl_o(wb_ctrl)
  );

  logic [63:0] r1, r2;
  regfile rfile1 (
    .clk(clk),
    .rst_n(rst_n),
    .r1_i(rs1),
    .r2_i(rs2),
    .r1_o(r1),
    .r2_o(r2),
    .we_i(wb_ctrl.we),
    .rd_i(wb_ctrl.rd),
    .wdata_i(wb_ctrl.wdata)
  );

endmodule

/******************************************************************************/
