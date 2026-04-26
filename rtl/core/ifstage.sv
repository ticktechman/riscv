/*
 *******************************************************************************
 *
 *        filename: ifstage.sv
 *     description: instruction fetch
 *         created: 2026/04/26
 *          author: ticktechman
 *
 *******************************************************************************
 */
module ifstage (
  input logic clk,
  input logic rst_n,
  input logic instr_error_i,
  input logic instr_ready_i,
  output logic [63:0] instr_addr_o,
  output logic instr_req_o
);

  localparam RESET_ADDR = 64'h0000_0000_0000_0000;

  logic [63:0] instr_addr;
  logic instr_req;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      instr_addr <= RESET_ADDR;
      instr_req  <= 1'b0;
    end else begin
      if (instr_ready_i) begin
        instr_addr <= instr_addr + 4;
      end
      instr_req <= 1'b1;
    end
  end

  assign instr_addr_o = instr_addr;
  assign instr_req_o  = instr_req;

endmodule

/******************************************************************************/
