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

`define COLOR_NONE "\033[0m"
`define COLOR_RED "\033[31m"
`define COLOR_GREEN "\033[32m"
`define COLOR_YELLOW "\033[33m"
`define LOGI(msg) $display("[I|%9t|%m.%0d] %s", $realtime, `__LINE__, msg)
`define LOGW(msg) $display("%s[W|%9t|%m.%0d] %s%s", `COLOR_YELLOW, $realtime, `__LINE__, msg, `COLOR_NONE)
`define LOGE(msg) $display("%s[E|%9t|%m.%0d] %s%s", `COLOR_RED, $realtime, `__LINE__, msg, `COLOR_NONE)

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
  parameter COUNTER = 20
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

//------------------------------------
// address space
//------------------------------------
typedef logic [63:0] reg_t;
typedef logic [63:0] addr_t;
typedef logic [3:0] port_idx_t;

typedef struct packed {
  port_idx_t idx;
  addr_t start_addr;
  addr_t end_addr;
} addr_space_t;

//------------------------------------
// data interface
//------------------------------------
interface xbar_intf;
  logic valid, ready, we, error;
  addr_t addr;
  reg_t rdata, wdata;

  modport master(input ready, rdata, error, output valid, we, addr, wdata);
  modport slave(output ready, rdata, error, input valid, we, addr, wdata);
endinterface

//------------------------------------
// xbar demux
//------------------------------------
module xdmux #(
  parameter int MN = 2
) (
  input logic          clk,
  input logic          rst_n,
  input logic [MN-1:0] requesters,

  output port_idx_t winner
);

  typedef logic [$clog2(MN)-1:0] pointer_t;

  pointer_t last_pos_r, last_pos;
  always_comb begin
    last_pos = last_pos_r;
    // `LOGI($sformatf("last:%0d", last_pos));
    if (|requesters) begin
      last_pos = last_pos_r + 1;
      for (int i = 0; i < MN; i++) begin
        if (requesters[last_pos]) begin
          winner = port_idx_t'(last_pos);
          break;
        end
        last_pos++;
      end
    end else begin
      winner = port_idx_t'(MN);
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      last_pos_r <= '1;
    end else begin
      last_pos_r <= last_pos;
    end
  end

endmodule

//------------------------------------
// routing master request to one slave
//------------------------------------
module xrouter #(
  parameter int ASN = 3
) (
  input logic  clk,
  input logic  rst_n,
  input logic  valid,
  input addr_t addr,

  input  addr_space_t spaces[ASN],
  output port_idx_t   idx
);

  `define addr_hit(space) (valid && addr >= space.start_addr && addr <= space.end_addr)
  always_comb begin
    idx = port_idx_t'(ASN);
    foreach (spaces[i]) begin
      if (`addr_hit(spaces[i])) begin
        idx = port_idx_t'(i);
        break;
      end
    end
  end
endmodule

//------------------------------------
// xbar
//------------------------------------
module xbar #(
  parameter int MN = 2,
  parameter int SN = 2
) (
  input logic clk,
  input logic rst_n,

  addr_space_t     addrspaces[SN],
  xbar_intf.slave  msts      [MN],
  xbar_intf.master slvs      [SN]
);
  `define REQ_OP(d, s, op) \
    op d.valid = s.valid; \
    op d.we = s.we; \
    op d.addr = s.addr; \
    op d.wdata = s.wdata;

  `define RSP_OP(d, s, op) \
    op d.ready = s.ready; \
    op d.error = s.error; \
    op d.rdata = s.rdata;

  `define REQ_ASSIGN(d, s) `REQ_OP(d, s, assign)
  `define RSP_ASSIGN(d, s) `RSP_OP(d, s, assign)

  typedef struct packed {
    logic  valid, we;
    addr_t addr;
    reg_t  wdata;
  } req_t;

  typedef struct packed {
    logic ready, error;
    reg_t rdata;
  } rsp_t;

  typedef logic [MN-1:0] requester_t;
  typedef logic [$clog2(SN)-1:0] slv_idx_t;
  typedef logic [$clog2(MN)-1:0] mst_idx_t;

  req_t mst_req[MN], slv_req[SN];
  rsp_t mst_rsp[MN], slv_rsp[SN];
  port_idx_t selected_slvs[MN];
  port_idx_t selected_msts[SN];
  requester_t requesters[SN];

  // connect signals of master and slave
  for (genvar s = 0; s < MN; s++) begin : master_xbar
    `REQ_ASSIGN(mst_req[s], msts[s])
    `RSP_ASSIGN(msts[s], mst_rsp[s])
    xrouter #(
      .ASN(SN)
    ) router (
      .clk,
      .rst_n,
      .spaces(addrspaces),
      .valid(mst_req[s].valid),
      .addr(mst_req[s].addr),
      .idx(selected_slvs[s])
    );
  end
  for (genvar s = 0; s < SN; s++) begin : slave_xbar
    `REQ_ASSIGN(slvs[s], slv_req[s])
    `RSP_ASSIGN(slv_rsp[s], slvs[s])
    xdmux #(
      .MN(MN)
    ) demux (
      .clk,
      .rst_n,
      .requesters(requesters[s]),
      .winner(selected_msts[s])
    );
  end

  // mux masters to slave
  always_comb begin
    slv_idx_t idx;
    foreach (selected_slvs[i]) begin
      idx = slv_idx_t'(selected_slvs[i]);
      if (selected_slvs[i] != port_idx_t'(SN)) begin
        requesters[idx][i] = 1'b1;
      end else begin
        requesters[idx][i] = 1'b0;
      end
    end
  end

  // setup channels for M & S
  always_comb begin : MS
    slv_idx_t sid;
    mst_idx_t mid;
    foreach (selected_msts[i]) begin : M_S
      mid = mst_idx_t'(selected_msts[i]);
      sid = slv_idx_t'(i);
      if (selected_msts[i] != port_idx_t'(MN)) begin : MS
        // `LOGI($sformatf("M(%0d) <-> S(%0d)", mid, sid));
        slv_req[sid] = mst_req[mid];
        slv_req[sid].addr -= addrspaces[sid].start_addr;
      end else begin
        slv_req[sid] = '0;
      end
    end
  end
  always_comb begin
    slv_idx_t sid;
    mst_idx_t mid;
    foreach (mst_rsp[i]) mst_rsp[i] = '0;
    foreach (selected_msts[i]) begin
      mid = mst_idx_t'(selected_msts[i]);
      sid = slv_idx_t'(i);
      if (selected_msts[i] != port_idx_t'(MN)) begin
        mst_rsp[mid] = slv_rsp[sid];
      end
    end
  end

endmodule

//------------------------------------
// masters
//------------------------------------
module cpu (
  input logic clk,
  input logic rst_n,
  input logic valid,
  input reg_t start_addr,

  xbar_intf.master xif
);

  typedef enum {
    IDLE,
    WORK,
    DONE
  } state_e;

  state_e state;
  always_comb begin : fsm
    addr_t addr;
    unique case (state)
      IDLE: addr = start_addr;
      WORK: begin
        xif.valid = valid;
        xif.addr  = addr;
      end
      DONE: begin
        `LOGW($sformatf("read: %0h", addr));
        xif.valid = 1'b0;
        addr += 8;
      end
      default: ;
    endcase
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= IDLE;
    end else begin
      if (valid) begin
        unique case (state)
          IDLE: state <= WORK;
          WORK: if (xif.ready) state <= DONE;
          DONE: state <= WORK;
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

  xbar_intf.slave xif
);
  localparam int CAP = 1024;
  typedef logic [$clog2(CAP)-1:0] idx_t;

  reg_t mem[CAP];
  idx_t idx;

  always_comb begin
    idx = xif.addr[$clog2(CAP)-1:0];
    xif.rdata = '0;
    xif.error = '0;
    if (xif.valid) begin
      if (~xif.we) begin
        `LOGI($sformatf("READ mem[%0d]=%h", idx, mem[idx]));
        xif.rdata = mem[idx];
      end else begin
        xif.rdata = xif.wdata;
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      foreach (mem[i]) begin
        mem[i] <= reg_t'(i);
      end
    end else begin
      xif.ready = xif.valid;
      if (xif.valid && xif.we) begin
        mem[idx] <= xif.wdata;
        `LOGI($sformatf("mem[%0d]=%h", idx, xif.wdata));
      end
    end
  end

endmodule

//------------------------------------
// main
//------------------------------------
module mini (
  input logic clk,
  input logic rst_n
);

  localparam MN = 2;
  localparam SN = 3;

  localparam addr_space_t mini_spaces[SN] = '{
      '{idx: 0, start_addr: 64'h0001_0000, end_addr: 64'h0001_ffff},
      '{idx: 1, start_addr: 64'h0002_0000, end_addr: 64'h0002_ffff},
      '{idx: 2, start_addr: 64'h0003_0000, end_addr: 64'h0003_ffff}
  };

  logic valid = '0;

  xbar_intf msts[MN] ();
  xbar_intf slvs[SN] ();

  xbar #(
    .MN(MN),
    .SN(SN)
  ) xbar1 (
    .clk,
    .rst_n,
    .addrspaces(mini_spaces),
    .msts(msts),
    .slvs(slvs)
  );

  cpu cpu1 (
    .clk,
    .rst_n,
    .valid,
    .start_addr(64'h0001_0000),
    .xif(msts[0])
  );

  cpu cpu2 (
    .clk,
    .rst_n,
    .valid,
    .start_addr(64'h0002_0000),
    .xif(msts[1])
  );

  // cpu cpu3 (
  //   .clk,
  //   .rst_n,
  //   .valid,
  //   .start_addr(64'h0001_0000),
  //   .xif(msts[2])
  // );
  // cpu cpu4 (
  //   .clk,
  //   .rst_n,
  //   .valid,
  //   .start_addr(64'h0001_0000),
  //   .xif(msts[3])
  // );

  sram sram1 (
    .clk,
    .rst_n,
    .xif(slvs[0])
  );
  sram sram2 (
    .clk,
    .rst_n,
    .xif(slvs[1])
  );
  sram sram3 (
    .clk,
    .rst_n,
    .xif(slvs[2])
  );

  int counter = 0;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
    end else begin
      counter++;
      valid = counter < 14;
    end
  end

endmodule

/******************************************************************************/
