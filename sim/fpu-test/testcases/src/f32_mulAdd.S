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

    /* load from current pointer
     * layout: a@+0, b@+4, c@+8, gold@+12, flags@+16, TESTNUM@+20
     */
    flw     f0, 0(s2)              /* a        @ +0  */
    flw     f1, 4(s2)              /* b        @ +4  */
    flw     f2, 8(s2)              /* c        @ +8  */
    lw      a2, 12(s2)             /* gold     @ +12 */
    lw      a3, 16(s2)             /* flags    @ +16 */
    lw      t0, 20(s2)             /* TESTNUM  @ +20 */

    /* clear fcsr */
    csrw    fcsr, zero
    fsrmi   _FRM

    /* execute fmadd.s: f3 = f0 * f1 + f2 */
    fmadd.s f3, f0, f1, f2
    fmv.x.s a4, f3                 /* DUT result -> GPR */

    /* read fflags */
    csrr    a5, fcsr
    andi    a5, a5, 0x1f

    /* NaN-aware check: test if gold is NaN (exp=all1, mantissa!=0) */
    srli    t3, a2, 23             /* f32 exp in bit[30:23] */
    li      t4, 0xff
    bne     t3, t4, normal_cmp

    li      t4, 0x007fffff
    and     t4, a2, t4
    beqz    t4, normal_cmp         /* mantissa=0 -> is INF -> normal compare */

    /* gold is NaN -> DUT must also be NaN, only compare fflags */
    srli    t3, a4, 23
    li      t4, 0xff
    bne     t3, t4, do_fail        /* DUT exp != all1 -> fail */
    li      t4, 0x007fffff
    and     t4, a4, t4
    beqz    t4, do_fail            /* DUT mantissa=0 -> is INF -> fail */
    bne     a5, a3, do_fail        /* fflags mismatch -> fail */
    j       do_pass

normal_cmp:
    bne     a4, a2, do_fail        /* result mismatch */
    bne     a5, a3, do_fail        /* fflags mismatch */

do_pass:
    addi    s2, s2, 24             /* advance pointer 24 bytes (6×4) */
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
.include "f32_mulAdd.txt.S"
test_data_end:
