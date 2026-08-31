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
    /* boundary check: pointer >= test_data_end -> all pass */
    bgeu    s2, s3, pass

    /* load from current pointer */
    lw      a0, 0(s2)              /* a (f32 bits)   @ +0  */
    fmv.w.x f0, a0                 /* a -> f0 (f32)         */
    ld      a2, 4(s2)              /* gold (f64 bits) @ +4  */
    lw      a3, 12(s2)             /* flags           @ +12 */
    lw      t0, 16(s2)             /* TESTNUM         @ +16 */

    /* clear fcsr */
    csrw    fcsr, zero
    fsrmi   _FRM

    /* execute fcvt.d.s */
    fcvt.d.s f4, f0                /* f4 = (double)(float)f0 */

    /* read fflags */
    csrr    a5, fcsr
    andi    a5, a5, 0x1f

    /* move result to GPR for bitwise comparison */
    fmv.x.d a4, f4                 /* f4 -> a4 (64-bit bits) */

    /* compare result bits with gold */
    bne     a4, a2, do_fail

    /* compare flags */
    bne     a5, a3, do_fail

do_pass:
    addi    s2, s2, 20             /* advance pointer 20 bytes */
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
.include "f32_to_f64.txt.S"
test_data_end:
