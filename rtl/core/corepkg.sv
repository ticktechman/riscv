/*
 *******************************************************************************
 *
 *        filename: corepkg.sv
 *     description:
 *         created: 2026/04/27
 *          author: ticktechman
 *
 *******************************************************************************
 */

package corepkg;

  typedef enum logic [6:0] {
    OPCODE_LOAD      = 7'b0000011,  // Load (lb, lw, ld, lh...)
    OPCODE_LOAD_FP   = 7'b0000111,  // Floating-point load (flw, fld)
    OPCODE_FENCE     = 7'b0001111,  // FENCE, FENCE.I
    OPCODE_OP_IMM    = 7'b0010011,  // ALU reg-imm (addi, xori, slli...)
    OPCODE_AUIPC     = 7'b0010111,  // AUIPC
    OPCODE_OP_IMM_32 = 7'b0011011,  // RV64 reg-imm word ops (addiw, slliw...)
    OPCODE_STORE     = 7'b0100011,  // Store (sb, sw, sd...)
    OPCODE_STORE_FP  = 7'b0100111,  // Floating-point store (fsw, fsd)
    OPCODE_AMO       = 7'b0101111,  // Atomic memory ops (lr/sc, amo*)
    OPCODE_OP        = 7'b0110011,  // ALU reg-reg (add, sub, mul, div...)
    OPCODE_LUI       = 7'b0110111,  // LUI
    OPCODE_OP_32     = 7'b0111011,  // RV64 reg-reg word ops (addw, mulw...)
    OPCODE_FMADD     = 7'b1000011,  // FMADD.S / FMADD.D
    OPCODE_FMSUB     = 7'b1000111,  // FMSUB.S / FMSUB.D
    OPCODE_FNMSUB    = 7'b1001011,  // FNMSUB.S / FNMSUB.D
    OPCODE_FNMADD    = 7'b1001111,  // FNMADD.S / FNMADD.D
    OPCODE_FP_OP     = 7'b1010011,  // FP ALU (fadd, fmul, fdiv, fsqrt...)
    OPCODE_FP_CMP    = 7'b1010001,  // FP compare (feq, flt, fle)
    OPCODE_BRANCH    = 7'b1100011,  // Branch (beq, bne, blt...)
    OPCODE_JALR      = 7'b1100111,  // JALR
    OPCODE_JAL       = 7'b1101111,  // JAL
    OPCODE_SYSTEM    = 7'b1110011   // ECALL, EBREAK, CSRR*
  } opcode_e;

  typedef enum logic [5:0] {
    ALU_ADD,
    ALU_SUB,
    ALU_AND,
    ALU_OR,
    ALU_XOR,
    ALU_SLL,
    ALU_SRL,
    ALU_SRA,
    ALU_SLT,
    ALU_SLTU,
    ALU_MUL,
    ALU_MULH,
    ALU_DIV,
    ALU_REM,

    // RV64 W
    ALU_ADDW,
    ALU_SUBW,
    ALU_SLLW,
    ALU_SRLW,
    ALU_SRAW,

    ALU_NONE
  } alu_op_e;

  typedef enum logic {
    OP1_RS1,
    OP1_PC
  } op1_e;

  typedef enum logic {
    OP2_RS2,
    OP2_IMM
  } op2_e;

  typedef enum logic [2:0] {
    IMM_I,
    IMM_S,
    IMM_B,
    IMM_U,
    IMM_J,
    IMM_NONE
  } imm_type_e;

  typedef enum logic [3:0] {
    LSU_NONE,
    LSU_LB,
    LSU_LH,
    LSU_LW,
    LSU_LD,
    LSU_LBU,
    LSU_LHU,
    LSU_LWU,
    LSU_SB,
    LSU_SH,
    LSU_SW,
    LSU_SD
  } lsu_op_e;

  typedef struct packed {
    logic branch;
    logic jump;
    logic reg_write;

    op1_e      op1;
    op2_e      op2;
    alu_op_e   alu_op;
    lsu_op_e   lsu_op;
    imm_type_e imm_type;
  } id_ctrl_t;

endpackage

/******************************************************************************/
