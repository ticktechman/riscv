`include "rtl/inc/log.svh"

module bootrom #(
  parameter string HEXFILE = "",
  parameter int unsigned DEPTH = 64
) (
  input logic clk,
  input logic rst_n,

  // rom access interface
  input logic req_i,
  input logic [63:0] addr_i,
  output logic [31:0] instr_o,
  output logic ready_o,
  output logic error_o
);

  localparam [63:0] ROMSIZE = DEPTH * 4;
  localparam int ROMIDX = $clog2(DEPTH) + 1;
  logic ready;
  logic [31:0] instr;

  // load hex
  logic [31:0] rom[DEPTH];
  initial begin
    $readmemh(HEXFILE, rom);
    `LOGI($sformatf("bootrom readed from %s", HEXFILE));
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      ready   <= 1'b0;
      instr   <= 32'b0;
      error_o <= 1'b0;
    end else begin
      if (req_i) begin
        if (addr_i > ROMSIZE) begin
          $finish;
        end else begin
          instr <= rom[addr_i[ROMIDX:2]];
          ready <= 1'b1;
        end
      end else begin
        ready <= 1'b0;
      end
    end
  end
  ;

  assign ready_o = ready;
  assign instr_o = instr;
  assign error_o = 1'b0;

endmodule
