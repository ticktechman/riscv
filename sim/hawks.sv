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


// `define DEBUG_LOG

//------------------------------------
// types and structures
//------------------------------------
package hawks;
  localparam int unsigned MASTER_CNT = 3;
  localparam int unsigned SLAVE_CNT = 7;
  localparam int unsigned REGMAX = 32;
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
  `define WU2I(r, a) {r[a+3], r[a+2], r[a+1], r[a]}
  `define write_data(r, off, data, sz) for (idx_t i = 0; i < sz; i++) r[off+i] <= data[8*i+:8]

  `define overlap(s1, t1, s2, t2) ((s1>=s2 && s1<=s2+databytes(t2)) || (s2>=s1 && s2<s1+databytes(t1)))

  typedef logic [63:0] reg_t;
  typedef logic [63:0] addr_t;
  typedef logic [31:0] instr_t;

  typedef struct packed {
    longint unsigned BASE;
    longint unsigned END;
  } mmap_t;

  // clint (0x02000000~0x0200ffff)
  parameter mmap_t mapping[SLAVE_CNT] = '{
      '{BASE: addr_t'('ha000_0000), END: addr_t'('ha000_0fff)},  // rom
      '{BASE: addr_t'('ha000_1000), END: addr_t'('ha000_1fff)},  // tohost
      '{BASE: addr_t'('h8000_0000), END: addr_t'('h8fff_ffff)},  // sram
      '{BASE: addr_t'('h0200_0000), END: addr_t'('h0200_ffff)},  // clint
      '{BASE: addr_t'('h0c00_0000), END: addr_t'('h0fff_ffff)},  // plic
      '{BASE: addr_t'('h9000_0000), END: addr_t'('h9000_0fff)},  // igen
      '{BASE: addr_t'('h9000_1000), END: addr_t'('h9000_1fff)}  // uart8250
  };
  // parameter mmap_t mapping[SLAVE_CNT] = '{
  //     '{BASE: addr_t'('h8000_0000), END: addr_t'('h8000_0fff)},
  //     '{BASE: addr_t'('h8000_1000), END: addr_t'('h8000_1fff)},
  //     '{BASE: addr_t'('h8000_2000), END: addr_t'('h8000_afff)},
  //     '{BASE: addr_t'('h0200_0000), END: addr_t'('h0200_ffff)},
  //     '{BASE: addr_t'('h0c00_0000), END: addr_t'('h0fff_ffff)},
  //     '{BASE: addr_t'('h9000_0000), END: addr_t'('h9000_0fff)},
  //     '{BASE: addr_t'('h9000_1000), END: addr_t'('h9000_1fff)}
  // };

  typedef enum {
    S8,
    U8,
    S16,
    U16,
    S32,
    U32,
    US64
  } datatype_e;

  function automatic addr_t databytes(datatype_e dtype);
    unique case (dtype)
      S8, U8:   return 64'd1;
      S16, U16: return 64'd2;
      S32, U32: return 64'd4;
      default:  return 64'd8;
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
    logic        rvc;

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
    .COUNTER(2000000000)
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

  logic stage_ready[5];
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
    output mmap_t mapping [SLAVE_CNT]
  );

  mmap_t maps[SLAVE_CNT] = '{default: 0};
  int fd, ret;
  initial begin : mmaps
    string elf;
    maps = mapping;
    $value$plusargs("elf=%s", elf);
    if (elf != "") begin
      fd = $fopen(elf, "r");
      if (fd != 0) begin
        $fclose(fd);
        ret = elf_parse_mapping(elf, maps);
        `LOGI($sformatf("sections for %s", elf));
        for (int i = 0; i < SLAVE_CNT; i++) begin
          `LOGI($sformatf("maps[%0d] base:%0h end:%0h", i, maps[i].BASE, maps[i].END));
        end
      end else begin
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
    .rif(rf.master)
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
    .rif(rf.master)
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
    .amo_addr_i(rf.master.v1),  // rs1_val
    .wd_i(mem_wd),
    .amo_wd_i(amo_wd),
    .rd_o(wb_mem),
    .amo_rd_o(amo_rd),
    .trap_i(ttaken)
  );

  rfu rfu1 (
    .clk(clk),
    .rst_n(rst_n),
    .valid(stage == STG_WB),
    .ready_o(stage_ready[4]),
    .rif(rf.slave),
    .wb_src_i(ttaken ? WB_SRC_NONE : wb_src),
    .rd_i(id_out.rd),
    .alu_i(wb_alu),
    .csr_i(wb_csr),
    .amo_i(wb_amo),
    .mem_i(wb_mem)
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

  rom rom1 (
    .clk(clk),
    .rst_n(rst_n),
    .mif(slave_ports[0].slave)
  );
  // sram sram1 (
  //   .clk(clk),
  //   .rst_n(rst_n),
  //   .mif(slave_ports[0].slave)
  // );

  scoreboard SB (
    .clk(clk),
    .rst_n(rst_n),
    .mif(slave_ports[1].slave)
  );

  sram #(
    .DATAONLY(0)
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
          if (stage_ready[2]) begin
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
              // if (exc[0].cause != 9) begin
              //   $display("exc cause:%0d pc:%0h priv:%0d msatus:%h", exc[0].cause, pc, priv, mstatus);
              // end
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
        f7          = instr_i[31:25];
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
        id_o = '0;
        id_o.rvc = 1;
        wb_src_o = WB_SRC_NONE;
        code = {instr_i[1:0], instr_i[15:13]};
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
            id_o.opcode    = OPCODE_LOAD;
            id_o.imm       = {56'b0, instr_i[6], instr_i[5], instr_i[12], instr_i[11], instr_i[10], 3'b000};
            id_o.rd        = {2'b01, instr_i[4:2]};
            id_o.rs1       = {2'b01, instr_i[9:7]};
            rif.r1         = {2'b01, instr_i[9:7]};
            id_o.alu_op    = ALU_ADD;
            id_o.reg_write = 1'b1;
            id_o.ld_op     = LD_LD;
            id_o.op_s1     = OP_SRC_REG;
            id_o.op_s2     = OP_SRC_IMM;
            wb_src_o       = WB_SRC_MEM;
          end

          // C.FSD TODO
          5'b00101: begin
            `LOGI("C.FSD");
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
          // C.FSWSP / C.FSDSP
          5'b10101: begin
            // TODO C.FSDSP = fsd  fs2, uimm(x2)
            `LOGI("C.FSDSP");
            id_o.opcode    = OPCODE_STORE;
            id_o.imm       = {55'b0, instr_i[9:7], instr_i[12:10], 3'b000};
            id_o.rs1       = 5'd2;
            id_o.rs2       = instr_i[11:7];
            rif.r1         = 5'd2;
            rif.r2         = instr_i[11:7];
            id_o.alu_op    = ALU_ADD;
            id_o.sd_op     = SD_SD;
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
         regif.master rif
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
      `LOGI($sformatf("a:%0d d:%0d m:%0d amo:%0d", id_i.alu_op, id_i.div_op, id_i.mult_op, id_i.amo_op));
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
    if (id_i.opcode inside {OPCODE_LOAD, OPCODE_STORE}) begin
      mem_addr = alu_result;
      if (id_i.opcode == OPCODE_STORE) begin
        mem_wd = rif.v2;
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
      default: return US64;
    endcase
  endfunction

endmodule

//------------------------------------
// sram
//------------------------------------
module sram #(
  parameter logic DATAONLY = 0
) (
  input logic clk,
  input logic rst_n,
  memif.slave mif
);
  localparam addr_t MAX = 256 * 1024 * 1024;
  typedef logic [$clog2(MAX)-1:0] idx_t;
  wire idx_t idx = mif.addr[$clog2(MAX)-1:0];
  logic [7:0] m[MAX];

  initial begin
    string elf;
    int fd;
    $value$plusargs("elf=%s", elf);
    if (elf != "") begin
      if (DATAONLY) begin
        elf = {elf, ".data"};
      end else begin
        elf = {elf, ".hex"};
      end
      fd = $fopen(elf, "r");
      if (fd != 0) begin
        $fclose(fd);
        $readmemh(elf, m);
        `LOGI($sformatf("ram load %s", elf));
      end
    end else begin
      foreach (m[i]) begin
        m[i] = '0;
      end
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
          S8, U8:   `write_data(m, idx, mif.wd, 1);
          S16, U16: `write_data(m, idx, mif.wd, 2);
          S32, U32: `write_data(m, idx, mif.wd, 4);
          US64:     `write_data(m, idx, mif.wd, 8);
          default:  ;
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
  // localparam addr_t SIZE = 4 * 1024 * 1024;
  localparam addr_t SIZE = 12 * 1024;
  // localparam string HEX = "isa/wfi.hex";
  localparam BITS = $clog2(SIZE);
  wire [BITS-1:0] idx = mif.addr[BITS-1:0];
  logic [7:0] mem[SIZE];

  initial begin
    string elf;
    int fd;
    // $value$plusargs("elf=%s", elf);
    if (elf != "") begin
      elf = {elf, ".hex"};
      fd  = $fopen(elf, "r");
      if (fd != 0) begin
        $fclose(fd);
        $readmemh(elf, mem);
        `LOGI($sformatf("rom load %s", elf));
      end
    end else begin
    end
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

  // assign reg for mmu
  always_comb begin
    priv_o    = priv;
    satp_o    = satp;
    mstatus_o = mstatus;
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
      MNSTATUS:   rd = '0;
      PMPCFG0:    rd = '0;
      PMPADDR0:   rd = '0;
      default: begin
        rd = '0;
        unexist = 1;
      end
    endcase
  end

  reg_t next;
  logic illegal;
  logic write;
  logic cy, tm, ir;
  always_comb begin
    next = 0;
    illegal = 0;
    write = 1;
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
      mstatus    <= '{UXL: 2'b10, SXL: 2'b10, default: 0};
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
      mimpid     <= 64'h0;
      mtime      <= 64'h0;
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

    if (commit_i && exc_fired_i) begin
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
        status        = mstatus;
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
        status        = mstatus;
        status.MPP    = priv;
        status.MPIE   = mstatus.MIE;
        status.MIE    = 0;
        trap_o        = 1;
        trap_target_o = mtvec;
      end
    end else if (commit_i && op_i inside {SYS_SRET, SYS_MRET}) begin
      if (op_i == SYS_SRET) begin
        `LOGI($sformatf("SRET->%0d", mstatus.SPP));
        priv_next     = mstatus.SPP ? M_SUPER : M_USER;
        status        = mstatus;
        status.SPP    = '0;
        status.SIE    = mstatus.SPIE;
        status.SPIE   = '0;
        trap_o        = 1;
        trap_target_o = sepc;
      end else begin
        `LOGI($sformatf("MRET->%0d", mstatus.MPP));
        status = mstatus;
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
    end else if (commit_i && m_intr != reg_t'(0)) begin
      interrupted_o = 1;
      if (mstatus.MIE) begin
        trap_o = 1;
        trap_target_o = mtvec;
        status = mstatus;
        status.MPP = priv;
        status.MPIE = mstatus.MIE;
        status.MIE = 0;
        priv_next = M_MACHINE;
        cause = mintr2cause(m_intr);
        epc = pc_i;
        `LOGW($sformatf("M-intr: %0h", cause));
      end
    end else if (commit_i && s_intr != reg_t'(0)) begin
      interrupted_o = 1;
      if (mstatus.SIE) begin
        trap_o = 1;
        trap_target_o = stvec;
        status = mstatus;
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

  // update register when trapped or xRET
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
    end else begin
      if (commit_i && exc_i.fired) begin
        if (strap) begin
          `LOGW("strap");
          priv <= priv_next;
          sepc <= epc;
          scause <= cause;
          mstatus <= status;
          stval <= eval;
        end else begin
          `LOGW("mtrap");
          priv <= priv_next;
          mepc <= epc;
          mcause <= cause;
          mstatus <= status;
          mtval <= eval;
        end
      end else if (commit_i && op_i inside {SYS_SRET, SYS_MRET}) begin
        mstatus <= status;
        priv    <= priv_next;
        if (op_i == SYS_SRET) begin
          scause <= '0;
        end else begin
          mcause <= '0;
        end
      end else if (commit_i && m_intr != reg_t'(0)) begin
        if (mstatus.MIE) begin
          mstatus <= status;
          priv <= priv_next;
          mepc <= epc;
          mcause <= cause;
        end
      end else if (commit_i && s_intr != reg_t'(0)) begin
        if (mstatus.SIE) begin
          mstatus <= status;
          priv <= priv_next;
          sepc <= epc;
          scause <= cause;
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
  input  reg_t             csr_i
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
