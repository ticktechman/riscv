/*
 *******************************************************************************
 *
 *        filename: idstage.sv
 *     description:
 *         created: 2026/04/26
 *          author: ticktechman
 *
 *******************************************************************************
 */

`include "rtl/inc/log.svh"

module idstage (
  input logic clk,
  input logic rst_n,
  input logic [31:0] instr_i,

  output logic [4:0] rs1_o,
  output logic [4:0] rs2_o,
  output logic [4:0] rd_o,
  output logic [63:0] imm_o,
  output logic error_o,

  output corepkg::id_ctrl_t ctrl_o
);

  import corepkg::*;

  opcode_e opcode;
  logic [2:0] f3;
  logic [6:0] f7;
  logic [9:0] fc;

  assign rs1_o = instr_i[19:15];
  assign rs2_o = instr_i[24:20];
  assign rd_o = instr_i[11:7];

  assign opcode = opcode_e'(instr_i[6:0]);
  assign f3 = instr_i[14:12];
  assign f7 = instr_i[31:25];
  assign fc = {f7, f3};

  always_comb begin
    ctrl_o = '0;
    ctrl_o.alu_op = ALU_NONE;
    ctrl_o.lsu_op = LSU_NONE;
    ctrl_o.op1 = OP1_RS1;
    ctrl_o.op2 = OP2_RS2;
    ctrl_o.imm_type = IMM_NONE;

    // handle opcode
    unique case (opcode)
      OPCODE_OP_IMM: begin
        ctrl_o.reg_write = 1;
        ctrl_o.op2 = OP2_IMM;
        ctrl_o.imm_type = IMM_I;
        unique case (f3)
          3'b000: ctrl_o.alu_op = ALU_ADD;
          3'b111: ctrl_o.alu_op = ALU_AND;
          3'b110: ctrl_o.alu_op = ALU_OR;
          3'b100: ctrl_o.alu_op = ALU_XOR;

          default: ;
        endcase
      end

      OPCODE_OP_IMM_32: begin
        ctrl_o.reg_write = 1;
        ctrl_o.op2 = OP2_IMM;
        ctrl_o.imm_type = IMM_I;
        unique case (f3)
          3'b000: ctrl_o.alu_op = ALU_ADDW;
          3'b001: ctrl_o.alu_op = ALU_SLLW;
          3'b101: ctrl_o.alu_op = (f7 == 7'b0000000) ? ALU_SRLW : ALU_SRAW;

          default: ;
        endcase
      end

      OPCODE_OP: begin
        ctrl_o.reg_write = 1;
        ctrl_o.op2 = OP2_RS2;
        unique case (fc)
          {7'b0000000, 3'b000} : ctrl_o.alu_op = ALU_ADD;
          {7'b0100000, 3'b000} : ctrl_o.alu_op = ALU_SUB;
          {7'b0000000, 3'b111} : ctrl_o.alu_op = ALU_AND;
          {7'b0000000, 3'b110} : ctrl_o.alu_op = ALU_OR;
          {7'b0000000, 3'b100} : ctrl_o.alu_op = ALU_XOR;
          {7'b0000000, 3'b001} : ctrl_o.alu_op = ALU_SLL;
          {7'b0000000, 3'b101} : ctrl_o.alu_op = ALU_SRL;
          {7'b0100000, 3'b101} : ctrl_o.alu_op = ALU_SRA;
          {7'b0000001, 3'b000} : ctrl_o.alu_op = ALU_MUL;
          {7'b0000001, 3'b100} : ctrl_o.alu_op = ALU_DIV;
          {7'b0000001, 3'b110} : ctrl_o.alu_op = ALU_REM;
          default: ;
        endcase
      end

      OPCODE_OP_32: begin
        ctrl_o.reg_write = 1;
        unique case (fc)
          {7'b0000000, 3'b000} : ctrl_o.alu_op = ALU_ADDW;
          {7'b0100000, 3'b000} : ctrl_o.alu_op = ALU_SUBW;
          {7'b0000000, 3'b001} : ctrl_o.alu_op = ALU_SLLW;
          {7'b0000000, 3'b101} : ctrl_o.alu_op = ALU_SRLW;
          {7'b0100000, 3'b101} : ctrl_o.alu_op = ALU_SRAW;
          default: ;
        endcase
      end

      OPCODE_LOAD: begin
        ctrl_o.reg_write = 1;
        ctrl_o.op2       = OP2_IMM;
        ctrl_o.imm_type  = IMM_I;
        ctrl_o.alu_op    = ALU_ADD;
        unique case (f3)
          3'b000: ctrl_o.lsu_op = LSU_LB;
          3'b001: ctrl_o.lsu_op = LSU_LH;
          3'b010: ctrl_o.lsu_op = LSU_LW;
          3'b011: ctrl_o.lsu_op = LSU_LD;
          3'b100: ctrl_o.lsu_op = LSU_LBU;
          3'b101: ctrl_o.lsu_op = LSU_LHU;
          3'b110: ctrl_o.lsu_op = LSU_LWU;

          default: ;
        endcase
      end

      OPCODE_STORE: begin
        ctrl_o.op2      = OP2_IMM;
        ctrl_o.imm_type = IMM_S;
        ctrl_o.alu_op   = ALU_ADD;
        unique case (f3)
          3'b000: ctrl_o.lsu_op = LSU_SB;
          3'b001: ctrl_o.lsu_op = LSU_SH;
          3'b010: ctrl_o.lsu_op = LSU_SW;
          3'b011: ctrl_o.lsu_op = LSU_SD;

          default: ;
        endcase
      end

      OPCODE_LUI: begin
        ctrl_o.reg_write = 1;
        ctrl_o.op2 = OP2_IMM;
        ctrl_o.imm_type = IMM_U;
      end

      OPCODE_AUIPC: begin
        ctrl_o.reg_write = 1;
        ctrl_o.op1 = OP1_PC;
        ctrl_o.op2 = OP2_IMM;
        ctrl_o.imm_type = IMM_U;
        ctrl_o.alu_op = ALU_ADD;
      end

      OPCODE_BRANCH: begin
        ctrl_o.branch   = 1;
        ctrl_o.imm_type = IMM_B;
        ctrl_o.alu_op   = ALU_SUB;
      end

      OPCODE_JAL: begin
        ctrl_o.jump = 1;
        ctrl_o.reg_write = 1;
        ctrl_o.op1 = OP1_PC;
        ctrl_o.op2 = OP2_IMM;
        ctrl_o.imm_type = IMM_J;
        ctrl_o.alu_op = ALU_ADD;
      end

      OPCODE_JALR: begin
        ctrl_o.jump = 1;
        ctrl_o.reg_write = 1;
        ctrl_o.op2 = OP2_IMM;
        ctrl_o.imm_type = IMM_I;
        ctrl_o.alu_op = ALU_ADD;
      end

      OPCODE_SYSTEM: begin
        `LOGE($sformatf("Unimplemented instr: %h", instr_i));
      end

      OPCODE_FENCE: begin
        `LOGE($sformatf("Unimplemented instr: %h", instr_i));
      end

      default: begin
        `LOGE($sformatf("bad instr: %h", instr_i));
        error_o = 1'b1;
      end
    endcase
  end

  // handle imm
  always_comb begin
    unique case (ctrl_o.imm_type)
      IMM_I: imm_o = {{52{instr_i[31]}}, instr_i[31:20]};
      IMM_S: imm_o = {{52{instr_i[31]}}, instr_i[31:25], instr_i[11:7]};
      IMM_B: imm_o = {{51{instr_i[31]}}, instr_i[31], instr_i[7], instr_i[30:25], instr_i[11:8], 1'b0};
      IMM_U: imm_o = {{32{1'b0}}, instr_i[31:12], 12'b0};
      IMM_J: imm_o = {{43{instr_i[31]}}, instr_i[31], instr_i[19:12], instr_i[20], instr_i[30:21], 1'b0};

      default: imm_o = '0;
    endcase
  end

endmodule

/******************************************************************************/
