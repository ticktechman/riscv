.section .text
.globl _start

_start:
    # 1. 设置中断向量表 (MTVEC)
    la t0, trap_handler
    csrw mtvec, t0

    # 2. 使能全局中断和外部中断
    li t0, 0x800           # 使能外部中断 (MEIE)
    csrs mie, t0
    li t0, 0x8             # 使能全局中断 (MIE)
    csrs mstatus, t0

    # --- 主程序：准备测试 mret ---
    li x5, 0xABCD          # 设置标记值，用于 mret 后检查
    wfi                    # 等待中断触发

    # --- mret 返回后的检查点 ---
    li x6, 0xABCD
    bne x5, x6, fail       # 检查寄存器上下文是否被破坏
    j pass

# ==========================================
# 无栈中断处理入口
# ==========================================
trap_handler:
    # 【关键改动】不再使用 sp 压栈，而是使用 t3-t6 作为影子寄存器来备份 t0-t2
    mv t3, t0
    mv t4, t1
    mv t5, t2

    # 读取 mcause 确认是外部中断 (ID = 11)
    csrr t0, mcause
    li t1, 11
    bne t0, t1, skip_irq

    # (这里可以加入清除外部中断控制器 pending 位的代码)

skip_irq:
    # ==========================================
    # 【新增代码】修改 mepc，使其指向 wfi 的下一条指令
    # ==========================================
    csrr t0, mepc          # 读取当前的 mepc (此时指向 wfi 指令)
    addi t0, t0, 4         # PC 加 4，跳过 4 字节的 wfi 指令
    csrw mepc, t0          # 将修改后的 PC 写回 mepc
    # ==========================================

    # 【关键改动】从影子寄存器恢复数据
    mv t0, t3
    mv t1, t4
    mv t2, t5

    mret                   # 返回主程序，此时将从 wfi 的下一条指令开始执行

#----------------------------------------
.equ TOHOST_BASE, 0x0000000080001000
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
#----------------------------------------
