`include "rtl/inc/log.svh"

module soc #(
  parameter ROM = ""
) (
  input logic clk,
  input logic rst_n
);

  localparam ROM1_BASE_ADDR = 64'h0000_0000_0000_0000;
  localparam ROM1_ADDR_MASK = 64'h0000_0000_0000_0FFF;
  localparam RESET_ADDR = 64'h0000_0000_0000_0000;

  logic [63:0] instr_addr;
  logic [31:0] instr;
  logic rom1_error;
  logic rom1_ready;
  logic instr_req;

  logic rom1_req;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      `LOGI("soc reset");
    end
  end

  assign rom1_req = instr_req && ((instr_addr & ~ROM1_ADDR_MASK) == ROM1_BASE_ADDR);
  bootrom #(
    .HEXFILE(ROM),
    .DEPTH(16)
  ) bootrom1 (
    .clk(clk),
    .rst_n(rst_n),
    .req_i(rom1_req),
    .addr_i(instr_addr - ROM1_BASE_ADDR),
    .instr_o(instr),
    .ready_o(rom1_ready),
    .error_o(rom1_error)
  );

  core core1 (
    .clk(clk),
    .rst_n(rst_n),
    .instr_i(instr),
    .instr_error_i(rom1_error),
    .instr_ready_i(rom1_ready),
    .instr_addr_o(instr_addr),
    .instr_req_o(instr_req)
  );

  uart uart1 (
    .clk(clk),
    .rst_n(rst_n)
  );

endmodule
