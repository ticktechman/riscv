.equ TOHOST_BASE, 0x80001000

.section .text.init
.globl _start
.align 8

_start:
    csrw    fcsr, zero

    /* init data pointer */
    la      s2, test_data
    la      s3, test_data_end

loop:
    bgeu    s2, s3, pass

    /* load from current pointer */
    ld      a0, 0(s2)              /* src (i64)       @ +0  */
    ld      a2, 8(s2)              /* gold (f64 bits) @ +8  */
    lw      a3, 16(s2)             /* flags           @ +16 */
    lw      t0, 20(s2)             /* TESTNUM         @ +20 */

    /* clear fcsr */
    csrw    fcsr, zero

    /* execute fcvt.d.l */
    fcvt.d.l f0, a0                /* f0 = (double)(int64)a0 */

    /* move f64 result to integer register for bit-exact compare */
    fmv.x.d a4, f0                 /* a4 = f0 bit pattern (64-bit) */

    /* read fflags */
    csrr    a5, fcsr
    andi    a5, a5, 0x1f

    /* compare result and flags */
    bne     a4, a2, do_fail
    bne     a5, a3, do_fail

do_pass:
    addi    s2, s2, 24             /* advance pointer 24 bytes */
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
  .include "./golden/i64_to_f64.txt.S"
test_data_end:
