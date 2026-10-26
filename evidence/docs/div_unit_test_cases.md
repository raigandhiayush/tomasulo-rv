# div_unit edge-case list

Testbench: `ooo_tests/tb_div_unit.v` (ported by B on 20 Oct 2026 to the SIGNALS v0.3 §2.12 ports). Result on 20 Oct 2026 (Icarus Verilog 12.0): **`TEST_PASS div_unit 24146`**, 0 failures, latency min 33 / max 33. Log: `evidence/20261020_e_div_unit_tb_div_unit.log`.
Every operation is also checked for latency = 33 (t+33), `busy` = 1 in every cycle between start and done, `busy` = 0 in the done cycle, correct `done_tag`, `done` lasting one cycle, and `result` held after done. Operands on `a`/`b`/`funct3` are scrambled right after start to prove they were latched.
E's original run (16 Oct, earlier variant with `done` at T+34) cross-checked 3446 results against a separate Python RV32M model: 0 mismatches.
Section A values are also kept as a separate vector list, `ooo_tests/vectors/div_unit_vectors.mem` (made by `tools/gen_div_vectors.py`, its own RV32M model, fixed seed), run by `ooo_tests/tb_div_unit_vectors.v`: **`TEST_PASS div_unit 4852`** on 21 Oct 2026, log `evidence/20261021_e_div_unit_vectors_tb_div_unit_vectors.log`. The vector file is generated: edit the script, not the `.mem`.

## A. Arithmetic corner cases (all four ops: DIV, DIVU, REM, REMU)

| # | Case | Example | Expected (RISC-V spec) | Covered by |
|---|---|---|---|---|
| A1 | Divide by zero, positive dividend | 7 / 0 | DIV/DIVU = 0xFFFFFFFF, REM/REMU = 7 | corner grid |
| A2 | Divide by zero, negative dividend | -7 / 0 | DIV = 0xFFFFFFFF (not +1), REM = -7 | corner grid |
| A3 | Zero divided by zero | 0 / 0 | quotient 0xFFFFFFFF, remainder 0 | corner grid |
| A4 | INT_MIN / 0 | 0x80000000 / 0 | DIV = 0xFFFFFFFF, REM = 0x80000000 | corner grid |
| A5 | Signed overflow | INT_MIN / -1 | DIV = INT_MIN, REM = 0 | corner grid |
| A6 | Same bits as unsigned | 0x80000000 /u 0xFFFFFFFF | DIVU = 0, REMU = 0x80000000 | corner grid |
| A7 | INT_MIN by ±1, ±2, INT_MIN, INT_MAX | INT_MIN / INT_MIN | 1, rem 0 | corner grid |
| A8 | INT_MIN+1 / -1 | 0x80000001 / -1 | INT_MAX | corner grid |
| A9 | Zero dividend | 0 / x | 0, rem 0 | corner grid, small exhaustive |
| A10 | Divide by 1 and by -1 | x / ±1 | x or -x, rem 0 | corner grid |
| A11 | Divisor larger than dividend | 3 / 7 | 0, rem 3 | corner grid, small exhaustive |
| A12 | Dividend equals divisor | x / x | 1, rem 0 | corner grid |
| A13 | Remainder sign follows dividend | -7 % 2, 7 % -2 | -1, +1 | corner grid, small exhaustive |
| A14 | All four sign combinations | ±7 / ±2 | trunc toward zero | corner grid, small exhaustive |
| A15 | Exact negative quotient (no -0 remainder) | -6 / 3 | -2, rem 0 | small exhaustive |
| A16 | 0xFFFFFFFF as -1 (signed) vs max (unsigned) | 0xFFFFFFFF / 2 | DIV = 0, DIVU = 0x7FFFFFFF | corner grid |
| A17 | Largest dividend, divisor 1 | 0xFFFFFFFF /u 1 | 0xFFFFFFFF (all 32 quotient bits set) | corner grid, walking one |
| A18 | Divisor with top bit set (unsigned) | x /u 0x80000000 | 0 or 1 | corner grid, walking one |
| A19 | Divisor every power of two 2^0..2^31 | 0xFFFFFFFF / 2^j | shift result | walking one (128 ops) |
| A20 | Dividend every power of two | 2^j / 3 | | walking one (128 ops) |
| A21 | Half-word patterns | 0x00010000, 0xFFFF0000 | | corner grid |

Corner grid = every pair of these 16 values, all four ops (1024 ops):
0, 1, -1, INT_MIN, INT_MAX, 7, -7, 2, -2, 0x12345678, INT_MIN+1, INT_MAX-1, 0x00010000, 0xFFFF0000, 3, -3.

Small exhaustive = every pair of a, b in -10..10, all four ops (1764 ops).
Random = 400 ops with random operands, 1 in 4 with an 8-bit divisor and 1 in 4 with a small signed divisor.

## B. Control and timing cases

| # | Case | What is checked |
|---|---|---|
| B1 | `start` held during reset | ignored, no busy/done after reset releases |
| B2 | Outputs right after reset | busy = 0, done = 0, result = 0 |
| B3 | Latency of every op | exactly 33 cycles (min 33, max 33) |
| B4 | `busy` during the op | 1 in every cycle t+1 .. t+32 |
| B5 | `busy` in the done cycle | 0 (Q6 decision) |
| B6 | `done` width | one cycle only |
| B7 | `result` after done | held until the next done |
| B8 | Operands change after start | result uses the latched values |
| B9 | Back-to-back ops | second start in the done cycle is accepted, latency still 33 |
| B10 | `start` held high continuously | second op starts in the done cycle, correct result and tag |
| B11 | `start` while busy | ignored, first op's result and tag come out |
| B12 | Every tag value 0..7 | returned unchanged on `done_tag` |
| B13 | Asynchronous `reset_n` pulse mid-op (no clock edge) | busy clears at once, no done, next op correct |
| B14 | `reset_n` in the last busy cycle (t+32) | no done |
| B15 | `reset_n` held across a clock edge mid-op | busy clears, no done, next op correct |

## C. Proof that the tests catch bugs (mutation check, B, 20 Oct, ported testbench)

| Bug planted in div_unit.v | Result |
|---|---|
| Divide-by-zero quotient not forced to 0xFFFFFFFF | TEST_FAIL, 34 failures |
| Remainder sign not applied | TEST_FAIL, 623 failures |
| Latency one cycle short (done at t+32) | TEST_FAIL, 8774 failures |

## D. Not covered yet

- Integration with C's DIV reservation station and `cdb_div` (needs `ooo_core`).
- Gate-level / post-synthesis timing on the Nexys A7 (needs Vivado).
- The DIV edge-case table in `VERIFICATION_AND_SUBMISSION.md`, which is missing from the project, so this list has not been compared against it.
