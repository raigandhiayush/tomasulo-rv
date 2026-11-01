#!/usr/bin/env bash
# Assemble test programs using tools/rvasm.py and generate reference commit traces.
set -eu
cd "$(dirname "$0")/.."                      # tomasulo-rv/
P=ooo_tests/programs
for s in "$P"/*.s; do
  python3 -I tools/rvasm.py "$s" -o "${s%.s}.hex"
done
# expected traces: <program> <sw value> <max commits>
python3 -I tools/ref_model.py "$P/top_mmio.hex"   --sw 0xA5A5 -o "$P/top_mmio.trace"
python3 -I tools/ref_model.py "$P/ooo_trace.hex"  -o "$P/ooo_trace.trace"
python3 -I tools/ref_model.py "$P/rv32m_edge.hex" -o "$P/rv32m_edge.trace"
python3 -I tools/ref_model.py "$P/base_rv32i.hex"  -o "$P/base_rv32i.trace"
python3 -I tools/ref_model.py "$P/pipe_m_edge.hex" -o "$P/pipe_m_edge.trace"
python3 -I tools/ref_model.py "$P/mul_stream.hex"    -o "$P/mul_stream.trace"
python3 -I tools/ref_model.py "$P/muldiv_stream.hex" -o "$P/muldiv_stream.trace"
python3 -I tools/ref_model.py mem_generator/imem_dmem/imem.hex --max 200 -o "$P/xor_baseline.trace"

# Optional C workload builds when a RISC-V GCC toolchain is present.
# RV32I workloads build with -march=rv32i (make <prog>_d8), so the same image also
# runs on the baseline (D17); RV32M workloads need -march=rv32im (make <prog>_d8_im).
C_PROGS_I="addition sort negative xor"
C_PROGS_M="mul div rv32m"
C_PROGS="$C_PROGS_I $C_PROGS_M"
PFX=${RISCV_PREFIX:-}
if [ -z "$PFX" ]; then
  for c in riscv-none-elf- riscv64-unknown-elf-; do
    if command -v "${c}gcc" >/dev/null; then PFX=$c; break; fi
  done
fi
if [ -n "$PFX" ]; then
  M=mem_generator/imem_dmem
  SAVE=$(mktemp -d)
  cp "$M"/imem.hex "$M"/imem.bin "$M"/dmem.hex "$M"/dmem.bin "$M"/code.dis "$SAVE"/
  trap 'cp "$SAVE"/* "$M"/; rm -r "$SAVE"' EXIT
  for p in $C_PROGS; do
    case " $C_PROGS_M " in
      *" $p "*) tgt="${p}_d8_im" ;;
      *)        tgt="${p}_d8" ;;
    esac
    make -s -C mem_generator "$tgt" CC="${PFX}gcc" OBJCOPY="${PFX}objcopy" OBJDUMP="${PFX}objdump"
    cp "$M"/imem.hex "$P/${p}_d8.hex"
    cp "$M"/code.dis "$P/${p}_d8.dis"
  done
else
  echo "build_test_programs: no RISC-V gcc, C workloads ($C_PROGS) not rebuilt"
fi
for p in $C_PROGS; do
  if [ -f "$P/${p}_d8.hex" ]; then
    python3 -I tools/ref_model.py "$P/${p}_d8.hex" -o "$P/${p}_d8.trace"
  fi
done
