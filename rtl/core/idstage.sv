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
  input logic instr_ready_i,

  output logic [ 4:0] rs1_o,
  output logic [ 4:0] rs2_o,
  output logic [ 4:0] rd_o,
  output logic [63:0] imm_o,

  output corepkg::id_ctrl_t ctrl_o
);

  import corepkg::*;
  id_ctrl_t ctrl;

  function id_ctrl_t decode();
    opcode_e opcode;
    logic [2:0] f3;
    logic [6:0] f7;
    logic [9:0] fc;

    opcode = opcode_e'(instr_i[6:0]);
    f3 = instr_i[14:12];
    f7 = instr_i[31:25];
    fc = {f7, f3};

    decode = '0;
    decode.alu_op = ALU_NONE;
    decode.sys_op = SYS_NONE;
    decode.fence_op = FENCE_NONE;
    decode.lsu_op = LSU_NONE;
    decode.op1 = OP1_RS1;
    decode.op2 = OP2_RS2;
    decode.imm_type = IMM_NONE;

    // handle opcode
    unique case (opcode)
      OPCODE_OP_IMM: begin
        decode.reg_write = 1;
        decode.op2 = OP2_IMM;
        decode.imm_type = IMM_I;
        unique case (f3)
          3'b000: decode.alu_op = ALU_ADD;
          3'b111: decode.alu_op = ALU_AND;
          3'b110: decode.alu_op = ALU_OR;
          3'b100: decode.alu_op = ALU_XOR;

          default: ;
        endcase
      end

      OPCODE_OP_IMM_32: begin
        decode.reg_write = 1;
        decode.op2 = OP2_IMM;
        decode.imm_type = IMM_I;
        unique case (f3)
          3'b000: decode.alu_op = ALU_ADDW;
          3'b001: decode.alu_op = ALU_SLLW;
          3'b101: decode.alu_op = (f7 == 7'b0000000) ? ALU_SRLW : ALU_SRAW;

          default: ;
        endcase
      end

      OPCODE_OP: begin
        decode.reg_write = 1;
        decode.op2 = OP2_RS2;
        unique case (fc)
          {7'b0000000, 3'b000} : decode.alu_op = ALU_ADD;
          {7'b0100000, 3'b000} : decode.alu_op = ALU_SUB;
          {7'b0000000, 3'b111} : decode.alu_op = ALU_AND;
          {7'b0000000, 3'b110} : decode.alu_op = ALU_OR;
          {7'b0000000, 3'b100} : decode.alu_op = ALU_XOR;
          {7'b0000000, 3'b001} : decode.alu_op = ALU_SLL;
          {7'b0000000, 3'b101} : decode.alu_op = ALU_SRL;
          {7'b0100000, 3'b101} : decode.alu_op = ALU_SRA;
          {7'b0000001, 3'b000} : decode.alu_op = ALU_MUL;
          {7'b0000001, 3'b100} : decode.alu_op = ALU_DIV;
          {7'b0000001, 3'b110} : decode.alu_op = ALU_REM;
          default: ;
        endcase
      end

      OPCODE_OP_32: begin
        decode.reg_write = 1;
        unique case (fc)
          {7'b0000000, 3'b000} : decode.alu_op = ALU_ADDW;
          {7'b0100000, 3'b000} : decode.alu_op = ALU_SUBW;
          {7'b0000000, 3'b001} : decode.alu_op = ALU_SLLW;
          {7'b0000000, 3'b101} : decode.alu_op = ALU_SRLW;
          {7'b0100000, 3'b101} : decode.alu_op = ALU_SRAW;
          default: ;
        endcase
      end

      OPCODE_LOAD: begin
        decode.reg_write = 1;
        decode.op2       = OP2_IMM;
        decode.imm_type  = IMM_I;
        decode.alu_op    = ALU_ADD;
        unique case (f3)
          3'b000: decode.lsu_op = LSU_LB;
          3'b001: decode.lsu_op = LSU_LH;
          3'b010: decode.lsu_op = LSU_LW;
          3'b011: decode.lsu_op = LSU_LD;
          3'b100: decode.lsu_op = LSU_LBU;
          3'b101: decode.lsu_op = LSU_LHU;
          3'b110: decode.lsu_op = LSU_LWU;

          default: ;
        endcase
      end

      OPCODE_STORE: begin
        decode.op2      = OP2_IMM;
        decode.imm_type = IMM_S;
        decode.alu_op   = ALU_ADD;
        unique case (f3)
          3'b000: decode.lsu_op = LSU_SB;
          3'b001: decode.lsu_op = LSU_SH;
          3'b010: decode.lsu_op = LSU_SW;
          3'b011: decode.lsu_op = LSU_SD;

          default: ;
        endcase
      end

      OPCODE_LUI: begin
        decode.reg_write = 1;
        decode.op2 = OP2_IMM;
        decode.imm_type = IMM_U;
      end

      OPCODE_AUIPC: begin
        decode.reg_write = 1;
        decode.op1 = OP1_PC;
        decode.op2 = OP2_IMM;
        decode.imm_type = IMM_U;
        decode.alu_op = ALU_ADD;
      end

      OPCODE_BRANCH: begin
        decode.branch   = 1;
        decode.imm_type = IMM_B;
        decode.alu_op   = ALU_SUB;
      end

      OPCODE_JAL: begin
        decode.jump = 1;
        decode.reg_write = 1;
        decode.op1 = OP1_PC;
        decode.op2 = OP2_IMM;
        decode.imm_type = IMM_J;
        decode.alu_op = ALU_ADD;
      end

      OPCODE_JALR: begin
        decode.jump = 1;
        decode.reg_write = 1;
        decode.op2 = OP2_IMM;
        decode.imm_type = IMM_I;
        decode.alu_op = ALU_ADD;
      end

      OPCODE_SYSTEM: begin
        unique case (f3)
          3'b000: begin
            unique case (instr_i[31:20])
              12'h000: decode.sys_op = SYS_ECALL;
              12'h001: decode.sys_op = SYS_EBREAK;
              12'h002: decode.sys_op = SYS_URET;
              12'h102: decode.sys_op = SYS_SRET;
              12'h302: decode.sys_op = SYS_MRET;
              default: ;
            endcase
          end
          3'b001: begin
            decode.reg_write = 1;
            decode.sys_op = SYS_CSRRW;
          end
          3'b010: begin
            decode.reg_write = 1;
            decode.sys_op = SYS_CSRRS;
          end
          3'b011: begin  // CSRRC
            decode.sys_op    = SYS_CSRRC;
            decode.reg_write = 1;
          end

          3'b101: begin  // CSRRWI
            decode.sys_op    = SYS_CSRRWI;
            decode.reg_write = 1;
          end

          3'b110: begin  // CSRRSI
            decode.sys_op    = SYS_CSRRSI;
            decode.reg_write = 1;
          end

          3'b111: begin  // CSRRCI
            decode.sys_op    = SYS_CSRRCI;
            decode.reg_write = 1;
          end
          default: ;
        endcase
      end

      OPCODE_FENCE: begin
        unique case (f3)
          3'b000:  decode.fence_op = FENCE_MEM;
          3'b001:  decode.fence_op = FENCE_I;
          default: decode.err = 1'b1;
        endcase
      end

      default: begin
        `LOGE($sformatf("BAD instr: %h", instr_i));
        decode.err = 1'b1;
      end
    endcase

  endfunction

  function logic [63:0] encode_imm(imm_type_e imm);
    unique case (imm)
      IMM_I:   encode_imm = {{52{instr_i[31]}}, instr_i[31:20]};
      IMM_S:   encode_imm = {{52{instr_i[31]}}, instr_i[31:25], instr_i[11:7]};
      IMM_B:   encode_imm = {{51{instr_i[31]}}, instr_i[31], instr_i[7], instr_i[30:25], instr_i[11:8], 1'b0};
      IMM_U:   encode_imm = {{32{1'b0}}, instr_i[31:12], 12'b0};
      IMM_J:   encode_imm = {{43{instr_i[31]}}, instr_i[31], instr_i[19:12], instr_i[20], instr_i[30:21], 1'b0};
      default: encode_imm = '0;
    endcase
  endfunction

  always_comb begin
    ctrl = '0;
    if (instr_ready_i) begin
      ctrl = decode();
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rs1_o <= '0;
      rs2_o <= '0;
      rd_o  <= '0;
      imm_o <= '0;
    end else begin
      if (instr_ready_i) begin
        rs1_o  <= instr_i[19:15];
        rs2_o  <= instr_i[24:20];
        rd_o   <= instr_i[11:7];
        ctrl_o <= ctrl;
        imm_o  <= encode_imm(ctrl.imm_type);
      end else begin
        ctrl_o.err <= '1;
      end
    end
  end

endmodule

/******************************************************************************/
