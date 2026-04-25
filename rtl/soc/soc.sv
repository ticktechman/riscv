`include "rtl/inc/log.svh"

module soc #(
  parameter ROM = ""
) (
  input logic clk,
  input logic rst_n
);

  localparam ROM1_BASE_ADDR = 64'h0000_0000_0000_0000;
  localparam ROM1_ADDR_MASK = 64'h0000_0000_0000_00FF;
  localparam RESET_ADDR = 64'h0000_0000_0000_0000;

  logic [63:0] instr_addr;
  logic [31:0] instr;
  logic rom1_error;
  logic rom1_ready;

  logic rom1_req;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      instr_addr = RESET_ADDR;
      `LOGI("soc reset");
    end else begin
      instr_addr <= instr_addr + 4;
    end
  end

  assign rom1_req = ((instr_addr & ~ROM1_ADDR_MASK) == ROM1_BASE_ADDR);
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

  uart uart1 (
    .clk(clk),
    .rst_n(rst_n)
  );

endmodule
