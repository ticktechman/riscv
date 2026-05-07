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
  logic clk, rst_n;

  initial begin
    $dumpfile("mini.vcd");
    $dumpvars(0, top);
    $timeformat(-9, 3, "", 9);
  end

  clkgen #(
    .COUNTER(2000)
  ) clock (
    .clk(clk),
    .rst_n(rst_n)
  );

  soc soc1 (
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
// mini
//-------------------------------------
module soc (
  input logic clk,
  input logic rst_n
);
  // id data
  logic [4:0] rs1, rs2, rd;
  logic [4:0] csr_imm;
  logic [11:0] csr_idx;
  logic br, br_taken, jump;
  logic reg_write;
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


  exec exec1 (
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
    .imm(imm),
    .csr_imm(csr_imm),
    .pc(pc),
    .br_taken(br_taken),
    .pc_target(pc_target),
    .mem_addr(mem_addr),
    .mem_data(mem_data),
    .wb_data(wb_data),
    .csr_wdata(csr_wdata)
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
  csr csr1 (
    .clk(clk),
    .rst_n(rst_n),
    .state(state),
    .sys_op(sys_op),
    .csr_wdata(csr_wdata),
    .csr_idx(csr_idx),
    .csr_val(csr_val)
  );

  // rom
  logic [31:0] instr;
  rom #(
    .HEX("isa/isa.hex")
    // .HEX("isa/csr.hex")
    // .HEX("isa/mem.hex")
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
    .MASK(~64'hfff)
  ) uart1 (
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
        DECODE: state <= EXEC;
        EXEC: state <= MEMACCESS;
        MEMACCESS: state <= WB;
        WB: begin
          state <= FETCH;
          pc <= pc_target != 0 ? pc_target : pc + 4;
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
  ALU_BLTU,
  ALU_BGEU
} alu_op_e;

typedef enum {
  SYS_NONE,
  SYS_ECALL,
  SYS_EBREAK,
  SYS_MRET,
  SYS_SRET,
  SYS_URET,
  SYS_CSRRW,
  SYS_CSRRS,
  SYS_CSRRC,
  SYS_CSRRWI,
  SYS_CSRRSI,
  SYS_CSRRCI
} sys_op_e;

typedef enum logic [11:0] {
  MSTATUS = 12'h300,
  MTVEC   = 12'h305,
  MEPC    = 12'h341,
  MCAUSE  = 12'h342,
  MIE     = 12'h304,
  MIP     = 12'h344
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
            3'b010:  alu_op = ALU_SLT;
            3'b011:  alu_op = ALU_SLTU;
            3'b100:  alu_op = ALU_XOR;
            3'b110:  alu_op = ALU_OR;
            3'b111:  alu_op = ALU_AND;
            default: ;
          endcase
          unique case (fc)
            {7'b0000000, 3'b001} : alu_op = ALU_SLL;
            {7'b0000000, 3'b101} : alu_op = ALU_SRL;
            {7'b0100000, 3'b101} : alu_op = ALU_SRA;
            default: ;
          endcase
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
          reg_write = 1;
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
  input reg_t imm,
  input [4:0] csr_imm,
  input addr_t pc,


  output logic  br_taken,
  output addr_t pc_target,
  output addr_t mem_addr,
  output reg_t  wb_data,
  output reg_t  mem_data,
  output reg_t  csr_wdata
);
  always_comb begin : exec
    reg_t alu_result;
    logic [63:0] op1, op2;
    logic [31:0] w_result;
    if (state == EXEC) begin
      br_taken = 1'b0;
      wb_data = '0;
      mem_data = '0;
      pc_target = '0;
      op1 = (op_s1 == OP_SRC_REG) ? rs1_val : pc;
      op2 = (op_s2 == OP_SRC_REG) ? rs2_val : imm;
      `LOGI($sformatf("alu_op:%0d op1:%h op2:%h", alu_op, op1, op2));
      unique case (alu_op)
        ALU_ADD:  alu_result = op1 + op2;
        ALU_SUB:  alu_result = op1 - op2;
        ALU_AND:  alu_result = op1 & op2;
        ALU_OR:   alu_result = op1 | op2;
        ALU_XOR:  alu_result = op1 ^ op2;
        ALU_SLL:  alu_result = op1 << op2[5:0];
        ALU_SRL:  alu_result = op2 >> op2[5:0];
        ALU_SRA:  alu_result = $signed(op1) >> op2[5:0];
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
        end
        SYS_EBREAK: begin
          $finish;
        end
        SYS_MRET: begin
        end
        SYS_CSRRW: begin
          `LOGI($sformatf("csrrw"));
          // csrrw rd, csr, rs1
          // x[rd] = CSRs[csr]; CSRs[csr] = x[rs1]
          wb_data   = csr_val;
          csr_wdata = rs1_val;
        end
        SYS_CSRRS: begin
          `LOGI($sformatf("csrrs: %h", csr_val));
          wb_data   = csr_val;
          csr_wdata = csr_val | rs1_val;
        end
        SYS_CSRRC: begin
          `LOGI($sformatf("csrrc"));
          wb_data   = csr_val;
          csr_wdata = csr_val & (~rs1_val);
        end
        SYS_CSRRWI: begin
          wb_data   = csr_val;
          csr_wdata = {{59{1'b0}}, csr_imm};
        end
        SYS_CSRRSI: begin
          wb_data   = csr_val;
          csr_wdata = csr_val | {{59{1'b0}}, csr_imm};
        end
        SYS_CSRRCI: begin
          wb_data   = csr_val;
          csr_wdata = csr_val & (~{{59{1'b0}}, csr_imm});
        end
        default: ;
      endcase

      if (reg_write) begin
        if (alu_op != ALU_NONE) begin
          wb_data = alu_result;
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
  input state_e state,
  input sys_op_e sys_op,
  input reg_t csr_wdata,
  input [11:0] csr_idx,
  output reg_t csr_val
);
  reg_t mstatus, mtvec, mepc, mcause, mie, mip;
  always_comb begin
    if (state == EXEC && csr_idx > 0) begin
      csr_val = '0;
      if (csr_idx > 0) begin
        unique case (csr_idx)
          MSTATUS: csr_val = mstatus;
          MTVEC: csr_val = mtvec;
          MEPC: csr_val = mepc;
          MCAUSE: csr_val = mcause;
          MIE: csr_val = mie;
          MIP: csr_val = mip;
          default: ;
        endcase
        // `LOGI($sformatf("read CSR[%03h]=%h", csr_idx, csr_val));
      end
      `LOGI($sformatf("read CSR[%03h]=%h", csr_idx, csr_val));
    end
  end
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      mstatus <= '0;
      mtvec <= '0;
      mepc <= '0;
      mcause <= '0;
      mie <= '0;
      mip <= '0;
    end else begin
      if (state == EXEC && sys_op >= SYS_CSRRW) begin
        `LOGI($sformatf("write CSR[%03h]=%h", csr_idx, csr_wdata));
        unique case (csr_idx)
          MSTATUS: mstatus <= csr_wdata;
          MTVEC: mtvec <= csr_wdata;
          MEPC: mepc <= csr_wdata;
          MCAUSE: mcause <= csr_wdata;
          MIE: mie <= csr_wdata;
          MIP: mip <= csr_wdata;
          default: ;
        endcase
      end
    end
  end
endmodule

//-----------------------------------
// sram
//-----------------------------------
module sram (
  input logic clk,
  input logic rst_n,
  input state_e state,
  input addr_t mem_addr,
  input mem_op_e mem_op,
  input reg_t mem_data,
  output reg_t mem_rdata
);
  localparam int unsigned RAMSIZE = 128;
  logic [7:0] ram[RAMSIZE];
  `define B2R(r, a) {{56{r[a][7]}}, r[a][7:0]}
  `define H2R(r, a) {{48{r[a+1][7]}}, r[a+1], r[a]}
  `define W2R(r, a) {{32{r[a+3][7]}}, r[a+3], r[a+2], r[a+1], r[a]}
  `define D2R(r, a) {r[a+7], r[a+6], r[a+5], r[a+4], r[a+3], r[a+2], r[a+1], r[a]}
  `define BU2R(r, a) {{56'b0}, r[a]}
  `define HU2R(r, a) {{48'b0}, r[a+1], r[a]}
  `define WU2R(r, a) {{32'b0}, r[a+3], r[a+2], r[a+1], r[a]}

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int i = 0; i < RAMSIZE; i++) begin
        ram[i] <= '0;
      end
    end else begin
      if (state == MEMACCESS && mem_op != MEM_NONE && mem_addr < 64'(RAMSIZE)) begin
        unique case (mem_op)
          LD_LB:  mem_rdata <= `B2R(ram, mem_addr[6:0]);
          LD_LH:  mem_rdata <= `H2R(ram, mem_addr[6:0]);
          LD_LW:  mem_rdata <= `W2R(ram, mem_addr[6:0]);
          LD_LD:  mem_rdata <= `D2R(ram, mem_addr[6:0]);
          LD_LBU: mem_rdata <= `BU2R(ram, mem_addr[6:0]);
          LD_LHU: mem_rdata <= `HU2R(ram, mem_addr[6:0]);
          LD_LWU: mem_rdata <= `WU2R(ram, mem_addr[6:0]);
          SD_SB:  ram[mem_addr[6:0]] <= mem_data[7:0];
          SD_SH:  for (logic [6:0] i = 0; i < 2; i++) ram[mem_addr[6:0]+i] <= mem_data[8*i+:8];
          SD_SW:  for (logic [6:0] i = 0; i < 4; i++) ram[mem_addr[6:0]+i] <= mem_data[8*i+:8];
          SD_SD:  for (logic [6:0] i = 0; i < 8; i++) ram[mem_addr[6:0]+i] <= mem_data[8*i+:8];
        endcase
      end
    end
  end
endmodule

//-----------------------------------
// rom
//-----------------------------------
module rom #(
  parameter string HEX = ""
) (
  input logic clk,
  input logic rst_n,
  input addr_t pc,
  output logic [31:0] instr
);
  localparam ROMSIZE = 64;
  logic [31:0] data[ROMSIZE];
  initial begin
    $readmemh(HEX, data);
    `LOGI($sformatf("load %s", HEX));
  end
  assign instr = data[pc[7:2]];
endmodule

//-----------------------------------
// uart
//-----------------------------------
module uart #(
  parameter addr_t BASE = 64'h2000,
  parameter addr_t MASK = ~64'hfff
) (
  input logic clk,
  input logic rst_n,
  input addr_t addr,
  input state_e state,
  input mem_op_e mem_op,
  input reg_t data
);

  logic enable;
  assign enable = ((addr & MASK) == BASE && state == MEMACCESS) ? 1 : 0;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
    end else begin
      if (enable && mem_op == SD_SB) begin
        $write("%c", data[7:0]);
      end
    end
  end

endmodule
/******************************************************************************/
