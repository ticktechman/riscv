.section .text
.globl _start

_start:
    # ----------------------------------------------------
    # 步骤 1：系统初始化，开启 FPU
    # ----------------------------------------------------
    li   t0, 0x00003000       # mstatus.FS 掩码 (Bits [14:13])
    csrs mstatus, t0          # FS = 2'b11 (Dirty/开启)
    fscsr x0                  # 清除 fcsr，所有异常标志归零

    # ----------------------------------------------------
    # 步骤 2：加载测试数据
    # ----------------------------------------------------
    la   t1, fp_pos_2_5
    fld  fa0, 0(t1)           # fa0 = +2.5
    la   t1, fp_pos_1_25
    fld  fa1, 0(t1)           # fa1 = +1.25
    la   t1, fp_pos_1_0
    fld  fa2, 0(t1)           # fa2 = +1.0
    la   t1, fp_neg_2_5
    fld  fa3, 0(t1)           # fa3 = -2.5
    la   t1, fp_pos_0_0
    fld  fa4, 0(t1)           # fa4 = +0.0
    la   t1, fp_max_double
    fld  fa5, 0(t1)           # fa5 = Max_Double
    la   t1, fp_snan
    fld  fa6, 0(t1)           # fa6 = sNaN
    la   t1, fp_pos_inf
    fld  fa7, 0(t1)           # fa7 = +Inf

    # ---- 预期结果 ----
    la   t1, fp_pos_3_125
    fld  ft0, 0(t1)           # 预期: +3.125
    la   t1, fp_pos_0_0
    fld  ft1, 0(t1)           # 预期: +0.0
    la   t1, fp_pos_inf
    fld  ft2, 0(t1)           # 预期: +Inf

    # ----------------------------------------------------
    # 步骤 3：测试 1 — fmadd.d 基本功能
    #   rd = 2.5 × 1.25 + 0.0 = 3.125
    # ----------------------------------------------------
    fmadd.d fs0, fa0, fa1, fa4
    feq.d   a0, fs0, ft0
    beq     a0, x0, fail

    # ----------------------------------------------------
    # 步骤 4：测试 2 — fmadd.d 产生精确零
    #   rd = 2.5 × 1.0 + (-2.5) = 2.5 - 2.5 = +0.0
    # ----------------------------------------------------
    fmadd.d fs1, fa0, fa2, fa3
    feq.d   a1, fs1, ft1
    beq     a1, x0, fail

    # ----------------------------------------------------
    # 步骤 5：测试 3 — fmadd.d 溢出异常
    #   rd = Max × Max + 0.0 → +Inf
    #   预期 fcsr: OF (bit 2) + NX (bit 1) = 0x05
    # ----------------------------------------------------
    fscsr   x0
    fmadd.d fs2, fa5, fa5, fa4    # +Inf
    feq.d   a2, fs2, ft2
    beq     a2, x0, fail

    frcsr   t5
    andi    t5, t5, 0x05          # OF | NX
    li      t6, 0x05
    bne     t5, t6, fail

    # ----------------------------------------------------
    # 步骤 6：测试 4 — fmadd.d NaN 传播与无效异常
    #   rd = NaN × 1.0 + 0.0 → NaN, fcsr.NV (bit 4)
    # ----------------------------------------------------
    fscsr   x0
    fmadd.d fs3, fa6, fa2, fa4    # NaN
    fclass.d a3, fs3
    andi    a3, a3, 0x200         # fclass NaN bits (bit8|bit9)
    beq     a3, x0, fail

    frcsr   t5
    andi    t5, t5, 0x10          # NV
    li      t6, 0x10
    bne     t5, t6, fail

    # ----------------------------------------------------
    # 步骤 7：测试 5 — fmadd.d 无穷大操作数（无异常）
    #   rd = Inf × 1.0 + 0.0 → +Inf
    #   预期 fcsr: 全 0
    # ----------------------------------------------------
    fscsr   x0
    fmadd.d fs4, fa7, fa2, fa4    # +Inf
    feq.d   a4, fs4, ft2
    beq     a4, x0, fail

    frcsr   t5
    bnez    t5, fail

    # ----------------------------------------------------
    # 步骤 8：全部通过，收尾
    # ----------------------------------------------------
    csrc mstatus, t0
    li   t0, 0x00001000
    csrs mstatus, t0
    j    pass

#---------------------------------------------------------
# 统一测试桩
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
# 浮点数据区（IEEE 754 双精度 64-bit）
#---------------------------------------------------------
.align 3
fp_pos_2_5:    .quad 0x4004000000000000   # +2.5
fp_pos_1_25:   .quad 0x3FF4000000000000   # +1.25
fp_pos_1_0:    .quad 0x3FF0000000000000   # +1.0
fp_neg_2_5:    .quad 0xC004000000000000   # -2.5
fp_pos_0_0:    .quad 0x0000000000000000   # +0.0
fp_max_double: .quad 0x7FEFFFFFFFFFFFFF   # Double 最大正值
fp_pos_3_125:  .quad 0x4009000000000000   # +3.125
fp_pos_inf:    .quad 0x7FF0000000000000   # +Infinity
fp_snan:       .quad 0x7FF7000000000000   # Quiet NaN
