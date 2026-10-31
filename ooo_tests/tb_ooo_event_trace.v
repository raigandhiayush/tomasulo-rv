// tb_ooo_event_trace - Verification testbench capturing out-of-order execution events and traces.
`timescale 1ns/1ps
`include "ooo_defs.vh"

module tb_ooo_event_trace;

	localparam TIMEOUT = 400;
	localparam DIV_PC  = 32'h10;

	reg                 clk = 1'b0;
	reg                 reset = 1'b0;
	always #5 clk = ~clk;

	wire    [15: 0]     led;
	wire    [ 7: 0]     seg, an;

	top_fpga_ooo #(.REFRESH_W(2)) DUT (.clk(clk), .reset(reset), .sw(16'd0), .led(led), .seg(seg), .an(an));

	wire    [`NCDB-1:0]          bus_v   = DUT.U_CORE.core.cdb_valid;
	wire    [`NCDB*`ROB_W-1:0]   bus_tag = DUT.U_CORE.core.cdb_tag;
	wire    [`NCDB*`XLEN-1:0]    bus_val = DUT.U_CORE.core.cdb_value;
	wire    [`ROB_W-1:0]         head    = DUT.U_CORE.core.rob.head;
	wire                         head_busy = DUT.U_CORE.core.rob.valid[head] && !DUT.U_CORE.core.rob.ready[head];
	wire    [31: 0]              head_pc = DUT.U_CORE.core.rob.pc[head];
	wire                         ooo_ev  = DUT.U_CORE.dbg_ooo_event;

	integer             n_pass = 0, n_fail = 0;
	integer             cyc = 0, n_ev = 0, n_multi = 0, k, n_act;
	integer             nonhead_under_div [0:`NCDB-1];
	reg                 exp_ev;

	task check(input ok, input [8*80-1:0] what, input [31:0] got, input [31:0] exp);
		begin
			if (ok) n_pass = n_pass + 1;
			else begin
				n_fail = n_fail + 1;
				$display("TEST_FAIL ooo_event_trace %0s: got %0d expected %0d (cycle %0d)", what, got, exp, cyc);
			end
		end
	endtask

	always @(negedge clk) if (reset && !DUT.done) begin
		exp_ev = 1'b0;
		n_act  = 0;
		for (k = 0; k < `NCDB; k = k + 1) if (bus_v[k]) begin
			n_act = n_act + 1;
			if (head_busy && bus_tag[k*`ROB_W +: `ROB_W] != head) begin
				exp_ev = 1'b1;
				if (head_pc == DIV_PC) nonhead_under_div[k] = nonhead_under_div[k] + 1;
			end
		end
		check(ooo_ev === exp_ev, "ooo_event vs bus tags and ROB head", ooo_ev, exp_ev);
		if (ooo_ev)     n_ev = n_ev + 1;
		if (n_act >= 2) n_multi = n_multi + 1;
		if (bus_v != 0 || ooo_ev)
			$display("TRACE cyc=%3d head=%0d pc=%h busy=%b | alu %s%0d=%0d | mul %s%0d=%0d | div %s%0d=%0d | lsu %s%0d=%0d | ooo_event=%b%s",
			         cyc, head, head_pc, head_busy,
			         bus_v[0] ? "t" : "-", bus_tag[0*`ROB_W +: `ROB_W], bus_v[0] ? bus_val[0*32 +: 32] : 0,
			         bus_v[1] ? "t" : "-", bus_tag[1*`ROB_W +: `ROB_W], bus_v[1] ? bus_val[1*32 +: 32] : 0,
			         bus_v[2] ? "t" : "-", bus_tag[2*`ROB_W +: `ROB_W], bus_v[2] ? bus_val[2*32 +: 32] : 0,
			         bus_v[3] ? "t" : "-", bus_tag[3*`ROB_W +: `ROB_W], bus_v[3] ? bus_val[3*32 +: 32] : 0,
			         ooo_ev, n_act >= 2 ? "  [2+ buses]" : "");
		cyc = cyc + 1;
	end

	initial begin
		for (k = 0; k < `NCDB; k = k + 1) nonhead_under_div[k] = 0;
		$dumpfile("../evidence/waves/ooo_event_trace.vcd");
		$dumpvars(1, tb_ooo_event_trace);
		$dumpvars(1, DUT.U_CORE.core);
		$dumpvars(1, DUT.U_CORE.core.rob);
		$dumpvars(1, DUT.U_PERF);
		#1;
		$readmemh("../ooo_tests/programs/ooo_trace.hex", DUT.U_IMEM.imem);
		repeat (4) @(negedge clk);
		reset = 1'b1;
		while (!DUT.done && cyc < TIMEOUT) @(negedge clk);
		repeat (2) @(negedge clk);

		check(DUT.done === 1'b1, "program finished (done)", DUT.done, 1);
		check(DUT.result === 32'd542, "result", DUT.result, 542);
		check(DUT.exception === 1'b0, "no exception", DUT.exception, 0);
		check(nonhead_under_div[0] > 0, "cdb_alu completion while the DIV is the unfinished head", nonhead_under_div[0], 1);
		check(nonhead_under_div[1] > 0, "cdb_mul completion while the DIV is the unfinished head", nonhead_under_div[1], 1);
		check(nonhead_under_div[3] > 0, "cdb_lsu completion while the DIV is the unfinished head", nonhead_under_div[3], 1);
		check(DUT.U_PERF.ooo_count === n_ev, "perf_counters.ooo_count vs ooo_event cycles", DUT.U_PERF.ooo_count, n_ev);
		check(n_multi > 0, "cycles with two or more buses active", n_multi, 1);

		$display("SUMMARY cycles=%0d retired=%0d ooo_event cycles=%0d (ooo_count=%0d), 2+ bus cycles=%0d, non-head completions under the DIV: alu=%0d mul=%0d div=%0d (not possible, see header) lsu=%0d",
		         DUT.U_PERF.cycles, DUT.U_PERF.retired, n_ev, DUT.U_PERF.ooo_count, n_multi,
		         nonhead_under_div[0], nonhead_under_div[1], nonhead_under_div[2], nonhead_under_div[3]);
		$display("Waveform: evidence/waves/ooo_event_trace.vcd");
		if (n_fail == 0) $display("TEST_PASS ooo_event_trace %0d", n_pass);
		else             $display("TEST_FAIL ooo_event_trace %0d failures, %0d passed", n_fail, n_pass);
		$finish;
	end

endmodule
