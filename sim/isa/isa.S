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

