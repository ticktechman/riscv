.section .text
.globl _start

_start:
    # ----------------------------------------------------
    # 1. 开启 FPU (mstatus.FS = Dirty)
    # ----------------------------------------------------
    li   t0, 0x00003000          # FS[14:13] = 11 (Dirty)
    csrs mstatus, t0
    fscsr x0                     # 清空 fcsr

    # ----------------------------------------------------
    # 2. 加载公共常量
    # ----------------------------------------------------
    la   t1, fp_pos_0_0
    fld  ft0, 0(t1)              # +0.0
    la   t1, fp_pos_inf
    fld  ft1, 0(t1)              # +Inf

    # ----------------------------------------------------
    # 3. sqrt(+4.0) = +2.0
    # ----------------------------------------------------
    la   t1, fp_pos_4_0
    fld  fa0, 0(t1)
    fsqrt.d fa4, fa0
    la   t1, fp_pos_2_0
    fld  ft2, 0(t1)
    feq.d a0, fa4, ft2
    beq   a0, x0, fail

    # ----------------------------------------------------
    # 4. sqrt(+1.0) = +1.0
    # ----------------------------------------------------
    la   t1, fp_pos_1_0
    fld  fa0, 0(t1)
    fsqrt.d fa4, fa0
    feq.d a0, fa4, fa0
    beq   a0, x0, fail

    # ----------------------------------------------------
    # 5. sqrt(+2.0) ≈ 1.4142135623730951
    # ----------------------------------------------------
    la   t1, fp_pos_2_0
    fld  fa0, 0(t1)
    fsqrt.d fa4, fa0
    la   t1, fp_sqrt_2
    fld  ft2, 0(t1)
    feq.d a0, fa4, ft2
    beq   a0, x0, fail

    # ----------------------------------------------------
    # 6. sqrt(+0.25) = +0.5
    # ----------------------------------------------------
    la   t1, fp_pos_0_25
    fld  fa0, 0(t1)
    fsqrt.d fa4, fa0
    la   t1, fp_pos_0_5
    fld  ft2, 0(t1)
    feq.d a0, fa4, ft2
    beq   a0, x0, fail

    # ----------------------------------------------------
    # 7. sqrt(+1e-4) = +0.01
    # ----------------------------------------------------
    la   t1, fp_pos_1e_4
    fld  fa0, 0(t1)
    fsqrt.d fa4, fa0
    la   t1, fp_pos_0_01
    fld  ft2, 0(t1)
    feq.d a0, fa4, ft2
    beq   a0, x0, fail

    # ----------------------------------------------------
    # 8. sqrt(+0.0) = +0.0
    # ----------------------------------------------------
    fsqrt.d fa4, ft0
    feq.d a0, fa4, ft0
    beq   a0, x0, fail

    # ----------------------------------------------------
    # 9. sqrt(DBL_MIN)
    # ----------------------------------------------------
     la   t1, fp_dbl_min
     fld  fa0, 0(t1)
     fsqrt.d fa4, fa0
     la   t1, fp_sqrt_dbl_min
     fld  ft2, 0(t1)
     feq.d a0, fa4, ft2
     beq   a0, x0, fail

    # ----------------------------------------------------
    # 10. sqrt(次正规数)
    # ----------------------------------------------------
    la   t1, fp_subnorm
    fld  fa0, 0(t1)
    fsqrt.d fa4, fa0
    la   t1, fp_sqrt_subnorm
    fld  ft2, 0(t1)
    feq.d a0, fa4, ft2
    beq   a0, x0, fail

    # ----------------------------------------------------
    # 11. sqrt(+∞) = +∞
    # ----------------------------------------------------
    fsqrt.d fa4, ft1
    feq.d a0, fa4, ft1
    beq   a0, x0, fail

    # ----------------------------------------------------
    # 12. sqrt(最大有限正数)
    # ----------------------------------------------------
    la   t1, fp_max_double
    fld  fa0, 0(t1)
    fsqrt.d fa4, fa0
    la   t1, fp_sqrt_max_double
    fld  ft2, 0(t1)
    feq.d a0, fa4, ft2
    beq   a0, x0, fail

    # ----------------------------------------------------
    # 13. sqrt(-1.0) → qNaN + NV 异常
    # ----------------------------------------------------
    la   t1, fp_neg_1_0
    fld  fa0, 0(t1)
    fsqrt.d fa4, fa0

    frcsr t5
    andi  t5, t5, 0x10           # NV (bit 4)
    li    t6, 0x10
    bne   t5, t6, fail

    # ----------------------------------------------------
    # 14. 恢复 FS 状态，进入 PASS
    # ----------------------------------------------------
    csrc mstatus, t0
    li   t0, 0x00001000          # FS = Initial
    csrs mstatus, t0
    j    pass

#---------------------------------------------------------
# tohost 测试桩
#---------------------------------------------------------
.equ TOHOST_BASE, 0x0000000080001000

pass:
    li   t0, TOHOST_BASE
    li   t1, 1
    sd   t1, 0(t0)
    j    end

fail:
    li   t0, TOHOST_BASE
    li   t1, 2
    sd   t1, 0(t0)
    j    end

end:
    ebreak

#---------------------------------------------------------
# IEEE 754 Double-Precision 数据区
#---------------------------------------------------------
.align 3
fp_pos_4_0:          .quad 0x4010000000000000
fp_pos_2_0:          .quad 0x4000000000000000
fp_sqrt_2:           .quad 0x3FF6A09E667F3BCD

fp_pos_1_0:          .quad 0x3FF0000000000000

fp_pos_0_25:         .quad 0x3FD0000000000000
fp_pos_0_5:          .quad 0x3FE0000000000000

fp_pos_1e_4:         .quad 0x3F1A36E2EB1C432D
fp_pos_0_01:         .quad 0x3F847AE147AE147B

fp_pos_0_0:          .quad 0x0000000000000000
fp_pos_inf:          .quad 0x7FF0000000000000

fp_dbl_min:          .quad 0x0010000000000000
fp_sqrt_dbl_min:     .quad 0x2000000000000000

fp_subnorm:          .quad 0x0008000000000000
fp_sqrt_subnorm:     .quad 0x1FF6A09E667F3BCD

fp_max_double:       .quad 0x7FEFFFFFFFFFFFFF
fp_sqrt_max_double:  .quad 0x5FEFFFFFFFFFFFFF

fp_neg_1_0:          .quad 0xBFF0000000000000
