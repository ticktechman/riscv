.section .text
.globl _start

_start:
    # 准备测试数据
    li x1, 100              # x1 = 100 (作为内存操作的加数/交换值)
    la x2, test_data        # x2 指向测试内存地址
    sd x0, 0(x2)            # 初始化内存地址为 0

    # 测试 1: amoadd.d.aqrl (原子加法)
    amoadd.d.aqrl x3, x1, (x2)
    li x5, 0                # 检查旧值 x3 == 0
    bne x3, x5, fail
    ld x4, 0(x2)
    li x5, 100              # 检查新内存值 == 100
    bne x4, x5, fail

    # 测试 2: amoswap.d.aqrl (原子交换)
    li x1, 50               # x1 = 50
    amoswap.d.aqrl x3, x1, (x2)
    li x5, 100              # 检查旧值 x3 == 100
    bne x3, x5, fail
    ld x4, 0(x2)
    li x5, 50               # 检查新内存值 == 50
    bne x4, x5, fail

    # 测试 3: amoand.d.aqrl (原子按位与)
    # 内存当前为 50，x1 为 15。50 & 15 = 2
    li x1, 15
    amoand.d.aqrl x3, x1, (x2)
    li x5, 50               # 检查旧值 x3 == 50
    bne x3, x5, fail
    ld x4, 0(x2)
    li x5, 2                # 检查新内存值 == 2
    bne x4, x5, fail

    # 测试 4: amoor.d.aqrl (原子按位或)
    # 内存当前为 2，x1 为 12。2 | 12 = 14
    li x1, 12
    amoor.d.aqrl x3, x1, (x2)
    li x5, 2                # 检查旧值 x3 == 2
    bne x3, x5, fail
    ld x4, 0(x2)
    li x5, 14               # 检查新内存值 == 14
    bne x4, x5, fail

    # 测试 5: amoxor.d.aqrl (原子按位异或)
    # 内存当前为 14，x1 为 10。14 ^ 10 = 4
    li x1, 10
    amoxor.d.aqrl x3, x1, (x2)
    li x5, 14               # 检查旧值 x3 == 14
    bne x3, x5, fail
    ld x4, 0(x2)
    li x5, 4                # 检查新内存值 == 4
    bne x4, x5, fail

    # 测试 6: amomax.d.aqrl (原子有符号最大值)
    # 内存当前为 4，x1 为 20。max(4, 20) = 20
    li x1, 20
    amomax.d.aqrl x3, x1, (x2)
    li x5, 4                # 检查旧值 x3 == 4
    bne x3, x5, fail
    ld x4, 0(x2)
    li x5, 20               # 检查新内存值 == 20
    bne x4, x5, fail

    # 测试 7: amomin.d.aqrl (原子有符号最小值)
    # 内存当前为 20，x1 为 8。min(20, 8) = 8
    li x1, 8
    amomin.d.aqrl x3, x1, (x2)
    li x5, 20               # 检查旧值 x3 == 20
    bne x3, x5, fail
    ld x4, 0(x2)
    li x5, 8                # 检查新内存值 == 8
    bne x4, x5, fail

    # 测试 8: amomaxu.d.aqrl (原子无符号最大值)
    # 内存当前为 8，x1 为 30。maxu(8, 30) = 30
    li x1, 30
    amomaxu.d.aqrl x3, x1, (x2)
    li x5, 8                # 检查旧值 x3 == 8
    bne x3, x5, fail
    ld x4, 0(x2)
    li x5, 30               # 检查新内存值 == 30
    bne x4, x5, fail

    # 测试 9: amominu.d.aqrl (原子无符号最小值)
    # 内存当前为 30，x1 为 15。minu(30, 15) = 15
    li x1, 15
    amominu.d.aqrl x3, x1, (x2)
    li x5, 30               # 检查旧值 x3 == 30
    bne x3, x5, fail
    ld x4, 0(x2)
    li x5, 15               # 检查新内存值 == 15
    bne x4, x5, fail

    # 测试 10: amoadd.w.aqrl (32位原子加法)
    sd x0, 0(x2)            # 重新初始化内存为 0
    li x1, 100
    amoadd.w.aqrl x3, x1, (x2)
    li x5, 0                # 检查旧值 x3 == 0
    bne x3, x5, fail
    lw x4, 0(x2)
    li x5, 100              # 检查新内存值低32位 == 100
    bne x4, x5, fail

    # 测试 11: amoswap.w.aqrl (32位原子交换)
    li x1, 50
    amoswap.w.aqrl x3, x1, (x2)
    li x5, 100              # 检查旧值 x3 == 100
    bne x3, x5, fail
    lw x4, 0(x2)
    li x5, 50               # 检查新内存值低32位 == 50
    bne x4, x5, fail

    # 测试 12: amoand.w.aqrl (32位原子按位与)
    # 内存当前为 50，x1 为 15。50 & 15 = 2
    li x1, 15
    amoand.w.aqrl x3, x1, (x2)
    li x5, 50               # 检查旧值 x3 == 50
    bne x3, x5, fail
    lw x4, 0(x2)
    li x5, 2                # 检查新内存值低32位 == 2
    bne x4, x5, fail

    # 测试 13: amoor.w.aqrl (32位原子按位或)
    # 内存当前为 2，x1 为 12。2 | 12 = 14
    li x1, 12
    amoor.w.aqrl x3, x1, (x2)
    li x5, 2                # 检查旧值 x3 == 2
    bne x3, x5, fail
    lw x4, 0(x2)
    li x5, 14               # 检查新内存值低32位 == 14
    bne x4, x5, fail

    # 测试 14: amoxor.w.aqrl (32位原子按位异或)
    # 内存当前为 14，x1 为 10。14 ^ 10 = 4
    li x1, 10
    amoxor.w.aqrl x3, x1, (x2)
    li x5, 14               # 检查旧值 x3 == 14
    bne x3, x5, fail
    lw x4, 0(x2)
    li x5, 4                # 检查新内存值低32位 == 4
    bne x4, x5, fail

    # 测试 15: amomax.w.aqrl (32位原子有符号最大值)
    # 内存当前为 4，x1 为 20。max(4, 20) = 20
    li x1, 20
    amomax.w.aqrl x3, x1, (x2)
    li x5, 4                # 检查旧值 x3 == 4
    bne x3, x5, fail
    lw x4, 0(x2)
    li x5, 20               # 检查新内存值低32位 == 20
    bne x4, x5, fail

    # 测试 16: amomin.w.aqrl (32位原子有符号最小值)
    # 内存当前为 20，x1 为 8。min(20, 8) = 8
    li x1, 8
    amomin.w.aqrl x3, x1, (x2)
    li x5, 20               # 检查旧值 x3 == 20
    bne x3, x5, fail
    lw x4, 0(x2)
    li x5, 8                # 检查新内存值低32位 == 8
    bne x4, x5, fail

    # 测试 17: amomaxu.w.aqrl (32位原子无符号最大值)
    # 内存当前为 8，x1 为 30。maxu(8, 30) = 30
    li x1, 30
    amomaxu.w.aqrl x3, x1, (x2)
    li x5, 8                # 检查旧值 x3 == 8
    bne x3, x5, fail
    lw x4, 0(x2)
    li x5, 30               # 检查新内存值低32位 == 30
    bne x4, x5, fail

    # 测试 18: amominu.w.aqrl (32位原子无符号最小值)
    # 内存当前为 30，x1 为 15。minu(30, 15) = 15
    li x1, 15
    amominu.w.aqrl x3, x1, (x2)
    li x5, 30               # 检查旧值 x3 == 30
    bne x3, x5, fail
    lw x4, 0(x2)
    li x5, 15               # 检查新内存值低32位 == 15
    bne x4, x5, fail

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

# 测试数据放在代码段尾部
.align 3
test_data:
    .dword 0
