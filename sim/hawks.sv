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
  localparam int unsigned REGMAX = 32;
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

  // used for sram data copy
  `define B2R(r, a) {{56{r[a][7]}}, r[a][7:0]}
  `define H2R(r, a) {{48{r[a+1][7]}}, r[a+1], r[a]}
  `define W2R(r, a) {{32{r[a+3][7]}}, r[a+3], r[a+2], r[a+1], r[a]}
  `define D2R(r, a) {r[a+7], r[a+6], r[a+5], r[a+4], r[a+3], r[a+2], r[a+1], r[a]}
  `define BU2R(r, a) {{56'b0}, r[a]}
  `define HU2R(r, a) {{48'b0}, r[a+1], r[a]}
  `define WU2R(r, a) {{32'b0}, r[a+3], r[a+2], r[a+1], r[a]}
  `define WU2I(r, a) {r[a+3], r[a+2], r[a+1], r[a]}
  `define write_data(r, off, data, sz) for (idx_t i = 0; i < sz; i++) r[off+i] <= data[8*i+:8]

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
    EXC_INSTR_ADDR_MISALIGNED = 64'h0,   // 指令地址未对齐
    EXC_INSTR_ACCESS_FAULT    = 64'h1,   // 取指访问故障
    EXC_ILLEGAL_INSTRUCTION   = 64'h2,   // 非法指令
    EXC_BREAKPOINT            = 64'h3,   // 断点
    EXC_LOAD_ADDR_MISALIGNED  = 64'h4,   // 加载地址未对齐
    EXC_LOAD_ACCESS_FAULT     = 64'h5,   // 加载访问故障
    EXC_STORE_ADDR_MISALIGNED = 64'h6,   // 存储/AMO地址未对齐
    EXC_STORE_ACCESS_FAULT    = 64'h7,   // 存储/AMO访问故障
    EXC_ECALL_U_MODE          = 64'h8,   // U模式环境调用
    EXC_ECALL_S_MODE          = 64'h9,   // S模式环境调用
    EXC_ECALL_M_MODE          = 64'hb,   // M模式环境调用
    EXC_INSTR_PAGE_FAULT      = 64'hc,   // 指令页面错误
    EXC_LOAD_PAGE_FAULT       = 64'hd,   // 加载页面错误
    EXC_STORE_PAGE_FAULT      = 64'hf,   // 存储/AMO页面错误
    EXC_NONE                  = 64'hfff, // just for internal usage

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

  typedef enum {
    IMM_NONE,
    IMM_I,
    IMM_S,
    IMM_U,
    IMM_J,
    IMM_B
  } imm_type_e;

  typedef enum logic [6:0] {
    OPCODE_LOAD      = 7'b0000011,  // Load (lb, lw, ld, lh...)
    OPCODE_FENCE     = 7'b0001111,  // FENCE, FENCE.I
    OPCODE_OP_IMM    = 7'b0010011,  // ALU reg-imm (addi, xori, slli...)
    OPCODE_AUIPC     = 7'b0010111,  // AUIPC
    OPCODE_OP_IMM_32 = 7'b0011011,  // RV64 reg-imm word ops (addiw, slliw...)
    OPCODE_STORE     = 7'b0100011,  // Store (sb, sw, sd...)
    OPCODE_AMO       = 7'b0101111,  // AMO(lr, sc, amoswap, amomax ...)
    OPCODE_OP        = 7'b0110011,  // ALU reg-reg (add, sub, mul, div...)
    OPCODE_LUI       = 7'b0110111,  // LUI
    OPCODE_OP_32     = 7'b0111011,  // RV64 reg-reg word ops (addw, mulw...)
    OPCODE_BRANCH    = 7'b1100011,  // Branch (beq, bne, blt...)
    OPCODE_JALR      = 7'b1100111,  // JALR
    OPCODE_JAL       = 7'b1101111,  // JAL
    OPCODE_SYSTEM    = 7'b1110011   // ECALL, EBREAK, CSRR*
  } opcode_e;

  typedef enum {
    ALU_NONE,
    ALU_ADD,   // 1
    ALU_SUB,
    ALU_AND,
    ALU_OR,
    ALU_XOR,   // 5
    ALU_SLL,
    ALU_SRL,
    ALU_SRA,
    ALU_SLT,
    ALU_SLTU,  // 10

    // rv64 32bit word
    ALU_ADDW,
    ALU_SUBW,
    ALU_SLLW,
    ALU_SRLW,
    ALU_SRAW,  // 15

    // branch
    ALU_BEQ,
    ALU_BNE,
    ALU_BLT,
    ALU_BGE,
    ALU_BLTU,  // 20
    ALU_BGEU
  } alu_op_e;

  typedef enum {
    MULT_NONE,
    MULT_MUL,     // rs1 * rs2
    MULT_MULH,    // rs1 * rs2 high 64bit
    MULT_MULHSU,  // rs1(s) * rs2(u) high 64bit
    MULT_MULHU,   // rs1(u) * rs2(u) high 64bit
    MULT_MULW     // 32bit rd[0:31] = rs1[31:0] * rs2[31:0]; rd[31] -> rd[63:32]
  } mult_op_e;

  typedef enum {
    DIV_NONE,
    DIV_DIV,   // rs1(s) / rs2(s)
    DIV_DIVU,  // rs1(u) / rs2(u)
    DIV_REM,   // rs1(s) % rs2(s)
    DIV_REMU,  // rs1(u) % rs2(u)

    // 32bit
    DIV_DIVW,   // rd[0:31] = rs1[31:0](s) / rs2[31:0](s); rd[31] -> rd[63:32]
    DIV_DIVUW,  // rd[0:31] = rs1[31:0](u) / rs2[31:0](u); rd[31] -> rd[63:32]
    DIV_REMW,   // rd[0:31] = rs1[31:0](s) % rs2[31:0](s); rd[31] -> rd[63:32]
    DIV_REMUW   // rd[0:31] = rs1[31:0](u) % rs2[31:0](u); rd[31] -> rd[63:32]
  } div_op_e;

  typedef enum {
    SYS_NONE,
    SYS_ECALL,
    SYS_EBREAK,
    SYS_MRET,
    SYS_SRET,
    SYS_WFI,
    SYS_URET,
    SYS_FENCE,
    SYS_CSRRW,
    SYS_CSRRS,
    SYS_CSRRC,
    SYS_CSRRWI,
    SYS_CSRRSI,
    SYS_CSRRCI
  } sys_op_e;

  typedef enum {
    AMO_NONE,
    AMO_LR,
    AMO_SC,
    AMO_SWAP,
    AMO_ADD,
    AMO_XOR,
    AMO_OR,
    AMO_AND,
    AMO_MIN,
    AMO_MAX,
    AMO_MINU,
    AMO_MAXU,
    AMO_LRW,
    AMO_SCW,
    AMO_SWAPW,
    AMO_ADDW,
    AMO_XORW,
    AMO_ORW,
    AMO_ANDW,
    AMO_MINW,
    AMO_MAXW,
    AMO_MINUW,
    AMO_MAXUW
  } amo_op_e;

  typedef enum logic [11:0] {
    // csr register in unprivilege mode
    CYCLE   = 12'hC00,
    TIME    = 12'hC01,
    INSTRET = 12'hC02,

    // csr register in M mode
    MSTATUS    = 12'h300,
    MISA       = 12'h301,
    MEDELEG    = 12'h302,
    MIDELEG    = 12'h303,
    MIE        = 12'h304,
    MTVEC      = 12'h305,
    MCOUNTEREN = 12'h306,
    MSCRATCH   = 12'h340,
    MEPC       = 12'h341,
    MCAUSE     = 12'h342,
    MTVAL      = 12'h343,
    MIP        = 12'h344,
    PMPCFG0    = 12'h3A0,
    PMPADDR0   = 12'h3B0,
    MHARTID    = 12'hF14,
    MENVCFG    = 12'h30A,

    // csr register in S mode
    SSTATUS    = 12'h100,
    SEDELEG    = 12'h102,
    SIDELEG    = 12'h103,
    SIE        = 12'h104,
    STVEC      = 12'h105,
    SCOUNTEREN = 12'h106,
    SSCRATCH   = 12'h140,
    SEPC       = 12'h141,
    SCAUSE     = 12'h142,
    STVAL      = 12'h143,
    SIP        = 12'h144,
    SATP       = 12'h180
  } csr_e;

  typedef enum {
    LD_NONE,
    LD_LB,
    LD_LH,
    LD_LW,
    LD_LD,
    LD_LBU,   // 5
    LD_LHU,
    LD_LWU
  } ld_op_e;

  typedef enum {
    SD_NONE,
    SD_SB,
    SD_SH,
    SD_SW,
    SD_SD
  } sd_op_e;

  typedef enum {
    OP_SRC_NONE,
    OP_SRC_REG,
    OP_SRC_IMM,
    OP_SRC_AMO,
    OP_SRC_PC
  } op_src_e;

  typedef struct packed {
    opcode_e  opcode;
    alu_op_e  alu_op;
    mult_op_e mult_op;
    div_op_e  div_op;
    sys_op_e  sys_op;
    ld_op_e   ld_op;
    sd_op_e   sd_op;
    amo_op_e  amo_op;

    logic [4:0]  rs1;
    logic [4:0]  rs2;
    logic [4:0]  rd;
    logic [4:0]  csr_imm;
    logic [11:0] csr;
    logic        reg_write;

    op_src_e op_s1;
    op_src_e op_s2;
    reg_t    imm;
  } id_t;

  typedef enum {
    WB_SRC_NONE,
    WB_SRC_ALU,
    WB_SRC_MEM,
    WB_SRC_AMO,
    WB_SRC_CSR
  } wb_src_e;

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

interface regif;
  logic [4:0] r1, r2;
  reg_t v1, v2;
  modport master(output r1, r2, input v1, v2);
  modport slave(input r1, r2, output v1, v2);
endinterface


//------------------------------
// top entry module (no args)
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
    .COUNTER(100)
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

  logic btaken;
  wb_src_e wb_src;
  reg_t wb_alu, wb_amo, wb_csr, wb_mem;
  stage_e stage, exc_stage;
  addr_t pc, btarget, ttarget;
  instr_t instr;
  id_t id_out;
  exception_t exc[5];

  memif master_ports[MASTER_CNT] ();
  memif slave_ports[SLAVE_CNT] ();
  regif rf ();

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
    .exc_o(exc[2]),
    .id_o(id_out),
    .wb_src_o(wb_src)
  );

  exu exu1 (
    .clk(clk),
    .rst_n(rst_n),
    .valid(stage == STG_EXEC),
    .ready_o(ex_ready),
    .exc_o(exc[3]),
    .pc_i(pc),
    .id_i(id_out),
    .btarget_o(btarget),
    .btaken_o(btaken),
    .rif(rf.master),
    .wb_o(wb_alu)
  );

  lsu lsu1 (
    .clk(clk),
    .rst_n(rst_n),
    .mif(master_ports[1].master),
    .valid(stage == STG_MEM),
    .ready_o(ls_ready),
    .exc_o(exc[4])
  );

  rfu rfu1 (
    .clk(clk),
    .rst_n(rst_n),
    .valid(stage == STG_WB),
    .ready_o(rf_ready),
    .rif(rf.slave),
    .wb_src_i(wb_src),
    .rd_i(id_out.rd),
    .alu_i(wb_alu),
    .csr_i(wb_csr),
    .amo_i(wb_amo),
    .mem_i(wb_mem)
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
            if (exc[4].fired) begin
              stage <= STG_WB;
              exc_stage <= stage;
            end else begin
              stage <= STG_WB;
            end
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
              if (btaken) begin
                pc = btarget;
              end else begin
                pc <= pc + 4;
              end
              stage <= STG_FETCH;
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

  mcause_e ecause;

  always_comb begin
    ready_o = 0;
    ecause  = EXC_NONE;

    if (valid && pc_i[1:0] != 0) begin
      `LOGI($sformatf("pc misaligned: %h", pc_i));
      ecause  = EXC_INSTR_ADDR_MISALIGNED;
      ready_o = 1;
    end

    if (valid && state == FETCH && mif.ready) begin
      ready_o = 1;
      if (mif.error) begin
        `LOGE($sformatf("load instr error: %h", pc_i));
        ecause = EXC_INSTR_ACCESS_FAULT;
      end
    end
  end

  // handle exception
  always_comb begin
    exc_o = '0;
    if (ecause != EXC_NONE) begin
      exc_o.fired = 1;
      exc_o.cause = ecause;
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
            if (ecause == EXC_NONE) begin
              mif.addr <= pc_i;
              mif.dtype <= U32;
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
  input instr_t instr_i,

  // decode output
  output id_t id_o,
  output wb_src_e wb_src_o
);
  mcause_e ecause;
  always_comb begin
    ready_o = 0;
    if (valid) begin
      ready_o = 1;
    end
  end

  // handle exceptions
  always_comb begin
    exc_o = '0;
    if (ecause != EXC_NONE) begin
      exc_o.fired = 1;
      exc_o.cause = ecause;
      exc_o.eval  = {32'b0, instr_i};
    end
  end

  // instr decoding
  logic [2:0] f3;
  logic [6:0] f7;
  logic [9:0] fc;
  imm_type_e imm_type;

  always_comb begin : decode
    ecause = EXC_NONE;
    if (valid) begin
      `LOGI("decode");
      id_o        = '0;
      wb_src_o    = WB_SRC_NONE;
      id_o.opcode = opcode_e'(instr_i[6:0]);
      id_o.rs1    = instr_i[19:15];
      id_o.rs2    = instr_i[24:20];
      id_o.rd     = instr_i[11:7];
      f3          = instr_i[14:12];
      f7          = instr_i[31:25];
      fc          = {f7, f3};

      unique case (id_o.opcode)
        OPCODE_OP: begin
          `LOGI("OP");
          // 002081b3: add x3, x1, x2
          // add rd, rs1, rs2
          // ALU: rs1 <op> rs2
          id_o.reg_write = 1;
          wb_src_o = WB_SRC_ALU;
          id_o.op_s1 = OP_SRC_REG;
          id_o.op_s2 = OP_SRC_REG;
          unique case (fc)
            {7'b0000000, 3'b000} : id_o.alu_op = ALU_ADD;
            {7'b0100000, 3'b000} : id_o.alu_op = ALU_SUB;
            {7'b0000000, 3'b111} : id_o.alu_op = ALU_AND;
            {7'b0000000, 3'b110} : id_o.alu_op = ALU_OR;
            {7'b0000000, 3'b100} : id_o.alu_op = ALU_XOR;
            {7'b0000000, 3'b001} : id_o.alu_op = ALU_SLL;
            {7'b0000000, 3'b101} : id_o.alu_op = ALU_SRL;
            {7'b0100000, 3'b101} : id_o.alu_op = ALU_SRA;
            {7'b0000000, 3'b010} : id_o.alu_op = ALU_SLT;
            {7'b0000000, 3'b011} : id_o.alu_op = ALU_SLTU;
            {7'b0000001, 3'b000} : id_o.mult_op = MULT_MUL;
            {7'b0000001, 3'b001} : id_o.mult_op = MULT_MULH;
            {7'b0000001, 3'b010} : id_o.mult_op = MULT_MULHSU;
            {7'b0000001, 3'b011} : id_o.mult_op = MULT_MULHU;
            {7'b0000001, 3'b100} : id_o.div_op = DIV_DIV;
            {7'b0000001, 3'b101} : id_o.div_op = DIV_DIVU;
            {7'b0000001, 3'b110} : id_o.div_op = DIV_REM;
            {7'b0000001, 3'b111} : id_o.div_op = DIV_REMU;
            default: ;
          endcase
        end
        OPCODE_OP_32: begin
          // R-type: rd = rs1 op rs2 (32-bit + sign extend)
          id_o.reg_write = 1;
          wb_src_o = WB_SRC_ALU;
          id_o.op_s1 = OP_SRC_REG;
          id_o.op_s2 = OP_SRC_REG;
          unique case (fc)
            {7'b0000000, 3'b000} : id_o.alu_op = ALU_ADDW;
            {7'b0100000, 3'b000} : id_o.alu_op = ALU_SUBW;
            {7'b0000000, 3'b001} : id_o.alu_op = ALU_SLLW;
            {7'b0000000, 3'b101} : id_o.alu_op = ALU_SRLW;
            {7'b0100000, 3'b101} : id_o.alu_op = ALU_SRAW;
            {7'b0000001, 3'b000} : id_o.mult_op = MULT_MULW;
            {7'b0000001, 3'b100} : id_o.div_op = DIV_DIVW;
            {7'b0000001, 3'b101} : id_o.div_op = DIV_DIVUW;
            {7'b0000001, 3'b110} : id_o.div_op = DIV_REMW;
            {7'b0000001, 3'b111} : id_o.div_op = DIV_REMUW;
            default: ;
          endcase
        end
        OPCODE_OP_IMM: begin
          `LOGI("OP_IMM");
          // 00500093: addi x1, x0, 5
          // addi rd, rs1, imm
          // ALU: rs1 <op> imm;
          id_o.reg_write = 1;
          wb_src_o = WB_SRC_ALU;
          id_o.op_s1 = OP_SRC_REG;
          id_o.op_s2 = OP_SRC_IMM;
          imm_type = IMM_I;
          unique case (f3)
            3'b000:  id_o.alu_op = ALU_ADD;
            3'b001:  id_o.alu_op = ALU_SLL;
            3'b010:  id_o.alu_op = ALU_SLT;
            3'b011:  id_o.alu_op = ALU_SLTU;
            3'b100:  id_o.alu_op = ALU_XOR;
            3'b110:  id_o.alu_op = ALU_OR;
            3'b101:  id_o.alu_op = (f7[5]) ? ALU_SRA : ALU_SRL;
            3'b111:  id_o.alu_op = ALU_AND;
            default: ;
          endcase
        end
        OPCODE_OP_IMM_32: begin
          `LOGI("OP_IMM32");
          // 00500093: addiw x1, x0, 5
          // addi rd, rs1, imm
          // ALU: rs1 <op> imm;
          id_o.reg_write = 1;
          wb_src_o = WB_SRC_ALU;
          id_o.op_s1 = OP_SRC_REG;
          id_o.op_s2 = OP_SRC_IMM;
          imm_type = IMM_I;
          unique case (f3)
            3'b000:  id_o.alu_op = ALU_ADDW;
            default: ;
          endcase
          unique case (fc)
            {7'b0000000, 3'b001} : id_o.alu_op = ALU_SLLW;
            {7'b0000000, 3'b101} : id_o.alu_op = ALU_SRLW;
            {7'b0100000, 3'b101} : id_o.alu_op = ALU_SRAW;
            default: ;
          endcase
        end
        OPCODE_LOAD: begin
          `LOGI("LOAD");
          // 00003283: ld x5, 0(x0)
          // ld rd, offset(rs1)
          // ALU: addr= rs1 + offset
          // rd = mem[addr]
          id_o.reg_write = 1;
          wb_src_o = WB_SRC_MEM;
          id_o.alu_op = ALU_ADD;
          id_o.op_s1 = OP_SRC_REG;
          id_o.op_s2 = OP_SRC_IMM;
          imm_type = IMM_I;
          unique case (f3)
            3'b000:  id_o.ld_op = LD_LB;
            3'b001:  id_o.ld_op = LD_LH;
            3'b010:  id_o.ld_op = LD_LW;
            3'b011:  id_o.ld_op = LD_LD;
            3'b100:  id_o.ld_op = LD_LBU;
            3'b101:  id_o.ld_op = LD_LHU;
            3'b110:  id_o.ld_op = LD_LWU;
            default: ;
          endcase
        end
        OPCODE_STORE: begin
          `LOGI("STORE");
          // 00403023: sd x4, 0(x0)
          // ALU: addr = rs1 + imm;
          // mem[addr] = rs2
          id_o.reg_write = 0;
          id_o.alu_op = ALU_ADD;
          id_o.op_s1 = OP_SRC_REG;
          id_o.op_s2 = OP_SRC_IMM;
          imm_type = IMM_S;
          unique case (f3)
            3'b000:  id_o.sd_op = SD_SB;
            3'b001:  id_o.sd_op = SD_SH;
            3'b010:  id_o.sd_op = SD_SW;
            3'b011:  id_o.sd_op = SD_SD;
            default: ;
          endcase
        end
        OPCODE_BRANCH: begin
          `LOGI("BRANCH");
          // 00628663: beq  x5, x6, +12
          // beq rs1, rs2, imm(label)
          // take_branch ? PC=PC+imm : PC=PC+4;
          imm_type   = IMM_B;
          id_o.op_s1 = OP_SRC_REG;
          id_o.op_s2 = OP_SRC_REG;
          unique case (f3)
            3'b000:  id_o.alu_op = ALU_BEQ;
            3'b001:  id_o.alu_op = ALU_BNE;
            3'b100:  id_o.alu_op = ALU_BLT;
            3'b101:  id_o.alu_op = ALU_BGE;
            3'b110:  id_o.alu_op = ALU_BLTU;
            3'b111:  id_o.alu_op = ALU_BGEU;
            default: ;
          endcase
        end
        OPCODE_JAL: begin
          `LOGI("JAL");
          // 008000ef: jal rd, imm
          // rd = PC+4; PC=PC+imm;
          imm_type = IMM_J;
          id_o.reg_write = 1;
          wb_src_o = WB_SRC_ALU;
          id_o.alu_op = ALU_ADD;
          id_o.op_s1 = OP_SRC_PC;
          id_o.op_s2 = OP_SRC_IMM;
        end
        OPCODE_JALR: begin
          `LOGI("JALR");
          // 00008067: jalr rd, imm(rs1)
          // rd = PC+4; PC = (rs1 + imm) & ~1 ;
          imm_type = IMM_I;
          id_o.reg_write = 1;
          wb_src_o = WB_SRC_ALU;
          id_o.alu_op = ALU_ADD;
          id_o.op_s1 = OP_SRC_REG;
          id_o.op_s2 = OP_SRC_IMM;
        end
        OPCODE_AUIPC: begin
          `LOGI("AUIPC");
          // auipc rd, imm
          // rd = PC + (imm << 12)
          imm_type = IMM_U;
          id_o.reg_write = 1;
          wb_src_o = WB_SRC_ALU;
          id_o.alu_op = ALU_ADD;
          id_o.op_s1 = OP_SRC_PC;
          id_o.op_s2 = OP_SRC_IMM;
        end
        OPCODE_LUI: begin
          `LOGI("LUI");
          // lui rd, imm
          // rd = (imm << 12)
          // ALU: x0 + (imm << 12);
          imm_type       = IMM_U;
          id_o.reg_write = 1;
          wb_src_o       = WB_SRC_ALU;
          id_o.alu_op    = ALU_ADD;
          id_o.rs1       = 0;
          id_o.op_s1     = OP_SRC_REG;
          id_o.op_s2     = OP_SRC_IMM;
        end

        OPCODE_SYSTEM: begin
          `LOGI("SYSTEM");
          unique case (f3)
            3'b000: begin
              unique case (instr_i[31:20])
                12'h000: begin
                  id_o.sys_op = SYS_ECALL;
                  ecause = EXC_ECALL_U_MODE;  //TODO
                end
                12'h001: begin
                  id_o.sys_op = SYS_EBREAK;
                  ecause = EXC_BREAKPOINT;
                end
                12'h002: id_o.sys_op = SYS_URET;
                12'h102: id_o.sys_op = SYS_SRET;
                12'h105: id_o.sys_op = SYS_WFI;
                12'h302: id_o.sys_op = SYS_MRET;
                default: ;
              endcase
              if (f7 == 7'b0001001) begin
                id_o.sys_op = SYS_FENCE;
              end
            end
            3'b001: begin
              // csrrw rd, csr, rs1
              // x[rd] = CSRs[csr]; CSRs[csr] = x[rs1]
              id_o.reg_write = 1;
              wb_src_o       = WB_SRC_CSR;
              id_o.sys_op    = SYS_CSRRW;
              id_o.csr       = instr_i[31:20];
            end
            3'b010: begin
              id_o.reg_write = 1;
              wb_src_o       = WB_SRC_CSR;
              id_o.sys_op    = SYS_CSRRS;
              id_o.csr       = instr_i[31:20];
            end
            3'b011: begin  // CSRRC
              id_o.reg_write = 1;
              wb_src_o       = WB_SRC_CSR;
              id_o.sys_op    = SYS_CSRRC;
              id_o.csr       = instr_i[31:20];
            end

            3'b101: begin  // CSRRWI
              id_o.reg_write = 1;
              id_o.sys_op    = SYS_CSRRWI;
              wb_src_o       = WB_SRC_CSR;
              id_o.csr       = instr_i[31:20];
              id_o.csr_imm   = id_o.rs1;
            end

            3'b110: begin  // CSRRSI
              id_o.reg_write = 1;
              id_o.sys_op    = SYS_CSRRSI;
              wb_src_o       = WB_SRC_CSR;
              id_o.csr       = instr_i[31:20];
              id_o.csr_imm   = id_o.rs1;
            end

            3'b111: begin  // CSRRCI
              id_o.reg_write = 1;
              id_o.sys_op    = SYS_CSRRCI;
              wb_src_o       = WB_SRC_CSR;
              id_o.csr       = instr_i[31:20];
              id_o.csr_imm   = id_o.rs1;
            end
            default: ;
          endcase
        end
        OPCODE_AMO: begin
          `LOGI("AMO");
          id_o.reg_write = 1;
          wb_src_o       = WB_SRC_AMO;
          id_o.op_s1     = OP_SRC_AMO;
          id_o.op_s2     = OP_SRC_REG;
          unique case (fc)
            {
              7'b0001000, 3'b010
            } : begin
              id_o.amo_op = AMO_LRW;
              id_o.ld_op  = LD_LW;
            end
            {
              7'b0001100, 3'b010
            } : begin
              id_o.amo_op = AMO_SCW;
              id_o.sd_op  = SD_SW;
            end
            {
              7'b0001000, 3'b011
            } : begin
              wb_src_o    = WB_SRC_MEM;
              id_o.amo_op = AMO_LR;
              id_o.ld_op  = LD_LD;
            end
            {
              7'b0001100, 3'b011
            } : begin
              wb_src_o    = WB_SRC_NONE;
              id_o.amo_op = AMO_SC;
              id_o.sd_op  = SD_SD;
            end
            {
              7'b0000100, 3'b010
            } : begin
              id_o.amo_op = AMO_SWAPW;
              id_o.sd_op  = SD_SW;
            end
            {
              7'b0000000, 3'b010
            } : begin
              id_o.amo_op = AMO_ADDW;
              id_o.alu_op = ALU_ADDW;
              id_o.sd_op  = SD_SW;
            end
            {
              7'b0010000, 3'b010
            } : begin
              id_o.amo_op = AMO_XORW;
              id_o.alu_op = ALU_XOR;
              id_o.sd_op  = SD_SW;
            end
            {
              7'b0100000, 3'b010
            } : begin
              id_o.amo_op = AMO_ORW;
              id_o.alu_op = ALU_OR;
              id_o.sd_op  = SD_SW;
            end
            {
              7'b0110000, 3'b010
            } : begin
              id_o.amo_op = AMO_ANDW;
              id_o.alu_op = ALU_AND;
              id_o.sd_op  = SD_SW;
            end
            {
              7'b1000000, 3'b010
            } : begin
              id_o.amo_op = AMO_MINW;
              id_o.alu_op = ALU_SLT;
              id_o.sd_op  = SD_SW;
            end
            {
              7'b1010000, 3'b010
            } : begin
              id_o.amo_op = AMO_MAXW;
              id_o.alu_op = ALU_SLT;
              id_o.sd_op  = SD_SW;
            end
            {
              7'b1100000, 3'b010
            } : begin
              id_o.amo_op = AMO_MINUW;
              id_o.alu_op = ALU_SLTU;
              id_o.sd_op  = SD_SW;
            end
            {
              7'b1110000, 3'b010
            } : begin
              id_o.amo_op = AMO_MAXUW;
              id_o.alu_op = ALU_SLTU;
              id_o.sd_op  = SD_SW;
            end
            {
              7'b0000100, 3'b011
            } : begin
              id_o.amo_op = AMO_SWAP;
              id_o.sd_op  = SD_SD;
            end
            {
              7'b0000000, 3'b011
            } : begin
              id_o.amo_op = AMO_ADD;
              id_o.alu_op = ALU_ADD;
              id_o.sd_op  = SD_SD;
            end
            {
              7'b0010000, 3'b011
            } : begin
              id_o.amo_op = AMO_XOR;
              id_o.alu_op = ALU_XOR;
              id_o.sd_op  = SD_SD;
            end
            {
              7'b0100000, 3'b011
            } : begin
              id_o.amo_op = AMO_OR;
              id_o.alu_op = ALU_OR;
              id_o.sd_op  = SD_SD;
            end
            {
              7'b0110000, 3'b011
            } : begin
              id_o.amo_op = AMO_AND;
              id_o.alu_op = ALU_AND;
              id_o.sd_op  = SD_SD;
            end
            {
              7'b1000000, 3'b011
            } : begin
              id_o.amo_op = AMO_MIN;
              id_o.alu_op = ALU_SLT;
              id_o.sd_op  = SD_SD;
            end
            {
              7'b1010000, 3'b011
            } : begin
              id_o.amo_op = AMO_MAX;
              id_o.alu_op = ALU_SLT;
              id_o.sd_op  = SD_SD;
            end
            {
              7'b1100000, 3'b011
            } : begin
              id_o.amo_op = AMO_MINU;
              id_o.alu_op = ALU_SLTU;
              id_o.sd_op  = SD_SD;
            end
            {
              7'b1110000, 3'b011
            } : begin
              id_o.amo_op = AMO_MAXU;
              id_o.alu_op = ALU_SLTU;
              id_o.sd_op  = SD_SD;
            end
            default: id_o.amo_op = AMO_NONE;
          endcase
        end
        default: ecause = EXC_ILLEGAL_INSTRUCTION;
      endcase

      unique case (imm_type)
        IMM_I:   id_o.imm = {{52{instr_i[31]}}, instr_i[31:20]};
        IMM_S:   id_o.imm = {{52{instr_i[31]}}, instr_i[31:25], instr_i[11:7]};
        IMM_B:   id_o.imm = {{51{instr_i[31]}}, instr_i[31], instr_i[7], instr_i[30:25], instr_i[11:8], 1'b0};
        IMM_U:   id_o.imm = {{32{instr_i[31]}}, instr_i[31:12], 12'b0};
        IMM_J:   id_o.imm = {{43{instr_i[31]}}, instr_i[31], instr_i[19:12], instr_i[20], instr_i[30:21], 1'b0};
        default: id_o.imm = '0;
      endcase
    end
  end
endmodule

//------------------------------------
// exec
// - arithmetic / logic
// - multiply and divide
// - amo operations
// - csr operations
// - addr calc: ld/sd, branch/jal(r)
//------------------------------------
module exu (
  input logic clk,
  input logic rst_n,
  input logic valid,
  output logic ready_o,
  output exception_t exc_o,
  input addr_t pc_i,
  input id_t id_i,
  output addr_t btarget_o,
  output logic btaken_o,
  output reg_t wb_o,
  regif.master rif
);
  reg_t alu_result;

  // handle register read and writeback
  always_comb begin
    rif.r1 = 0;
    rif.r2 = 0;
    wb_o   = 0;
    if (valid) begin
      rif.r1 = id_i.rs1;
      rif.r2 = id_i.rs2;
    end
    if (id_i.reg_write) begin
      if (id_i.alu_op != ALU_NONE) begin
        wb_o = alu_result;
      end else if (id_i.mult_op != MULT_NONE) begin
        wb_o = mul_result;
      end else if (id_i.div_op != DIV_NONE) begin
        wb_o = div_result;
      end
      if (id_i.opcode inside {OPCODE_JAL, OPCODE_JALR}) begin
        wb_o = pc_i + 4;
      end
    end
  end

  // handle done
  always_comb begin
    ready_o = 0;
    if (valid) begin
      ready_o = div_done;
    end
  end

  // prepare op1 and op2 for alu, mul, div
  reg_t op1, op2;
  always_comb begin
    op1 = 0;
    op2 = 0;
    if (valid) begin
      op1 = id_i.op_s1 == OP_SRC_REG ? rif.v1 : pc_i;
      op2 = id_i.op_s2 == OP_SRC_REG ? rif.v2 : id_i.imm;
    end
  end

  // do math and logic calculation
  alu alu1 (
    .clk(clk),
    .rst_n(rst_n),
    .valid(valid && id_i.alu_op != ALU_NONE),
    .op_i(id_i.alu_op),
    .pc_i(pc_i),
    .op1_i(op1),
    .op2_i(op2),
    .result_o(alu_result)
  );

  // do multiply
  reg_t mul_result;
  mul mul1 (
    .valid(valid),
    .op_i(id_i.mult_op),
    .op1_i(op1),
    .op2_i(op2),
    .result_o(mul_result)
  );

  // do divide
  reg_t div_result;
  logic div_done;
  div div1 (
    .clk(clk),
    .rst_n(rst_n),
    .valid(valid),
    .op_i(id_i.div_op),
    .op1_i(op1),
    .op2_i(op2),
    .result_o(div_result),
    .done_o(div_done)
  );

  // handle branch and jump
  always_comb begin
    btarget_o = '0;
    btaken_o  = 0;
    if (id_i.opcode == OPCODE_BRANCH) begin
      // meet branch
      if (alu_result[0]) begin
        btarget_o = pc_i + id_i.imm;
        btaken_o  = 1;
      end
    end
    if (id_i.opcode == OPCODE_JAL) begin
      // rd = PC+4; PC=PC+imm;
      btarget_o = alu_result;
      btaken_o  = 1;
    end else if (id_i.opcode == OPCODE_JALR) begin
      // rd = PC+4; PC = (rs1 + imm) & ~1 ;
      btarget_o = alu_result & ~1;
      btaken_o  = 1;
    end
  end

endmodule


//------------------------------------
// alu
//------------------------------------
module alu (
  input logic clk,
  input logic rst_n,
  input logic valid,
  input alu_op_e op_i,
  input addr_t pc_i,
  input reg_t op1_i,
  input reg_t op2_i,
  output reg_t result_o
);
  logic [31:0] w_result;

  always_comb begin
    if (valid) begin
      unique case (op_i)
        ALU_ADD:  result_o = op1_i + op2_i;
        ALU_SUB:  result_o = op1_i - op2_i;
        ALU_AND:  result_o = op1_i & op2_i;
        ALU_OR:   result_o = op1_i | op2_i;
        ALU_XOR:  result_o = op1_i ^ op2_i;
        ALU_SLL:  result_o = op1_i << op2_i[5:0];
        ALU_SRL:  result_o = op1_i >> op2_i[5:0];
        ALU_SRA:  result_o = $signed(op1_i) >>> op2_i[5:0];
        ALU_SLT:  result_o = ($signed(op1_i) < $signed(op2_i)) ? 64'd1 : 64'd0;
        ALU_SLTU: result_o = (op1_i < op2_i) ? 64'd1 : 64'd0;
        ALU_BNE:  result_o = (op1_i != op2_i) ? 1 : 0;
        ALU_BEQ:  result_o = (op1_i == op2_i) ? 1 : 0;
        ALU_BLT:  result_o = ($signed(op1_i) < $signed(op2_i)) ? 1 : 0;
        ALU_BGE:  result_o = ($signed(op1_i) >= $signed(op2_i)) ? 1 : 0;
        ALU_BLTU: result_o = (op1_i < op2_i) ? 1 : 0;
        ALU_BGEU: result_o = (op1_i >= op2_i) ? 1 : 0;

        ALU_ADDW: begin
          w_result = op1_i[31:0] + op2_i[31:0];
          result_o = {{32{w_result[31]}}, w_result};
        end
        ALU_SUBW: begin
          w_result = op1_i[31:0] - op2_i[31:0];
          result_o = {{32{w_result[31]}}, w_result};
        end
        ALU_SLLW: begin
          w_result = op1_i[31:0] << op2_i[4:0];
          result_o = {{32{w_result[31]}}, w_result};
        end
        ALU_SRLW: begin
          w_result = op1_i[31:0] >> op2_i[4:0];
          result_o = {{32{w_result[31]}}, w_result};
        end
        ALU_SRAW: begin
          w_result = $signed(op1_i[31:0]) >>> op2_i[4:0];
          result_o = {{32{w_result[31]}}, w_result};
        end
        default: result_o = '0;
      endcase
      // `LOGI($sformatf("op:%0d, op1:%h op2_i:%h r:%h", op_i, op1, op2_i, result_o));
    end
  end
endmodule


//------------------------------------
// multiply
//------------------------------------
module mul (
  input logic valid,
  input mult_op_e op_i,
  input reg_t op1_i,
  input reg_t op2_i,
  output reg_t result_o
);

  logic signed [64:0] opa, opb;
  logic signed [129:0] full;
  always_comb begin
    if (valid) begin
      opa = '0;
      opb = '0;
      unique case (op_i)
        MULT_MULHU: begin
          opa = {1'b0, op1_i};
          opb = {1'b0, op2_i};
        end
        MULT_MULHSU: begin
          opa = {op1_i[63], op1_i};
          opb = {1'b0, op2_i};
        end
        MULT_MUL, MULT_MULH: begin
          opa = {op1_i[63], op1_i};
          opb = {op2_i[63], op2_i};
        end
        MULT_MULW: begin
          opa = {{33{op1_i[31]}}, op1_i[31:0]};
          opb = {{33{op2_i[31]}}, op2_i[31:0]};
        end
        default: ;
      endcase
    end
  end
  assign full = opa * opb;

  always_comb begin
    if (valid) begin
      unique case (op_i)
        MULT_MUL: begin
          result_o = full[63:0];
        end
        MULT_MULW: begin
          result_o = {{32{full[31]}}, full[31:0]};
        end
        MULT_MULH, MULT_MULHSU, MULT_MULHU: begin
          result_o = {{32{full[31]}}, full[31:0]};
          result_o = full[127:64];
        end
        default: result_o = 0;
      endcase
    end
  end

endmodule

//------------------------------------
// divider
//------------------------------------
module div (
  input logic clk,
  input logic rst_n,
  input logic valid,
  input div_op_e op_i,
  input reg_t op1_i,
  input reg_t op2_i,
  output reg_t result_o,
  output logic done_o
);

  typedef enum logic [1:0] {
    IDLE   = 2'b00,
    DIVIDE = 2'b01,
    FINISH = 2'b10
  } state_t;
  state_t state_q, state_d;

  logic [63:0] a_q, a_d, b_q, b_d, quot_q, quot_d;
  logic [5:0] cnt_q, cnt_d;
  logic res_inv_q, res_inv_d, rem_inv_q, rem_inv_d;
  logic is_rem_q, is_rem_d, is_div_zero_q, is_div_zero_d;

  // preprocess
  logic [63:0] op_a_abs, op_b_abs;
  logic a_sign, b_sign, is_signed;
  logic is_divider, is_rv64w;

  assign is_divider = op_i != DIV_NONE;
  assign is_rv64w = op_i inside {DIV_DIVW, DIV_REMW, DIV_REMUW, DIV_DIVUW};
  assign is_signed = op_i inside {DIV_DIV, DIV_DIVW, DIV_REM, DIV_REMW};
  assign a_sign    = is_rv64w ? op1_i[31] : op1_i[63];
  assign b_sign    = is_rv64w ? op2_i[31] : op2_i[63];

  always_comb begin
    logic [63:0] v1, v2;
    v1 = is_rv64w ? (is_signed ? {{32{op1_i[31]}}, op1_i[31:0]} : {32'b0, op1_i[31:0]}) : op1_i;
    v2 = is_rv64w ? (is_signed ? {{32{op2_i[31]}}, op2_i[31:0]} : {32'b0, op2_i[31:0]}) : op2_i;
    op_a_abs = (is_signed && a_sign) ? (~v1 + 64'd1) : v1;
    op_b_abs = (is_signed && b_sign) ? (~v2 + 64'd1) : v2;
  end

  // leader zero counter to reduce loop
  function automatic logic [5:0] count_lz(logic [63:0] val);
    logic [5:0] count;
    count = 6'd0;
    for (int i = 63; i >= 0; i--) begin
      if (val[i]) break;
      count = count + 6'd1;
    end
    return count;
  endfunction

  logic [5:0] lzc_a, lzc_b, shift_amt;
  assign lzc_a = count_lz(op_a_abs);
  assign lzc_b = count_lz(op_b_abs);
  assign shift_amt = (lzc_b > lzc_a) ? (lzc_b - lzc_a) : 6'd0;

  // try sub
  logic [64:0] sub_res;
  assign sub_res = {1'b0, a_q} - {1'b0, b_q};

  // fsm
  always_comb begin
    state_d = state_q;
    a_d = a_q;
    b_d = b_q;
    quot_d = quot_q;
    cnt_d = cnt_q;
    is_div_zero_d = is_div_zero_q;
    is_rem_d = is_rem_q;
    res_inv_d = res_inv_q;
    rem_inv_d = rem_inv_q;
    done_o = is_divider ? 1'b0 : 1'b1;

    if (is_divider) begin
      case (state_q)
        IDLE: begin
          if (valid) begin
            is_div_zero_d = (op_b_abs == 64'b0);
            is_rem_d      = op_i inside {DIV_REM, DIV_REMUW, DIV_REMW, DIV_REMU};
            res_inv_d     = is_signed && (a_sign ^ b_sign) && (op_b_abs != 64'b0);
            rem_inv_d     = is_signed && a_sign;
            a_d           = op_a_abs;
            b_d           = op_b_abs << shift_amt;
            quot_d        = 64'b0;
            cnt_d         = shift_amt;
            if (!is_divider || op_a_abs < op_b_abs || op_b_abs == 64'b0) state_d = FINISH;
            else state_d = DIVIDE;
          end
        end
        DIVIDE: begin
          if (!sub_res[64]) begin
            a_d    = sub_res[63:0];
            quot_d = {quot_q[64-2:0], 1'b1};
          end else begin
            quot_d = {quot_q[64-2:0], 1'b0};
          end
          b_d = {1'b0, b_q[63:1]};
          if (cnt_q == 6'd0) state_d = FINISH;
          else cnt_d = cnt_q - 6'd1;
        end
        FINISH: begin
          done_o = 1'b1;
          if (valid) state_d = IDLE;
        end
        default: state_d = IDLE;
      endcase
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= IDLE;
      a_q <= 0;
      b_q <= 0;
      quot_q <= 0;
      cnt_q <= 0;
      is_div_zero_q <= 0;
      is_rem_q <= 0;
      res_inv_q <= 0;
      rem_inv_q <= 0;
    end else begin
      state_q <= state_d;
      a_q <= a_d;
      b_q <= b_d;
      quot_q <= quot_d;
      cnt_q <= cnt_d;
      is_div_zero_q <= is_div_zero_d;
      is_rem_q <= is_rem_d;
      res_inv_q <= res_inv_d;
      rem_inv_q <= rem_inv_d;
    end
  end

  // result and sign bit
  always_comb begin
    logic [63:0] q_signed, r_signed, pre_res;
    q_signed = res_inv_q ? (~quot_q + 64'd1) : quot_q;
    r_signed = rem_inv_q ? (~a_q + 64'd1) : a_q;
    if (is_div_zero_q) begin
      q_signed = 64'hFFFF_FFFF_FFFF_FFFF;
      r_signed = is_rv64w ? {{32{op1_i[31]}}, op1_i[31:0]} : op1_i;
    end
    pre_res  = is_rem_q ? r_signed : q_signed;
    result_o = is_rv64w ? {{32{pre_res[31]}}, pre_res[31:0]} : pre_res;
  end
endmodule

//------------------------------------
// lsu
// - load data / store data
// - use mmu to map va to pa
// - LR & SC flag record & clear
// - addr: alu-result(ld/sd), rs1_val(amo)
// - write data: rs2_val(sd), amo-result(amo)
//------------------------------------
module lsu (
  input logic clk,
  input logic rst_n,
  memif.master mif,

  // common interface for each stage
  input logic valid,
  output logic ready_o,
  output exception_t exc_o

  // input ld_op_e ld_op_i,
  // input sd_op_e sd_op_i,
  // input amo_op_e amo_op_i,
  // input addr_t  addr_i,
  // input reg_t   wd_i
  // output reg_t  rd_o
);
  typedef enum {
    IDLE,
    FETCH
  } state_e;
  state_e state;

  // handle exceptions
  mcause_e ecause;
  always_comb begin
    ready_o = 0;
    ecause  = EXC_NONE;
    if (valid) begin
      ready_o = 1;
    end
  end
  always_comb begin
    if (ecause != EXC_NONE) begin
      exc_o.fired = 1;
      exc_o.cause = ecause;
      exc_o.eval  = 0;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
    end else begin
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
  localparam addr_t MAX = 32 * 1024;
  typedef logic [$clog2(MAX)-1:0] idx_t;
  wire idx_t idx = mif.addr[$clog2(MAX)-1:0];
  logic [7:0] m[MAX];
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
      unique case (mif.dtype)
        S8: mif.rd = `B2R(m, idx);
        U8: mif.rd = `BU2R(m, idx);
        S16: mif.rd = `H2R(m, idx);
        U16: mif.rd = `HU2R(m, idx);
        S32: mif.rd = `W2R(m, idx);
        U32: mif.rd = `WU2R(m, idx);
        US64: mif.rd = `D2R(m, idx);
        default: ;
      endcase
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      foreach (m[i]) begin
        m[i] <= '0;
      end
    end else begin
      if (mif.valid && mif.we) begin
        unique case (mif.dtype)
          S8: `write_data(m, idx, mif.wd, 8);
          U8: `write_data(m, idx, mif.wd, 8);
          S16: `write_data(m, idx, mif.wd, 16);
          U16: `write_data(m, idx, mif.wd, 16);
          S32: `write_data(m, idx, mif.wd, 32);
          U32: `write_data(m, idx, mif.wd, 32);
          US64: `write_data(m, idx, mif.wd, 64);
          default: ;
        endcase
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
  localparam string HEX = "isa/div.hex";
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
// - instruction mapping
// - data addr mapping
// - itlb, dtlb
// - ptw with arbitor
// - exception to outside
//------------------------------------
module mmu (
  input logic clk,
  input logic rst_n
);

endmodule

//------------------------------------
// csr
// - register rw
// - irq to trap vector
// - priviledge management
//------------------------------------
module csr (
  input logic clk,
  input logic rst_n
);
endmodule

//------------------------------------
// register file
// - 32 64bits common register rw
//------------------------------------
module rfu (
  input logic clk,
  input logic rst_n,
  input logic valid,
  output logic ready_o,
  regif.slave rif,
  input wb_src_e wb_src_i,
  input logic [4:0] rd_i,
  input reg_t alu_i,
  input reg_t mem_i,
  input reg_t amo_i,
  input reg_t csr_i
);
  reg_t x[REGMAX];
  reg_t r;

  always_comb begin
    unique case (wb_src_i)
      WB_SRC_ALU: r = alu_i;
      WB_SRC_MEM: r = mem_i;
      WB_SRC_CSR: r = csr_i;
      WB_SRC_AMO: r = amo_i;
      default: ;
    endcase
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      foreach (x[i]) begin
        x[i] <= '0;
      end
    end else begin : writeback
      if (valid && wb_src_i != WB_SRC_NONE && rd_i != 0) begin
        x[rd_i] <= r;
        `LOGI($sformatf("WB: x[%02d]=%h", rd_i, r));
      end
    end
  end

  always_comb begin
    if (32'(rif.r1) < REGMAX) rif.v1 = x[rif.r1];
    if (32'(rif.r2) < REGMAX) rif.v2 = x[rif.r2];
  end

  always_comb begin
    ready_o = 1;
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
