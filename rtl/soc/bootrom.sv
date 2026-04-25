`include "rtl/inc/log.svh"

module bootrom #(
    parameter HEX_FILE = ""
) (
  input logic clk,
  input logic rst_n
);

  // load hex
  logic [31:0] rom[64];
  initial begin
    $readmemh(HEX_FILE, rom);
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
    end else begin
      `LOGE("bootrom end");
      $finish;
    end
  end
  ;

endmodule
