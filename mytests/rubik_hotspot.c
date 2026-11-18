/* Diagnostic harness, outside the submitted implementation.
 * The physical move model and known distances come from the unchanged tests.
 */
#include "../tests/trubik.c"
#include "bench.h"
#include "tests.h"

#ifndef HS_PROFILE
#define HS_PROFILE 0
#endif
#ifndef HS_VARIANT
#define HS_VARIANT "unknown"
#endif

static const char *const hs_states[] = {
    "12345671111111", "46253172123131", "43562713121333",
    "72465131321333", "62345713133111", "24513763133333",
};
static const int hs_distances[] = {0, 2, 4, 6, 8, 9};
static const uint32_t hs_inputs[] = {0, 1, 2, 3, 4, 5};
static char hs_out[64];

#if HS_PROFILE
enum { HS_FIELDS = 13 };
extern uint32_t hs_counts[HS_FIELDS];
static const char *const hs_names[HS_FIELDS] = {
    "search_entries",   "prefix_nodes",  "terminal_attempts",
    "terminal_probes",  "terminal_hits", "terminal_misses",
    "terminal_wraps",   "pdb_prunes",    "finish_entries",
    "lookup_entries",   "lookup_probes", "transition_steps",
    "bound_iterations",
};
#endif

static int hs_verify(const char *state, const char *out, int n, int expected)
{
    if (n != expected)
        return 0;
    struct cube c = parse(state);
    size_t len = 0;
    while (len < sizeof hs_out && out[len])
        len++;
    if (len == sizeof hs_out)
        return 0;
    int count = 0;
    for (size_t i = 0; i < len;) {
        size_t j = i;
        while (j < len && out[j] != ' ')
            j++;
        int m = token(out + i, j - i);
        if (m < 0 || (j < len && j + 1 == len))
            return 0;
        c = turn(c, m);
        count++;
        i = j + 1;
    }
    return count == n && solved(&c);
}

static int hs_case(const char *set,
                   unsigned index,
                   const char *state,
                   int expected)
{
    for (unsigned i = 0; i < sizeof hs_out; i++)
        hs_out[i] = '#';
#if HS_PROFILE
    for (unsigned i = 0; i < HS_FIELDS; i++)
        hs_counts[i] = 0;
#endif
    uint64_t used;
    int n;
    PERF_CALL(used, n = rubik_solve_asm(state, hs_out, sizeof hs_out));
    if (!hs_verify(state, hs_out, n, expected)) {
        bm_printf("HOTSPOT CHECK FAILED variant=%s state=%s result=%d\n",
                  HS_VARIANT, state, n);
        return 0;
    }
    bm_printf(
        "@@hotspot variant=%s dataset=%s index=%u state=%s "
        "distance=%d instructions=%llu",
        HS_VARIANT, set, index, state, expected, (unsigned long long) used);
#if HS_PROFILE
    for (unsigned i = 0; i < HS_FIELDS; i++)
        bm_printf(" %s=%u", hs_names[i], hs_counts[i]);
#endif
    bm_printf("\n");
    return 1;
}

int main(void)
{
#if !HS_PROFILE
    rt_register_tests();
    utest_register_tests();
    rubik_register_tests();
    int rc = run_tests();
    if (rc)
        return rc;
    BENCH("rubik", "solve", HS_VARIANT, hs_inputs, 6,
          rubik_solve_asm(hs_states[in], hs_out, sizeof hs_out));
#else
    (void) hs_inputs;
    /* Instrumentation costs are excluded from performance comparisons.
     * Do not run instruction-budget tests on this diagnostic-only variant.
     */
#endif
    for (unsigned i = 0; i < 6; i++)
        if (!hs_case("bench6", i, hs_states[i], hs_distances[i]))
            return 1;
    for (unsigned i = 0; i < RUBIK_NCASES; i++)
        if (!hs_case("official59", i, rubik_cases[i].state,
                     rubik_cases[i].distance))
            return 1;
    if (!hs_case("directed", 0, "54721631111111", 11))
        return 1;
    return 0;
}
