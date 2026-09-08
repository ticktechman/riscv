.section .text
.globl _start

_start:
    # ==========================================
    # 1. M-mode 初始化阶段 (芯片默认在此模式启动)
    # ==========================================
    # 设置 M-mode 的异常入口
    la t0, m_trap_handler
    csrw mtvec, t0

    # 【关键】将 Ecall 异常 (异常号 8) 委托给 S-mode 处理
    # medeleg 的第 8 位设为 1，这样 U-mode 的 ecall 才会去 S-mode，而不是留在 M-mode
    li t0, (1 << 8)
    csrw medeleg, t0

    # 准备从 M-mode 跳转到 S-mode
    la t0, s_mode_entry       # 设置 mret 的返回地址
    csrw mepc, t0
    li t0, 0x1800             # 清除 mstatus.MPP (设为 1 表示 S-mode，0 表示 U-mode)
    csrc mstatus, t0
    li t0, 0x0800             # 设置 mstatus.MPP = 1 (S-mode)
    csrs mstatus, t0

    # 输出 'M' (表示 M-mode 初始化完成)
    lui t0, 0x2
    li t1, 'M'
    sb t1, 0(t0)

    mret                      # 【测试 mret】从 M-mode 切换到 S-mode

    # ==========================================
    # 2. S-mode 入口阶段
    # ==========================================
s_mode_entry:
    # 设置 S-mode 的异常入口
    la t0, s_trap_handler
    csrw stvec, t0

    # 准备从 S-mode 跳转到 U-mode
    la t0, u_mode_entry       # 设置 sret 的返回地址
    csrw sepc, t0
    li t0, 0x0100             # 清除 sstatus.SPP (设为 1 表示 S-mode，0 表示 U-mode)
    csrc sstatus, t0

    # 输出 'S' (表示成功进入 S-mode)
    lui t0, 0x2
    li t1, 'S'
    sb t1, 0(t0)

    sret                      # 【测试 sret】从 S-mode 切换到 U-mode

    # ==========================================
    # 3. U-mode 入口阶段
    # ==========================================
u_mode_entry:
    # 输出 'U' (表示成功进入 U-mode)
    lui t0, 0x2
    li t1, 'U'
    sb t1, 0(t0)

    # 在 U-mode 触发 ecall，期望陷入 S-mode
    ecall                     # 【测试 ecall】U-mode -> S-mode

    # 如果 ecall 没生效直接跑到了这里，说明失败
    j fail

    # ==========================================
    # 4. S-mode 异常处理程序
    # ==========================================
s_trap_handler:
    # 输出 'X' (表示进入了 S-mode 异常处理，理论上 U->S 会触发这里)
    # 为了最终输出 MSUMP，我们这里不输出字符，直接判断是否要继续向上触发
    # 读取 sepc 判断异常来源，这里简单起见直接再次执行 ecall 触发 S->M
    ecall                     # 【测试 ecall】S-mode -> M-mode

    # 如果上面的 ecall 没生效，执行 sret 返回 U-mode (会导致 fail)
    sret

    # ==========================================
    # 5. M-mode 异常处理程序
    # ==========================================
m_trap_handler:
    # 输出 'P' (表示成功从 S-mode 陷入 M-mode，全流程打通！)
    lui t0, 0x2
    li t1, 'P'
    sb t1, 0(t0)

    # 为了程序能正常结束，我们需要把 mepc 指向 fail 标签的下一条指令（end）
    # 这样 mret 之后就会直接跳到 end，避免重复输出或跑飞
    la t0, end
    csrw mepc, t0
    mret                      # 返回并结束

fail:
    lui t0, 0x2
    li t1, 'F'
    sb t1, 0(t0)
end:
    ebreak
