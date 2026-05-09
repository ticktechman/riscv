# 0 "hello.S"
# 0 "<built-in>"
# 0 "<command-line>"
# 1 "/usr/riscv64-linux-gnu/include/stdc-predef.h" 1 3
# 0 "<command-line>" 2
# 1 "hello.S"
# hello.s
.section .text
.globl _start

_start:
    li x1, 10
    li x2, 20
    mul x3, x1, x2
    li x4, 200
    bne x3, x4, fail

    li t0, -2                      # 补码: 0xFFFFFFFFFFFFFFFE
    li t1, 0x7FFFFFFFFFFFFFFF      # 最大正整数
    mulh t2, t0, t1                # 结果的高 64 位应为 -1 (0xFFFFFFFFFFFFFFFF)
    li t3, -1
    bne t2, t3, fail

    li t0, 0xFFFFFFFFFFFFFFFF      # 无符号最大值 (2^64 - 1)
    li t1, 0xFFFFFFFFFFFFFFFF      # 同上
    mulhu t2, t0, t1               # 结果应为 (2^64 - 2)，即 0xFFFFFFFFFFFFFFFE
    li t3, 0xFFFFFFFFFFFFFFFE
    bne t2, t3, fail

    li t0, -1
    li t1, 2
    mulhsu t2, t0, t1
    li t3, -1
    bne t2, t3, fail

    li t0, 0x7FFFFFFF              # 32位最大正整数
    li t1, 2
    mulw t2, t0, t1                # 32位结果为 0xFFFFFFFE (即 -2) # 符号扩展到64位应为 0xFFFFFFFFFFFFFFFE
    li t3, -2
    bne t2, t3, fail

pass:
    lui t0, 0x2
    li t1, 'P'
    sb t1, 0(t0)
    li t1, '\n'
    sb t1, 0(t0)
    j end

fail:
    lui t0, 0x2
    li t1, 'F'
    sb t1, 0(t0)
    li t1, '\n'
    sb t1, 0(t0)
    j end
end:
  ebreak
