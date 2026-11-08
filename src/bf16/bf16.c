#include "bf16.h"

uint16_t bf16_from_f32(uint32_t f32bits)
{
    if (((f32bits >> 23) & 0xFFu) != 0xFFu)
        f32bits += 0x7FFFu + ((f32bits >> 16) & 1u);
    return (uint16_t) (f32bits >> 16);
}

uint16_t bf16_mul(uint16_t a, uint16_t b)
{
    uint32_t sign = (a ^ b) & 0x8000u;
    int ea = (a >> 7) & 0xFF, eb = (b >> 7) & 0xFF;
    uint32_t ma = a & 0x7Fu, mb = b & 0x7Fu;
    /* Classification order and denormal truncation follow the quiz contract. */
    if (ea == 255) {
        if (ma)
            return a;
        return (b & 0x7FFFu) == 0 ? 0x7FC0u : sign | 0x7F80u;
    }
    if (eb == 255) {
        if (mb)
            return b;
        return (a & 0x7FFFu) == 0 ? 0x7FC0u : sign | 0x7F80u;
    }
    if ((a & 0x7FFFu) == 0 || (b & 0x7FFFu) == 0)
        return (uint16_t) sign;
    if (ea == 0) {
        ea = 1;
        while (ma < 128) {
            ma <<= 1;
            ea--;
        }
    } else {
        ma |= 128u;
    }
    if (eb == 0) {
        eb = 1;
        while (mb < 128) {
            mb <<= 1;
            eb--;
        }
    } else {
        mb |= 128u;
    }
    uint32_t product = ma * mb;
    int exponent = ea + eb - 127;
    if (product >= 32768) {
        product >>= 1;
        exponent++;
    }
    uint32_t fraction = (product >> 7) & 0x7Fu;
    if (exponent >= 255)
        return (uint16_t) (sign | 0x7F80u);
    if (exponent <= 0) {
        if (exponent < -6)
            return (uint16_t) sign;
        return (uint16_t) (sign | (fraction >> (1 - exponent)));
    }
    return (uint16_t) (sign | ((uint32_t) exponent << 7) | fraction);
}

uint16_t bf16_sqrt(uint16_t a)
{
    uint32_t exponent = (a >> 7) & 0xFFu;
    uint32_t fraction = a & 0x7Fu;
    if (exponent == 255)
        return fraction || !(a & 0x8000u) ? a : 0x7FC0u;
    if ((a & 0x7FFFu) == 0)
        return 0;
    if (a & 0x8000u)
        return 0x7FC0u;
    if (exponent == 0)
        return 0;
    uint32_t mantissa = fraction | 128u;
    if ((exponent & 1u) == 0)
        mantissa <<= 1;
    /* Largest root with floor(root^2 / 128) <= mantissa. */
    uint32_t low = 90, high = 256, root = 0;
    while (low <= high) {
        uint32_t mid = (low + high) >> 1;
        if (((mid * mid) >> 7) <= mantissa) {
            root = mid;
            low = mid + 1;
        } else {
            high = mid - 1;
        }
    }
    return (uint16_t) ((((exponent + 127u) >> 1) << 7) | (root & 0x7Fu));
}
