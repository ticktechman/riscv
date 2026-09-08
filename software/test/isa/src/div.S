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

#----------------------------------------
.equ TOHOST_BASE, 0x0000000080001000
pass:
    li  t0, TOHOST_BASE
    li   t1, 1
    sw   t1, 0(t0)
    j    end

fail:
    li  t0, TOHOST_BASE
    li   t1, 2
    sw   t1, 0(t0)
    j    end

end:
    ebreak
#----------------------------------------

