.equ TOHOST_BASE, 0x80001000

.section .text.init
.globl _start
.align 8

#include "inc/frnd.S"

_start:
    csrw    fcsr, zero

    /* init data pointer */
    la      s2, test_data
    la      s3, test_data_end

loop:
    bgeu    s2, s3, pass

    /* load from current pointer */
    lwu      a0, 0(s2)              /* src (ui32)       @ +0  */
    ld      a2, 4(s2)              /* gold (f64 bits) @ +4  */
    lw      a3, 12(s2)              /* flags           @ +12  */
    lw      t0, 16(s2)             /* TESTNUM         @ +15 */

    /* clear fcsr */
    csrw    fcsr, zero
    fsrmi   _FRM

    /* execute fcvt.s.w */
    fcvt.d.w f0, a0                /* f0 = (float)(int32)a0 */

    /* move f64 result to integer register for bit-exact compare */
    fmv.x.d a4, f0                 /* a4 = f0 bit pattern */

    /* read fflags */
    csrr    a5, fcsr
    andi    a5, a5, 0x1f

    /* compare result and flags */
    bne     a4, a2, do_fail
    bne     a5, a3, do_fail

do_pass:
    addi    s2, s2, 20             /* advance pointer 16 bytes */
    j       loop

do_fail:
    slli    t1, t0, 1              /* TOHOST = TESTNUM << 1 */
    j       fail

/* ============ TOHOST exit ============ */

pass:
    li      t0, TOHOST_BASE
    li      t1, 1
    sw      t1, 0(t0)              /* write 1 = ALL PASS */
    j       end

fail:
    li      t0, TOHOST_BASE
    sw      t1, 0(t0)              /* write testnum<<1 = FAIL */
    j       end

end:
    ebreak

/* ============ data section ============ */

.pushsection .tohost
tohost:
.align 8
    .dword 0

.section .data
.align 4

test_data:
  .include "ui32_to_f64.txt.S"
test_data_end:
