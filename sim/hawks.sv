/*
 *******************************************************************************
 *
 *        filename: hawks.sv
 *     description:
 *         created: 2026/05/30
 *          author: ticktechman
 *
 *******************************************************************************
 */
/*
- top
    - clkgen
    - soc
        - ifu
        - idu
        - exu
            - alu
            - mul
            - div
        - lsu
            - sram
            - rom
            - scoreboard(tohost)
        - rfu
        - bus
        - mmu
        - csr
        - raptor
*/

`timescale 1ns / 100ps

`define DEBUG_LOG
`ifdef DEBUG_LOG
`define LOGI(msg) $display("[I|%9t|%m] %s", $realtime, msg)
`define LOGW(msg) $display("[W|%9t|%m] %s", $realtime, msg)
`define LOGE(msg) $display("[E|%9t|%m] %s", $realtime, msg)
`else
`define LOGI(msg)
`define LOGW(msg)
`define LOGE(msg)
`endif

`define COLOR_NONE "\033[0m"
`define RED "\033[31m"
`define GREEN "\033[32m"
`define YELLOW "\033[33m"

//------------------------------------
// types and structures
//------------------------------------
package hawks;
  localparam int unsigned MAXMASTER = 2;
  localparam int unsigned MAXSLV = 3;

  typedef logic [63:0] reg_t;
  typedef logic [63:0] addr_t;
  typedef struct packed {
    addr_t BASE;
    addr_t END;
  } mmap_t;

  parameter mmap_t maping[MAXSLV] = '{
      '{BASE: addr_t'('h8000_0000), END: addr_t'('h8000_1fff)},
      '{BASE: addr_t'('h8000_2000), END: addr_t'('h8000_2fff)},
      '{BASE: addr_t'('h8000_3000), END: addr_t'('h8000_3fff)}
  };

  typedef enum {
    S8,
    U8,
    S16,
    U16,
    S32,
    U32,
    US64
  } mtype_e;


  typedef struct packed {
    logic   valid;
    logic   we;
    addr_t  addr;
    mtype_e mtype;
    reg_t   wd;
  } request_t;

  typedef struct packed {
    logic ready;
    logic error;
    reg_t rd;
  } response_t;

endpackage
import hawks::*;

//------------------------------------
// interfaces
//------------------------------------
interface memif;
  logic valid, ready, error, we;
  mtype_e mtype;
  addr_t addr;
  reg_t rd, wd;

  modport master(input ready, error, rd, output valid, we, addr, mtype, wd);
  modport slave(output ready, error, rd, input valid, we, addr, mtype, wd);
endinterface


//------------------------------
// top entry module (zero args)
//------------------------------
module top ();
  logic clk, rst_n, intr;

  initial begin
    $dumpfile("mini.vcd");
    $dumpvars(0, top);
    $timeformat(-9, 3, "", 9);
    intr = 1'b0;
    // #1000 intr = 1'b1;
  end

  clkgen #(
    .COUNTER(20)
  ) clock (
    .clk(clk),
    .rst_n(rst_n)
  );

  soc soc1 (
    .clk(clk),
    .rst_n(rst_n),
    .intr_i(intr)
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
    #2 rst_n = 1;
    repeat (COUNTER) @(negedge clk);
    #0.5 rst_n = 0;
    $write($sformatf("%sTIMEOUT%s", `YELLOW, `COLOR_NONE));
    #0.1 $finish;
  end

  always #1 clk = ~clk;
endmodule


//-------------------------------------
// soc include (pipeline 5 stages, mmu, csr, ...)
//-------------------------------------
module soc (
  input logic clk,
  input logic rst_n,
  input logic intr_i
);

  memif master_ports[MAXMASTER] ();
  memif slave_ports[MAXSLV] ();

  bus #(
    .mmaping(maping)
  ) bus1 (
    .clk(clk),
    .rst_n(rst_n),
    .masters(master_ports),
    .slaves(slave_ports)
  );

  ifu ifu1 (
    .clk(clk),
    .rst_n(rst_n),
    .mif(master_ports[0].master)
  );

  lsu lsu1 (
    .clk(clk),
    .rst_n(rst_n),
    .mif(master_ports[1].master)
  );

  sram sram1 (
    .clk(clk),
    .rst_n(rst_n),
    .mif(slave_ports[0].slave)
  );

  rom rom1 (
    .clk(clk),
    .rst_n(rst_n),
    .mif(slave_ports[1].slave)
  );

  scoreboard SB (
    .clk(clk),
    .rst_n(rst_n),
    .mif(slave_ports[2].slave)
  );

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
    end else begin
      `LOGI("tick");
    end
  end

endmodule

//------------------------------------
// bus related types and module
//------------------------------------
// shared single channel crossbar
module bus #(
  parameter mmap_t mmaping[MAXSLV]
) (
  input logic clk,
  input logic rst_n,
  memif.slave masters[MAXMASTER],
  memif.master slaves[MAXSLV]
);
  request_t mreq[MAXMASTER];
  response_t mrsp[MAXMASTER];
  request_t sreq[MAXSLV];
  response_t srsp[MAXSLV];


  generate
    for (genvar m = 0; m < MAXMASTER; m++) begin : master_flatten
      assign mreq[m].valid = masters[m].valid;
      assign mreq[m].addr = masters[m].addr;
      assign mreq[m].we = masters[m].we;
      assign mreq[m].wd = masters[m].wd;
      assign masters[m].ready = mrsp[m].ready;
      assign masters[m].error = mrsp[m].error;
      assign masters[m].rd = mrsp[m].rd;
    end

    for (genvar s = 0; s < MAXSLV; s++) begin : slave_flatten
      assign slaves[s].valid = sreq[s].valid;
      assign slaves[s].addr = sreq[s].addr;
      assign slaves[s].we = sreq[s].we;
      assign slaves[s].wd = sreq[s].wd;
      assign srsp[s].ready = slaves[s].ready;
      assign srsp[s].error = slaves[s].error;
      assign srsp[s].rd = slaves[s].rd;
    end
  endgenerate

  // choose one master
  logic [MAXMASTER-1:0] reqs;
  int master_selected;
  always_comb begin
    reqs = '0;
    master_selected = -1;
    foreach (mreq[i]) begin
      if (mreq[i].valid) begin
        master_selected = i;
        break;
      end
    end
  end

  // choose slave by master reqeust addr
  int slave_selected;
  addr_t addr;
  always_comb begin
    slave_selected = -1;
    addr = 0;
    if (master_selected != -1) begin
      addr = mreq[master_selected].addr;
      foreach (mmaping[i]) begin
        if (addr >= mmaping[i].BASE && addr <= mmaping[i].END) begin
          slave_selected = i;
          addr = addr - mmaping[i].BASE;
          break;
        end
      end
    end
  end

  // connect master and slave on both req and resp
  always_comb begin
    foreach (sreq[i]) begin
      sreq[i] = '0;
    end
    foreach (mrsp[i]) begin
      mrsp[i] = '0;
    end

    if (master_selected != -1 && slave_selected != -1) begin
      sreq[slave_selected] = mreq[master_selected];
      sreq[slave_selected].addr = addr;
      mrsp[master_selected] = srsp[slave_selected];
    end
  end

endmodule

//------------------------------------
// ifu
//------------------------------------
module ifu (
  input logic clk,
  input logic rst_n,
  memif.master mif
);
  typedef enum {
    IDLE,
    FETCH
  } state_e;

  state_e state;
  logic fetch;

  addr_t addr = addr_t'('h8000_0000);
  addr_t next;

  always_comb begin
    next = addr + 1;
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= IDLE;
      fetch <= 1;
    end else begin
      if (fetch) begin
        `LOGI($sformatf("state:%0d addr=%h", state, addr));
        unique case (state)
          IDLE: begin
            mif.valid <= 1;
            mif.addr  <= addr;
            mif.we    <= 0;
            mif.mtype <= US64;
            addr <= next;
            state <= FETCH;
          end
          FETCH: begin
            if (mif.ready) begin
              mif.valid <= 0;
              `LOGI($sformatf("data readed: %0d", mif.rd));
              state <= IDLE;
              fetch <= 0;
            end
          end
          default: ;
        endcase
      end
    end
  end

endmodule

//------------------------------------
// lsu
//------------------------------------
module lsu (
  input logic clk,
  input logic rst_n,
  memif.master mif
);
  typedef enum {
    IDLE,
    FETCH
  } state_e;

  state_e state;
  logic fetch;

  addr_t addr = addr_t'('h8000_3000);
  addr_t next;

  always_comb begin
    next = addr + 1;
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= IDLE;
      fetch <= 1;
    end else begin
      if (fetch) begin
        `LOGI($sformatf("state:%0d addr=%h", state, addr));
        unique case (state)
          IDLE: begin
            mif.valid <= 1;
            mif.addr  <= addr;
            mif.we    <= 1;
            mif.wd    <= 0;
            mif.mtype <= US64;
            addr <= next;
            state <= FETCH;
          end
          FETCH: begin
            if (mif.ready) begin
              mif.valid <= 0;
              `LOGI($sformatf("data readed: %0d", mif.rd));
              state <= IDLE;
              fetch <= 0;
            end
          end
          default: ;
        endcase
      end
    end
  end

endmodule

//------------------------------------
// sram
//------------------------------------
module sram (
  input logic clk,
  input logic rst_n,
  memif.slave mif
);

  localparam addr_t MAX = 128;
  wire [$clog2(MAX)-1:0] idx = mif.addr[$clog2(MAX)-1:0];
  reg_t m[MAX];
  initial begin
    foreach (m[i]) begin
      m[i] = 64'(i + 10);
    end
  end

  // bypass RAW
  always_comb begin
    mif.ready = 1'b1;
    if (mif.we && mif.valid) begin
      mif.rd = mif.wd;
    end else begin
      mif.rd = m[idx];
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
    end else begin
      if (mif.valid && mif.we) begin
        m[idx] = mif.wd;
      end
    end
  end

endmodule

//------------------------------------
// rom
//------------------------------------
module rom (
  input logic clk,
  input logic rst_n,
  memif.slave mif
);
  localparam addr_t MAX = 128;
  wire [$clog2(MAX)-1:0] idx = mif.addr[$clog2(MAX)-1:0];
  reg_t m[MAX];
  initial begin
    foreach (m[i]) begin
      m[i] = 64'(i + 190);
    end
  end

  // bypass RAW
  always_comb begin
    mif.ready = 1'b1;
    if (mif.we && mif.valid) begin
      mif.rd = mif.wd;
    end else begin
      mif.rd = m[idx];
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
    end else begin
      if (mif.valid && mif.we) begin
        m[idx] = mif.wd;
      end
    end
  end

endmodule

//------------------------------------
// scoreboard
//------------------------------------
module scoreboard (
  input logic clk,
  input logic rst_n,
  memif.slave mif
);
  assign mif.ready = 1;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
    end else begin
      if (mif.valid && mif.we) begin
        if (mif.wd == 0) begin
          $write("%sPASS%s", `GREEN, `COLOR_NONE);
        end else begin
          $write("%sFAIL:%0d%s", `RED, mif.wd, `COLOR_NONE);
        end
        $finish(0);
      end
    end
  end

endmodule

/******************************************************************************/
