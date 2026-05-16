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
    .COUNTER(10000)
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
    #1.5 rst_n = 1;
    repeat (COUNTER) @(negedge clk);
    #0.5 rst_n = 0;
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
  reg_t imm;

  // exec data
  addr_t mem_addr, pc_target;
  reg_t wb_data, mem_data, mem_rdata;

  // members
  state_e state;
  addr_t pc;

  decoder decoder1 (
    .instr(instr),
    .state(state),
    .rs1(rs1),
    .rs2(rs2),
    .rd(rd),
    .alu_op(alu_op),
    .sys_op(sys_op),
    .mem_op(mem_op),
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
    .op_s1(op_s1),
    .op_s2(op_s2),
    .rs1_val(rs1_val),
    .rs2_val(rs2_val),
    .csr_val(csr_val),
    .trap_target(trap_target),
    .imm(imm),
    .csr_imm(csr_imm),
    .pc(pc),
    .br_taken(br_taken),
    .pc_target(pc_target),
    .mem_addr(mem_addr),
    .mem_data(mem_data),
    .wb_data(wb_data),
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
    .rs2_val(rs2_val)
  );

  // csr
  reg_t csr_val, csr_wdata;
  reg_t trap_target;
  logic irqt, irqe, interrupted;
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
    .interrupted(interrupted)
  );

  // rom
  logic [31:0] instr;
  rom #(
    .SIZE(8192),
    .HEX("isa/div.hex")
  ) rom1 (
    .clk(clk),
    .rst_n(rst_n),
    .pc(pc),
    .instr(instr)
  );

  // sram
  sram sram1 (
    .clk(clk),
    .rst_n(rst_n),
    .state(state),
    .mem_addr(mem_addr),
    .mem_op(mem_op),
    .mem_rdata(mem_rdata),
    .mem_data(mem_data)
  );

  uart #(
    .BASE(64'h2000),
    .MASK(64'hfff)
  ) uart1 (
    .clk(clk),
    .rst_n(rst_n),
    .addr(mem_addr),
    .state(state),
    .mem_op(mem_op),
    .data(mem_data)
  );

  // for rvtest
  rvtest rvt1 (
    .clk(clk),
    .rst_n(rst_n),
    .addr(mem_addr),
    .state(state),
    .mem_op(mem_op),
    .data(mem_data)
  );

  //---------------------------------
  // state machine
  //---------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      `LOGW("reset");
      state <= IDLE;
      pc <= 64'h8000_0000_0000_0000;
    end else begin
      unique case (state)
        IDLE: state <= FETCH;
        FETCH: begin
          `LOGI($sformatf("fetch pc=%h instr=%h", pc, instr));
          state <= DECODE;
        end
        DECODE: begin
          state <= EXEC;
        end
        EXEC: begin
          `LOGI($sformatf("exec_done: %b", exec_done));
          if (exec_done) begin
            state <= MEMACCESS;
          end
        end
        MEMACCESS: state <= WB;
        WB: begin
          if (!halt) begin
            state <= FETCH;
            pc <= pc_target != 0 ? pc_target : pc + 4;
          end else begin
            if (interrupted) begin
              `LOGI("INT");
              state <= FETCH;
              pc <= pc_target != 0 ? pc_target : pc + 4;
            end
          end
        end
        default: ;
      endcase
    end
  end

endmodule

localparam int unsigned REGMAX = 32;
typedef logic [63:0] addr_t;
typedef logic [63:0] reg_t;

typedef enum {
  IDLE,
  FETCH,
  DECODE,
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
  SYS_CSRRW,
  SYS_CSRRS,
  SYS_CSRRC,
  SYS_CSRRWI,
  SYS_CSRRSI,
  SYS_CSRRCI
} sys_op_e;

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
  LD_LBU,
  LD_LHU,
  LD_LWU,
  MEM_SEP,
  SD_SB,
  SD_SH,
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
} mstatus_rv64_t;

typedef union packed {
  mstatus_rv64_t fields;  // Access via bit-fields
  logic [63:0]   value;   // Access as a whole 64-bit register
} mstatus_u;

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
} medeleg_rv64_t;

typedef union packed {
  medeleg_rv64_t fields;  // Access via bit-fields
  logic [63:0]   value;   // Access as a whole 64-bit register
} medeleg_u;

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
} mintr_rv64_t;

typedef union packed {
  mintr_rv64_t fields;
  logic [63:0] value;
} mintr_u;

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
} misa_rv64_t;
typedef struct packed {
  misa_rv64_t  fields;
  logic [63:0] value;
} misa_u;

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
  input op_src_e op_s1,
  input op_src_e op_s2,
  input reg_t rs1_val,
  input reg_t rs2_val,
  input reg_t csr_val,
  input reg_t trap_target,
  input reg_t imm,
  input [4:0] csr_imm,
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
      br_taken = 1'b0;
      wb_data = '0;
      mem_data = '0;
      pc_target = '0;
      op1 = (op_s1 == OP_SRC_REG) ? rs1_val : pc;
      op2 = (op_s2 == OP_SRC_REG) ? rs2_val : imm;
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
          pc_target = trap_target;
        end
        SYS_EBREAK: begin
          $finish;
        end
        SYS_MRET: begin
          // pc = mepc;
          pc_target = trap_target;
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

      if (reg_write) begin
        if (alu_op != ALU_NONE) begin
          if (alu_op inside {ALU_MUL, ALU_MULH, ALU_MULHU, ALU_MULHSU, ALU_MULW}) begin
            wb_data = mult_result;
          end else if (alu_op inside {ALU_DIV, ALU_DIVU, ALU_DIVW, ALU_DIVUW, ALU_REM, ALU_REMW, ALU_REMU, ALU_REMUW}) begin
            wb_data = div_result;
          end else begin
            wb_data = alu_result;
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
        mem_addr = alu_result;
        if (mem_op > MEM_SEP) mem_data = rs2_val;
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
    done = 1'b0;

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
  output reg_t rs2_val
);
  reg_t x[REGMAX];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
    end else begin : writeback
      if (state == WB && we == 1) begin
        if (rd > 0) begin
          x[rd] <= wdata;
          `LOGI($sformatf("WB: x[%02d]=%h", rd, wdata));
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
  output logic interrupted
);
  // handle irq
  // handle exceptions
  // handle csr register rw
  // handle mmu
  // handle privilege level change

  `define MSTATUS_WR_MASK 64'h8000000F007FF5AA
  typedef enum logic [1:0] {
    M_USER,
    M_SUPER,
    M_MACHINE
  } mode_e;

  `define USIP 0
  `define SSIP 1
  `define MSIP 3
  `define STIP 5
  `define MTIP 7
  `define SEIP 9
  `define MEIP 11
  `define SSTATUS_READ_MASK 64'h8000_0000_000A_63F2
  `define SSTATUS_WRITE_MASK 64'h0000_0000_000A_61F2
  `define SIE_MASK 64'h0222
  `define SIP_MASK 64'h0222

  mstatus_u mstatus;
  medeleg_u medeleg;
  mintr_u mideleg, mie, mip;
  misa_u misa;

  reg_t mtvec, mtval, mepc, mcause, mhartid, mscratch;
  reg_t stvec, stval, sepc, scause, sscratch, satp;
  reg_t cycle;
  mode_e mode;

  always_comb begin
    csr_val = '0;
    if (state == EXEC && csr_idx > 0) begin
      unique case (csr_idx)
        MSTATUS: csr_val = mstatus.value;
        MISA: csr_val = misa.value;
        MEDELEG: csr_val = medeleg.value;
        MIDELEG: csr_val = mideleg.value;
        MIE: csr_val = mie.value;
        MTVEC: csr_val = mtvec;
        MSCRATCH: csr_val = mscratch;
        MEPC: csr_val = mepc;
        MCAUSE: csr_val = mcause;
        MTVAL: csr_val = mtval;
        MIP: csr_val = mip.value;
        MHARTID: csr_val = mhartid;
        SSTATUS: csr_val = mstatus.value;  //& `SSTATUS_READ_MASK;
        SIE: csr_val = mie.value & `SIE_MASK;
        STVEC: csr_val = stvec;
        SSCRATCH: csr_val = sscratch;
        SEPC: csr_val = sepc;
        SCAUSE: csr_val = scause;
        STVAL: csr_val = stval;
        SIP: csr_val = mip.value & `SIP_MASK;
        SATP: csr_val = satp;
        default: ;
      endcase
      `LOGI($sformatf("read CSR[%03h]=%h", csr_idx, csr_val));
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      mstatus.fields <= '{UXL: 2'b10, SXL: 2'b10, default: 0};
      misa.fields <= '{A: 1, I: 1, M: 1, S: 1, U: 1, MXL: 2'b10, default: 0};
      medeleg.value <= '0;
      mideleg.value <= '0;
      mtvec <= '0;
      mtval <= '0;
      mscratch <= '0;
      mepc <= '0;
      mcause <= '0;
      mie.value <= '0;
      mip.value <= '0;
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
        if (sys_op == SYS_ECALL) begin
          `LOGI("ECALL");
          unique case (mode)
            M_USER: begin
              if (medeleg.fields.ecall_from_u_mode) begin
                scause <= EXC_ECALL_U_MODE;
                sepc <= pc;
                trap_target <= stvec;
                mode <= M_SUPER;
                mstatus.fields.SPP <= 1'b0;
                mstatus.fields.SPIE <= mstatus.fields.SIE;
                mstatus.fields.SIE <= 1'b0;
              end else begin
                mcause <= EXC_ECALL_U_MODE;
                mepc <= pc;
                trap_target <= mtvec;
                mode <= M_MACHINE;
                mstatus.fields.MPP <= 2'b00;
                mstatus.fields.MPIE <= mstatus.fields.MIE;
                mstatus.fields.MIE <= 1'b0;
              end
            end
            M_SUPER: begin
              if (medeleg.fields.ecall_from_s_mode) begin
                scause <= EXC_ECALL_S_MODE;
                trap_target <= stvec;
                sepc <= pc;
                mstatus.fields.SPP <= 1'b1;
                mstatus.fields.SPIE <= mstatus.fields.SIE;
                mstatus.fields.SIE <= 1'b0;
              end else begin
                mcause <= EXC_ECALL_S_MODE;
                trap_target <= mtvec;
                mepc <= pc;
                mode <= M_MACHINE;
                mstatus.fields.MPP <= 2'b01;
                mstatus.fields.MPIE <= mstatus.fields.MIE;
                mstatus.fields.MIE <= 1'b0;
              end
            end
            M_MACHINE: begin
              mcause <= EXC_ECALL_M_MODE;
              trap_target <= mtvec;
              mepc <= pc;
              mode <= M_MACHINE;
              mstatus.fields.MPP <= 2'b10;
              mstatus.fields.MPIE <= mstatus.fields.MIE;
              mstatus.fields.MIE <= 1'b0;
            end
          endcase
        end else if (sys_op == SYS_MRET) begin
          `LOGI("MRET");
          // restore privilege
          mcause <= '0;
          mode <= mode_e'(mstatus.fields.MPP);
          trap_target <= mepc;
          mstatus.fields.MIE <= mstatus.fields.MPIE;
          mstatus.fields.MPIE <= 1'b0;
        end else if (sys_op == SYS_SRET) begin
          `LOGI("SRET");
          mcause <= '0;
          mode <= mstatus.fields.SPP ? M_SUPER : M_USER;
          trap_target <= sepc;
          mstatus.fields.SIE <= mstatus.fields.SPIE;
          mstatus.fields.SPIE <= 1'b0;
        end else if (sys_op >= SYS_CSRRW) begin
          `LOGI($sformatf("write CSR[%03h]=%h", csr_idx, csr_wdata));
          unique case (csr_idx)
            MSTATUS: mstatus.value <= (mstatus.value & ~`MSTATUS_WR_MASK) | (csr_wdata & `MSTATUS_WR_MASK);
            MEDELEG: medeleg.value <= csr_wdata;
            MIDELEG: mideleg.value <= csr_wdata;
            MIE: mie.value <= csr_wdata;
            MTVEC: mtvec <= csr_wdata;
            MSCRATCH: mscratch <= csr_wdata;
            MIP: mip.value <= csr_wdata;
            MEPC: mepc <= csr_wdata;
            MCAUSE: mcause <= csr_wdata;
            MTVAL: mtval <= csr_wdata;

            SSTATUS: mstatus.value <= (mstatus.value & ~`MSTATUS_WR_MASK) | (csr_wdata & `MSTATUS_WR_MASK);
            SIE: mie.value <= csr_wdata & `SIE_MASK;
            STVEC: stvec <= csr_wdata;
            SSCRATCH: sscratch <= csr_wdata;
            SEPC: sepc <= csr_wdata;
            SCAUSE: scause <= csr_wdata;
            STVAL: stval <= csr_wdata;
            SIP: mip.value <= csr_wdata & `SIP_MASK;
            SATP: satp <= csr_wdata;
            default: ;
          endcase
        end
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
    end else begin
      if (mideleg.fields.STI) begin
        mip.fields.STI <= irq_timer;
      end else begin
        mip.fields.MTI <= irq_timer;
      end
      if (mideleg.fields.SEI) begin
        mip.fields.SEI <= irq_external;
      end else begin
        mip.fields.MEI <= irq_external;
      end
    end
  end

  mintr_u m_intr, s_intr;
  always_comb begin
    m_intr.value = mip.value & mie.value & (~mideleg.value);
    s_intr.value = mip.value & mie.value & (mideleg.value);
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
    end else begin
      interrupted <= 1'b0;
      // `LOGI($sformatf("int m=%h, s=%h", m_intr.value, s_intr.value));
      if (state == WB && m_intr.value != reg_t'(0)) begin
        // int m-mode
        interrupted <= 1'b1;
        trap_target <= '0;
        if (mstatus.fields.MIE) begin
          mstatus.fields.MPP <= mode;
          mstatus.fields.MPIE <= mstatus.fields.MIE;
          mstatus.fields.MIE <= 1'b0;
          mode <= M_MACHINE;
          mepc <= pc;
          mcause <= mintr2cause(m_intr);
          trap_target <= mtvec;
        end
      end else if (state == WB && s_intr.value != reg_t'(0)) begin
        // int s-mode
        interrupted <= 1'b1;
        trap_target <= '0;
        if (mstatus.fields.SIE) begin
          mstatus.fields.SPP <= (mode == M_USER ? 1'b0 : 1'b1);
          mstatus.fields.SPIE <= mstatus.fields.SIE;
          mstatus.fields.SIE <= 1'b0;
          mode <= M_SUPER;
          sepc <= pc;
          scause <= sintr2cause(s_intr);
          trap_target <= stvec;
        end
      end
    end
  end

  function automatic mcause_e mintr2cause(mintr_u u);
    if (u.fields.MEI) begin
      return INTR_MACHINE_EXT;
    end else if (u.fields.MSI) begin
      return INTR_MACHINE_SW;
    end else begin
      return INTR_MACHINE_TMR;
    end
  endfunction

  function automatic mcause_e sintr2cause(mintr_u u);
    if (u.fields.SEI) begin
      return INTR_SUPERVISOR_EXT;
    end else if (u.fields.SSI) begin
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
  parameter SIZE = 1024,
  // parameter addr_t BASE = 64'b0,
  // parameter addr_t BASE = 64'h8000_0000_0000_3000,
  parameter addr_t BASE = 64'h8000_0000_0000_2000,
  parameter addr_t MASK = 64'h3ff
) (
  input logic clk,
  input logic rst_n,
  input state_e state,
  input addr_t mem_addr,
  input mem_op_e mem_op,
  input reg_t mem_data,
  output reg_t mem_rdata
);
  localparam int unsigned BITS = $clog2(SIZE);
  logic enable;

  logic [7:0] ram[SIZE];
  addr_t offset;
  `define B2R(r, a) {{56{r[a][7]}}, r[a][7:0]}
  `define H2R(r, a) {{48{r[a+1][7]}}, r[a+1], r[a]}
  `define W2R(r, a) {{32{r[a+3][7]}}, r[a+3], r[a+2], r[a+1], r[a]}
  `define D2R(r, a) {r[a+7], r[a+6], r[a+5], r[a+4], r[a+3], r[a+2], r[a+1], r[a]}
  `define BU2R(r, a) {{56'b0}, r[a]}
  `define HU2R(r, a) {{48'b0}, r[a+1], r[a]}
  `define WU2R(r, a) {{32'b0}, r[a+3], r[a+2], r[a+1], r[a]}

  integer fd;
  string hex_file;
  initial begin
    $value$plusargs("hex_file=%s", hex_file);
    if (hex_file != "") begin
      fd = $fopen({hex_file, ".data"}, "r");
      if (fd != 0) begin
        $fclose(fd);
        $readmemh({hex_file, ".data"}, ram);
        $display("ram load %s bits:%0d", {hex_file, ".data"}, BITS);
      end
    end
  end
  assign enable = (mem_addr & ~MASK) == BASE;
  assign offset = mem_addr - BASE;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int i = 0; i < SIZE; i++) begin
        // ram[i] <= '0;
      end
    end else begin
      if (state == MEMACCESS && mem_op != MEM_NONE && enable) begin
        `LOGI($sformatf("offset:%h op:%0d data: %h", offset, mem_op, mem_data));
        unique case (mem_op)
          LD_LB:  mem_rdata <= `B2R(ram, offset[BITS-1:0]);
          LD_LH:  mem_rdata <= `H2R(ram, offset[BITS-1:0]);
          LD_LW:  mem_rdata <= `W2R(ram, offset[BITS-1:0]);
          LD_LD:  mem_rdata <= `D2R(ram, offset[BITS-1:0]);
          LD_LBU: mem_rdata <= `BU2R(ram, offset[BITS-1:0]);
          LD_LHU: mem_rdata <= `HU2R(ram, offset[BITS-1:0]);
          LD_LWU: mem_rdata <= `WU2R(ram, offset[BITS-1:0]);
          SD_SB:  ram[offset[BITS-1:0]] <= mem_data[7:0];
          SD_SH:  for (logic [BITS-1:0] i = 0; i < 2; i++) ram[offset[BITS-1:0]+i] <= mem_data[8*i+:8];
          SD_SW:  for (logic [BITS-1:0] i = 0; i < 4; i++) ram[offset[BITS-1:0]+i] <= mem_data[8*i+:8];
          SD_SD:  for (logic [BITS-1:0] i = 0; i < 8; i++) ram[offset[BITS-1:0]+i] <= mem_data[8*i+:8];
        endcase
      end
    end
  end
endmodule

//-----------------------------------
// rom
//-----------------------------------
module rom #(
  parameter string HEX = "",
  parameter int unsigned SIZE = 256
) (
  input logic clk,
  input logic rst_n,
  input addr_t pc,
  output logic [31:0] instr
);
  localparam int unsigned ROMSIZE = SIZE / 4;
  localparam int unsigned BITS = $clog2(ROMSIZE);
  logic [31:0] data[ROMSIZE];
  initial begin
    string hex_file;
    $value$plusargs("hex_file=%s", hex_file);
    if (hex_file != "") begin
      $readmemh(hex_file, data);
      $display($sformatf("load %s", hex_file));
    end else begin
      $readmemh(HEX, data);
      $display($sformatf("load %s", HEX));
    end
    // `LOGI($sformatf("load %s %s", HEX, hex_file));
  end
  assign instr = data[pc[BITS+1:2]];

endmodule

//-----------------------------------
// uart
//-----------------------------------
module uart #(
  parameter addr_t BASE = 64'h2000,
  parameter addr_t MASK = 64'hfff
) (
  input logic clk,
  input logic rst_n,
  input addr_t addr,
  input state_e state,
  input mem_op_e mem_op,
  input reg_t data
);

  logic enable;
  assign enable = ((addr & ~MASK) == BASE && state == MEMACCESS);
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
`define COLOR_NONE "\033[0m"
`define RED "\033[31m"
`define GREEN "\033[32m"
module rvtest (
  input logic clk,
  input logic rst_n,
  input addr_t addr,
  input state_e state,
  input mem_op_e mem_op,
  input reg_t data
);

  // addr_t BASE = 64'h8000_0000_0000_2000;
  addr_t BASE = 64'h8000_0000_0000_1000;
  addr_t MASK = 64'hfff;

  logic enable;
  addr_t offset;
  assign enable = ((addr & ~MASK) == BASE && state == MEMACCESS);
  assign offset = addr - BASE;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
    end else begin
      if (enable && mem_op == SD_SW) begin
        if (offset == 0) begin
          if (data[31:0] == 32'd1) begin
            $display("%sPASS%s", `GREEN, `COLOR_NONE);
          end else begin
            $display($sformatf("%sFAIL%s: %0d", `RED, `COLOR_NONE, data[31:0]));
          end
          $finish;
        end
      end
    end
  end

endmodule

/******************************************************************************/
