.section .text
.globl _start

# ================= 硬件验证平台退出地址 =================
.equ TOHOST_BASE,     0x0000000080001000

# ================= CLINT 定时器基地址 =================
.equ CLINT_BASE,      0x02000000
.equ CLINT_MTIMECMP,  CLINT_BASE + 0x4000
.equ CLINT_MTIME,     CLINT_BASE + 0xBFF8

# ================= CSR 寄存器地址 =================
.equ CSR_MSTATUS,     0x300
.equ CSR_MIE,         0x304
.equ CSR_MTVEC,       0x305
.equ CSR_MCAUSE,      0x342

# ================= 常量定义 =================
.equ MIE_MTIE,        0x80                  # Machine Timer Interrupt Enable (bit 7)
.equ MSTATUS_MIE,     0x8                   # Machine Interrupt Enable (bit 3)
.equ CAUSE_MTI,       0x8000000000000007    # RV64 机器模式定时器中断完整 mcause 值
.equ TIMEOUT_LIMIT,   1000000               # 超时循环计数

# ================= 主程序入口 =================
_start:
    # 1. 设置异常/中断向量表基地址 (Direct 模式)
    la t0, trap_vector
    csrw CSR_MTVEC, t0

    # 2. 初始化定时器
    li t0, CLINT_MTIME
    ld t1, 0(t0)
    li t2, 20
    add t3, t1, t2
    li t0, CLINT_MTIMECMP
    sd t3, 0(t0)

    # 3. 使能定时器中断 (MTIE)
    li t0, 0
    csrw CSR_MIE, t0
    li t0, MIE_MTIE
    csrs CSR_MIE, t0

    # 4. 开启全局机器模式中断 (MSTATUS.MIE)
    li t0, 0
    csrw CSR_MSTATUS, t0
    li t0, MSTATUS_MIE
    csrs CSR_MSTATUS, t0

    # 5. 等待中断触发，同时包含超时检测机制
    # 【核心修改】全程使用 Callee-saved 的 s 寄存器作为主循环变量
    li s0, 0                  # s0: 中断触发标志位
    li s1, 0                  # s1: 超时计数器 (替代原来的 t0)
    li s2, TIMEOUT_LIMIT      # s2: 超时上限 (替代原来的 t1)

wait_loop:
    bnez s0, pass             # 如果 s0 被 ISR 置为 1，跳转 pass
    addi s1, s1, 1            # 计数器递增
    blt s1, s2, wait_loop     # 如果未超时，继续等待

    j fail                    # 超时未触发，跳转 fail

# ================= 异常/中断向量表 =================
.align 2
trap_vector:
    # 【核心修改】因为主程序用的是 s 寄存器，ISR 里可以毫无顾忌地随便用 t 寄存器！
    # 无需任何保存/恢复操作！

    # 检查中断原因 (mcause)
    csrr t0, CSR_MCAUSE
    li t1, CAUSE_MTI
    bne t0, t1, default_trap  # 如果不是定时器中断，跳转默认处理

    # 是定时器中断：清除中断标志
    li t0, CLINT_MTIME
    ld t1, 0(t0)
    li t2, 10000000
    add t3, t1, t2
    li t0, CLINT_MTIMECMP
    sd t3, 0(t0)

    # 手动重新开启全局中断 (MSTATUS.MIE)
    li t0, MSTATUS_MIE
    csrs CSR_MSTATUS, t0

    li s0, 1                  # 标记中断已成功触发 (修改 s0 是业务逻辑需要)

    mret                      # 从中断返回

default_trap:
    mret                      # 其他异常直接返回

# ================= 测试结果输出 =================
pass:
    li  t0, TOHOST_BASE
    li  t1, 1
    sw  t1, 0(t0)
    j   end

fail:
    li  t0, TOHOST_BASE
    li  t1, 2
    sw  t1, 0(t0)
    j   end

end:
    ebreak
