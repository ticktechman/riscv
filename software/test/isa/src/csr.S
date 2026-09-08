.section .text
.globl _start

_start:
    # 准备测试数据
    li x1, 0x123456789ABCDEF0   # x1 = 初始测试值
    li x2, 0x00000000000000FF   # x2 = 掩码/置位值
    li x3, 0xFFFFFFFFFFFFFF00   # x3 = 清零掩码

    # 测试 1: csrrw (读写 mscratch)
    # 将 x1 的值写入 mscratch，并将 mscratch 的旧值读入 x4
    csrrw x4, mscratch, x1

    # 检查旧值 x4 == 0 (mscratch 默认初始值通常为0)
    li x5, 0
    bne x4, x5, fail

    # 检查 mscratch 当前值 == x1
    csrr x6, mscratch
    bne x6, x1, fail

    # 测试 2: csrrs (置位 mscratch)
    # 将 x2 中的 1 置位到 mscratch，旧值存入 x4
    csrrs x4, mscratch, x2

    # 检查旧值 x4 == x1
    bne x4, x1, fail

    # 检查 mscratch 新值 == (x1 | x2)
    or x7, x1, x2
    csrr x6, mscratch
    bne x6, x7, fail

    # 测试 3: csrrc (清零 mscratch)
    # 将 x3 中的 0 清零 mscratch 对应位，旧值存入 x4
    csrrc x4, mscratch, x3

    # 检查旧值 x4 == (x1 | x2)
    bne x4, x7, fail

    # 检查 mscratch 新值 == ((x1 | x2) & x3)
    not x9, x3                  # 先对 x3 取反，得到 0x00000000000000FF
    and x8, x7, x9              # 计算预期值：(x1 | x2) & ~x3
    csrr x6, mscratch           # 读取硬件更新后的 mscratch
    bne x6, x8, fail            # 比较硬件结果与预期结果

    # 所有测试通过
    j pass

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
