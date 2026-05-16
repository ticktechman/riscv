/*
 *******************************************************************************
 *
 *        filename: mini.sv
 *     description: mini verilog.
 *         created: 2026-05-01
 *          author: ticktechman
 *
 *******************************************************************************
 */

// build:  verilator -j 0 --timing --binary --trace -o mini --top-module top mini.sv && ./obj_dir/mini

`timescale 1ns / 100ps

`define LOGI(msg) $display("[I|%9t|%m] %s", $realtime, msg)
`define LOGW(msg) $display("[W|%9t|%m] %s", $realtime, msg)
`define LOGE(msg) $display("[E|%9t|%m] %s", $realtime, msg)

//-------------------------------------
// Testbench
//-------------------------------------
module top ();
  logic clk, rst_n;

  initial begin
    $dumpfile("mini.vcd");
    $dumpvars(0, top);
    $timeformat(-9, 3, "", 9);
  end

  clkgen clock (
    .clk(clk),
    .rst_n(rst_n)
  );

  mini m1 (
    .clk(clk),
    .rst_n(rst_n)
  );

endmodule

//-------------------------------------
// clock gen
//-------------------------------------
module clkgen #(
  parameter COUNTER = 10
) (
  output logic clk,
  output logic rst_n
);
  initial begin
    clk   = 0;
    rst_n = 0;
    #1.5 rst_n = 1;
    repeat (COUNTER) @(negedge clk);
    #0.5 rst_n = 0;
    #0.1 $finish;
  end

  always #1 clk = ~clk;
endmodule

//-------------------------------------
// clock gen
//-------------------------------------
module mini (
  input logic clk,
  input logic rst_n
);

  typedef struct packed {
    logic         SD;              // [63] Dirty state
    logic [62:43] reserved_62_43;  // [62:43] WPRI
    logic         MDT;             // [42] M-mode Trap Disable
    logic         MPELP;           // [41] M-mode Previous Landing Pad
    logic         reserved_40;     // [40] WPRI
    logic         MPV;             // [39] M-mode Previous Virtualization
    logic         GVA;             // [38] Guest Virtual Address
    logic         MBE;             // [37] Memory Privilege Big Endian
    logic         SBE;             // [36] Supervisor Big Endian
    logic [35:34] SXL;             // [35:34] Supervisor Mode XLEN
    logic [33:32] UXL;             // [33:32] User Mode XLEN
    logic [31:25] reserved_31_25;  // [31:25] WPRI
    logic         SDT;             // [24] Store/Load Trap (or SDT)
    logic         SPELP;           // [23] Supervisor Previous Landing Pad
    logic         TSR;             // [22] Trap SRET
    logic         TW;              // [21] Timeout Wait
    logic         TVM;             // [20] Trap Virtual Memory
    logic         MXR;             // [19] Make eXecutable Readable
    logic         SUM;             // [18] permit Supervisor User Memory access
    logic         MPRV;            // [17] Modify PRiVilege
    logic [16:15] XS;              // [16:15] Extension State
    logic [14:13] FS;              // [14:13] Floating-point Unit State
    logic [12:11] MPP;             // [12:11] Machine Previous Privilege mode
    logic [10:9]  VS;              // [10:9] Vector Extension State (Added!)
    logic         SPP;             // [8] Supervisor Previous Privilege mode
    logic         MPIE;            // [7] Machine Previous Interrupt Enable
    logic         UBE;             // [6] User Mode Big Endian
    logic         SPIE;            // [5] Supervisor Previous Interrupt Enable
    logic         reserved_4;      // [4] WPRI
    logic         MIE;             // [3] Machine Interrupt Enable
    logic         reserved_2;      // [2] WPRI
    logic         SIE;             // [1] Supervisor Interrupt Enable
    logic         reserved_0;      // [0] WPRI
  } mstatus_rv64_t;

  typedef union packed {
    mstatus_rv64_t fields;  // Access via bit-fields
    logic [63:0]   value;   // Access as a whole 64-bit register
  } mstatus_u;

  mstatus_u ms;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      `LOGW("reset");
      ms.fields <= '{
          MDT: 1,
          MPELP: 1,
          MPV: 1,
          GVA: 1,
          MBE: 1,
          SBE: 1,
          SDT: 1,
          SPELP: 1,
          TSR: 1,
          TW: 1,
          TVM: 1,
          MXR: 1,
          SUM: 1,
          MPRV: 1,
          MPP: 2'b11,
          VS: 2'b11,
          SPP: 1,
          MPIE: 1,
          UBE: 1,
          SPIE: 1,
          MIE: 1,
          SIE: 1,
          default: 0
      };
    end else begin
      `LOGI("hello");
      `LOGI($sformatf("%h", ms.value));
    end
  end

endmodule

/******************************************************************************/
