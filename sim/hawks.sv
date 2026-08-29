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
  localparam int unsigned MASTER_CNT = 3;
  localparam int unsigned SLAVE_CNT = 7;
  localparam int unsigned REGMAX = 32;
  localparam int unsigned KB = 1024;
  localparam int unsigned MB = 1024 * KB;
  localparam addr_t BOOT_ADDR = 64'h8000_0000;

`ifdef DEBUG_LOG
  `define LOGI(msg) $display("[I|%9t|%m.%0d] %s", $realtime, `__LINE__, msg)
  `define LOGW(msg) $display("%s[W|%9t|%m.%0d] %s%s", `COLOR_YELLOW, $realtime, `__LINE__, msg, `COLOR_NONE)
  `define LOGE(msg) $display("%s[E|%9t|%m.%0d] %s%s", `COLOR_RED, $realtime, `__LINE__, msg, `COLOR_NONE)
`else
  `define LOGI(msg)
  `define LOGW(msg)
  `define LOGE(msg)
`endif

  `define LOGPTE(tag, x) `LOGI($sformatf("%s(PPN-%h D%b A%b U%b X%b W%b R%b V%b)", \
     tag, x.PPN, x.D, x.A, x.U, x.X, x.W, x.R, x.V));
  `define LOGTLB(tag, x) `LOGI($sformatf("%s(PPN-%0h VPN-%0h ASID-%0h PG:%0d c%b D%b A%b U%b X%b W%b R%b V%b)", \
     tag, x.PPN, x.VPN, x.ASID, x.PGSIZE, x.cached, x.D, x.A, x.U, x.X, x.W, x.R, x.V));

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
  `define FW2R(r, a) {{32{1'b1}}, r[a+3], r[a+2], r[a+1], r[a]}
  `define WU2I(r, a) {r[a+3], r[a+2], r[a+1], r[a]}
  `define write_data(r, off, data, sz) for (idx_t i = 0; i < sz; i++) r[off+i] <= data[8*i+:8]

  `define overlap(s1, t1, s2, t2) ((s1>=s2 && s1<=s2+databytes(t2)) || (s2>=s1 && s2<s1+databytes(t1)))

  `define elf_load(surfix, data) \
    begin \
      string elf; \
      int fd; \
      $value$plusargs("elf=%s", elf); \
      if (elf != "") begin: elfload \
        elf = {elf, surfix}; \
        fd  = $fopen(elf, "r"); \
        if (fd != 0) begin \
          $fclose(fd); \
          $readmemh(elf, data); \
          `LOGI($sformatf("load %s", elf)); \
        end else begin \
          `LOGE($sformatf("fail to load %s", elf)); \
          $finish(1); \
        end \
      end \
    end\

  `define ONES(n) {n{1'b1}}
  `define BOXED_F32(v) (v[63:32] == 32'hffff_ffff)
  `define MASK(N, n) ((N'(1) << n) - 1)
  `define OR_NBITS(val, n) (|(val & `MASK($bits(val), n)))
  `define min(a, b) (a < b ? a : b)
  `define max(a, b) (a > b ? a : b)

  typedef logic [63:0] reg_t;
  typedef logic [63:0] addr_t;
  typedef logic [31:0] instr_t;


  // basic data types
  typedef logic [63:0] u64_t;
  typedef logic [31:0] u32_t;
  typedef logic [15:0] u16_t;
  typedef logic signed [63:0] i64_t;
  typedef logic signed [31:0] i32_t;
  typedef logic signed [15:0] i16_t;

  typedef struct packed {
    longint unsigned BASE;
    longint unsigned END;
  } mmap_t;

  // for opensbi + linux + busybox
  // parameter mmap_t mapping[SLAVE_CNT] = '{
  //     '{BASE: addr_t'('ha000_0000), END: addr_t'('ha000_0fff)},  // rom
  //     '{BASE: addr_t'('ha000_1000), END: addr_t'('ha000_1fff)},  // tohost
  //     '{BASE: addr_t'('h8000_0000), END: addr_t'('h8fff_ffff)},  // sram
  //     '{BASE: addr_t'('h0200_0000), END: addr_t'('h0200_ffff)},  // clint
  //     '{BASE: addr_t'('h0c00_0000), END: addr_t'('h0fff_ffff)},  // plic
  //     '{BASE: addr_t'('h9000_0000), END: addr_t'('h9000_0fff)},  // igen
  //     '{BASE: addr_t'('h9000_1000), END: addr_t'('h9000_1fff)}  // uart8250
  // };

  // for normal dev and test
  // parameter mmap_t mapping[SLAVE_CNT] = '{
  //     '{BASE: addr_t'('h8000_0000), END: addr_t'('h8000_0fff)},
  //     '{BASE: addr_t'('h8000_1000), END: addr_t'('h8000_1fff)},
  //     '{BASE: addr_t'('h8000_2000), END: addr_t'('h8000_afff)},
  //     '{BASE: addr_t'('h0200_0000), END: addr_t'('h0200_ffff)},
  //     '{BASE: addr_t'('h0c00_0000), END: addr_t'('h0fff_ffff)},
  //     '{BASE: addr_t'('h9000_0000), END: addr_t'('h9000_0fff)},
  //     '{BASE: addr_t'('h9000_1000), END: addr_t'('h9000_1fff)}
  // };

  // fpu-test
  parameter mmap_t mapping[SLAVE_CNT] = '{
      '{BASE: addr_t'('h8000_0000), END: addr_t'('h8000_0fff)},  // rom
      '{BASE: addr_t'('h8000_1000), END: addr_t'('h8000_1fff)},  // tohost
      '{BASE: addr_t'('h8000_2000), END: addr_t'('h8fff_ffff)},  // sram
      '{BASE: addr_t'('h0200_0000), END: addr_t'('h0200_ffff)},  // clint
      '{BASE: addr_t'('h0c00_0000), END: addr_t'('h0fff_ffff)},  // plic
      '{BASE: addr_t'('h9000_0000), END: addr_t'('h9000_0fff)},  // igen
      '{BASE: addr_t'('h9000_1000), END: addr_t'('h9000_1fff)}  // uart8250
  };

  typedef enum {
    S8,    // 0
    U8,
    S16,
    U16,
    S32,
    U32,   // 5
    F32,
    US64,
    F64
  } datatype_e;

  function automatic addr_t databytes(datatype_e dtype);
    unique case (dtype)
      S8, U8: return 64'd1;
      S16, U16: return 64'd2;
      S32, U32, F32: return 64'd4;
      default: return 64'd8;
    endcase
  endfunction

  typedef enum {
    STG_IDLE,
    STG_FETCH,
    STG_DECODE,
    STG_EXEC,
    STG_MEM,
    STG_AMO,  // 5
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

    INTR_SUPERVISOR_SW  = 64'h8000_0000_0000_0001,  // S-level software interrupt
    INTR_MACHINE_SW     = 64'h8000_0000_0000_0003,  // M-level software interrupt
    INTR_SUPERVISOR_TMR = 64'h8000_0000_0000_0005,  // S-level timer interrupt
    INTR_MACHINE_TMR    = 64'h8000_0000_0000_0007,  // M-level timer interrupt
    INTR_SUPERVISOR_EXT = 64'h8000_0000_0000_0009,  // S-level external interrupt
    INTR_MACHINE_EXT    = 64'h8000_0000_0000_000B   // M-level external interrupt
  } mcause_e;

  typedef struct packed {
    logic    fired;
    mcause_e cause;
    reg_t    eval;
  } exception_t;

  // 32-bit instruction imm type
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
    OPCODE_SYSTEM    = 7'b1110011,  // ECALL, EBREAK, CSRR*

    // FPU related
    OPCODE_FP_LOAD  = 7'b0000111,  // Floating-point Load (flw, fld, flh...)
    OPCODE_FP_STORE = 7'b0100111,  // Floating-point Store (fsw, fsd, fsh...)
    OPCODE_FMADD    = 7'b1000011,  // Fused Multiply-Add (fmadd.s, fmadd.d...)
    OPCODE_FMSUB    = 7'b1000111,  // Fused Multiply-Sub (fmsub.s, fmsub.d...)
    OPCODE_FNMSUB   = 7'b1001011,  // Negated Fused Multiply-Sub (fnmsub.s...)
    OPCODE_FNMADD   = 7'b1001111,  // Negated Fused Multiply-Add (fnmadd.s...)
    OPCODE_FP_OP    = 7'b1010011   // FP reg-reg ops (fadd, fsub, fcvt, fmv...)
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
    SYS_ECALL,   // 1
    SYS_EBREAK,
    SYS_MRET,
    SYS_SRET,
    SYS_WFI,     // 5
    SYS_URET,
    SYS_FENCE,
    SYS_CSRRW,
    SYS_CSRRS,
    SYS_CSRRC,   // 10
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
    // FPU related
    FFLAGS = 12'h001,
    FRM    = 12'h002,
    FCSR   = 12'h003,

    // csr register in unprivilege mode
    CYCLE   = 12'hC00,
    TIME    = 12'hC01,
    INSTRET = 12'hC02,

    // m-mode register
    MVENDORID = 12'hF11,
    MARCHID   = 12'hF12,
    MIMPID    = 12'hF13,

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
    SATP       = 12'h180,

    // others
    MNSTATUS = 12'h744
  } csr_e;

  typedef enum {
    LD_NONE,
    LD_LB,
    LD_LH,
    LD_LW,
    LD_LD,
    LD_LBU,   // 5
    LD_LHU,
    LD_LWU,
    LD_LFW,   // float
    LD_LFD    // double
  } ld_op_e;

  typedef enum {
    SD_NONE,
    SD_SB,
    SD_SH,
    SD_SW,
    SD_SD,
    SD_SFW,
    SD_SFD
  } sd_op_e;

  typedef enum {
    OP_SRC_NONE,
    OP_SRC_REG,
    OP_SRC_IMM,
    OP_SRC_AMO,
    OP_SRC_PC,
    OP_SRC_FPR
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
    fop_e     fop;

    logic [4:0]  rs1;
    logic [4:0]  rs2;
    logic [4:0]  rs3;
    logic [4:0]  rd;
    logic [4:0]  csr_imm;
    logic [11:0] csr;
    logic        reg_write;
    logic        fpr_write;
    logic        rvc;
    logic        single;
    logic [2:0]  frm;

    op_src_e op_s1;
    op_src_e op_s2;
    op_src_e op_s3;
    reg_t    imm;
  } id_t;

  typedef enum {
    WB_SRC_NONE,
    WB_SRC_ALU,
    WB_SRC_MEM,
    WB_SRC_AMO,
    WB_SRC_CSR,
    WB_SRC_FPU
  } wb_src_e;

  typedef enum logic [1:0] {
    M_USER    = 2'b00,
    M_SUPER   = 2'b01,
    M_MACHINE = 2'b11
  } priviledge_e;

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
    logic [28:0] HPM;  // Bits [31:3]: 硬件性能监视器计数器使能位 (hpmcounter3~31)
    logic        IR;   // Bit 2: 指令执行计数器使能位 (instret)
    logic        TM;   // Bit 1: 时间计数器使能位 (time)
    logic        CY;   // Bit 0: 周期计数器使能位 (cycle)
  } mcounteren_t;

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
    PG_4K,
    PG_2M,
    PG_1G
  } pagesize_e;

  typedef struct packed {
    logic        cached;
    pagesize_e   PGSIZE;  // page size
    logic [15:0] ASID;    // address space ID
    logic [26:0] VPN;     // virtual page number
    logic [43:0] PPN;     // physical page number
    logic        V;       // valid
    logic        G;       // global
    logic        U;       // permission user
    logic        X;       // permission execution
    logic        W;       // permission write
    logic        R;       // permission read
    logic        D;       // dirty
    logic        A;       // accessed
  } tlb_entry_t;


  //------------------------------------
  // rv64fd related data defination
  //------------------------------------
  typedef struct packed {
    logic nv;  // invalid operation
    logic dz;  // divide zero
    logic of;  // overflow
    logic uf;  // underflow
    logic nx;  // inexact
  } fflags_t;

  typedef enum logic [2:0] {
    RNE = 3'b000,  // Round to Nearest, ties to Even (default mode)
    RTZ = 3'b001,  // Round towards Zero
    RDN = 3'b010,  // Round Down, towards -Infinity
    RUP = 3'b011,  // Round Up, towards +Infinity
    RMM = 3'b100,  // Round to Nearest, ties to Max Magnitude
    DYN = 3'b111   // Dynamic Rounding Mode
  } frm_e;

  typedef struct packed {
    logic [23:0] reserved;  // Bits [31:8] reserved
    logic [2:0]  frm;       // Bits [7:5] : Dynamic Rounding Mode
    fflags_t     fflags;    // Bits [4:0] : Accrued Exceptions
  } fcsr_t;

  typedef struct packed {
    logic NAN;
    logic SNAN;
    logic QNAN;
    logic INF;
    logic ZERO;
    logic SUBN;
  } fattr_t;

  typedef struct packed {logic G, R, S;} grs_t;

  typedef enum logic [6:0] {
    FOP_NONE = 7'b00_00000,

    // add / sub / fma
    FOP_ADD   = 7'b00_00001,
    FOP_SUB   = 7'b00_00010,
    FOP_MADD  = 7'b00_00011,
    FOP_MSUB  = 7'b00_00100,
    FOP_NMADD = 7'b00_00101,
    FOP_NMSUB = 7'b00_00110,

    // mul
    FOP_MUL = 7'b01_00000,

    // div
    FOP_DIV  = 7'b10_00000,
    FOP_SQRT = 7'b10_00001,

    // misc
    FOP_CMP_EQ   = 7'b11_00000,
    FOP_CMP_LT   = 7'b11_00001,
    FOP_CMP_LE   = 7'b11_00010,
    FOP_MIN      = 7'b11_00011,
    FOP_MAX      = 7'b11_00100,
    FOP_CLASS    = 7'b11_00101,
    FOP_SGNJ     = 7'b11_00110,
    FOP_SGNJN    = 7'b11_00111,
    FOP_SGNJX    = 7'b11_01000,
    FOP_CVT_W_F  = 7'b11_01001,
    FOP_CVT_WU_F = 7'b11_01010,
    FOP_CVT_L_F  = 7'b11_01011,
    FOP_CVT_LU_F = 7'b11_01100,
    FOP_CVT_F_W  = 7'b11_01101,
    FOP_CVT_F_WU = 7'b11_01110,
    FOP_CVT_F_L  = 7'b11_01111,
    FOP_CVT_F_LU = 7'b11_10000,
    FOP_CVT_S_D  = 7'b11_10001,  // fcvt.s.d = double to single
    FOP_CVT_D_S  = 7'b11_10010,  // fcvt.d.s = single to double
    FOP_MV_X_F   = 7'b11_10011,  // FMV.X.W = mv single / double to integer
    FOP_MV_F_X   = 7'b11_10110   // FMV.D.X = mv integer to double / single
  } fop_e;

  typedef struct packed {
    logic        s;
    logic [7:0]  e;
    logic [22:0] f;
  } f32_t;

  typedef struct packed {
    logic [31:0] box;
    logic        s;
    logic [7:0]  e;
    logic [22:0] f;
  } f32_boxed_t;

  typedef struct packed {
    logic        s;
    logic [10:0] e;
    logic [51:0] f;
  } f64_t;

  typedef struct packed {
    logic    valid;
    reg_t    result;
    fflags_t flags;
  } ffast_t;

  typedef struct packed {
    logic sign;
    logic [11:0] exp;
    logic [52:0] manti;  // hidden-1bit, frac-52bit
  } funpack_t;

  typedef struct packed {
    reg_t result;
    fflags_t flags;
  } fpacked_t;

  // canonical qNaN
  localparam CQNAN_D = 64'h7FF8000000000000;
  localparam CQNAN_S = 64'hFFFFFFFF7FC00000;

  `define fp_sign(single, v) (single ? v[31] : v[63])
  `define fp_exp(single, v, N) (single ? N'(v[30:23]) : N'(v[62:52]))
  `define fp_frac(single, v) (single ? {29'b0, v[22:0]} : v[51:0])
  `define fp_manti(single, v) (single ? {1'b1, v[22:0], 29'b0} : {1'b1, v[51:0]})
  `define fp_subn_manti(single, v) (single ? {1'b0, v[22:0], 29'b0} : {1'b0, v[51:0]})
  `define fp_bias(single, N) (single ? N'd127 : N'd1023)
  `define fp_abs(single, v) (single ? v[30:0] : v[62:0])
  `define fp_abs64(single, v) (single ? {33'b0, v[30:0]} : {1'b0, v[62:0]})
  `define fp_pack(single, s, e, m) (single ? {32'hffff_ffff, s, e[7:0], m[22:0]} : {s, e[10:0], m[51:0]})
  `define fp_zero(single, s) (single ? {32'hffff_ffff, s, 31'b0} : {s, 63'b0})
  `define fp_inf(single, s) (single ? {32'hffff_ffff, s, 8'hff, 23'b0} : {s, 11'h7ff, 52'b0})
  `define fp_mkval(single, sign, v) (single ? {v[63:32], sign, v[30:0]}: {sign, v[62:0]})
  `define fp_quiet(single, v) v |= (single_i ? 64'b1 << 22 : 64'b1 << 51)

  `define FP_CQNAN(single) (single ? CQNAN_S : CQNAN_D)

  function automatic reg_t fnan2(reg_t op[2], fattr_t attr[2]);
    return attr[1].NAN ? op[1] : op[0];
  endfunction
  function automatic reg_t fnan3(reg_t op[3], fattr_t attr[3]);
    return attr[0].NAN ? op[0] : (attr[1].NAN ? op[1] : op[2]);
  endfunction
  function automatic reg_t fsnan2(reg_t op[2], fattr_t attr[2]);
    return attr[1].SNAN ? op[1] : op[0];
  endfunction
  function automatic reg_t fsnan3(reg_t op[3], fattr_t attr[3]);
    return attr[2].SNAN ? op[2] : (attr[0].SNAN ? op[0] : op[1]);
  endfunction

  function automatic funpack_t funpack(logic single, reg_t v, fattr_t a);
    funpack_t res;
    res = '0;
    res.sign = `fp_sign(single, v);
    if (a.SUBN) begin
      res.exp   = 12'd1;
      res.manti = `fp_subn_manti(single, v);
    end else if (a.ZERO) begin
      res.exp   = '0;
      res.manti = '0;
    end else begin
      res.exp   = `fp_exp(single, v, 12);
      res.manti = `fp_manti(single, v);
    end
    `LOGI($sformatf("s:%b e:%0d m:%h", res.sign, res.exp, res.manti));
    return res;
  endfunction

  function automatic logic frndup(logic G, R, S, L, sign, frm_e mode);
    logic rndup;
    unique case (mode)
      RNE: rndup = G & (R | S | L);
      RDN: rndup = sign & (G | R | S);
      RUP: rndup = (!sign) & (G | R | S);
      RMM: rndup = G;
      default: rndup = 0;
    endcase
    return rndup;
  endfunction

  function automatic logic check_file_exist(string name);
    int fd = $fopen(name, "r");
    if (fd != 0) begin
      $fclose(fd);
      return 1;
    end else begin
      return 0;
    end
  endfunction

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
  logic [4:0] r1, r2, r3;
  reg_t v1, v2, v3;
  modport master(output r1, r2, r3, input v1, v2, v3);
  modport slave(input r1, r2, r3, output v1, v2, v3);
endinterface

interface mmapingif;
  logic valid, ready, error;
  logic [2:0] rwx;
  addr_t va, pa;

  modport master(input ready, error, pa, output valid, rwx, va);
  modport slave(output ready, error, pa, input valid, rwx, va);
endinterface


//------------------------------
// top entry module (no args)
//------------------------------
module top ();
  logic clk, rst_n, intr, rtc;

  initial begin
    // $dumpfile("waveforms.vcd");
    // $dumpvars(0, top);
    $timeformat(-9, 3, "", 9);
    intr = 1'b0;
  end

  clkgen #(
    .COUNTER(18880000)
  ) clock (
    .clk(clk),
    .rst_n(rst_n),
    .rtc_o(rtc)
  );
  logic halt;

  soc soc1 (
    .clk(clk),
    .rst_n(rst_n),
    .halt_o(halt),
    .rtc_i(rtc),
    .intr_i(intr)
  );

  raptor raptor1 (
    .clk(clk),
    .rst_n(rst_n),
    .halt_i(halt),
    .intr_o(intr)
  );

endmodule

//-------------------------------------
// clock gen
//-------------------------------------
module clkgen #(
  parameter COUNTER = 10
) (
  output logic clk,
  output logic rst_n,
  output logic rtc_o
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
  always #20 rtc_o = ~rtc_o;
endmodule


//-------------------------------------
// soc include (pipeline 5 stages, mmu, csr, ...)
//-------------------------------------
module soc (
  input  logic clk,
  input  logic rst_n,
  input  logic rtc_i,
  input  logic intr_i,
  output logic halt_o
);

  logic stage_ready[6];
  logic btaken, ttaken;
  wb_src_e wb_src;
  reg_t wb_alu, wb_amo, wb_csr, wb_mem;
  stage_e stage, exc_stage;
  addr_t pc, btarget, ttarget;
  instr_t instr;
  id_t id_out;
  exception_t exc[6];

  memif master_ports[MASTER_CNT] ();
  memif slave_ports[SLAVE_CNT] ();
  regif rf ();

  import "DPI-C" function int elf_parse_mapping(
    input  string elf_path,
    output mmap_t mapping [3]
  );

  mmap_t maps[SLAVE_CNT] = '{default: 0};
  mmap_t elfmaps[3] = '{default: 0};
  int fd, ret;
  initial begin : mmaps
    string elf;
    maps = mapping;
    $value$plusargs("elf=%s", elf);
    if (check_file_exist(elf) == 1) begin
      ret = elf_parse_mapping(elf, elfmaps);
      `LOGI($sformatf("sections for %s", elf));
      for (int i = 0; i < 3; i++) begin
        maps[i] = elfmaps[i];
      end
      foreach (maps[i]) begin
        `LOGI($sformatf("maps[%0d] 0x%0h ~ 0x%0h", i, maps[i].BASE, maps[i].END));
      end
    end
  end

  xbar xbar1 (
    .clk(clk),
    .rst_n(rst_n),
    .mmapping(maps),
    .masters(master_ports),
    .slaves(slave_ports)
  );

  ifu ifu1 (
    .clk(clk),
    .rst_n(rst_n),
    .mif(master_ports[0].master),
    .mapif(imap.master),
    .valid(stage == STG_FETCH),
    .pc_i(pc),
    .instr_o(instr),
    .ready_o(stage_ready[0]),
    .exc_o(exc[1])
  );

  idu idu1 (
    .clk(clk),
    .rst_n(rst_n),
    .valid(stage == STG_DECODE),
    .instr_i(instr),
    .ready_o(stage_ready[1]),
    .priv_i(priv),
    .mstatus_i(mstatus),
    .exc_o(exc[2]),
    .id_o(id_out),
    .wb_src_o(wb_src),
    .rif(rf.master),
    .fif(fprif)
  );

  exu exu1 (
    .clk(clk),
    .rst_n(rst_n),
    .valid(stage == STG_EXEC),
    .ready_o(stage_ready[2]),
    .exc_o(exc[3]),
    .pc_i(pc),
    .id_i(id_out),
    .op_amo_i(amo_rd),
    .btarget_o(btarget),
    .btaken_o(btaken),
    .wb_o(wb_alu),
    .wb_amo_o(wb_amo),
    .mem_addr_o(mem_addr),
    .mem_wd_o(mem_wd),
    .amo_wd_o(amo_wd),
    .rif(rf.master),
    .fif(fprif.master)
  );

  regif fprif ();
  fflags_t fflags;
  reg_t wb_fpu2gpr;
  reg_t wb_fpu2fpr;
  logic [2:0] frm;
  fpu fpu1 (
    .clk(clk),
    .rst_n(rst_n),
    .valid(stage == STG_EXEC),
    .id_i(id_out),
    .op_i(id_out.fop),
    .single_i(id_out.single),
    .rm_i(id_out.frm == DYN ? frm : id_out.frm),
    .fstate_i(mstatus.FS),
    .rif(rf.master),
    .fif(fprif.master),
    .wb_gpr_o(wb_fpu2gpr),  // to rfu
    .wb_fpr_o(wb_fpu2fpr),  // to fpr
    .flags_o(fflags),  // to fcsr
    .ready_o(stage_ready[5])
  );

  fpr fpr1 (
    .clk(clk),
    .rst_n(rst_n),
    .valid(stage == STG_WB && id_out.fpr_write == 1),
    .rd_i(id_out.rd),
    .wb_src_i(wb_src),
    .wb_fpu_i(wb_fpu2fpr),
    .wb_mem_i(wb_mem),
    .rif(fprif.slave)
  );

  reg_t mem_wd;
  addr_t mem_addr;
  reg_t amo_wd, amo_rd;
  lsu lsu1 (
    .clk(clk),
    .rst_n(rst_n),
    .mif(master_ports[1].master),
    .mapif(dmap.master),
    .valid(stage == STG_MEM),
    .ready_o(stage_ready[3]),
    .exc_o(exc[4]),
    .ld_op_i(id_out.ld_op),
    .sd_op_i(id_out.sd_op),
    .amo_op_i(id_out.amo_op),
    .amo_valid_i(stage == STG_AMO),
    .addr_i(mem_addr),
    .amo_addr_i(rf.master.v1),
    .wd_i(mem_wd),
    .amo_wd_i(amo_wd),
    .rd_o(wb_mem),
    .amo_rd_o(amo_rd),
    .trap_i(ttaken)
  );

  rfu rfu1 (
    .clk(clk),
    .rst_n(rst_n),
    .valid(stage == STG_WB && id_out.reg_write == 1),
    .ready_o(stage_ready[4]),
    .rif(rf.slave),
    .wb_src_i(ttaken ? WB_SRC_NONE : wb_src),
    .rd_i(id_out.rd),
    .alu_i(wb_alu),
    .csr_i(wb_csr),
    .amo_i(wb_amo),
    .mem_i(wb_mem),
    .fpu_i(wb_fpu2gpr)
  );

  satp_t satp;
  mstatus_t mstatus;
  priviledge_e priv;
  logic tlb_invalid;
  logic exc_fired;
  logic itimer, ipi, interrupted;
  logic halt;
  assign halt_o = halt;
  csr csr1 (
    .clk(clk),
    .rst_n(rst_n),
    .valid(stage == STG_EXEC),
    .commit_i(stage == STG_WB),
    .pc_i(pc),
    .instr_i(instr),
    .op_i(id_out.sys_op),
    .op1_i(id_out.op_s1 == OP_SRC_REG ? rf.master.v1 : {59'b0, id_out.csr_imm}),
    .which_i(id_out.csr),
    .wb_o(wb_csr),
    .satp_o(satp),
    .mstatus_o(mstatus),
    .priv_o(priv),
    .exc_fired_i(exc_fired),
    .exc_i(exc[0]),
    .exc_o(exc[5]),
    .trap_o(ttaken),
    .trap_target_o(ttarget),
    .tlb_invalid_o(tlb_invalid),
    .fflags_i(fflags),
    .frm_o(frm),
    .fpr_write_i(id_out.fpr_write),
    .time_i(timeval),
    .halt_o(halt),
    .irq_timer_i(itimer),
    .irq_ex_i(intr[0]),
    .interrupted_o(interrupted)
  );

  mmapingif imap (), dmap ();
  mmu mmu1 (
    .clk(clk),
    .rst_n(rst_n),
    .mstatus_i(mstatus),
    .priv_i(priv),
    .satp_i(satp),
    .tlb_invalid_i(tlb_invalid),
    .imapif(imap.slave),
    .dmapif(dmap.slave),
    .mif(master_ports[2].master)
  );

  // rom rom1 (
  //   .clk(clk),
  //   .rst_n(rst_n),
  //   .mif(slave_ports[0].slave)
  // );
  sram #(
    .CAPS_IN_BYTES(12 * KB)
  ) sram1 (
    .clk(clk),
    .rst_n(rst_n),
    .mif(slave_ports[0].slave)
  );

  scoreboard SB (
    .clk(clk),
    .rst_n(rst_n),
    .mif(slave_ports[1].slave)
  );

  sram #(
    .DATAONLY(1)
  ) sram2 (
    .clk(clk),
    .rst_n(rst_n),
    .mif(slave_ports[2].slave)
  );

  reg_t timeval;
  clint clint1 (
    .clk(clk),
    .rst_n(rst_n),
    .mif(slave_ports[3]),
    .rtc_i(rtc_i),
    .time_o(timeval),
    .timer_o(itimer),
    .ipi_o(ipi)
  );

  logic [15:0] intr_src;
  logic [1:0] intr;
  plic plic1 (
    .clk(clk),
    .rst_n(rst_n),
    .src_i(intr_src),
    .intr_o(intr),
    .mif(slave_ports[4])
  );

  igen igen1 (
    .clk(clk),
    .rst_n(rst_n),
    .intr_o(intr_src[2]),
    .mif(slave_ports[5])
  );

  uart8250 uart1 (
    .clk(clk),
    .rst_n(rst_n),
    .mif(slave_ports[6]),
    .intr_o(intr_src[1])
  );


  // copy exception to exc[0]
  int idx;
  always_comb begin
    exc[0].fired = 0;
    idx = int'(exc_stage);
    if (exc_stage != STG_IDLE) begin
      if (exc_stage == STG_EXEC) begin
        exc[0] = exc[5].fired ? exc[5] : exc[idx];
      end else begin
        exc[0] = exc[idx];
      end
      `LOGE($sformatf("exc: stage:%0d cause:0x%0h", exc_stage, exc[idx].cause));
    end
    if (stage == STG_WB && exc[0].fired) begin
      exc_fired = 1;
    end else begin
      exc_fired = 0;
    end
  end

  logic enter_amo;
  always_comb begin
    enter_amo = !(id_out.amo_op inside {AMO_NONE, AMO_LR, AMO_LRW, AMO_SC, AMO_SCW});
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
          if (stage_ready[0]) begin
            // $display("%0h", pc);
            if (exc[1].fired) begin
              stage <= STG_WB;
              exc_stage <= stage;
            end else begin
              stage <= STG_DECODE;
            end
          end
        end
        STG_DECODE: begin
          if (stage_ready[1]) begin
            stage <= STG_EXEC;
            if (exc[2].fired) begin
              stage <= STG_WB;
              exc_stage <= stage;
            end else begin
              if (enter_amo) begin
                stage <= STG_AMO;
              end else begin
                stage <= STG_EXEC;
              end
            end
          end
        end
        STG_AMO: begin
          if (stage_ready[3]) begin
            if (exc[4].fired) begin
              stage <= STG_EXEC;
              exc_stage <= stage;
            end else begin
              stage <= STG_EXEC;
            end
          end
        end
        STG_EXEC: begin
          if (stage_ready[2] & stage_ready[5]) begin
            if (exc[5].fired || exc[3].fired) begin
              exc_stage <= STG_EXEC;
              stage <= STG_WB;
            end else begin
              stage <= STG_MEM;
            end
          end
        end
        STG_MEM: begin
          if (stage_ready[3]) begin
            if (exc[4].fired) begin
              stage <= STG_WB;
              exc_stage <= stage;
            end else begin
              stage <= STG_WB;
            end
          end
        end
        STG_WB: begin
          if (halt) begin
            `LOGW("WFI");
            if (interrupted) begin
              stage <= STG_FETCH;
              pc <= (ttaken ? ttarget : pc + (id_out.rvc ? 2 : 4));
            end
          end else begin
            if (exc_stage != STG_IDLE) begin
              `LOGE($sformatf("exc at stage: %0d cause:%0d", exc_stage, exc[0].cause));
              exc_stage <= STG_IDLE;
            end
            if (stage_ready[4]) begin
              if (ttaken) begin
                pc <= ttarget;
              end else if (btaken) begin
                pc <= btarget;
              end else begin
                pc <= pc + (id_out.rvc ? 2 : 4);
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
module xbar (
  input logic clk,
  input logic rst_n,
  input mmap_t mmapping[SLAVE_CNT],
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
      assign mreq[m].dtype = masters[m].dtype;
      assign masters[m].ready = mrsp[m].ready;
      assign masters[m].error = mrsp[m].error;
      assign masters[m].rd = mrsp[m].rd;
    end

    for (genvar s = 0; s < SLAVE_CNT; s++) begin : slave_flatten
      assign slaves[s].valid = sreq[s].valid;
      assign slaves[s].addr = sreq[s].addr;
      assign slaves[s].we = sreq[s].we;
      assign slaves[s].wd = sreq[s].wd;
      assign slaves[s].dtype = sreq[s].dtype;
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
      foreach (mmapping[i]) begin
        if (addr >= mmapping[i].BASE && addr <= mmapping[i].END) begin
          slave_selected = i;
          addr = addr - mmapping[i].BASE;
          break;
        end
      end
    end
  end

  // connect master and slave on both req and resp
  always_comb begin
    foreach (sreq[i]) sreq[i].valid = '0;
    foreach (mrsp[i]) mrsp[i].ready = '0;

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
  mmapingif.master mapif,

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
    FETCH1,
    FETCH2
  } state_e;
  state_e state;

  mcause_e ecause;
  logic complete;

  always_comb begin
    ready_o  = 0;
    ecause   = EXC_NONE;
    complete = 0;

    if (valid && pc_i[0] != 0) begin
      `LOGI($sformatf("pc misaligned:0x%0h", pc_i));
      ecause  = EXC_INSTR_ADDR_MISALIGNED;
      ready_o = 1;
    end

    if (valid && state == MAPPING && mapif.ready) begin
      if (mapif.error) begin
        `LOGE($sformatf("instr page fault: 0x%0h", pc_i));
        ecause  = EXC_INSTR_PAGE_FAULT;
        ready_o = 1;
      end
    end

    if (valid && mif.ready) begin
      complete = mif.rd[1:0] == 2'b11 && mif.dtype == U32;
      complete = complete | mif.rd[1:0] != 2'b11;
      if (state == FETCH2 || (state == FETCH1 && complete)) begin
        ready_o = 1;
        if (mif.error) begin
          `LOGE($sformatf("load instr error: va:0x%0h pa:0x%0h", pc_i, mapif.pa));
          ecause = EXC_INSTR_ACCESS_FAULT;
        end
      end
    end
  end

  // handle exception
  always_comb begin
    exc_o.fired = 0;
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
              mapif.valid <= 1;
              mapif.va    <= pc_i;
              state       <= MAPPING;
            end
          end
          MAPPING: begin
            if (mapif.ready) begin
              mapif.valid <= 0;
              if (!mapif.error) begin
                `LOGI($sformatf("pa:0x%0h va:0x%0h", mapif.pa, mapif.va));
                mif.addr <= mapif.pa;
                if (mapif.pa[11:0] == 12'hffe) begin
                  mif.dtype <= U16;
                end else begin
                  mif.dtype <= U32;
                end
                mif.we    <= 0;
                mif.valid <= 1;
                state     <= FETCH1;
              end else begin
                state <= IDLE;
              end
            end
          end
          FETCH1: begin
            if (mif.ready) begin
              `LOGI($sformatf("pc=0x%0h, instr=0x%h", pc_i, mif.rd[31:0]));
              if (mif.rd[1:0] == 2'b11 && mif.dtype != U32) begin
                instr_o[15:0] <= mif.rd[15:0];
                mif.addr      <= mif.addr + 2;
                mif.dtype     <= U16;
                mif.valid     <= 1;
                state         <= FETCH2;
              end else begin
                mif.valid <= 0;
                instr_o <= mif.rd[31:0];
                state <= IDLE;
              end
            end
          end
          FETCH2: begin
            if (mif.ready) begin
              `LOGI($sformatf("pc=0x%0h, instr=0x%h", pc_i, mif.rd[31:0]));
              mif.valid      <= 0;
              instr_o[31:16] <= mif.rd[15:0];
              state          <= IDLE;
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
  input mstatus_t mstatus_i,
  input priviledge_e priv_i,

  // decode output
  regif.master rif,
  regif.master fif,
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
    exc_o.fired = 0;
    if (ecause != EXC_NONE) begin
      exc_o.fired = 1;
      exc_o.cause = ecause;
      exc_o.eval  = {32'b0, instr_i};
      if (ecause >= EXC_ECALL_U_MODE && ecause <= EXC_ECALL_M_MODE) begin
        exc_o.eval = 0;
      end
    end
  end

  function automatic mcause_e mcause_of_ecall(priviledge_e priv);
    unique case (priv)
      M_USER:  return EXC_ECALL_U_MODE;
      M_SUPER: return EXC_ECALL_S_MODE;
      default: return EXC_ECALL_M_MODE;
    endcase
  endfunction

  // instr decoding
  logic [2:0] f3;
  logic [6:0] f7;
  logic [9:0] fc;
  logic [7:0] amo;
  imm_type_e imm_type;
  logic [4:0] code;

  // fpu related
  logic [4:0] f5;
  logic [2:0] rm;
  logic [1:0] fmt;

  always_comb begin : decode
    ecause = EXC_NONE;
    if (valid) begin
      if (instr_i[1:0] == 2'b11) begin
        id_o        = '0;
        wb_src_o    = WB_SRC_NONE;
        id_o.opcode = opcode_e'(instr_i[6:0]);
        id_o.rs1    = instr_i[19:15];
        id_o.rs2    = instr_i[24:20];
        id_o.rd     = instr_i[11:7];
        f3          = instr_i[14:12];
        f5          = instr_i[31:27];
        f7          = instr_i[31:25];
        rm          = instr_i[14:12];
        fmt         = instr_i[26:25];
        fc          = {f7, f3};
        amo         = {f7[6:2], f3};
        rif.r1      = instr_i[19:15];
        rif.r2      = instr_i[24:20];

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
            rif.r1         = 0;
            id_o.op_s1     = OP_SRC_REG;
            id_o.op_s2     = OP_SRC_IMM;
          end

          OPCODE_SYSTEM: begin
            `LOGI("SYSTEM");
            id_o.op_s1 = OP_SRC_REG;
            unique case (f3)
              3'b000: begin
                unique case (instr_i[31:20])
                  12'h000: begin
                    `LOGI($sformatf("ECALL %0d", priv_i));
                    id_o.sys_op = SYS_ECALL;
                    ecause = mcause_of_ecall(priv_i);
                  end
                  12'h001: begin
                    `LOGI("EBREAK");
                    id_o.sys_op = SYS_EBREAK;
                    ecause = EXC_BREAKPOINT;
                  end
                  12'h002: id_o.sys_op = SYS_URET;
                  12'h102: begin
                    id_o.sys_op = SYS_SRET;
                    if (priv_i < M_SUPER) ecause = EXC_ILLEGAL_INSTRUCTION;
                    if (mstatus_i.TSR) ecause = EXC_ILLEGAL_INSTRUCTION;
                  end
                  12'h105: begin
                    id_o.sys_op = SYS_WFI;
                    if (priv_i == M_USER && mstatus_i.TW == 1) begin
                      ecause = EXC_ILLEGAL_INSTRUCTION;
                    end
                  end
                  12'h302: begin
                    id_o.sys_op = SYS_MRET;
                    if (priv_i < M_MACHINE) ecause = EXC_ILLEGAL_INSTRUCTION;
                  end
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
                id_o.op_s1     = OP_SRC_IMM;
                id_o.sys_op    = SYS_CSRRWI;
                wb_src_o       = WB_SRC_CSR;
                id_o.csr       = instr_i[31:20];
                id_o.csr_imm   = id_o.rs1;
              end

              3'b110: begin  // CSRRSI
                id_o.reg_write = 1;
                id_o.op_s1     = OP_SRC_IMM;
                id_o.sys_op    = SYS_CSRRSI;
                wb_src_o       = WB_SRC_CSR;
                id_o.csr       = instr_i[31:20];
                id_o.csr_imm   = id_o.rs1;
              end

              3'b111: begin  // CSRRCI
                id_o.reg_write = 1;
                id_o.op_s1     = OP_SRC_IMM;
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
            unique case (amo)
              8'b00010010: begin
                wb_src_o    = WB_SRC_MEM;
                id_o.amo_op = AMO_LRW;
                id_o.ld_op  = LD_LW;
              end
              8'b00011010: begin
                wb_src_o    = WB_SRC_MEM;
                id_o.amo_op = AMO_SCW;
                id_o.sd_op  = SD_SW;
              end
              8'b00010011: begin
                wb_src_o    = WB_SRC_MEM;
                id_o.amo_op = AMO_LR;
                id_o.ld_op  = LD_LD;
              end
              8'b00011011: begin
                wb_src_o    = WB_SRC_MEM;
                id_o.amo_op = AMO_SC;
                id_o.sd_op  = SD_SD;
              end
              8'b00001010: begin
                id_o.amo_op = AMO_SWAPW;
                id_o.ld_op  = LD_LW;
                id_o.sd_op  = SD_SW;
              end
              8'b00000010: begin
                id_o.amo_op = AMO_ADDW;
                id_o.alu_op = ALU_ADDW;
                id_o.ld_op  = LD_LW;
                id_o.sd_op  = SD_SW;
              end
              8'b00100010: begin
                id_o.amo_op = AMO_XORW;
                id_o.alu_op = ALU_XOR;
                id_o.ld_op  = LD_LW;
                id_o.sd_op  = SD_SW;
              end
              8'b01000010: begin
                id_o.amo_op = AMO_ORW;
                id_o.alu_op = ALU_OR;
                id_o.ld_op  = LD_LW;
                id_o.sd_op  = SD_SW;
              end
              8'b01100010: begin
                id_o.amo_op = AMO_ANDW;
                id_o.alu_op = ALU_AND;
                id_o.ld_op  = LD_LW;
                id_o.sd_op  = SD_SW;
              end
              8'b10000010: begin
                id_o.amo_op = AMO_MINW;
                id_o.alu_op = ALU_SLT;
                id_o.ld_op  = LD_LW;
                id_o.sd_op  = SD_SW;
              end
              8'b10100010: begin
                id_o.amo_op = AMO_MAXW;
                id_o.alu_op = ALU_SLT;
                id_o.ld_op  = LD_LW;
                id_o.sd_op  = SD_SW;
              end
              8'b11000010: begin
                id_o.amo_op = AMO_MINUW;
                id_o.alu_op = ALU_SLTU;
                id_o.ld_op  = LD_LW;
                id_o.sd_op  = SD_SW;
              end
              8'b11100010: begin
                id_o.amo_op = AMO_MAXUW;
                id_o.alu_op = ALU_SLTU;
                id_o.ld_op  = LD_LW;
                id_o.sd_op  = SD_SW;
              end
              8'b00001011: begin
                id_o.amo_op = AMO_SWAP;
                id_o.ld_op  = LD_LD;
                id_o.sd_op  = SD_SD;
              end
              8'b00000011: begin
                id_o.amo_op = AMO_ADD;
                id_o.alu_op = ALU_ADD;
                id_o.ld_op  = LD_LD;
                id_o.sd_op  = SD_SD;
              end
              8'b00100011: begin
                id_o.amo_op = AMO_XOR;
                id_o.alu_op = ALU_XOR;
                id_o.ld_op  = LD_LD;
                id_o.sd_op  = SD_SD;
              end
              8'b01000011: begin
                id_o.amo_op = AMO_OR;
                id_o.alu_op = ALU_OR;
                id_o.ld_op  = LD_LD;
                id_o.sd_op  = SD_SD;
              end
              8'b01100011: begin
                id_o.amo_op = AMO_AND;
                id_o.alu_op = ALU_AND;
                id_o.ld_op  = LD_LD;
                id_o.sd_op  = SD_SD;
              end
              8'b10000011: begin
                id_o.amo_op = AMO_MIN;
                id_o.alu_op = ALU_SLT;
                id_o.ld_op  = LD_LD;
                id_o.sd_op  = SD_SD;
              end
              8'b10100011: begin
                id_o.amo_op = AMO_MAX;
                id_o.alu_op = ALU_SLT;
                id_o.ld_op  = LD_LD;
                id_o.sd_op  = SD_SD;
              end
              8'b11000011: begin
                id_o.amo_op = AMO_MINU;
                id_o.alu_op = ALU_SLTU;
                id_o.ld_op  = LD_LD;
                id_o.sd_op  = SD_SD;
              end
              8'b11100011: begin
                id_o.amo_op = AMO_MAXU;
                id_o.alu_op = ALU_SLTU;
                id_o.ld_op  = LD_LD;
                id_o.sd_op  = SD_SD;
              end
              default: begin
                id_o.amo_op = AMO_NONE;
                `LOGE($sformatf("unknown AMO f7:%b f3:%b", f7, f3));
              end
            endcase
          end

          // fload point instruction
          OPCODE_FP_LOAD: begin
            `LOGI("FP_LOAD");
            id_o.fpr_write = 1;
            wb_src_o = WB_SRC_MEM;
            imm_type = IMM_I;
            id_o.alu_op = ALU_ADD;
            id_o.op_s1 = OP_SRC_REG;
            id_o.op_s2 = OP_SRC_IMM;
            rif.r1 = instr_i[19:15];
            unique case (instr_i[14:12])
              3'b010: begin
                id_o.ld_op  = LD_LFW;
                id_o.single = 1;
              end
              3'b011: begin
                id_o.ld_op  = LD_LFD;
                id_o.single = 0;
              end
              default: ecause = EXC_ILLEGAL_INSTRUCTION;
            endcase
          end
          OPCODE_FP_STORE: begin
            `LOGI("FP_STORE");
            imm_type = IMM_S;
            id_o.alu_op = ALU_ADD;
            id_o.op_s1 = OP_SRC_REG;
            id_o.op_s2 = OP_SRC_IMM;
            rif.r1 = instr_i[19:15];
            fif.r2 = instr_i[24:20];
            unique case (instr_i[14:12])
              3'b010: begin
                id_o.sd_op  = SD_SFW;
                id_o.single = 1;
              end
              3'b011: begin
                id_o.sd_op  = SD_SFD;
                id_o.single = 0;
              end
              default: ecause = EXC_ILLEGAL_INSTRUCTION;
            endcase
          end
          OPCODE_FMADD: begin
            `LOGI("FMADD");
            id_o.fpr_write = 1;
            wb_src_o = WB_SRC_FPU;
            id_o.rs3 = instr_i[31:27];
            id_o.frm = rm;
            id_o.fop = FOP_MADD;
            id_o.op_s1 = OP_SRC_FPR;
            id_o.op_s2 = OP_SRC_FPR;
            id_o.op_s3 = OP_SRC_FPR;
            fif.r1 = instr_i[19:15];
            fif.r2 = instr_i[24:20];
            fif.r3 = instr_i[31:27];
            unique case (fmt)
              2'b00:   id_o.single = 1;
              2'b01:   id_o.single = 0;
              default: ecause = EXC_ILLEGAL_INSTRUCTION;
            endcase
          end
          OPCODE_FMSUB: begin
            `LOGI("FMSUB");
            id_o.fpr_write = 1;
            wb_src_o = WB_SRC_FPU;
            id_o.rs3 = instr_i[31:27];
            id_o.frm = rm;
            id_o.fop = FOP_MSUB;
            id_o.op_s1 = OP_SRC_FPR;
            id_o.op_s2 = OP_SRC_FPR;
            id_o.op_s3 = OP_SRC_FPR;
            fif.r1 = instr_i[19:15];
            fif.r2 = instr_i[24:20];
            fif.r3 = instr_i[31:27];
            unique case (fmt)
              2'b00:   id_o.single = 1;
              2'b01:   id_o.single = 0;
              default: ecause = EXC_ILLEGAL_INSTRUCTION;
            endcase
          end
          OPCODE_FNMADD: begin
            `LOGI("FNMADD");
            id_o.fpr_write = 1;
            wb_src_o = WB_SRC_FPU;
            id_o.rs3 = instr_i[31:27];
            id_o.frm = rm;
            id_o.fop = FOP_NMADD;
            id_o.op_s1 = OP_SRC_FPR;
            id_o.op_s2 = OP_SRC_FPR;
            id_o.op_s3 = OP_SRC_FPR;
            fif.r1 = instr_i[19:15];
            fif.r2 = instr_i[24:20];
            fif.r3 = instr_i[31:27];
            unique case (fmt)
              2'b00:   id_o.single = 1;
              2'b01:   id_o.single = 0;
              default: ecause = EXC_ILLEGAL_INSTRUCTION;
            endcase
          end
          OPCODE_FNMSUB: begin
            `LOGI("FNMSUB");
            id_o.fpr_write = 1;
            wb_src_o = WB_SRC_FPU;
            id_o.rs3 = instr_i[31:27];
            id_o.frm = rm;
            id_o.fop = FOP_NMSUB;
            id_o.op_s1 = OP_SRC_FPR;
            id_o.op_s2 = OP_SRC_FPR;
            id_o.op_s3 = OP_SRC_FPR;
            fif.r1 = instr_i[19:15];
            fif.r2 = instr_i[24:20];
            fif.r3 = instr_i[31:27];
            unique case (fmt)
              2'b00:   id_o.single = 1;
              2'b01:   id_o.single = 0;
              default: ecause = EXC_ILLEGAL_INSTRUCTION;
            endcase
          end
          OPCODE_FP_OP: begin
            `LOGI("FP_OP");
            id_o.frm = rm;
            fif.r1 = instr_i[19:15];
            fif.r2 = instr_i[24:20];
            id_o.op_s1 = OP_SRC_FPR;
            id_o.op_s2 = OP_SRC_FPR;
            id_o.fpr_write = 1;
            wb_src_o = WB_SRC_FPU;
            unique case (fmt)
              2'b00:   id_o.single = 1;
              2'b01:   id_o.single = 0;
              default: ecause = EXC_ILLEGAL_INSTRUCTION;
            endcase

            unique case (f5)
              5'b00000: id_o.fop = FOP_ADD;
              5'b00001: id_o.fop = FOP_SUB;
              5'b00010: id_o.fop = FOP_MUL;
              5'b00011: id_o.fop = FOP_DIV;
              5'b01011: begin
                id_o.fop   = FOP_SQRT;
                id_o.op_s2 = OP_SRC_NONE;
              end
              5'b00100: begin
                unique case (rm)
                  3'b000:  id_o.fop = FOP_SGNJ;
                  3'b001:  id_o.fop = FOP_SGNJN;
                  3'b010:  id_o.fop = FOP_SGNJX;
                  default: ecause = EXC_ILLEGAL_INSTRUCTION;
                endcase
              end
              5'b00101: begin  // min/max
                unique case (rm)
                  3'b000:  id_o.fop = FOP_MIN;
                  3'b001:  id_o.fop = FOP_MAX;
                  default: ecause = EXC_ILLEGAL_INSTRUCTION;
                endcase
              end
              5'b11000: begin  // fpr(single/double) -> gpr((U)int)
                id_o.fpr_write = 0;
                id_o.reg_write = 1;
                id_o.op_s2 = OP_SRC_NONE;
                unique case (instr_i[24:20])
                  5'b00000: id_o.fop = FOP_CVT_W_F;  // ->s32
                  5'b00001: id_o.fop = FOP_CVT_WU_F;  // ->u32
                  5'b00010: id_o.fop = FOP_CVT_L_F;  // ->s64
                  5'b00011: id_o.fop = FOP_CVT_LU_F;  // ->u64
                  default:  ecause = EXC_ILLEGAL_INSTRUCTION;
                endcase
              end
              5'b11010: begin  // gpr (U)int -> single / double
                rif.r1 = instr_i[19:15];
                id_o.op_s2 = OP_SRC_REG;
                id_o.op_s2 = OP_SRC_NONE;
                unique case (instr_i[24:20])
                  5'b00000: id_o.fop = FOP_CVT_F_W;
                  5'b00001: id_o.fop = FOP_CVT_F_WU;
                  5'b00010: id_o.fop = FOP_CVT_F_L;
                  5'b00011: id_o.fop = FOP_CVT_F_LU;
                  default:  ecause = EXC_ILLEGAL_INSTRUCTION;
                endcase
              end
              5'b01000: begin  // float <-> double
                id_o.op_s2 = OP_SRC_NONE;
                unique case (instr_i[24:20])
                  5'b00000: begin
                    id_o.fop = FOP_CVT_D_S;
                    id_o.single = 1;
                  end
                  5'b00001: begin
                    id_o.fop = FOP_CVT_S_D;
                    id_o.single = 0;
                  end
                  default: ecause = EXC_ILLEGAL_INSTRUCTION;
                endcase
              end
              5'b11100: begin  // move fpr to gpr
                id_o.fpr_write = 0;
                id_o.reg_write = 1;
                id_o.op_s2 = OP_SRC_NONE;
                unique case (rm)
                  3'b000:  id_o.fop = FOP_MV_X_F;
                  3'b001:  id_o.fop = FOP_CLASS;  // fclass.s
                  default: ecause = EXC_ILLEGAL_INSTRUCTION;
                endcase
              end
              5'b11110: begin  // move gpr to fpr
                unique case (rm)
                  3'b000: begin
                    rif.r1 = instr_i[19:15];
                    id_o.op_s1 = OP_SRC_REG;
                    id_o.op_s2 = OP_SRC_NONE;
                    id_o.fop = FOP_MV_F_X;
                  end
                  3'b001: begin
                    id_o.fpr_write = 0;
                    id_o.reg_write = 1;
                    id_o.op_s2 = OP_SRC_NONE;
                    id_o.fop = FOP_CLASS;  // fclass.d
                  end
                  default: ecause = EXC_ILLEGAL_INSTRUCTION;
                endcase
              end
              5'b10100: begin  // fcmp
                id_o.fpr_write = 0;
                id_o.reg_write = 1;
                unique case (instr_i[14:12])
                  3'b000:  id_o.fop = FOP_CMP_LE;
                  3'b001:  id_o.fop = FOP_CMP_LT;
                  3'b010:  id_o.fop = FOP_CMP_EQ;
                  default: ecause = EXC_ILLEGAL_INSTRUCTION;
                endcase
              end
              default:  ecause = EXC_ILLEGAL_INSTRUCTION;
            endcase
          end
          OPCODE_FENCE: begin
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
      end else begin
        // C extension
        id_o     = '0;
        id_o.rvc = 1;
        wb_src_o = WB_SRC_NONE;
        code     = {instr_i[1:0], instr_i[15:13]};
        unique case (code)
          //----------------
          // Quadrant 0
          //----------------

          // C.ADDI4SPN : x[rd] = x[sp] + imm
          5'b00000: begin
            if (instr_i[15:0] == 16'h00) begin
              ecause = EXC_ILLEGAL_INSTRUCTION;
            end else begin
              `LOGI("C.ADDI4SPN");
              id_o.opcode    = OPCODE_OP_IMM;
              id_o.imm       = {54'b0, instr_i[10:7], instr_i[12:11], instr_i[5], instr_i[6], 2'b00};
              id_o.rd        = {2'b01, instr_i[4:2]};
              id_o.rs1       = 5'd2;
              rif.r1         = 5'd2;
              id_o.alu_op    = ALU_ADD;
              id_o.reg_write = 1'b1;
              id_o.op_s1     = OP_SRC_REG;
              id_o.op_s2     = OP_SRC_IMM;
              wb_src_o       = WB_SRC_ALU;
            end
          end

          // C.LW
          5'b00010: begin
            `LOGI("C.LW");
            id_o.opcode    = OPCODE_LOAD;
            id_o.imm       = {57'b0, instr_i[5], instr_i[12], instr_i[11], instr_i[10], instr_i[6], 2'b00};
            id_o.rd        = {2'b01, instr_i[4:2]};
            id_o.rs1       = {2'b01, instr_i[9:7]};
            rif.r1         = {2'b01, instr_i[9:7]};
            id_o.alu_op    = ALU_ADD;
            id_o.ld_op     = LD_LW;
            id_o.reg_write = 1'b1;
            id_o.op_s1     = OP_SRC_REG;
            id_o.op_s2     = OP_SRC_IMM;
            wb_src_o       = WB_SRC_MEM;
          end

          // C.LD
          5'b00011: begin
            `LOGI("C.LD");
            id_o.opcode    = OPCODE_LOAD;
            id_o.imm       = {56'b0, instr_i[6], instr_i[5], instr_i[12], instr_i[11], instr_i[10], 3'b000};
            id_o.rd        = {2'b01, instr_i[4:2]};
            id_o.rs1       = {2'b01, instr_i[9:7]};
            rif.r1         = {2'b01, instr_i[9:7]};
            id_o.alu_op    = ALU_ADD;
            id_o.ld_op     = LD_LD;
            id_o.reg_write = 1'b1;
            id_o.op_s1     = OP_SRC_REG;
            id_o.op_s2     = OP_SRC_IMM;
            wb_src_o       = WB_SRC_MEM;
          end

          // C.SW
          5'b00110: begin
            `LOGI("C.SW");
            id_o.opcode    = OPCODE_STORE;
            id_o.imm       = {57'b0, instr_i[5], instr_i[12], instr_i[11], instr_i[10], instr_i[6], 2'b00};
            id_o.rs1       = {2'b01, instr_i[9:7]};
            id_o.rs2       = {2'b01, instr_i[4:2]};
            rif.r1         = {2'b01, instr_i[9:7]};
            rif.r2         = {2'b01, instr_i[4:2]};
            id_o.alu_op    = ALU_ADD;
            id_o.sd_op     = SD_SW;
            id_o.reg_write = 1'b0;
            id_o.op_s1     = OP_SRC_REG;
            id_o.op_s2     = OP_SRC_IMM;
            wb_src_o       = WB_SRC_NONE;
          end

          // C.SD
          5'b00111: begin
            `LOGI("C.SD");
            id_o.opcode    = OPCODE_STORE;
            id_o.imm       = {56'b0, instr_i[6], instr_i[5], instr_i[12], instr_i[11], instr_i[10], 3'b000};
            id_o.rs1       = {2'b01, instr_i[9:7]};
            id_o.rs2       = {2'b01, instr_i[4:2]};
            rif.r1         = {2'b01, instr_i[9:7]};
            rif.r2         = {2'b01, instr_i[4:2]};
            id_o.alu_op    = ALU_ADD;
            id_o.sd_op     = SD_SD;
            id_o.reg_write = 1'b0;
            id_o.op_s1     = OP_SRC_REG;
            id_o.op_s2     = OP_SRC_IMM;
            wb_src_o       = WB_SRC_NONE;
          end

          // TODO C.FLD
          5'b00001: begin
            `LOGI("C.FLD");
            id_o.opcode    = OPCODE_FP_LOAD;
            id_o.imm       = {56'b0, instr_i[6], instr_i[5], instr_i[12], instr_i[11], instr_i[10], 3'b000};
            id_o.rd        = {2'b01, instr_i[4:2]};
            id_o.rs1       = {2'b01, instr_i[9:7]};
            rif.r1         = {2'b01, instr_i[9:7]};
            id_o.alu_op    = ALU_ADD;
            id_o.reg_write = 1'b0;
            id_o.fpr_write = 1'b1;
            id_o.ld_op     = LD_LFD;
            id_o.op_s1     = OP_SRC_REG;
            id_o.op_s2     = OP_SRC_IMM;
            wb_src_o       = WB_SRC_MEM;
          end

          // C.FSD TODO
          5'b00101: begin
            `LOGI("C.FSD");
            id_o.opcode    = OPCODE_FP_STORE;
            id_o.imm       = {56'b0, instr_i[6], instr_i[5], instr_i[12], instr_i[11], instr_i[10], 3'b000};
            id_o.rs1       = {2'b01, instr_i[9:7]};
            id_o.rs2       = {2'b01, instr_i[4:2]};
            rif.r1         = {2'b01, instr_i[9:7]};
            fif.r2         = {2'b01, instr_i[4:2]};
            id_o.alu_op    = ALU_ADD;
            id_o.sd_op     = SD_SFD;
            id_o.reg_write = 1'b0;
            id_o.fpr_write = 1'b0;
            id_o.op_s1     = OP_SRC_REG;
            id_o.op_s2     = OP_SRC_IMM;
            wb_src_o       = WB_SRC_NONE;
          end

          //-------------------------
          // Quadrant 1
          //-------------------------

          // C.ADDI / C.NOP
          5'b01000: begin
            id_o.opcode    = OPCODE_OP_IMM;
            id_o.imm       = {{59{instr_i[12]}}, instr_i[6:2]};
            id_o.rd        = instr_i[11:7];
            id_o.rs1       = instr_i[11:7];
            rif.r1         = instr_i[11:7];
            id_o.alu_op    = ALU_ADD;
            id_o.reg_write = 1'b1;
            id_o.op_s1     = OP_SRC_REG;
            id_o.op_s2     = OP_SRC_IMM;
            wb_src_o       = WB_SRC_ALU;
            if (instr_i[11:7] == 5'b0) begin
              `LOGI("C.NOP");
            end else begin
              `LOGI("C.ADDI");
            end
          end

          // C.ADDIW
          5'b01001: begin
            if (instr_i[11:7] != 5'b0) begin
              `LOGI("C.ADDIW");
              id_o.opcode    = OPCODE_OP_IMM_32;
              id_o.imm       = {{59{instr_i[12]}}, instr_i[6:2]};
              id_o.rd        = instr_i[11:7];
              id_o.rs1       = instr_i[11:7];
              rif.r1         = instr_i[11:7];
              id_o.alu_op    = ALU_ADDW;
              id_o.reg_write = 1'b1;
              id_o.op_s1     = OP_SRC_REG;
              id_o.op_s2     = OP_SRC_IMM;
              wb_src_o       = WB_SRC_ALU;
            end else begin
              ecause = EXC_ILLEGAL_INSTRUCTION;
            end
          end

          // C.LI
          5'b01010: begin
            `LOGI("C.LI");
            id_o.opcode    = OPCODE_OP_IMM;
            id_o.imm       = {{59{instr_i[12]}}, instr_i[6:2]};
            id_o.rd        = instr_i[11:7];
            id_o.rs1       = 5'd0;
            rif.r1         = 5'd0;
            id_o.alu_op    = ALU_ADD;
            id_o.reg_write = 1'b1;
            id_o.op_s1     = OP_SRC_REG;
            id_o.op_s2     = OP_SRC_IMM;
            wb_src_o       = WB_SRC_ALU;
          end

          // C.ADDI16SP
          5'b01011: begin
            if (instr_i[11:7] == 5'h02) begin
              id_o.opcode    = OPCODE_OP_IMM;
              id_o.imm       = {{55{instr_i[12]}}, instr_i[4], instr_i[3], instr_i[5], instr_i[2], instr_i[6], 4'b0};
              id_o.rd        = instr_i[11:7];
              id_o.rs1       = instr_i[11:7];
              rif.r1         = instr_i[11:7];
              id_o.alu_op    = ALU_ADD;
              id_o.reg_write = 1'b1;
              id_o.op_s1     = OP_SRC_REG;
              id_o.op_s2     = OP_SRC_IMM;
              wb_src_o       = WB_SRC_ALU;
              if (id_o.imm == 64'b0) begin
                ecause = EXC_ILLEGAL_INSTRUCTION;
              end else begin
                `LOGI("C.ADDI16SP");
              end
            end else begin
              `LOGI("C.LUI");
              id_o.opcode    = OPCODE_LUI;
              id_o.imm       = {{47{instr_i[12]}}, instr_i[6:2], 12'b0};
              id_o.rd        = instr_i[11:7];
              id_o.rs1       = 5'd0;
              rif.r1         = 5'd0;
              id_o.alu_op    = ALU_ADD;
              id_o.reg_write = 1'b1;
              id_o.op_s1     = OP_SRC_REG;
              id_o.op_s2     = OP_SRC_IMM;
              wb_src_o       = WB_SRC_ALU;
            end
          end

          // C.SRLI / C.SRAI / C.ANDI / CA
          5'b01100: begin
            if (instr_i[11:10] == 2'b00) begin
              `LOGI("C.SRLI");
              id_o.opcode    = OPCODE_OP_IMM;
              id_o.imm       = {58'b0, instr_i[12], instr_i[6:2]};
              id_o.rd        = {2'b01, instr_i[9:7]};
              id_o.rs1       = {2'b01, instr_i[9:7]};
              rif.r1         = {2'b01, instr_i[9:7]};
              id_o.alu_op    = ALU_SRL;
              id_o.reg_write = 1'b1;
              id_o.op_s1     = OP_SRC_REG;
              id_o.op_s2     = OP_SRC_IMM;
              wb_src_o       = WB_SRC_ALU;
            end else if (instr_i[11:10] == 2'b01) begin
              `LOGI("C.SRAI");
              id_o.opcode    = OPCODE_OP_IMM;
              id_o.imm       = {58'b0, instr_i[12], instr_i[6:2]};
              id_o.rd        = {2'b01, instr_i[9:7]};
              id_o.rs1       = {2'b01, instr_i[9:7]};
              rif.r1         = {2'b01, instr_i[9:7]};
              id_o.alu_op    = ALU_SRA;
              id_o.reg_write = 1'b1;
              id_o.op_s1     = OP_SRC_REG;
              id_o.op_s2     = OP_SRC_IMM;
              wb_src_o       = WB_SRC_ALU;
            end else if (instr_i[11:10] == 2'b10) begin
              `LOGI("C.ANDI");
              id_o.opcode    = OPCODE_OP_IMM;
              id_o.imm       = {{59{instr_i[12]}}, instr_i[6:2]};
              id_o.rd        = {2'b01, instr_i[9:7]};
              id_o.rs1       = {2'b01, instr_i[9:7]};
              rif.r1         = {2'b01, instr_i[9:7]};
              id_o.alu_op    = ALU_AND;
              id_o.reg_write = 1'b1;
              id_o.op_s1     = OP_SRC_REG;
              id_o.op_s2     = OP_SRC_IMM;
              wb_src_o       = WB_SRC_ALU;
            end else begin
              id_o.opcode    = OPCODE_OP;
              id_o.rd        = {2'b01, instr_i[9:7]};
              id_o.rs1       = {2'b01, instr_i[9:7]};
              id_o.rs2       = {2'b01, instr_i[4:2]};
              rif.r1         = {2'b01, instr_i[9:7]};
              rif.r2         = {2'b01, instr_i[4:2]};
              id_o.reg_write = 1'b1;
              id_o.op_s1     = OP_SRC_REG;
              id_o.op_s2     = OP_SRC_REG;
              wb_src_o       = WB_SRC_ALU;
              if (instr_i[12] == 0) begin
                case (instr_i[6:5])
                  2'b00: begin
                    `LOGI("C.SUB");
                    id_o.alu_op = ALU_SUB;
                  end
                  2'b01: begin
                    `LOGI("C.XOR");
                    id_o.alu_op = ALU_XOR;
                  end
                  2'b10: begin
                    `LOGI("C.OR");
                    id_o.alu_op = ALU_OR;
                  end
                  2'b11: begin
                    `LOGI("C.AND");
                    id_o.alu_op = ALU_AND;
                  end
                endcase
              end else begin
                id_o.opcode = OPCODE_OP_32;
                case (instr_i[6:5])
                  2'b00: begin
                    `LOGI("C.SUBW");
                    id_o.alu_op = ALU_SUBW;
                  end
                  2'b01: begin
                    `LOGI("C.ADDW");
                    id_o.alu_op = ALU_ADDW;
                  end
                  default: ecause = EXC_ILLEGAL_INSTRUCTION;
                endcase
              end
            end
          end

          // C.J
          5'b01101: begin
            `LOGI("C.J");
            id_o.opcode = OPCODE_JAL;
            id_o.imm = {
              {53{instr_i[12]}},
              instr_i[8],
              instr_i[10:9],
              instr_i[6],
              instr_i[7],
              instr_i[2],
              instr_i[11],
              instr_i[5:3],
              1'b0
            };
            id_o.rd = 5'd0;
            id_o.alu_op = ALU_ADD;
            id_o.reg_write = 1'b0;
            id_o.op_s1 = OP_SRC_PC;
            id_o.op_s2 = OP_SRC_IMM;
            wb_src_o = WB_SRC_ALU;
          end

          // C.BEQZ = beq rs1, x0, imm
          5'b01110: begin
            `LOGI("C.BEQZ");
            id_o.opcode    = OPCODE_BRANCH;
            id_o.imm       = {{56{instr_i[12]}}, instr_i[6:5], instr_i[2], instr_i[11:10], instr_i[4:3], 1'b0};
            id_o.rs1       = {2'b01, instr_i[9:7]};
            id_o.rs1       = 5'd0;
            rif.r1         = {2'b01, instr_i[9:7]};
            rif.r2         = 5'd0;
            id_o.alu_op    = ALU_BEQ;
            id_o.reg_write = 1'b0;
            id_o.op_s1     = OP_SRC_REG;
            id_o.op_s2     = OP_SRC_REG;
            wb_src_o       = WB_SRC_ALU;
          end

          // C.BNEZ bne rs1, x0, imm
          5'b01111: begin
            `LOGI("C.BNEZ");
            id_o.opcode    = OPCODE_BRANCH;
            id_o.imm       = {{56{instr_i[12]}}, instr_i[6:5], instr_i[2], instr_i[11:10], instr_i[4:3], 1'b0};
            id_o.rs1       = {2'b01, instr_i[9:7]};
            rif.r1         = {2'b01, instr_i[9:7]};
            id_o.rs2       = 5'd0;
            rif.r2         = 5'd0;
            id_o.alu_op    = ALU_BNE;
            id_o.reg_write = 1'b0;
            id_o.op_s1     = OP_SRC_REG;
            id_o.op_s2     = OP_SRC_REG;
            wb_src_o       = WB_SRC_ALU;
          end

          //-------------------------
          // Quadrant 2
          //-------------------------
          // C.SLLI
          5'b10000: begin
            `LOGI("C.SLLI");
            id_o.opcode    = OPCODE_OP_IMM;
            id_o.imm       = {58'b0, instr_i[12], instr_i[6:2]};
            id_o.rd        = instr_i[11:7];
            id_o.rs1       = instr_i[11:7];
            rif.r1         = instr_i[11:7];
            id_o.alu_op    = ALU_SLL;
            id_o.reg_write = 1'b1;
            id_o.op_s1     = OP_SRC_REG;
            id_o.op_s2     = OP_SRC_IMM;
            wb_src_o       = WB_SRC_ALU;
          end

          // TODO C.FLDSP
          5'b10001: begin
            `LOGI("C.FLDSP");
            id_o.opcode    = OPCODE_FP_LOAD;
            id_o.imm       = {55'b0, instr_i[4:2], instr_i[12], instr_i[6:5], 3'b000};
            id_o.rd        = instr_i[11:7];
            id_o.rs1       = 5'd2;
            rif.r1         = 5'd2;
            id_o.alu_op    = ALU_ADD;
            id_o.ld_op     = LD_LFD;
            id_o.reg_write = 1'b0;
            id_o.fpr_write = 1'b1;
            id_o.op_s1     = OP_SRC_REG;
            id_o.op_s2     = OP_SRC_IMM;
            wb_src_o       = WB_SRC_MEM;
          end

          // C.LWSP = lw rd, offset(x2)
          5'b10010: begin
            id_o.opcode    = OPCODE_LOAD;
            id_o.imm       = {56'b0, instr_i[3:2], instr_i[12], instr_i[6:4], 2'b00};
            id_o.rd        = instr_i[11:7];
            id_o.rs1       = 5'd2;
            rif.r1         = 5'd2;
            id_o.alu_op    = ALU_ADD;
            id_o.ld_op     = LD_LW;
            id_o.reg_write = 1'b1;
            id_o.op_s1     = OP_SRC_REG;
            id_o.op_s2     = OP_SRC_IMM;
            wb_src_o       = WB_SRC_MEM;
            if (id_o.rd == 5'd0) begin
              ecause = EXC_ILLEGAL_INSTRUCTION;
            end else begin
              `LOGI("C.LWSP");
            end
          end

          // C.LDSP
          5'b10011: begin
            id_o.opcode    = OPCODE_LOAD;
            id_o.imm       = {55'b0, instr_i[4:2], instr_i[12], instr_i[6:5], 3'b000};
            id_o.rd        = instr_i[11:7];
            id_o.rs1       = 5'd2;
            rif.r1         = 5'd2;
            id_o.alu_op    = ALU_ADD;
            id_o.ld_op     = LD_LD;
            id_o.reg_write = 1'b1;
            id_o.op_s1     = OP_SRC_REG;
            id_o.op_s2     = OP_SRC_IMM;
            wb_src_o       = WB_SRC_MEM;
            if (id_o.rd == 5'd0) begin
              ecause = EXC_ILLEGAL_INSTRUCTION;
            end else begin
              `LOGI("C.LDSP");
            end
          end

          // C.JR / C.JALR / C.EBREAK / C.MV
          5'b10100: begin
            if (instr_i[12] == 1'b0) begin
              if (instr_i[6:2] == 5'b0) begin
                // C.JR = jalr x0, 0(rs1)
                id_o.opcode    = OPCODE_JALR;
                id_o.rs1       = instr_i[11:7];
                rif.r1         = instr_i[11:7];
                id_o.alu_op    = ALU_ADD;
                id_o.reg_write = 1'b0;
                id_o.imm       = '0;
                id_o.op_s1     = OP_SRC_REG;
                id_o.op_s2     = OP_SRC_IMM;
                wb_src_o       = WB_SRC_ALU;
                if (id_o.rs1 == 5'd0) begin
                  ecause = EXC_ILLEGAL_INSTRUCTION;
                end else begin
                  `LOGI("C.JR");
                end
              end else begin
                // C.MV = add rd, rs2, x0
                `LOGI("C.MV");
                id_o.opcode    = OPCODE_OP;
                id_o.rd        = instr_i[11:7];
                id_o.rs2       = instr_i[6:2];
                rif.r2         = instr_i[6:2];
                rif.r1         = '0;
                id_o.alu_op    = ALU_ADD;
                id_o.reg_write = 1'b1;
                id_o.op_s1     = OP_SRC_REG;
                id_o.op_s2     = OP_SRC_REG;
                wb_src_o       = WB_SRC_ALU;
              end
            end else begin
              if (instr_i[6:2] == 5'b0) begin
                if (instr_i[11:7] == 5'b0) begin
                  `LOGI("C.EBREAK");
                  id_o.opcode = OPCODE_SYSTEM;
                  id_o.sys_op = SYS_EBREAK;
                  ecause      = EXC_BREAKPOINT;
                end else begin
                  // C.JALR = jalr x1, 0(rs1)
                  `LOGI("C.JAlR");
                  id_o.opcode    = OPCODE_JALR;
                  id_o.rd        = 5'd1;
                  id_o.rs1       = instr_i[11:7];
                  rif.r1         = instr_i[11:7];
                  id_o.alu_op    = ALU_ADD;
                  id_o.imm       = '0;
                  id_o.reg_write = 1'b1;
                  id_o.op_s1     = OP_SRC_REG;
                  id_o.op_s2     = OP_SRC_IMM;
                  wb_src_o       = WB_SRC_ALU;
                end
              end else begin
                // C.ADD = add rd, rd, rs2
                `LOGI("C.ADD");
                id_o.opcode    = OPCODE_OP;
                id_o.rd        = instr_i[11:7];
                id_o.rs1       = instr_i[11:7];
                id_o.rs2       = instr_i[6:2];
                rif.r1         = instr_i[11:7];
                rif.r2         = instr_i[6:2];
                id_o.alu_op    = ALU_ADD;
                id_o.reg_write = 1'b1;
                id_o.op_s1     = OP_SRC_REG;
                id_o.op_s2     = OP_SRC_REG;
                wb_src_o       = WB_SRC_ALU;
              end
            end
          end

          // C.SWSP = sw rs2, uimm(x2)
          5'b10110: begin
            `LOGI("C.SWSP");
            id_o.opcode    = OPCODE_STORE;
            id_o.imm       = {56'b0, instr_i[8:7], instr_i[12:9], 2'b00};
            id_o.rs1       = 5'd2;
            id_o.rs2       = instr_i[6:2];
            rif.r1         = 5'd2;
            rif.r2         = instr_i[6:2];
            id_o.alu_op    = ALU_ADD;
            id_o.sd_op     = SD_SW;
            id_o.reg_write = 1'b0;
            id_o.op_s1     = OP_SRC_REG;
            id_o.op_s2     = OP_SRC_IMM;
            wb_src_o       = WB_SRC_NONE;
          end

          // C.SDSP = sd rs2, uimm(x2)
          5'b10111: begin
            `LOGI("C.SDSP");
            id_o.opcode    = OPCODE_STORE;
            id_o.imm       = {55'b0, instr_i[9:7], instr_i[12:10], 3'b000};
            id_o.rs1       = 5'd2;
            id_o.rs2       = instr_i[6:2];
            rif.r1         = 5'd2;
            rif.r2         = instr_i[6:2];
            id_o.alu_op    = ALU_ADD;
            id_o.sd_op     = SD_SD;
            id_o.reg_write = 1'b0;
            id_o.op_s1     = OP_SRC_REG;
            id_o.op_s2     = OP_SRC_IMM;
            wb_src_o       = WB_SRC_NONE;
          end
          // C.FSDSP
          5'b10101: begin
            // TODO C.FSDSP = fsd  fs2, uimm(x2)
            `LOGI("C.FSDSP");
            id_o.opcode    = OPCODE_FP_STORE;
            id_o.imm       = {55'b0, instr_i[9:7], instr_i[12:10], 3'b000};
            id_o.rs1       = 5'd2;
            id_o.rs2       = instr_i[11:7];
            rif.r1         = 5'd2;
            fif.r2         = instr_i[11:7];
            id_o.alu_op    = ALU_ADD;
            id_o.sd_op     = SD_SFD;
            id_o.reg_write = 1'b0;
            id_o.op_s1     = OP_SRC_REG;
            id_o.op_s2     = OP_SRC_IMM;
            wb_src_o       = WB_SRC_NONE;
          end

          default: begin
            ecause = EXC_ILLEGAL_INSTRUCTION;
          end
        endcase
      end
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
  input  logic        clk,
  input  logic        rst_n,
  input  logic        valid,
  output logic        ready_o,
  output exception_t  exc_o,
  input  addr_t       pc_i,
  input  id_t         id_i,
  input  reg_t        op_amo_i,
  output addr_t       btarget_o,
  output logic        btaken_o,
  output reg_t        wb_o,
  output reg_t        wb_amo_o,
  output addr_t       mem_addr_o,
  output reg_t        mem_wd_o,
  output reg_t        amo_wd_o,
         regif.master rif,
         regif.master fif
);
  reg_t alu_result;
  reg_t wb, wb_amo, mem_wd, amo_wd;
  addr_t mem_addr, btarget;
  logic btaken;

  // handle register read and writeback
  always_comb begin
    wb     = '0;
    wb_amo = '0;
    exc_o  = '0;
    if (valid && id_i.reg_write) begin
      if (id_i.alu_op != ALU_NONE) begin
        wb = alu_result;
      end else if (id_i.mult_op != MULT_NONE) begin
        wb = mul_result;
      end else if (id_i.div_op != DIV_NONE) begin
        wb = div_result;
      end
      if (id_i.opcode inside {OPCODE_JAL, OPCODE_JALR}) begin
        if (id_i.rvc) begin
          wb = pc_i + 2;
        end else begin
          wb = pc_i + 4;
        end
      end
      if (id_i.amo_op != AMO_NONE) begin
        wb_amo = op_amo_i;
      end
    end
  end

  // prepare op1 and op2 for alu, mul, div
  reg_t op1, op2;
  always_comb begin
    op1 = 0;
    op2 = 0;
    if (valid) begin
      unique case (id_i.op_s1)
        OP_SRC_REG: op1 = rif.v1;
        OP_SRC_AMO: op1 = op_amo_i;
        default:    op1 = pc_i;
      endcase
      op2 = id_i.op_s2 == OP_SRC_REG ? rif.v2 : id_i.imm;
      if(id_i.alu_op != ALU_NONE || id_i.div_op != DIV_NONE || id_i.mult_op != MULT_NONE || id_i.amo_op != AMO_NONE) begin
        `LOGI($sformatf("a:%0d d:%0d m:%0d amo:%0d", id_i.alu_op, id_i.div_op, id_i.mult_op, id_i.amo_op));
      end
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

  amo amo1 (
    .valid(valid),
    .op_i(id_i.amo_op),
    .alu_result_i(alu_result),
    .op1_i(op1),
    .op2_i(op2),
    .result_o(amo_wd)
  );

  // handle branch and jump
  always_comb begin
    btarget = '0;
    btaken  = 0;
    ready_o = div_done;
    if (id_i.opcode == OPCODE_BRANCH) begin
      // meet branch
      if (alu_result[0]) begin
        btarget = pc_i + id_i.imm;
        btaken  = 1;
      end
    end
    if (id_i.opcode == OPCODE_JAL) begin
      // rd = PC+4; PC=PC+imm;
      btarget = alu_result;
      btaken  = 1;
    end else if (id_i.opcode == OPCODE_JALR) begin
      // rd = PC+4; PC = (rs1 + imm) & ~1 ;
      btarget = alu_result & ~1;
      btaken  = 1;
    end
  end

  // handle load and store
  always_comb begin
    mem_addr = '0;
    mem_wd   = '0;
    if (id_i.ld_op != LD_NONE || id_i.sd_op != SD_NONE) begin
      mem_addr = alu_result;
      if (id_i.sd_op != SD_NONE) begin
        if (id_i.sd_op inside {SD_SFW, SD_SFD}) begin
          mem_wd = fif.v2;
        end else begin
          mem_wd = rif.v2;
        end
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
    end else begin
      if (valid) begin
        btaken_o   <= btaken;
        btarget_o  <= btarget;
        wb_o       <= wb;
        wb_amo_o   <= wb_amo;
        mem_addr_o <= mem_addr;
        mem_wd_o   <= mem_wd;
        amo_wd_o   <= amo_wd;
      end
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
      `LOGI($sformatf("op:%0d, op1:0x%0h op2:0x%0h res:0x%0h", op_i, op1_i, op2_i, result_o));
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
  assign is_rv64w   = op_i inside {DIV_DIVW, DIV_REMW, DIV_REMUW, DIV_DIVUW};
  assign is_signed  = op_i inside {DIV_DIV, DIV_DIVW, DIV_REM, DIV_REMW};
  assign a_sign     = is_rv64w ? op1_i[31] : op1_i[63];
  assign b_sign     = is_rv64w ? op2_i[31] : op2_i[63];

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
    if (!valid) begin
      done_o = 0;
    end else begin
      done_o = is_divider ? 1'b0 : 1'b1;
    end

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
          `LOGI($sformatf("op:%0d: op1:%0d op2:%0d res:%0d", op_i, op1_i, op2_i, result_o));
          done_o = 1'b1;
          if (valid) state_d = IDLE;
        end
        default: state_d = IDLE;
      endcase
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q       <= IDLE;
      a_q           <= 0;
      b_q           <= 0;
      quot_q        <= 0;
      cnt_q         <= 0;
      is_div_zero_q <= 0;
      is_rem_q      <= 0;
      res_inv_q     <= 0;
      rem_inv_q     <= 0;
    end else begin
      state_q       <= state_d;
      a_q           <= a_d;
      b_q           <= b_d;
      quot_q        <= quot_d;
      cnt_q         <= cnt_d;
      is_div_zero_q <= is_div_zero_d;
      is_rem_q      <= is_rem_d;
      res_inv_q     <= res_inv_d;
      rem_inv_q     <= rem_inv_d;
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
// amo
//------------------------------------
module amo (
  input logic valid,
  input reg_t op1_i,
  input reg_t op2_i,
  input reg_t alu_result_i,
  input amo_op_e op_i,
  output reg_t result_o
);

  always_comb begin
    result_o = alu_result_i;
    if (valid) begin
      if (op_i != AMO_NONE) begin
        `LOGI($sformatf("op:%0d op1:0x%0h, op2:0x%0h", op_i, op1_i, op2_i));
      end
      unique case (op_i)
        AMO_MAX, AMO_MAXU: result_o = alu_result_i == 0 ? op1_i : op2_i;
        AMO_MIN, AMO_MINU: result_o = alu_result_i == 0 ? op2_i : op1_i;
        AMO_MAXW: result_o = ($signed(op1_i[31:0]) > $signed(op2_i[31:0])) ? op1_i : op2_i;
        AMO_MAXUW: result_o = (op1_i[31:0] > op2_i[31:0]) ? op1_i : op2_i;
        AMO_MINW: result_o = ($signed(op1_i[31:0]) < $signed(op2_i[31:0])) ? op1_i : op2_i;
        AMO_MINUW: result_o = (op1_i[31:0] < op2_i[31:0]) ? op1_i : op2_i;
        AMO_SWAP: result_o = op2_i;
        AMO_SWAPW: result_o = {32'(op2_i[31]), op2_i[31:0]};
        AMO_SCW, AMO_SC: result_o = op2_i;
        default: ;
      endcase
    end
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
  mmapingif.master mapif,

  // common interface for each stage
  input  logic       valid,
  output logic       ready_o,
  output exception_t exc_o,

  input  ld_op_e  ld_op_i,
  input  sd_op_e  sd_op_i,
  input  amo_op_e amo_op_i,
  input  logic    amo_valid_i,
  input  addr_t   addr_i,
  input  addr_t   amo_addr_i,
  input  reg_t    wd_i,
  input  reg_t    amo_wd_i,
  output reg_t    rd_o,
  output reg_t    amo_rd_o,
  input  logic    trap_i
);
  typedef enum {
    IDLE,
    MAPPING,
    MEM,
    SC_FAIL
  } state_e;

  typedef struct packed {
    reg_t      hartid;
    logic      valid;
    addr_t     addr;
    datatype_e dtype;
  } lrmark_t;

  logic load, store;
  logic lrenable, scenable;
  state_e state;
  mcause_e ecause;
  datatype_e dtype;
  addr_t addr;
  reg_t wd;

  lrmark_t lrmark;

  always_comb begin
    lrenable = amo_op_i inside {AMO_LR, AMO_LRW} && valid;
    scenable = amo_op_i inside {AMO_SC, AMO_SCW} && valid;

    if (amo_op_i != AMO_NONE) begin
      load  = ld_op_i != LD_NONE;
      store = sd_op_i != SD_NONE && !amo_valid_i;
      addr  = amo_addr_i;
      wd    = amo_wd_i;
    end else begin
      load  = ld_op_i != LD_NONE;
      store = sd_op_i != SD_NONE;
      addr  = addr_i;
      wd    = wd_i;
    end
    if (load) begin
      dtype = ldop2dtype(ld_op_i);
    end else begin
      dtype = sdop2dtype(sd_op_i);
    end

    ready_o = 1;
    ecause  = EXC_NONE;
    if ((valid || amo_valid_i) && (load || store)) begin
      ready_o = 0;
      if (state == MAPPING && mapif.ready == 1) begin
        if (mapif.error) begin
          ecause  = load ? EXC_LOAD_PAGE_FAULT : EXC_STORE_PAGE_FAULT;
          // if (ecause == EXC_STORE_PAGE_FAULT) begin
          //   // $display("exc va:%0h", mapif.va);
          // end
          ready_o = 1;
        end
      end
      if (state == SC_FAIL) begin
        ready_o = 1;
      end
      if (state == MEM && mif.ready == 1) begin
        ready_o = 1;
        if (mif.error) begin
          ecause = load ? EXC_LOAD_ACCESS_FAULT : EXC_STORE_ACCESS_FAULT;
        end
      end
    end

    if (ecause != EXC_NONE) begin
      `LOGE($sformatf("exc, cause: 0x%0h", ecause));
      exc_o.fired = 1;
      exc_o.cause = ecause;
      exc_o.eval  = addr;
    end else begin
      exc_o.fired = 0;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state  <= IDLE;
      lrmark <= '0;
    end else begin
      if (trap_i) begin
        lrmark <= '0;
      end

      if ((valid || amo_valid_i) && (load || store)) begin
        unique case (state)
          IDLE: begin
            if (ecause == EXC_NONE) begin
              mapif.valid <= 1;
              mapif.va    <= addr;
              mapif.rwx   <= {load, store, 1'b0};
              state       <= MAPPING;
            end
          end
          MAPPING: begin
            if (mapif.ready) begin
              mapif.valid <= 0;
              if (mapif.error) begin
                state <= IDLE;
              end else begin
                if (store && scenable && !`overlap(lrmark.addr, lrmark.dtype, mapif.pa, dtype)) begin
                  `LOGE("sc failed");
                  state <= SC_FAIL;
                  rd_o  <= 1;
                end else begin
                  mif.valid <= 1;
                  mif.we <= store;
                  mif.addr <= mapif.pa;
                  mif.wd <= store ? wd : 0;
                  state <= MEM;
                  mif.dtype <= dtype;
                end
              end
            end
          end
          MEM: begin
            if (mif.ready) begin
              mif.valid <= 0;
              if (load && mif.error == 0) begin
                if (lrenable) begin
                  lrmark.valid <= 1;
                  lrmark.dtype <= amo_op_i == AMO_LR ? US64 : S32;
                  lrmark.addr  <= mif.addr;
                end

                if (amo_valid_i) begin
                  amo_rd_o <= mif.rd;
                end else begin
                  rd_o <= mif.rd;
                end
              end else if (store && mif.error == 0) begin
                if (`overlap(lrmark.addr, lrmark.dtype, mif.addr, dtype)) begin
                  if (scenable) begin
                    rd_o <= 0;
                  end
                  lrmark <= '0;
                end
              end
              state <= IDLE;
            end
          end
          SC_FAIL: begin
            state <= IDLE;
          end
          default: ;
        endcase
      end
    end
  end

  function automatic datatype_e sdop2dtype(sd_op_e op);
    unique case (op)
      SD_SB:   return U8;
      SD_SH:   return U16;
      SD_SW:   return U32;
      SD_SD:   return US64;
      SD_SFW:  return F32;
      SD_SFD:  return F64;
      default: return US64;
    endcase
  endfunction
  function automatic datatype_e ldop2dtype(ld_op_e op);
    unique case (op)
      LD_LB:   return S8;
      LD_LBU:  return U8;
      LD_LH:   return S16;
      LD_LHU:  return U16;
      LD_LW:   return S32;
      LD_LWU:  return U32;
      LD_LD:   return US64;
      LD_LFW:  return F32;
      LD_LFD:  return F64;
      default: return US64;
    endcase
  endfunction

endmodule

//------------------------------------
// sram
//------------------------------------
module sram #(
  parameter logic DATAONLY = 0,
  parameter int unsigned CAPS_IN_BYTES = 8 * MB
) (
  input logic clk,
  input logic rst_n,
  memif.slave mif
);
  typedef logic [$clog2(CAPS_IN_BYTES)-1:0] idx_t;
  wire idx_t idx = mif.addr[$clog2(CAPS_IN_BYTES)-1:0];
  logic [7:0] m[CAPS_IN_BYTES];

  initial begin
    if (DATAONLY) begin
      `elf_load(".data", m);
    end else begin
      `elf_load(".hex", m);
    end
  end

  // bypass RAW
  always_comb begin
    mif.ready = mif.valid;
    if (mif.we && mif.valid) begin
      mif.rd = mif.wd;
    end else begin
      if (mif.valid) begin
        unique case (mif.dtype)
          S8: mif.rd = `B2R(m, idx);
          U8: mif.rd = `BU2R(m, idx);
          S16: mif.rd = `H2R(m, idx);
          U16: mif.rd = `HU2R(m, idx);
          S32: mif.rd = `W2R(m, idx);
          U32: mif.rd = `WU2R(m, idx);
          F32: mif.rd = `FW2R(m, idx);
          F64: mif.rd = `D2R(m, idx);
          US64: mif.rd = `D2R(m, idx);
          default: ;
        endcase
        `LOGI($sformatf("read M[%0d]=0x%0h type:%0d", idx, mif.rd, mif.dtype));
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      // foreach (m[i]) begin
      //   m[i] <= '0;
      // end
    end else begin
      if (mif.valid && mif.we) begin
        `LOGI($sformatf("write M[%0d]=0x%0h type:%0d", idx, mif.wd, mif.dtype));
        unique case (mif.dtype)
          S8, U8: `write_data(m, idx, mif.wd, 1);
          S16, U16: `write_data(m, idx, mif.wd, 2);
          S32, U32, F32: `write_data(m, idx, mif.wd, 4);
          US64, F64: `write_data(m, idx, mif.wd, 8);
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
  localparam addr_t SIZE = 12 * KB;
  localparam BITS = $clog2(SIZE);
  wire [BITS-1:0] idx = mif.addr[BITS-1:0];
  logic [7:0] mem[SIZE];

  initial begin
    `elf_load(".hex", mem);
  end

  // bypass RAW
  always_comb begin
    mif.ready = mif.valid;
    if (mif.we && mif.valid) begin
      mif.error = 1;
    end else begin
      if (mif.valid) begin
        unique case (mif.dtype)
          U16: mif.rd = `HU2R(mem, idx);
          U32: mif.rd = `WU2R(mem, idx);
          default: ;
        endcase
      end
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
  input logic        clk,
  input logic        rst_n,
  input mstatus_t    mstatus_i,
  input priviledge_e priv_i,
  input satp_t       satp_i,
  input logic        tlb_invalid_i,
        mmapingif    imapif,
        mmapingif    dmapif,
        memif.master mif
);

  typedef enum {
    WS_IDLE,
    WS_LDPGD,
    WS_LDPMD,
    WS_LDPTE,
    WS_UPDATE_AD,
    WS_DONE
  } walking_state_e;

  `define VPN2(va) va[38:30]
  `define VPN1(va) va[29:21]
  `define VPN0(va) va[20:12]
  `define PGD_ADDR(ppn, va) {8'h00, ppn, 12'(`VPN2(va) << 3)}
  `define PMD_ADDR(ppn, va) {8'h00, ppn, 12'(`VPN1(va) << 3)}
  `define PTE_ADDR(ppn, va) {8'h00, ppn, 12'(`VPN0(va) << 3)}

  `define cache_tlb(tlb, pgsz, va) begin \
    tlb.cached <= 1;       \
    tlb.PGSIZE <= pgsz;  \
    tlb.ASID <= satp_i.ASID; \
    tlb.VPN <= va[38:12];  \
    tlb.PPN <= pte.PPN;    \
    tlb.V <= pte.V;        \
    tlb.R <= pte.R;        \
    tlb.W <= pte.W;        \
    tlb.X <= pte.X;        \
    tlb.U <= pte.U;        \
    tlb.D <= pte.D;        \
    tlb.A <= pte.A;        \
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
    unique case (tlb.PGSIZE) \
      PG_1G:   pa <= {8'b0, tlb.PPN[43:18], va[29:0]}; \
      PG_2M:   pa <= {8'b0, tlb.PPN[43:9], va[20:0]};  \
      PG_4K:   pa <= {8'b0, tlb.PPN[43:0], va[11:0]};  \
      default: pa <= '0; \
    endcase \
  end
  function automatic logic [26:0] vpnmask(pagesize_e pgsz);
    unique case (pgsz)
      PG_4K:   vpnmask = {9'h1ff, 9'h1ff, 9'h1ff};
      PG_2M:   vpnmask = {9'h1ff, 9'h1ff, 9'h000};
      PG_1G:   vpnmask = {9'h1ff, 9'h000, 9'h000};
      default: vpnmask = {9'h1ff, 9'h1ff, 9'h1ff};
    endcase
  endfunction
  function automatic logic tlb_aligned(tlb_entry_t tlb);
    unique case (tlb.PGSIZE)
      PG_1G:   return (tlb.PPN & 44'h3ffff) == 0;
      PG_2M:   return (tlb.PPN & 44'h1ff) == 0;
      default: return 1;
    endcase
  endfunction

  tlb_entry_t itlb, dtlb;
  pagesize_e pgsize;
  pte_t pte;
  logic leaf;
  logic imap, dmap;
  logic ihit, dhit, ialigned, daligned;
  logic icheck, dcheck, lcheck;
  logic [1:0] markad;
  priviledge_e epriv;

  always_comb begin
    epriv = priv_i;
    if (priv_i == M_MACHINE && mstatus_i.MPRV == 1) begin
      epriv = priviledge_e'(mstatus_i.MPP);
    end
    pte = mif.rd;
    leaf = pte.V & (pte.R | pte.W | pte.X);
    imap = priv_i != M_MACHINE && satp_i.MODE == 8 && imapif.valid == 1;
    dmap = epriv < M_MACHINE && satp_i.MODE == 8 && dmapif.valid == 1;

    ihit = itlb.cached && (itlb.VPN & vpnmask(itlb.PGSIZE)) == (imapif.va[38:12] & vpnmask(itlb.PGSIZE)) &&
        (itlb.G || itlb.ASID == satp_i.ASID);
    dhit = dtlb.cached && (dtlb.VPN & vpnmask(dtlb.PGSIZE)) == (dmapif.va[38:12] & vpnmask(dtlb.PGSIZE)) &&
        (dtlb.G || dtlb.ASID == satp_i.ASID);

    icheck = itlb.V && itlb.X && ((priv_i == M_SUPER && itlb.U == 0) || (priv_i == M_USER && itlb.U == 1));
    dcheck = dtlb.V && ((dmapif.rwx[2] == 1 && (dtlb.R || (mstatus_i.MXR && dtlb.X))) || (dmapif.rwx[1] == 1 && dtlb.W));
    lcheck = (epriv == M_USER && dtlb.U == 1) || (epriv == M_SUPER && (dtlb.U == 0 || mstatus_i.SUM));

    ialigned = tlb_aligned(itlb);
    daligned = tlb_aligned(dtlb);

    markad = '0;
    if (ihit) begin
      markad[0] = !itlb.A;
    end
    if (dhit) begin
      markad[0] = !dtlb.A;
      markad[1] = dmapif.rwx[1] == 1 ? !dtlb.D : 0;
    end
  end

  // controller
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
    end else begin
      if (tlb_invalid_i) begin
        `LOGW("invalid TLB");
        itlb <= '0;
        dtlb <= '0;
      end

      imapif.ready <= 0;
      dmapif.ready <= 0;
      imapif.error <= 0;
      dmapif.error <= 0;
      if (imapif.valid && !imap) begin
        `LOGI($sformatf("bypass map instr: 0x%0h priv:%0d, mode:%0d", imapif.va, priv_i, satp_i.MODE));
        imapif.pa    <= imapif.va;
        imapif.ready <= 1;
      end
      if (dmapif.valid && !dmap) begin
        `LOGI($sformatf("bypass map data: 0x%0h", dmapif.va));
        dmapif.pa    <= dmapif.va;
        dmapif.ready <= 1;
      end

      if (imap && ihit) begin
        if (ialigned && icheck) begin
          imapif.ready <= 1;
          `build_pa_by_tlb(imapif.pa, itlb, imapif.va);
          if (|markad && !walking) begin
            `LOGI("data trigger update PTE");
            walking    <= 1;
            walking_va <= imapif.va;
            update_ad  <= markad;
            iwalking   <= 1;
          end
        end else begin
          `LOGTLB("itlb", itlb);
          imapif.ready <= 1;
          imapif.error <= 1;
        end
      end
      if (dmap && dhit) begin
        if (daligned && dcheck && lcheck) begin
          dmapif.ready <= 1;
          `build_pa_by_tlb(dmapif.pa, dtlb, dmapif.va);
          if (|markad && !walking) begin
            `LOGI("data trigger update PTE");
            walking    <= 1;
            walking_va <= dmapif.va;
            update_ad  <= markad;
            iwalking   <= 0;
          end
        end else begin
          `LOGE($sformatf("dmap error: %b %b", dcheck, lcheck));
          `LOGTLB("dtlb", dtlb);
          // $display("dmap: dcheck: %b, lcheck: %b", dcheck, lcheck);
          dmapif.ready <= 1;
          dmapif.error <= 1;
        end
      end

      if (dmap && !dhit) begin
        if (!walking) begin
          walking    <= 1;
          walking_va <= dmapif.va;
          update_ad  <= 2'b0;
          iwalking   <= 0;
        end
      end else if (imap && !ihit) begin
        if (!walking) begin
          walking    <= 1;
          walking_va <= imapif.va;
          update_ad  <= 2'b0;
          iwalking   <= 1;
        end
      end

    end
  end


  // page table walking
  logic walking, iwalking;
  walking_state_e wstate;
  addr_t walking_va;
  logic [1:0] update_ad;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wstate   <= WS_IDLE;
      walking  <= 0;
      iwalking <= 0;
    end else begin
      if (walking) begin
        unique case (wstate)
          WS_IDLE: begin
            wstate <= WS_LDPGD;
            mif.valid <= 1'b1;
            mif.we <= 1'b0;
            mif.dtype <= US64;
            mif.addr <= `PGD_ADDR(satp_i.PPN, walking_va);
            `LOGI($sformatf("ptw:0x%0h va:0x%0h", `PGD_ADDR(satp_i.PPN, walking_va), walking_va));
          end
          WS_LDPGD: begin
            if (mif.ready) begin
              `LOGPTE("pgd", pte);
              mif.valid <= 1'b0;
              if (!pte.V || leaf) begin
                wstate <= WS_DONE;
                pgsize <= PG_1G;
                if (iwalking) begin
                  `cache_tlb(itlb, PG_1G, walking_va)
                end else begin
                  `cache_tlb(dtlb, PG_1G, walking_va)
                end
              end else begin
                mif.valid <= 1'b1;
                mif.we <= 1'b0;
                mif.dtype <= US64;
                wstate <= WS_LDPMD;
                mif.addr <= `PMD_ADDR(pte.PPN, walking_va);
              end
            end
          end
          WS_LDPMD: begin
            if (mif.ready) begin
              `LOGPTE("pmd", pte);
              mif.valid <= 1'b0;
              if (!pte.V || leaf) begin
                wstate <= WS_DONE;
                pgsize <= PG_2M;
                if (iwalking) begin
                  `cache_tlb(itlb, PG_2M, walking_va)
                end else begin
                  `cache_tlb(dtlb, PG_2M, walking_va)
                end
              end else begin
                mif.valid <= 1'b1;
                mif.we <= 1'b0;
                mif.dtype <= US64;
                wstate <= WS_LDPTE;
                mif.addr <= `PTE_ADDR(pte.PPN, walking_va);
              end
            end
          end
          WS_LDPTE: begin
            if (mif.ready) begin
              `LOGPTE("pte", pte);
              mif.valid <= 1'b0;
              wstate <= WS_DONE;
              pgsize <= PG_4K;
              if (iwalking) begin
                `cache_tlb(itlb, PG_4K, walking_va)
              end else begin
                `cache_tlb(dtlb, PG_4K, walking_va)
              end
            end
          end
          WS_UPDATE_AD: begin
            if (mif.ready) begin
              `LOGPTE("AD updated", pte);
              mif.valid <= 1'b0;
              wstate <= WS_DONE;
              update_ad <= '0;
            end
          end
          WS_DONE: begin
            if (|update_ad) begin
              mif.valid <= 1'b1;
              mif.we <= 1'b1;
              mif.dtype <= US64;
              wstate <= WS_UPDATE_AD;
              unique case (update_ad)
                2'b01:   mif.wd <= mif.rd;
                2'b10:   mif.wd <= mif.rd | `PTE_D;
                2'b11:   mif.wd <= mif.rd | `PTE_A | `PTE_D;
                default: ;
              endcase
              `LOGI($sformatf("update: %0h", mif.rd));
            end else begin
              wstate  <= WS_IDLE;
              walking <= '0;
            end
          end
        endcase
      end
    end
  end

endmodule

//------------------------------------
// csr
// - register rw
// - irq to trap vector
// - priviledge management
//------------------------------------
module csr (
  input  logic               clk,
  input  logic               rst_n,
  input  logic               valid,
  input  logic               commit_i,
  input  addr_t              pc_i,
  input  instr_t             instr_i,
  input  sys_op_e            op_i,           // system instr
  input  reg_t               op1_i,
  input  logic        [11:0] which_i,        // index of register
  output reg_t               wb_o,           // csr instr write back
  output satp_t              satp_o,         // satp for mmu
  output mstatus_t           mstatus_o,      // mstatus for mmu
  output priviledge_e        priv_o,         // current priviledge for mmu
  input  logic               exc_fired_i,    // trigger csr to handle exception
  input  exception_t         exc_i,          // exception from others
  output exception_t         exc_o,          // csr instr exception and it will come back at WB stage
  output logic               tlb_invalid_o,  // to mmu
  output logic               halt_o,
  output logic               trap_o,
  output addr_t              trap_target_o,
  input  reg_t               time_i,
  input  fflags_t            fflags_i,       // fpu fflags
  output logic        [ 2:0] frm_o,          // fpu frm
  input  logic               fpr_write_i,    // update mstatus.FS

  // irq interface
  input  logic irq_timer_i,   // timer int from clint
  input  logic irq_ex_i,      // external int from PLIC
  output logic interrupted_o  // for wfi
);
  // 1. csr rw(check permission: priv-[9:8] and ro, rw[11:10])
  // 2. handle exception according to current priv and deleg
  // 3. handle int according to current priv and deleg
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
  `define MTVEC_MASK 64'hffff_ffff_ffff_fffc
  `define FCSR_MASK 32'h0000_00ff
  `define TM(en) (which_i == TIME && !en.TM)
  `define CY(en) (which_i == CYCLE && !en.CY)
  `define IR(en) (which_i == INSTRET && !en.IR)

  mstatus_t mstatus;
  medeleg_t medeleg;
  mintr_t mideleg, mie, mip;
  misa_t misa;

  reg_t mtvec, mtval, mepc, mcause, mhartid, mscratch, mvendorid, marchid, mimpid, mtime;
  reg_t stvec, stval, sepc, scause, sscratch;
  reg_t cycle;
  satp_t satp;
  mcounteren_t mcounteren, scounteren;
  priviledge_e priv;
  mcause_e ecause;
  fcsr_t fcsr;

  always_comb begin
    priv_o    = priv;
    satp_o    = satp;
    mstatus_o = mstatus;
    frm_o     = fcsr.frm;
  end

  reg_t rd;
  logic unexist;
  always_comb begin
    unexist = 0;
    unique case (which_i)
      MSTATUS:    rd = mstatus;
      MISA:       rd = misa;
      MEDELEG:    rd = medeleg;
      MIDELEG:    rd = mideleg;
      MIE:        rd = mie;
      MTVEC:      rd = mtvec;
      MSCRATCH:   rd = mscratch;
      MEPC:       rd = mepc;
      MCAUSE:     rd = mcause;
      MTVAL:      rd = mtval;
      MIP:        rd = mip;
      MHARTID:    rd = mhartid;
      SSTATUS:    rd = mstatus;  //& `SSTATUS_READ_MASK;
      SIE:        rd = mie & `SIE_MASK;
      STVEC:      rd = stvec;
      SSCRATCH:   rd = sscratch;
      SEPC:       rd = sepc;
      SCAUSE:     rd = scause;
      STVAL:      rd = stval;
      SIP:        rd = mip & `SIP_MASK;
      SATP:       rd = satp;
      MCOUNTEREN: rd = {32'b0, mcounteren};
      SCOUNTEREN: rd = {32'b0, scounteren};
      CYCLE:      rd = cycle;
      MVENDORID:  rd = mvendorid;
      MARCHID:    rd = marchid;
      MIMPID:     rd = mimpid;
      TIME:       rd = mtime;
      FFLAGS:     rd = {59'b0, fcsr.fflags};
      FRM:        rd = {61'b0, fcsr.frm};
      FCSR:       rd = {32'b0, fcsr};
      MNSTATUS:   rd = '0;
      PMPCFG0:    rd = '0;
      PMPADDR0:   rd = '0;
      default: begin
        rd      = '0;
        unexist = 1;
      end
    endcase
  end

  reg_t next;
  logic illegal;
  logic write;
  logic cy, tm, ir;
  always_comb begin
    next        = 0;
    illegal     = 0;
    write       = 1;
    exc_o.fired = 0;
    if (valid) begin
      // `LOGI($sformatf("op:%0d op1:0x%0h, rd:0x%0h", op_i, op1_i, rd));
      unique case (op_i)
        SYS_CSRRW, SYS_CSRRWI: next = op1_i;
        SYS_CSRRS, SYS_CSRRSI: next = rd | op1_i;
        SYS_CSRRC, SYS_CSRRCI: next = rd & (~op1_i);
        default: ;
      endcase
      if (mstatus.TVM && priv == M_SUPER) begin
        if (op_i == SYS_FENCE) begin
          illegal = 1;
        end
      end
      if (op_i >= SYS_CSRRW) begin
        `LOGI($sformatf("op:%0d, next=0x%0h", op_i, next));
        // csr rw(check permission: priv-[9:8] and ro, rw[11:10])
        if (op_i inside {SYS_CSRRC, SYS_CSRRS, SYS_CSRRSI, SYS_CSRRCI} && op1_i == 0) begin
          write = 0;
        end
        // check writable
        if (write && which_i[11:10] == 2'b11) begin
          illegal = 1;
        end
        // check priviledge
        if (which_i[9:8] > priv) begin
          illegal = 1;
        end else begin
          if (priv == M_USER) begin
            illegal = `TM(scounteren) || `CY(scounteren) || `IR(scounteren);
          end else if (priv == M_SUPER) begin
            illegal = `TM(mcounteren) || `CY(mcounteren) || `IR(mcounteren);
          end
        end

        if (mstatus.TVM && priv == M_SUPER) begin
          if (which_i == SATP) begin
            illegal = 1;
          end
        end
        if (unexist == 1) begin
          `LOGE($sformatf("unknown CSR[0x%3h]", which_i));
          illegal = 1;
        end
      end

      if (illegal) begin
        exc_o.fired = 1;
        exc_o.cause = EXC_ILLEGAL_INSTRUCTION;
        exc_o.eval  = {32'b0, instr_i};
      end
    end
  end

  always_comb begin
    tlb_invalid_o = 0;
    halt_o = 0;
    if (commit_i) begin
      unique case (op_i)
        SYS_FENCE: begin
          tlb_invalid_o = 1;
        end
        SYS_WFI: begin
          halt_o = 1;
        end
        default: ;
      endcase
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      priv       <= M_MACHINE;
      mstatus    <= '{UXL: 2'b10, SXL: 2'b10, FS: 2'b01, default: 0};
      misa       <= '{A: 1, I: 1, M: 1, S: 1, U: 1, MXL: 2'b10, default: 0};  // rv64imasu
      medeleg    <= '0;
      mideleg    <= '0;
      mtvec      <= '0;
      mtval      <= '0;
      mscratch   <= '0;
      mepc       <= '0;
      mcause     <= '0;
      mie        <= '0;
      mip        <= '0;
      mhartid    <= '0;
      stvec      <= '0;
      sscratch   <= '0;
      stval      <= '0;
      scause     <= '0;
      satp       <= '0;
      cycle      <= '0;
      mcounteren <= '0;
      scounteren <= '0;
      mvendorid  <= 64'h489;
      marchid    <= 64'h1;
      mimpid     <= '0;
      mtime      <= '0;
      fcsr       <= '0;
    end else begin
      cycle <= cycle + 1;
      mtime <= time_i;
      if (valid) begin
        wb_o <= rd;
        if (op_i >= SYS_CSRRW) begin
          // check permission
          if (illegal) begin
            `LOGE("illegal csr operation");
          end else begin
            `LOGI($sformatf("CSR[%03h]=%0h", which_i, next));
            unique case (which_i)
              MSTATUS: mstatus <= (mstatus & ~`MSTATUS_WR_MASK) | (next & `MSTATUS_WR_MASK);
              MEDELEG: medeleg <= next;
              MIDELEG: mideleg <= next;
              MIE: mie <= (mie & ~`MIE_MASK) | (next & `MIE_MASK);
              MTVEC: mtvec <= next & `MTVEC_MASK;
              MSCRATCH: mscratch <= next;
              MIP: mip <= (mip & ~`MIP_MASK) | (next & `MIP_MASK);
              MEPC: mepc <= next;
              MCAUSE: mcause <= next;
              MTVAL: mtval <= next;

              SSTATUS: mstatus <= (mstatus & ~`SSTATUS_WR_MASK) | (next & `SSTATUS_WR_MASK);
              SIE: mie <= (mie & ~`SIE_MASK) | (next & `SIE_MASK);
              STVEC: stvec <= next & `MTVEC_MASK;
              SSCRATCH: sscratch <= next;
              SEPC: sepc <= next;
              SCAUSE: scause <= next;
              STVAL: stval <= next;
              SIP: mip <= (mip & ~`SIP_MASK) | (next & `SIP_MASK);
              SATP: begin
                satp[59:0] <= next[59:0];
                if (next[63:60] == 4'h8) begin
                  satp.MODE <= 4'h8;
                end
              end
              MCOUNTEREN: mcounteren <= next[31:0];
              SCOUNTEREN: mcounteren <= next[31:0];
              FCSR: fcsr <= next[31:0] & `FCSR_MASK;
              FRM: fcsr.frm <= next[2:0];
              FFLAGS: fcsr.fflags <= next[4:0];
              default: ;
            endcase
          end
        end
      end
    end
  end

  // handle exception and xRET
  logic strap;
  mstatus_t status;
  mcause_e cause;
  reg_t eval;
  reg_t epc;
  priviledge_e priv_next;

  function automatic logic edeleg(mcause_e cause);
    return medeleg[cause[5:0]];
  endfunction

  always_comb begin
    strap         = '0;
    status        = '0;
    cause         = EXC_NONE;
    epc           = '0;
    eval          = '0;
    priv_next     = M_USER;
    trap_o        = 0;
    trap_target_o = '0;
    interrupted_o = 0;

    if (commit_i) begin
      status = mstatus;
      if (fpr_write_i) begin
        status.FS = 2'b11;
        status.SD = 1'b1;
      end
      if (exc_fired_i) begin
        `LOGE($sformatf("exc fired: 0x%0h", exc_i.cause));
        if (priv < M_MACHINE) begin
          if (edeleg(exc_i.cause)) begin
            strap = 1;
          end
        end
        if (strap) begin
          // strap
          cause         = exc_i.cause;
          eval          = exc_i.eval;
          epc           = pc_i;
          priv_next     = M_SUPER;
          status.SPP    = priv == M_USER ? 0 : 1;
          status.SPIE   = mstatus.SIE;
          status.SIE    = 0;
          trap_o        = 1;
          trap_target_o = stvec;
        end else begin
          // mtrap
          cause         = exc_i.cause;
          eval          = exc_i.eval;
          epc           = pc_i;
          priv_next     = M_MACHINE;
          status.MPP    = priv;
          status.MPIE   = mstatus.MIE;
          status.MIE    = 0;
          trap_o        = 1;
          trap_target_o = mtvec;
        end
      end else if (op_i inside {SYS_SRET, SYS_MRET}) begin
        if (op_i == SYS_SRET) begin
          `LOGI($sformatf("SRET->%0d", mstatus.SPP));
          priv_next     = mstatus.SPP ? M_SUPER : M_USER;
          status.SPP    = '0;
          status.SIE    = mstatus.SPIE;
          status.SPIE   = '0;
          trap_o        = 1;
          trap_target_o = sepc;
        end else begin
          `LOGI($sformatf("MRET->%0d", mstatus.MPP));
          if (mstatus.MPP < M_MACHINE) begin
            status.MPRV = 0;
          end
          status.MPP    = 0;
          status.MIE    = mstatus.MPIE;
          status.MPIE   = 0;
          priv_next     = priviledge_e'(mstatus.MPP);
          trap_o        = 1;
          trap_target_o = mepc;
        end
      end else if (m_intr != reg_t'(0)) begin
        interrupted_o = 1;
        if (mstatus.MIE) begin
          trap_o = 1;
          trap_target_o = mtvec;
          status.MPP = priv;
          status.MPIE = mstatus.MIE;
          status.MIE = 0;
          priv_next = M_MACHINE;
          cause = mintr2cause(m_intr);
          epc = pc_i;
          `LOGW($sformatf("M-intr: %0h", cause));
        end
      end else if (s_intr != reg_t'(0)) begin
        interrupted_o = 1;
        if (mstatus.SIE) begin
          trap_o = 1;
          trap_target_o = stvec;
          status.SPP = (priv == M_USER ? 0 : 1);
          status.SPIE = mstatus.SIE;
          status.SIE = 0;
          priv_next = M_SUPER;
          cause = sintr2cause(s_intr);
          epc = pc_i;
          `LOGW($sformatf("S-intr: %0h", cause));
        end
      end
    end
  end

  // update register when trapped or xRET
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
    end else begin
      if (commit_i) begin
        mstatus <= status;
        fcsr.fflags <= fcsr.fflags | fflags_i;
        if (exc_i.fired) begin
          if (strap) begin
            `LOGW("strap");
            priv   <= priv_next;
            sepc   <= epc;
            scause <= cause;
            stval  <= eval;
          end else begin
            `LOGW("mtrap");
            priv   <= priv_next;
            mepc   <= epc;
            mcause <= cause;
            mtval  <= eval;
          end
        end else if (op_i inside {SYS_SRET, SYS_MRET}) begin
          priv <= priv_next;
          if (op_i == SYS_SRET) begin
            scause <= '0;
          end else begin
            mcause <= '0;
          end
        end else if (m_intr != reg_t'(0)) begin
          if (mstatus.MIE) begin
            priv   <= priv_next;
            mepc   <= epc;
            mcause <= cause;
          end
        end else if (s_intr != reg_t'(0)) begin
          if (mstatus.SIE) begin
            priv   <= priv_next;
            sepc   <= epc;
            scause <= cause;
          end
        end
      end
    end
  end

  // handle interrupt
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
    end else begin
      if (mideleg.STI) begin
        mip.STI <= irq_timer_i;
      end else begin
        mip.MTI <= irq_timer_i;
      end
      if (mideleg.SEI) begin
        mip.SEI <= irq_ex_i;
      end else begin
        mip.MEI <= irq_ex_i;
      end
    end
  end

  mintr_t m_intr, s_intr;
  always_comb begin
    m_intr = mip & mie & (~mideleg);
    s_intr = mip & mie & (mideleg);
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

//------------------------------------
// register file
// - 32 64bits common register rw
//------------------------------------
module rfu (
  input  logic             clk,
  input  logic             rst_n,
  input  logic             valid,
  output logic             ready_o,
         regif.slave       rif,
  input  wb_src_e          wb_src_i,
  input  logic       [4:0] rd_i,
  input  reg_t             alu_i,
  input  reg_t             mem_i,
  input  reg_t             amo_i,
  input  reg_t             csr_i,
  input  reg_t             fpu_i
);
  reg_t x[REGMAX];
  reg_t r;

  always_comb begin
    unique case (wb_src_i)
      WB_SRC_ALU: r = alu_i;
      WB_SRC_MEM: r = mem_i;
      WB_SRC_CSR: r = csr_i;
      WB_SRC_AMO: r = amo_i;
      WB_SRC_FPU: r = fpu_i;
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
        `LOGI($sformatf("WB: x[%02d]=0x%0h", rd_i, r));
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
// clint (0x02000000~0x0200ffff)
// - only MTIME and MSWI
// - NO STIME and SSWI
//------------------------------------
module clint (
  input logic clk,
  input logic rst_n,
  memif.slave mif,
  input logic rtc_i,
  output logic timer_o,
  output logic ipi_o,
  output reg_t time_o
);

  reg_t mtime, mtimecmp;
  logic [31:0] msip;
  logic rtc_incr;

  // rtc timer incr
  rtcsyncer syncer1 (
    .clk(clk),
    .rst_n(rst_n),
    .rtc_i(rtc_i),
    .r_edge_o(rtc_incr)
  );

  // write interface
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      msip     <= '0;
      mtimecmp <= '1;
    end else begin
      if (rtc_incr) begin
        mtime <= mtime + 64'd1;
        `LOGI($sformatf("time:%0d timecmp:%0d", mtime, mtimecmp));
      end
      if (mif.valid && mif.we) begin
        `LOGI($sformatf("clint[0x%04h]=0x%0h", mif.addr, mif.wd));
        unique case (mif.addr)
          64'h0000: msip[0] <= mif.wd[0];
          64'h4000: mtimecmp <= mif.wd;
          default:  ;
        endcase
      end
    end
  end

  // read interface
  always_comb begin
    mif.ready = mif.valid;
    if (mif.valid && !mif.we) begin
      unique case (mif.addr)
        64'h0000: mif.rd = {32'b0, msip};
        64'h4000: mif.rd = mtimecmp;
        64'hBFF8: mif.rd = mtime;
        default:  ;
      endcase
    end
  end

  always_comb begin
    timer_o = (mtime >= mtimecmp);
    ipi_o   = msip[0];
    time_o  = mtime;
  end
endmodule

//------------------------------------
// sync rtc clk to main core clk
//------------------------------------
module rtcsyncer (
  input  logic clk,
  input  logic rst_n,
  input  logic rtc_i,
  output logic r_edge_o
);
  logic stage1;
  logic stage2;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      stage1 <= 1'b0;
    end else begin
      stage1 <= rtc_i;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      stage2 <= 1'b0;
    end else begin
      stage2 <= stage1;
    end
  end

  assign r_edge_o = stage2 & (~stage1);
endmodule

//------------------------------------
// plic (0c00_0000~0fff_ffff)=64MB
//   ctx = hart * priviledge(M + S)
// - priority:       0c00_0000 (4B per int source 1023 max)
// - pending:        0c00_1000 (1-bit per int source 1023 max)
// - enable :        0c00_2000 (1-bit per ctx*source max 15872 * 1023)
// - threshold:      0c20_0000 (4B per ctx 0 max 15872)
// - claim/complete: 0c20_0004 (4B per ctx 0 max 15872)
// - threshold:      0c20_1000 (4B per ctx 1 max 15872)
// - claim/complete: 0c20_1004 (4B per ctx 1 max 15872)
//------------------------------------
module plic #(
  parameter int unsigned SOURCE_CNT = 16,
  parameter int unsigned CTX_CNT = 2,
  parameter int unsigned MAX_PRIO = 7
) (
  input logic clk,
  input logic rst_n,
  input logic [SOURCE_CNT-1:0] src_i,
  output logic [CTX_CNT-1:0] intr_o,
  memif.slave mif
);
  localparam int unsigned PRIO_BASE = 32'h00_0000;
  localparam int unsigned PENDING_BASE = 32'h00_1000;
  localparam int unsigned ENABLE_BASE = 32'h00_2000;
  localparam int unsigned THRESHOLD_BASE = 32'h20_0000;
  localparam int unsigned CLAIM_BASE = 32'h20_0004;
  localparam int unsigned PLIC_END = 32'h3f_fffc;

  localparam int unsigned PRIOW = $clog2(MAX_PRIO);
  localparam int unsigned SRCW = $clog2(SOURCE_CNT);
  localparam int unsigned SREM = (SOURCE_CNT % 32);

  // per source var
  logic [PRIOW-1:0] prio[SOURCE_CNT];
  logic [SOURCE_CNT-1:0] ip, claim;

  // per context var
  logic [SOURCE_CNT-1:0] ie[CTX_CNT];
  logic [PRIOW-1:0] threshold[CTX_CNT];
  logic [SRCW-1:0] fired[CTX_CNT];

  always_comb begin
    ip = src_i & ~claim;
    ip[0] = 0;
  end


  // calculate best intr
  for (genvar ctx = 0; ctx < CTX_CNT; ctx++) begin : mygen
    logic [PRIOW-1:0] max_prio;
    always_comb begin
      fired[ctx] = 0;
      max_prio   = threshold[ctx] + 1;
      for (int i = SOURCE_CNT - 1; i >= 0; i--) begin
        if ((ip[i] & ie[ctx][i] == 1) && prio[i] >= max_prio) begin
          max_prio   = prio[i];
          fired[ctx] = SRCW'(i);
        end
      end
      if (fired[ctx] > 0) begin
        `LOGW($sformatf("context %0d fired:%0d", ctx, fired[ctx]));
        intr_o[ctx] = 1;
      end else begin
        intr_o[ctx] = 0;
      end
    end
  end

  int unsigned ctx;
  int unsigned src;
  always_comb begin
    ctx = CTX_CNT;
    src = SOURCE_CNT;
    if (mif.valid) begin
      if (mif.addr[31:0] < PENDING_BASE) begin
        src = (mif.addr[31:0] / 32'd4);
      end else if (mif.addr[31:0] >= PENDING_BASE && mif.addr[31:0] < ENABLE_BASE) begin
        src = (mif.addr[31:0] - ENABLE_BASE) * 32;
      end else if (mif.addr[31:0] >= ENABLE_BASE && mif.addr[31:0] < THRESHOLD_BASE) begin
        ctx = (mif.addr[31:0] - ENABLE_BASE) / 32'h80;
        src = (mif.addr[31:0] - ENABLE_BASE - ctx * 32'h80) * 32;
      end else if (mif.addr[31:0] >= THRESHOLD_BASE && mif.addr[31:0] < PLIC_END) begin
        ctx = (mif.addr[31:0] - THRESHOLD_BASE) / 32'h1000;
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      claim <= '0;
    end else begin
      // reg write
      mif.ready <= 0;
      if (mif.valid && mif.we) begin
        mif.ready <= 1;
        if (mif.addr[31:0] < PENDING_BASE) begin
          if (src < SOURCE_CNT) begin
            prio[src] <= mif.wd[PRIOW-1:0];
            `LOGI($sformatf("set prio[%0d]=%0d", src, mif.wd[PRIOW-1:0]));
          end
        end else if (mif.addr[31:0] >= ENABLE_BASE && mif.addr[31:0] < THRESHOLD_BASE) begin
          if (ctx < CTX_CNT && src < SOURCE_CNT) begin
            if (src + 32 >= SOURCE_CNT) begin
              `LOGI($sformatf("enable %0d %b", src, mif.wd[SREM-1:0]));
              ie[ctx][src+:SREM] <= mif.wd[(SREM)-1:0];
            end else begin
              for (int i = 0; i < 32; i++) begin
                ie[ctx][src+i] <= mif.wd[i];
              end
            end
          end
        end else if (mif.addr[31:0] >= THRESHOLD_BASE && mif.addr[31:0] < PLIC_END) begin
          if (ctx < CTX_CNT) begin
            if (mif.addr[2:0] == 3'b000) begin
              threshold[ctx] <= mif.wd[PRIOW-1:0];
            end else if (mif.addr[2:0] == 3'b100) begin
              if (mif.wd[31:0] < SOURCE_CNT && claim[mif.wd[SRCW-1:0]] == 1) begin
                claim[mif.wd[SRCW-1:0]] <= 0;
              end
            end
          end
        end
      end else if (mif.valid && !mif.we) begin
        mif.ready <= 1;
        if (mif.addr[31:0] < PENDING_BASE) begin
          if (src < SOURCE_CNT) begin
            mif.rd <= {32'b0, 32'(prio[src])};
          end
        end else if (mif.addr[31:0] >= PENDING_BASE && mif.addr[31:0] < ENABLE_BASE) begin
          if (src < SOURCE_CNT) begin
            if (src + 32 >= SOURCE_CNT) begin
              mif.rd <= '0;
              for (int i = 0; i < SREM; i++) begin
                mif.rd[i] <= ip[src+i];
              end
            end else begin
              mif.rd[63:32] <= '0;
              for (int i = 0; i < 32; i++) begin
                mif.rd[i] <= ip[src+i];
              end
            end
          end
        end else if (mif.addr[31:0] >= ENABLE_BASE && mif.addr[31:0] < THRESHOLD_BASE) begin
          if (ctx < CTX_CNT && src < SOURCE_CNT) begin
            if (src + 32 >= SOURCE_CNT) begin
              mif.rd <= '0;
              mif.rd[SREM-1:0] <= ie[ctx][src+:SREM];
            end else begin
              mif.rd[63:32] <= '0;
              for (int i = 0; i < 32; i++) begin
                mif.rd[i] <= ie[ctx][src+i];
              end
            end
          end
        end else if (mif.addr[31:0] >= THRESHOLD_BASE && mif.addr[31:0] < PLIC_END) begin
          if (ctx < CTX_CNT) begin
            if (mif.addr[2:0] == 3'b000) begin
              mif.rd <= '0;
              mif.rd[PRIOW-1:0] <= threshold[ctx];
            end else if (mif.addr[2:0] == 3'b100) begin
              `LOGI($sformatf("ctx:%0d %0d", ctx, fired[ctx]));
              mif.rd <= '0;
              mif.rd[SRCW-1:0] <= fired[ctx];
              if (fired[ctx] > 0) begin
                claim[fired[ctx]] <= 1;
              end
            end
          end
        end
      end
    end
  end

endmodule

//------------------------------------
// interrupt generater
//------------------------------------
module igen (
  input logic clk,
  input logic rst_n,
  output logic intr_o,
  memif.slave mif
);

  logic intr;
  assign mif.ready = mif.valid;
  assign intr_o = intr;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
    end else begin
      if (mif.valid && mif.we == 1) begin
        intr <= mif.wd[0];
      end
    end
  end

endmodule

//------------------------------------
// raptor for exception, irq
//------------------------------------
module raptor (
  input  logic clk,
  input  logic rst_n,
  input  logic halt_i,
  output logic intr_o
);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      intr_o <= 0;
    end else begin
      if (halt_i) begin
        intr_o <= 1;
      end else begin
        intr_o <= 0;
      end
    end
  end

endmodule

//------------------------------------
// uart 8250 (from NS-National Semiconductor)
//------------------------------------
module uart8250 (
  input logic clk,
  input logic rst_n,
  memif mif,
  output logic intr_o
);
  import "DPI-C" function void sim_uart_init();
  import "DPI-C" function void sim_uart_cleanup();
  import "DPI-C" function void sim_host_putc(input byte ch);
  import "DPI-C" function int sim_host_getc(output byte ch);

  typedef enum logic [7:0] {
    REG_RBR_THR_DLL = 0,
    REG_IER_DLM,
    REG_IIR_FCR,
    REG_LCR,
    REG_MCR,
    REG_LSR,  // 5
    REG_MSR
  } reg_e;

  // 1. 中断允许寄存器 (IER) - DLAB=0
  typedef struct packed {
    logic [7:4] reserved_7_4;  // Bit [7:4]: 保留位
    logic       EDSSI;         // Bit 3: 允许 Modem 状态中断
    logic       ELSI;          // Bit 2: 允许接收线路状态中断
    logic       ETBEI;         // Bit 1: 允许发送保持寄存器空中断
    logic       ERBFI;         // Bit 0: 允许接收数据就绪中断
  } ier_t;

  // 2. 通信线控制寄存器 (LCR)
  typedef struct packed {
    logic       DLAB;  // Bit 7: 除数锁存访问位
    logic       BC;    // Bit 6: Break 控制位
    logic [2:0] PS;    // Bit [5:3]: 奇偶校验选择
    logic       STB;   // Bit 2: 停止位长度 (0=1位, 1=1.5/2位)
    logic [1:0] WLS;   // Bit [1:0]: 数据位长度 (00=5位, 01=6位, 10=7位, 11=8位)
  } lcr_t;

  // 3. Modem 控制寄存器 (MCR)
  typedef struct packed {
    logic [2:0] reserved_7_5;  // Bit [7:5]: 保留位
    logic       LOOP;          // Bit 4: 本地回环测试模式
    logic       OUT2;          // Bit 3: 通用输出引脚 2
    logic       OUT1;          // Bit 2: 通用输出引脚 1
    logic       RTS;           // Bit 1: 请求发送
    logic       DTR;           // Bit 0: 数据终端准备好
  } mcr_t;

  // 4. 通信线状态寄存器 (LSR)
  typedef struct packed {
    logic ERR_FIFO;  // Bit 7: FIFO 中存在错误数据 (16550特有)
    logic TEMT;      // Bit 6: 发送移位寄存器空
    logic THRE;      // Bit 5: 发送保持寄存器空
    logic BI;        // Bit 4: 线路间断 (Break Interrupt)
    logic FE;        // Bit 3: 帧格式错误
    logic PE;        // Bit 2: 奇偶校验错误
    logic OE;        // Bit 1: 溢出错误
    logic DR;        // Bit 0: 接收数据就绪
  } lsr_t;

  // 5. Modem 状态寄存器 (MSR)
  typedef struct packed {
    logic DCD;   // Bit 7: 数据载波检测当前状态
    logic RI;    // Bit 6: 振铃指示当前状态
    logic DSR;   // Bit 5: 数据设备就绪当前状态
    logic CTS;   // Bit 4: 清除发送当前状态
    logic DDCD;  // Bit 3: DCD 状态变化标志
    logic TERI;  // Bit 2: RI 状态变化标志
    logic DDSR;  // Bit 1: DSR 状态变化标志
    logic DCTS;  // Bit 0: CTS 状态变化标志
  } msr_t;

  // 6. 中断识别寄存器 (IIR) - 只读
  typedef struct packed {
    logic [5:0] reserved_7_2;  // Bit [7:2]: 保留位
    logic [1:0] IID;           // Bit [1:0]: 中断源识别 (00=Modem, 01=THR空, 10=接收就绪, 11=线路状态)
  } iir_t;

  // 7. FIFO 控制寄存器 (FCR) - 只写 (16550扩展)
  typedef struct packed {
    logic [1:0] reserved_7_6;  // Bit [7:6]: 保留位
    logic [1:0] RXTRIG;        // Bit [5:4]: 接收 FIFO 触发中断阈值 (00=1B, 01=4B, 10=8B, 11=14B)
    logic [1:0] reserved_3_2;  // Bit [3:2]: 保留位
    logic       TX_FIFO_RST;   // Bit 1: 发送 FIFO 复位
    logic       RX_FIFO_RST;   // Bit 0: 接收 FIFO 复位
  } fcr_t;

  initial begin
    sim_uart_init();
  end

  final begin
    sim_uart_cleanup();
  end

  logic [7:0] thr, rbr, data;
  lsr_t lsr;
  ier_t ier;
  iir_t iir;
  lcr_t lcr;
  mcr_t mcr;
  msr_t msr;
  logic dlab, tx_busy;

  assign dlab = lcr.DLAB;
  assign intr_o = (ier.ERBFI & lsr.DR) | (ier.ETBEI & lsr.THRE);
  assign mif.ready = mif.valid;

  // read reg
  always_comb begin
    if (mif.valid && !mif.we) begin
      mif.rd = '0;
      unique case (mif.addr[7:0])
        REG_RBR_THR_DLL: mif.rd[7:0] = dlab ? 8'h00 : rbr;
        REG_IER_DLM: mif.rd[7:0] = dlab ? 8'h00 : ier;
        REG_IIR_FCR: mif.rd[7:0] = iir;
        REG_LCR: mif.rd[7:0] = lcr;
        REG_LSR: mif.rd[7:0] = lsr;
        default: ;
      endcase
      `LOGI($sformatf("read uart[%0d]: 0x%h", mif.addr[7:0], mif.rd[7:0]));
    end
  end

  //write
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      lsr <= '{THRE: 1, default: 0};
    end else begin
      if (mif.valid && mif.we) begin
        `LOGI($sformatf("write uart[%0d]=%0h", mif.addr[7:0], mif.wd[7:0]));
        unique case (mif.addr[7:0])
          REG_RBR_THR_DLL: begin
            if (!dlab && lsr.THRE) begin
              lsr.THRE <= 0;
              tx_busy  <= 1;
              sim_host_putc(mif.wd[7:0]);
            end
          end
          REG_IER_DLM: if (!dlab) ier <= mif.wd[7:0];
          REG_LCR: lcr <= mif.wd[7:0];
          default: ;
        endcase
      end

      // simulate tx
      if (tx_busy) begin
        tx_busy  <= 0;
        lsr.THRE <= 1;
      end

      // simulate rx
      if (!lsr.DR) begin
        if (sim_host_getc(rbr) > 0) begin
          lsr.DR <= 1;
        end
      end

      // clear DR when read
      if (mif.valid && !mif.we && mif.addr[7:0] == REG_RBR_THR_DLL && !dlab) begin
        lsr.DR <= 0;
      end
    end
  end

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
        if (mif.wd == 1) begin
          $write("%sPASS%s ", `COLOR_GREEN, `COLOR_NONE);
        end else begin
          $write("%sFAIL:%0d%s ", `COLOR_RED, mif.wd[63:1], `COLOR_NONE);
        end
        $finish(0);
      end
    end
  end

endmodule

//------------------------------------
// fpu related modules
//------------------------------------
module fpr (
  input logic clk,
  input logic rst_n,
  input logic valid,
  input logic [4:0] rd_i,
  input wb_src_e wb_src_i,
  input reg_t wb_fpu_i,
  input reg_t wb_mem_i,
  regif.slave rif
);
  reg_t f[REGMAX];

  always_comb begin
    rif.v1 = f[rif.r1];
    rif.v2 = f[rif.r2];
    rif.v3 = f[rif.r3];
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      foreach (f[i]) f[i] <= '0;
    end else begin
      if (valid) begin
        f[rd_i] <= wb_src_i == WB_SRC_FPU ? wb_fpu_i : wb_mem_i;
        `LOGI($sformatf("FWB:f[%02d]=0x%0h", rd_i, wb_src_i == WB_SRC_FPU ? wb_fpu_i : wb_mem_i));
      end
    end
  end
endmodule

//------------------------------------
// FPU top module
//------------------------------------
module fpu (
  input logic clk,
  input logic rst_n,
  input logic valid,
  input id_t id_i,
  input fop_e op_i,
  input logic single_i,
  input logic [2:0] rm_i,
  input logic [1:0] fstate_i,
  regif.master rif,
  regif.master fif,

  output reg_t    wb_gpr_o, // to rfu
  output reg_t    wb_fpr_o, // to fpr
  output fflags_t flags_o,  // to fcsr
  output logic    ready_o
);

  reg_t wb_gpr, wb_fpr;
  fflags_t flags;
  fattr_t attrs[3];

  // check input value
  always_comb begin
    attrs = '{default: 0};
    if (id_i.op_s1 == OP_SRC_FPR) begin
      attrs[0] = calc_attr(fif.v1, id_i.single);
    end
    if (id_i.op_s2 == OP_SRC_FPR) begin
      attrs[1] = calc_attr(fif.v2, id_i.single);
    end
    if (id_i.op_s3 == OP_SRC_FPR) begin
      attrs[2] = calc_attr(fif.v3, id_i.single);
    end
  end

  // do float compare
  reg_t cmp_result;
  fflags_t cmp_flags;
  logic cmp_ready, cmp_valid;
  fcmp fcmp1 (
    .clk(clk),
    .rst_n(rst_n),
    .valid(valid && id_i.fop inside {FOP_CMP_EQ, FOP_CMP_LT, FOP_CMP_LE}),
    .single_i(id_i.single),
    .attr_i(attrs[0:1]),
    .op_i(id_i.fop),
    .op1_i(fif.v1),
    .op2_i(fif.v2),
    .result_o(cmp_result),
    .flags_o(cmp_flags),
    .ready_o(cmp_ready),
    .valid_o(cmp_valid)
  );

  reg_t fmv_result;
  logic fmv_ready, fmv_valid;
  fmv fmv1 (
    .clk(clk),
    .rst_n(rst_n),
    .valid(valid && id_i.fop inside {FOP_MV_F_X, FOP_MV_X_F}),
    .single_i(id_i.single),
    .op_i(id_i.fop),
    .op1_i(id_i.fop == FOP_MV_F_X ? rif.v1 : fif.v1),
    .result_o(fmv_result),
    .ready_o(fmv_ready),
    .valid_o(fmv_valid)
  );

  reg_t fcvt_result;
  fflags_t fcvt_flags;
  logic fcvt_ready, fcvt_valid;
  logic cvt_i2d = id_i.fop inside {FOP_CVT_F_W, FOP_CVT_F_L, FOP_CVT_F_WU, FOP_CVT_F_LU};
  fcvt fcvt1 (
    .clk(clk),
    .rst_n(rst_n),
    .valid(valid),
    .single_i(id_i.single),
    .attr_i(attrs[0]),
    .op_i(id_i.fop),
    .op1_i(cvt_i2d ? rif.v1 : fif.v1),
    .rm_i(rm_i),
    .result_o(fcvt_result),
    .flags_o(fcvt_flags),
    .ready_o(fcvt_ready),
    .valid_o(fcvt_valid)
  );

  reg_t fclass_result;
  fflags_t fclass_flags;
  logic fclass_ready, fclass_valid;
  fclass fclass1 (
    .clk(clk),
    .rst_n(rst_n),
    .valid(valid && id_i.fop inside {FOP_CLASS}),
    .single_i(id_i.single),
    .attr_i(attrs[0]),
    .op_i(id_i.fop),
    .op1_i(fif.v1),
    .result_o(fclass_result),
    .flags_o(fclass_flags),
    .ready_o(fclass_ready),
    .valid_o(fclass_valid)
  );

  reg_t fmax_result;
  logic fmax_ready, fmax_valid;
  fflags_t fmax_flags;
  fmax fmax1 (
    .clk(clk),
    .rst_n(rst_n),
    .valid(valid && id_i.fop inside {FOP_MAX, FOP_MIN}),
    .single_i(id_i.single),
    .attr_i(attrs[0:1]),
    .op_i(id_i.fop),
    .op1_i(fif.v1),
    .op2_i(fif.v2),
    .result_o(fmax_result),
    .flags_o(fmax_flags),
    .ready_o(fmax_ready),
    .valid_o(fmax_valid)
  );

  reg_t fsgnj_result;
  logic fsgnj_ready, fsgnj_valid;
  fflags_t fsgnj_flags;
  fsgnj fsgnj1 (
    .clk(clk),
    .rst_n(rst_n),
    .valid(valid && id_i.fop inside {FOP_SGNJ, FOP_SGNJX, FOP_SGNJN}),
    .single_i(id_i.single),
    .attr_i(attrs[0:1]),
    .op_i(id_i.fop),
    .op1_i(fif.v1),
    .op2_i(fif.v2),
    .result_o(fsgnj_result),
    .flags_o(fsgnj_flags),
    .ready_o(fsgnj_ready),
    .valid_o(fsgnj_valid)
  );

  reg_t add_result;
  fflags_t add_flags;
  logic add_ready, add_valid;
  fadd fadd1 (
    .clk(clk),
    .rst_n(rst_n),
    .valid(valid && id_i.fop inside {FOP_ADD, FOP_SUB}),
    .single_i(id_i.single),
    .attr_i(attrs[0:1]),
    .rm_i(rm_i),
    .op_i(id_i.fop),
    .op1_i(fif.v1),
    .op2_i(fif.v2),
    .result_o(add_result),
    .flags_o(add_flags),
    .ready_o(add_ready),
    .valid_o(add_valid)
  );

  reg_t mul_result;
  fflags_t mul_flags;
  logic mul_ready, mul_valid;
  fmul fmul1 (
    .clk(clk),
    .rst_n(rst_n),
    .valid(valid && id_i.fop == FOP_MUL),
    .single_i(id_i.single),
    .attr_i(attrs[0:1]),
    .rm_i(rm_i),
    .op_i(id_i.fop),
    .op1_i(fif.v1),
    .op2_i(fif.v2),
    .result_o(mul_result),
    .flags_o(mul_flags),
    .ready_o(mul_ready),
    .valid_o(mul_valid)
  );

  reg_t fma_result;
  fflags_t fma_flags;
  logic fma_ready, fma_valid;
  fma fma1 (
    .clk(clk),
    .rst_n(rst_n),
    .valid(valid && id_i.fop inside {FOP_MADD, FOP_MSUB, FOP_NMADD, FOP_NMSUB}),
    .single_i(id_i.single),
    .attr_i(attrs[0:2]),
    .rm_i(rm_i),
    .op_i(id_i.fop),
    .op1_i(fif.v1),
    .op2_i(fif.v2),
    .op3_i(fif.v3),
    .result_o(fma_result),
    .flags_o(fma_flags),
    .ready_o(fma_ready),
    .valid_o(fma_valid)
  );

  reg_t div_result;
  fflags_t div_flags;
  logic div_ready, div_valid;
  fdiv fdiv1 (
    .clk(clk),
    .rst_n(rst_n),
    .valid(valid && id_i.fop == FOP_DIV),
    .single_i(id_i.single),
    .attr_i(attrs[0:1]),
    .rm_i(rm_i),
    .op_i(id_i.fop),
    .op1_i(fif.v1),
    .op2_i(fif.v2),
    .result_o(div_result),
    .flags_o(div_flags),
    .ready_o(div_ready),
    .valid_o(div_valid)
  );

  reg_t sqrt_result;
  fflags_t sqrt_flags;
  logic sqrt_ready, sqrt_valid;
  fsqrt fsqrt1 (
    .clk(clk),
    .rst_n(rst_n),
    .valid(valid && id_i.fop == FOP_SQRT),
    .single_i(id_i.single),
    .attr_i(attrs[0]),
    .rm_i(rm_i),
    .op_i(id_i.fop),
    .op1_i(fif.v1),
    .result_o(sqrt_result),
    .flags_o(sqrt_flags),
    .ready_o(sqrt_ready),
    .valid_o(sqrt_valid)
  );

  always_comb begin
    wb_fpr  = '0;
    wb_gpr  = '0;
    flags   = '0;
    ready_o = 0;
    if (cmp_valid) begin
      wb_gpr  = cmp_result;
      flags   = cmp_flags;
      ready_o = cmp_ready;
      if (cmp_ready) begin
        `LOGI($sformatf("FCMP:%0d flags:%b", cmp_result, cmp_flags));
      end
    end else if (fmax_valid) begin
      wb_fpr  = fmax_result;
      flags   = fmax_flags;
      ready_o = fmax_ready;
      if (fmax_ready) begin
        `LOGI($sformatf("FMAX:0x%0h", fmax_result));
      end
    end else if (add_valid) begin
      wb_fpr  = add_result;
      flags   = add_flags;
      ready_o = add_ready;
      if (add_ready) begin
        `LOGI($sformatf("FADD:0x%0h flags:%b", add_result, add_flags));
      end
    end else if (fma_valid) begin
      wb_fpr  = fma_result;
      flags   = fma_flags;
      ready_o = fma_ready;
      if (fma_ready) begin
        `LOGI($sformatf("FMA:0x%0h flags:%b", fma_result, fma_flags));
      end
    end else if (mul_valid) begin
      wb_fpr  = mul_result;
      flags   = mul_flags;
      ready_o = mul_ready;
      if (mul_ready) begin
        `LOGI($sformatf("FMUL:0x%0h flags:%b", mul_result, mul_flags));
      end
    end else if (div_valid) begin
      wb_fpr  = div_result;
      flags   = div_flags;
      ready_o = div_ready;
      if (div_ready) begin
        `LOGI($sformatf("FDIV:0x%0h flags:%b", div_result, div_flags));
      end
    end else if (fsgnj_valid) begin
      wb_fpr  = fsgnj_result;
      flags   = fsgnj_flags;
      ready_o = fsgnj_ready;
      if (fsgnj_ready) begin
        `LOGI($sformatf("FSGNJ:0x%0h flags:%b", fsgnj_result, fsgnj_flags));
      end
    end else if (sqrt_valid) begin
      wb_fpr  = sqrt_result;
      flags   = sqrt_flags;
      ready_o = sqrt_ready;
      if (sqrt_ready) begin
        `LOGI($sformatf("FSQRT:0x%0h flags:%b", sqrt_result, sqrt_flags));
      end
    end else if (fcvt_valid) begin
      ready_o = fcvt_ready;
      flags   = fcvt_flags;
      if (id_i.fop inside {FOP_CVT_F_LU, FOP_CVT_F_WU, FOP_CVT_F_L, FOP_CVT_F_W, FOP_CVT_S_D, FOP_CVT_D_S}) begin
        wb_fpr = fcvt_result;
      end else begin
        wb_gpr = fcvt_result;
      end
      if (fcvt_ready) begin
        `LOGW($sformatf("FCVT:0x%0h flags:%b", fcvt_result, fcvt_flags));
      end
    end else if (fmv_valid) begin
      ready_o = fmv_ready;
      flags   = '0;
      if (id_i.fop == FOP_MV_F_X) begin
        wb_fpr = fmv_result;
      end else begin
        wb_gpr = fmv_result;
      end
      if (fmv_ready) begin
        `LOGI($sformatf("FMV:0x%0h", fmv_result));
      end
    end else if (fclass_valid) begin
      ready_o = fclass_ready;
      flags   = '0;
      wb_gpr  = fclass_result;
      if (fclass_ready) begin
        `LOGI($sformatf("FCLASS:0x%0h", fmv_result));
      end
    end else begin
      ready_o = 1;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
    end else begin
      if (valid) begin
        wb_fpr_o = wb_fpr;
        wb_gpr_o = wb_gpr;
        flags_o  = flags;
      end
    end
  end

  function automatic fattr_t calc_attr(reg_t v, logic single);
    fattr_t attr = '{default: 0};
    f32_t f32 = v[31:0];
    f64_t f64 = v;
    if (single) begin
      attr.NAN  = f32.e == 8'hff && f32.f != 23'h0;
      attr.SNAN = f32.e == 8'hff && f32.f != 23'h0 && f32.f[22] == 0;
      attr.QNAN = f32.e == 8'hff && f32.f != 23'h0 && f32.f[22] == 1;
      attr.INF  = f32.e == 8'hff && f32.f == 23'h0;
      attr.ZERO = f32.e == 8'h00 && f32.f == 23'h0;
      attr.SUBN = f32.e == 8'h00 && f32.f != 23'h0;
    end else begin
      attr.NAN  = f64.e == 11'h7ff && f64.f != 52'h0;
      attr.SNAN = f64.e == 11'h7ff && f64.f != 52'h0 && f64.f[51] == 0;
      attr.QNAN = f64.e == 11'h7ff && f64.f != 52'h0 && f64.f[51] == 1;
      attr.INF  = f64.e == 11'h7ff && f64.f == 52'h0;
      attr.ZERO = f64.e == 11'h000 && f64.f == 52'h0;
      attr.SUBN = f64.e == 11'h000 && f64.f != 52'h0;
    end
    return attr;
  endfunction
endmodule

//------------------------------------
// fadd and fsub
//------------------------------------
module fadd (
  input logic clk,
  input logic rst_n,
  input logic valid,
  input logic single_i,
  input fattr_t attr_i[2],
  input logic [2:0] rm_i,
  input fop_e op_i,
  input reg_t op1_i,
  input reg_t op2_i,
  output reg_t result_o,
  output fflags_t flags_o,
  output logic ready_o,
  output logic valid_o
);

  // verilog_format: off
  typedef enum { SB, S1, S2, S3, SE } state_e;
  // verilog_format: on

  typedef struct packed {
    logic sign, sticky;
    logic [11:0] exp;
    logic [64:0] manti;  // {funpack_t.manti, }
  } faligned_t;


  `define EXP_INF_S 8'hff
  `define EXP_INF_D 11'h7ff
  `define EXP_MAX_S 8'hfe
  `define EXP_MAX_D 11'h7fe
  `define max_exp(single) (single ? 12'd254 : 12'd2046)

  //-----------------
  // check fastpath
  //-----------------
  function automatic ffast_t check_fastpath();
    ffast_t res;
    logic s1, s2;
    logic nan, infi, zero, both_nan, both_infi, both_zero;

    res = '{valid: 1, default: 0};
    s1 = single_i ? op1_i[31] : op1_i[63];
    s2 = single_i ? op2_i[31] ^ op_i == FOP_SUB : op2_i[63] ^ op_i == FOP_SUB;
    nan = attr_i[0].NAN | attr_i[1].NAN;
    infi = attr_i[0].INF | attr_i[1].INF;
    both_nan = attr_i[0].NAN & attr_i[1].NAN;
    both_infi = attr_i[0].INF & attr_i[1].INF;
    zero = attr_i[0].ZERO | attr_i[1].ZERO;
    both_zero = attr_i[0].ZERO & attr_i[1].ZERO;

    // NaN + [NaN]
    if (nan) begin
      res.result = attr_i[0].NAN ? op1_i : op2_i;
      if (attr_i[0].SNAN | attr_i[1].SNAN) begin
        // make it QNaN
        res.result = attr_i[0].SNAN ? op1_i : op2_i;
        if (single_i) begin
          res.result[22] = 1'b1;
        end else begin
          res.result[51] = 1'b1;
        end
        res.flags.nv = 1;
      end
      return res;
    end
    // INF + [INF]
    if (infi) begin
      // INF + INF
      if (both_infi) begin
        // same sign
        if (s1 != s2) begin
          res.result   = `FP_CQNAN(single_i);
          res.flags.nv = 1;
        end else begin
          res.result = `fp_inf(single_i, s1);
        end
        return res;
      end
      // INF + X
      if (!nan) begin
        res.result = attr_i[0].INF ? op1_i : `fp_mkval(single_i, s2, op2_i);
        return res;
      end
    end

    // ZERO + [ZERO]
    if (zero) begin
      if (both_zero) begin
        res.result = (s1 == s2 ? op1_i : {1'b0, 63'b0});
      end else begin
        res.result = (attr_i[0].ZERO ? `fp_mkval(single_i, s2, op2_i) : `fp_mkval(single_i, s1, op1_i));
      end
      return res;
    end

    res.valid = 0;
    return res;
  endfunction

  function automatic int lzc(logic [63:0] val);
    int i;
    for (i = 63; i >= 0; i--) if (val[i] != 1'b0) break;
    return 63 - i;
  endfunction

  function automatic faligned_t alignment(funpack_t u1, funpack_t u2);
    logic [11:0] diff, exp;
    logic sticky, s1, s2, carry;
    reg_t m1, m2;
    faligned_t res = '{default: 0};

    m1 = {u1.manti, 11'b0};
    m2 = {u2.manti, 11'b0};
    s1 = u1.sign;
    s2 = op_i == FOP_SUB ^ u2.sign;
    sticky = 1'b0;

    if (u1.exp >= u2.exp) begin
      diff = u1.exp - u2.exp;
      exp = u1.exp;
      sticky = `OR_NBITS(m2, diff);
      m2 = m2 >> diff;
      m2[0] |= sticky;
    end else begin
      diff = u2.exp - u1.exp;
      exp = u2.exp;
      sticky = `OR_NBITS(m1, diff);
      m1 = m1 >> diff;
      m1[0] |= sticky;
    end
    res.sticky = sticky;

    // sub
    if (s1 ^ s2) begin
      res.exp = exp;
      if (m1 >= m2) begin
        res.sign  = m1 == m2 ? 0 : s1;
        res.manti = m1 - m2;
      end else begin
        res.sign  = s2;
        res.manti = m2 - m1;
      end
    end else begin
      res.exp   = exp;
      res.sign  = s1;
      res.manti = {1'b0, m1} + {1'b0, m2};
    end
    `LOGI($sformatf("s:%b e:%0d m:0x%0h", res.sign, res.exp, res.manti));
    return res;
  endfunction

  function automatic faligned_t normalize(faligned_t ali);
    faligned_t res;
    int lz;
    res.sign   = ali.sign;
    res.sticky = ali.sticky;
    if (ali.manti == '0) begin
      res.exp   = '0;
      res.manti = '0;
    end else if (ali.manti[64]) begin
      res.exp = ali.exp + 1;
      if (ali.manti[0]) begin
        res.sticky = 1;
      end
      res.manti = ali.manti >> 1;
    end else begin
      lz = lzc(ali.manti[63:0]);
      `LOGI($sformatf("lz:%0d manti:%h", lz, ali.manti));
      if (ali.exp > 12'(lz)) begin
        res.manti = ali.manti << lz;
        res.exp   = ali.exp - 12'(lz);
      end else begin
        res.exp   = '0;
        res.manti = ali.manti << (ali.exp > 0 ? ali.exp - 1 : 0);
      end
    end
    `LOGI($sformatf("s:%b e:%0d m:0x%h", res.sign, res.exp, res.manti));
    return res;
  endfunction

  function automatic fpacked_t pack(faligned_t norm, frm_e rm);
    // do round
    logic [51:0] frac;
    logic [11:0] exp;
    logic overflow;
    logic G, R, S, L;
    logic rnd;
    fpacked_t res;
    res = '0;
    rnd = 0;
    S   = norm.sticky;
    if (single_i) begin
      L = norm.manti[40];
      G = norm.manti[39];
      R = norm.manti[38];
      S = (|norm.manti[37:0]) | norm.sticky;
    end else begin
      L = norm.manti[11];
      G = norm.manti[10];
      R = norm.manti[9];
      S = (|norm.manti[8:0]) | norm.sticky;
    end

    unique case (rm)
      RNE: rnd = G & (L | R | S);
      RTZ: rnd = 0;
      RDN: rnd = norm.sign & (G | R | S);
      RUP: rnd = ~norm.sign & (G | R | S);
      RMM: rnd = G;
      default: ;
    endcase
    `LOGI($sformatf("G:%b R:%b S:%b L:%b rnd:%b", G, R, S, L, rnd));
    res.flags.nx = G | R | S;

    frac = single_i ? {29'b0, norm.manti[62:40]} : norm.manti[62:11];
    exp = norm.exp;
    `LOGI($sformatf("frac:%h norm:%h", frac, norm.manti));

    if (rnd) begin
      res.flags.nx = 1;
      overflow = single_i ? frac[22:0] == `ONES(23) : frac == `ONES(52);
      if (overflow) begin
        exp  = exp + 11'd1;
        frac = '0;
      end else begin
        frac += 1;
      end
    end

    if (exp > `max_exp(single_i)) begin
      res.flags.of = 1;
      res.flags.nx = 1;
      unique case (rm)
        RNE, RMM: begin
          exp = single_i ? 12'({'0, `EXP_INF_S}) : 12'({'0, `EXP_INF_D});
          frac = '0;
          res.flags.of = 1;
        end
        RTZ: begin
          exp  = single_i ? 12'({'0, `EXP_MAX_S}) : 12'({'0, `EXP_MAX_D});
          frac = '1;
        end
        RDN: begin
          if (norm.sign) begin
            exp = single_i ? 12'({'0, `EXP_INF_S}) : 12'({'0, `EXP_INF_D});
            frac = '0;
            res.flags.of = 1;
          end else begin
            exp  = single_i ? 12'({'0, `EXP_MAX_S}) : 12'({'0, `EXP_MAX_D});
            frac = '1;
          end
        end
        RUP: begin
          if (norm.sign) begin
            exp  = single_i ? 12'({'0, `EXP_MAX_S}) : 12'({'0, `EXP_MAX_D});
            frac = '1;
          end else begin
            exp = single_i ? 12'({'0, `EXP_INF_S}) : 12'({'0, `EXP_INF_D});
            frac = '0;
            res.flags.of = 1;
          end
        end
        default: ;
      endcase
    end

    `LOGI($sformatf("s:%b e:%0d f:%h", norm.sign, exp, frac));
    res.flags.uf = (res.flags.nx && exp == 0);
    res.result   = `fp_pack(single_i, norm.sign, exp, frac);
    return res;
  endfunction


  ffast_t fast;
  state_e state;
  always_comb begin
    faligned_t aligned, normed;
    funpack_t u1, u2;
    fpacked_t pcked;
    if (valid) begin
      unique case (state)
        SB: fast = '0;
        S1: begin
          fast = check_fastpath();
          if (!fast.valid) begin
            u1 = funpack(single_i, op1_i, attr_i[0]);
            u2 = funpack(single_i, op2_i, attr_i[1]);
          end
        end
        S2: aligned = alignment(u1, u2);
        S3: normed = normalize(aligned);
        SE: begin
          if (fast.valid) begin
            {result_o, flags_o} = {fast.result, fast.flags};
          end else begin
            pcked = pack(normed, frm_e'(rm_i));
            {result_o, flags_o} = {pcked.result, pcked.flags};
          end
        end
        default: ;
      endcase
    end
  end

  assign ready_o = (state == SE || !valid);
  assign valid_o = valid;

  // S1-unpack and input check special case
  // S2-alignment & shift & add/sub
  // S3-normalize & round
  // S4-pack & flags
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= SB;
    end else begin
      if (valid) begin
        unique case (state)
          SB: state <= S1;
          S1: state <= fast.valid ? SE : S2;
          S2: state <= S3;
          S3: state <= SE;
          SE: state <= SB;
        endcase
      end
    end
  end
endmodule

//------------------------------------
// FPU multiply
//------------------------------------
module fmul (
  input logic clk,
  input logic rst_n,
  input logic valid,
  input logic single_i,
  input fattr_t attr_i[2],
  input logic [2:0] rm_i,
  input fop_e op_i,
  input reg_t op1_i,
  input reg_t op2_i,
  output reg_t result_o,
  output fflags_t flags_o,
  output logic ready_o,
  output logic valid_o
);

  // verilog_format: off
  typedef enum { SB, S1, S2, S3, SE } state_e;
  // verilog_format: on

  typedef struct packed {
    logic sign;
    logic [12:0] exp;
    logic [105:0] manti;  // HH.FF....F
    fflags_t flags;
  } fmul_t;

  function automatic int clz(logic [105:0] val);
    int i;
    for (i = 105; i >= 0; i--) if (val[i] != 1'b0) break;
    return 105 - i;
  endfunction

  function automatic ffast_t check_fastpath(reg_t v1, v2, fattr_t a1, a2);
    // +/-zero, +/-inf, QNaN, SNaN, normal, subnormal
    logic sign;
    ffast_t res;
    res = '0;
    res.valid = 1;
    sign = single_i ? v1[31] ^ v2[31] : v1[63] ^ v2[63];

    `LOGW($sformatf("a1:%b a2:%b", a1, a2));
    if (a1.SNAN || a2.SNAN) begin
      // choose the SNAN one and make it QNAN
      res.result   = a1.SNAN ? v1 : v2;
      res.result   = res.result | (single_i ? 64'(1 << 22) : 64'(1 << 51));
      res.flags.nv = 1;
      return res;
    end
    if ((a1.INF && a2.ZERO) || (a1.ZERO && a2.INF)) begin
      `LOGW($sformatf("result: %h", res.result));
      res.result   = `FP_CQNAN(single_i);
      res.flags.nv = 1;
      return res;
    end
    if (a1.QNAN || a2.QNAN) begin
      res.result = a1.QNAN ? v1 : v2;
      return res;
    end
    if (a1.ZERO || a2.ZERO) begin
      res.result = `fp_zero(single_i, sign);
      return res;
    end
    if (a1.INF || a2.INF) begin
      res.result = `fp_inf(single_i, sign);
      return res;
    end
    res.valid = 0;
    return res;
  endfunction

  function automatic fmul_t multiply(funpack_t u1, funpack_t u2);
    fmul_t res;
    res.sign  = u1.sign ^ u2.sign;
    res.manti = u1.manti * u2.manti;
    res.exp   = u1.exp + u2.exp + 13'd1 - `fp_bias(single_i, 13);  // +1 to make int part to MSB
    `LOGI($sformatf("exp:%0d manti:%h", res.exp, res.manti));
    return res;
  endfunction

  function automatic fmul_t normalize(fmul_t v);
    fmul_t res;
    logic L, G, R, S, rndup, tiny;
    logic [12:0] exp;
    logic [105:0] manti;
    int lz = clz(v.manti);
    exp = 13'(v.exp) - 13'(lz);
    manti = v.manti << lz;
    S = 0;
    tiny = 0;
    if ($signed(exp) <= 0) begin
      if ($signed(exp) < -106) begin
        S = |manti;
        manti = '0;
        exp = '0;
      end else if ($signed(exp) <= 0) begin
        exp = exp - 1;
        S = `OR_NBITS(manti, (-$signed(exp)));
        tiny = single_i ? manti[104:81] != `ONES(24) : manti[104:52] != `ONES(53);
        manti = manti >> -$signed(exp);
        manti[0] |= S;
        exp = '0;
      end
    end

    if (single_i) begin
      L = manti[82];
      G = manti[81];
      R = manti[80];
      S = (|manti[79:0]) | S;
    end else begin
      L = manti[53];
      G = manti[52];
      R = manti[51];
      S = (|manti[50:0]) | S;
    end

    res.exp = exp;
    res.sign = v.sign;
    rndup = frndup(G, R, S, L, v.sign, frm_e'(rm_i));
    res.flags.nx = (G | R | S);
    if (tiny && res.flags.nx) begin
      res.flags.uf = 1;
    end
    if (rndup) begin
      if (single_i) begin
        if (manti[104:82] == `ONES(23)) begin
          res.manti = {1'b1, 105'b0};
          res.exp += 13'd1;
        end else begin
          manti[105:82] += 1;
          res.manti = manti;
        end
      end else begin
        if (manti[104:53] == `ONES(52)) begin
          res.manti = {1'b1, 105'b0};
          res.exp += 13'd1;
        end else begin
          manti[105:53] += 1;
          res.manti = manti;
        end
      end
    end else begin
      res.manti = manti;
    end
    if (res.exp == 13'd0) begin
      res.flags.uf = G | R | S;
    end

    // flags
    if (single_i) begin
      if ($signed(res.exp) >= 13'sd255) begin
        res.flags.of = 1;
        res.flags.nx = 1;
        res.exp = 13'h0ff;
        res.manti = '0;
      end
    end else begin
      if ($signed(res.exp) >= 13'sd2047) begin
        res.flags.of = 1;
        res.flags.nx = 1;
        res.exp = 13'h7ff;
        res.manti = '0;
      end
    end

    `LOGI($sformatf("s:%b e:%0d m=%h", res.sign, res.exp, res.manti));
    return res;
  endfunction

  function automatic fpacked_t pack(fmul_t v);
    fpacked_t res;
    res.result = single_i ? {32'hffff_ffff, v.sign, v.exp[7:0], v.manti[104:82]} : {v.sign, v.exp[10:0], v.manti[104:53]};
    res.flags = v.flags;
    return res;
  endfunction

  // FSM
  state_e state;
  ffast_t fast;

  always_comb begin
    funpack_t u1, u2;
    fmul_t mult, norm;
    fpacked_t pcked;
    if (valid) begin
      unique case (state)
        SB: fast = '0;
        S1: begin
          fast = check_fastpath(op1_i, op2_i, attr_i[0], attr_i[1]);
          if (!fast.valid) begin
            u1 = funpack(single_i, op1_i, attr_i[0]);
            u2 = funpack(single_i, op2_i, attr_i[1]);
          end
        end
        S2: mult = multiply(u1, u2);
        S3: norm = normalize(mult);
        SE: begin
          pcked = pack(norm);
          if (fast.valid) begin
            result_o = fast.result;
            flags_o  = fast.flags;
          end else begin
            result_o = pcked.result;
            flags_o  = pcked.flags;
          end
        end
        default: ;
      endcase
    end
  end

  assign ready_o = (state == SE || !valid);
  assign valid_o = valid;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= SB;
    end else begin
      if (valid) begin
        unique case (state)
          SB: state <= S1;
          S1: state <= fast.valid ? SE : S2;
          S2: state <= S3;
          S3: state <= SE;
          SE: state <= SB;
        endcase
      end
    end
  end

endmodule

//------------------------------------
// FPU divide
//------------------------------------
module fdiv (
  input logic clk,
  input logic rst_n,
  input logic valid,
  input logic single_i,
  input fattr_t attr_i[2],
  input logic [2:0] rm_i,
  input fop_e op_i,
  input reg_t op1_i,
  input reg_t op2_i,
  output reg_t result_o,
  output fflags_t flags_o,
  output logic ready_o,
  output logic valid_o
);
  // verilog_format: off
  typedef enum { SB, S1, S2, S3, S4, SE } state_e;
  // verilog_format: on

  typedef struct packed {
    logic sign, tiny;
    logic [12:0] exp;
    logic [52:0] manti;
    grs_t grs;
    fflags_t flags;
  } fdiv_t;

  function automatic int clz(logic [52:0] val);
    int i;
    for (i = 52; i >= 0; i--) if (val[i] != 1'b0) break;
    return 52 - i;
  endfunction

  function automatic ffast_t check_fastpath(reg_t v1, v2, fattr_t a1, a2);
    ffast_t res = '{valid: 1, default: 0};
    logic sign = single_i ? v1[31] ^ v2[31] : v1[63] ^ v2[63];

    `LOGI($sformatf("v1:%h v2:%h a1:%b a2:%b", v1, v2, a1, a2));
    if (a1.SNAN || a2.SNAN) begin
      // choose the SNAN one and make it QNAN
      res.result   = a1.SNAN ? v1 : v2;
      res.result   = res.result | (single_i ? 64'(1 << 22) : 64'(1 << 51));
      res.flags.nv = 1;
      return res;
    end
    if (a1.QNAN || a2.QNAN) begin
      res.result = a1.QNAN ? v1 : v2;
      return res;
    end
    if ((a1.INF && a2.INF) || (a1.ZERO && a2.ZERO)) begin
      res.flags.nv = 1;
      res.result   = `FP_CQNAN(single_i);
      return res;
    end
    if (a1.INF) begin
      res.result = `fp_inf(single_i, sign);
      return res;
    end
    if (a2.ZERO) begin
      res.flags.dz = 1;
      res.result   = `fp_inf(single_i, sign);
      return res;
    end
    if (a2.INF || a1.ZERO) begin
      res.result = single_i ? {`ONES(32), sign, 31'b0} : {sign, 63'b0};
      return res;
    end
    res.valid = 0;
    return res;
  endfunction

  function automatic funpack_t prenormalize(funpack_t v, fattr_t a);
    funpack_t res = v;
    // TODO need check
    if (a.SUBN) begin
      int lz = clz(v.manti);
      if (lz > 0) begin
        res.manti = v.manti << lz;
        res.exp   = 12'd1 - 12'(lz);
      end
    end
    `LOGI($sformatf("s:%b e:%0d m:%0h", res.sign, $signed(res.exp), res.manti));
    return res;
  endfunction

  function automatic fdiv_t normalize(fdiv_t v);
    fdiv_t res = '{default: 0, sign: v.sign};
    logic [52:0] manti;
    logic G, R, S, L, overflow, tiny;
    logic rndup;
    logic [12:0] exp;

    L = v.manti[0];
    G = v.grs.G;
    R = v.grs.R;
    S = v.grs.S;

    rndup = frndup(G, R, S, L, v.sign, frm_e'(rm_i));
    exp = 13'(v.exp);
    res.exp = v.exp;
    manti = v.manti;
    if (rndup) begin
      overflow = single_i ? manti[22:0] == `ONES(23) : manti[51:0] == `ONES(52);
      if (overflow) begin
        res.manti = single_i ? {29'b0, 1'b1, 23'b0} : {1'b1, 52'b0};
        exp = v.exp + 13'd1;
        res.exp = exp;
      end else begin
        manti = v.manti + 53'd1;
        res.manti = manti;
      end
    end else begin
      res.manti = v.manti;
    end

    // flags
    res.flags.nx = (G | R | S);
    if (v.tiny && res.flags.nx) begin
      res.flags.uf = 1;
    end
    if (res.exp == 0) begin
      res.flags.uf = res.flags.nx;
    end
    if (single_i) begin
      if ($signed(exp) >= 13'd255) begin
        res.flags.of = 1;
        res.flags.nx = 1;
        res.exp = 13'h0ff;
        res.manti = '0;
      end
    end else begin
      if ($signed(exp) >= 13'd2047) begin
        res.flags.of = 1;
        res.flags.nx = 1;
        res.exp = 13'h7ff;
        res.manti = '0;
      end
    end
    `LOGI($sformatf("rnd:%b s:%b e:%0d m:%h", rndup, res.sign, res.exp, res.manti));
    return res;
  endfunction

  function automatic fpacked_t pack(fdiv_t v);
    fpacked_t res = '{default: 0};
    res.result = `fp_pack(single_i, v.sign, v.exp, v.manti);
    res.flags  = v.flags;
    return res;
  endfunction

  // FSM
  state_e state;
  ffast_t fast;
  logic iterate_end;

  always_comb begin
    funpack_t u1, u2, p1, p2;
    fdiv_t norm;
    fpacked_t pcked;

    // div
    logic [106:0] holder;
    logic [53:0] sub, divisor;
    logic [54:0] quotient;
    logic gotone, sticky, tiny;
    logic [12:0] lz;
    int cnt;
    fdiv_t dres;


    if (valid) begin
      unique case (state)
        SB: begin
          fast = '0;
          iterate_end = 0;
        end
        S1: begin
          fast = check_fastpath(op1_i, op2_i, attr_i[0], attr_i[1]);
          if (!fast.valid) begin
            u1 = funpack(single_i, op1_i, attr_i[0]);
            u2 = funpack(single_i, op2_i, attr_i[1]);
          end
        end
        S2: begin
          // clz && prenormalize
          p1       = prenormalize(u1, attr_i[0]);
          p2       = prenormalize(u2, attr_i[1]);

          // prepare for div iteration
          dres     = '0;
          holder   = {1'b0, p1.manti, 53'b0};
          cnt      = single_i ? 32'd26 : 32'd55;
          quotient = '0;
          gotone   = 0;
          lz       = 0;
        end
        S3: begin
          divisor = {1'b0, p2.manti};
          sub = holder[106:53] - divisor;
          if (holder[106:53] >= divisor) begin
            holder   = {sub[52:0], holder[52:0], 1'b0};
            quotient = {quotient[53:0], 1'b1};
            gotone   = 1;
          end else begin
            holder   = {holder[105:0], 1'b0};
            quotient = {quotient[53:0], 1'b0};
            if (!gotone) begin
              lz++;
            end
          end
          if (gotone) begin
            cnt--;
          end
          iterate_end = (cnt <= 0);
        end
        S4: begin
          dres.sign = p1.sign ^ p2.sign;
          dres.exp = $signed(p1.exp) - $signed(p2.exp) + $signed(`fp_bias(single_i, 13)) - $signed(lz);
          sticky = |holder;
          tiny = 0;
          if ($signed(dres.exp) <= 0) begin
            tiny = single_i ? quotient[23:1] != `ONES(23) : quotient[53:1] != `ONES(53);
            sticky |= `OR_NBITS(quotient, -$signed(dres.exp) + 1);
            quotient = quotient >> -$signed(dres.exp) + 1;
            dres.exp = '0;
          end

          dres.manti = quotient[54:2];
          dres.grs.G = quotient[1];
          dres.grs.R = quotient[0];
          dres.grs.S = sticky;
          dres.tiny  = tiny;
          `LOGI($sformatf("div done >> s:%b e:%0d m:%h", dres.sign, $signed(dres.exp), dres.manti));
          norm = normalize(dres);
        end
        SE: begin
          if (fast.valid) begin
            result_o = fast.result;
            flags_o  = fast.flags;
          end else begin
            pcked    = pack(norm);
            result_o = pcked.result;
            flags_o  = pcked.flags;
          end
        end
        default: ;
      endcase
    end
  end

  assign ready_o = (state == SE || !valid);
  assign valid_o = valid;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= SB;
    end else begin
      if (valid) begin
        unique case (state)
          SB: state <= S1;
          S1: state <= fast.valid ? SE : S2;
          S2: state <= S3;
          S3: state <= iterate_end ? S4 : S3;
          S4: state <= SE;
          SE: state <= SB;
          default: ;
        endcase
      end
    end
  end
endmodule

//------------------------------------
// fsqrt
//------------------------------------
module fsqrt (
  input logic clk,
  input logic rst_n,
  input logic valid,
  input logic single_i,
  input fattr_t attr_i,
  input logic [2:0] rm_i,
  input fop_e op_i,
  input reg_t op1_i,
  output reg_t result_o,
  output fflags_t flags_o,
  output logic ready_o,
  output logic valid_o
);
  localparam BP = 64;
  localparam MP = BP + 5;
  localparam DN = 30;
  localparam SN = 24;
  localparam SEL_BITS = 12;

  // verilog_format: off
  typedef enum { SB, S1, S2, S3, S4, SE } state_e;
  // verilog_format: on

  typedef struct packed {
    logic sign;
    logic signed [11:0] exp;
    logic [52:0] manti;  // hidden-1bit, frac-52bit
  } funpack_t;

  function automatic int clz(logic [52:0] val);
    int i;
    for (i = 52; i >= 0; i--) if (val[i] != 1'b0) break;
    return 52 - i;
  endfunction

  function automatic ffast_t check_fastpath(reg_t v1, fattr_t a1);
    ffast_t res = '{valid: 1, default: 0};
    logic sign = single_i ? v1[31] : v1[63];
    `LOGI($sformatf("v:%h a:%b", v1, a1));

    if (a1.NAN) begin
      if (a1.SNAN) begin
        res.flags.nv = 1;
      end
      res.result = v1 | (64'b1 << (single_i ? 22 : 51));
      return res;
    end

    if ((a1.INF && !sign) || a1.ZERO) begin
      res.result = v1;
      return res;
    end

    if (sign) begin
      res.flags.nv = 1;
      res.result   = `FP_CQNAN(single_i);
      return res;
    end

    res.valid = 0;
    return res;
  endfunction

  function automatic funpack_t unpack(reg_t v, fattr_t a);
    funpack_t res = '{default: 0};
    int lz = 0;
    res.sign = single_i ? v[31] : v[63];
    if (a.SUBN) begin
      res.manti = single_i ? {1'b0, v[22:0], 29'b0} : {1'b0, v[51:0]};
      lz = clz(res.manti);
      res.exp = 11'sd1 - 11'(lz);
      res.manti = res.manti <<< lz;
    end else begin
      res.exp   = single_i ? {4'b0, v[30:23]} : {1'b0, v[62:52]};
      res.manti = single_i ? {1'b1, v[22:0], 29'b0} : {1'b1, v[51:0]};
    end
    `LOGI($sformatf("s:%b e:%0d m:%0h", res.sign, res.exp, res.manti));
    return res;
  endfunction

  function automatic logic signed [MP-1:0] multi_s(logic signed [2:0] sfac, logic signed [MP-1:0] f);
    unique case (sfac)
      3'sd0:   return MP'(0);
      3'sd1:   return f;
      3'sd2:   return f <<< 1;
      -3'sd1:  return (~f) + MP'(1);
      -3'sd2:  return (~(f <<< 1) + MP'(1));
      default: return MP'(0);
    endcase
  endfunction
  function automatic logic [2:0] select_s(logic signed [MP-1:0] fr4, logic signed [MP-1:0] partial_s, int shift);
    localparam BITS = SEL_BITS;
    logic signed [2:0] candidates[3];
    logic signed [2:0] fit;
    logic signed [MP-1:0] new_s;
    logic signed [MP-1:0] v1, v2, delta, best_delta;

    if (partial_s == MP'(0)) begin
      return 3'd0;
    end

    if (fr4 >= MP'(0)) begin
      candidates = {3'sd0, 3'sd1, 3'sd2};
    end else begin
      candidates = {3'sd0, -3'sd1, -3'sd2};
    end

    best_delta = {1'b0, {(MP - 1) {1'b1}}};
    foreach (candidates[i]) begin
      if (shift >= 0) begin
        new_s = partial_s + (MP'(candidates[i]) <<< shift);
      end else begin
        new_s = partial_s;
      end

      v1 = fr4 >>> (BP - BITS);
      v2 = new_s >>> (BP - BITS);
      delta = v1 - multi_s(candidates[i], v2);
      if (delta < 0) begin
        delta = -delta;
      end
      if (best_delta > delta) begin
        best_delta = delta;
        fit = candidates[i];
      end
    end

    return fit;
  endfunction

  // fastpath > unpack > prepare > iterate SRT-radix4 > get root > normalize
  // > round > pack

  // FSM
  state_e state;
  ffast_t fast;
  logic iterate_end;

  always_comb begin
    funpack_t u1;
    fflags_t flags;
    logic G, R, S, L, rndup, root_adj;
    logic signed [11:0] exp, real_e;
    logic [51:0] manti;
    logic signed [MP-1:0] rem, rem_4x, root, root_2x, root_s, inc, mq;
    logic signed [2:0] sfactor;
    int counter, max_counter, shift;

    unique case (state)
      SB: begin
        fast = '0;
        iterate_end = 0;
        root_adj = 0;
      end
      S1: begin
        fast = check_fastpath(op1_i, attr_i);
        `LOGI($sformatf("fsqrt %.16e, fast:%b", $bitstoreal(op1_i), fast.valid));
        if (!fast.valid) begin
          u1 = unpack(op1_i, attr_i);
        end
      end
      S2: begin
        // prepare
        real_e = 12'(u1.exp) - (single_i ? 12'sd127 : 12'sd1023);
        exp = (real_e >>> 1) + (single_i ? 12'sd127 : 12'sd1023);
        rem = MP'(u1.manti) <<< (BP - 52);
        root = MP'(1) <<< BP;
        if (real_e[0]) begin
          rem = rem >>> 1;
          sfactor = u1.manti[51] == 1'b1 ? 3'sd0 : -3'sd1;
        end else begin
          rem = rem >>> 2;
          sfactor = u1.manti[51] == 1'b1 ? -3'sd1 : -3'sd2;
        end
        rem -= (MP'(1) <<< BP);
        root += (MP'(sfactor) << (BP - 2));
        root_s = MP'(2 << BP) + MP'(sfactor <<< (BP - 2));
        rem = (rem <<< 2) - multi_s(sfactor, root_s);
        counter = 0;
        max_counter = single_i ? SN : DN;
        iterate_end = 0;
        flags = '0;
        // `LOGI($sformatf("rem: %0d root:%0d", rem, root));
      end
      S3: begin
        // iterate
        counter += 1;
        shift = BP - ((counter + 1) << 1);
        rem_4x = rem <<< 2;
        root_2x = root <<< 1;
        sfactor = select_s(rem_4x, root_2x, shift);
        inc = (shift >= 0 ? MP'(sfactor) << shift : '0);
        root_s = root_2x + inc;
        rem = rem_4x - multi_s(sfactor, root_s);
        root += inc;
        `LOGI($sformatf("root:%0d sfactor:%0d, inc:%0d", root, sfactor, inc));
        iterate_end = counter >= max_counter;
      end
      S4: begin
        // adjustment root
        if (rem[MP-1]) begin
          root = root - (MP'(1) << 4);
          `LOGW($sformatf("adjust root to:%h", root));
          root_adj = 1;
        end

        // normalize
        root = root <<< 1;
        mq = root - (1 << BP);
        G = single_i ? mq[BP-24] : mq[BP-53];
        R = single_i ? mq[BP-25] : mq[BP-54];
        S = single_i ? |mq[BP-26:0] : |mq[BP-55:0];
        L = single_i ? mq[BP-23] : mq[BP-52];

        rndup = frndup(G, R, S, L, u1.sign, frm_e'(rm_i));
        `LOGW($sformatf("mq:%h rem:%h", mq, rem));
        manti = single_i ? {29'b0, mq[BP-1:BP-23]} : mq[BP-1:BP-52];
        if (rndup) begin
          if (manti == `ONES(52)) begin
            exp += 1;
          end
          manti += 52'b1;
        end
        flags.nx = (G | R | S | root_adj | rem != '0);
      end
      SE: begin
        if (fast.valid) begin
          `LOGI($sformatf("fast:%h", fast.result));
          result_o = fast.result;
          flags_o  = fast.flags;
        end else begin
          if (single_i) begin
            result_o = {32'hffffffff, u1.sign, exp[7:0], manti[22:0]};
          end else begin
            result_o = {u1.sign, exp[10:0], manti};
          end
          `LOGI($sformatf("result:%.16e, e:%0d, m:%h", $bitstoreal(result_o), exp, manti));
          flags_o = flags;
        end
      end
      default: ;
    endcase
  end

  assign ready_o = (state == SE || !valid);
  assign valid_o = valid;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= SB;
    end else begin
      if (valid) begin
        unique case (state)
          SB: state <= S1;
          S1: state <= fast.valid ? SE : S2;
          S2: state <= S3;
          S3: state <= iterate_end ? S4 : S3;
          S4: state <= SE;
          SE: state <= SB;
        endcase
      end
    end
  end

endmodule

//------------------------------------
// fma
//------------------------------------
module fma (
  input logic clk,
  input logic rst_n,
  input logic valid,
  input logic single_i,
  input fattr_t attr_i[3],
  input logic [2:0] rm_i,
  input fop_e op_i,
  input reg_t op1_i,
  input reg_t op2_i,
  input reg_t op3_i,
  output reg_t result_o,
  output fflags_t flags_o,
  output logic ready_o,
  output logic valid_o
);
  // verilog_format: off
  typedef enum { SB, S1, S2, S3, S4, SE } state_e;
  // verilog_format: on

  typedef struct packed {
    logic sign;
    logic signed [12:0] exp;
    logic [52:0] manti;
  } funpacked_t;

  typedef struct packed {
    logic sign;
    logic signed [12:0] exp;
    logic [105:0] manti;
  } fmul_t;

  typedef struct packed {
    logic sign, sticky;
    logic signed [12:0] exp;
    logic [108:0] manti;
  } fadd_t;

  typedef struct packed {
    logic sign;
    logic [10:0] exp;
    logic [51:0] frac;
    fflags_t flags;
  } fnorm_t;

  // fastpath > unpack > multiply > alignment > add > roundup > normalize > pack

  // FSM
  state_e state;
  ffast_t fast;

  function automatic int clz(logic [52:0] val);
    int i;
    for (i = 52; i >= 0; i--) if (val[i] != 1'b0) break;
    return 52 - i;
  endfunction

  function automatic funpacked_t funpacked(logic single, reg_t v, fattr_t a);
    funpacked_t res;
    int lz = 0;
    res = '0;
    res.sign = `fp_sign(single, v);
    if (a.SUBN) begin
      res.exp = 13'sd1;
      res.manti = `fp_subn_manti(single, v);
      lz = clz(res.manti);
      if (lz > 0) begin
        res.exp -= 13'(lz);
        res.manti = res.manti << lz;
      end
    end else if (a.ZERO) begin
      res.exp   = '0;
      res.manti = '0;
    end else begin
      res.exp   = `fp_exp(single, v, 13);
      res.manti = `fp_manti(single, v);
    end
    `LOGI($sformatf("s:%b e:%0d m:%h", res.sign, res.exp, res.manti));
    return res;
  endfunction

  // fastcheck: INF, ZERO, NAN(SNAN, QNAN), SUBN
  function automatic ffast_t check_fastpath();
    ffast_t res = '{valid: 1, default: 0};
    fattr_t a1, a2, a3, a12;
    logic s1, s2, s3, s12;
    logic nan, snan, zxi, ixi, prod_inf, prod_zero, nv;
    reg_t op12 = '0;

    `LOGI($sformatf("v1:%h v2:%h v3:%h a:%b %b %b", op1_i, op2_i, op3_i, a1, a2, a3));
    {s1, s2, s3} = single_i ? {op1_i[31], op2_i[31], op3_i[31]} : {op1_i[63], op2_i[63], op3_i[63]};
    {a1, a2, a3} = {attr_i[0], attr_i[1], attr_i[2]};
    nv = 0;
    a12 = '0;

    // verilog_format: off
    unique case (op_i)
      FOP_MADD: begin s12 = 0 + (s1^s2); s3 = 0 + s3; end
      FOP_MSUB: begin s12 = 0 + (s1^s2); s3 = 1 + s3; end
      FOP_NMADD: begin s12 = 1 + (s1^s2); s3 = 1 + s3; end
      FOP_NMSUB: begin s12 = 1 + (s1^s2); s3 = 0 + s3; end
      default: ;
    endcase
    // verilog_format: on

    // calculate a x b
    if (a1.NAN | a2.NAN) begin
      a12.NAN = 1;
      if (a1.SNAN | a2.SNAN) begin
        nv   = 1;
        op12 = a1.SNAN ? op1_i : op2_i;
      end else begin
        op12 = a1.NAN ? op1_i : op2_i;
      end
      `fp_quiet(single_i, op12);
    end else if (a1.INF | a2.INF) begin
      if ((a1.INF && a2.ZERO) || (a2.INF && a1.ZERO)) begin
        op12 = `FP_CQNAN(single_i);
        nv = 1;
        a12.NAN = 1;
      end else if (a1.INF | a2.INF) begin
        op12 = `fp_inf(single_i, s12);
        a12.INF = 1;
      end
    end else if (a1.ZERO | a2.ZERO) begin
      a12.ZERO = 1;
      op12 = `fp_zero(single_i, s12);
    end

    if (a12.INF | a12.ZERO | a12.NAN | a3.INF | a3.NAN) begin
      if (a12.NAN | a3.NAN) begin
        if (a3.SNAN) begin
          nv = 1;
        end
        res.result = a3.SNAN ? op3_i : (a12.NAN ? op12 : op3_i);
        `fp_quiet(single_i, res.result);
      end else if (a12.INF | a3.INF) begin
        if (a12.INF & a3.INF) begin
          if (s12 != s3) begin
            nv = 1;
            res.result = `FP_CQNAN(single_i);
          end else begin
            res.result = op12;
          end
        end else begin
          res.result = a12.INF ? op12 : `fp_inf(single_i, s3);
        end
      end else if (a12.ZERO) begin
        res.result = `fp_mkval(single_i, s3, op3_i);
        if (a3.ZERO) begin
          if (s12 != s3) begin
            res.result = `fp_zero(single_i, 1'b0);
          end
        end
      end
      res.flags.nv = nv;
      return res;
    end

    res.valid = 0;
    return res;
  endfunction

  function automatic fmul_t multiply(funpacked_t u1, u2);
    fmul_t res = '{default: 0};
    res.sign  = u1.sign ^ u2.sign;
    res.exp   = u1.exp + u2.exp - (single_i ? 13'd127 : 13'd1023);
    res.manti = u1.manti * u2.manti;
    `LOGI($sformatf("s:%b e:%0d m:%0h", res.sign, $signed(res.exp), res.manti));
    return res;
  endfunction

  function automatic fadd_t madd(fmul_t m, funpacked_t u3);
    fadd_t res = '{default: 0};
    logic signed [12:0] exp, diff;
    logic [108:0] m1, m2;  // HHH.FFF...FFGR
    logic s = 0;
    logic s1, s2;  // sign of operator 1&2;

    // verilog_format: off
    unique case (op_i)
      FOP_MADD: begin s1 = 0 + m.sign; s2 = 0 + u3.sign; end
      FOP_MSUB: begin s1 = 0 + m.sign; s2 = 1 + u3.sign; end
      FOP_NMADD: begin s1 = 1 + m.sign; s2 = 1 + u3.sign; end
      FOP_NMSUB: begin s1 = 1 + m.sign; s2 = 0 + u3.sign; end
      default: ;
    endcase
    // verilog_format: on

    // align exponent of m and u3
    if ($signed(m.exp) >= $signed(13'(u3.exp))) begin
      diff = $signed(m.exp) - $signed(13'(u3.exp));
      exp = m.exp;
      m1 = {1'b0, m.manti[105:0], 2'b0};
      m2 = {2'b0, u3.manti, 52'b0, 2'b0};
      s = `OR_NBITS(m2, diff);
      m2 = m2 >> diff;
      m2[0] |= s;
      `LOGW($sformatf("diff:%0d m.exp=%0d", diff, $signed(m.exp)));
    end else begin
      diff = $signed(13'(u3.exp)) - $signed(m.exp);
      exp = 13'(u3.exp);
      m2 = {2'b0, u3.manti, 52'b0, 2'b0};
      m1 = {1'b0, m.manti[105:0], 2'b0};
      s = `OR_NBITS(m1, diff);
      m1 = m1 >> diff;
      m1[0] |= s;
      `LOGW($sformatf("diff:%0d", diff));
    end

    `LOGI($sformatf("exp:%0d m1:%h m2:%h", exp, m1, m2));

    if (s1 ^ s2) begin
      res.exp = exp;
      if (m1 >= m2) begin
        res.sign  = s1;
        res.manti = m1 - m2;
      end else begin
        res.sign  = s2;
        res.manti = m2 - m1;
      end
    end else begin
      res.sign  = s1;
      res.exp   = exp;
      res.manti = m1 + m2;
    end
    `LOGW($sformatf("exp:%0d manti:%h", res.exp, res.manti));

    res.exp += 2;  // make only one hidden bit;
    res.sticky = s;

    // `LOGI($sformatf("fadd s:%b e:%0d m:%h", res.sign, res.exp, res.manti));
    return res;
  endfunction

  function automatic fnorm_t normalize(fadd_t v);
    fnorm_t res = '{default: 0};
    logic s = v.sticky;
    logic G, R, S, L, rndup, tiny;
    int lz;
    logic [12:0] max_e = single_i ? 13'd255 : 13'd2047;

    if (v.manti == 109'b0) begin
      res.exp  = '0;
      res.frac = '0;
      res.sign = v.sign;
      if (v.sticky) begin
        res.flags.nx = 1'b1;
        res.flags.uf = 1'b1;
      end
    end else begin
      lz = clz(v.manti[108:56]);
      if (lz >= 53) begin
        lz += clz(v.manti[55:3]);
        if (lz >= 106) begin
          if (v.manti[2] == 0) begin
            lz += 1;
            if (v.manti[1] == 0) begin
              lz += 1;
              if (v.manti[0] == 0) begin
                lz += 1;
              end
            end
          end
        end
      end

      if (lz > 0) begin
        v.exp -= 13'(lz);
        v.manti = v.manti << lz;
      end

      tiny = 0;
      if (v.exp <= 0) begin
        tiny = single_i ? v.manti[107:84] != `ONES(24) : v.manti[107:55] != `ONES(53);
        v.manti = v.manti >> (1 - v.exp);
        v.exp = '0;
      end

      if (single_i) begin
        L = v.manti[85];
        G = v.manti[84];
        R = v.manti[83];
        S = (|v.manti[82:0]) | s;
      end else begin
        L = v.manti[56];
        G = v.manti[55];
        R = v.manti[54];
        S = s | (|v.manti[53:0]);
      end

      rndup = frndup(G, R, S, L, v.sign, frm_e'(rm_i));
      res.flags.nx = G | R | S;
      if (tiny && res.flags.nx) begin
        res.flags.uf = 1;
      end
      res.sign = v.sign;
      res.frac = single_i ? {`ONES(29), v.manti[107:85]} : v.manti[107:56];

      `LOGW($sformatf("rndup:%b frac:%h", rndup, res.frac));
      if (rndup) begin
        if (res.frac == `ONES(52)) begin
          res.frac = '0;
          v.exp += 13'sd1;
        end else begin
          res.frac += 52'd1;
        end
      end

      if (v.exp >= max_e) begin
        res.exp = max_e[10:0];
        res.frac = '0;
        res.flags.of = 1;
        res.flags.nx = 1;
      end else begin
        res.exp = v.exp[10:0];
      end
    end
    if (res.exp == '0) begin
      res.flags.uf = res.flags.nx;
    end

    return res;
  endfunction

  function automatic fpacked_t pack(fnorm_t norm);
    fpacked_t res;
    res.flags  = norm.flags;
    res.result = single_i ? {`ONES(32), norm.sign, norm.exp[7:0], norm.frac[22:0]} : {norm.sign, norm.exp, norm.frac};
    return res;
  endfunction

  always_comb begin
    funpacked_t u1, u2, u3;
    fmul_t mul;
    fadd_t ma;
    fnorm_t norm;
    fpacked_t pcked;
    unique case (state)
      SB: begin
        fast = '0;
      end
      S1: begin
        // check fastpath & unpack
        fast = check_fastpath();
        `LOGI($sformatf("fast.valid: %d", fast.valid));
        if (!fast.valid) begin
          u1 = funpacked(single_i, op1_i, attr_i[0]);
          u2 = funpacked(single_i, op2_i, attr_i[1]);
          u3 = funpacked(single_i, op3_i, attr_i[2]);
        end
      end
      S2: mul = multiply(u1, u2);
      S3: begin
        ma = madd(mul, u3);
      end
      S4: begin
        norm = normalize(ma);
      end
      SE: begin
        if (fast.valid) begin
          result_o = fast.result;
          flags_o  = fast.flags;
        end else begin
          pcked = pack(norm);
          result_o = pcked.result;
          flags_o = pcked.flags;
        end
      end
      default: ;
    endcase
  end

  assign ready_o = (state == SE || !valid);
  assign valid_o = valid;

  // FSM
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= SB;
    end else begin
      if (valid) begin
        unique case (state)
          SB: state <= S1;
          S1: state <= fast.valid ? SE : S2;
          S2: state <= S3;
          S3: state <= S4;
          S4: state <= SE;
          SE: state <= SB;
        endcase
      end
    end
  end

endmodule

//------------------------------------
// mv
//------------------------------------
module fmv (
  input  logic clk,
  input  logic rst_n,
  input  logic valid,
  input  logic single_i,
  input  fop_e op_i,
  input  reg_t op1_i,
  output reg_t result_o,
  output logic ready_o,
  output logic valid_o
);

  always_comb begin
    ready_o = valid;
  end

  always_comb begin
    valid_o  = valid;
    result_o = '0;
    if (valid) begin
      unique case (op_i)
        FOP_MV_X_F: begin
          `LOGI($sformatf("f2x:0x%0h single:%b", op1_i, single_i));
          result_o = single_i ? {{32{op1_i[31]}}, op1_i[31:0]} : op1_i;
        end
        FOP_MV_F_X: begin
          `LOGI($sformatf("x2f:0x%0h single:%b", op1_i, single_i));
          result_o = single_i ? {`ONES(32), op1_i[31:0]} : op1_i;
        end
        default: ;
      endcase
    end
  end

endmodule

//------------------------------------
// convert
//------------------------------------
module fcvt (
  input logic clk,
  input logic rst_n,
  input logic valid,
  input logic single_i,
  input fop_e op_i,
  input reg_t op1_i,
  input fattr_t attr_i,
  input logic [2:0] rm_i,
  output reg_t result_o,
  output fflags_t flags_o,
  output logic ready_o,
  output logic valid_o
);

  typedef struct packed {
    reg_t result;
    fflags_t flags;
  } fconvert_t;

  function automatic int clz(logic [63:0] val, int effective_bits);
    int i;
    for (i = 63; i >= 64 - effective_bits; i--) begin
      if (val[i]) break;
    end
    return 63 - i;
  endfunction

  function automatic fconvert_t s2d();
    // INF, ZERO, NAN(QNaN, SNaN), SUBN
    fconvert_t res = '{default: 0};
    int lz = 0;
    logic [22:0] frac;

    `LOGI($sformatf("s2d: %h attr:%b", op1_i, attr_i));

    if (attr_i.INF) begin
      res.result = {op1_i[31], 11'h7FF, 52'b0};
    end else if (attr_i.NAN) begin
      if (attr_i.SNAN) begin
        res.flags.nv = 1;
        res.result   = {op1_i[31], 11'h7ff, 1'b1, op1_i[21:0], 29'b0};  // change to QNaN
      end else begin
        res.result = {op1_i[31], 11'h7ff, op1_i[22:0], 29'b0};
      end
    end else if (attr_i.ZERO) begin
      res.result = {op1_i[31], 11'b0, 52'b0};
    end else if (attr_i.SUBN) begin
      // subnormal
      lz   = clz({op1_i[22:0], 41'b0}, 23);
      frac = op1_i[22:0] << (lz + 1);
      `LOGW($sformatf("frac:%h lz:%0d", frac, lz));
      res.result = {op1_i[31], 11'd896 - 11'(lz), frac, 29'b0};
    end else begin
      // normal
      res.result = {op1_i[31], 11'(op1_i[30:23]) + 11'd896, {op1_i[22:0], 29'b0}};
    end
    return res;
  endfunction

  function automatic fconvert_t d2s();
    fconvert_t res = '{default: 0};
    logic signed [11:0] exp = {1'b0, op1_i[62:52]};
    logic [22:0] frac = op1_i[51:29];
    logic [52:0] manti = {1'b1, op1_i[51:0]};
    logic G, R, S, L, rndup, s;
    exp -= 12'sd1023;
    `LOGI($sformatf("d2s: e:%0d %h attr:%b", exp, op1_i, attr_i));

    if (attr_i.INF) begin
      res.result = {`ONES(32), op1_i[63], 8'hff, 23'b0};
    end else if (attr_i.ZERO) begin
      res.result = {`ONES(32), op1_i[63], 8'h00, 23'b0};
    end else if (attr_i.NAN) begin
      if (attr_i.SNAN) begin
        res.flags.nv = 1;
      end
      res.result = {`ONES(32), op1_i[63], 8'hff, 1'b1, op1_i[50:29]};
    end else if (exp < -12'sd126) begin
      // TODO
      exp = -12'sd127 - exp;
      s = `OR_NBITS(manti, exp);
      manti = manti >> exp;
      L = manti[30];
      G = manti[29];
      R = manti[28];
      S = |manti[27:0];
      S = S | s;

      exp = '0;
      rndup = frndup(G, R, S, L, op1_i[63], frm_e'(rm_i));
      if (rndup) begin
        if (manti[52:30] == `ONES(23)) begin
          exp += 12'sd1;
          manti = '0;
        end else begin
          manti[52:30] += 23'd1;
        end
      end
      res.flags.nx = G | R | S;
      res.flags.uf = (exp == '0 && res.flags.nx);
      res.result   = {`ONES(32), op1_i[63], exp[7:0], manti[52:30]};
    end else if (exp > 12'sd127) begin
      res.result   = {`ONES(32), op1_i[63], 8'hff, 23'b0};
      res.flags.nx = 1;
      res.flags.of = 1;
    end else begin
      //normal data
      L = op1_i[29];
      G = op1_i[28];
      R = op1_i[27];
      S = |op1_i[26:0];
      exp += 12'd127;

      rndup = frndup(G, R, S, L, op1_i[63], frm_e'(rm_i));
      if (rndup) begin
        if (frac == `ONES(23)) begin
          frac = '0;
          exp += 1;
        end else begin
          frac += 23'd1;
        end
      end
      res.flags.nx = G | S;
      res.flags.of = exp > 12'd254;
      res.result   = {`ONES(32), op1_i[63], exp[7:0], frac};
      `LOGI($sformatf("e:%0d, f:%h", exp[7:0], frac));
    end
    return res;
  endfunction

  // i32|i64|u32|u64 -> s|d
  function automatic fconvert_t i2d(logic isigned, logic l);
    fconvert_t res = '{default: 0};
    reg_t val;
    logic sign, rndup, G, R, S, L;
    int lz;
    logic [10:0] exp;
    logic [51:0] frac;

    sign = isigned ? op1_i[63] : 0;
    val  = (isigned && op1_i[63]) ? -op1_i : op1_i;
    val  = l ? val : {val[31:0], 32'b0};
    lz   = clz(val, l ? 64 : 32);
    exp  = l ? 11'd63 - 11'(lz) : 11'd31 - 11'(lz);
    exp += (single_i ? 11'd127 : 11'd1023);

    if (op1_i == 64'b0) begin
      res.result = single_i ? {`ONES(32), 32'b0} : '0;
    end else begin
      val = val << (lz + 1);
      if (single_i) begin
        frac = {`ONES(29), val[63:41]};
        L = val[41];
        G = val[40];
        R = val[39];
        S = |val[38:0];
      end else begin
        frac = val[63:12];
        L = val[12];
        G = val[11];
        R = val[10];
        S = |val[9:0];
      end

      rndup = frndup(G, R, S, L, sign, frm_e'(rm_i));
      if (rndup) begin
        if (frac == `ONES(52)) begin
          frac = '0;
          exp += 1;
        end else begin
          frac += 52'd1;
        end
      end
      if (single_i) begin
        frac = {29'b0, frac[22:0]};
      end
      res.flags.nx = G | S;
      res.result   = single_i ? {`ONES(32), sign, exp[7:0], frac[22:0]} : {sign, exp, frac};
    end

    `LOGI($sformatf("isgn:%b (%0d) s:%b e:%0d f:%h", isigned, $signed(op1_i), sign, exp, frac));
    return res;
  endfunction

  localparam I64_MAX = 64'h7FFF_FFFF_FFFF_FFFF;
  localparam I32_MAX = 64'h0000_0000_7FFF_FFFF;
  localparam I64_MIN = 64'h8000_0000_0000_0000;
  localparam I32_MIN = 64'hFFFF_FFFF_8000_0000;
  localparam U64_MAX = 64'hFFFF_FFFF_FFFF_FFFF;
  localparam U32_MAX = 64'h0000_0000_FFFF_FFFF;

  // s|d -> u32|u64|i32|i64
  function automatic fconvert_t d2i(logic isigned, logic l);
    // INF, ZERO, NAN(QNaN, SNaN), SUBN, max_e(-+)
    fconvert_t res = '{default: 0};
    logic fsign = `fp_sign(single_i, op1_i);
    logic signed [11:0] exp = `fp_exp(single_i, op1_i, 12), shift;
    logic signed [11:0] max_e = l ? (isigned ? 12'd63 : 12'd64) : (isigned ? 12'd31 : 12'd32);
    logic [51:0] frac;
    reg_t ires;
    logic G, R, S, L, rndup;

    // integer(64bits) + frac(52bits) + GR
    logic [65:0] data = '0;
    data = {1'b0, `fp_manti(single_i, op1_i), 10'b0, 2'b0};
    exp -= `fp_bias(single_i, 12);

    `LOGI($sformatf("v:%h a:%b e:%0d max_e:%0d isigned:%b", op1_i, attr_i, exp, max_e, isigned));
    if (attr_i.ZERO) begin
      if (!isigned && fsign) begin
        res.flags = '{default: 0};
      end
    end else if (attr_i.NAN) begin
      res.flags  = '{nv: 1'b1, default: 0};
      res.result = '0;
    end else if (attr_i.INF || exp >= max_e) begin
      res.flags = '{nv: 1'b1, default: 0};
      // -2^max_e is valid, but 2^max_e is overflow, 2^max_e - 1 is valid;
      if (!attr_i.INF && fsign && exp == max_e) begin
        frac = `fp_frac(single_i, op1_i);
        if ((|(frac >> (12'sd52 - exp))) == 0) begin
          res.flags.nv = ~isigned;
          res.flags.nx = !res.flags.nv && (|frac) == 1'b1;
        end
      end
      if (fsign) begin
        res.result = l ? (isigned ? I64_MIN : 64'b0) : (isigned ? I32_MIN : 64'b0);
      end else begin
        res.result = l ? (isigned ? I64_MAX : U64_MAX) : (isigned ? I32_MAX : U32_MAX);
      end
    end else begin
      // normal data
      shift = 12'd62 - exp;
      if (shift >= 65) begin
        S = |data;
      end else begin
        S = (shift > 0 ? `OR_NBITS(data, shift) : 0);
      end
      data = (shift > 0 ? data >> shift : data << -shift);
      ires = data[65:2];
      L = data[2];
      G = data[1];
      R = data[0];

      rndup = frndup(G, R, S, L, fsign, frm_e'(rm_i));
      res.flags.nx = G | R | S;

      `LOGW($sformatf("ires:%h rndup:%b", ires, rndup));
      if (rndup) begin
        if (!fsign && ires == (l ? (isigned ? I64_MAX : U64_MAX) : (isigned ? I32_MAX : U32_MAX))) begin
          res.flags.nv = 1;
          res.flags.nx = 0;
        end else begin
          ires += 1;
        end
      end
      if (fsign && !isigned) begin
        if (ires != 64'b0) begin
          res.flags.nv = 1;
          res.flags.nx = 0;
        end
      end
      res.result = fsign ? (isigned ? -ires : 64'b0) : ires;
      if (!l) begin
        res.result = isigned ? {{32{res.result[31]}}, res.result[31:0]} : {32'b0, res.result[31:0]};
      end
    end

    return res;
  endfunction

  always_comb begin
    ready_o = valid;
  end

  always_comb begin
    fconvert_t res;
    valid_o  = 0;
    result_o = '0;
    flags_o  = '0;
    res      = '0;
    if (valid) begin
      unique case (op_i)
        FOP_CVT_W_F: begin
          res = d2i(1, 0);
          {result_o, flags_o, valid_o} = {res.result, res.flags, 1'b1};
        end
        FOP_CVT_WU_F: begin
          res = d2i(0, 0);
          {result_o, flags_o, valid_o} = {res.result, res.flags, 1'b1};
        end
        FOP_CVT_L_F: begin
          res = d2i(1, 1);
          {result_o, flags_o, valid_o} = {res.result, res.flags, 1'b1};
        end
        FOP_CVT_LU_F: begin
          res = d2i(0, 1);
          {result_o, flags_o, valid_o} = {res.result, res.flags, 1'b1};
        end
        FOP_CVT_F_W: begin
          res = i2d(1, 0);
          {result_o, flags_o, valid_o} = {res.result, res.flags, 1'b1};
        end
        FOP_CVT_F_WU: begin
          res = i2d(0, 0);
          {result_o, flags_o, valid_o} = {res.result, res.flags, 1'b1};
        end
        FOP_CVT_F_L: begin
          res = i2d(1, 1);
          {result_o, flags_o, valid_o} = {res.result, res.flags, 1'b1};
        end
        FOP_CVT_F_LU: begin
          res = i2d(0, 1);
          {result_o, flags_o, valid_o} = {res.result, res.flags, 1'b1};
        end
        FOP_CVT_S_D: begin
          res = d2s();
          {result_o, flags_o, valid_o} = {res.result, res.flags, 1'b1};
        end
        FOP_CVT_D_S: begin
          res = s2d();
          {result_o, flags_o, valid_o} = {res.result, res.flags, 1'b1};
        end
        default: valid_o = 0;
      endcase
    end
  end

endmodule

//------------------------------------
// min max
//------------------------------------
module fmax (
  input logic clk,
  input logic rst_n,
  input logic valid,
  input logic single_i,
  input fop_e op_i,
  input reg_t op1_i,
  input reg_t op2_i,
  input fattr_t attr_i[2],
  output reg_t result_o,
  output fflags_t flags_o,
  output logic ready_o,
  output logic valid_o
);

  always_comb begin
    ready_o = valid;
  end

  function automatic logic less_than();
    // INF, ZERO, NAN(QNaN, SNaN), SUBN
    logic res;
    logic [1:0] sign = {`fp_sign(single_i, op1_i), `fp_sign(single_i, op2_i)};
    reg_t val1, val2;
    val1 = `fp_abs64(single_i, op1_i);
    val2 = `fp_abs64(single_i, op2_i);
    unique case (sign)
      2'b00:   res = (val1 < val2);
      2'b11:   res = (val1 > val2);
      2'b10:   res = 1;
      2'b01:   res = 0;
      default: res = 0;
    endcase
    `LOGI($sformatf("%h %h lessthan :%b", op1_i, op2_i, res));
    return res;
  endfunction

  always_comb begin
    logic idx, nan;
    valid_o  = valid;
    result_o = '0;
    flags_o  = '0;
    if (valid) begin
      unique case (op_i)
        FOP_MIN: begin
          // flags_o.nv = attr_i[0].SNAN | attr_i[1].SNAN;
          `LOGI($sformatf("fmin: %h %h", op1_i, op2_i));
          nan = attr_i[0].NAN | attr_i[1].NAN;
          if (nan) begin
            `LOGI($sformatf("%b %b", attr_i[0].NAN, attr_i[1].NAN));
            idx = attr_i[0].NAN ? 1 : 0;
          end else begin
            idx = ~less_than();
          end
          `LOGI($sformatf("fmin:%b", idx));
          result_o = idx == 0 ? op1_i : op2_i;
          if (attr_i[0].SNAN | attr_i[1].SNAN) begin
            flags_o.nv = 1;
          end
          if (attr_i[0].NAN & attr_i[1].NAN) begin
            result_o = `FP_CQNAN(single_i);
          end
        end
        FOP_MAX: begin
          `LOGI($sformatf("fax: %h %h", op1_i, op2_i));
          nan = attr_i[0].NAN | attr_i[1].NAN;
          if (nan) begin
            `LOGI($sformatf("%b %b", attr_i[0].NAN, attr_i[1].NAN));
            idx = attr_i[0].NAN ? 1 : 0;
          end else begin
            idx = less_than();
          end

          `LOGI($sformatf("fmax:%b sana:%b %b", idx, attr_i[0].SNAN, attr_i[1].SNAN));
          result_o = idx == 0 ? op1_i : op2_i;
          if (attr_i[0].SNAN | attr_i[1].SNAN) begin
            flags_o.nv = 1;
          end
          if (attr_i[0].NAN & attr_i[1].NAN) begin
            result_o = `FP_CQNAN(single_i);
          end
        end
        default: ;
      endcase
    end
  end

endmodule

//------------------------------------
// fclass
//------------------------------------
module fclass (
  input logic clk,
  input logic rst_n,
  input logic valid,
  input logic single_i,
  input fop_e op_i,
  input reg_t op1_i,
  input fattr_t attr_i,
  output reg_t result_o,
  output fflags_t flags_o,
  output logic ready_o,
  output logic valid_o
);

  typedef struct packed {
    logic qnan;
    logic snan;
    logic positive_inf;
    logic positive_normal;
    logic positive_subnormal;
    logic positive_zero;
    logic negative_zero;
    logic negative_subnormal;
    logic negative_normal;
    logic negative_inf;
  } fclassify_t;

  always_comb begin
    ready_o = valid;
  end

  function automatic fclassify_t classify();
    fclassify_t res = '{default: 0};
    logic sign = `fp_sign(single_i, op1_i);
    res.qnan = attr_i.QNAN;
    res.snan = attr_i.SNAN;
    res.positive_inf = attr_i.INF && sign == 0;
    res.negative_inf = attr_i.INF && sign == 1;
    res.positive_zero = attr_i.ZERO && sign == 0;
    res.negative_zero = attr_i.ZERO && sign == 1;
    res.positive_subnormal = attr_i.SUBN && sign == 0;
    res.negative_subnormal = attr_i.SUBN && sign == 1;

    if (res == 10'b0) begin
      res.positive_normal = sign == 0;
      res.negative_normal = sign == 1;
    end

    `LOGI($sformatf("fclass: %b", res));
    return res;
  endfunction

  always_comb begin
    valid_o  = valid;
    result_o = '0;
    if (valid) begin
      unique case (op_i)
        FOP_CLASS: result_o = {54'b0, classify()};
        default:   ;
      endcase
    end
  end
endmodule

//------------------------------------
// fsgnj
//------------------------------------
module fsgnj (
  input logic clk,
  input logic rst_n,
  input logic valid,
  input logic single_i,
  input fop_e op_i,
  input reg_t op1_i,
  input reg_t op2_i,
  input fattr_t attr_i[2],
  output reg_t result_o,
  output fflags_t flags_o,
  output logic ready_o,
  output logic valid_o
);

  always_comb begin
    ready_o = valid;
  end

  always_comb begin
    logic s1, s2, s;
    reg_t v1, v2;
    valid_o = valid;

    if (valid) begin
      `LOGI($sformatf("sgnj: %h %h", op1_i, op2_i));
      v1 = op1_i;
      v2 = op2_i;
      if (single_i) begin
        if (!`BOXED_F32(op1_i)) begin
          v1 = CQNAN_S;
        end
        if (!`BOXED_F32(op2_i)) begin
          v2 = CQNAN_S;
        end
      end
      s1 = `fp_sign(single_i, v1);
      s2 = `fp_sign(single_i, v2);
      unique case (op_i)
        FOP_SGNJ:  s = s2;
        FOP_SGNJX: s = s1 ^ s2;
        FOP_SGNJN: s = ~s2;
        default:   ;
      endcase
      result_o = single_i ? {`ONES(32), s, v1[30:0]} : {s, v1[62:0]};
      flags_o  = '0;
    end
  end

endmodule

//------------------------------------
// float compare
//------------------------------------
module fcmp (
  input logic clk,
  input logic rst_n,
  input logic valid,
  input logic single_i,
  input fattr_t attr_i[2],
  input fop_e op_i,
  input reg_t op1_i,
  input reg_t op2_i,
  output reg_t result_o,
  output fflags_t flags_o,
  output logic ready_o,
  output logic valid_o
);

  always_comb begin
    ready_o = 1;
  end

  logic rst;
  logic nan, snan, all_zero;

  logic [1:0] sign;
  reg_t val1, val2;

  always_comb begin
    valid_o = 0;
    if (valid) begin
      valid_o = 1;
      flags_o = '0;
      rst = 0;

      nan = attr_i[0].NAN | attr_i[1].NAN;
      snan = attr_i[0].SNAN | attr_i[1].SNAN;
      all_zero = attr_i[0].ZERO && attr_i[1].ZERO;

      if (single_i) begin
        if (!`BOXED_F32(op1_i) || !`BOXED_F32(op2_i)) begin
          nan = 1;
        end
      end
      sign = {`fp_sign(single_i, op1_i), `fp_sign(single_i, op2_i)};
      val1 = `fp_abs64(single_i, op1_i);
      val2 = `fp_abs64(single_i, op2_i);

      unique case (op_i)
        FOP_CMP_EQ: begin
          `LOGI($sformatf("feq(single:%b):%h %h", single_i, op1_i, op2_i));
          if (nan) begin
            rst = 0;
            if (snan) begin
              flags_o.nv = 1;
            end
          end else begin
            rst = ((val1 == val2 && (sign == 2'b00 || sign == 2'b11)) | all_zero);
          end
        end

        FOP_CMP_LE: begin
          `LOGI($sformatf("fle:%h %h", op1_i, op2_i));
          if (nan) begin
            rst = 0;
            flags_o.nv = 1;
          end else if (all_zero) begin
            rst = 1;
          end else begin
            unique case (sign)
              2'b00:   rst = (val1 <= val2);
              2'b11:   rst = (val1 >= val2);
              2'b10:   rst = 1;
              2'b01:   rst = 0;
              default: rst = 0;
            endcase
          end
        end

        FOP_CMP_LT: begin
          `LOGI($sformatf("flt:%h %h", op1_i, op2_i));
          if (nan) begin
            rst = 0;
            flags_o.nv = 1;
          end else if (all_zero) begin
            rst = 0;
          end else begin
            unique case (sign)
              2'b00:   rst = (val1 < val2);
              2'b11:   rst = (val1 > val2);
              2'b10:   rst = 1;
              2'b01:   rst = 0;
              default: rst = 0;
            endcase
          end
        end

        default: begin
          valid_o = 0;
          rst = 0;
        end
      endcase
      result_o = {63'b0, rst};
    end
  end

endmodule

/******************************************************************************/
