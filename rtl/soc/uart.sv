`include "rtl/inc/log.svh"

module uart (
  input logic clk,
  input logic rst_n
);
  initial begin
    `LOGI("UART init");
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
    end else begin
    end
  end
  ;
endmodule
