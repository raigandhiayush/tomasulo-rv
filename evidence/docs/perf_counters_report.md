# perf_counters — implementation report (Person E, 19 Oct 2026; edge-case update 20 Oct)

> **Repo note (A, 21 Oct 2026):** imported into the repo. Files now live at `ooo_rtl/perf_counters.v`, `ooo_tests/tb_perf_counters.v`; `perf_counters.v` logic is unchanged (21 Oct: only its header comment now cites D21). In-repo run: `TEST_PASS perf_counters 674060`, log `evidence/20261021_e_perf_counters_tb_perf_counters.log` (via `simulation/run_unit_tests.sh`). E's sandbox log is `evidence/20261020_e_perf_counters_sandbox.log`. The `toma-rv/rtl`, `tb/` paths below are E's sandbox layout. Open point 1 is already settled by SIGNALS §2.1: `pipe_ooo` keeps the baseline `pipe` ports **plus** the `dbg_*` outputs after them (option a), so `top_fpga_ooo` can wire `dbg_*` straight to `perf_counters`. Points 2 and 3 were decided by A on 21 Oct as blueprint **D21**: counters wrap; `run = rst_n_sync & ~done`, so the done-store edge is counted and nothing after it, with the same rule for the baseline cycle counts.

Task (TASKS v0.3, E): implement `perf_counters.v` for cycle/commit/OoO-event evidence. Reviewer **A**. Evidence: counter increment and reset tests (plus reset/rollover, TASKS later day).

## Compliance checklist (extracted before coding)

| Item | Spec source | Value used |
|---|---|---|
| Module / file | SIGNALS_REFERENCE 2.16, blueprint 6.15 | `perf_counters` in `perf_counters.v` |
| Testbench file | blueprint 6.15 | `tb_perf_counters.v` |
| Clock / reset | SIGNALS_REFERENCE conventions, CLAUDE.md | `clk` in; `reset_n` in, active low, asynchronous |
| Inputs (1 bit each) | SIGNALS_REFERENCE 2.16 | `run`, `commit_valid`, `ooo_event`, `stall_rob`, `stall_rs`, `hold` |
| Outputs (32 bits each) | SIGNALS_REFERENCE 2.16 | `cycles`, `retired`, `ooo_count`, `rob_stall_cycles`, `rs_stall_cycles`, `hold_cycles` |
| Behaviour | blueprint 6.15 | count cycles while `run`; retired, OoO events, stall-reason cycles; `run = 0` freezes all |
| Test requirement | blueprint 6.15, TASKS | each counter vs testbench count over 1,000 random cycles; run=0 freeze; increment; reset; rollover |
| Pass line | CLAUDE.md, DoD L2 | `TEST_PASS perf_counters <n>` |
| Shared constants | CLAUDE.md | none needed (no ROB_W/ROB_N/NCDB in this block) |

## A. Files created or modified

| File | Status | Purpose |
|---|---|---|
| `toma-rv/rtl/perf_counters.v` | new | The module (design file). |
| `toma-rv/tb/tb_perf_counters.v` | new | Self-checking testbench named by blueprint 6.15. |
| `toma-rv/evidence/perf_counters_sim.log` | new | Saved run log (DoD L2) with command and tool version. |
| `toma-rv/docs/perf_counters_report.md` | new | This report. |

20 Oct update: only `tb_perf_counters.v` (new edge-case steps 9-16), the log and this report changed. `perf_counters.v` is unchanged (md5 `2ab45a27d35ce45a242aa526a67a9031`).

## B. Specification compliance

- Six 32-bit registers in one `always @(posedge clk or negedge reset_n)` block (one owner per register, nonblocking, no combinational logic, so no latches).
- `run = 1`: `cycles` +1 every cycle; each other counter +1 in a cycle where its input is 1. `run = 0`: all six hold (blueprint 6.15 "`run = 0` freezes all").
- `reset_n = 0` clears all six immediately (asynchronous), as in `div_unit` and `regfile_2r1w`.
- Outputs are the register values; they change only on a clock edge or reset.
- `ooo_defs.vh` is not included because the block uses none of its constants (CLAUDE.md's rule is about not hard-coding ROB/tag/bus sizes; none appear here).

## C. Interface and value verification

Checked by inspection against SIGNALS_REFERENCE 2.16 and by compiling the testbench, which connects every port by name (`.run(run)`, ... `.hold_cycles(hold_cycles)`):

| Port | Dir | Width | Matches spec |
|---|---|---|---|
| `clk`, `reset_n` | in | 1 | yes |
| `run`, `commit_valid`, `ooo_event`, `stall_rob`, `stall_rs`, `hold` | in | 1 | yes |
| `cycles`, `retired`, `ooo_count`, `rob_stall_cycles`, `rs_stall_cycles`, `hold_cycles` | out | 32 | yes |

**Executed port audit (20 Oct):** a script parsed the SIGNALS_REFERENCE 2.16 table and the RTL port list: 14 of 14 ports match in name, direction and width, there are no extra or missing ports, the module is named `perf_counters`, and the testbench connects all 14 by name. The RTL has no internal variables other than the six output registers. The `dbg_*` names in section E are copied from blueprint §5. `core_clk`, `core_reset_n` and `run` are placeholders for the nets inside your own `top_fpga_ooo`, which isn't written yet.

No parameters. Outputs are declared `output reg [31:0]`; this does not change the name, direction or width seen by an instantiating module.

## D. Additional verification files

Only `tb_perf_counters.v` (required by blueprint 6.15) and its log. Mutation tests, lint and synthesis were run from a scratch folder that is not part of the project.

## E. Integration instructions

Instantiate in `top_fpga_ooo` (blueprint 6.16) with named ports:

```verilog
perf_counters u_perf (
    .clk(core_clk), .reset_n(core_reset_n),
    .run(run),                         // 1 from reset release until MMIO done (0x1000_0004)
    .commit_valid(dbg_commit_valid), .ooo_event(dbg_ooo_event),
    .stall_rob(dbg_stall_rob), .stall_rs(dbg_stall_rs), .hold(dbg_hold),
    .cycles(cycles), .retired(retired), .ooo_count(ooo_count),
    .rob_stall_cycles(rob_stall_cycles), .rs_stall_cycles(rs_stall_cycles),
    .hold_cycles(hold_cycles));
```

The `dbg_*` sources are `ooo_core`'s debug outputs (blueprint section 5, SIGNALS_REFERENCE section 3). Compile with `iverilog -g2012 rtl/perf_counters.v ...`; no include path needed. In the repo the files move to `ooo_rtl/perf_counters.v` and `ooo_tests/tb_perf_counters.v`.

## Open points for A (reported, not decided)

1. **Conflict: how the `dbg_*` signals reach `perf_counters`.** Blueprint 6.16 puts `perf_counters` in `top_fpga_ooo` next to `pipe_ooo`, and SIGNALS_REFERENCE 3 routes `ooo_core dbg_*` to `perf_counters`. But `pipe_ooo` must keep **exactly** the baseline `pipe` ports (blueprint §1.3, §5, 6.14), which have no `dbg_*` outputs. So the top cannot see them. Options for A: (a) `pipe_ooo` gets extra `dbg_*` outputs (changes the "exactly these ports" rule); (b) `perf_counters` is instantiated inside `pipe_ooo`/`ooo_core` and its outputs exported (same problem for the 7-segment display); (c) the top instantiates `ooo_core` directly instead of `pipe_ooo`. `perf_counters.v` itself is unaffected by the choice.
2. *(Decided 21 Oct, D21: wrap.)* **Rollover: wrap or saturate?** TASKS asks to "check reset/rollover" but no file says which. The RTL wraps (plain 32-bit add, 0xFFFFFFFF -> 0) and the testbench checks that. At 50 MHz `cycles` wraps after about 86 s of `run = 1`; workloads end long before that and `run` drops at done.
3. *(Decided 21 Oct, D21: `run = rst_n_sync & ~done`.)* **`run` source.** SIGNALS_REFERENCE says "0 after `done`". Its rise (at reset release, or a cycle later) is set by `top_fpga_ooo`, not here; it decides whether the first cycle is counted, so it must match the baseline's "same done convention" (D17) when cycles are compared.

## F. Test results

Executed (Icarus Verilog 12.0, Verilator 5.020, Yosys 0.33, project sandbox, 20 Oct). Result: **TEST_PASS perf_counters 674060**, where every cycle checks all six outputs against the testbench count.

| # | Check | Result |
|---|---|---|
| 1 | Power-up in reset: outputs 0; clock edges ignored even with every input 1 | pass |
| 2 | `run = 0` after reset with every event 1: nothing counts | pass |
| 3 | Increment one input at a time and all together, with exact totals | pass |
| 4 | Freeze for 20 random cycles, then resume from the held value | pass |
| 5 | Async reset in the middle of a cycle: 0 before the next edge, held while low; the first cycle after release counts 1 | pass |
| 6 | 1,000 random cycles vs testbench count (blueprint 6.15) | pass |
| 7 | Rollover 0xFFFFFFFE -> 0xFFFFFFFF -> 0 -> 1 on all six; holds at 0xFFFFFFFF when `run = 0` | pass |
| 8 | 1,000 more random cycles with random async resets | pass |
| 9 | All 64 combinations of `{run, commit_valid, ooo_event, stall_rob, stall_rs, hold}`, up then down; exact totals 64/32/32/32/32/32 | pass |
| 10 | No carry-over: events seen while `run = 0` are not counted when `run` returns | pass |
| 11 | Carry into every bit: each counter at 2^k-1 goes to 2^k for k = 1..31 (186 checks, includes 0x7FFFFFFF -> 0x80000000) | pass |
| 12 | Independence: each of the six counters wraps alone while the others keep different values | pass |
| 13 | Pulses between clock edges are not counted; `run` glitching low between edges does not stop a count | pass |
| 14 | `reset_n` falling at the same instant as a rising edge with every input 1: reset wins | pass |
| 15 | 1 ns reset pulse between edges clears all | pass |
| 16 | Long run: 100,000 cycles with every input 1 (exact 100000), then 10,000 cycles with `run` toggling (exact 105000) | pass |
| - | Coverage minimums enforced by the testbench (combos 128, carries 186, glitches 10, wraps 12, async resets 12) | met |
| - | Port-name audit vs SIGNALS_REFERENCE 2.16 (section C) | 14/14 match |
| - | 18 broken RTL copies (mutants): sync reset, negedge clock, `run` ignored, `cycles` counting when `run = 0`, five input swaps, saturate, reset value 1, reset polarity, +2 step, 16-bit width, carry broken at bit 24 and bit 31, sticky event | 17 give TEST_FAIL. The one survivor (`hold \| !run`) behaves the same as the real design, because `!run` is always 0 inside the `run` branch. |
| - | `verilator --lint-only -Wall` on the RTL | clean |
| - | `iverilog -g2001` compile of the RTL | ok |
| - | `yosys synth_xilinx` | 192 FDCE (6x32, async clear), 48 CARRY4, 0 latches |

**Not executed:**
- Vivado `xvlog` compile and Vivado synthesis log (DoD L1); this needs a team machine.
- Review by A and merge (DoD L3).
- Reset released exactly on a clock edge. This is a race in any simulator, and `top_fpga_ooo`'s reset synchronizer (blueprint 6.16) prevents it on the board.

The testbench writes the DUT registers by hierarchical name for the rollover and carry steps. That is standard Verilog, but it hasn't been run in xsim yet. The open points above are not resolved by these tests.
