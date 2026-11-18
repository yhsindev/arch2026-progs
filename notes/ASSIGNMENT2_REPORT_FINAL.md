# Assignment 2: Measured Optimizations on RV32I

**Implementation:** [ef7eaee](https://github.com/yhsindev/arch2026-progs/tree/ef7eaee1684875372bbbde966716e17c59eca99c). Main measurements: November 8, 2026; Rubik controlled experiment and numerical-error recheck: November 18.

## 1. Measurement method and results

Environment: GCC 15.2.0, `-march=rv32i_zicsr -mabi=ilp32 -ffreestanding`, and rv32emu ffb041b with system emulation, ELF loading, and the interpreter. The guest has a 4 KiB stack, no allocator, and no hardware multiply/divide or floating point. Calls to the supplied software `__mulsi3` remain inside measured work.

The [harness][bench] reads 64-bit counters with rollover protection, measures N calls, and subtracts a matching input-copy loop:

~~~text
mean count = (call-loop count - copy-loop count) / N
reduction = 100 * (1 - assembly mean / fastest C mean)
~~~

Checksums prevent deletion. Tests, printing, and offline table generation are excluded; operand preparation, the op1 count wrapper, and Rubik parsing/output formatting remain included. Inputs are the [six Rubik states][rubik-bench] at distances 0/2/4/6/8/9 and sixteen fixed words per [BF16][bf16-bench], [GCD][gcd-bench], and [fixed][fixed-bench] function.

rv32emu counts executed guest instructions, not physical CPU latency. One deterministic pass supplies these workload means, not worst-case bounds. Each row selects the fastest C among four builds and assembly from that **same ELF**; values are rounded, percentages use unrounded data.

| Function | C O1 | C O2 | C O3 | C Os | Assembly (ELF) | Reduction |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Rubik | 45,328.500 | 38,057.167 | 33,123.333 | 48,142.333 | 26,552.000 (O3) | 19.84% |
| BF16 narrow | 11.062 | 11.188 | 12.812 | 11.188 | 12.250 (O1) | -10.73% |
| BF16 multiply | 94.312 | 87.188 | 88.625 | 91.312 | 65.500 (O2) | 24.87% |
| BF16 root | 326.062 | 323.375 | 324.812 | 332.000 | 45.875 (O2) | 85.81% |
| GCD | 101.625 | 116.625 | 118.812 | 119.688 | 90.438 (O1) | 11.01% |
| op1 | 27.250 | 24.688 | 26.812 | 24.688 | 22.125 (O2) | 10.38% |
| op2 | 4.000 | 4.000 | 5.938 | 4.000 | 4.000 (O1) | 0.00% |
| op3 | 9.000 | 9.000 | 10.938 | 9.000 | 7.000 (O1) | 22.22% |
| Q multiply | 329.188 | 318.750 | 320.688 | 325.750 | 220.625 (O2) | 30.78% |

O1 is best for GCD; choosing O2 alone would overstate the gain. Rubik O3 reduces counts while growing C text from 1,944 to 7,580 bytes. Caller/baseline differences can also change adjusted means. BF16 narrowing is 1.1875 counts slower, within the framework's two-count tolerance; subtraction ties C.

## 2. Binary GCD

[C][gcd-c], [assembly][gcd-s], [contract][gcd-h], [tests][gcd-tests].

Stein's identities replace division:

$$
\gcd(2a,2b)=2\gcd(a,b),\quad
\gcd(2a,b)=\gcd(a,b)\text{ for odd }b.
$$

After removing powers of two, subtracting the smaller odd operand preserves the GCD and decreases the positive state. A nonzero odd-minus-odd difference is even. Assembly therefore jumps directly into the shift body:

~~~asm
sub  a1, a1, a0
bnez a1, .Lgcd_right
~~~

Bottom-tested loops remove redundant jumps/parity checks. The combined loop-control implementation reduces the benchmark count by 11.01%. Zero operands return directly; unsigned comparisons handle the complete 32-bit range.

Verification compares all 65,536 eight-bit pairs against Euclid, plus extremes, powers, random pairs, and algebraic properties. Results are exact on checked inputs. Fraction reduction on dividerless embedded processors is a direct application.

## 3. Bitwise arithmetic and Q11.20

[C][fixed-c], [assembly][fixed-s], [contract][fixed-h], [tests][fixed-tests].

For op1, each pass computes carry=(a & b)<<1, a=a^b, b=carry. The identity $a+b=(a\oplus b)+2(a\land b)$ preserves the sum modulo $2^{32}$; carries move left and vanish within 32 passes. Assembly retains the required iteration count but stores it once. Direct addition would violate that contract. Op2 is simply unsigned subtraction modulo $2^{32}$.

For op3,

$$
\left\lfloor(a+b)/2\right\rfloor=(a\land b)+((a\oplus b)\gg1).
$$

It avoids losing a carry from a 32-bit sum. Compiled O2 C uses seven instructions including return; the handwritten form uses five, matching the benchmark's reduction from 9 to 7 counts.

Signed Q11.20 stores $A/2^{20}$, with spacing $2^{-20}$ and range $[-2048,2048-2^{-20}]$. Multiplication requires

$$
R=\left\lfloor(AB+2^{19})/2^{20}\right\rfloor
$$

followed by low-32-bit wrap. Ties round toward positive infinity: stored inputs (3,524288) give 2, while (-3,524288) give -1.

C splits unsigned magnitudes, including INT32_MIN, and expands $(A_h2^{16}+A_l)(B_h2^{16}+B_l)$ into four 16×16 products. Widening afterward avoids unavailable `__muldi3`; O2 contains four `__mulsi3` calls. Assembly uses one register-pair shift-and-add loop, restores sign, propagates rounding carry, then extracts:

~~~asm
srli a0, t0, 20
slli t1, t1, 12
or   a0, a0, t1
~~~

The whole multiplication improves 30.78%. Before wrap, real error is $-2^{-21}<R/2^{20}-AB/2^{40}\le2^{-21}$; wrap invalidates that bound. Integer operations are exact. Tests cover independent references, a 64×64 grid, random pairs, carry counts, ties, zero and INT32_MIN. Embedded scaling benefits from this arithmetic only when the application plans its overflow range.

## 4. BF16 arithmetic

[C][bf16-c], [assembly][bf16-s], [contract][bf16-h], [tests][bf16-tests].

BF16 has sign s, eight exponent bits E (bias 127), and seven fraction bits F:

$$
x=(-1)^s(1+F/128)2^{E-127}\ (1\le E\le254);
\quad x=(-1)^sF2^{-133}\ (E=0).
$$

Minimum positive normal/subnormal values are $2^{-126}$/$2^{-133}$; maximum finite magnitude is $(2-2^{-7})2^{127}$. Normal spacing is $2^{E-134}$.

Narrowing adds 0x7FFF plus bit 16 for nearest-even rounding; exponent-all-ones inputs truncate unchanged. Finite results have at most half an output ULP rounding error; overflow may produce infinity. Assembly preserves this behavior without improving the benchmark.

Multiplication normalizes subnormal inputs, multiplies eight-bit significands, adjusts the exponent, and truncates. Assembly replaces a general helper with local shift-and-add, reducing counts 24.87%. The contract's operand order and underflow rule matter: a first infinity can swallow a second NaN, and denormal output shifts the fraction after hidden-bit removal.

For positive normals, m=128+F is doubled when the unbiased exponent is odd. C square root repeatedly squares binary-search midpoints; its threshold is

$$
\lfloor r^2/128\rfloor\le m
\iff r^2\le128(m+1)-1.
$$

Assembly computes that radicand's integer square root in eight restoring rounds, removing multiplication and reducing counts 85.81%. Using 128m would change answers. NaNs are preserved; either signed zero and positive subnormals produce +0; negative nonzero values produce the canonical NaN.

Host analysis decodes BF16 exactly into binary64 and compares with host arithmetic; the November 18 rerun reproduced:

| Domain | Inputs | Maximum relative error | Example |
| --- | ---: | ---: | --- |
| Square root, positive normals | 32,512 | 0.388351% | 0x0081 → 0x2000 |
| Multiply, both operands in [1,2) | 16,384 pairs | 0.769184% | 0x3F9E × 0x3FD1 → 0x4000 |

Normal-product truncation loses less than one output ULP away from exceptional ranges. The multiplication maximum covers only the stated domain; no fixed relative bound is claimed at zero, underflow or overflow. Tests check every square-root encoding, narrowing sweeps, a 256×256 multiplication grid and all encodings against eight constants. Reduced-precision inference storage is an application, but these arithmetic measurements do not establish model accuracy.

## 5. Rubik: compact search and hotspot measurement

[C][rubik-c], [assembly][rubik-s], [generator][generator], [contract][rubik-h], [tests][rubik-tests]. The model follows [minirubik](https://github.com/sysprog21/minirubik).

Fixing one corner leaves $7!\times3^6=3,674,160$ legal states: the seventh twist follows from the sum-modulo-three constraint. Each R/R2/R', B/B2/B', D/D2/D' costs one. The API validates fourteen characters, returns -1 without modifying output for invalid states, and -2 for insufficient capacity.

Permutation/orientation transition tables avoid rebuilding corners per move. Payload bytes are: transitions 34,614 + abstract distances 5,769 + terminal hash table 65,536 + distance-eleven keys 10,576 = 116,495 before alignment. Full BFS runs only during host table generation.

The maximum of permutation-only and orientation-only distances is an admissible lower bound; their sum could double-count moves. Search increases bounds, excludes mergeable consecutive same-face moves, and accepts an exact radius-five suffix only when it fits the remaining budget. Thus smaller bounds are exhausted before accepting a shortest solution. Verified distance-eleven membership permits starting those roots at eleven.

A terminal record packs (key<<7)|(distance<<4)|move, with key=(p<<10)|o; full-key comparison resolves hash collisions. Each stored move decreases exact suffix distance.

### Controlled change: reject misses before creating a frame

Current assembly checks an empty slot before entering the 32-byte reconstruction frame:

~~~asm
lw  t3, 0(t1)
beq t3, t4, .Lrubik_search_fail
~~~

A generated O2 ablation removes only this inline precheck, keeping tables, pruning, pointer probing and search order. It is a counterfactual, not a historical version. Both uninstrumented variants pass the unchanged 52-test suite.

A third ELF counts events separately from performance. Over 59 public states: T=32,441 attempts, M=32,405 misses, H=36 hits, C=242,563 collisions, W=0 wraps. Miss rate is 99.889%; average probe length is 8.477 slots. Verified disassembly gives

$$
I_{probe}=13T+2M+4H+6C+2W=1,942,065.
$$

This is 43.35% of net solve-call instructions, a derived instruction share, not sampled CPU time.

| Workload/unit | Without precheck | Current | Reduction |
| --- | ---: | ---: | ---: |
| Six-state BENCH mean/call | 29,138.333 | 26,549.833 | 8.88% |
| 59-state net count sum | 4,964,670 | 4,479,585 | 9.77% |

The improvement costs 84 code bytes (1,488→1,572); 36 public cases improve and 23 tie. This isolates the precheck, not pointer-only gains or all-state worst cases. Diagnostic counts use a different O2 caller from the original compiler comparison.

Independent tests apply the output moves and check known minimum lengths, invalid inputs and capacities. Solver assembly uses at most 528 bytes of frames, preserving saved registers and alignment. Compact offline abstraction plus online search is useful for memory-bounded planning.

## 6. Space, validation and reproduction

Allocated implementation bytes from size -A exclude debug data and the shared harness. The C rows select the smallest build independently of speed.

| Variant | .text | .rodata | .data | .bss | Total |
| --- | ---: | ---: | ---: | ---: | ---: |
| Rubik C Os | 1,792 | 116,500 | 0 | 0 | 118,292 |
| Rubik asm | 1,572 | 116,496 | 0 | 0 | 118,068 |
| BF16 C Os | 672 | 0 | 0 | 0 | 672 |
| BF16 asm | 520 | 0 | 0 | 0 | 520 |
| GCD C Os | 120 | 0 | 0 | 0 | 120 |
| GCD asm | 132 | 0 | 0 | 0 | 132 |
| Fixed C O2 | 360 | 0 | 0 | 0 | 360 |
| Fixed asm | 212 | 0 | 0 | 0 | 212 |

Rubik's largest C build is O3 at 124,080 bytes; all fit 131,072 including code. GCD's gain costs twelve bytes; BF16/fixed assembly save 152/148 bytes against smallest C.

The [November 9 CI](https://github.com/yhsindev/arch2026-progs/actions/runs/42459082381/attempts/2) scored 100/100 for ef7eaee using the instructor's harness: four builds, host ASan/UBSan, ISA/symbol restrictions and budgets. Recorded host summaries are GCD 13/0, fixed 15/0, BF16 17/0, Rubik 23/0. Check printed summaries, not host exit status alone. Average results do not establish per-call budgets; finite binary-operation tests do not enumerate every 32-bit pair.

With prerequisites installed, reproduce using `make cycles dump size sanitize test`, `python3 notes/report-assets/measure_error.py`, and `python3 mytests/rubik_hotspot.py`. [Measurement evidence](https://github.com/yhsindev/arch2026-progs/tree/main/notes/report-assets) includes raw CSVs, experiment logs and SHA-256 metadata. All arguments and key results are in this report; no other draft is required.

AI tools assisted implementation, debugging, experiment tooling and drafting. Only the Rubik precheck has an isolated per-edit measurement; other gains compare complete C/assembly implementations. CodeTrial recording is a separate deliverable.

[bench]: https://github.com/yhsindev/arch2026-progs/blob/ef7eaee1684875372bbbde966716e17c59eca99c/common/bench.h
[rubik-bench]: https://github.com/yhsindev/arch2026-progs/blob/ef7eaee1684875372bbbde966716e17c59eca99c/tests/mrubik.c
[bf16-bench]: https://github.com/yhsindev/arch2026-progs/blob/ef7eaee1684875372bbbde966716e17c59eca99c/tests/mbf16.c
[gcd-bench]: https://github.com/yhsindev/arch2026-progs/blob/ef7eaee1684875372bbbde966716e17c59eca99c/tests/mgcd.c
[fixed-bench]: https://github.com/yhsindev/arch2026-progs/blob/ef7eaee1684875372bbbde966716e17c59eca99c/tests/mfixed.c
[gcd-c]: https://github.com/yhsindev/arch2026-progs/blob/ef7eaee1684875372bbbde966716e17c59eca99c/src/gcd/gcd.c
[gcd-s]: https://github.com/yhsindev/arch2026-progs/blob/ef7eaee1684875372bbbde966716e17c59eca99c/src/gcd/gcd.S#L21
[gcd-tests]: https://github.com/yhsindev/arch2026-progs/blob/ef7eaee1684875372bbbde966716e17c59eca99c/tests/tgcd.c
[fixed-c]: https://github.com/yhsindev/arch2026-progs/blob/ef7eaee1684875372bbbde966716e17c59eca99c/src/fixed/fixed.c
[fixed-s]: https://github.com/yhsindev/arch2026-progs/blob/ef7eaee1684875372bbbde966716e17c59eca99c/src/fixed/fixed.S#L17
[fixed-tests]: https://github.com/yhsindev/arch2026-progs/blob/ef7eaee1684875372bbbde966716e17c59eca99c/tests/tfixed.c
[bf16-c]: https://github.com/yhsindev/arch2026-progs/blob/ef7eaee1684875372bbbde966716e17c59eca99c/src/bf16/bf16.c
[bf16-s]: https://github.com/yhsindev/arch2026-progs/blob/ef7eaee1684875372bbbde966716e17c59eca99c/src/bf16/bf16.S#L133
[bf16-tests]: https://github.com/yhsindev/arch2026-progs/blob/ef7eaee1684875372bbbde966716e17c59eca99c/tests/tbf16.c
[rubik-c]: https://github.com/yhsindev/arch2026-progs/blob/ef7eaee1684875372bbbde966716e17c59eca99c/src/rubik/rubik.c
[rubik-s]: https://github.com/yhsindev/arch2026-progs/blob/ef7eaee1684875372bbbde966716e17c59eca99c/src/rubik/rubik.S#L338
[rubik-tests]: https://github.com/yhsindev/arch2026-progs/blob/ef7eaee1684875372bbbde966716e17c59eca99c/tests/trubik.c
[generator]: https://github.com/yhsindev/arch2026-progs/blob/ef7eaee1684875372bbbde966716e17c59eca99c/notes/gen_rubik_tables.c
[gcd-h]: https://github.com/yhsindev/arch2026-progs/blob/ef7eaee1684875372bbbde966716e17c59eca99c/src/gcd/gcd.h
[fixed-h]: https://github.com/yhsindev/arch2026-progs/blob/ef7eaee1684875372bbbde966716e17c59eca99c/src/fixed/fixed.h
[bf16-h]: https://github.com/yhsindev/arch2026-progs/blob/ef7eaee1684875372bbbde966716e17c59eca99c/src/bf16/bf16.h
[rubik-h]: https://github.com/yhsindev/arch2026-progs/blob/ef7eaee1684875372bbbde966716e17c59eca99c/src/rubik/rubik.h
