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
    flw     f0, 0(s2)              /* a        @ +0  */
    flw     f1, 4(s2)              /* b        @ +4  */
    lw      a2, 8(s2)              /* gold     @ +8  */
    lw      a3, 12(s2)             /* flags    @ +12 */
    lw      t0, 16(s2)             /* TESTNUM  @ +16 */

    /* clear fcsr */
    csrw    fcsr, zero
    fsrmi  _FRM

    /* execute feq.s */
    feq.s   a4, f0, f1             /* a4 = (a == b) ? 1 : 0 */

    /* read fflags */
    csrr    a5, fcsr
    andi    a5, a5, 0x1f

    /* compare result and flags */
    bne     a4, a2, do_fail
    bne     a5, a3, do_fail

do_pass:
    addi    s2, s2, 20             /* advance pointer 20 bytes (5x4) */
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
.include "f32_eq.txt.S"
test_data_end:
