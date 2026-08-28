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
    /* pointer >= test_data_end -> all pass */
    bgeu    s2, s3, pass

    /* load double operands
     * layout:
     *   a       @ +0  (8B)
     *   b       @ +8  (8B)
     *   c       @ +16 (8B)
     *   gold    @ +24 (8B)
     *   flags   @ +32 (4B)
     *   TESTNUM @ +36 (4B)
     */
    fld     f0, 0(s2)
    fld     f1, 8(s2)
    fld     f2, 16(s2)
    ld      a2, 24(s2)             /* gold */
    lw      a3, 32(s2)             /* flags */
    lw      t0, 36(s2)             /* TESTNUM */

    /* clear fflags */
    csrw    fcsr, zero

    /* execute fmadd.d: f3 = f0 * f1 + f2 */
    fmadd.d f3, f0, f1, f2
    fmv.x.d a4, f3                 /* DUT result -> GPR */

    /* read fflags */
    csrr    a5, fcsr
    andi    a5, a5, 0x1f

    /* NaN-aware check: exp[62:52] == 0x7FF */
    srli    t3, a2, 52
    li      t4, 0x7ff
    bne     t3, t4, normal_cmp

    /* mantissa[51:0] == 0 -> INF -> normal compare */
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
    addi    s2, s2, 40             /* advance 40 bytes (5×8) */
    j       loop

do_fail:
    slli    t1, t0, 1              /* TOHOST = TESTNUM << 1 */
    j       fail

/* ============ TOHOST exit ============ */

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

/* ============ data ============ */

.pushsection .tohost
tohost:
  .align 8
  .dword 0

.section .data
  .align 4

test_data:
.include "./golden/f64_mulAdd.txt.S"
test_data_end:
