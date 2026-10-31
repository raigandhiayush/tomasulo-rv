#!/usr/bin/env bash
# Build and run unit testbenches with Icarus Verilog and record evidence logs.
# Usage: simulation/run_unit_tests.sh [owner-letter] [test-name ...]
set -u
cd "$(dirname "$0")/.."                      # tomasulo-rv/
EVID="evidence"
mkdir -p simulation/build "$EVID"
WHO="${1:-b}"
shift $(( $# > 0 ? 1 : 0 ))
ONLY=" $* "
DATE="$(date +%Y%m%d)"
TOOL="$(iverilog -V 2>&1 | head -1)"
COMMIT="$(git -C . rev-parse --short HEAD 2>/dev/null || echo 'none (uncommitted working tree)')"
DIRTY="$(git -C . status --porcelain 2>/dev/null | head -1 | grep -q . && echo ' +uncommitted changes' || true)"

CORE_SRCS="ooo_rtl/pipe_ooo.v ooo_rtl/ooo_core.v ooo_rtl/ooo_frontend.v ooo_rtl/instr_queue.v ooo_rtl/ooo_decode.v ooo_rtl/ooo_dispatch.v ooo_rtl/rat.v ooo_rtl/regfile_2r1w.v ooo_rtl/rob.v ooo_rtl/rs_array.v ooo_rtl/alu_fu.v ooo_rtl/mul_unit.v ooo_rtl/div_unit.v ooo_rtl/lsu.v ooo_rtl/l1_dcache.v ooo_rtl/bpred.v ooo_rtl/mem_wait.v"
TOP_SRCS="ooo_rtl/top_fpga_ooo.v ooo_rtl/perf_counters.v $CORE_SRCS modules/memory.v"

# name | owner | spec | sources
TESTS=(
  "tb_alu_fu|c|blueprint 6.9|ooo_rtl/alu_fu.v ooo_tests/tb_alu_fu.v"
  "tb_rs_array|c|blueprint 6.8|ooo_rtl/rs_array.v ooo_tests/tb_rs_array.v"
  "tb_alu_path|c|blueprint 3.6 rules 4,5; 6.8+6.9|ooo_rtl/rs_array.v ooo_rtl/alu_fu.v ooo_tests/tb_alu_path.v"
  "tb_ooo_frontend|c|blueprint 6.4, rule 12|ooo_rtl/instr_queue.v ooo_rtl/ooo_frontend.v ooo_tests/tb_ooo_frontend.v"
  "tb_regfile_2r1w|e|blueprint 6.5|ooo_rtl/regfile_2r1w.v ooo_tests/tb_regfile_2r1w.v"
  "tb_div_unit|e|blueprint 6.11, rule 6|ooo_rtl/div_unit.v ooo_tests/tb_div_unit.v"
  "tb_div_unit_vectors|e|blueprint 6.11, div_unit_test_cases.md section A (ooo_tests/vectors)|ooo_rtl/div_unit.v ooo_tests/tb_div_unit_vectors.v"
  "tb_perf_counters|e|blueprint 6.15, SIGNALS 2.16|ooo_rtl/perf_counters.v ooo_tests/tb_perf_counters.v"
  "tb_instr_queue|d|blueprint 6.3|ooo_rtl/instr_queue.v ooo_tests/tb_instr_queue.v"
  "tb_instr_queue_d8|d|blueprint 6.3 at DEPTH=8 (count width fix)|-Ptb_instr_queue.DEPTH=8 ooo_rtl/instr_queue.v ooo_tests/tb_instr_queue.v"
  "tb_mul_unit|d|blueprint 6.10, rule 6|ooo_rtl/mul_unit.v ooo_tests/tb_mul_unit.v"
  "tb_ooo_decode|d|blueprint 6.2|ooo_rtl/ooo_decode.v ooo_tests/tb_ooo_decode.v"
  "tb_rob|b|blueprint 6.7, rules 2,8|ooo_rtl/rob.v ooo_tests/tb_rob.v"
  "tb_lsu|b|blueprint 6.12, rules 7,11, D10, D13|ooo_rtl/lsu.v ooo_tests/tb_lsu.v"
  "tb_lsu_realmem|b|blueprint 6.12 with the real baseline data_mem|-DREAL_DMEM modules/memory.v ooo_rtl/lsu.v ooo_tests/tb_lsu.v"
  "tb_l1_dcache|a|L1 data cache: 5 configs (2-way WB, 2-way WT, direct-mapped WB 8-word, 2-way WB and WT on slow memory) vs golden memory + cache-state model, real data_mem|modules/memory.v ooo_rtl/l1_dcache.v ooo_rtl/mem_wait.v ooo_tests/tb_l1_dcache.v"
  "tb_baseline_probe|b|blueprint 1.3 baseline (xor program in imem.hex)|-I modules modules/pipeline.v modules/memory.v modules/IF_ID.v modules/execute.v modules/wb.v simulation/tb_baseline_probe.v"
  "tb_rat|a|blueprint 6.6, rule 10|ooo_rtl/rat.v ooo_tests/tb_rat.v"
  "tb_ooo_dispatch|a|blueprint 6.13, rule 3, D11-D16|ooo_rtl/ooo_decode.v ooo_rtl/ooo_dispatch.v ooo_tests/tb_ooo_dispatch.v"
  "tb_ooo_core|a|blueprint 6.14, section 3.6 (directed + random RV32IM vs ISA model)|$CORE_SRCS modules/memory.v ooo_tests/tb_ooo_core.v"
  "tb_ooo_system|a|blueprint 6.14, pipe_ooo vs baseline pipe on imem.hex|-I modules $CORE_SRCS modules/pipeline.v modules/memory.v modules/IF_ID.v modules/execute.v modules/wb.v ooo_tests/tb_ooo_system.v"
  "tb_top_fpga_ooo|e|blueprint 6.16, D8, D20-D22, MMIO test plan T1-T9|-DTOMA_SIM $TOP_SRCS ooo_tests/tb_top_fpga_ooo.v"
  "tb_commit_trace|e|blueprint 6.17 reference model + commit-trace compare|-DTOMA_SIM $TOP_SRCS ooo_tests/tb_commit_trace.v"
  "tb_baseline_counters|c|D17, D21, D24, blueprint 4.3: pipe / pipe_m / pipe_ooo cycle counts, cross-checked with top_fpga_ooo and top_fpga_base|-DTOMA_SIM -I modules $TOP_SRCS baseline_fpga/top_fpga_base.v modules/pipeline.v modules/IF_ID.v modules/execute.v modules/wb.v baseline_m/pipeline_m.v baseline_m/IF_ID_m.v baseline_m/execute_m.v simulation/tb_baseline_counters.v"
  "tb_ooo_event_trace|c|TASKS 19 Oct: ooo_event, non-head completion per bus, 2+ bus cycles; cycle-exact scenario of ooo_trace.s, built for fixed 1-cycle loads, so run without the data cache (DC_EN=0); the cached core's multi-bus cycles are counted by tb_ooo_core|-DTOMA_SIM -DDC_EN=0 $TOP_SRCS ooo_tests/tb_ooo_event_trace.v"
  "tb_bpred|a|bpred: BTB + 2-bit counters|FULL ooo_rtl/bpred.v ooo_tests/tb_bpred.v"
  "tb_mem_wait|a|mem_wait: exact timing, burst, write buffer, ordering, random vs golden|FULL modules/memory.v ooo_rtl/mem_wait.v ooo_tests/tb_mem_wait.v"
  "tb_ooo_core_spec|a|random RV32IM vs ISA model with speculation on|FULL -DMEM_WAIT=0 -DDC_WB=0 $CORE_SRCS modules/memory.v ooo_tests/tb_ooo_core.v"
  "tb_commit_trace_spec|a|21 programs (8 looping stress) vs ref model: default build: speculation + 2-way write-back + slow memory|FULL -DTOMA_SIM $TOP_SRCS ooo_tests/tb_commit_trace.v"
  "tb_commit_trace_chaos|a|same with the predictor randomly corrupted while running|FULL -DTOMA_SIM -DSPEC_CHAOS $TOP_SRCS ooo_tests/tb_commit_trace.v"
  "tb_commit_trace_wt|a|same with a write-through cache and a corrupted predictor|FULL -DTOMA_SIM -DSPEC_CHAOS -DDC_WB=0 $TOP_SRCS ooo_tests/tb_commit_trace.v"
  "tb_commit_trace_nocache|a|same with no cache and slow memory|FULL -DTOMA_SIM -DDC_EN=0 $TOP_SRCS ooo_tests/tb_commit_trace.v"
  "tb_commit_trace_fast|a|same with speculation and data_mem at full speed|FULL -DTOMA_SIM -DMEM_WAIT=0 $TOP_SRCS ooo_tests/tb_commit_trace.v"
  "tb_top_fpga_ooo_spec|a|board self-test T1-T9 on the default build|FULL -DTOMA_SIM $TOP_SRCS ooo_tests/tb_top_fpga_ooo.v"
  "tb_baseline_counters_spec|a|pipe / pipe_m / pipe_ooo counts with speculation (data_mem at full speed: the baselines have no wait support)|FULL -DTOMA_SIM -DMEM_WAIT=0 -DDC_WB=0 -I modules $TOP_SRCS baseline_fpga/top_fpga_base.v modules/pipeline.v modules/IF_ID.v modules/execute.v modules/wb.v baseline_m/pipeline_m.v baseline_m/IF_ID_m.v baseline_m/execute_m.v simulation/tb_baseline_counters.v"
  "check_elf|e|blueprint 6.17 tools/check_elf.py (synthetic ELFs + ooo_decode cross-check)|py:tools/test_check_elf.py"
  "rvasm|a|tools/rvasm.py encodings vs gcc (code.dis)|py:tools/rvasm.py --selftest"
)

fail=0
for t in "${TESTS[@]}"; do
  IFS='|' read -r name owner spec srcs <<< "$t"
  [ "$ONLY" != "  " ] && [[ "$ONLY" != *" $name "* ]] && continue
  log="$EVID/${DATE}_${owner}_${name#tb_}_${name}.log"
  rm -f simulation/pipeline.vcd simulation/pipeline_output.txt
  if [[ "$srcs" == py:* ]]; then
    cmd="python3 -I ${srcs#py:}"
  else
    case "$srcs" in FULL*) defs=""; srcs="${srcs#FULL}" ;; *) defs="-DSPEC_EN=0 -DMEM_WAIT=0 -DDC_WB=0" ;; esac
    cmd="iverilog -g2012 -I ooo_rtl $defs -o simulation/build/$name $srcs && (cd simulation && vvp -n build/$name)"
  fi
  start=$(date +%s)
  out="$(eval "$cmd" 2>&1)"; rc=$?
  secs=$(( $(date +%s) - start ))
  if echo "$out" | grep -q "^TEST_PASS" && ! echo "$out" | grep -q "^TEST_FAIL"; then res=PASS; else res=FAIL; fail=1; fi
  summary="$(echo "$out" | grep -E '^TEST_(PASS|FAIL)' | tail -1)"
  simtime="$(echo "$out" | sed -n 's/.*\$finish called at \([0-9]*\) (1ps).*/\1/p')"
  {
    echo "=== TOMA-RV Test Evidence ==="
    echo "Date: $(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo "Owner (module): $(echo "$owner" | tr a-z A-Z)   Run by: $(echo "$WHO" | tr a-z A-Z)"
    echo "Module: ${name#tb_}"
    echo "Specification: $spec"
    echo "Tool: $TOOL"
    echo "Command: $cmd"
    echo "Working directory: tomasulo-rv"
    echo "Commit: $COMMIT$DIRTY"
    echo "Exit status: $rc"
    echo "Simulated time: ${simtime:-?} ps (10 ns clock => $(( ${simtime:-0} / 10000 )) cycles)"
    echo "Wall time: ${secs}s"
    echo "Test result: $res"
    echo "Summary: $summary"
    echo "---"
    echo "$out" | grep -v "^warning: Some design\|^       :" | tail -80
    echo "---"
  } > "$log"
  printf '%-18s %s  %s\n' "$name" "$res" "$summary"
done
exit $fail
