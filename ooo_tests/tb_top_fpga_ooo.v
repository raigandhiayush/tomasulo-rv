// tb_top_fpga_ooo - Self-checking testbench for FPGA top level covering MMIO, peripherals, and counters.
`timescale 1ns/1ps
`include "ooo_defs.vh"

module tb_top_fpga_ooo;

	localparam TIMEOUT = 5000;
	localparam NRUN    = 4;

	reg                 clk = 1'b0;
	reg                 reset = 1'b0;
	reg     [15: 0]     sw = 16'd0;
	always #5 clk = ~clk;

	wire    [15: 0]     led;
	wire    [ 7: 0]     seg, an;

	top_fpga_ooo #(.REFRESH_W(2)) DUT (.clk(clk), .reset(reset), .sw(sw), .led(led), .seg(seg), .an(an));

	integer             n_pass = 0, n_fail = 0;

	task check(input ok, input [8*96-1:0] what, input [31:0] got, input [31:0] exp);
		begin
			if (ok) n_pass = n_pass + 1;
			else begin
				n_fail = n_fail + 1;
				$display("TEST_FAIL top_fpga_ooo %0s: got %h expected %h (t=%0t, sw=%h)", what, got, exp, $time, sw);
			end
		end
	endtask

	// ---- T6: no MMIO store may reach data_mem, at any time --------------------
	always @(posedge clk)
		if (DUT.U_DMEM.we && DUT.U_DMEM.waddr[31:28] == 4'h1)
			check(0, "T6 data_mem.we for an MMIO address", DUT.U_DMEM.waddr, 0);

	// ---- result history (T2, T2b, T8) -----------------------------------------
	reg     [31: 0]     r_hist [0:7];
	integer             n_hist;
	always @(posedge clk)
		if (DUT.U_CORE.dmem_write_ready && DUT.U_CORE.dmem_write_address[31:2] == 30'h0400_0000)
			#1 begin
				if (n_hist < 8) r_hist[n_hist] = DUT.result;
				n_hist = n_hist + 1;
			end

	// ---- D21: independent cycle and commit count -------------------------------
	integer             cnt_cycles, cnt_retired;
	reg                 counting;
	always @(posedge clk) begin
		// sample the state before the edge: count while released and not done
		counting = DUT.rst_n_sync && !DUT.done;
		if (counting) begin
			cnt_cycles = cnt_cycles + 1;
			if (DUT.U_CORE.dbg_commit_valid) cnt_retired = cnt_retired + 1;
		end
	end

	// memory as the program sees it: a write-back cache may hold newer data than data_mem
	function [31:0] mem_view(input integer word);
		integer l;
		begin
			mem_view = DUT.U_DMEM.dmem[word];
			for (l = 0; l < `DC_WAYS * `DC_SETS; l = l + 1)
				if (DUT.U_CORE.core.g_dcache.dcache.valid[l] && (l % `DC_SETS) == ((word >> $clog2(`DC_WORDS)) & (`DC_SETS - 1)) &&
				    DUT.U_CORE.core.g_dcache.dcache.tags[l] == (word >> ($clog2(`DC_WORDS) + $clog2(`DC_SETS))))
					mem_view = DUT.U_CORE.core.g_dcache.dcache.data[l * `DC_WORDS + (word & (`DC_WORDS - 1))];
		end
	endfunction

	// ---- display decode --------------------------------------------------------
	function [6:0] font(input [3:0] n);
		case (n)
			4'h0: font = 7'b0111111; 4'h1: font = 7'b0000110; 4'h2: font = 7'b1011011; 4'h3: font = 7'b1001111;
			4'h4: font = 7'b1100110; 4'h5: font = 7'b1101101; 4'h6: font = 7'b1111101; 4'h7: font = 7'b0000111;
			4'h8: font = 7'b1111111; 4'h9: font = 7'b1101111; 4'hA: font = 7'b1110111; 4'hB: font = 7'b1111100;
			4'hC: font = 7'b0111001; 4'hD: font = 7'b1011110; 4'hE: font = 7'b1111001; default: font = 7'b1110001;
		endcase
	endfunction

	task check_display(input [31:0] value);
		integer d, k, seen;
		begin
			seen = 0;
			for (k = 0; k < 64; k = k + 1) begin
				@(negedge clk);
				d = -1;
				case (an)
					8'b11111110: d = 0; 8'b11111101: d = 1; 8'b11111011: d = 2; 8'b11110111: d = 3;
					8'b11101111: d = 4; 8'b11011111: d = 5; 8'b10111111: d = 6; 8'b01111111: d = 7;
				endcase
				check(d >= 0, "display: exactly one anode active", {24'd0, an}, 0);
				if (d >= 0) begin
					check(seg === ~{1'b0, font(value[4*d +: 4])}, "display: segment pattern", {24'd0, seg},
					      {24'd0, ~{1'b0, font(value[4*d +: 4])}});
					seen = seen | (1 << d);
				end
			end
			check(seen == 8'hFF, "display: all 8 digits refreshed", seen, 8'hFF);
		end
	endtask

	// ---- runs ------------------------------------------------------------------
	reg     [15: 0]     sw_val [0:NRUN-1];
	reg     [31: 0]     run_cycles [0:NRUN-1];
	reg     [31: 0]     run_retired [0:NRUN-1];
	reg     [31: 0]     sentinel [0:4];
	reg     [31: 0]     frozen_c, frozen_r;
	integer             r, i, cyc;
	integer             sent_idx [0:4];
	integer             seed = 2026;

	initial begin
		sw_val[0] = 16'h0000; sw_val[1] = 16'hFFFF; sw_val[2] = 16'hA5A5; sw_val[3] = $random(seed);
		// data_mem words that the T6 MMIO stores alias onto (addr[11:2])
		sent_idx[0] = 0; sent_idx[1] = 2; sent_idx[2] = 3; sent_idx[3] = 4; sent_idx[4] = 1020;
		#1;
		$readmemh("../ooo_tests/programs/top_mmio.hex", DUT.U_IMEM.imem);
		for (i = 0; i < 5; i = i + 1) begin
			sentinel[i] = 32'hA000_0000 + sent_idx[i];
			DUT.U_DMEM.dmem[sent_idx[i]] = sentinel[i];
		end

		for (r = 0; r < NRUN; r = r + 1) begin
			// ---- T1: in reset everything is 0
			reset = 1'b0;
			sw    = sw_val[r];
			repeat (4) @(negedge clk);
			check(DUT.result === 0 && DUT.done === 0, "T1 result/done in reset", {DUT.result[30:0], DUT.done}, 0);
			check(DUT.U_PERF.cycles === 0 && DUT.U_PERF.retired === 0 && DUT.U_PERF.ooo_count === 0,
			      "T1 counters in reset", DUT.U_PERF.cycles, 0);
			check(led === 16'd0, "T1 led in reset", {16'd0, led}, 0);
			n_hist = 0; cnt_cycles = 0; cnt_retired = 0;
			reset = 1'b1;
			cyc = 0;
			while (!DUT.done && cyc < TIMEOUT) begin @(negedge clk); cyc = cyc + 1; end
			check(DUT.done === 1'b1, "T3 done set by the byte store to 0x1000_0004", DUT.done, 1);

			// ---- T2, T2b, T8: result after each store to 0x1000_0000
			check(n_hist == 4, "number of result writes", n_hist, 4);
			check(r_hist[0] === 32'h0000_0005, "T2b sb to result", r_hist[0], 32'h0000_0005);
			check(r_hist[1] === 32'h1234_0005, "T2b sh to result+2", r_hist[1], 32'h1234_0005);
			check(r_hist[2] === 32'hCAFE_BABE, "T2 sw to result", r_hist[2], 32'hCAFE_BABE);
			check(r_hist[3] === 32'd3,         "T8 result of sort + MUL/DIV", r_hist[3], 3);
			check(DUT.result === 32'd3, "T6 result unchanged by other MMIO stores / T7 RAM stores", DUT.result, 3);

			// ---- T4, T5: values the program loaded and stored to 0x200..
			check(mem_view(32'h200 >> 2) === {16'd0, sw}, "T4 lw switches", mem_view(32'h200 >> 2), {16'd0, sw});
			check(mem_view(32'h204 >> 2) === 32'h1122_3344, "T5 lw RAM between switch loads", mem_view(32'h204 >> 2), 32'h1122_3344);
			check(mem_view(32'h208 >> 2) === {16'd0, sw}, "T5 lw switches after RAM", mem_view(32'h208 >> 2), {16'd0, sw});
			check(mem_view(32'h20C >> 2) === 32'd0, "T5 lw other MMIO address reads 0", mem_view(32'h20C >> 2), 0);
			check(mem_view(32'h210 >> 2) === {16'd0, sw}, "T4 lhu switches", mem_view(32'h210 >> 2), {16'd0, sw});
			check(mem_view(32'h214 >> 2) === {24'd0, sw[15:8]}, "T4 lbu switches byte 1", mem_view(32'h214 >> 2), {24'd0, sw[15:8]});
			check(mem_view(32'h218 >> 2) === 32'd0, "T5 lw of the result address reads 0", mem_view(32'h218 >> 2), 0);

			// ---- T6, T7: aliased words untouched, plain RAM stores landed
			for (i = 0; i < 5; i = i + 1)
				check(mem_view(sent_idx[i]) === sentinel[i], "T6 data_mem word aliased by an MMIO store changed",
				      mem_view(sent_idx[i]), sentinel[i]);
			check(mem_view(32'h100 >> 2) === 32'h1122_3344, "T7 store to 0x0000_0100", mem_view(32'h100 >> 2), 32'h1122_3344);
			check(mem_view(1023) === 32'h1122_3344, "T7 store to 0x0FFF_FFFC", mem_view(1023), 32'h1122_3344);

			// ---- T8: sorted array
			check(mem_view(32'h300 >> 2) === 3 && mem_view(32'h304 >> 2) === 6 &&
			      mem_view(32'h308 >> 2) === 9, "T8 sorted array {3,6,9}", mem_view(32'h300 >> 2), 3);

			// ---- D21 counting rule and T3 freeze
			@(negedge clk);
			check(DUT.U_PERF.cycles === cnt_cycles, "D21 cycles vs testbench edge count", DUT.U_PERF.cycles, cnt_cycles);
			check(DUT.U_PERF.retired === cnt_retired, "D21 retired vs testbench commit count", DUT.U_PERF.retired, cnt_retired);
			check(DUT.U_PERF.retired === 92, "D21 retired = commits through the done store (ref_model: 92)", DUT.U_PERF.retired, 92);
			frozen_c = DUT.U_PERF.cycles;
			frozen_r = DUT.U_PERF.retired;
			repeat (100) @(negedge clk);
			check(DUT.U_PERF.cycles === frozen_c && DUT.U_PERF.retired === frozen_r,
			      "T3 counters frozen after done", DUT.U_PERF.cycles, frozen_c);
			check(DUT.exception === 1'b0, "no exception", DUT.exception, 0);
			check(led === {1'b1, 1'b0, 14'd3}, "led = {done, exception, result[13:0]}", {16'd0, led}, {16'd0, 1'b1, 1'b0, 14'd3});

			// ---- display: value selected by sw[15:14], cache page when sw[13] = 1
			if (sw[12]) check_display(sw[14] ? DUT.U_PERF.mispredict_count : DUT.U_PERF.branch_count);
			else case (sw[15:13])
				3'b000:  check_display(DUT.result);
				3'b010:  check_display(DUT.U_PERF.cycles);
				3'b100:  check_display(DUT.U_PERF.retired);
				3'b110:  check_display(DUT.U_PERF.ooo_count);
				3'b001:  check_display(DUT.U_PERF.dcache_access_count);
				3'b011:  check_display(DUT.U_PERF.dcache_hit_count);
				3'b101:  check_display(DUT.U_PERF.dcache_miss_count);
				default: check_display(DUT.U_PERF.dcache_stall_cycles);
			endcase

			run_cycles[r]  = DUT.U_PERF.cycles;
			run_retired[r] = DUT.U_PERF.retired;
			$display("run %0d: sw=%h result=%h cycles=%0d retired=%0d ooo_count=%0d (tb count %0d/%0d)",
			         r, sw, DUT.result, DUT.U_PERF.cycles, DUT.U_PERF.retired, DUT.U_PERF.ooo_count,
			         cnt_cycles, cnt_retired);
			// ---- T9: same counts as the first run
			check(run_cycles[r] === run_cycles[0] && run_retired[r] === run_retired[0],
			      "T9 rerun after reset: same cycles and retired", run_cycles[r], run_cycles[0]);
		end

		if (n_fail == 0) $display("TEST_PASS top_fpga_ooo %0d", n_pass);
		else             $display("TEST_FAIL top_fpga_ooo %0d failures, %0d passed", n_fail, n_pass);
		$finish;
	end

endmodule
