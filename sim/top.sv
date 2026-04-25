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

endmodule
