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

// build:  verilator --timing --binary --trace -o mini --top-module top mini.sv

`timescale 1ns / 100ps

// `define DEBUG_LOG
`ifdef DEBUG_LOG
`define LOGI(msg) $display("[I|%9t|%m] %s", $realtime, msg)
`define LOGW(msg) $display("[W|%9t|%m] %s", $realtime, msg)
`define LOGE(msg) $display("[E|%9t|%m] %s", $realtime, msg)
`else
`define LOGI(msg)
`define LOGW(msg)
`define LOGE(msg)
`endif

`define EADDR 64'hffff_ffff_ffff_ffff
`define LOGPTE(tag, x) `LOGI($sformatf("%s(PPN-%h D%b A%b U%b X%b W%b R%b V%b)", \
  tag, x.PPN, x.D, x.A, x.U, x.X, x.W, x.R, x.V));
`define COLOR_NONE "\033[0m"
`define RED "\033[31m"
`define GREEN "\033[32m"
`define YELLOW "\033[33m"

typedef enum {
  SZ_1B,
  SZ_2B,
  SZ_4B,
  SZ_8B
} size_e;
typedef enum {
  SC_NONE,
  SC_SUCC,
  SC_FAIL
} sc_e;

interface mmaping;
  logic valid, ready, error;
  logic [1:0] rw;
  addr_t va, pa;

  modport master(input ready, error, pa, output valid, rw, va);
  modport slave(output ready, error, pa, input valid, rw, va);
endinterface

interface mem_access;
  logic valid, ready, error, we;
  size_e size;
  addr_t addr;
  reg_t rdata, wdata;

  modport master(input ready, error, rdata, output valid, we, addr, size, wdata);
  modport slave(output ready, error, rdata, input valid, we, addr, size, wdata);
endinterface


//-------------------------------------
// Testbench
//-------------------------------------
module top ();
  logic clk, rst_n, intr;

  initial begin
    $dumpfile("mini.vcd");
    $dumpvars(0, top);
    $timeformat(-9, 3, "", 9);
    intr = 1'b0;
    #1000 intr = 1'b1;
  end

  clkgen #(
    .COUNTER(50000)
  ) clock (
    .clk(clk),
    .rst_n(rst_n)
  );

  soc soc1 (
    .clk(clk),
    .rst_n(rst_n),
    .intr(intr)
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
    $display($sformatf("%sTIMEOUT%s", `YELLOW, `COLOR_NONE));
    #0.1 $finish;
  end

  always #1 clk = ~clk;
endmodule

//-------------------------------------
// mini
//-------------------------------------
module soc (
  input logic clk,
  input logic rst_n,
  input logic intr
);
  // id data
  logic [4:0] rs1, rs2, rd;
  logic [4:0] csr_imm;
  logic [11:0] csr_idx;
  logic br, br_taken, jump;
  logic reg_write;
  logic exec_done;
  op_src_e op_s1, op_s2;
  opcode_e opcode;
  alu_op_e alu_op;
  mem_op_e mem_op;
  sys_op_e sys_op;
  amo_op_e amo_op;
  reg_t imm;

  // exec data
  addr_t mem_addr, pc_target;
  reg_t wb_data, mem_data, mem_rdata;

  // members
  state_e state;
  addr_t pc, pa_pc;
  addr_t pa_data;
  logic fetch_ready;
  logic data_ready;
  logic pte_req, pte_ready, mmu_error;
  addr_t pte_addr;
  pte_t pte;
  reg_t mmu_causeval;
  mcause_e mmu_cause;
  mstatus_t mstatus;
  logic pte_wr_req;
  addr_t pte_wr_addr;
  pte_t pte_wr_data;
  logic tlb_invalid;

  mmaping amo_map ();
  mem_access amo_ma ();

  reg_t op_amo;
  atomic amo1 (
    .clk(clk),
    .rst_n(rst_n),
    .state(state),
    .amo_op(amo_op),
    .rs1_val(rs1_val),
    .op_amo(op_amo),
    .amo_ready(amo_ready),
    .mmap(amo_map.master),
    .ma(amo_ma.master)
  );

  mmu mmu1 (
    .clk(clk),
    .rst_n(rst_n),
    .state(state),
    .va_pc(pc),
    .pa_pc(pa_pc),
    .pc_ready(fetch_ready),
    .mem_op(mem_op),
    .va_data(mem_addr),
    .pa_data(pa_data),
    .data_ready(data_ready),
    .satp(satp),
    .priv(priv),
    .mstatus(mstatus),

    .amo(amo_map.slave),

    .pte_req(pte_req),
    .pte_addr(pte_addr),
    .pte(pte),
    .pte_ready(pte_ready),

    .error(mmu_error),
    .cause(mmu_cause),
    .causeval(mmu_causeval),
    .pte_wr_req(pte_wr_req),
    .pte_wr_addr(pte_wr_addr),
    .pte_wr_data(pte_wr_data),

    .tlb_invalid(tlb_invalid)
  );

  decoder decoder1 (
    .instr(instr),
    .state(state),
    .rs1(rs1),
    .rs2(rs2),
    .rd(rd),
    .alu_op(alu_op),
    .sys_op(sys_op),
    .mem_op(mem_op),
    .amo_op(amo_op),
    .op_s1(op_s1),
    .op_s2(op_s2),
    .imm(imm),
    .reg_write(reg_write),
    .br(br),
    .jump(jump),
    .csr_imm(csr_imm),
    .csr_idx(csr_idx),
    .opcode(opcode)
  );


  logic halt;
  exec exec1 (
    .clk(clk),
    .rst_n(rst_n),
    .opcode(opcode),
    .state(state),
    .reg_write(reg_write),
    .br(br),
    .alu_op(alu_op),
    .sys_op(sys_op),
    .mem_op(mem_op),
    .amo_op(amo_op),
    .op_s1(op_s1),
    .op_s2(op_s2),
    .rs1_val(rs1_val),
    .rs2_val(rs2_val),
    .csr_val(csr_val),
    .trap_target(trap_target),
    .imm(imm),
    .op_amo(op_amo),
    .csr_imm(csr_imm),
    .pc(pc),
    .br_taken(br_taken),
    .pc_target(pc_target),
    .mem_addr(mem_addr),
    .mem_data(mem_data),
    .wb_data(wb_data),
    .rs2(rs2),
    .csr_wdata(csr_wdata),
    .done(exec_done),
    .halt(halt)
  );

  // register file
  reg_t rs1_val, rs2_val;
  registerfile rf1 (
    .clk(clk),
    .rst_n(rst_n),
    .state(state),
    .we(reg_write),
    .rd(rd),
    .wdata((mem_op > MEM_NONE && mem_op < MEM_SEP) ? mem_rdata : wb_data),
    .rs1(rs1),
    .rs2(rs2),
    .rs1_val(rs1_val),
    .rs2_val(rs2_val),
    .sc(sc)
  );

  // csr
  reg_t csr_val, csr_wdata;
  reg_t trap_target;
  logic irqt, irqe, interrupted;
  satp_t satp;
  priv_lvl_e priv;
  csr csr1 (
    .clk(clk),
    .rst_n(rst_n),
    .pc(pc),
    .state(state),
    .sys_op(sys_op),
    .csr_wdata(csr_wdata),
    .csr_idx(csr_idx),
    .csr_val(csr_val),
    .trap_target(trap_target),
    .irq_timer(irqt),
    .irq_external(intr),
    .interrupted(interrupted),
    .satp_o(satp),
    .priv_o(priv),
    .mstatus_o(mstatus),
    .mmu_exc(mmu_error),
    .mmu_cause(mmu_cause),
    .mmu_causeval(mmu_causeval),
    .tlb_invalid(tlb_invalid)
  );

  // rom
  logic [31:0] instr, instr1, instr2;
  rom #(
    .HEX("isa/div.hex")
  ) rom1 (
    .clk(clk),
    .rst_n(rst_n),
    .pc(pa_pc),
    .instr(instr1)
  );

  // sram
  logic amo_ready;
  sc_e sc;
  sram sram1 (
    .clk(clk),
    .rst_n(rst_n),
    .state(state),
    .mem_addr(pa_data),
    .mem_op(mem_op),
    .amo_op(amo_op),
    .mem_rdata(mem_rdata),
    .mem_data(mem_data),
    .data_ready(data_ready),
    .pte_req(pte_req),
    .pte_addr(pte_addr),
    .pte(pte),
    .pte_ready(pte_ready),
    .pte_wr_req(pte_wr_req),
    .pte_wr_addr(pte_wr_addr),
    .pte_wr_data(pte_wr_data),
    .mmu_error(mmu_error),
    .pc(pa_pc),
    .instr(instr2),
    .amo(amo_ma.slave),
    .sc(sc)
  );

  assign instr = instr1 != 0 ? instr1 : instr2;

  uart uart1 (
    .clk(clk),
    .rst_n(rst_n),
    .addr(pa_data),
    .state(state),
    .mem_op(mem_op),
    .data(mem_data)
  );

  // for rvtest
  rvtest rvt1 (
    .clk(clk),
    .rst_n(rst_n),
    .addr(pa_data),
    .state(state),
    .mem_op(mem_op),
    .data(mem_data)
  );

  //---------------------------------
  // state machine
  //---------------------------------
  logic amo_in = !(amo_op inside {AMO_NONE, AMO_LR, AMO_LRW, AMO_SC, AMO_SCW});
  // logic amo_in = (amo_op != AMO_NONE);
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      `LOGW("reset");
      state <= IDLE;
      pc <= 64'h0000_0000_8000_0000;
    end else begin
      unique case (state)
        IDLE: state <= FETCH;
        FETCH: begin
          if (fetch_ready) begin
            `LOGI($sformatf("fetch pc=%h pa=%h instr=%h", pc, pa_pc, instr));
            state <= DECODE;
          end
        end
        DECODE: begin
          if (amo_in) begin
            state <= AMOMEM;
          end else begin
            state <= EXEC;
          end
        end
        AMOMEM: begin
          if (amo_ready) state <= EXEC;
        end
        EXEC: begin
          `LOGI($sformatf("exec_done: %b", exec_done));
          if (exec_done) begin
            if (mem_op != MEM_NONE) begin
              state <= MEMACCESS;
            end else begin
              state <= WB;
            end
          end
        end
        MEMACCESS: begin
          if (data_ready) begin
            state <= WB;
          end
        end
        WB: begin
          if (!halt) begin
            state <= FETCH;
            pc <= new_target != `EADDR ? new_target : pc + 4;
          end else begin
            // WFI wait for interrupted
            if (interrupted) begin
              `LOGI("INT");
              state <= FETCH;
              pc <= new_target != `EADDR ? new_target : pc + 4;
            end
          end
          trap_target <= '1;
        end
        default: ;
      endcase
    end
  end

  addr_t new_target;
  always_comb begin
    if (trap_target != `EADDR) begin
      new_target = trap_target;
    end else if (pc_target != `EADDR) begin
      new_target = pc_target;
    end else begin
      new_target = `EADDR;
    end
  end
endmodule

//---------------------------------------------
// data types and structures
//---------------------------------------------
localparam int unsigned REGMAX = 32;
typedef logic [63:0] addr_t;
typedef logic [63:0] reg_t;

typedef enum {
  IDLE,
  FETCH,
  DECODE,
  AMOMEM,
  EXEC,
  MEMACCESS,
  WB
} state_e;

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
  ALU_BGEU,

  ALU_MUL,     // rs1 * rs2
  ALU_MULH,    // rs1 * rs2 high 64bit
  ALU_MULHSU,  // rs1(s) * rs2(u) high 64bit
  ALU_MULHU,   // rs1(u) * rs2(u) high 64bit
  ALU_DIV,     // rs1(s) / rs2(s)
  ALU_DIVU,    // rs1(u) / rs2(u)
  ALU_REM,     // rs1(s) % rs2(s)
  ALU_REMU,    // rs1(u) % rs2(u)

  // 32bit
  ALU_MULW,   // rd[0:31] = rs1[31:0] * rs2[31:0]; rd[31] -> rd[63:32]
  ALU_DIVW,   // rd[0:31] = rs1[31:0](s) / rs2[31:0](s); rd[31] -> rd[63:32]
  ALU_DIVUW,  // rd[0:31] = rs1[31:0](u) / rs2[31:0](u); rd[31] -> rd[63:32]
  ALU_REMW,   // rd[0:31] = rs1[31:0](s) % rs2[31:0](s); rd[31] -> rd[63:32]
  ALU_REMUW   // rd[0:31] = rs1[31:0](u) % rs2[31:0](u); rd[31] -> rd[63:32]
} alu_op_e;

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

// reg_t mstatus, mtvec, mtval, mepc, mcause, mie, mip, mhartid, medeleg, mideleg, misa, mscratch;
// reg_t stvec, stval, sepc, scause, sscratch, satp;
typedef enum logic [11:0] {
  // csr register in M mode
  MSTATUS  = 12'h300,
  MISA     = 12'h301,
  MEDELEG  = 12'h302,
  MIDELEG  = 12'h303,
  MIE      = 12'h304,
  MTVEC    = 12'h305,
  MSCRATCH = 12'h340,
  MEPC     = 12'h341,
  MCAUSE   = 12'h342,
  MTVAL    = 12'h343,
  MIP      = 12'h344,
  MHARTID  = 12'hf14,

  // csr register in s mode
  SSTATUS  = 12'h100,
  SIE      = 12'h104,
  STVEC    = 12'h105,
  SSCRATCH = 12'h140,
  SEPC     = 12'h141,
  SCAUSE   = 12'h142,
  STVAL    = 12'h143,
  SIP      = 12'h144,
  SATP     = 12'h180
} csr_e;

typedef enum {
  MEM_NONE,
  LD_LB,
  LD_LH,
  LD_LW,
  LD_LD,
  LD_LBU,  // 5
  LD_LHU,
  LD_LWU,
  MEM_SEP,
  SD_SB,
  SD_SH,  // 10
  SD_SW,
  SD_SD
} mem_op_e;


typedef enum {
  B_NONE,
  B_BEQ,
  B_BNE,
  B_BLT,
  B_GE,
  B_BLTU,
  B_BGEU
} branch_op_e;

typedef enum {
  OP_SRC_NONE,
  OP_SRC_REG,
  OP_SRC_IMM,
  OP_SRC_AMO,
  OP_SRC_PC
} op_src_e;

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
  EXC_ECALL_M_MODE          = 64'hB,  // M模式环境调用
  EXC_INSTR_PAGE_FAULT      = 64'hC,  // 指令页面错误
  EXC_LOAD_PAGE_FAULT       = 64'hD,  // 加载页面错误
  EXC_STORE_PAGE_FAULT      = 64'hF,  // 存储/AMO页面错误

  INTR_SUPERVISOR_SW  = 64'h8000_0000_0000_0001,  // 监督级软件中断
  INTR_MACHINE_SW     = 64'h8000_0000_0000_0003,  // 机器级软件中断
  INTR_SUPERVISOR_TMR = 64'h8000_0000_0000_0005,  // 监督级定时器中断
  INTR_MACHINE_TMR    = 64'h8000_0000_0000_0007,  // 机器级定时器中断
  INTR_SUPERVISOR_EXT = 64'h8000_0000_0000_0009,  // 监督级外部中断
  INTR_MACHINE_EXT    = 64'h8000_0000_0000_000B   // 机器级外部中断
} mcause_e;

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
} mstatus_t;

typedef struct packed {
  logic [63:48] custom_63_48;              // [63:48] Designated for custom use / reserved
  logic [47:32] reserved_47_32;            // [47:32] reserved
  logic [31:24] custom_31_24;              // [31:24] Designated for custom use
  logic [23:20] reserved_23_20;            // [23:20] Reserved
  logic         hardware_error;            // [19]   hardware error
  logic         software_check;            // [18]   software check
  logic         reserved_17;               // [17]   Reserved
  logic         double_trap;               // [16]   double trap
  logic         store_amo_page_fault;      // [15]   Store/AMO page fault
  logic         reserved_14;               // [14]   Reserved
  logic         load_page_fault;           // [13]   Load page fault
  logic         instruction_page_fault;    // [12]  Instruction page fault
  logic         ecall_from_m_mode;         // [11] ecall from m-mode
  logic         reserved_10;               // [10] Reserved
  logic         ecall_from_s_mode;         // [9]    Environment call from S-mode
  logic         ecall_from_u_mode;         // [8]    Environment call from U-mode
  logic         store_amo_access_fault;    // [7]   Store/AMO access fault
  logic         store_amo_misaligned;      // [6]    Store/AMO address misaligned
  logic         load_access_fault;         // [5]    Load access fault
  logic         load_misaligned;           // [4]    Load address misaligned
  logic         breakpoint;                // [3]    Breakpoint
  logic         illegal_instruction;       // [2]    Illegal instruction
  logic         instruction_access_fault;  // [1] Instruction access fault
  logic         instruction_misaligned;    // [0] Instruction address misaligned
} medeleg_t;

typedef struct packed {
  logic [63:12] reserved_63_12;  // [63:12] Reserved / Designated for platform use
  logic         MEI;             // [11] Machine external interrupt
  logic         reserved_10;     // [10]   Reserved
  logic         SEI;             // [9]  Supervisor external interrupt
  logic         reserved_8;      // [8]    Reserved
  logic         MTI;             // [7]  Machine timer interrupt
  logic         reserved_6;      // [6]    Reserved
  logic         STI;             // [5]  Supervisor timer interrupt
  logic         reserved_4;      // [4]    Reserved
  logic         MSI;             // [3]  Machine software interrupt
  logic         reserved_2;      // [2]    Reserved
  logic         SSI;             // [1]  Supervisor software interrupt
  logic         reserved_0;      // [0]    Reserved
} mintr_t;

typedef struct packed {
  logic [63:62] MXL;
  logic [61:26] reserved_26_61;
  logic Z;
  logic Y;
  logic X;
  logic W;
  logic V;
  logic U;
  logic T;
  logic S;
  logic R;
  logic Q;
  logic P;
  logic O;
  logic N;
  logic M;
  logic L;
  logic K;
  logic J;
  logic I;
  logic H;
  logic G;
  logic F;
  logic E;
  logic D;
  logic C;
  logic B;
  logic A;
} misa_t;

typedef struct packed {
  logic [63:60] MODE;  // [63:60] Mode: Address translation mode (Sv39=8, Sv48=9, Sv57=10, Bare=0)
  logic [59:44] ASID;  // [59:44] ASID: Address Space Identifier
  logic [43:0]  PPN;   // [43:0]  PPN: Physical Page Number of the root page table
} satp_t;

typedef struct packed {
  logic         N;               // [63] N
  logic [62:61] PBMT;            // [62:61] PBMT
  logic [60:54] reserved_54_60;  // [60:54] reserved
  logic [53:10] PPN;             // [53:10] PPN: Physical Page Number
  logic [9:8]   RSW;             // [9:8]  RSW: Reserved for use by supervisor software
  logic         D;               // [7]    D: Dirty bit
  logic         A;               // [6]    A: Accessed bit
  logic         G;               // [5]    G: Global bit
  logic         U;               // [4]    U: User bit
  logic         X;               // [3]    X: Execute permission
  logic         W;               // [2]    W: Write permission
  logic         R;               // [1]    R: Read permission
  logic         V;               // [0]    V: Valid bit
} pte_t;

`define PTE_A 64'h40
`define PTE_D 64'h80

typedef enum logic [1:0] {
  M_USER = 2'b00,
  M_SUPER = 2'b01,
  M_MACHINE = 2'b11
} priv_lvl_e;

typedef enum logic [1:0] {
  PG_4K,
  PG_2M,
  PG_1G
} pagesize_e;

typedef struct packed {
  pagesize_e   PGSIZE;  // page size
  logic [15:0] ASID;    // 地址空间标识符
  logic [26:0] VPN;     // 虚拟页号
  logic [43:0] PPN;     // 物理页号
  logic        V;       // 有效位 (Valid)
  logic        G;       // 全局位 (Global)
  logic        U;       // 用户态权限 (User)
  logic        X;       // 可执行权限 (Execute)
  logic        W;       // 可写权限 (Write)
  logic        R;       // 可读权限 (Read)
  logic        D;       // 脏位 (Dirty)
  logic        A;       // 已访问位 (Accessed)
} tlb_entry_t;

//-----------------------------------
// decoder
//-----------------------------------
module decoder (
  input logic [31:0] instr,
  input state_e state,
  output logic [4:0] rs1,
  output logic [4:0] rs2,
  output logic [4:0] rd,
  output alu_op_e alu_op,
  output sys_op_e sys_op,
  output mem_op_e mem_op,
  output amo_op_e amo_op,
  output op_src_e op_s1,
  output op_src_e op_s2,
  output reg_t imm,
  output logic reg_write,
  output logic br,
  output logic jump,
  output logic [4:0] csr_imm,
  output logic [11:0] csr_idx,
  output opcode_e opcode
);
  logic [2:0] f3;
  logic [6:0] f7;
  logic [9:0] fc;
  imm_type_e imm_type;

  always_comb begin : decode
    if (state == DECODE) begin
      alu_op = ALU_NONE;
      sys_op = SYS_NONE;
      mem_op = MEM_NONE;
      amo_op = AMO_NONE;
      imm_type = IMM_NONE;
      op_s1 = OP_SRC_NONE;
      op_s2 = OP_SRC_NONE;
      reg_write = 0;
      br = 1'b0;
      jump = 1'b0;
      csr_imm = '0;
      csr_idx = '0;

      rs1 = instr[19:15];
      rs2 = instr[24:20];
      rd = instr[11:7];
      f3 = instr[14:12];
      f7 = instr[31:25];
      opcode = opcode_e'(instr[6:0]);

      fc = {f7, f3};
      unique case (opcode)
        OPCODE_OP: begin
          `LOGI("OP");
          // 002081b3: add x3, x1, x2
          // add rd, rs1, rs2
          // ALU: rs1 <op> rs2
          reg_write = 1;
          op_s1 = OP_SRC_REG;
          op_s2 = OP_SRC_REG;
          unique case (fc)
            {7'b0000000, 3'b000} : alu_op = ALU_ADD;
            {7'b0100000, 3'b000} : alu_op = ALU_SUB;
            {7'b0000000, 3'b111} : alu_op = ALU_AND;
            {7'b0000000, 3'b110} : alu_op = ALU_OR;
            {7'b0000000, 3'b100} : alu_op = ALU_XOR;
            {7'b0000000, 3'b001} : alu_op = ALU_SLL;
            {7'b0000000, 3'b101} : alu_op = ALU_SRL;
            {7'b0100000, 3'b101} : alu_op = ALU_SRA;
            {7'b0000000, 3'b010} : alu_op = ALU_SLT;
            {7'b0000000, 3'b011} : alu_op = ALU_SLTU;
            {7'b0000001, 3'b000} : alu_op = ALU_MUL;
            {7'b0000001, 3'b001} : alu_op = ALU_MULH;
            {7'b0000001, 3'b010} : alu_op = ALU_MULHSU;
            {7'b0000001, 3'b011} : alu_op = ALU_MULHU;
            {7'b0000001, 3'b100} : alu_op = ALU_DIV;
            {7'b0000001, 3'b101} : alu_op = ALU_DIVU;
            {7'b0000001, 3'b110} : alu_op = ALU_REM;
            {7'b0000001, 3'b111} : alu_op = ALU_REMU;

            default: ;
          endcase
        end
        OPCODE_OP_32: begin
          // R-type: rd = rs1 op rs2 (32-bit + sign extend)
          reg_write = 1;
          op_s1 = OP_SRC_REG;
          op_s2 = OP_SRC_REG;
          unique case (fc)
            {7'b0000000, 3'b000} : alu_op = ALU_ADDW;
            {7'b0100000, 3'b000} : alu_op = ALU_SUBW;
            {7'b0000000, 3'b001} : alu_op = ALU_SLLW;
            {7'b0000000, 3'b101} : alu_op = ALU_SRLW;
            {7'b0100000, 3'b101} : alu_op = ALU_SRAW;
            {7'b0000001, 3'b000} : alu_op = ALU_MULW;
            {7'b0000001, 3'b100} : alu_op = ALU_DIVW;
            {7'b0000001, 3'b101} : alu_op = ALU_DIVUW;
            {7'b0000001, 3'b110} : alu_op = ALU_REMW;
            {7'b0000001, 3'b111} : alu_op = ALU_REMUW;
            default: ;
          endcase
        end
        OPCODE_OP_IMM: begin
          `LOGI("OP_IMM");
          // 00500093: addi x1, x0, 5
          // addi rd, rs1, imm
          // ALU: rs1 <op> imm;
          reg_write = 1;
          op_s1 = OP_SRC_REG;
          op_s2 = OP_SRC_IMM;
          imm_type = IMM_I;
          unique case (f3)
            3'b000:  alu_op = ALU_ADD;
            3'b001:  alu_op = ALU_SLL;
            3'b010:  alu_op = ALU_SLT;
            3'b011:  alu_op = ALU_SLTU;
            3'b100:  alu_op = ALU_XOR;
            3'b110:  alu_op = ALU_OR;
            3'b101:  alu_op = (f7[5]) ? ALU_SRA : ALU_SRL;
            3'b111:  alu_op = ALU_AND;
            default: ;
          endcase
          `LOGI($sformatf("aluop:%0d", alu_op));
        end
        OPCODE_OP_IMM_32: begin
          `LOGI("OP_IMM32");
          // 00500093: addiw x1, x0, 5
          // addi rd, rs1, imm
          // ALU: rs1 <op> imm;
          reg_write = 1;
          op_s1 = OP_SRC_REG;
          op_s2 = OP_SRC_IMM;
          imm_type = IMM_I;
          unique case (f3)
            3'b000:  alu_op = ALU_ADDW;
            default: ;
          endcase
          unique case (fc)
            {7'b0000000, 3'b001} : alu_op = ALU_SLLW;
            {7'b0000000, 3'b101} : alu_op = ALU_SRLW;
            {7'b0100000, 3'b101} : alu_op = ALU_SRAW;
            default: ;
          endcase
        end
        OPCODE_LOAD: begin
          `LOGI("LOAD");
          // 00003283: ld x5, 0(x0)
          // ld rd, offset(rs1)
          // ALU: addr= rs1 + offset
          // rd = mem[addr]
          reg_write = 1;
          alu_op = ALU_ADD;
          imm_type = IMM_I;
          op_s1 = OP_SRC_REG;
          op_s2 = OP_SRC_IMM;
          unique case (f3)
            3'b000:  mem_op = LD_LB;
            3'b001:  mem_op = LD_LH;
            3'b010:  mem_op = LD_LW;
            3'b011:  mem_op = LD_LD;
            3'b100:  mem_op = LD_LBU;
            3'b101:  mem_op = LD_LHU;
            3'b110:  mem_op = LD_LWU;
            default: ;
          endcase
        end
        OPCODE_STORE: begin
          `LOGI("STORE");
          // 00403023: sd x4, 0(x0)
          // ALU: addr = rs1 + imm;
          // mem[addr] = rs2
          reg_write = 0;
          alu_op = ALU_ADD;
          imm_type = IMM_S;
          op_s1 = OP_SRC_REG;
          op_s2 = OP_SRC_IMM;
          unique case (f3)
            3'b000:  mem_op = SD_SB;
            3'b001:  mem_op = SD_SH;
            3'b010:  mem_op = SD_SW;
            3'b011:  mem_op = SD_SD;
            default: ;
          endcase
        end
        OPCODE_BRANCH: begin
          `LOGI("BRANCH");
          // 00628663: beq  x5, x6, +12
          // beq rs1, rs2, imm(label)
          // take_branch ? PC=PC+imm : PC=PC+4;
          br = 1'b1;
          imm_type = IMM_B;
          op_s1 = OP_SRC_REG;
          op_s2 = OP_SRC_REG;
          unique case (f3)
            3'b000:  alu_op = ALU_BEQ;
            3'b001:  alu_op = ALU_BNE;
            3'b100:  alu_op = ALU_BLT;
            3'b101:  alu_op = ALU_BGE;
            3'b110:  alu_op = ALU_BLTU;
            3'b111:  alu_op = ALU_BGEU;
            default: ;
          endcase
        end
        OPCODE_JAL: begin
          `LOGI("JAL");
          // 008000ef: jal rd, imm
          // rd = PC+4; PC=PC+imm;
          jump = 1'b1;
          imm_type = IMM_J;
          reg_write = 1;
          alu_op = ALU_ADD;
          op_s1 = OP_SRC_PC;
          op_s2 = OP_SRC_IMM;
        end
        OPCODE_JALR: begin
          `LOGI("JALR");
          // 00008067: jalr rd, imm(rs1)
          // rd = PC+4; PC = (rs1 + imm) & ~1 ;
          jump = 1'b1;
          imm_type = IMM_I;
          reg_write = 1;
          alu_op = ALU_ADD;
          op_s1 = OP_SRC_REG;
          op_s2 = OP_SRC_IMM;
        end
        OPCODE_AUIPC: begin
          `LOGI("AUIPC");
          // auipc rd, imm
          // rd = PC + (imm << 12)
          imm_type = IMM_U;
          reg_write = 1;
          alu_op = ALU_ADD;
          op_s1 = OP_SRC_PC;
          op_s2 = OP_SRC_IMM;
        end
        OPCODE_LUI: begin
          `LOGI("LUI");
          // lui rd, imm
          // rd = (imm << 12)
          // ALU: x0 + (imm << 12);
          imm_type = IMM_U;
          reg_write = 1;
          alu_op = ALU_ADD;
          rs1 = 0;
          op_s1 = OP_SRC_REG;
          op_s2 = OP_SRC_IMM;
        end

        OPCODE_SYSTEM: begin
          `LOGI("SYSTEM");
          unique case (f3)
            3'b000: begin
              unique case (instr[31:20])
                12'h000: sys_op = SYS_ECALL;
                12'h001: sys_op = SYS_EBREAK;
                12'h002: sys_op = SYS_URET;
                12'h102: sys_op = SYS_SRET;
                12'h105: sys_op = SYS_WFI;
                12'h302: sys_op = SYS_MRET;
                default: ;
              endcase
              if (f7 == 7'b0001001) begin
                sys_op = SYS_FENCE;
              end
            end
            3'b001: begin
              // csrrw rd, csr, rs1
              // x[rd] = CSRs[csr]; CSRs[csr] = x[rs1]
              csr_idx = instr[31:20];
              reg_write = 1;
              sys_op = SYS_CSRRW;
            end
            3'b010: begin
              csr_idx = instr[31:20];
              reg_write = 1;
              sys_op = SYS_CSRRS;
            end
            3'b011: begin  // CSRRC
              csr_idx = instr[31:20];
              sys_op    = SYS_CSRRC;
              reg_write = 1;
            end

            3'b101: begin  // CSRRWI
              csr_idx = instr[31:20];
              sys_op    = SYS_CSRRWI;
              reg_write = 1;
              csr_imm = rs1;
            end

            3'b110: begin  // CSRRSI
              csr_idx = instr[31:20];
              sys_op    = SYS_CSRRSI;
              reg_write = 1;
              csr_imm = rs1;
            end

            3'b111: begin  // CSRRCI
              csr_idx = instr[31:20];
              sys_op    = SYS_CSRRCI;
              reg_write = 1;
              csr_imm = rs1;
            end
            default: ;
          endcase
        end
        OPCODE_AMO: begin
          `LOGI("AMO");
          reg_write = 1;
          op_s1 = OP_SRC_AMO;
          op_s2 = OP_SRC_REG;
          unique case (fc)
            // verilog_format: off
            {7'b0001000, 3'b010} : begin amo_op = AMO_LRW; mem_op = LD_LW; end
            {7'b0001100, 3'b010} : begin amo_op = AMO_SCW; mem_op = SD_SW; end
            {7'b0001000, 3'b011} : begin amo_op = AMO_LR; mem_op = LD_LD; end
            {7'b0001100, 3'b011} : begin amo_op = AMO_SC; mem_op = SD_SD; end
            {7'b0000100, 3'b010} : begin amo_op = AMO_SWAPW; mem_op = SD_SW; end
            {7'b0000000, 3'b010} : begin amo_op = AMO_ADDW; alu_op = ALU_ADDW; mem_op = SD_SW; end
            {7'b0010000, 3'b010} : begin amo_op = AMO_XORW; alu_op = ALU_XOR; mem_op = SD_SW; end
            {7'b0100000, 3'b010} : begin amo_op = AMO_ORW; alu_op = ALU_OR; mem_op = SD_SW; end
            {7'b0110000, 3'b010} : begin amo_op = AMO_ANDW; alu_op = ALU_AND; mem_op = SD_SW; end
            {7'b1000000, 3'b010} : begin amo_op = AMO_MINW; alu_op = ALU_SLT; mem_op = SD_SW; end
            {7'b1010000, 3'b010} : begin amo_op = AMO_MAXW; alu_op = ALU_SLT; mem_op = SD_SW; end
            {7'b1100000, 3'b010} : begin amo_op = AMO_MINUW; alu_op = ALU_SLTU; mem_op = SD_SW; end
            {7'b1110000, 3'b010} : begin amo_op = AMO_MAXUW; alu_op = ALU_SLTU; mem_op = SD_SW; end
            {7'b0000100, 3'b011} : begin amo_op = AMO_SWAP; mem_op = SD_SD; end
            {7'b0000000, 3'b011} : begin amo_op = AMO_ADD; alu_op = ALU_ADD; mem_op = SD_SD; end
            {7'b0010000, 3'b011} : begin amo_op = AMO_XOR; alu_op = ALU_XOR; mem_op = SD_SD; end
            {7'b0100000, 3'b011} : begin amo_op = AMO_OR; alu_op = ALU_OR; mem_op = SD_SD; end
            {7'b0110000, 3'b011} : begin amo_op = AMO_AND; alu_op = ALU_AND; mem_op = SD_SD; end
            {7'b1000000, 3'b011} : begin amo_op = AMO_MIN; alu_op = ALU_SLT; mem_op = SD_SD; end
            {7'b1010000, 3'b011} : begin amo_op = AMO_MAX; alu_op = ALU_SLT; mem_op = SD_SD; end
            {7'b1100000, 3'b011} : begin amo_op = AMO_MINU; alu_op = ALU_SLTU; mem_op = SD_SD; end
            {7'b1110000, 3'b011} : begin amo_op = AMO_MAXU; alu_op = ALU_SLTU; mem_op = SD_SD; end
            // verilog_format: on
            default: amo_op = AMO_NONE;
          endcase
        end
        default: ;
      endcase

      unique case (imm_type)
        IMM_I:   imm = {{52{instr[31]}}, instr[31:20]};
        IMM_S:   imm = {{52{instr[31]}}, instr[31:25], instr[11:7]};
        IMM_B:   imm = {{51{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
        IMM_U:   imm = {{32{instr[31]}}, instr[31:12], 12'b0};
        IMM_J:   imm = {{43{instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0};
        default: imm = '0;
      endcase
    end
  end
endmodule

//-----------------------------------
// exec
//-----------------------------------
module exec (
  input logic clk,
  input logic rst_n,
  input opcode_e opcode,
  input state_e state,
  input logic reg_write,
  input logic br,
  input alu_op_e alu_op,
  input sys_op_e sys_op,
  input mem_op_e mem_op,
  input amo_op_e amo_op,
  input op_src_e op_s1,
  input op_src_e op_s2,
  input reg_t rs1_val,
  input reg_t rs2_val,
  input reg_t csr_val,
  input reg_t trap_target,
  input reg_t imm,
  input reg_t op_amo,
  input [4:0] csr_imm,
  input [4:0] rs2,
  input addr_t pc,


  output logic  br_taken,
  output addr_t pc_target,
  output addr_t mem_addr,
  output reg_t  wb_data,
  output reg_t  mem_data,
  output reg_t  csr_wdata,
  output logic  done,
  output logic  halt
);
  reg_t alu_result;
  reg_t mult_result;
  reg_t div_result;
  logic [63:0] op1, op2;
  logic [31:0] w_result;
  logic divdone;

  mult mult1 (
    .clk(clk),
    .rst_n(rst_n),
    .state(state),
    .alu_op(alu_op),
    .op1(rs1_val),
    .op2(rs2_val),
    .result(mult_result)
  );

  divider div1 (
    .clk(clk),
    .rst_n(rst_n),
    .state(state),
    .alu_op(alu_op),
    .op1(rs1_val),
    .op2(rs2_val),
    .result(div_result),
    .done(done)
  );


  always_comb begin : exec
    if (state == EXEC) begin
      br_taken  = 1'b0;
      wb_data   = '0;
      mem_data  = '0;
      pc_target = '1;
      // op1 = (op_s1 == OP_SRC_REG) ? rs1_val : pc;
      unique case (op_s1)
        OP_SRC_REG: op1 = rs1_val;
        OP_SRC_PC: op1 = pc;
        OP_SRC_AMO: op1 = op_amo;
        default: ;
      endcase
      op2  = (op_s2 == OP_SRC_REG) ? rs2_val : imm;
      halt = 1'b0;

      `LOGI($sformatf("alu_op:%0d op1:%h op2:%h", alu_op, op1, op2));
      unique case (alu_op)
        ALU_ADD:  alu_result = op1 + op2;
        ALU_SUB:  alu_result = op1 - op2;
        ALU_AND:  alu_result = op1 & op2;
        ALU_OR:   alu_result = op1 | op2;
        ALU_XOR:  alu_result = op1 ^ op2;
        ALU_SLL:  alu_result = op1 << op2[5:0];
        ALU_SRL:  alu_result = op1 >> op2[5:0];
        ALU_SRA:  alu_result = $signed(op1) >>> op2[5:0];
        ALU_SLT:  alu_result = ($signed(op1) < $signed(op2)) ? 64'd1 : 64'd0;
        ALU_SLTU: alu_result = (op1 < op2) ? 64'd1 : 64'd0;
        ALU_BNE:  alu_result = (op1 != op2) ? 1 : 0;
        ALU_BEQ:  alu_result = (op1 == op2) ? 1 : 0;
        ALU_BLT:  alu_result = ($signed(op1) < $signed(op2)) ? 1 : 0;
        ALU_BGE:  alu_result = ($signed(op1) >= $signed(op2)) ? 1 : 0;
        ALU_BLTU: alu_result = (op1 < op2) ? 1 : 0;
        ALU_BGEU: alu_result = (op1 >= op2) ? 1 : 0;

        ALU_ADDW: begin
          w_result   = op1[31:0] + op2[31:0];
          alu_result = {{32{w_result[31]}}, w_result};
        end
        ALU_SUBW: begin
          w_result   = op1[31:0] - op2[31:0];
          alu_result = {{32{w_result[31]}}, w_result};
        end
        ALU_SLLW: begin
          w_result   = op1[31:0] << op2[4:0];
          alu_result = {{32{w_result[31]}}, w_result};
        end
        ALU_SRLW: begin
          w_result   = op1[31:0] >> op2[4:0];
          alu_result = {{32{w_result[31]}}, w_result};
        end
        ALU_SRAW: begin
          w_result   = $signed(op1[31:0]) >>> op2[4:0];
          alu_result = {{32{w_result[31]}}, w_result};
        end
        default: alu_result = '0;
      endcase

      unique case (sys_op)
        SYS_ECALL: begin
          // record mcause=11; mepc = pc + 4; mpie=mstatus; mie = 0; pc=mtvec;
          // pc_target = trap_target;
        end
        SYS_EBREAK: begin
          $finish;
        end
        SYS_MRET: begin
          // pc = mepc;
          // pc_target = trap_target;
        end
        SYS_WFI: begin
          `LOGI("WFI");
          halt = 1'b1;
        end
        SYS_CSRRW: begin
          `LOGI($sformatf("csrrw: %h %h", csr_val, rs1_val));
          // csrrw rd, csr, rs1
          // x[rd] = CSRs[csr]; CSRs[csr] = x[rs1]
          wb_data   = csr_val;
          csr_wdata = rs1_val;
        end
        SYS_CSRRS: begin
          `LOGI($sformatf("csrrs: %h %h", csr_val, rs1_val));
          wb_data   = csr_val;
          csr_wdata = csr_val | rs1_val;
        end
        SYS_CSRRC: begin
          `LOGI($sformatf("csrrc: %h %h", csr_val, rs1_val));
          wb_data   = csr_val;
          csr_wdata = csr_val & (~rs1_val);
        end
        SYS_CSRRWI: begin
          `LOGI($sformatf("csrrwi: %h %h", csr_val, csr_imm));
          wb_data   = csr_val;
          csr_wdata = {{59{1'b0}}, csr_imm};
        end
        SYS_CSRRSI: begin
          `LOGI($sformatf("csrrsi: %h %h", csr_val, csr_imm));
          wb_data   = csr_val;
          csr_wdata = csr_val | {{59{1'b0}}, csr_imm};
        end
        SYS_CSRRCI: begin
          `LOGI($sformatf("csrrci: %h %h", csr_val, csr_imm));
          wb_data   = csr_val;
          csr_wdata = csr_val & (~{{59{1'b0}}, csr_imm});
        end
        default: ;
      endcase

      unique case (amo_op)
        AMO_MAX, AMO_MAXU: alu_result = alu_result == 0 ? op_amo : rs2_val;
        AMO_MIN, AMO_MINU: alu_result = alu_result == 0 ? rs2_val : op_amo;
        AMO_MAXW: alu_result = ($signed(op_amo[31:0]) > $signed(rs2_val[31:0])) ? op_amo : rs2_val;
        AMO_MAXUW: alu_result = (op_amo[31:0] > rs2_val[31:0]) ? op_amo : rs2_val;
        AMO_MINW: alu_result = ($signed(op_amo[31:0]) < $signed(rs2_val[31:0])) ? op_amo : rs2_val;
        AMO_MINUW: alu_result = (op_amo[31:0] < rs2_val[31:0]) ? op_amo : rs2_val;
        AMO_SWAP: begin
          alu_result = rs2_val;
        end
        AMO_SWAPW: begin
          alu_result = {32'(rs2_val[31]), rs2_val[31:0]};
        end
        AMO_SCW, AMO_SC: begin
          alu_result = rs2_val;
        end
        default: ;
      endcase

      if (reg_write) begin
        if (alu_op != ALU_NONE) begin
          if (amo_op == AMO_NONE) begin
            if (alu_op inside {ALU_MUL, ALU_MULH, ALU_MULHU, ALU_MULHSU, ALU_MULW}) begin
              wb_data = mult_result;
            end else if (alu_op inside {ALU_DIV, ALU_DIVU, ALU_DIVW, ALU_DIVUW, ALU_REM, ALU_REMW, ALU_REMU, ALU_REMUW}) begin
              wb_data = div_result;
            end else begin
              wb_data = alu_result;
            end
          end else begin
            wb_data = op_amo;
          end
        end else begin
          if (amo_op != AMO_NONE) begin
            wb_data = op_amo;
          end
        end
      end
      if (br == 1) begin
        br_taken = alu_result[0];
        if (br_taken) begin
          pc_target = pc + imm;
        end
      end
      if (opcode == OPCODE_JAL) begin
        // rd = PC+4; PC=PC+imm;
        wb_data   = pc + 4;
        pc_target = alu_result;
      end else if (opcode == OPCODE_JALR) begin
        // rd = PC+4; PC = (rs1 + imm) & ~1 ;
        wb_data   = pc + 4;
        pc_target = alu_result & ~1;
      end

      if (mem_op != MEM_NONE) begin
        if (amo_op == AMO_NONE) begin
          mem_addr = alu_result;
          if (mem_op > MEM_SEP) mem_data = rs2_val;
        end else begin
          mem_addr = rs1_val;
          mem_data = alu_result;
        end
      end
    end
  end

endmodule

//-----------------------------------
// multiplier
//-----------------------------------
module mult (
  input logic clk,
  input logic rst_n,
  input state_e state,
  input alu_op_e alu_op,
  input reg_t op1,
  input reg_t op2,
  output reg_t result
);

  logic signed [64:0] opa, opb;
  logic signed [129:0] full;
  always_comb begin
    if (state == EXEC) begin
      opa = '0;
      opb = '0;
      unique case (alu_op)
        ALU_MULHU: begin
          opa = {1'b0, op1};
          opb = {1'b0, op2};
        end
        ALU_MULHSU: begin
          opa = {op1[63], op1};
          opb = {1'b0, op2};
        end
        ALU_MUL, ALU_MULH: begin
          opa = {op1[63], op1};
          opb = {op2[63], op2};
        end
        ALU_MULW: begin
          opa = {{33{op1[31]}}, op1[31:0]};
          opb = {{33{op2[31]}}, op2[31:0]};
        end
        default: ;
      endcase
    end
  end
  assign full = opa * opb;

  always_comb begin
    result = '0;
    if (state == EXEC) begin
      unique case (alu_op)
        ALU_MUL: begin
          result = full[63:0];
        end
        ALU_MULW: begin
          result = {{32{full[31]}}, full[31:0]};
        end
        ALU_MULH, ALU_MULHSU, ALU_MULHU: begin
          result = {{32{full[31]}}, full[31:0]};
          result = full[127:64];
        end
        default: ;
      endcase
    end
  end

endmodule

//-----------------------------------
// divider
//-----------------------------------
module divider (
  input logic clk,
  input logic rst_n,
  input state_e state,
  input alu_op_e alu_op,
  input reg_t op1,
  input reg_t op2,
  output reg_t result,
  output logic done
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

  assign is_divider = alu_op inside {ALU_DIVW, ALU_REMW, ALU_REMUW, ALU_DIVUW, ALU_DIV, ALU_DIVU, ALU_REM, ALU_REMU};
  assign is_rv64w = alu_op inside {ALU_DIVW, ALU_REMW, ALU_REMUW, ALU_DIVUW};
  assign is_signed = alu_op inside {ALU_DIV, ALU_DIVW, ALU_REM, ALU_REMW};
  assign a_sign    = is_rv64w ? op1[31] : op1[63];
  assign b_sign    = is_rv64w ? op2[31] : op2[63];

  always_comb begin
    logic [63:0] v1, v2;
    v1 = is_rv64w ? (is_signed ? {{32{op1[31]}}, op1[31:0]} : {32'b0, op1[31:0]}) : op1;
    v2 = is_rv64w ? (is_signed ? {{32{op2[31]}}, op2[31:0]} : {32'b0, op2[31:0]}) : op2;
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
    done = is_divider ? 1'b0 : 1'b1;

    if (is_divider) begin
      case (state_q)
        IDLE: begin
          if (state == EXEC) begin
            is_div_zero_d = (op_b_abs == 64'b0);
            is_rem_d      = alu_op inside {ALU_REM, ALU_REMUW, ALU_REMW, ALU_REMU};
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
          done = 1'b1;
          if (state == EXEC) state_d = IDLE;
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
      r_signed = is_rv64w ? {{32{op1[31]}}, op1[31:0]} : op1;
    end
    pre_res = is_rem_q ? r_signed : q_signed;
    result  = is_rv64w ? {{32{pre_res[31]}}, pre_res[31:0]} : pre_res;
  end

endmodule

//-----------------------------------
// register files
//-----------------------------------
module registerfile (
  input logic clk,
  input logic rst_n,
  input state_e state,
  input logic we,
  input logic [4:0] rd,
  input reg_t wdata,

  input logic [4:0] rs1,
  input logic [4:0] rs2,
  output reg_t rs1_val,
  output reg_t rs2_val,

  // for lr/sc instr
  input sc_e sc
);
  reg_t x[REGMAX];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
    end else begin : writeback
      if (state == WB && we == 1) begin
        if (rd > 0) begin
          if (sc == SC_NONE) begin
            x[rd] <= wdata;
            `LOGI($sformatf("WB: x[%02d]=%h", rd, wdata));
          end else begin
            x[rd] <= (sc == SC_SUCC ? 0 : 64'd1);
            `LOGI($sformatf("WB SC: x[%02d]=%h", rd, (sc == SC_SUCC ? 0 : 64'd1)));
          end
        end
      end
    end
  end

  always_comb begin
    if (32'(rs1) < REGMAX) rs1_val = x[rs1];
    if (32'(rs2) < REGMAX) rs2_val = x[rs2];
  end
endmodule

//-----------------------------------
// csr
//-----------------------------------
module csr (
  input logic clk,
  input logic rst_n,
  input addr_t pc,
  input state_e state,
  input sys_op_e sys_op,
  input reg_t csr_wdata,
  input [11:0] csr_idx,
  output reg_t csr_val,
  output reg_t trap_target,

  input  logic irq_timer,
  input  logic irq_external,
  output logic interrupted,

  output satp_t satp_o,
  output priv_lvl_e priv_o,
  output mstatus_t mstatus_o,

  input logic mmu_exc,
  input mcause_e mmu_cause,
  input reg_t mmu_causeval,

  output logic tlb_invalid
);
  // handle irq
  // handle exceptions
  // handle csr register rw
  // handle mmu
  // handle privilege level change

  `define MSTATUS_WR_MASK 64'h000006f001fe1fea
  `define SSTATUS_WR_MASK 64'h8000000f000de122

  `define USIP 0
  `define SSIP 1
  `define MSIP 3
  `define STIP 5
  `define MTIP 7
  `define SEIP 9
  `define MEIP 11
  `define SIE_MASK 64'h0222
  `define SIP_MASK 64'h0222
  `define MIE_MASK 64'h0aaa
  `define MIP_MASK 64'h0aaa

  mstatus_t mstatus;
  medeleg_t medeleg;
  mintr_t mideleg, mie, mip;
  misa_t misa;

  reg_t mtvec, mtval, mepc, mcause, mhartid, mscratch;
  reg_t stvec, stval, sepc, scause, sscratch, satp;
  reg_t cycle;
  priv_lvl_e mode;

  assign priv_o = mode;
  assign satp_o = satp;
  assign mstatus_o = mstatus;

  always_comb begin
    csr_val = '0;
    if (state == EXEC && csr_idx > 0) begin
      unique case (csr_idx)
        MSTATUS: csr_val = mstatus;
        MISA: csr_val = misa;
        MEDELEG: csr_val = medeleg;
        MIDELEG: csr_val = mideleg;
        MIE: csr_val = mie;
        MTVEC: csr_val = mtvec;
        MSCRATCH: csr_val = mscratch;
        MEPC: csr_val = mepc;
        MCAUSE: csr_val = mcause;
        MTVAL: csr_val = mtval;
        MIP: csr_val = mip;
        MHARTID: csr_val = mhartid;
        SSTATUS: csr_val = mstatus;  //& `SSTATUS_READ_MASK;
        SIE: csr_val = mie & `SIE_MASK;
        STVEC: csr_val = stvec;
        SSCRATCH: csr_val = sscratch;
        SEPC: csr_val = sepc;
        SCAUSE: csr_val = scause;
        STVAL: csr_val = stval;
        SIP: csr_val = mip & `SIP_MASK;
        SATP: csr_val = satp;
        default: ;
      endcase
      `LOGI($sformatf("read CSR[%03h]=%h", csr_idx, csr_val));
    end
  end


  // handle mmu trap
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      trap_target <= '1;
    end else begin
      if (mmu_exc) begin
        `LOGI($sformatf("MMU exc mode: %0d cause: %0d", mode, mmu_cause));
        unique case (mode)
          M_USER: begin
            if (medeleg.ecall_from_u_mode) begin
              scause <= mmu_cause;
              sepc <= pc;
              stval <= mmu_causeval;
              trap_target <= stvec;
              mode <= M_SUPER;
              mstatus.SPP <= 1'b0;
              mstatus.SPIE <= mstatus.SIE;
              mstatus.SIE <= 1'b0;
            end else begin
              mcause <= mmu_cause;
              mepc <= pc;
              trap_target <= mtvec;
              mtval <= mmu_causeval;
              mode <= M_MACHINE;
              mstatus.MPP <= mode;
              mstatus.MPIE <= mstatus.MIE;
              mstatus.MIE <= 1'b0;
            end
          end
          M_SUPER: begin
            if (medeleg.ecall_from_s_mode) begin
              scause <= mmu_cause;
              trap_target <= stvec;
              sepc <= pc;
              stval <= mmu_causeval;
              mstatus.SPP <= 1'b1;
              mstatus.SPIE <= mstatus.SIE;
              mstatus.SIE <= 1'b0;
            end else begin
              mcause <= mmu_cause;
              trap_target <= mtvec;
              mepc <= pc;
              mtval <= mmu_causeval;
              mode <= M_MACHINE;
              mstatus.MPP <= mode;
              mstatus.MPIE <= mstatus.MIE;
              mstatus.MIE <= 1'b0;
            end
          end
          M_MACHINE: begin
            mstatus.MPRV <= 1'b0;
            mcause <= mmu_cause;
            trap_target <= mtvec;
            mepc <= pc;
            mtval <= mmu_causeval;
            mode <= M_MACHINE;
            mstatus.MPP <= mode;
            mstatus.MPIE <= mstatus.MIE;
            mstatus.MIE <= 1'b0;
          end
        endcase

      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      mstatus <= '{UXL: 2'b10, SXL: 2'b10, default: 0};
      misa <= '{A: 1, I: 1, M: 1, S: 1, U: 1, MXL: 2'b10, default: 0};  // rv64imasu
      medeleg <= '0;
      mideleg <= '0;
      mtvec <= '0;
      mtval <= '0;
      mscratch <= '0;
      mepc <= '0;
      mcause <= '0;
      mie <= '0;
      mip <= '0;
      mhartid <= '0;
      mode <= M_MACHINE;
      stvec <= '0;
      sscratch <= '0;
      stval <= '0;
      scause <= '0;
      satp <= '0;
    end else begin
      if (state == EXEC) begin
        // record mcause=11; mepc = pc + 4; mpie=mstatus; mie = 0; pc=mtvec;
        if (tlb_invalid == 1) begin
          tlb_invalid <= 0;
        end

        if (sys_op == SYS_ECALL) begin
          `LOGI("ECALL");
          unique case (mode)
            M_USER: begin
              if (medeleg.ecall_from_u_mode) begin
                scause <= EXC_ECALL_U_MODE;
                sepc <= pc;
                trap_target <= stvec;
                mode <= M_SUPER;
                mstatus.SPP <= 1'b0;
                mstatus.SPIE <= mstatus.SIE;
                mstatus.SIE <= 1'b0;
              end else begin
                mcause <= EXC_ECALL_U_MODE;
                mepc <= pc;
                trap_target <= mtvec;
                mode <= M_MACHINE;
                mstatus.MPP <= mode;
                mstatus.MPIE <= mstatus.MIE;
                mstatus.MIE <= 1'b0;
              end
            end
            M_SUPER: begin
              if (medeleg.ecall_from_s_mode) begin
                scause <= EXC_ECALL_S_MODE;
                trap_target <= stvec;
                sepc <= pc;
                mstatus.SPP <= 1'b1;
                mstatus.SPIE <= mstatus.SIE;
                mstatus.SIE <= 1'b0;
              end else begin
                mcause <= EXC_ECALL_S_MODE;
                trap_target <= mtvec;
                mepc <= pc;
                mode <= M_MACHINE;
                mstatus.MPP <= mode;
                mstatus.MPIE <= mstatus.MIE;
                mstatus.MIE <= 1'b0;
              end
            end
            M_MACHINE: begin
              mcause <= EXC_ECALL_M_MODE;
              trap_target <= mtvec;
              mepc <= pc;
              mode <= M_MACHINE;
              mstatus.MPP <= mode;
              mstatus.MPIE <= mstatus.MIE;
              mstatus.MIE <= 1'b0;
            end
          endcase
        end else if (sys_op == SYS_MRET) begin
          `LOGI($sformatf("MRET: %0d mepc:%h", mstatus.MPP, mepc));
          // restore privilege
          mcause <= '0;
          mstatus.MPRV <= 1'b0;
          mode <= priv_lvl_e'(mstatus.MPP);
          trap_target <= mepc;
          mstatus.MPP <= '0;
          mstatus.MIE <= mstatus.MPIE;
          mstatus.MPIE <= 1'b0;
        end else if (sys_op == SYS_SRET) begin
          `LOGI("SRET");
          mcause <= '0;
          mode <= mstatus.SPP ? M_SUPER : M_USER;
          trap_target <= sepc;
          mstatus.SPP <= '0;
          mstatus.SIE <= mstatus.SPIE;
          mstatus.SPIE <= 1'b0;
        end else if (sys_op == SYS_FENCE) begin
          tlb_invalid <= 1'b1;
        end else if (sys_op >= SYS_CSRRW) begin
          `LOGI($sformatf("write CSR[%03h]=%h", csr_idx, csr_wdata));
          unique case (csr_idx)
            MSTATUS: mstatus <= (mstatus & ~`MSTATUS_WR_MASK) | (csr_wdata & `MSTATUS_WR_MASK);
            MEDELEG: medeleg <= csr_wdata;
            MIDELEG: mideleg <= csr_wdata;
            MIE: mie <= (mie & ~`MIE_MASK) | (csr_wdata & `MIE_MASK);
            MTVEC: mtvec <= csr_wdata;
            MSCRATCH: mscratch <= csr_wdata;
            MIP: mip <= (mip & ~`MIP_MASK) | (csr_wdata & `MIP_MASK);
            MEPC: mepc <= csr_wdata;
            MCAUSE: mcause <= csr_wdata;
            MTVAL: mtval <= csr_wdata;

            SSTATUS: mstatus <= (mstatus & ~`SSTATUS_WR_MASK) | (csr_wdata & `SSTATUS_WR_MASK);
            SIE: mie <= (mie & ~`SIE_MASK) | (csr_wdata & `SIE_MASK);
            STVEC: stvec <= csr_wdata;
            SSCRATCH: sscratch <= csr_wdata;
            SEPC: sepc <= csr_wdata;
            SCAUSE: scause <= csr_wdata;
            STVAL: stval <= csr_wdata;
            SIP: mip <= (mip & ~`SIP_MASK) | (csr_wdata & `SIP_MASK);
            SATP: satp <= csr_wdata;
            default: ;
          endcase
        end
      end
    end
  end

  // handle IRQ
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
    end else begin
      if (mideleg.STI) begin
        mip.STI <= irq_timer;
      end else begin
        mip.MTI <= irq_timer;
      end
      if (mideleg.SEI) begin
        mip.SEI <= irq_external;
      end else begin
        mip.MEI <= irq_external;
      end
    end
  end

  mintr_t m_intr, s_intr;
  always_comb begin
    m_intr = mip & mie & (~mideleg);
    s_intr = mip & mie & (mideleg);
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
    end else begin
      interrupted <= 1'b0;
      // `LOGI($sformatf("int m=%h, s=%h", m_intr, s_intr));
      if (state == WB && m_intr != reg_t'(0)) begin
        // int m-mode
        interrupted <= 1'b1;
        trap_target <= '1;
        if (mstatus.MIE) begin
          mstatus.MPP <= mode;
          mstatus.MPIE <= mstatus.MIE;
          mstatus.MIE <= 1'b0;
          mode <= M_MACHINE;
          mepc <= pc;
          mcause <= mintr2cause(m_intr);
          trap_target <= mtvec;
        end
      end else if (state == WB && s_intr != reg_t'(0)) begin
        // int s-mode
        interrupted <= 1'b1;
        trap_target <= '1;
        if (mstatus.SIE) begin
          mstatus.SPP <= (mode == M_USER ? 1'b0 : 1'b1);
          mstatus.SPIE <= mstatus.SIE;
          mstatus.SIE <= 1'b0;
          mode <= M_SUPER;
          sepc <= pc;
          scause <= sintr2cause(s_intr);
          trap_target <= stvec;
        end
      end
    end
  end

  function automatic mcause_e mintr2cause(mintr_t u);
    if (u.MEI) begin
      return INTR_MACHINE_EXT;
    end else if (u.MSI) begin
      return INTR_MACHINE_SW;
    end else begin
      return INTR_MACHINE_TMR;
    end
  endfunction

  function automatic mcause_e sintr2cause(mintr_t u);
    if (u.SEI) begin
      return INTR_SUPERVISOR_EXT;
    end else if (u.SSI) begin
      return INTR_SUPERVISOR_SW;
    end else begin
      return INTR_SUPERVISOR_TMR;
    end
  endfunction

endmodule

//-----------------------------------
// sram
//-----------------------------------
module sram #(
  parameter reg_t SIZE = 32 * 1024
) (
  input logic clk,
  input logic rst_n,
  input state_e state,
  input addr_t mem_addr,
  input mem_op_e mem_op,
  input amo_op_e amo_op,
  input reg_t mem_data,
  input data_ready,
  output reg_t mem_rdata,

  // page table interface
  input  logic  pte_req,
  input  addr_t pte_addr,
  output pte_t  pte,
  output logic  pte_ready,

  input logic  pte_wr_req,
  input addr_t pte_wr_addr,
  input pte_t  pte_wr_data,
  input logic  mmu_error,

  // fetch interface
  input addr_t pc,
  output logic [31:0] instr,

  // amo interface
  mem_access.slave amo,
  output sc_e sc
);

  typedef struct packed {
    reg_t  hartid;
    logic  valid;
    addr_t addr;
    size_e sz;
  } lr_t;

  lr_t lr;
  size_e lrsz, scsz;

  localparam reg_t BITS = reg_t'($clog2(SIZE));
  logic enable;

  logic lrenable, scenable;

  addr_t BASE = 64'h0000_0000_8000_2000;
  reg_t SZ = SIZE;

  logic [7:0] ram[SIZE];
  addr_t offset;
  `define B2R(r, a) {{56{r[a][7]}}, r[a][7:0]}
  `define H2R(r, a) {{48{r[a+1][7]}}, r[a+1], r[a]}
  `define W2R(r, a) {{32{r[a+3][7]}}, r[a+3], r[a+2], r[a+1], r[a]}
  `define D2R(r, a) {r[a+7], r[a+6], r[a+5], r[a+4], r[a+3], r[a+2], r[a+1], r[a]}
  `define BU2R(r, a) {{56'b0}, r[a]}
  `define HU2R(r, a) {{48'b0}, r[a+1], r[a]}
  `define WU2R(r, a) {{32'b0}, r[a+3], r[a+2], r[a+1], r[a]}
  `define WU2I(r, a) {r[a+3], r[a+2], r[a+1], r[a]}
  `define write_data(off, data, sz) for (logic [BITS-1:0] i = 0; i < sz; i++) ram[off[BITS-1:0]+i] <= data[8*i+:8]

  integer fd;
  string hex_file;
  initial begin
    $value$plusargs("data.base=%h", BASE);
    $value$plusargs("data.size=%h", SZ);
    `LOGI($sformatf("base:%h size:%h", BASE, SZ));
    $value$plusargs("hex_file=%s", hex_file);
    if (hex_file != "") begin
      fd = $fopen({hex_file, ".data"}, "r");
      if (fd != 0) begin
        $fclose(fd);
        $readmemh({hex_file, ".data"}, ram);
        `LOGI($sformatf("ram load %s", {hex_file, ".data"}));
      end
    end
  end
  assign enable   = (mem_addr >= BASE && mem_addr < BASE + SZ) && (data_ready) && !mmu_error;
  assign offset   = mem_addr - BASE;
  assign lrenable = amo_op inside {AMO_LR, AMO_LRW};
  assign scenable = amo_op inside {AMO_SC, AMO_SCW};
  always_comb begin
    lrsz = (amo_op == AMO_LR ? SZ_8B : SZ_4B);
    scsz = (amo_op == AMO_SC ? SZ_8B : SZ_4B);
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (reg_t i = 0; i < SIZE; i++) begin
        // ram[i] <= '0;
      end
      lr <= '0;
    end else begin
      sc <= SC_NONE;
      if (state == MEMACCESS && mem_op != MEM_NONE && enable) begin
        `LOGI($sformatf("MEM:%h op:%0d data: %h", offset, mem_op, mem_data));
        unique case (mem_op)
          LD_LB:  mem_rdata <= `B2R(ram, offset[BITS-1:0]);
          LD_LH:  mem_rdata <= `H2R(ram, offset[BITS-1:0]);
          LD_LW:  mem_rdata <= `W2R(ram, offset[BITS-1:0]);
          LD_LD:  mem_rdata <= `D2R(ram, offset[BITS-1:0]);
          LD_LBU: mem_rdata <= `BU2R(ram, offset[BITS-1:0]);
          LD_LHU: mem_rdata <= `HU2R(ram, offset[BITS-1:0]);
          LD_LWU: mem_rdata <= `WU2R(ram, offset[BITS-1:0]);
          SD_SB:  `write_data(offset, mem_data, 1);
          SD_SH:  `write_data(offset, mem_data, 2);
          SD_SW: begin
            if (scenable) begin
              if (lr.valid && offset == lr.addr && lr.sz == SZ_4B) begin
                `write_data(offset, mem_data, 4);
                sc <= SC_SUCC;
                lr.valid <= 0;
                `LOGW("sc succ");
              end else begin
                sc <= SC_FAIL;
                `LOGW("sc fail");
              end
            end else begin
              `write_data(offset, mem_data, 4);
              if (lr.valid && offset == lr.addr && lr.sz == SZ_4B) begin
                lr.valid <= 0;
              end
            end
          end
          SD_SD: begin
            if (scenable) begin
              if (lr.valid && offset == lr.addr && lr.sz == SZ_8B) begin
                `write_data(offset, mem_data, 8);
                sc <= SC_SUCC;
                `LOGW("sc succ");
              end else begin
                sc <= SC_FAIL;
                `LOGW("sc fail");
              end
            end else begin
              `write_data(offset, mem_data, 8);
              if (lr.valid && offset == lr.addr && lr.sz == SZ_8B) begin
                lr.valid <= 0;
              end
            end
          end
        endcase

        if (lrenable) begin
          `LOGI($sformatf("LR mark: %h", offset));
          lr.valid <= 1'b1;
          lr.addr <= offset;
          lr.sz <= lrsz;
        end
      end
    end
  end

  // for pte request
  addr_t pte_offset;
  pte_t pte_readed;
  always_comb begin
    pte_readed = '0;
    pte_offset = pte_addr - BASE;
    if (pte_req && (pte_addr >= BASE && pte_addr < BASE + SZ)) begin
      pte_readed = `D2R(ram, pte_offset[BITS-1:0]);
      `LOGI($sformatf("pte_readed: addr:%h %h", pte_addr, pte_readed));
    end
    if (pte_wr_req && (pte_addr >= BASE && pte_addr < BASE + SZ)) begin
      pte_offset = pte_addr - BASE;
    end
  end


  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
    end else begin
      if (pte_wr_req && (pte_wr_addr >= BASE && pte_wr_addr < BASE + SZ)) begin
        `LOGI($sformatf("write pte %h: %h", pte_wr_addr, pte_wr_data));
        for (logic [BITS-1:0] i = 0; i < 8; i++) ram[pte_offset[BITS-1:0]+i] <= pte_wr_data[8*i+:8];
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
    end else begin
      if (pte_req) begin
        pte_ready <= 1'b1;
        pte <= pte_readed;
      end
      if (pte_ready) pte_ready <= 1'b0;
    end
  end


  // fetch interface
  logic ienable;
  addr_t ioffset;
  always_comb begin
    ioffset = pc - BASE;
    ienable = (pc >= BASE && pc < BASE + SZ);
    if (ienable) begin
      instr = `WU2I(ram, ioffset[BITS-1:0]);
    end else begin
      instr = '0;
    end
  end


  // amo access
  logic amo_en;
  addr_t amo_offset;
  always_comb begin
    amo_en = state == AMOMEM && amo.addr >= BASE && amo.addr < BASE + SZ && amo.valid;
    amo_offset = amo.addr - BASE;
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
    end else begin
      amo.ready <= 1'b0;
      if (amo_en) begin
        if (amo.we) begin
          // write
          unique case (amo.size)
            SZ_4B:   `write_data(amo_offset, amo.wdata, 4);
            SZ_8B:   `write_data(amo_offset, amo.wdata, 8);
            default: ;
          endcase
        end else begin
          // read
          unique case (amo.size)
            SZ_4B:   amo.rdata <= `W2R(ram, amo_offset[BITS-1:0]);
            SZ_8B:   amo.rdata <= `D2R(ram, amo_offset[BITS-1:0]);
            default: `LOGI("AMO READ ERROR");
          endcase
        end
        amo.ready <= 1'b1;
      end
    end
  end

endmodule

//-----------------------------------
// rom
//-----------------------------------
module rom #(
  parameter string HEX = "",
  parameter reg_t SIZE = 32 * 1024
) (
  input logic clk,
  input logic rst_n,
  input addr_t pc,
  output logic [31:0] instr
);

  addr_t BASE = 64'h0000_0000_8000_0000;
  reg_t SZ = SIZE;

  localparam reg_t ROMSIZE = SIZE / 4;
  localparam reg_t BITS = reg_t'($clog2(ROMSIZE));
  logic [31:0] data[ROMSIZE];

  initial begin : init
    string hex_file;
    $value$plusargs("text_init.base=%h", BASE);
    $value$plusargs("text_init.size=%h", SZ);
    `LOGI($sformatf("base:%h size:%h", BASE, SZ));
    $value$plusargs("hex_file=%s", hex_file);
    if (hex_file != "") begin
      $readmemh(hex_file, data);
      `LOGI($sformatf("load %s", hex_file));
    end else begin
      $readmemh(HEX, data);
      `LOGI($sformatf("load %s", HEX));
    end
  end

  logic valid;

  always_comb begin
    valid = (pc >= BASE && pc < BASE + SZ);
    if (valid) begin
      instr = data[pc[BITS+1:2]];
    end else begin
      instr = '0;
    end
  end

endmodule

//-----------------------------------
// uart
//-----------------------------------
module uart #(
  parameter addr_t BASE = 64'h0000_0000_9000_0000,
  parameter addr_t SIZE = 64'h1000
) (
  input logic clk,
  input logic rst_n,
  input addr_t addr,
  input state_e state,
  input mem_op_e mem_op,
  input reg_t data
);

  logic enable;
  assign enable = (addr >= BASE && addr < BASE + SIZE && state == MEMACCESS);
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
    end else begin
      if (enable && mem_op == SD_SB) begin
        $write("%c", data[7:0]);
      end
    end
  end

endmodule

//-----------------------------------
// rvtest
//-----------------------------------
module rvtest (
  input logic clk,
  input logic rst_n,
  input addr_t addr,
  input state_e state,
  input mem_op_e mem_op,
  input reg_t data
);

  addr_t BASE = 64'h0000_0000_8000_1000;
  addr_t SIZE = 64'h1000;

  initial begin
    $value$plusargs("tohost.base=%h", BASE);
    $value$plusargs("tohost.size=%h", SIZE);
    `LOGI($sformatf("base:%h size:%h", BASE, SIZE));
  end

  logic enable;
  addr_t offset;
  assign enable = ((addr >= BASE && addr < BASE + SIZE) && state == MEMACCESS);
  assign offset = addr - BASE;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
    end else begin
      if (enable && mem_op == SD_SW) begin
        if (offset == 0) begin
          if (data[31:0] == 32'd1) begin
            $write("%sPASS%s", `GREEN, `COLOR_NONE);
          end else begin
            $write($sformatf("%sFAIL%s: %0d", `RED, `COLOR_NONE, data[31:0]));
          end
          $finish(0);
        end
      end
    end
  end

endmodule

//-----------------------------------
// mmu
//-----------------------------------
module mmu (
  input logic clk,
  input logic rst_n,

  input state_e state,
  input satp_t satp,
  input mstatus_t mstatus,
  input priv_lvl_e priv,

  // for instruction va translation
  input  addr_t va_pc,
  output addr_t pa_pc,
  output logic  pc_ready,

  // for data va translation
  input mem_op_e mem_op,
  input addr_t va_data,
  output addr_t pa_data,
  output logic data_ready,

  // for amo va mapping
  mmaping.slave amo,

  // pte write interface
  output logic  pte_wr_req,
  output addr_t pte_wr_addr,
  output pte_t  pte_wr_data,

  // read pte interface
  output logic  pte_req,
  output addr_t pte_addr,
  input  pte_t  pte,
  input  logic  pte_ready,

  // csr interface
  output logic error,
  output mcause_e cause,
  output reg_t causeval,

  // tlb flush
  input logic tlb_invalid
);

  typedef enum {
    IDLE,
    LDPGD,
    LDPMD,
    LDPTE,
    CHKPERM,
    DONE
  } mmu_state_e;

  `define set_flags(thiz) begin \
    V = thiz.V; \
    R = thiz.R; \
    W = thiz.W; \
    X = thiz.X; \
    U = thiz.U; \
    A = thiz.A; \
    D = thiz.D; \
  end

  `define set_vpn(thiz) begin \
    vpn2 = thiz[38:30]; \
    vpn1 = thiz[29:21]; \
    vpn0 = thiz[20:12]; \
  end

  `define cache_tlb(tlb, va) begin \
    tlb.PGSIZE <= pgsize; \
    tlb.ASID <= satp.ASID; \
    tlb.VPN <= va[38:12]; \
    tlb.PPN <= pte.PPN; \
    tlb.V <= pte.V; \
    tlb.R <= pte.R; \
    tlb.W <= pte.W; \
    tlb.X <= pte.X; \
    tlb.U <= pte.U; \
    tlb.D <= pte.D; \
    tlb.A <= 1; \
  end

  `define build_pa_by_pte(pa, pte, va) begin \
    unique case (pgsize) \
      PG_1G:   pa <= {8'b0, pte.PPN[53:28], va[29:0]}; \
      PG_2M:   pa <= {8'b0, pte.PPN[53:19], va[20:0]}; \
      PG_4K:   pa <= {8'b0, pte.PPN[53:10], va[11:0]}; \
      default: pa <= '0; \
    endcase \
  end

  `define build_pa_by_tlb(pa, tlb, va) begin \
    unique case (pgsize) \
      PG_1G:   pa <= {8'b0, tlb.PPN[43:18], va[29:0]}; \
      PG_2M:   pa <= {8'b0, tlb.PPN[43:9], va[20:0]};  \
      PG_4K:   pa <= {8'b0, tlb.PPN[43:0], va[11:0]};  \
      default: pa <= '0; \
    endcase \
  end

  mmu_state_e mmu_state;
  tlb_entry_t itlb, dtlb;
  pagesize_e pgsize;
  logic iready, dready, aligned, ihit, dhit;
  logic leaf, icheck, iwalking;
  logic V, R, W, X, U, A, D;
  logic [8:0] vpn0, vpn1, vpn2;
  logic [26:0] vpnmask;

  always_comb begin
    unique case (itlb.PGSIZE)
      PG_4K:   vpnmask = {9'h1ff, 9'h1ff, 9'h1ff};
      PG_2M:   vpnmask = {9'h1ff, 9'h1ff, 9'h000};
      PG_1G:   vpnmask = {9'h1ff, 9'h000, 9'h000};
      default: vpnmask = {9'h1ff, 9'h1ff, 9'h1ff};
    endcase
    ihit = itlb.V && (itlb.VPN & vpnmask) == (va_pc[38:12] & vpnmask) && (itlb.G || itlb.ASID == satp.ASID);
    dhit = dtlb.V && (dtlb.VPN & vpnmask) == (va_data[38:12] & vpnmask) && (dtlb.G || dtlb.ASID == satp.ASID);
    if (state == FETCH && ihit) begin
      `set_flags(itlb)
    end else if (state == MEMACCESS && dhit) begin
      `set_flags(dtlb)
    end else begin
      `set_flags(pte)
    end

    leaf = V & (R | W | X);
    icheck = (priv == M_SUPER && U == 0) || (priv == M_USER && U == 1);
    iwalking = (satp.MODE == 8 && priv != M_MACHINE && state == FETCH);
    if (state == FETCH) begin
      `set_vpn(va_pc)
    end else begin
      `set_vpn(va_data)
    end
  end

  // data page mapping
  logic isload, isstore, dwalking, dcheck, lcheck;
  priv_lvl_e lvl;
  logic [63:0] markad;
  always_comb begin
    lvl = priv;
    if (priv == M_MACHINE && mstatus.MPRV == 1) begin
      lvl = priv_lvl_e'(mstatus.MPP);
    end

    isload   = mem_op > MEM_NONE && mem_op < MEM_SEP;
    isstore  = mem_op > MEM_SEP && mem_op <= SD_SD;
    dwalking = (satp.MODE == 8 && lvl < M_MACHINE && mem_op != MEM_NONE && state == MEMACCESS);
    dcheck   = (isload && (R || (mstatus.MXR && X))) || (isstore && W);
    lcheck   = (lvl == M_USER && U == 1) || (lvl == M_SUPER && (U == 0 || mstatus.SUM));

    markad   = '0;
    if (!A) markad = markad | `PTE_A;
    if (isstore && !D) markad = markad | `PTE_D;
  end

  // instruction and data page mapping
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      mmu_state <= IDLE;
      iready <= 1'b0;
      dready <= 1'b0;
      itlb <= '0;
      dtlb <= '0;
    end else begin
      iready <= 1'b0;
      dready <= 1'b0;
      if (tlb_invalid) begin
        itlb.V <= 0;
        dtlb.V <= 0;
      end
      amo.ready <= 1'b0;

      if (state == FETCH && !iwalking) begin
        `LOGI($sformatf("NO iwalking va:%h", va_pc));
        pa_pc  <= va_pc;
        iready <= 1'b1;
      end
      if (state == MEMACCESS && !dwalking) begin
        pa_data <= va_data;
        dready  <= 1'b1;
      end
      if (state == AMOMEM && amo.valid) begin
        amo.pa <= amo.va;
        amo.ready <= 1'b1;
      end

      if (dwalking || iwalking) begin
        unique case (mmu_state)
          IDLE: begin
            aligned <= 1;
            if (iwalking && ihit) begin
              `LOGI("ihit");
              mmu_state <= CHKPERM;
              pgsize <= itlb.PGSIZE;
            end else if (dwalking && dhit) begin
              `LOGI("dhit");
              mmu_state <= CHKPERM;
              pgsize <= dtlb.PGSIZE;
            end else begin
              mmu_state <= LDPGD;
              pte_req   <= 1'b1;
              pte_addr  <= {8'h00, satp.PPN, 12'(vpn2 << 3)};
            end
          end
          LDPGD: begin
            if (pte_ready) begin
              `LOGPTE("pgd", pte);
              pte_req <= 1'b0;
              if (!V || leaf) begin
                mmu_state <= CHKPERM;
                pgsize <= PG_1G;
                aligned <= (pte.PPN & 44'h3ffff) == 0;
              end else begin
                pte_req   <= 1'b1;
                mmu_state <= LDPMD;
                pte_addr  <= {8'h00, pte.PPN, 12'(vpn1 << 3)};
              end
            end
          end
          LDPMD: begin
            if (pte_ready) begin
              `LOGPTE("pmd", pte);
              pte_req <= 1'b0;
              if (!V || leaf) begin
                mmu_state <= CHKPERM;
                pgsize <= PG_2M;
                aligned <= (pte.PPN & 44'h1ff) == 0;
              end else begin
                pte_req   <= 1'b1;
                mmu_state <= LDPTE;
                pte_addr  <= {8'h00, pte.PPN, 12'(vpn0 << 3)};
              end
            end
          end
          LDPTE: begin
            if (pte_ready) begin
              `LOGPTE("pte", pte);
              pte_req <= 1'b0;
              mmu_state <= CHKPERM;
              pgsize <= PG_4K;
            end
          end
          CHKPERM: begin
            mmu_state <= DONE;
            if (iwalking && (!V || !X || !icheck || !aligned)) begin
              error <= 1'b1;
              cause <= EXC_INSTR_PAGE_FAULT;
              causeval <= va_pc;
              iready <= 1'b1;
            end else if (dwalking && (!V || !aligned || !dcheck || !lcheck)) begin
              error <= 1'b1;
              cause <= isload ? EXC_LOAD_PAGE_FAULT : EXC_STORE_PAGE_FAULT;
              causeval <= va_data;
              dready <= 1'b1;
            end else begin
              // build PA
              if (iwalking) begin
                iready <= 1'b1;
                if (ihit) begin
                  `build_pa_by_tlb(pa_pc, itlb, va_pc)
                end else begin
                  `build_pa_by_pte(pa_pc, pte, va_pc)
                  `cache_tlb(itlb, va_pc)

                  // mark A flag
                  if (A == 0) begin
                    pte_wr_req  <= 1'b1;
                    pte_wr_data <= pte | `PTE_A;
                    pte_wr_addr <= pte_addr;
                  end
                end
              end

              if (dwalking) begin
                dready <= 1'b1;
                if (dhit) begin
                  `build_pa_by_tlb(pa_data, dtlb, va_data)
                end else begin
                  // build PA
                  `build_pa_by_pte(pa_data, pte, va_data)
                  `cache_tlb(dtlb, va_data)
                end
                if (markad != 0) begin
                  pte_wr_req <= 1'b1;
                  pte_wr_data <= pte | markad;
                  pte_wr_addr <= pte_addr;
                  dtlb.D <= (markad & `PTE_D) == 0 ? 0 : 1;
                end
              end
            end
          end
          DONE: begin
            error <= 1'b0;
            iready <= 1'b0;
            dready <= 1'b0;
            aligned <= 1'b1;
            mmu_state <= IDLE;
            pte_wr_req <= 1'b0;
          end
        endcase
      end
    end
  end

  assign pc_ready   = iready;
  assign data_ready = dready;

endmodule

//-----------------------------------------
// amo
//-----------------------------------------
module atomic (
  input logic clk,
  input logic rst_n,
  input state_e state,
  input amo_op_e amo_op,
  input reg_t rs1_val,
  output reg_t op_amo,
  output logic amo_ready,

  mmaping.master mmap,
  mem_access.master ma
);

  typedef enum {
    AMO_IDLE,
    AMO_VA2PA,
    AMO_READ,
    AMO_DONE
  } amostate_e;

  logic word = amo_op >= AMO_SWAPW && amo_op <= AMO_MAXUW;
  amostate_e astate;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      astate <= AMO_IDLE;
      mmap.valid <= 1'b0;
      ma.valid <= 1'b0;
    end else begin
      amo_ready  <= 1'b0;
      mmap.valid <= 1'b0;
      ma.valid   <= 1'b0;

      // request sram to load data
      if (state == AMOMEM) begin
        unique case (astate)
          AMO_IDLE: begin
            `LOGI("amo request mmu");
            mmap.rw <= 2'b11;
            mmap.va <= rs1_val;
            mmap.valid <= 1'b1;
            astate <= AMO_VA2PA;
          end
          AMO_VA2PA: begin
            if (mmap.ready) begin
              `LOGI($sformatf("amo mmu ready: %h", mmap.pa));
              // TODO: handle error
              mmap.valid <= 1'b0;
              ma.we <= 1'b0;
              ma.addr <= mmap.pa;
              ma.size <= word ? SZ_4B : SZ_8B;
              ma.valid <= 1'b1;
              astate <= AMO_READ;
            end
          end
          AMO_READ: begin
            if (ma.ready) begin
              `LOGI($sformatf("amo data ready: %h", ma.rdata));
              ma.valid <= 1'b0;
              op_amo <= ma.rdata;
              amo_ready <= 1'b1;
              astate <= AMO_DONE;
            end
          end
          AMO_DONE: begin
            astate <= AMO_IDLE;
          end
          default: ;
        endcase
      end
    end
  end

endmodule

/******************************************************************************/
