module soc #(
    parameter ROM = ""
) (
  input logic clk,
  input logic rst_n
);

  bootrom #(
      .HEX_FILE(ROM)
  ) hello (
    .clk(clk),
    .rst_n(rst_n)
  );

  uart uart1 (
    .clk(clk),
    .rst_n(rst_n)
  );

endmodule
