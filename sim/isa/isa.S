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
    add x3, x1, x2
    sub x4, x2, x1

    # 检查 x3 == 30
    li x5, 30
    bne x3, x5, fail

    # 检查 x4 == 10
    li x5, 10
    bne x4, x5, fail

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
