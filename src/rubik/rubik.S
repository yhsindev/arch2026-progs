# rubik_solve_asm: optimal 2x2x2 cube solver, hand-written RV32I.
#
# int rubik_solve_asm(const char *state, char *out, size_t cap)
#                                   a0 = state, a1 = out, a2 = cap; result in a0
#
# RV32I and Zicsr only: no mul, div, rem, no floating point, no compressed
# instructions or heap. Prefix recursion is at most six moves deep; each
# frame is 64 bytes. The terminal suffix uses an exact radius-five table.
# s0-s4 are table bases, s5 points to the eleven-byte path. All callee-saved
# registers are preserved, including on invalid-input and short-buffer exits.

    .text

    .globl  rubik_solve_asm
    .type   rubik_solve_asm, @function
    .align  2
rubik_solve_asm:
    addi    sp, sp, -112
    sw      ra, 96(sp)
    sw      s0, 48(sp)
    sw      s1, 52(sp)
    sw      s2, 56(sp)
    sw      s3, 60(sp)
    sw      s4, 64(sp)
    sw      s5, 68(sp)
    sw      s6, 72(sp)
    sw      s7, 76(sp)
    sw      s8, 80(sp)
    sw      s9, 84(sp)
    sw      s10, 88(sp)
    sw      s11, 92(sp)
    mv      s7, a1
    mv      s8, a2
    beqz    a0, .Lrubik_invalid
    mv      a3, a0
    li      t0, 0
    li      t1, 0
    addi    t2, sp, 12
    li      t6, 7
.Lrubik_parse_p:
    lbu     t3, 0(a3)
    addi    t3, t3, -49
    bgeu    t3, t6, .Lrubik_invalid
    li      t4, 1
    sll     t4, t4, t3
    and     t5, t1, t4
    bnez    t5, .Lrubik_invalid
    or      t1, t1, t4
    sw      t3, 0(t2)
    addi    t2, t2, 4
    addi    a3, a3, 1
    addi    t0, t0, 1
    bltu    t0, t6, .Lrubik_parse_p
    li      s9, 0
    li      t0, 0
.Lrubik_rank_outer:
    slli    t3, t0, 2
    add     t3, sp, t3
    lw      t3, 12(t3)
    addi    t1, t0, 1
    li      t2, 0
.Lrubik_rank_inner:
    bgeu    t1, t6, .Lrubik_rank_scale
    slli    t4, t1, 2
    add     t4, sp, t4
    lw      t4, 12(t4)
    sltu    t4, t4, t3
    add     t2, t2, t4
    addi    t1, t1, 1
    j       .Lrubik_rank_inner
.Lrubik_rank_scale:
    sub     t4, t6, t0
    mv      t5, s9
    li      s9, 0
.Lrubik_rank_multiply:
    add     s9, s9, t5
    addi    t4, t4, -1
    bnez    t4, .Lrubik_rank_multiply
    add     s9, s9, t2
    addi    t0, t0, 1
    bltu    t0, t6, .Lrubik_rank_outer
    li      s10, 0
    li      t0, 0
    li      t1, 0
    li      t6, 3
.Lrubik_parse_o:
    lbu     t2, 0(a3)
    addi    t2, t2, -49
    bgeu    t2, t6, .Lrubik_invalid
    add     t1, t1, t2
    li      t3, 6
    bgeu    t0, t3, .Lrubik_last_o
    slli    t3, s10, 1
    add     s10, s10, t3
    add     s10, s10, t2
.Lrubik_last_o:
    addi    a3, a3, 1
    addi    t0, t0, 1
    li      t3, 7
    bltu    t0, t3, .Lrubik_parse_o
    lbu     t2, 0(a3)
    bnez    t2, .Lrubik_invalid
.Lrubik_orientation_sum:
    bltu    t1, t6, .Lrubik_sum_done
    sub     t1, t1, t6
    j       .Lrubik_orientation_sum
.Lrubik_sum_done:
    bnez    t1, .Lrubik_invalid
    la      s0, .Lrubik_perm_move
    la      s1, .Lrubik_ori_move
    la      s2, .Lrubik_perm_dist
    la      s3, .Lrubik_ori_dist
    la      s4, .Lrubik_terminal
    mv      s5, sp
    mv      a0, s9
    mv      a1, s10
    li      a2, 0
    li      a3, 5
    call    .Lrubik_finish
    bgez    a0, .Lrubik_render
    add     t0, s2, s9
    lbu     s11, 0(t0)
    add     t0, s3, s10
    lbu     t0, 0(t0)
    bgeu    s11, t0, .Lrubik_bound_min
    mv      s11, t0
.Lrubik_bound_min:
    li      t0, 6
    bgeu    s11, t0, .Lrubik_check_diameter
    mv      s11, t0
.Lrubik_check_diameter:
    la      t0, .Lrubik_diameter
    slli    t1, s9, 10
    or      t1, t1, s10
    li      t2, 0
    li      t3, 2644
.Lrubik_diameter_loop:
    bgeu    t2, t3, .Lrubik_diameter_end
    add     t4, t2, t3
    srli    t4, t4, 1
    slli    t5, t4, 2
    add     t5, t0, t5
    lw      t5, 0(t5)
    bltu    t5, t1, .Lrubik_diameter_right
    mv      t3, t4
    j       .Lrubik_diameter_loop
.Lrubik_diameter_right:
    addi    t2, t4, 1
    j       .Lrubik_diameter_loop
.Lrubik_diameter_end:
    li      t3, 2644
    beq     t2, t3, .Lrubik_deepen
    slli    t2, t2, 2
    add     t2, t0, t2
    lw      t2, 0(t2)
    bne     t2, t1, .Lrubik_deepen
    li      s11, 11
.Lrubik_deepen:
    mv      a0, s9
    mv      a1, s10
    mv      a2, s11
    li      a3, 3
    li      a4, 0
    call    .Lrubik_search
    bgez    a0, .Lrubik_render
    addi    s11, s11, 1
    li      t0, 11
    bgeu    t0, s11, .Lrubik_deepen
    j       .Lrubik_invalid
.Lrubik_render:
    mv      s6, a0
    li      t0, 0
    addi    t1, sp, 12
.Lrubik_render_loop:
    bgeu    t0, s6, .Lrubik_render_done
    beqz    t0, .Lrubik_render_move
    li      t2, 32
    sb      t2, 0(t1)
    addi    t1, t1, 1
.Lrubik_render_move:
    add     t2, s5, t0
    lbu     t2, 0(t2)
    li      t3, 82
    li      t4, 3
    bltu    t2, t4, .Lrubik_render_face
    addi    t2, t2, -3
    li      t3, 66
    bltu    t2, t4, .Lrubik_render_face
    addi    t2, t2, -3
    li      t3, 68
.Lrubik_render_face:
    sb      t3, 0(t1)
    addi    t1, t1, 1
    beqz    t2, .Lrubik_render_next
    li      t3, 50
    li      t4, 1
    beq     t2, t4, .Lrubik_render_suffix
    li      t3, 39
.Lrubik_render_suffix:
    sb      t3, 0(t1)
    addi    t1, t1, 1
.Lrubik_render_next:
    addi    t0, t0, 1
    j       .Lrubik_render_loop
.Lrubik_render_done:
    sb      zero, 0(t1)
    addi    t0, sp, 12
    sub     t2, t1, t0
    bgeu    t2, s8, .Lrubik_small_buffer
    mv      t1, s7
.Lrubik_copy:
    lbu     t2, 0(t0)
    sb      t2, 0(t1)
    addi    t0, t0, 1
    addi    t1, t1, 1
    bnez    t2, .Lrubik_copy
    mv      a0, s6
    j       .Lrubik_return
.Lrubik_small_buffer:
    beqz    s8, .Lrubik_small_return
    sb      zero, 0(s7)
.Lrubik_small_return:
    li      a0, -2
    j       .Lrubik_return
.Lrubik_invalid:
    li      a0, -1
.Lrubik_return:
    lw      s0, 48(sp)
    lw      s1, 52(sp)
    lw      s2, 56(sp)
    lw      s3, 60(sp)
    lw      s4, 64(sp)
    lw      s5, 68(sp)
    lw      s6, 72(sp)
    lw      s7, 76(sp)
    lw      s8, 80(sp)
    lw      s9, 84(sp)
    lw      s10, 88(sp)
    lw      s11, 92(sp)
    lw      ra, 96(sp)
    addi    sp, sp, 112
    ret
    .size   rubik_solve_asm, .-rubik_solve_asm

# Lookup clobbers only a0 and t0-t5; a1-a4 remain available to its caller.
.Lrubik_lookup:
    slli    t0, a0, 10
    or      t0, t0, a1
    srli    t1, t0, 7
    xor     t1, t1, t0
    srli    t2, t0, 13
    xor     t1, t1, t2
    slli    t1, t1, 18
    srli    t1, t1, 18
    slli    t1, t1, 2
    add     t1, s4, t1
    li      t5, 65536
    add     t5, t5, s4
    li      t4, -1
.Lrubik_probe:
    lw      a0, 0(t1)
    beq     a0, t4, .Lrubik_lookup_return
    srli    t2, a0, 7
    beq     t2, t0, .Lrubik_lookup_return
    addi    t1, t1, 4
    bne     t1, t5, .Lrubik_probe
    mv      t1, s4
    j       .Lrubik_probe
.Lrubik_lookup_return:
    ret

# a0=p, a1=o, a2=prefix length, a3=remaining. Return total length or -1.
.Lrubik_finish:
    addi    sp, sp, -32
    sw      a0, 0(sp)
    sw      a1, 4(sp)
    sw      a2, 8(sp)
    sw      a3, 12(sp)
    sw      ra, 28(sp)
    call    .Lrubik_lookup
    li      t0, -1
    beq     a0, t0, .Lrubik_finish_fail
    srli    t0, a0, 4
    andi    t0, t0, 7
    lw      t1, 12(sp)
    bltu    t1, t0, .Lrubik_finish_fail
.Lrubik_suffix_loop:
    srli    t0, a0, 4
    andi    t0, t0, 7
    beqz    t0, .Lrubik_finish_success
    andi    t0, a0, 15
    lw      t1, 8(sp)
    add     t2, s5, t1
    sb      t0, 0(t2)
    addi    t1, t1, 1
    sw      t1, 8(sp)
    mv      t2, s0
    mv      t3, s1
    li      t4, 3
    bltu    t0, t4, .Lrubik_suffix_face
    addi    t0, t0, -3
    li      t1, 10080
    add     t2, t2, t1
    addi    t3, t3, 1458
    bltu    t0, t4, .Lrubik_suffix_face
    addi    t0, t0, -3
    add     t2, t2, t1
    addi    t3, t3, 1458
.Lrubik_suffix_face:
    addi    t0, t0, 1
    lw      a0, 0(sp)
    lw      a1, 4(sp)
.Lrubik_suffix_turn:
    slli    t1, a0, 1
    add     t1, t2, t1
    lhu     a0, 0(t1)
    slli    t1, a1, 1
    add     t1, t3, t1
    lhu     a1, 0(t1)
    addi    t0, t0, -1
    bnez    t0, .Lrubik_suffix_turn
    sw      a0, 0(sp)
    sw      a1, 4(sp)
    call    .Lrubik_lookup
    j       .Lrubik_suffix_loop
.Lrubik_finish_success:
    lw      a0, 8(sp)
    j       .Lrubik_finish_return
.Lrubik_finish_fail:
    li      a0, -1
.Lrubik_finish_return:
    lw      ra, 28(sp)
    addi    sp, sp, 32
    ret

# a0=p, a1=o, a2=remaining, a3=previous face, a4=prefix length.
# Reject impossible nodes before allocating a frame.
.Lrubik_search:
    add     t0, s2, a0
    lbu     t0, 0(t0)
    bltu    a2, t0, .Lrubik_search_fail
    add     t0, s3, a1
    lbu     t0, 0(t0)
    bltu    a2, t0, .Lrubik_search_fail
    li      t0, 5
    bltu    t0, a2, .Lrubik_search_prefix
    # Most terminal probes miss. Test inline before allocating the suffix
    # frame; successful probes alone enter reconstruction.
    slli    t0, a0, 10
    or      t0, t0, a1
    srli    t1, t0, 7
    xor     t1, t1, t0
    srli    t2, t0, 13
    xor     t1, t1, t2
    slli    t1, t1, 18
    srli    t1, t1, 18
    slli    t1, t1, 2
    add     t1, s4, t1
    li      t5, 65536
    add     t5, t5, s4
    li      t4, -1
.Lrubik_search_probe:
    lw      t3, 0(t1)
    beq     t3, t4, .Lrubik_search_fail
    srli    t2, t3, 7
    beq     t2, t0, .Lrubik_search_found
    addi    t1, t1, 4
    bne     t1, t5, .Lrubik_search_probe
    mv      t1, s4
    j       .Lrubik_search_probe
.Lrubik_search_found:
    mv      a3, a2
    mv      a2, a4
    j       .Lrubik_finish
.Lrubik_search_fail:
    li      a0, -1
    ret
.Lrubik_search_prefix:
    addi    sp, sp, -64
    sw      a0, 0(sp)
    sw      a1, 4(sp)
    sw      s6, 16(sp)
    sw      s7, 20(sp)
    sw      s8, 24(sp)
    sw      s9, 28(sp)
    sw      s10, 32(sp)
    sw      s11, 36(sp)
    sw      ra, 60(sp)
    mv      s8, a2
    mv      s9, a3
    mv      s11, a4
    li      s10, 0
.Lrubik_search_face:
    beq     s10, s9, .Lrubik_search_next_face
    lw      s6, 0(sp)
    lw      s7, 4(sp)
    sw      zero, 8(sp)
    mv      t0, s0
    mv      t1, s1
    beqz    s10, .Lrubik_search_bases
    li      t2, 10080
    add     t0, t0, t2
    addi    t1, t1, 1458
    li      t3, 1
    beq     s10, t3, .Lrubik_search_bases
    add     t0, t0, t2
    addi    t1, t1, 1458
.Lrubik_search_bases:
    sw      t0, 44(sp)
    sw      t1, 48(sp)
.Lrubik_search_turn:
    lw      t0, 44(sp)
    lw      t1, 48(sp)
    slli    t2, s6, 1
    add     t2, t0, t2
    lhu     s6, 0(t2)
    slli    t2, s7, 1
    add     t2, t1, t2
    lhu     s7, 0(t2)
    slli    t0, s10, 1
    add     t0, t0, s10
    lw      t1, 8(sp)
    add     t0, t0, t1
    add     t1, s5, s11
    sb      t0, 0(t1)
    mv      a0, s6
    mv      a1, s7
    addi    a2, s8, -1
    mv      a3, s10
    addi    a4, s11, 1
    call    .Lrubik_search
    bgez    a0, .Lrubik_search_return
    lw      t0, 8(sp)
    addi    t0, t0, 1
    sw      t0, 8(sp)
    li      t1, 3
    bltu    t0, t1, .Lrubik_search_turn
.Lrubik_search_next_face:
    addi    s10, s10, 1
    li      t0, 3
    bltu    s10, t0, .Lrubik_search_face
    li      a0, -1
.Lrubik_search_return:
    lw      s6, 16(sp)
    lw      s7, 20(sp)
    lw      s8, 24(sp)
    lw      s9, 28(sp)
    lw      s10, 32(sp)
    lw      s11, 36(sp)
    lw      ra, 60(sp)
    addi    sp, sp, 64
    ret

    .section .rodata
    .include "src/rubik/rubik_tables.inc"
