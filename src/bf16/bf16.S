# BFloat16 routines: hand-written RV32I.
#
# uint16_t bf16_from_f32_asm(uint32_t f32bits)   a0 -> a0
# uint16_t bf16_mul_asm(uint16_t a, uint16_t b)  a0, a1 -> a0
# uint16_t bf16_sqrt_asm(uint16_t a)             a0 -> a0
#
# RV32I and Zicsr only: no mul, div, rem, no floating point, no compressed
# instructions. Tests: tests/tbf16.c.

    .text

    .globl  bf16_from_f32_asm
    .type   bf16_from_f32_asm, @function
    .align  2
bf16_from_f32_asm:
    srli    t0, a0, 23
    andi    t0, t0, 255
    li      t1, 255
    beq     t0, t1, .Lf32_truncate
    srli    t0, a0, 16
    andi    t0, t0, 1
    lui     t1, 8
    addi    t1, t1, -1
    add     a0, a0, t1
    add     a0, a0, t0
.Lf32_truncate:
    srli    a0, a0, 16
    ret
    .size   bf16_from_f32_asm, .-bf16_from_f32_asm

    .globl  bf16_mul_asm
    .type   bf16_mul_asm, @function
    .align  2
bf16_mul_asm:
    xor     a2, a0, a1
    srli    a2, a2, 15
    slli    a2, a2, 15
    srli    t0, a0, 7
    andi    t0, t0, 255
    srli    t1, a1, 7
    andi    t1, t1, 255
    andi    t2, a0, 127
    andi    t3, a1, 127
    li      t5, 255
    beq     t0, t5, .Lbmul_special_a
    beq     t1, t5, .Lbmul_special_b
    or      a4, t0, t2
    beqz    a4, .Lbmul_zero
    or      a4, t1, t3
    beqz    a4, .Lbmul_zero
    bnez    t0, .Lbmul_normal_a
    li      t0, 1
.Lbmul_normalize_a:
    slli    t2, t2, 1
    addi    t0, t0, -1
    andi    a4, t2, 128
    beqz    a4, .Lbmul_normalize_a
    j       .Lbmul_test_b
.Lbmul_normal_a:
    ori     t2, t2, 128
.Lbmul_test_b:
    bnez    t1, .Lbmul_normal_b
    li      t1, 1
.Lbmul_normalize_b:
    slli    t3, t3, 1
    addi    t1, t1, -1
    andi    a4, t3, 128
    beqz    a4, .Lbmul_normalize_b
    j       .Lbmul_product
.Lbmul_normal_b:
    ori     t3, t3, 128
.Lbmul_product:
    add     t4, t0, t1
    addi    t4, t4, -127
    li      a3, 0
.Lbmul_loop:
    andi    a4, t3, 1
    beqz    a4, .Lbmul_shift
    add     a3, a3, t2
.Lbmul_shift:
    slli    t2, t2, 1
    srli    t3, t3, 1
    bnez    t3, .Lbmul_loop
    srli    a4, a3, 15
    beqz    a4, .Lbmul_fraction
    srli    a3, a3, 1
    addi    t4, t4, 1
.Lbmul_fraction:
    srli    a3, a3, 7
    andi    a3, a3, 127
    bge     t4, t5, .Lbmul_inf
    blez    t4, .Lbmul_underflow
    slli    t4, t4, 7
    or      a0, t4, a3
    or      a0, a0, a2
    ret
.Lbmul_underflow:
    li      a4, -6
    blt     t4, a4, .Lbmul_zero
    li      a4, 1
    sub     a4, a4, t4
    srl     a3, a3, a4
    or      a0, a3, a2
    ret
.Lbmul_special_a:
    bnez    t2, .Lbmul_return
    slli    a4, a1, 17
    beqz    a4, .Lbmul_nan
    j       .Lbmul_inf
.Lbmul_special_b:
    bnez    t3, .Lbmul_return_b
    slli    a4, a0, 17
    beqz    a4, .Lbmul_nan
.Lbmul_inf:
    li      a0, 0x7f80
    or      a0, a0, a2
    ret
.Lbmul_return_b:
    mv      a0, a1
.Lbmul_return:
    ret
.Lbmul_nan:
    li      a0, 0x7fc0
    ret
.Lbmul_zero:
    mv      a0, a2
    ret
    .size   bf16_mul_asm, .-bf16_mul_asm

    .globl  bf16_sqrt_asm
    .type   bf16_sqrt_asm, @function
    .align  2
bf16_sqrt_asm:
    srli    t0, a0, 7
    andi    t0, t0, 255
    andi    t1, a0, 127
    li      t2, 255
    beq     t0, t2, .Lbsqrt_special
    slli    t2, a0, 17
    beqz    t2, .Lbsqrt_zero
    slli    t2, a0, 16
    bltz    t2, .Lbsqrt_nan
    beqz    t0, .Lbsqrt_zero
    ori     t1, t1, 128
    andi    t2, t0, 1
    bnez    t2, .Lbsqrt_radicand
    slli    t1, t1, 1
.Lbsqrt_radicand:
    addi    t0, t0, 127
    srli    t0, t0, 1
    slli    t0, t0, 7
    addi    t1, t1, 1
    slli    t1, t1, 7
    addi    t1, t1, -1
    # Restoring integer square root of 128*(mantissa+1)-1, eight rounds.
    li      t2, 0
    li      t3, 0x4000
.Lbsqrt_loop:
    add     t4, t2, t3
    srli    t2, t2, 1
    bltu    t1, t4, .Lbsqrt_next
    sub     t1, t1, t4
    add     t2, t2, t3
.Lbsqrt_next:
    srli    t3, t3, 2
    bnez    t3, .Lbsqrt_loop
    andi    t2, t2, 127
    or      a0, t0, t2
    ret
.Lbsqrt_special:
    bnez    t1, .Lbsqrt_return
    slli    t2, a0, 16
    bgez    t2, .Lbsqrt_return
.Lbsqrt_nan:
    li      a0, 0x7fc0
    ret
.Lbsqrt_zero:
    li      a0, 0
.Lbsqrt_return:
    ret
    .size   bf16_sqrt_asm, .-bf16_sqrt_asm
