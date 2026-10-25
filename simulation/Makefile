# --- Variables ---
# filelist.txt holds the baseline, the OoO core, pipe_m and every system testbench;
# -top picks which one runs. TOMA_SIM replaces the MMCM/BUFG in top_fpga_ooo
# (otherwise xelab stops: MMCME2_BASE / BUFG not found); it does not affect the baseline.
BFLAGS   = -d TOMA_SIM -i ../modules -i ../ooo_rtl -f filelist.txt
TOP_MOD  = tb_pipeline
SNAPSHOT = riscv_sim
MEM_GEN  = ../mem_generator
PY      ?= $(if $(filter Windows_NT,$(OS)),python,python3)

# RV32M workloads build with -march=rv32im (make <p>_d8_im), the rest with rv32i
RV32M_PROGS = mul div rv32m

# Vivado Tools
XVLOG = xvlog
XELAB = xelab
XSIM  = xsim

.PHONY: help clean sort addition negative xor board_test

help:
	@echo "Usage: make <program_name>  baseline tb_pipeline on the original C code (e.g. make addition)"
	@echo "       make board_test      tb_top_fpga_ooo on top_mmio.hex (expect TEST_PASS top_fpga_ooo)"
	@echo "       make ooo_<prog>      D8 C workload on pipe / pipe_m / pipe_ooo with cycle counts"
	@echo "                            <prog> = addition sort negative xor mul div rv32m"

# Generic Rule for all programs (baseline, original C code)
xor sort addition negative:
	# 1. Generate Hex Files
	$(MAKE) clean -C $(MEM_GEN)
	$(MAKE) $@ -C $(MEM_GEN)

	# 2. Vivado Simulation Flow
	$(XVLOG) $(BFLAGS)
	$(XELAB) -top $(TOP_MOD) -snapshot $(SNAPSHOT) -debug typical

	# 3. Run Simulation (log to stdout to see display)
	$(XSIM) $(SNAPSHOT) -runall -log stdout

# OoO board-level self-test (top_mmio.hex, MMIO tests T1-T9)
board_test:
	$(XVLOG) $(BFLAGS)
	$(XELAB) -top tb_top_fpga_ooo -snapshot ooo_board -debug typical
	$(XSIM) ooo_board -runall -log stdout

# D8 C workload: result checked against tools/ref_model.py, D21 cycles on all cores
ooo_%:
	# 1. Generate Hex Files (rv32im for RV32M workloads)
	$(MAKE) clean -C $(MEM_GEN)
	$(MAKE) $(if $(filter $*,$(RV32M_PROGS)),$*_d8_im,$*_d8) -C $(MEM_GEN)

	# 2. Expected result and commit count
	mkdir -p build
	$(PY) ../tools/ref_model.py $(MEM_GEN)/imem_dmem/imem.hex -o build/measure.trace

	# 3. Vivado Simulation Flow
	$(XVLOG) $(BFLAGS)
	$(XELAB) -top tb_baseline_counters -snapshot ooo_cycles -debug typical
	$(XSIM) ooo_cycles -runall -log stdout -testplusarg hex=../mem_generator/imem_dmem/imem.hex -testplusarg trace=build/measure.trace

clean:
	@rm -rf xsim.dir/ .Xil/
	@rm -f xvlog.log xvlog.pb xelab.log xelab.pb xsim.log xsim.jou xsim.pb
	@rm -f pipeline.vcd
	@rm -f build/measure.trace
