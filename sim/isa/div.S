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
    li x1, 16
    li x2, 80
    div x3, x2, x1
    li x4, 5
    bne x3, x4, fail

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
