// tb_commit_trace - Verification testbench comparing RTL commit trace against reference model.
`timescale 1ns/1ps
`include "ooo_defs.vh"

module tb_commit_trace;

	localparam NPROG   = 22;
	localparam TIMEOUT = 100000;

	reg                 clk = 1'b0;
	reg                 reset = 1'b0;
	reg     [15: 0]     sw = 16'd0;
	always #5 clk = ~clk;

	wire    [15: 0]     led;
	wire    [ 7: 0]     seg, an;

	top_fpga_ooo #(.REFRESH_W(2)) DUT (.clk(clk), .reset(reset), .sw(sw), .led(led), .seg(seg), .an(an));

	// ---- program list: hex, expected trace, switch value -------------------
	reg     [8*64-1:0]  p_hex   [0:NPROG-1];
	reg     [8*64-1:0]  p_trace [0:NPROG-1];
	reg     [15: 0]     p_sw    [0:NPROG-1];

	initial begin
		p_hex[0] = "../mem_generator/imem_dmem/imem.hex";   p_trace[0] = "../ooo_tests/programs/xor_baseline.trace"; p_sw[0] = 16'h0000;
		p_hex[1] = "../ooo_tests/programs/top_mmio.hex";    p_trace[1] = "../ooo_tests/programs/top_mmio.trace";     p_sw[1] = 16'hA5A5;
		p_hex[2] = "../ooo_tests/programs/ooo_trace.hex";   p_trace[2] = "../ooo_tests/programs/ooo_trace.trace";    p_sw[2] = 16'h0000;
		p_hex[3] = "../ooo_tests/programs/rv32m_edge.hex";  p_trace[3] = "../ooo_tests/programs/rv32m_edge.trace";   p_sw[3] = 16'h0000;
		p_hex[4] = "../ooo_tests/programs/mul_d8.hex";      p_trace[4] = "../ooo_tests/programs/mul_d8.trace";       p_sw[4] = 16'h0000;
		p_hex[5] = "../ooo_tests/programs/div_d8.hex";      p_trace[5] = "../ooo_tests/programs/div_d8.trace";       p_sw[5] = 16'h0000;
		p_hex[6] = "../ooo_tests/programs/rv32m_d8.hex";    p_trace[6] = "../ooo_tests/programs/rv32m_d8.trace";     p_sw[6] = 16'h0000;
		p_hex[7] = "../ooo_tests/programs/addition_d8.hex"; p_trace[7] = "../ooo_tests/programs/addition_d8.trace";  p_sw[7] = 16'h0000;
		p_hex[8] = "../ooo_tests/programs/sort_d8.hex";     p_trace[8] = "../ooo_tests/programs/sort_d8.trace";      p_sw[8] = 16'h0000;
		p_hex[9] = "../ooo_tests/programs/negative_d8.hex"; p_trace[9] = "../ooo_tests/programs/negative_d8.trace";  p_sw[9] = 16'h0000;
		p_hex[10] = "../ooo_tests/programs/xor_d8.hex";     p_trace[10] = "../ooo_tests/programs/xor_d8.trace";      p_sw[10] = 16'h0000;
		// constructed best cases for the pipelined MUL / MUL in a DIV shadow (A, 26 Oct; D17: not typical)
		p_hex[11] = "../ooo_tests/programs/mul_stream.hex"; p_trace[11] = "../ooo_tests/programs/mul_stream.trace";  p_sw[11] = 16'h0000;
		p_hex[12] = "../ooo_tests/programs/muldiv_stream.hex"; p_trace[12] = "../ooo_tests/programs/muldiv_stream.trace"; p_sw[12] = 16'h0000;
		// branch speculation stress (tools/gen_spec_programs.py)
		p_hex[13] = "../ooo_tests/programs/spec_stress_0.hex"; p_trace[13] = "../ooo_tests/programs/spec_stress_0.trace"; p_sw[13] = 16'h0000;
		p_hex[14] = "../ooo_tests/programs/spec_stress_1.hex"; p_trace[14] = "../ooo_tests/programs/spec_stress_1.trace"; p_sw[14] = 16'h0000;
		p_hex[15] = "../ooo_tests/programs/spec_stress_2.hex"; p_trace[15] = "../ooo_tests/programs/spec_stress_2.trace"; p_sw[15] = 16'h0000;
		p_hex[16] = "../ooo_tests/programs/spec_stress_3.hex"; p_trace[16] = "../ooo_tests/programs/spec_stress_3.trace"; p_sw[16] = 16'h0000;
		p_hex[17] = "../ooo_tests/programs/spec_stress_4.hex"; p_trace[17] = "../ooo_tests/programs/spec_stress_4.trace"; p_sw[17] = 16'h0000;
		p_hex[18] = "../ooo_tests/programs/spec_stress_5.hex"; p_trace[18] = "../ooo_tests/programs/spec_stress_5.trace"; p_sw[18] = 16'h0000;
		p_hex[19] = "../ooo_tests/programs/spec_stress_6.hex"; p_trace[19] = "../ooo_tests/programs/spec_stress_6.trace"; p_sw[19] = 16'h0000;
		p_hex[20] = "../ooo_tests/programs/spec_stress_7.hex"; p_trace[20] = "../ooo_tests/programs/spec_stress_7.trace"; p_sw[20] = 16'h0000;
		p_hex[21] = "../ooo_tests/programs/base_rv32i.hex"; p_trace[21] = "../ooo_tests/programs/base_rv32i.trace"; p_sw[21] = 16'h0000;
	end

	// ---- expected trace ----------------------------------------------------
	localparam MAXL = 4096;
	reg     [31: 0]     e_kind [0:MAXL-1];
	reg     [31: 0]     e_pc   [0:MAXL-1];
	reg     [31: 0]     e_rd   [0:MAXL-1];
	reg     [31: 0]     e_val  [0:MAXL-1];
	reg     [31: 0]     e_addr [0:MAXL-1];
	reg     [31: 0]     e_lane [0:MAXL-1];
	reg     [31: 0]     e_strb [0:MAXL-1];
	integer             n_exp, fd, nf;
	reg     [31: 0]     f0, f1, f2, f3, f4, f5, f6;

	task read_trace(input [8*64-1:0] fname);
		begin
			n_exp = 0;
			fd = $fopen(fname, "r");
			if (fd == 0) begin
				$display("TEST_FAIL commit_trace cannot open %0s", fname);
				$finish;
			end
			while (!$feof(fd) && n_exp < MAXL) begin
				nf = $fscanf(fd, "%h %h %h %h %h %h %h\n", f0, f1, f2, f3, f4, f5, f6);
				if (nf == 7) begin
					e_kind[n_exp] = f0; e_pc[n_exp] = f1; e_rd[n_exp] = f2; e_val[n_exp] = f3;
					e_addr[n_exp] = f4; e_lane[n_exp] = f5; e_strb[n_exp] = f6;
					n_exp = n_exp + 1;
				end
			end
			$fclose(fd);
		end
	endtask

`ifdef SPEC_CHAOS
	// A prediction is only a hint: scribble over the predictor while programs run.
	// False hits on non-branches, wrong targets and random counters may cost cycles
	// but must never change a committed result.
	integer ch_i;
	always @(negedge clk) if (active && ($random & 3) == 0) begin
		ch_i = $random & (`BTB_N - 1);
		DUT.U_CORE.core.g_bpred.bp.btb_valid[ch_i]  = 1'b1;
		DUT.U_CORE.core.g_bpred.bp.btb_uncond[ch_i] = $random;
		DUT.U_CORE.core.g_bpred.bp.btb_tag[ch_i]    = $random;
		DUT.U_CORE.core.g_bpred.bp.btb_target[ch_i] = $random & 32'h0000_0FFC;
		DUT.U_CORE.core.g_bpred.bp.bht[$random & (`BHT_N - 1)] = $random;
	end
`endif

	// ---- commit monitor ----------------------------------------------------
	wire                c_valid    = DUT.U_CORE.dbg_commit_valid;
	wire    [31: 0]     c_pc       = DUT.U_CORE.dbg_commit_pc;
	wire    [ 4: 0]     c_rd       = DUT.U_CORE.dbg_commit_rd;
	wire                c_has_rd   = DUT.U_CORE.dbg_commit_has_rd;
	wire    [31: 0]     c_value    = DUT.U_CORE.dbg_commit_value;
	wire                c_is_store = DUT.U_CORE.dbg_commit_is_store;
	// A committed store must appear in its commit cycle. With no data cache or a
	// write-through cache that is the core's memory write port; a write-back
	// cache keeps stores in the cache, so there it is the LSU -> cache request.
	wire                m_we       = (`DC_EN && `DC_WB) ? DUT.U_CORE.core.lsu_we    : DUT.U_CORE.dmem_write_ready;
	wire    [31: 0]     m_waddr    = (`DC_EN && `DC_WB) ? DUT.U_CORE.core.lsu_waddr : DUT.U_CORE.dmem_write_address;
	wire    [31: 0]     m_wdata    = (`DC_EN && `DC_WB) ? DUT.U_CORE.core.lsu_wdata : DUT.U_CORE.dmem_write_data;
	wire    [ 3: 0]     m_wstrb    = (`DC_EN && `DC_WB) ? DUT.U_CORE.core.lsu_wstrb : DUT.U_CORE.dmem_write_byte;

	integer             idx, n_fail, n_checked, n_prog_fail, j;
	reg                 active;
	reg     [31: 0]     g_kind, g_lane;

	function [31:0] lanes(input [31:0] d, input [3:0] s);
		for (j = 0; j < 4; j = j + 1)
			lanes[8*j +: 8] = s[j] ? d[8*j +: 8] : 8'h00;
	endfunction

	always @(posedge clk) if (active && c_valid && idx < n_exp - 1) begin
		g_kind = c_is_store ? 32'd2 : c_has_rd ? 32'd1 : 32'd0;
		g_lane = lanes(m_wdata, m_wstrb);
		if (g_kind !== e_kind[idx] || c_pc !== e_pc[idx] ||
		    (g_kind == 1 && (c_rd !== e_rd[idx][4:0] || c_value !== e_val[idx])) ||
		    (g_kind == 2 && (!m_we || m_waddr !== e_addr[idx] || g_lane !== e_lane[idx] ||
		                     m_wstrb !== e_strb[idx][3:0]))) begin
			n_fail = n_fail + 1;
			if (n_fail <= 10)
				$display("TEST_FAIL commit_trace commit %0d t=%0t: got kind=%0d pc=%h rd=%0d val=%h st(we=%b addr=%h lanes=%h strb=%b), expected kind=%0d pc=%h rd=%0d val=%h st(addr=%h lanes=%h strb=%h)",
				         idx, $time, g_kind, c_pc, c_rd, c_value, m_we, m_waddr, g_lane, m_wstrb,
				         e_kind[idx], e_pc[idx], e_rd[idx], e_val[idx], e_addr[idx], e_lane[idx], e_strb[idx]);
		end
		n_checked = n_checked + 1;
		idx = idx + 1;
	end

	// ---- run every program -------------------------------------------------
	integer p, cyc, last, n_skip;
	initial begin
		n_fail = 0; n_checked = 0; active = 0; idx = 0; n_exp = 0; n_skip = 0;
		#1;
		for (p = 0; p < NPROG; p = p + 1) begin
			fd = $fopen(p_hex[p], "r");
			if (fd == 0) begin
				n_skip = n_skip + 1;
				$display("SKIP commit_trace %0s: not built (no RISC-V gcc)", p_hex[p]);
			end else begin
			$fclose(fd);
			reset = 1'b0;
			sw    = p_sw[p];
			read_trace(p_trace[p]);
			$readmemh(p_hex[p], DUT.U_IMEM.imem);
			idx = 0;
			n_prog_fail = n_fail;
			repeat (5) @(negedge clk);
			active = 1;
			reset  = 1'b1;
			cyc = 0;
			while (idx < n_exp - 1 && cyc < TIMEOUT) begin
				@(negedge clk);
				cyc = cyc + 1;
			end
			repeat (3) @(negedge clk);
			active = 0;
			last = n_exp - 1;
			if (idx < last) begin
				n_fail = n_fail + 1;
				$display("TEST_FAIL commit_trace %0s: only %0d of %0d commits in %0d cycles", p_hex[p], idx, last, cyc);
			end
			if (e_kind[last] != 3 || DUT.result !== e_val[last] || DUT.done !== e_addr[last][0] ||
			    DUT.exception !== e_lane[last][0]) begin
				n_fail = n_fail + 1;
				$display("TEST_FAIL commit_trace %0s end state: result=%h done=%b exception=%b, expected %h %0d %0d",
				         p_hex[p], DUT.result, DUT.done, DUT.exception, e_val[last], e_addr[last], e_lane[last]);
			end
			if (e_addr[last][0] && DUT.U_PERF.retired !== last) begin
				n_fail = n_fail + 1;
				$display("TEST_FAIL commit_trace %0s retired=%0d, expected %0d (D21: up to and including the done store)",
				         p_hex[p], DUT.U_PERF.retired, last);
			end
			$display("%0s: %0d commits compared, result=%h done=%b exception=%b cycles=%0d retired=%0d ooo_count=%0d, %0d failures",
			         p_hex[p], idx, DUT.result, DUT.done, DUT.exception, DUT.U_PERF.cycles, DUT.U_PERF.retired,
			         DUT.U_PERF.ooo_count, n_fail - n_prog_fail);
			$display("%0s: dcache accesses=%0d hits=%0d misses=%0d stall_cycles=%0d branches=%0d mispredicts=%0d",
			         p_hex[p], DUT.U_PERF.dcache_access_count, DUT.U_PERF.dcache_hit_count,
			         DUT.U_PERF.dcache_miss_count, DUT.U_PERF.dcache_stall_cycles,
			         DUT.U_PERF.branch_count, DUT.U_PERF.mispredict_count);
			end
		end
		if (n_skip != 0) $display("commit_trace: %0d of %0d programs skipped", n_skip, NPROG);
		if (n_fail == 0) $display("TEST_PASS commit_trace %0d", n_checked);
		else             $display("TEST_FAIL commit_trace %0d failures", n_fail);
		$finish;
	end

endmodule
