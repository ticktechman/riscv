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
`timescale 1ns / 100ps

`define DEBUG_LOG
//------------------------------------
// types and structures
//------------------------------------
package hawks;
  localparam int unsigned MASTER_CNT = 2;
  localparam int unsigned SLAVE_CNT = 3;
  localparam addr_t BOOT_ADDR = 64'h8000_0000;

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
  `define COLOR_RED "\033[31m"
  `define COLOR_GREEN "\033[32m"
  `define COLOR_YELLOW "\033[33m"

  typedef logic [63:0] reg_t;
  typedef logic [63:0] addr_t;
  typedef logic [31:0] instr_t;

  typedef struct packed {
    addr_t BASE;
    addr_t END;
  } mmap_t;

  parameter mmap_t maping[SLAVE_CNT] = '{
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
  } datatype_e;

  typedef enum {
    STG_IDLE,
    STG_FETCH,
    STG_DECODE,
    STG_EXEC,
    STG_MEM,
    STG_WB
  } stage_e;

  typedef struct packed {
    logic valid;
    logic we;
    addr_t addr;
    datatype_e dtype;
    reg_t wd;
  } request_t;

  typedef struct packed {
    logic ready;
    logic error;
    reg_t rd;
  } response_t;

  typedef enum logic [63:0] {
    EXC_INSTR_ADDR_MISALIGNED = 64'h0,  // 指令地址未对齐
    EXC_INSTR_ACCESS_FAULT    = 64'h1,  // 取指访问故障
    EXC_ILLEGAL_INSTRUCTION   = 64'h2,  // 非法指令
    EXC_BREAKPOINT            = 64'h3,  // 断点
    EXC_LOAD_ADDR_MISALIGNED  = 64'h4,  // 加载地址未对齐
    EXC_LOAD_ACCESS_FAULT     = 64'h5,  // 加载访问故障
    EXC_STORE_ADDR_MISALIGNED = 64'h6,  // 存储/AMO地址未对齐
    EXC_STORE_ACCESS_FAULT    = 64'h7,  // 存储/AMO访问故障
    EXC_ECALL_U_MODE          = 64'h8,  // U模式环境调用
    EXC_ECALL_S_MODE          = 64'h9,  // S模式环境调用
    EXC_ECALL_M_MODE          = 64'hb,  // M模式环境调用
    EXC_INSTR_PAGE_FAULT      = 64'hc,  // 指令页面错误
    EXC_LOAD_PAGE_FAULT       = 64'hd,  // 加载页面错误
    EXC_STORE_PAGE_FAULT      = 64'hf,  // 存储/AMO页面错误

    INTR_SUPERVISOR_SW  = 64'h8000_0000_0000_0001,  // 监督级软件中断
    INTR_MACHINE_SW     = 64'h8000_0000_0000_0003,  // 机器级软件中断
    INTR_SUPERVISOR_TMR = 64'h8000_0000_0000_0005,  // 监督级定时器中断
    INTR_MACHINE_TMR    = 64'h8000_0000_0000_0007,  // 机器级定时器中断
    INTR_SUPERVISOR_EXT = 64'h8000_0000_0000_0009,  // 监督级外部中断
    INTR_MACHINE_EXT    = 64'h8000_0000_0000_000B   // 机器级外部中断
  } mcause_e;

  typedef struct packed {
    logic    fired;
    mcause_e cause;
    reg_t    eval;
  } exception_t;

endpackage
import hawks::*;

//------------------------------------
// interfaces
//------------------------------------
interface memif;
  logic valid, ready, error, we;
  addr_t addr;
  datatype_e dtype;
  reg_t rd, wd;

  modport master(input ready, error, rd, output valid, we, addr, dtype, wd);
  modport slave(output ready, error, rd, input valid, we, addr, dtype, wd);
endinterface


//------------------------------
// top entry module (zero args)
//------------------------------
module top ();
  logic clk, rst_n, intr;

  initial begin
    $dumpfile("hawks.vcd");
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
    $write($sformatf("%sTIMEOUT%s", `COLOR_YELLOW, `COLOR_NONE));
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

  logic if_ready, id_ready, ex_ready, ls_ready, rf_ready;

  stage_e stage, exc_stage;
  addr_t pc;
  instr_t instr;
  exception_t exc[5];

  memif master_ports[MASTER_CNT] ();
  memif slave_ports[SLAVE_CNT] ();

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
    .mif(master_ports[0].master),
    .valid(stage == STG_FETCH),
    .pc_i(pc),
    .instr_o(instr),
    .ready_o(if_ready),
    .exc_o(exc[1])
  );

  idu idu1 (
    .clk(clk),
    .rst_n(rst_n),
    .valid(stage == STG_DECODE),
    .instr_i(instr),
    .ready_o(id_ready),
    .exc_o(exc[2])
  );

  exu exu1 (
    .clk(clk),
    .rst_n(rst_n),
    .valid(stage == STG_EXEC),
    .ready_o(ex_ready),
    .exc_o(exc[3])
  );

  lsu lsu1 (
    .clk(clk),
    .rst_n(rst_n),
    .mif(master_ports[1].master),
    .ready_o(ls_ready)
  );

  rfu rfu1 (
    .clk(clk),
    .rst_n(rst_n),
    .ready_o(rf_ready)
  );

  rom rom1 (
    .clk(clk),
    .rst_n(rst_n),
    .mif(slave_ports[0].slave)
  );

  sram sram1 (
    .clk(clk),
    .rst_n(rst_n),
    .mif(slave_ports[1].slave)
  );

  scoreboard SB (
    .clk(clk),
    .rst_n(rst_n),
    .mif(slave_ports[2].slave)
  );

  int idx;
  always_comb begin
    exc[0] = '0;
    idx = int'(exc_stage);
    if (exc_stage != STG_IDLE) begin
      exc[0] = exc[idx];
    end
  end
  // pipeline fsm
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      stage <= STG_IDLE;
      pc    <= BOOT_ADDR;
    end else begin
      `LOGI($sformatf("stage:%0d", stage));
      unique case (stage)
        STG_IDLE: begin
          exc_stage <= stage;
          stage <= STG_FETCH;
        end
        STG_FETCH: begin
          if (if_ready) begin
            if (exc[1].fired) begin
              stage <= STG_WB;
              exc_stage <= stage;
            end else begin
              stage <= STG_DECODE;
            end
          end
        end
        STG_DECODE: begin
          if (id_ready) begin
            stage <= STG_EXEC;
            if (exc[2].fired) begin
              stage <= STG_WB;
              exc_stage <= stage;
            end else begin
              stage <= STG_EXEC;
            end
          end
        end
        STG_EXEC: begin
          if (ex_ready) begin
            stage <= STG_MEM;
          end
        end
        STG_MEM: begin
          if (ls_ready) begin
            stage <= STG_WB;
          end
        end
        STG_WB: begin
          if (exc_stage != STG_IDLE) begin
            // TODO handle exception change pc and return to fetch stage
            `LOGI($sformatf("exc fired at stage: %0d cause:%0d", exc_stage, exc[0].cause));
            pc <= pc + 4;
            exc_stage <= STG_IDLE;
            stage <= STG_FETCH;
          end else begin
            if (rf_ready) begin
              stage <= STG_FETCH;
              pc <= pc + 4;
            end
          end
        end
        default: ;
      endcase
    end
  end

endmodule

//------------------------------------
// bus related types and module
//------------------------------------
// shared single channel crossbar
module bus #(
  parameter mmap_t mmaping[SLAVE_CNT]
) (
  input logic clk,
  input logic rst_n,
  memif.slave masters[MASTER_CNT],
  memif.master slaves[SLAVE_CNT]
);
  request_t mreq[MASTER_CNT];
  response_t mrsp[MASTER_CNT];
  request_t sreq[SLAVE_CNT];
  response_t srsp[SLAVE_CNT];

  generate
    for (genvar m = 0; m < MASTER_CNT; m++) begin : master_flatten
      assign mreq[m].valid = masters[m].valid;
      assign mreq[m].addr = masters[m].addr;
      assign mreq[m].we = masters[m].we;
      assign mreq[m].wd = masters[m].wd;
      assign masters[m].ready = mrsp[m].ready;
      assign masters[m].error = mrsp[m].error;
      assign masters[m].rd = mrsp[m].rd;
    end

    for (genvar s = 0; s < SLAVE_CNT; s++) begin : slave_flatten
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
  logic [MASTER_CNT-1:0] reqs;
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
    foreach (sreq[i]) sreq[i] = '0;
    foreach (mrsp[i]) mrsp[i] = '0;

    if (master_selected != -1 && slave_selected != -1) begin
      sreq[slave_selected] = mreq[master_selected];
      sreq[slave_selected].addr = addr;
      mrsp[master_selected] = srsp[slave_selected];
    end else begin
      // master request but no slave
      if (master_selected != -1) begin
        mrsp[master_selected].ready = 1;
        mrsp[master_selected].error = 1;
        mrsp[master_selected].rd = 0;
      end
    end
  end

endmodule

//------------------------------------
// ifu
//------------------------------------
module ifu (
  input logic clk,
  input logic rst_n,
  memif.master mif,

  // instr fetch interface
  input  logic   valid,
  input  addr_t  pc_i,
  output instr_t instr_o,
  output logic   ready_o,

  // exception interface
  output exception_t exc_o
);
  typedef enum {
    IDLE,
    MAPPING,
    FETCH
  } state_e;

  state_e state;

  logic bus_err, page_fault, misaligned;
  always_comb begin
    ready_o    = 0;
    bus_err    = 0;
    page_fault = 0;
    misaligned = 0;

    if (valid && pc_i[1:0] != 0) begin
      `LOGI($sformatf("pc misaligned: %h", pc_i));
      misaligned = 1;
      ready_o = 1;
    end

    if (valid && state == FETCH && mif.ready) begin
      ready_o = 1;
      if (mif.error) begin
        `LOGE($sformatf("load instr error: %h", pc_i));
        bus_err = 1;
      end
    end
  end

  // handle exception
  always_comb begin
    exc_o = '0;
    if (bus_err) begin
      exc_o.fired = 1;
      exc_o.cause = EXC_INSTR_ACCESS_FAULT;
      exc_o.eval  = pc_i;
    end else if (misaligned) begin
      exc_o.fired = 1;
      exc_o.cause = EXC_INSTR_ADDR_MISALIGNED;
      exc_o.eval  = pc_i;
    end else if (page_fault) begin
      exc_o.fired = 1;
      exc_o.cause = EXC_INSTR_PAGE_FAULT;
      exc_o.eval  = pc_i;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= IDLE;
    end else begin
      if (valid) begin
        unique case (state)
          IDLE: begin
            if (!misaligned) begin
              mif.addr <= pc_i;
              mif.we <= 0;
              mif.valid <= 1;
              state <= FETCH;
            end
          end
          FETCH: begin
            if (mif.ready) begin
              `LOGI($sformatf("pc:%h, instr=%h", pc_i, mif.rd[31:0]));
              mif.valid <= 0;
              instr_o <= mif.rd[31:0];
              state <= IDLE;
            end
          end
          default: ;
        endcase
      end
    end
  end
endmodule


//------------------------------------
// idu
//------------------------------------
module idu (
  input logic clk,
  input logic rst_n,

  // common interface for each stage
  input logic valid,
  output logic ready_o,
  output exception_t exc_o,

  // stage specific input
  input instr_t instr_i
);
  typedef enum {
    EXC_NONE,
    BAD_INSTR,
    EBREAK,
    ECALL_U,
    ECALL_S,
    ECALL_M
  } idexc_e;

  idexc_e exc;

  always_comb begin
    ready_o = 0;
    exc = EXC_NONE;
    if (valid) begin
      ready_o = 1;
    end
  end

  always_comb begin
    exc_o = '0;
    unique case (exc)
      BAD_INSTR: begin
        exc_o.fired = 1;
        exc_o.cause = EXC_ILLEGAL_INSTRUCTION;
        exc_o.eval  = {32'b0, instr_i};
      end
      EBREAK: begin
        exc_o.fired = 1;
        exc_o.cause = EXC_BREAKPOINT;
        exc_o.eval  = '0;
      end
      ECALL_U: begin
        exc_o.fired = 1;
        exc_o.cause = EXC_ECALL_U_MODE;
        exc_o.eval  = '0;
      end
      ECALL_S: begin
        exc_o.fired = 1;
        exc_o.cause = EXC_ECALL_S_MODE;
        exc_o.eval  = '0;
      end
      ECALL_M: begin
        exc_o.fired = 1;
        exc_o.cause = EXC_ECALL_M_MODE;
        exc_o.eval  = '0;
      end
      default: ;
    endcase
  end

endmodule

//------------------------------------
// exec
//------------------------------------
module exu (
  input logic clk,
  input logic rst_n,

  // common interface for each stage
  input logic valid,
  output logic ready_o,
  output exception_t exc_o
);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
    end else begin
      ready_o <= 1;
    end
  end

endmodule


//------------------------------------
// alu
//------------------------------------
module alu (
  input logic clk,
  input logic rst_n
);

endmodule


//------------------------------------
// multiply
//------------------------------------
module mul (
  input logic clk,
  input logic rst_n
);

endmodule

//------------------------------------
// divider
//------------------------------------
module div (
  input logic clk,
  input logic rst_n
);

endmodule

//------------------------------------
// lsu
//------------------------------------
module lsu (
  input logic clk,
  input logic rst_n,
  memif.master mif,

  output logic ready_o
);
  typedef enum {
    IDLE,
    FETCH
  } state_e;

  state_e state;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
    end else begin
      ready_o <= 1;
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
      m[i] = '0;
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
  localparam addr_t SIZE = 4 * 1024;
  localparam string HEX = "isa/isa.hex";
  localparam BITS = $clog2(SIZE);
  wire [BITS-1:0] idx = mif.addr[BITS+1:2];
  logic [31:0] mem[SIZE];

  initial begin
    $readmemh(HEX, mem);
  end

  // bypass RAW
  always_comb begin
    mif.ready = 1'b0;
    mif.error = 0;
    mif.rd = 0;
    if (mif.valid) begin
      if (mif.we) begin
        mif.error = 1;
      end else begin
        mif.rd = {32'b0, mem[idx]};
      end
      mif.ready = 1'b1;
    end
  end

endmodule

//------------------------------------
// mmu
//------------------------------------
module mmu (
  input logic clk,
  input logic rst_n
);

endmodule

//------------------------------------
// csr
//------------------------------------
module csr (
  input logic clk,
  input logic rst_n
);

endmodule

//------------------------------------
// register file
//------------------------------------
module rfu (
  input  logic clk,
  input  logic rst_n,
  output logic ready_o
);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
    end else begin
      ready_o <= 1;
    end
  end
endmodule

//------------------------------------
// raptor for exception, irq
//------------------------------------
module raptor (
  input logic clk,
  input logic rst_n
);

endmodule

//------------------------------------
// scoreboard (riscv-tests tohost to receive result)
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
          $write("%sPASS%s", `COLOR_GREEN, `COLOR_NONE);
        end else begin
          $write("%sFAIL:%0d%s", `COLOR_RED, mif.wd, `COLOR_NONE);
        end
        $finish(0);
      end
    end
  end

endmodule

/******************************************************************************/
