module top (
    input logic clk,
    input logic rst_n
);
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
    end else begin
      $write("end\n");
      $finish;
    end
  end
  ;

endmodule
