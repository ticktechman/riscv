
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
  localparam int ADDR_IDX = $clog2(DEPTH) + 1;

  typedef enum {
    IDLE,
    READ
  } state_t;
  state_t current_state, next_state;

  logic [31:0] rom[DEPTH];

  logic [31:0] instr_r;
  logic ready_r;

  // load hex
  initial begin : bootrom
    $readmemh(HEXFILE, rom);
    `LOGI($sformatf("bootrom loaded from %s", HEXFILE));
  end

  // state machine
  always_comb begin
    case (current_state)
      IDLE: begin
        if (req_i) next_state = READ;
        else next_state = IDLE;
      end
      READ: next_state = IDLE;
      default: next_state = IDLE;
    endcase
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      current_state <= IDLE;
      ready_r       <= 1'b0;
      instr_r       <= 32'b0;
      error_o       <= 1'b0;
    end else begin
      current_state <= next_state;
      ready_r <= 1'b0;
      error_o <= 1'b0;

      if (current_state == READ) begin
        if (addr_i >= ROMSIZE) begin
          error_o <= 1'b1;
          ready_r <= 1'b1;
          `LOGE("Address out of bounds");
          $finish;
        end else begin
          `LOGI($sformatf("addr=%02d instr=%h", addr_i, rom[addr_i[ADDR_IDX:2]]));
          instr_r <= rom[addr_i[ADDR_IDX:2]];
          ready_r <= 1'b1;
        end
      end else begin
        error_o <= 1'b0;
      end
    end
  end

  assign ready_o = ready_r;
  assign instr_o = instr_r;

endmodule
