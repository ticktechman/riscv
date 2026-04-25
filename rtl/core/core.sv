module core (
  input logic clk,
  input logic rst_n
);
  always_ff @(posedge clk or negedge rst_n) begin
  end
  ;
endmodule
