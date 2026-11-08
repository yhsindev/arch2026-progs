# Fixed-point arithmetic checkpoint

Verified locally on 2026-11-08 with GCC 15.2.0 and rv32emu ffb041b.
These source changes have not been committed.

The C adder preserves the observable carry-loop count. Unsigned subtraction
wraps modulo 2^32. The C average halves each operand before adding, including
the extra unit when both are odd. Assembly uses the equivalent identity
(a & b) + ((a ^ b) >> 1), saving two instructions.

The C product combines four unsigned 16-bit partial products, then restores
the sign. Casting after each multiplication avoids an unavailable __muldi3;
the only external implementation symbol is the supplied __mulsi3. Assembly
uses a low/high register pair and shift-and-add multiplication of unsigned
magnitudes. Both handle INT32_MIN, add 2^19 before shifting by 20, round ties
toward positive infinity, and keep the low 32 output bits without saturation.

Host ASan/UBSan: 15 passed, 0 failed, no sanitizer report. The official driver
passes all four optimization levels, ISA, instruction budgets, performance,
disassembly, and footprint checks: 55/55 in fixed-only mode.

| Function | Best C cycles/call | Assembly cycles/call | Speedup |
| --- | ---: | ---: | ---: |
| op1 | 24.6875 | 22.125 | 1.12x |
| op2 | 4 | 4 | 1.00x |
| op3 | 9 | 7 | 1.29x |
| q_mul | 318.75 | 220.625 | 1.44x |

The implementation text is 212 bytes for assembly versus 360 bytes for the
smallest C build; no implementation data sections are allocated. Runtime and
test harness sizes are excluded. The emulator counts executed instructions;
these figures do not predict hardware pipeline or cache latency.

Reproduce with the commands in notes/PROGRESS.md, using --prog fixed.
