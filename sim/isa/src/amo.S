.section .text
.globl _start

_start:
    # 准备测试数据
    li x1, 100              # x1 = 100 (作为内存操作的加数/交换值)
    li x2, 0x80002000       # x2 指向指定的测试内存绝对地址
    sd x0, 0(x2)            # 初始化内存地址 0x80002000 为 0

    # 测试 1: amoadd.d (原子加法)
    # 将 x1(100) 与 test_mem(0) 相加，结果写回 test_mem，旧值(0)存入 x3
    amoadd.d x3, x1, (x2)

    # 检查旧值 x3 == 0
    li x5, 0
    bne x3, x5, fail

    # 检查新内存值 == 100
    ld x4, 0(x2)
    li x5, 100
    bne x4, x5, fail

    # 测试 2: amoswap.d (原子交换)
    li x1, 250              # x1 = 250 (作为交换的新值)
    # 将 x1(250) 与 test_mem(100) 交换，新值(250)写入 test_mem，旧值(100)存入 x3
    amoswap.d x3, x1, (x2)

    # 检查旧值 x3 == 100
    li x5, 100
    bne x3, x5, fail

    # 检查新内存值 == 250
    ld x4, 0(x2)
    li x5, 250
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
