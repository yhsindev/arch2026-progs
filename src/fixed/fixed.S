# op1, op2, op3 and q_mul: hand-written RV32I.
#
# uint32_t op1_asm(uint32_t a, uint32_t b, int *n)   a0, a1, a2 -> a0
# uint32_t op2_asm(uint32_t a, uint32_t b)           a0, a1 -> a0
# uint32_t op3_asm(uint32_t a, uint32_t b)           a0, a1 -> a0
# int32_t  q_mul_asm(int32_t a, int32_t b)           a0, a1 -> a0
#
# RV32I and Zicsr only: no mul, div, rem, no floating point, no compressed
# instructions. q_mul forms a 64-bit product in a register pair. Tests:
# tests/tfixed.c.

    .text

    .globl  op1_asm
    .type   op1_asm, @function
    .align  2
op1_asm:
    # a0 = sum, a1 = pending carry, a2 = count pointer.
    # Keep the count in t0 and store it once at the end.
    li      t0, 0
    beqz    a1, .Lop1_done
.Lop1_loop:
    and     t1, a0, a1
    xor     a0, a0, a1
    slli    a1, t1, 1
    addi    t0, t0, 1
    bnez    a1, .Lop1_loop
.Lop1_done:
    sw      t0, 0(a2)
    ret
    .size   op1_asm, .-op1_asm

    .globl  op2_asm
    .type   op2_asm, @function
    .align  2
op2_asm:
    # Low 32 bits of a - b; a0 also holds the return value.
    sub     a0, a0, a1
    ret
    .size   op2_asm, .-op2_asm

    .globl  op3_asm
    .type   op3_asm, @function
    .align  2
op3_asm:
    # Exact average: (a & b) + ((a ^ b) >> 1).
    and     t0, a0, a1
    xor     a0, a0, a1
    srli    a0, a0, 1
    add     a0, a0, t0
    ret
    .size   op3_asm, .-op3_asm

    .globl  q_mul_asm
    .type   q_mul_asm, @function
    .align  2
q_mul_asm:
    # Multiply unsigned magnitudes in t1:t0, preserving the product sign.
    xor     t6, a0, a1
    srai    t0, a0, 31
    xor     a0, a0, t0
    sub     a0, a0, t0
    srai    t0, a1, 31
    xor     a1, a1, t0
    sub     a1, a1, t0
    li      t0, 0
    li      t1, 0
    li      t2, 0
    beqz    a1, .Lqmul_sign
.Lqmul_loop:
    andi    t3, a1, 1
    beqz    t3, .Lqmul_shift
    add     t0, t0, a0
    sltu    t3, t0, a0
    add     t1, t1, t2
    add     t1, t1, t3
.Lqmul_shift:
    srli    t3, a0, 31
    slli    a0, a0, 1
    slli    t2, t2, 1
    or      t2, t2, t3
    srli    a1, a1, 1
    bnez    a1, .Lqmul_loop
.Lqmul_sign:
    bgez    t6, .Lqmul_round
    not     t0, t0
    not     t1, t1
    addi    t0, t0, 1
    seqz    t3, t0
    add     t1, t1, t3
.Lqmul_round:
    lui     t3, 0x80
    add     t0, t0, t3
    sltu    t3, t0, t3
    add     t1, t1, t3
    srli    a0, t0, 20
    slli    t1, t1, 12
    or      a0, a0, t1
    ret
    .size   q_mul_asm, .-q_mul_asm
