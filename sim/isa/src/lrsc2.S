.section .text
.globl _start

_start:
    # 1. 获取本地测试数据的地址 (直接使用 la 伪指令)
    la      x10, test_data

    # 2. 初始化内存数据为 100
    li      x11, 100
    sd      x11, 0(x10)

    # 3. 执行 lr.d.aqrl
    lr.w.aqrl x12, 0(x10)     # x12 应该读到旧值 100

    # 检查 lr 读到的值是否正确
    li      x13, 100
    bne     x12, x13, fail

    # 4. 计算新值 (100 + 50 = 150)
    li      x14, 50
    add     x15, x12, x14

    # 5. 执行 sc.d.rl
    sc.w.rl x16, x15, 0(x10)  # x16 应该返回 0 (表示成功写入)

    # 检查 sc 是否成功 (必须返回 0)
    bnez    x16, fail

    # 6. 验证内存中的新值是否为 150
    ld      x17, 0(x10)
    li      x13, 150
    bne     x17, x13, fail

    # 7. 测试 sc 失败的情况
    li      x15, 200
    sc.w.rl x16, x15, 0(x10)
    beqz    x16, fail

    # 所有检查通过
    j       pass

#----------------------------------------
.equ TOHOST_BASE, 0x0000000080001000
pass:
    li      x10, TOHOST_BASE
    li      x11, 1
    sw      x11, 0(x10)
    j       end

fail:
    li      x10, TOHOST_BASE
    li      x11, 2
    sw      x11, 0(x10)
    j       end

end:
    ebreak

#----------------------------------------
# 测试数据直接放在代码段末尾，8字节对齐
.align 3
test_data:
    .dword 0
