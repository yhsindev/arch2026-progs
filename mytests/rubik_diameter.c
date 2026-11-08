/* Additional coverage: all 2,644 diameter states, using the instructor's
 * independent physical-cube checker unchanged. This is not graded code.
 */
#include "../tests/trubik.c"
#include "rubik_diameter_states.h"

int main(void)
{
    unsigned implementations = 1;
#ifdef __riscv
    implementations = 2;
#endif
    for (unsigned impl = 0; impl < implementations; impl++) {
        solve_fn solve = rubik_solve;
#ifdef __riscv
        if (impl)
            solve = rubik_solve_asm;
        uint64_t maximum = 0;
        unsigned worst = 0;
#endif
        for (unsigned i = 0; i < 2644; i++) {
            int length = -1;
            if (solve_and_verify(solve, diameter_states[i], &length) !=
                    TEST_PASS ||
                length != 11) {
                utest_printer("diameter failed: impl=%u state=%s length=%d\n",
                              impl, diameter_states[i], length);
                return 1;
            }
#ifdef __riscv
            char out[64];
            uint64_t used;
            PERF_CALL(used,
                      length = solve(diameter_states[i], out, sizeof out));
            if (used > maximum) {
                maximum = used;
                worst = i;
            }
#endif
        }
        utest_printer("diameter impl=%u: 2644 passed, 0 failed\n", impl);
#ifdef __riscv
        utest_printer("maximum=%llu state=%s\n", (unsigned long long) maximum,
                      diameter_states[worst]);
#endif
    }
    return 0;
}
