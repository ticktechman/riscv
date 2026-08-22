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
    /* boundary check: pointer >= test_data_end -> all pass */
    bgeu    s2, s3, pass

    /* load from current pointer */
    fld     f0, 0(s2)              /* a        @ +0  */
    fld     f1, 8(s2)              /* b        @ +8  */
    ld      a2, 16(s2)             /* gold     @ +16 */
    lw      a3, 24(s2)             /* flags    @ +24 */
    lw      t0, 28(s2)             /* TESTNUM  @ +28 */

    /* clear fcsr */
    csrw    fcsr, zero

    /* execute fadd.d */
    fsub.d  f3, f0, f1
    fmv.x.d a4, f3                 /* DUT result -> GPR */

    /* read fflags */
    csrr    a5, fcsr
    andi    a5, a5, 0x1f

    /* NaN-aware check: test if gold is NaN (exp=all1, mantissa!=0) */
    srli    t3, a2, 52
    li      t4, 0x7ff
    bne     t3, t4, normal_cmp

    li      t4, 0x000fffffffffffff
    and     t4, a2, t4
    beqz    t4, normal_cmp         /* mantissa=0 -> is INF -> normal compare */

    /* gold is NaN -> DUT must also be NaN, only compare fflags */
    srli    t3, a4, 52
    li      t4, 0x7ff
    bne     t3, t4, do_fail        /* DUT exp != all1 -> fail */
    li      t4, 0x000fffffffffffff
    and     t4, a4, t4
    beqz    t4, do_fail            /* DUT mantissa=0 -> is INF -> fail */
    bne     a5, a3, do_fail        /* fflags mismatch -> fail */
    j       do_pass

normal_cmp:
    bne     a4, a2, do_fail        /* result mismatch */
    bne     a5, a3, do_fail        /* fflags mismatch */

do_pass:
    addi    s2, s2, 32             /* advance pointer 32 bytes */
    j       loop

do_fail:
    slli    t1, t0, 1              /* TOHOST = TESTNUM << 1 */
    j       fail

/* ============ TOHOST exit ============ */

pass:
    li      t0, TOHOST_BASE
    li      t1, 1
    sd      t1, 0(t0)              /* write 1 = ALL PASS */
    j       end

fail:
    li      t0, TOHOST_BASE
    sd      t1, 0(t0)              /* write testnum<<1 = FAIL */
    j       end

end:
    ebreak                         /* absolute execution wall */

/* ============ data section ============ */
.pushsection .tohost
tohost:
.align 8
   .dword 0

.section .data
.align 8

test_data:
.include "./golden/f64_sub.txt.S"
test_data_end:
