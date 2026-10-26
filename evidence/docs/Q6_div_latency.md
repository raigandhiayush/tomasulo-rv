# Q6: DIV latency and `busy` in the done cycle

Status: **proposed by E on 16 Oct 2026; revised by B on 20 Oct 2026 to match the `div_unit.v` in `ooo_rtl/` and SIGNALS_REFERENCE v0.3 §2.12. Signed off by A on 20 Oct 2026**; blueprint rule 6 / §6.11 and SIGNALS §2.12 updated.

> Revision note (B, 20 Oct): E's first draft described a variant with a synchronous active-high `rst`, a `flush` port and `done` at T+34. The RTL in the repo is the spec-conformant variant: asynchronous active-low `reset_n` (CLAUDE.md invariant), no `flush` (D9: no speculation in the commitment design), and `done` at t+33 as in blueprint rule 6. The sign fix is folded into the 32nd iteration, so there is no separate FIX cycle. Occupancy is still the planned 34 cycles (t .. t+33).

## Decision

1. **Fixed latency: `done` exactly at t+33** for DIV, DIVU, REM and REMU, for every operand including x/0 and INT_MIN/-1. No early-out.
   Measured in Icarus Verilog 12.0 by `ooo_tests/tb_div_unit.v` (24,146 checks, corner grid + exhaustive −10..10 + walking ones + random): min 33, max 33. Evidence: `evidence/20261020_e_div_unit_tb_div_unit.log`.
2. **`busy` is 0 in the done cycle.** A new op can start in t+33, the cycle the previous result appears. Initiation interval = 33 cycles.
3. Issue rule for C's DIV RS: **`iss_accept = ~busy`, `start = iss_valid & ~busy`** (already wired that way in C's core fragment). A `start` while busy is ignored.
4. `done` is a one-cycle pulse. `result` and `done_tag` stay valid after it until the next done.
5. `reset_n` (asynchronous, active low) aborts an op in flight; no `done` is produced for it.

## Timing (start sampled in cycle t)

```
cycle   t     t+1   ...   t+32  t+33  t+34
start   1     0           0     0/1
busy    0     1     ...   1     0     (1 if started at t+33)
done    0     0           0     1     0
result  old   old         old   NEW   NEW
```
t+1..t+32 are the 32 restoring iterations; the last one also applies the sign fix and the x/0 select.

## Why

- Fixed latency keeps the timing diagrams to one picture and makes the RS issue rule a single check of `busy`. With four CDBs (D6) the DIV owns `cdb_div`, so `done` is never refused and no hold-until-ack handshake is needed.
- Dropping `busy` in the done cycle removes a dead cycle between back-to-back divides at no hardware cost.

## Ports (SIGNALS_REFERENCE v0.3 §2.12)

| Port | Dir | Width | Meaning |
|---|---|---|---|
| clk, reset_n | in | 1 | reset_n asynchronous, active low |
| start | in | 1 | begin op (only when busy==0) |
| funct3 | in | 2 | 00 DIV, 01 DIVU, 10 REM, 11 REMU |
| a, b | in | 32 | dividend rs1, divisor rs2 (latched at start) |
| tag | in | ROB_W | ROB tag, returned on done_tag |
| busy | out | 1 | 1 from t+1 to t+32 |
| done | out | 1 | 1-cycle pulse at t+33 |
| result | out | 32 | quotient or remainder |
| done_tag | out | ROB_W | tag of the finished op |

Run (from `tomasulo-rv/`): `iverilog -g2012 -I ooo_rtl -o simulation/build/tb_div_unit ooo_rtl/div_unit.v ooo_tests/tb_div_unit.v && vvp simulation/build/tb_div_unit`

## Closed
- A signed off points 1–5 on 20 Oct 2026; blueprint rule 6 / §6.11 and the SIGNALS §2.12 `busy` row now say "0 in the done cycle".
