/* Host-only table generator. Model: sysprog21/minirubik (MIT).
 * Enumerate the whole graph on the host; emit only transitions, abstract
 * distances, the radius-five ball and the distance-eleven set for the target.
 */
#include <stdint.h>
#include <stdio.h>
#include <string.h>

enum { NP = 5040, NO = 729, NST = NP * NO, NH = 16384 };
static const uint8_t source[3][7] = {{1, 4, 2, 0, 3, 5, 6},
                                     {0, 1, 2, 4, 5, 6, 3},
                                     {0, 2, 5, 3, 1, 4, 6}};
static const uint8_t twist[3][7] = {{1, 2, 0, 2, 1, 0, 0},
                                    {0, 0, 0, 1, 2, 1, 2},
                                    {0, 0, 0, 0, 0, 0, 0}};
static uint16_t pm[3 * NP], om[3 * NO];
static uint8_t pd[NP], od[NO], distance[NST], back[NST];
static uint32_t queue[NST], terminal[NH], diameter[2644];

static unsigned rank_perm(const uint8_t p[7])
{
    unsigned rank = 0;
    for (unsigned i = 0; i < 7; i++) {
        unsigned smaller = 0;
        for (unsigned j = i + 1; j < 7; j++)
            smaller += p[j] < p[i];
        rank = rank * (7 - i) + smaller;
    }
    return rank;
}

static void transitions(void)
{
    for (unsigned rank = 0; rank < NP; rank++) {
        uint8_t available[7] = {0, 1, 2, 3, 4, 5, 6}, p[7];
        unsigned r = rank, factorial = 720;
        for (unsigned i = 0; i < 7; i++) {
            unsigned q = r / factorial;
            r %= factorial;
            p[i] = available[q];
            for (unsigned j = q; j + 1 < 7 - i; j++)
                available[j] = available[j + 1];
            if (i < 5)
                factorial /= 6 - i;
        }
        for (unsigned face = 0; face < 3; face++) {
            uint8_t next[7];
            for (unsigned i = 0; i < 7; i++)
                next[i] = p[source[face][i]];
            pm[face * NP + rank] = (uint16_t) rank_perm(next);
        }
    }
    for (unsigned rank = 0; rank < NO; rank++) {
        uint8_t o[7];
        unsigned r = rank, sum = 0;
        for (int i = 5; i >= 0; i--) {
            o[i] = r % 3;
            sum += o[i];
            r /= 3;
        }
        o[6] = (3 - sum % 3) % 3;
        for (unsigned face = 0; face < 3; face++) {
            unsigned next = 0;
            for (unsigned i = 0; i < 6; i++)
                next = next * 3 + (o[source[face][i]] + twist[face][i]) % 3;
            om[face * NO + rank] = (uint16_t) next;
        }
    }
}

static void abstract_dist(const uint16_t *move, unsigned n, uint8_t *dist)
{
    memset(dist, 255, n);
    unsigned head = 0, tail = 1;
    queue[0] = 0;
    dist[0] = 0;
    while (head < tail) {
        unsigned r = queue[head++];
        for (unsigned face = 0; face < 3; face++) {
            unsigned next = r;
            for (unsigned turn = 0; turn < 3; turn++) {
                next = move[face * n + next];
                if (dist[next] == 255) {
                    dist[next] = dist[r] + 1;
                    queue[tail++] = next;
                }
            }
        }
    }
}

static int full_dist(void)
{
    memset(distance, 255, sizeof distance);
    unsigned head = 0, tail = 1;
    queue[0] = 0;
    distance[0] = 0;
    while (head < tail) {
        unsigned state = queue[head++], p = state / NO, o = state % NO;
        for (unsigned face = 0; face < 3; face++) {
            unsigned pn = p, on = o;
            for (unsigned turn = 0; turn < 3; turn++) {
                pn = pm[face * NP + pn];
                on = om[face * NO + on];
                unsigned next = pn * NO + on;
                if (distance[next] == 255) {
                    distance[next] = distance[state] + 1;
                    back[next] = face * 3 + (2 - turn);
                    queue[tail++] = next;
                }
            }
        }
    }
    if (tail != NST)
        return 1;
    memset(terminal, 255, sizeof terminal);
    unsigned near = 0, far = 0, histogram[12] = {0};
    for (unsigned state = 0; state < NST; state++) {
        unsigned d = distance[state], key = ((state / NO) << 10) | (state % NO);
        if (d > 11)
            return 1;
        histogram[d]++;
        if (d <= 5) {
            unsigned h = (key ^ (key >> 7) ^ (key >> 13)) & (NH - 1);
            while (terminal[h] != UINT32_MAX)
                h = (h + 1) & (NH - 1);
            terminal[h] = (key << 7) | (d << 4) | back[state];
            near++;
        }
        if (d == 11) {
            if (far >= 2644)
                return 1;
            diameter[far++] = key;
        }
    }
    for (unsigned d = 0; d < 12; d++)
        printf("distance %u: %u states\n", d, histogram[d]);
    printf("radius-five %u; diameter %u; total %u\n", near, far, tail);
    return near != 12224 || far != 2644;
}

static void emit(FILE *c,
                 FILE *s,
                 const char *name,
                 unsigned width,
                 const void *data,
                 unsigned n)
{
    fprintf(c, "static const uint%u_t %s[%u] = {\n", width, name, n);
    fprintf(s, "    .balign %u\n.Lrubik_%s:\n", width / 8, name);
    for (unsigned i = 0; i < n; i++) {
        unsigned row = width == 32 ? 6 : 10;
        uint32_t v = width == 32   ? ((const uint32_t *) data)[i]
                     : width == 16 ? ((const uint16_t *) data)[i]
                                   : ((const uint8_t *) data)[i];
        if (i % row == 0) {
            fprintf(c, "    ");
            fprintf(s, "    .%s ",
                    width == 32   ? "word"
                    : width == 16 ? "half"
                                  : "byte");
        }
        if (width == 32) {
            fprintf(c, "0x%08xu,", v);
            fprintf(s, "0x%08x", v);
        } else {
            fprintf(c, "%u,", v);
            fprintf(s, "%u", v);
        }
        if (i % row == row - 1 || i + 1 == n) {
            fprintf(c, "\n");
            fprintf(s, "\n");
        } else {
            fprintf(c, " ");
            fprintf(s, ", ");
        }
    }
    fprintf(c, "};\n\n");
}

int main(void)
{
    transitions();
    abstract_dist(pm, NP, pd);
    abstract_dist(om, NO, od);
    if (full_dist()) {
        fprintf(stderr, "Cube graph verification failed\n");
        return 1;
    }
    FILE *c = fopen("src/rubik/rubik_tables.h", "w");
    FILE *s = fopen("src/rubik/rubik_tables.inc", "w");
    if (!c || !s)
        return 1;
    fprintf(
        c,
        "/* Generated by notes/gen_rubik_tables.c; host-only full BFS. */\n");
    fprintf(c, "#pragma once\n\n#include <stdint.h>\n\n");
    fprintf(s,
            "# Generated by notes/gen_rubik_tables.c; independent assembly "
            "data.\n");
    emit(c, s, "perm_move", 16, pm, 3 * NP);
    emit(c, s, "ori_move", 16, om, 3 * NO);
    emit(c, s, "perm_dist", 8, pd, NP);
    emit(c, s, "ori_dist", 8, od, NO);
    emit(c, s, "terminal", 32, terminal, NH);
    emit(c, s, "diameter", 32, diameter, 2644);
    return fclose(c) != 0 || fclose(s) != 0;
}
