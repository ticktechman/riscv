module top (
  input logic clk,
  input logic rst_n
);

  soc #(
      .ROM("./hello/hello.hex")
  ) soc1 (
    .clk(clk),
    .rst_n(rst_n)
  );

  // always_ff @(posedge clk or negedge rst_n) begin
  //   if (!rst_n) begin
  //   end else begin
  //     $write("end\n");
  //     $finish;
  //   end
  // end
  // ;

endmodule
