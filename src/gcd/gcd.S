# gcd_u32_asm: Stein's binary GCD, hand-written RV32I.
#
# Arguments: a0 = a, a1 = b. Return: a0 = gcd(a, b).
# Registers: t0 = common power of two; t1 = parity test or difference.
# Leaf function: only caller-saved registers, no stack or external calls.
# Right-shift loops test at the bottom to avoid an extra jump per bit.
# Once both values are odd, their nonzero difference has a factor of two.

    .text
    .globl gcd_u32_asm
    .type gcd_u32_asm, @function
    .align 2
gcd_u32_asm:
    beqz a0, .Lgcd_return_b
    beqz a1, .Lgcd_return
    li t0, 0
    or t1, a0, a1
    andi t1, t1, 1
    bnez t1, .Lgcd_left_test

.Lgcd_common:
    srli a0, a0, 1
    srli a1, a1, 1
    addi t0, t0, 1
    or t1, a0, a1
    andi t1, t1, 1
    beqz t1, .Lgcd_common

.Lgcd_left_test:
    andi t1, a0, 1
    bnez t1, .Lgcd_right_test
.Lgcd_left:
    srli a0, a0, 1
    andi t1, a0, 1
    beqz t1, .Lgcd_left

.Lgcd_right_test:
    andi t1, a1, 1
    bnez t1, .Lgcd_compare
.Lgcd_right:
    srli a1, a1, 1
    andi t1, a1, 1
    beqz t1, .Lgcd_right

.Lgcd_compare:
    bltu a1, a0, .Lgcd_swap_difference
    sub a1, a1, a0
    bnez a1, .Lgcd_right
    sll a0, a0, t0
.Lgcd_return:
    ret

.Lgcd_swap_difference:
    sub t1, a0, a1
    mv a0, a1
    mv a1, t1
    j .Lgcd_right

.Lgcd_return_b:
    mv a0, a1
    ret
    .size gcd_u32_asm, .-gcd_u32_asm
