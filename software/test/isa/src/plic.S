#----------------------------------------
# 宏定义与常量
#----------------------------------------
.equ PLIC_BASE,       0x0C000000
.equ PLIC_PRIORITY,   0x00000000
.equ PLIC_ENABLE,     0x00002000
.equ PLIC_THRESHOLD,  0x00200000
.equ PLIC_CLAIM,      0x00200004

.equ TRIGGER_ADDR,    0x90000000
.equ IRQ_ID,          2
.equ TOHOST_BASE,     0x0000000080001000

.equ TIMEOUT_LIMIT,   0x1000000

#----------------------------------------
# 代码段
#----------------------------------------
.section .text
.globl _start
.globl trap_entry

_start:
    # 初始化状态变量：使用 s0 寄存器存储 irq_handled 状态
    li s0, 0

    # 1. 配置 PLIC
    # 设置中断源 2 的优先级为 1
    li t0, PLIC_BASE + PLIC_PRIORITY + (IRQ_ID * 4)
    li t1, 1
    sw t1, 0(t0)

    # 使能 Context 0 (Hart0 M-mode) 接收中断源 2
    li t0, PLIC_BASE + PLIC_ENABLE + (0 * 0x80)
    li t1, (1 << IRQ_ID)
    sw t1, 0(t0)

    # 设置 Context 0 的优先级阈值为 0
    li t0, PLIC_BASE + PLIC_THRESHOLD + (0 * 0x1000)
    sw zero, 0(t0)

    # 2. 配置 CPU 中断相关 CSR
    la t0, trap_entry
    csrw mtvec, t0

    # 开启 mie.MEIE (第11位)
    li t0, (1 << 11)
    csrw mie, t0

    # 开启 mstatus.MIE (第3位)
    csrr t0, mstatus
    ori t0, t0, (1 << 3)
    csrw mstatus, t0

    # 3. 触发中断
    li t0, TRIGGER_ADDR
    li t1, 0x01
    sw t1, 0(t0)

    # 4. 主循环：等待中断处理完成 (带超时保护)
    li t3, TIMEOUT_LIMIT
wait_loop:
    bnez s0, pass       # 检查 s0 寄存器，如果不为0则跳转 pass

    addi t3, t3, -1     # 超时计数器递减
    bnez t3, wait_loop  # 未超时则继续等待

    # 超时未收到中断，测试失败
    j fail

#----------------------------------------
# 测试结束与 Tohost 通信
#----------------------------------------
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
# 中断处理入口
#----------------------------------------
.align 2
trap_entry:
    # 【已移除 SP 压栈操作，直接操作寄存器】

    # 读取 PLIC Claim/Complete 寄存器 (Context 0)
    li t0, PLIC_BASE + PLIC_CLAIM + (0 * 0x1000)
    lw t0, 0(t0)          # t0 = 获取到的中断 ID

    beqz t0, trap_exit    # 如果返回 0，说明没有需要处理的中断

    # 验证是否是预期的中断源 2
    li t1, IRQ_ID
    bne t0, t1, trap_exit

    # 清除触发源
    li t1, TRIGGER_ADDR
    sw zero, 0(t1)

    # 修改状态变量：将 s0 寄存器置为 1
    li s0, 1

    # 将中断 ID 写回 Claim/Complete 寄存器，通知 PLIC 处理完成
    li t1, PLIC_BASE + PLIC_CLAIM + (0 * 0x1000)
    sw t0, 0(t1)

trap_exit:
    # 【已移除 SP 恢复操作】
    # 直接返回，t0 和 s0 的值将被改变
    mret
