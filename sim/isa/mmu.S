.section .text
.globl _start

_start:
    # ==========================================
    # 【M-mode 阶段】环境初始化与页表构建
    # ==========================================

    # 1. 配置 M-mode 异常处理入口 (兜底保护)
    la t0, m_trap_handler
    csrw mtvec, t0

    # 2. 构建 Sv39 页表 (非恒等映射)
    # 物理地址(PA): 0x8000_0000 开始
    # 虚拟地址(VA): 0x9000_0000 开始
    # 页表存放在 SRAM 中，物理地址为 0x80002000 (严格 4K 对齐)
    li t0, 0x80002000      # 页表基地址

    # 【核心修复】正确构建 L2 页表项 (PTE)
    # 目标物理地址: 0x8000_0000
    li t3, 0x80000000
    srl t3, t3, 12        # 计算 PPN = 0x80000000 >> 12 = 0x80000
    sll t3, t3, 10        # PTE 中 PPN 位于 [53:10]，左移 10 位对齐

    # 设置权限位: V(1) | R(2) | W(4) | X(8) | A(64) | D(128) = 0xEF
    li t4, 0xEF
    or t3, t3, t4          # 组合出完整的 PTE: 0x200000EF

    # 将 PTE 写入 L2 页表的第 36 项 (对应虚拟地址 0x9000_0000)
    # 偏移为 36 * 8 = 288 字节
    addi t5, t0, 24
    sd t3, 0(t5)

    # 3. 【核心操作】在 M-mode 下提前开启 MMU (写入 satp 寄存器)
    li t0, 0x80002000      # 页表物理基地址
    srli t0, t0, 12        # satp.PPN = 0x80002000 >> 12 = 0x80002

    li t1, 8               # MODE = 8 表示开启 Sv39 模式 (64位系统)
    slli t1, t1, 60        # MODE 位于 satp 的最高 4 位 [63:60]
    or t0, t0, t1          # 组合 satp 的值 (PPN | MODE)

    csrw satp, t0          # 写入 satp 开启虚拟内存
    sfence.vma zero, zero  # 刷新 TLB，使配置立即生效

    # 4. 配置 S-mode 异常处理入口
    la t0, s_trap_handler
    csrw stvec, t0

    # 5. 准备切换到 S-mode
    li t0, (1 << 11)       # 设置 mstatus.MPP = 01 (S-mode)
    csrs mstatus, t0

    # 设置 mepc 为 S-mode 下要执行的虚拟地址入口
    la t0, s_mode_entry
    li t1, 0x80000000
    sub t0, t0, t1
    li t1, 0xC0000000
    add t0, t0, t1
    csrw mepc, t0

    # 6. 执行 mret，正式从 M-mode 切换到 S-mode
    mret

# ==========================================
# 【S-mode 阶段】在虚拟地址空间下执行测试
# ==========================================
.align 4
s_mode_entry:
    # 测试 SRAM 的读写 (虚拟地址 0x9000_2000 -> 物理地址 0x8000_2000)
    li t0, 0xC0002000
    li t1, 0xDEADBEEF
    sw t1, 0(t0)
    lwu t2, 0(t0)

    bne t1, t2, fail

    # 【已按要求修改】直接跳转到 pass
    j pass

# ==========================================
# M-mode 异常处理 (兜底)
# ==========================================
.align 4
.globl m_trap_handler
m_trap_handler:
    csrr t0, mcause
    csrr t1, mtval
    j fail

# ==========================================
# S-mode 异常处理 (捕获 Page Fault)
# ==========================================
.align 4
.globl s_trap_handler
s_trap_handler:
    csrr t0, scause
    csrr t1, stval
    j fail

# ==========================================
# 测试结果输出
# ==========================================
pass:
    li  t0, 0xC0001000
    li  t1, 1
    sw  t1, 0(t0)
    j   end

fail:
    li  t0, 0xC0001000
    li  t1, 2
    sw  t1, 0(t0)
    j   end

end:
    ebreak
