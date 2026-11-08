#include "fixed.h"

/* Bitwise addition with explicit carry propagation. */
uint32_t op1(uint32_t a, uint32_t b, int *n)
{
    *n = 0;
    while (b != 0) {
        uint32_t carry = (a & b) << 1;
        a = a ^ b;
        b = carry;
        (*n)++;
    }
    return a;
}

uint32_t op2(uint32_t a, uint32_t b)
{
    return a - b;
}

uint32_t op3(uint32_t a, uint32_t b)
{
    /* Halve first; two odd operands contribute one more to the average. */
    return (a >> 1) + (b >> 1) + (a & b & 1u);
}

int32_t q_mul(int32_t a, int32_t b)
{
    /* Unsigned magnitudes also handle INT32_MIN without signed overflow. */
    uint32_t ma = a < 0 ? 0u - (uint32_t) a : (uint32_t) a;
    uint32_t mb = b < 0 ? 0u - (uint32_t) b : (uint32_t) b;
    uint32_t al = ma & 0xFFFFu, ah = ma >> 16;
    uint32_t bl = mb & 0xFFFFu, bh = mb >> 16;

    /* Each 16-bit product fits 32 bits; widen only after multiplying.
     * RV32I can use the supplied __mulsi3 instead of requiring __muldi3.
     */
    uint64_t product = (uint64_t) (al * bl) + ((uint64_t) (al * bh) << 16) +
                       ((uint64_t) (ah * bl) << 16) +
                       ((uint64_t) (ah * bh) << 32);
    if ((a < 0) != (b < 0))
        product = 0u - product;

    /* Round before shifting. Unsigned arithmetic preserves the low 32
     * result bits even for negative products and overflowing outputs.
     */
    product += (uint64_t) 1 << (Q - 1);
    uint32_t result = (uint32_t) (product >> Q);

    /* Map the bit pattern to int32_t using only representable conversions. */
    return result <= INT32_MAX ? (int32_t) result : -1 - (int32_t) (~result);
}
