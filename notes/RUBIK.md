# Optimal Rubik solver checkpoint

Verified on 2026-11-08 with GCC 15.2.0, the instructor framework fd2d7c1 and
rv32emu ffb041b. The corner model is from sysprog21/minirubik (MIT), matching
Assignment 1. C and hand-written assembly have independent table definitions.

## Tables and optimality

The host-only generator, notes/gen_rubik_tables.c, builds the three quarter-turn
transition tables in each abstraction, then performs a full breadth-first
enumeration of all 3,674,160 legal states. It emits only these target tables:

- Permutation and orientation transitions: 34,614 bytes.
- Abstract distances: 5,769 bytes.
- Radius-five open-addressed hash table: 65,536 bytes, 12,224 occupied slots.
- Sorted distance-eleven keys: 10,576 bytes, 2,644 entries.

The key is (permutation << 10) | orientation. A hash-table record packs that
key, its exact suffix distance, and a first move that decreases the distance.
Empty slots use UINT32_MAX. Linear probing wraps at the table end.

The target validates the complete input before touching the output. It uses
iterative deepening for the prefix, prunes with both abstract distances, and
finishes using a suffix whose exact distance fits the remaining bound. Adjacent
equal faces are omitted because they combine into one move or cancel. The
complete diameter table permits starting at eleven for those states; absence
from the radius-five table proves a lower bound of six for all others.
These bounds and increasing depth prove the first solution is shortest.

The assembly probes unsuccessful terminal states before allocating a suffix
frame. Pointer increments and an explicit end comparison replace repeated hash
index scaling. Prefix recursion uses at most six 64-byte frames, plus a
112-byte public frame and a 32-byte suffix frame, comfortably below 4 KiB.
All callee-saved registers are restored on every public return path.

## Evidence and measured trade-offs

- Host ASan/UBSan: 23 passed, 0 failed, no sanitizer report.
- Official target suite: 52 passed, 0 failed at all four optimization levels;
  includes exact shortest distances, malformed inputs, output formatting and
  every buffer capacity around the required length.
- Additional personal checker: all 2,644 distance-eleven states pass for the
  host C build and target C/assembly. It reuses the instructor's independent
  physical-cube checker without changing tests/trubik.c.
- Across all diameter states at O2, the largest measured C count is 4,692,809
  and the assembly count is 3,201,222, both at 54721631111111. Budgets are
  50,000,000 and 7,500,000 respectively. These maxima cover the complete
  diameter set, not every state at shorter distances.
- Official benchmark: fastest C is O3 at 33,123.33 cycles/call; assembly is
  26,549.5, approximately 1.25x faster.
- Assembly allocated sections total 118,068 bytes (1,572 text + 116,496 data).
  C ranges from 118,292 bytes at Os to 124,080 at O3. All fit 131,072 bytes.
- A fresh clone of the instructor's framework, with a fresh emulator build,
  grades the entire submission 100/100 and produces all three charts.

The whole-state distance arrays and queue exist only in the host generator;
they are not linked into either implementation. Tables contain general states,
not the grading vectors, and each query performs target-side search.
The original Assignment 1 CLI and renderer are left untouched.

## Reproduction

From the repository root, regenerate the source tables with:

    cc -O2 notes/gen_rubik_tables.c -o /tmp/gen-rubik
    /tmp/gen-rubik
    source notes/activate.sh
    clang-format-20 -i src/rubik/rubik_tables.h

Rebuild the assembly after regenerating its include file, for example with
make clean followed by make test. The personal test source and complete
diameter input set are in mytests/rubik_diameter.c and
mytests/rubik_diameter_states.h. The test includes the instructor's checker;
it does not replace or weaken the grading harness.

The English HackMD write-up and the personally completed CodeTrial interview
and recording remain separate submission requirements; a full script score
does not establish that those manual requirements are complete.
