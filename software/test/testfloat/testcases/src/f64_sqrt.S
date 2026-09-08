.equ TOHOST_BASE, 0x80001000

.section .text.init
.globl _start
.align 8

#include "inc/frnd.S"

_start:
    csrw    fcsr, zero

    la      s2, test_data
    la      s3, test_data_end

loop:
    bgeu    s2, s3, pass

    fld     f0, 0(s2)              /* a        @ +0  */
    fld     f2, 8(s2)              /* gold     @ +8  */
    lw      a3, 16(s2)             /* flags    @ +16 */
    lw      t0, 20(s2)             /* TESTNUM  @ +20 */

    csrw    fcsr, zero
    fsrmi   _FRM


    fsqrt.d f3, f0
    fmv.x.d a4, f3                 /* DUT result -> GPR */
    fmv.x.d a2, f2                 /* gold -> GPR */

    csrr    a5, fcsr
    andi    a5, a5, 0x1f

    /* NaN check: gold exp[62:52] */
    srli    t3, a2, 52
    li      t4, 0x7ff
    bne     t3, t4, normal_cmp

    li      t4, 0x000fffffffffffff
    and     t4, a2, t4
    beqz    t4, normal_cmp

    /* gold is NaN -> DUT must also be NaN */
    srli    t3, a4, 52
    li      t4, 0x7ff
    bne     t3, t4, do_fail
    li      t4, 0x000fffffffffffff
    and     t4, a4, t4
    beqz    t4, do_fail
    bne     a5, a3, do_fail
    j       do_pass

normal_cmp:
    bne     a4, a2, do_fail
    bne     a5, a3, do_fail

do_pass:
    addi    s2, s2, 24
    j       loop

do_fail:
    slli    t1, t0, 1
    j       fail

pass:
    li      t0, TOHOST_BASE
    li      t1, 1
    sw      t1, 0(t0)
    j       end

fail:
    li      t0, TOHOST_BASE
    sw      t1, 0(t0)
    j       end

end:
    ebreak

.pushsection .tohost
tohost:
.align 8
   .dword 0

.section .data
.align 8

test_data:
.include "f64_sqrt.txt.S"
test_data_end:
