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
    li t0, 0x10000000 # UART 映射地址
    li t1, 0x48 # 'H'
    sd t1, 0(t0)
    ebreak
