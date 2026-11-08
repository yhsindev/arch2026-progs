#include "rubik.h"
#include "rubik_tables.h"

struct solution {
    uint8_t moves[11];
    unsigned length;
};

/* A record stores (permutation << 10 | orientation), distance, first move. */
static uint32_t terminal_find(unsigned p, unsigned o)
{
    unsigned key = (p << 10) | o;
    unsigned h = (key ^ (key >> 7) ^ (key >> 13)) & 16383u;
    for (;;) {
        uint32_t record = terminal[h];
        if (record == UINT32_MAX || (record >> 7) == key)
            return record;
        h = (h + 1) & 16383u;
    }
}

static int finish(unsigned p,
                  unsigned o,
                  unsigned depth,
                  unsigned remaining,
                  struct solution *answer)
{
    uint32_t record = terminal_find(p, o);
    if (record == UINT32_MAX || ((record >> 4) & 7u) > remaining)
        return 0;
    while ((record >> 4) & 7u) {
        unsigned move = record & 15u, face, turn;
        answer->moves[depth++] = (uint8_t) move;
        if (move < 3) {
            face = 0;
            turn = move + 1;
        } else if (move < 6) {
            face = 1;
            turn = move - 2;
        } else {
            face = 2;
            turn = move - 5;
        }
        do {
            p = perm_move[face * 5040 + p];
            o = ori_move[face * 729 + o];
        } while (--turn);
        record = terminal_find(p, o);
    }
    answer->length = depth;
    return 1;
}

/* Search a prefix, then certify its suffix using an exact terminal distance.
 * Consecutive equal faces cannot be necessary in a shortest solution.
 */
static int search(unsigned p,
                  unsigned o,
                  unsigned remaining,
                  unsigned previous,
                  unsigned depth,
                  struct solution *answer)
{
    if (perm_dist[p] > remaining || ori_dist[o] > remaining)
        return 0;
    if (remaining <= 5)
        return finish(p, o, depth, remaining, answer);
    for (unsigned face = 0; face < 3; face++) {
        if (face == previous)
            continue;
        unsigned pn = p, on = o;
        for (unsigned turn = 0; turn < 3; turn++) {
            pn = perm_move[face * 5040 + pn];
            on = ori_move[face * 729 + on];
            answer->moves[depth] = (uint8_t) (face * 3 + turn);
            if (search(pn, on, remaining - 1, face, depth + 1, answer))
                return 1;
        }
    }
    return 0;
}

int rubik_solve(const char *state, char *out, size_t cap)
{
    if (!state)
        return -1;
    unsigned cubies[7], seen = 0;
    for (unsigned i = 0; i < 7; i++) {
        unsigned digit = (unsigned char) state[i] - (unsigned) '1';
        if (digit >= 7 || (seen & (1u << digit)))
            return -1;
        seen |= 1u << digit;
        cubies[i] = digit;
    }
    unsigned p = 0;
    for (unsigned i = 0; i < 7; i++) {
        unsigned smaller = 0;
        for (unsigned j = i + 1; j < 7; j++)
            smaller += cubies[j] < cubies[i];
        p = p * (7 - i) + smaller;
    }
    unsigned o = 0, sum = 0;
    for (unsigned i = 0; i < 7; i++) {
        unsigned digit = (unsigned char) state[i + 7] - (unsigned) '1';
        if (digit >= 3)
            return -1;
        sum += digit;
        if (i < 6)
            o = o * 3 + digit;
    }
    if (state[14] != '\0')
        return -1;
    while (sum >= 3)
        sum -= 3;
    if (sum != 0)
        return -1;

    struct solution answer;
    if (!finish(p, o, 0, 5, &answer)) {
        unsigned bound = perm_dist[p];
        if (bound < ori_dist[o])
            bound = ori_dist[o];
        if (bound < 6)
            bound = 6;
        unsigned key = (p << 10) | o, low = 0, high = 2644;
        while (low < high) {
            unsigned mid = (low + high) >> 1;
            if (diameter[mid] < key)
                low = mid + 1;
            else
                high = mid;
        }
        if (low < 2644 && diameter[low] == key)
            bound = 11;
        while (!search(p, o, bound, 3, 0, &answer)) {
            if (++bound > 11)
                return -1;
        }
    }
    unsigned chars = 0;
    for (unsigned i = 0; i < answer.length; i++) {
        unsigned move = answer.moves[i];
        unsigned turn = move >= 6 ? move - 6 : move >= 3 ? move - 3 : move;
        chars += 1 + (turn != 0) + (i != 0);
    }
    if (cap <= chars) {
        if (cap)
            out[0] = '\0';
        return -2;
    }
    char *cursor = out;
    for (unsigned i = 0; i < answer.length; i++) {
        unsigned move = answer.moves[i];
        if (i)
            *cursor++ = ' ';
        *cursor++ = move < 3 ? 'R' : move < 6 ? 'B' : 'D';
        unsigned turn = move >= 6 ? move - 6 : move >= 3 ? move - 3 : move;
        if (turn)
            *cursor++ = turn == 1 ? '2' : '\'';
    }
    *cursor = '\0';
    return (int) answer.length;
}
