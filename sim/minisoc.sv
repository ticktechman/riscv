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

`define LOGI(msg) $display("[I|%9t|%m] %s", $realtime, msg)
`define LOGW(msg) $display("[W|%9t|%m] %s", $realtime, msg)
`define LOGE(msg) $display("[E|%9t|%m] %s", $realtime, msg)

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
    .COUNTER(100)
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
    ALU_ADD,
    ALU_SUB,
    ALU_BEQ,
    ALU_BNE,
    ALU_BLT,
    ALU_BGE,
    ALU_BLTU,
    ALU_BGEU
  } alu_op_e;

  typedef enum {
    MEM_NONE,
    MEM_LD,
    MEM_SD
  } mem_op_e;

  typedef enum {
    LD_NONE,
    LD_LB,
    LD_LH,
    LD_LW,
    LD_LD,
    LD_LBU,
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


  // id data
  logic [4:0] rs1, rs2, rd;
  logic [63:0] imm;
  logic [2:0] f3;
  logic [6:0] f7;
  logic [9:0] fc;
  logic br, br_taken;
  imm_type_e imm_type;
  op_src_e op_s1, op_s2;
  opcode_e opcode;
  alu_op_e alu_op;
  mem_op_e mem_op;
  ld_op_e ld_op;
  sd_op_e sd_op;
  logic reg_write;

  // exec data
  addr_t mem_addr, br_target, j_target;
  reg_t alu_result, wb_data, mem_data, mem_rdata;

  // members
  state_e state;
  addr_t pc;
  reg_t x[REGMAX];
  reg_t csr[REGMAX];

  always_comb begin
    if (state == DECODE) begin
      alu_op = ALU_NONE;
      mem_op = MEM_NONE;
      ld_op = LD_NONE;
      sd_op = SD_NONE;
      imm_type = IMM_NONE;
      op_s1 = OP_SRC_NONE;
      op_s2 = OP_SRC_NONE;
      reg_write = 0;
      br = 1'b0;

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
          mem_op = MEM_LD;
          alu_op = ALU_ADD;
          imm_type = IMM_I;
          op_s1 = OP_SRC_REG;
          op_s2 = OP_SRC_IMM;
          unique case (f3)
            3'b000:  ld_op = LD_LB;
            3'b001:  ld_op = LD_LH;
            3'b010:  ld_op = LD_LW;
            3'b011:  ld_op = LD_LD;
            3'b100:  ld_op = LD_LBU;
            3'b101:  ld_op = LD_LHU;
            3'b110:  ld_op = LD_LWU;
            default: ;
          endcase
        end
        OPCODE_STORE: begin
          `LOGI("STORE");
          // 00403023: sd x4, 0(x0)
          // ALU: addr = rs1 + imm;
          // mem[addr] = rs2
          reg_write = 1;
          mem_op = MEM_SD;
          alu_op = ALU_ADD;
          imm_type = IMM_S;
          op_s1 = OP_SRC_REG;
          op_s2 = OP_SRC_IMM;
          unique case (f3)
            3'b000:  sd_op = SD_SB;
            3'b001:  sd_op = SD_SH;
            3'b010:  sd_op = SD_SW;
            3'b011:  sd_op = SD_SD;
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

  always_comb begin : exec
    logic [63:0] op1, op2;
    if (state == EXEC) begin
      br_taken = 1'b0;
      wb_data = '0;
      mem_data = '0;
      op1 = (op_s1 == OP_SRC_REG) ? x[rs1] : pc;
      op2 = (op_s2 == OP_SRC_REG) ? x[rs2] : imm;
      unique case (alu_op)
        ALU_ADD:  alu_result = op1 + op2;
        ALU_SUB:  alu_result = op1 - op2;
        ALU_BNE:  alu_result = (op1 != op2) ? 1 : 0;
        ALU_BEQ:  alu_result = (op1 == op2) ? 1 : 0;
        ALU_BLT:  alu_result = ($signed(op1) < $signed(op2)) ? 1 : 0;
        ALU_BGE:  alu_result = ($signed(op1) >= $signed(op2)) ? 1 : 0;
        ALU_BLTU: alu_result = (op1 < op2) ? 1 : 0;
        ALU_BGEU: alu_result = (op1 >= op2) ? 1 : 0;
        default:  alu_result = '0;
      endcase
      // `LOGI($sformatf(
      //       "s[%02d,%02d] rs[%02d, %02d] op[%h,%h] alu:%0d result:%0d",
      //       op_s1,
      //       op_s2,
      //       rs1,
      //       rs2,
      //       op1,
      //       op2,
      //       alu_op,
      //       alu_result
      //       ));
      if (reg_write) begin
        wb_data = alu_result;
      end
      if (br == 1) begin
        br_taken = alu_result[0];
        if (br_taken) begin
          br_target = pc + imm;
        end
      end
      if (opcode == OPCODE_JAL) begin
        // rd = PC+4; PC=PC+imm;
        wb_data  = pc + 4;
        j_target = alu_result;
      end
      if (opcode == OPCODE_JALR) begin
        // rd = PC+4; PC = (rs1 + imm) & ~1 ;
        wb_data  = pc + 4;
        j_target = alu_result & ~1;
      end
      if (mem_op != MEM_NONE) begin
        mem_addr = alu_result;
        if (mem_op == MEM_SD) begin
          mem_data = x[rs2];
        end
      end
    end
  end

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
        IDLE: begin
          `LOGI("idle ...");
          state <= FETCH;
        end
        FETCH: begin
          `LOGI($sformatf("start fetch pc=%h instr=%h", pc, instr));
          state <= DECODE;
        end
        DECODE: begin
          state <= EXEC;
        end
        EXEC: begin
          state <= MEMACCESS;
        end
        MEMACCESS: begin
          state <= WB;
        end
        WB: begin
          state <= FETCH;
          if (br_taken) begin
            pc <= br_target;
            `LOGI($sformatf("pc to br_target=%h", br_target));
          end else if (opcode == OPCODE_JAL || opcode == OPCODE_JALR) begin
            `LOGI($sformatf("pc to j_target=%h", j_target));
            pc <= j_target;
          end else begin
            pc <= pc + 4;
          end
        end
        default: ;
      endcase
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
    end else begin
      if (state == WB && reg_write == 1) begin
        if (rd > 0) begin
          if (mem_op == MEM_LD) begin
            x[rd] <= mem_rdata;
            `LOGI($sformatf("WB: x[%02d]=%h", rd, mem_rdata));
          end else begin
            `LOGI($sformatf("WB: x[%02d]=%h", rd, wb_data));
            x[rd] <= wb_data;
          end
        end
      end
    end
  end

  //---------------------------------
  // rom
  //---------------------------------
  localparam ROMSIZE = 64;
  logic [31:0] rom[ROMSIZE], instr;
  initial begin
    rom[0]  = 32'h00500093;  // addi x1, x0, 5
    rom[1]  = 32'h00a00113;  // addi x2, x0, 10
    rom[2]  = 32'h002081b3;  // add  x3, x1, x2
    rom[3]  = 32'h00318233;  // add  x4, x3, x3
    rom[4]  = 32'h00403023;  // sd   x4, 0(x0)
    rom[5]  = 32'h00003283;  // ld   x5, 0(x0)
    rom[6]  = 32'h00528333;  // add  x6, x5, x5
    rom[7]  = 32'h00628663;  // beq  x5, x6, +12
    rom[8]  = 32'h00100393;  // addi x7, x0, 1
    rom[9]  = 32'h00630663;  // beq  x6, x6, +12
    rom[10] = 32'h06300413;  // addi x8, x0, 99 (flushed)
    rom[11] = 32'h00200493;  // addi x9, x0, 2
    rom[12] = 32'h008000ef;  // jal  x1, +8
    rom[13] = 32'h00300513;  // addi x10, x0, 3
    rom[14] = 32'h00400593;  // addi x11, x0, 4
    rom[15] = 32'h00008067;  // jalr x0, x1, 0
    rom[16] = 32'h00b03023;  // sd   x11, 0(x0)
    rom[17] = 32'h00003603;  // ld   x12, 0(x0)
    rom[18] = 32'h00100693;  // addi x13, x0, 1
  end
  assign instr = rom[pc[7:2]];

  //---------------------------------
  // ram
  //---------------------------------
  localparam int unsigned RAMSIZE = 128;
  logic [7:0] ram[RAMSIZE];
  logic [6:0] addr;
  reg_t raw;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int i = 0; i < RAMSIZE; i++) begin
        ram[i] <= '0;
      end
    end else begin
      if (state == MEMACCESS && mem_op != MEM_NONE) begin
        addr = mem_addr[6:0];
        unique case (mem_op)
          MEM_LD: begin
            `LOGI($sformatf("load m[%0d]", addr));
            unique case (ld_op)
              LD_LB: begin
                mem_rdata <= {{56{ram[addr][7]}}, ram[addr][7:0]};
              end
              LD_LH: begin
                mem_rdata <= {{48{ram[addr+1][7]}}, ram[addr+1], ram[addr]};
              end
              LD_LW: begin
                mem_rdata <= {{32{ram[addr+3][7]}}, ram[addr+3], ram[addr+2], ram[addr+1], ram[addr]};
              end
              LD_LD: begin
                mem_rdata <= {
                  ram[addr+7], ram[addr+6], ram[addr+5], ram[addr+4], ram[addr+3], ram[addr+2], ram[addr+1], ram[addr]
                };
              end
              LD_LBU: begin
                mem_rdata <= {{56'b0}, ram[addr]};
              end
              LD_LHU: begin
                mem_rdata <= {{48'b0}, ram[addr+1], ram[addr]};
              end
              LD_LWU: begin
                mem_rdata <= {{32'b0}, ram[addr+3], ram[addr+2], ram[addr+1], ram[addr]};
              end
            endcase
          end
          MEM_SD: begin
            `LOGI($sformatf("m[%0d]=%h", addr, mem_data));
            unique case (sd_op)
              SD_SB: begin
                ram[addr] <= mem_data[7:0];
              end
              SD_SH: begin
                ram[addr]   <= mem_data[7:0];
                ram[addr+1] <= mem_data[15:8];
              end
              SD_SW: begin
                ram[addr]   <= mem_data[7:0];
                ram[addr+1] <= mem_data[15:8];
                ram[addr+2] <= mem_data[23:16];
                ram[addr+3] <= mem_data[31:24];
              end
              SD_SD: begin
                ram[addr]   <= mem_data[7:0];
                ram[addr+1] <= mem_data[15:8];
                ram[addr+2] <= mem_data[23:16];
                ram[addr+3] <= mem_data[31:24];
                ram[addr+4] <= mem_data[39:32];
                ram[addr+5] <= mem_data[47:40];
                ram[addr+6] <= mem_data[55:48];
                ram[addr+7] <= mem_data[63:56];
              end
            endcase
          end
        endcase
      end
    end
  end

endmodule

/******************************************************************************/
