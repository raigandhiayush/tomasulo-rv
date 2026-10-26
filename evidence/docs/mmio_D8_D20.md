# MMIO implementation note: D8 / D20

Status: **E, 19 Oct 2026, for B's review. 21 Oct: Q1–Q6 decided by A as blueprint D22 (Q6 differs from E's proposal); counter `run` rule is D21.** Sources: PROJECT_BLUEPRINT v0.3 D8, D20, §3.6 rule 11, §6.16; SIGNALS_REFERENCE v0.3 §1.1, §1.3, §2.16, §2.17. Items the spec left open are listed under **Decided 21 Oct** below.

## Where it lives

In `top_fpga_ooo.v` and in the system testbench, **not in the core** (D8). `pipe_ooo` keeps the baseline `pipe` ports unchanged. The decode sits between the `pipe_ooo` data-memory ports and `data_mem`.

## Address map (D8, SIGNALS_REFERENCE §2.17)

| Address | Access | Effect |
|---|---|---|
| `0x1000_0000` | store | latches the **result** |
| `0x1000_0004` | store | sets **done** and stops the counters (`perf_counters.run` = 0 after done, §2.16) |
| `0x1000_0008` | load | returns the switches (a mux in front of the read data) |

## Rules (D20)

1. **Decode.** An address is MMIO when bits [31:28] = `4'h1`.
2. **MMIO never writes `data_mem`.** `data_mem.we = dmem_write_ready & (dmem_write_address[31:28] != 4'h1)`. `data_mem` decodes only bits [11:2], so without this gate a store to `0x1000_0000` would also overwrite word 0.
3. **Result and done** are written on `dmem_write_ready` with `dmem_write_address` = `0x1000_0000` / `0x1000_0004`, data from `dmem_write_data`. *(D22)* `result` is written per byte lane: lane *i* takes `dmem_write_data[8i+7:8i]` when `dmem_write_byte[i]` = 1. `done` is set by any store to `0x1000_0004`.
5. *(D21)* **Counters.** `perf_counters.run = rst_n_sync & ~done`. The edge that latches `done` is still counted; nothing after it.
4. **Switch-read mux uses the read address registered in the `LA` cycle.** The core drives `dmem_read_ready` / `dmem_read_address` in `LA`, and `data_mem.rdata` returns one cycle later (`LW`). So on `dmem_read_ready` the top registers whether `dmem_read_address` = `0x1000_0008`, and in the next cycle `pipe_ooo.dmem_read_data_temp` takes the switches when that registered flag is set, else `data_mem.rdata`. Selecting on the current `dmem_read_address` would pick the wrong source.

Nothing MMIO-specific is needed inside the core: stores write memory only in their commit cycle, loads start only after every older store has committed (§3.6 rule 11), and there is no speculation, so no wrong-path store can reach these addresses.

## Decided 21 Oct (blueprint D22; was "not in the spec")

| # | Question | E's proposal | A's decision (D22) |
|---|---|---|---|
| Q1 | The switches are 16 bits and the read is 32 bits. How are the upper 16 bits filled? | Zero-extend: `{16'd0, sw}` | Adopted |
| Q2 | Within the MMIO region, are the three addresses matched exactly or by low bits only? | Exact 32-bit match. Other MMIO addresses: store dropped, load returns 0 | Adopted as an exact **word-address** match (bits [31:2]); byte lanes come from `dmem_write_byte` / the LSU's load formatting, so `sh` to `0x1000_0002` still reaches `result`. A wrong pointer still cannot alias onto `result`. |
| Q3 | Does a store to `0x1000_0004` always set done, or does it take bit 0 of the data? | Always set; cleared only by reset | Adopted |
| Q4 | Are result and done cleared by reset? | Yes, by the top's synchronized `reset_n` | Adopted (otherwise `run` stays 0 after a second reset) |
| Q5 | Are the switches synchronized before the mux? (The spec names only a reset synchronizer.) | Two flip-flops | Adopted |
| Q6 | Byte/halfword stores (`dmem_write_byte` ≠ `4'b1111`) to result/done. | Write the full `dmem_write_data` word | **Changed: honour `dmem_write_byte` per lane.** The LSU replicates SB/SH data (`lsu.v`: SB drives `{4{byte}}`, strobe `0001 << off`), so a full-word latch turns `sb 5` into `0x05050505`. |

## Test plan (in `tb_top_fpga_ooo.v`, §6.16)

*21 Oct: implemented in `ooo_rtl/top_fpga_ooo.v` and `ooo_tests/tb_top_fpga_ooo.v` with the real `pipe_ooo` (no stub needed) running `ooo_tests/programs/top_mmio.s` four times (switches 0x0000, 0xFFFF, 0xA5A5, random). **TEST_PASS top_fpga_ooo 644.** Mutation check: 9 planted bugs (full-word result latch, byte-address match, low-bits match, ungated `data_mem.we`, switch mux on the current address, other-MMIO loads from RAM, sign-extended switches, `run` ignoring done, done surviving reset) all give TEST_FAIL. T8 uses a hand-assembled sort + MUL/DIV kernel because the C ports cannot be built yet (no toolchain).*

Self-checking; prints `TEST_PASS top_fpga_ooo <n>`; log in `evidence/`.

| # | Test | Expected |
|---|---|---|
| T1 | Reset, then read result and done | both 0 (Q4) |
| T2 | Store `0xCAFEBABE` to `0x1000_0000` | result = `0xCAFEBABE`; `data_mem` word 0 unchanged |
| T2b | After reset: `sb` of `0x05` to `0x1000_0000`, then `sh` of `0x1234` to `0x1000_0002` | result = `0x00000005`, then `0x12340005` (D22 Q6) |
| T3 | Store to `0x1000_0004` | done = 1; `perf_counters` stop counting (`cycles`, `retired` frozen) |
| T4 | Switches set to `0x0000`, `0xFFFF`, `0xA5A5`, random; load `0x1000_0008` | load returns the switch value (Q1) |
| T5 | Back-to-back loads alternating `0x1000_0008` and a RAM address | each load gets its own source (proves the registered-address mux) |
| T6 | Stores to every MMIO address, every byte-lane pattern | `data_mem.we` never 1; all `data_mem` words unchanged |
| T7 | Stores to `0x0000_0000` and `0x0FFF_FFFC` (bits [31:28] = 0) | reach `data_mem`; result and done unchanged |
| T8 | A ported D8 workload (`addition`, `sort`, `negative`, `xor`) | result matches the expected value; done = 1 |
| T9 | Run T8, assert reset, run it again (D21/D22) | second run: same result, same `cycles` and `retired` (counted from the first edge after reset release through the done-store edge) |

T1–T7 and T2b can run with a stub in place of `pipe_ooo` that drives the baseline `dmem_*` ports; T8 and T9 need the integrated core. `data_mem` has no initializer and no reset, so the workload must write every word before it reads it; then T9 holds without re-programming.
