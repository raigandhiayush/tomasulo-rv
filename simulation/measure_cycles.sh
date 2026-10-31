#!/usr/bin/env bash
# Runs cycle measurement comparing pipe, pipe_m, and pipe_ooo against ref_model traces.
set -eu
cd "$(dirname "$0")/.."                      # tomasulo-rv/
# usage: simulation/measure_cycles.sh [program.hex] [sw, hex]; the program must end with the
# D8 done store (the original mem_generator/imem_dmem/imem.hex never does)
HEX="$(realpath "${1:-ooo_tests/programs/xor_d8.hex}")"
SW="${2:-0}"
mkdir -p simulation/build
TRACE="$PWD/simulation/build/measure.trace"
python3 -I tools/ref_model.py "$HEX" --sw "0x$SW" -o "$TRACE"

CORE="ooo_rtl/pipe_ooo.v ooo_rtl/ooo_core.v ooo_rtl/ooo_frontend.v ooo_rtl/instr_queue.v ooo_rtl/ooo_decode.v ooo_rtl/ooo_dispatch.v ooo_rtl/rat.v ooo_rtl/regfile_2r1w.v ooo_rtl/rob.v ooo_rtl/rs_array.v ooo_rtl/alu_fu.v ooo_rtl/mul_unit.v ooo_rtl/div_unit.v ooo_rtl/lsu.v ooo_rtl/l1_dcache.v ooo_rtl/bpred.v ooo_rtl/mem_wait.v"
iverilog -g2012 -DTOMA_SIM -DMEM_WAIT=0 -DDC_WB=0 -I ooo_rtl -I modules -o simulation/build/tb_baseline_counters \
  ooo_rtl/top_fpga_ooo.v baseline_fpga/top_fpga_base.v ooo_rtl/perf_counters.v $CORE modules/memory.v \
  modules/pipeline.v modules/IF_ID.v modules/execute.v modules/wb.v \
  baseline_m/pipeline_m.v baseline_m/IF_ID_m.v baseline_m/execute_m.v \
  simulation/tb_baseline_counters.v
out="$(cd simulation && vvp -n build/tb_baseline_counters +hex="$HEX" +trace="$TRACE" +sw="$SW")"
echo "$out" | grep -E '^(PERF|DCACHE|BASELINE_BUG|TEST_)'
echo "$out" | awk '/^PERF/ && /cycles=/ { split($3, c, "="); split($7, n, "="); cyc[c[2]] = n[2] }
  END {
    if (cyc["pipe_ooo"] == "") exit
    if (cyc["pipe"]   != "") printf "speed-up pipe   / pipe_ooo = %.3f\n", cyc["pipe"]   / cyc["pipe_ooo"]
    if (cyc["pipe_m"] != "") printf "speed-up pipe_m / pipe_ooo = %.3f\n", cyc["pipe_m"] / cyc["pipe_ooo"]
  }'
echo "$out" | grep -q '^TEST_PASS'
