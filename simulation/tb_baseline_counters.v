// Testbench comparing cycle counts and commit traces across pipe, pipe_m, and pipe_ooo cores.
`timescale 1ns/1ps
`include "ooo_defs.vh"

// one core in the top_fpga_ooo system; CORE 0 = pipe, 1 = pipe_m, 2 = pipe_ooo
module tbc_sys #(
	parameter CORE = 0
) (
	input                   clk,
	input                   reset,              // active low
	input       [15: 0]     sw
);

	localparam [31: 0] MMIO_RESULT = 32'h1000_0000;
	localparam [31: 0] MMIO_DONE   = 32'h1000_0004;
	localparam [31: 0] MMIO_SW     = 32'h1000_0008;

	wire    [31: 0]         imem_addr, imem_data;
	wire                    dmem_re, dmem_we;
	wire    [31: 0]         dmem_raddr, dmem_rdata, dmem_waddr, dmem_wdata, ram_rdata;
	wire    [ 3: 0]         dmem_wstrb;
	wire                    exception;
	wire                    commit_valid, ooo_event;

	generate
		if (CORE == 0) begin : g_core
			pipe U_CORE (
				.clk(clk), .reset(reset), .stall(1'b0), .exception(exception), .pc_out(),
				.inst_mem_is_valid(1'b1), .inst_mem_read_data(imem_data), .inst_mem_address(imem_addr),
				.dmem_read_data_temp(dmem_rdata), .dmem_write_valid(1'b1), .dmem_read_valid(1'b1),
				.dmem_read_ready(dmem_re), .dmem_read_address(dmem_raddr),
				.dmem_write_ready(dmem_we), .dmem_write_address(dmem_waddr),
				.dmem_write_data(dmem_wdata), .dmem_write_byte(dmem_wstrb)
			);
			assign commit_valid = 1'b0;
			assign ooo_event    = 1'b0;
		end else if (CORE == 1) begin : g_core
			pipe_m U_CORE (
				.clk(clk), .reset(reset), .stall(1'b0), .exception(exception), .pc_out(),
				.inst_mem_is_valid(1'b1), .inst_mem_read_data(imem_data), .inst_mem_address(imem_addr),
				.dmem_read_data_temp(dmem_rdata), .dmem_write_valid(1'b1), .dmem_read_valid(1'b1),
				.dmem_read_ready(dmem_re), .dmem_read_address(dmem_raddr),
				.dmem_write_ready(dmem_we), .dmem_write_address(dmem_waddr),
				.dmem_write_data(dmem_wdata), .dmem_write_byte(dmem_wstrb),
				.dbg_retire(commit_valid)
			);
			assign ooo_event    = 1'b0;
		end else begin : g_core
			pipe_ooo U_CORE (
				.clk(clk), .reset(reset), .stall(1'b0), .exception(exception), .pc_out(),
				.inst_mem_is_valid(1'b1), .inst_mem_read_data(imem_data), .inst_mem_address(imem_addr),
				.dmem_read_data_temp(dmem_rdata), .dmem_write_valid(1'b1), .dmem_read_valid(1'b1),
				.dmem_read_ready(dmem_re), .dmem_read_address(dmem_raddr),
				.dmem_write_ready(dmem_we), .dmem_write_address(dmem_waddr),
				.dmem_write_data(dmem_wdata), .dmem_write_byte(dmem_wstrb),
				.dbg_commit_valid(commit_valid), .dbg_commit_pc(), .dbg_commit_rd(),
				.dbg_commit_has_rd(), .dbg_commit_value(), .dbg_commit_is_store(),
				.dbg_ooo_event(ooo_event), .dbg_stall_rob(), .dbg_stall_rs(), .dbg_hold(),
				.dbg_cdb_valid()
			);
		end
	endgenerate

	// memories and MMIO exactly as in top_fpga_ooo (D20, D22)
	wire                    w_mmio = (dmem_waddr[31:28] == 4'h1);
	wire                    r_mmio = (dmem_raddr[31:28] == 4'h1);

	instr_mem U_IMEM (.clk(clk), .pc(imem_addr), .instr(imem_data));
	data_mem  U_DMEM (.clk(clk), .re(dmem_re), .raddr(dmem_raddr), .rdata(ram_rdata),
	                  .we(dmem_we & ~w_mmio), .waddr(dmem_waddr), .wdata(dmem_wdata), .wstrb(dmem_wstrb));

	reg     [31: 0]         result;
	reg                     done;
	reg                     rd_sw, rd_zero;
	integer                 b;

	always @(posedge clk or negedge reset) begin
		if (!reset)
			result <= 32'd0;
		else if (dmem_we && dmem_waddr[31:2] == MMIO_RESULT[31:2])
			for (b = 0; b < 4; b = b + 1)
				if (dmem_wstrb[b]) result[8*b +: 8] <= dmem_wdata[8*b +: 8];
	end

	always @(posedge clk or negedge reset) begin
		if (!reset)                                              done <= 1'b0;
		else if (dmem_we && dmem_waddr[31:2] == MMIO_DONE[31:2]) done <= 1'b1;
	end

	always @(posedge clk or negedge reset) begin
		if (!reset) begin
			rd_sw   <= 1'b0;
			rd_zero <= 1'b0;
		end else if (dmem_re) begin
			rd_sw   <= (dmem_raddr[31:2] == MMIO_SW[31:2]);
			rd_zero <= r_mmio && (dmem_raddr[31:2] != MMIO_SW[31:2]);
		end
	end

	// switches are constant during a run, so the 2-FF synchronizer is left out
	assign dmem_rdata = rd_sw   ? {16'd0, sw} :
	                    rd_zero ? 32'd0 :
	                              ram_rdata;

	perf_counters U_PERF (
		.clk(clk), .reset_n(reset), .run(reset & ~done),
		.commit_valid(commit_valid), .ooo_event(ooo_event),
		.stall_rob(1'b0), .stall_rs(1'b0), .hold(1'b0),
		.cycles(), .retired(), .ooo_count(),
		.rob_stall_cycles(), .rs_stall_cycles(), .hold_cycles()
	);

endmodule


module tb_baseline_counters;

	localparam NCORE   = 3;
	localparam NPROG   = 5;
	localparam TIMEOUT = 50000;
	localparam MAXL    = 8192;

	reg                 clk = 1'b0;
	reg                 reset = 1'b0;
	reg     [15: 0]     sw = 16'd0;
	always #5 clk = ~clk;

	tbc_sys #(.CORE(0)) S0 (.clk(clk), .reset(reset), .sw(sw));
	tbc_sys #(.CORE(1)) S1 (.clk(clk), .reset(reset), .sw(sw));
	tbc_sys #(.CORE(2)) S2 (.clk(clk), .reset(reset), .sw(sw));

	wire    [15: 0]     led;
	wire    [ 7: 0]     seg, an;
	top_fpga_ooo #(.REFRESH_W(2)) TOP (.clk(clk), .reset(reset), .sw(sw), .led(led), .seg(seg), .an(an));

	wire    [15: 0]     led_b0, led_b1;
	wire    [ 7: 0]     seg_b0, an_b0, seg_b1, an_b1;
	top_fpga_base #(.CORE(0), .REFRESH_W(2)) TOPB0 (.clk(clk), .reset(reset), .sw(sw), .led(led_b0), .seg(seg_b0), .an(an_b0));
	top_fpga_base #(.CORE(1), .REFRESH_W(2)) TOPB1 (.clk(clk), .reset(reset), .sw(sw), .led(led_b1), .seg(seg_b1), .an(an_b1));

	// ---- program list ------------------------------------------------------
	reg     [8*256-1:0] p_hex   [0:NPROG-1];
	reg     [8*256-1:0] p_trace [0:NPROG-1];
	reg     [15: 0]     p_sw    [0:NPROG-1];
	reg     [8*256-1:0] arg_hex, arg_trace;
	reg     [15: 0]     arg_sw;
	integer             nprog;

	initial begin
		p_hex[0] = "../ooo_tests/programs/base_rv32i.hex";  p_trace[0] = "../ooo_tests/programs/base_rv32i.trace";  p_sw[0] = 16'h0000;
		p_hex[1] = "../ooo_tests/programs/top_mmio.hex";    p_trace[1] = "../ooo_tests/programs/top_mmio.trace";    p_sw[1] = 16'hA5A5;
		p_hex[2] = "../ooo_tests/programs/ooo_trace.hex";   p_trace[2] = "../ooo_tests/programs/ooo_trace.trace";   p_sw[2] = 16'h0000;
		p_hex[3] = "../ooo_tests/programs/rv32m_edge.hex";  p_trace[3] = "../ooo_tests/programs/rv32m_edge.trace";  p_sw[3] = 16'h0000;
		p_hex[4] = "../ooo_tests/programs/pipe_m_edge.hex"; p_trace[4] = "../ooo_tests/programs/pipe_m_edge.trace"; p_sw[4] = 16'h0000;
		nprog = NPROG;
		if ($value$plusargs("hex=%s", arg_hex)) begin
			if (!$value$plusargs("trace=%s", arg_trace)) begin
				$display("TEST_FAIL baseline_counters +hex given without +trace");
				$finish;
			end
			if (!$value$plusargs("sw=%h", arg_sw)) arg_sw = 16'h0000;
			p_hex[0] = arg_hex; p_trace[0] = arg_trace; p_sw[0] = arg_sw;
			nprog = 1;
		end
	end

	// ---- expected trace: stores and end state --------------------------------
	reg     [31: 0]     e_addr [0:MAXL-1];
	reg     [31: 0]     e_lane [0:MAXL-1];
	reg     [31: 0]     e_strb [0:MAXL-1];
	integer             n_st, n_commit, fd, nf;
	reg     [31: 0]     f0, f1, f2, f3, f4, f5, f6;
	reg     [31: 0]     end_result;
	reg                 end_done, end_exc;

	task read_trace(input [8*256-1:0] fname);
		begin
			n_st = 0; n_commit = 0; end_done = 1'b0; end_exc = 1'b0; end_result = 32'd0;
			fd = $fopen(fname, "r");
			if (fd == 0) begin
				$display("TEST_FAIL baseline_counters cannot open %0s", fname);
				$finish;
			end
			while (!$feof(fd)) begin
				nf = $fscanf(fd, "%h %h %h %h %h %h %h\n", f0, f1, f2, f3, f4, f5, f6);
				if (nf == 7) begin
					if (f0 == 3) begin
						end_result = f3; end_done = f4[0]; end_exc = f5[0];
					end else begin
						n_commit = n_commit + 1;
						if (f0 == 2 && n_st < MAXL) begin
							e_addr[n_st] = f4; e_lane[n_st] = f5; e_strb[n_st] = f6;
							n_st = n_st + 1;
						end
					end
				end
			end
			$fclose(fd);
		end
	endtask

	// RV32M present? (OP opcode with funct7 = 0000001)
	reg     [31: 0]     prog [0:1023];
	reg                 has_m;
	integer             w;

	task scan_m;
		begin
			has_m = 1'b0;
			for (w = 0; w < 1024; w = w + 1)
				if (prog[w][6:0] === 7'b0110011 && prog[w][31:25] === 7'b0000001) has_m = 1'b1;
		end
	endtask

	// ---- store monitor, one per core -------------------------------------------
	integer             n_fail, n_checks, j;
	reg                 active;
	reg                 en      [0:NCORE-1];
	integer             st_idx  [0:NCORE-1];
	reg     [31: 0]     st_off  [0:NCORE-1];
	reg                 off_set [0:NCORE-1];
	reg     [31: 0]     g_lane;

	integer             bug0;               // store mismatches of core 0 (pipe)

	function [31:0] lanes(input [31:0] d, input [3:0] s);
		for (j = 0; j < 4; j = j + 1)
			lanes[8*j +: 8] = s[j] ? d[8*j +: 8] : 8'h00;
	endfunction

	task check_store(input integer c, input we, input dn, input [31:0] addr,
	                 input [31:0] data, input [3:0] strb);
		begin
			if (active && en[c] && we && !dn) begin
				g_lane = lanes(data, strb);
				if (st_idx[c] >= n_st) begin
					if (c == 0) bug0 = bug0 + 1; else n_fail = n_fail + 1;
					if (n_fail + bug0 <= 20)
						$display("%0s baseline_counters core %0d t=%0t: extra store addr=%h data=%h strb=%b",
						         c == 0 ? "BASELINE_BUG" : "TEST_FAIL", c, $time, addr, data, strb);
				end else begin
					if (e_addr[st_idx[c]][31:28] != 4'h1 && !off_set[c]) begin
						st_off[c]  = addr - e_addr[st_idx[c]];
						off_set[c] = 1'b1;
					end
					if (g_lane !== e_lane[st_idx[c]] || strb !== e_strb[st_idx[c]][3:0] ||
					    (e_addr[st_idx[c]][31:28] == 4'h1 ? addr !== e_addr[st_idx[c]]
					                                      : addr - st_off[c] !== e_addr[st_idx[c]])) begin
						if (c == 0) bug0 = bug0 + 1; else n_fail = n_fail + 1;
						if (n_fail + bug0 <= 20)
							$display("%0s baseline_counters core %0d store %0d t=%0t: got addr=%h lanes=%h strb=%b, expected addr=%h(+%h) lanes=%h strb=%h",
							         c == 0 ? "BASELINE_BUG" : "TEST_FAIL", c, st_idx[c], $time, addr, g_lane, strb, e_addr[st_idx[c]], st_off[c],
							         e_lane[st_idx[c]], e_strb[st_idx[c]]);
					end
				end
				st_idx[c] = st_idx[c] + 1;
				n_checks  = n_checks + 1;
			end
		end
	endtask

	always @(posedge clk) begin
		check_store(0, S0.dmem_we, S0.done, S0.dmem_waddr, S0.dmem_wdata, S0.dmem_wstrb);
		check_store(1, S1.dmem_we, S1.done, S1.dmem_waddr, S1.dmem_wdata, S1.dmem_wstrb);
		check_store(2, S2.dmem_we, S2.done, S2.dmem_waddr, S2.dmem_wdata, S2.dmem_wstrb);
	end

	// ---- end-of-run checks and report --------------------------------------
	reg     [31: 0]     c_result [0:NCORE-1];
	reg                 c_done   [0:NCORE-1];
	reg                 c_exc    [0:NCORE-1];
	reg     [31: 0]     c_cycles [0:NCORE-1];
	reg     [31: 0]     c_ret    [0:NCORE-1];
	reg     [8*8-1:0]   c_name   [0:NCORE-1];

	initial begin
		c_name[0] = "pipe"; c_name[1] = "pipe_m"; c_name[2] = "pipe_ooo";
	end

	reg                 bad0;               // pipe ran into the baseline bug

	task fail(input [8*160-1:0] msg, input integer c);
		begin
			if (c == 0) begin
				bad0 = 1'b1;
				$display("BASELINE_BUG baseline_counters %0s: %0s %0s", p_hex[p], c_name[c], msg);
			end else begin
				n_fail = n_fail + 1;
				$display("TEST_FAIL baseline_counters %0s: %0s %0s", p_hex[p], c_name[c], msg);
			end
		end
	endtask

	integer p, c, cyc;
	initial begin
		n_fail = 0; n_checks = 0; active = 0;
		#1;
		for (p = 0; p < nprog; p = p + 1) begin
			reset = 1'b0;
			sw    = p_sw[p];
			read_trace(p_trace[p]);
			for (w = 0; w < 1024; w = w + 1) prog[w] = 32'd0;
			$readmemh(p_hex[p], prog);
			scan_m;
			bug0 = 0; bad0 = 1'b0;
			$readmemh(p_hex[p], S0.U_IMEM.imem);
			$readmemh(p_hex[p], S1.U_IMEM.imem);
			$readmemh(p_hex[p], S2.U_IMEM.imem);
			$readmemh(p_hex[p], TOP.U_IMEM.imem);
			$readmemh(p_hex[p], TOPB0.U_IMEM.imem);
			$readmemh(p_hex[p], TOPB1.U_IMEM.imem);
			for (c = 0; c < NCORE; c = c + 1) begin
				en[c] = (c != 0) || !has_m;
				st_idx[c] = 0; st_off[c] = 32'd0; off_set[c] = 1'b0;
			end
			repeat (5) @(negedge clk);
			active = 1;
			reset  = 1'b1;
			cyc = 0;
			while (cyc < TIMEOUT && !((S0.done || !en[0]) && (TOPB0.done || !en[0]) && S1.done && S2.done && TOP.done && TOPB1.done)) begin
				@(negedge clk);
				cyc = cyc + 1;
			end
			repeat (3) @(negedge clk);
			active = 0;

			c_result[0] = S0.result; c_done[0] = S0.done; c_exc[0] = S0.exception; c_cycles[0] = S0.U_PERF.cycles;
			c_result[1] = S1.result; c_done[1] = S1.done; c_exc[1] = S1.exception; c_cycles[1] = S1.U_PERF.cycles;
			c_result[2] = S2.result; c_done[2] = S2.done; c_exc[2] = S2.exception; c_cycles[2] = S2.U_PERF.cycles;
			c_ret[0] = n_commit; c_ret[1] = S1.U_PERF.retired; c_ret[2] = S2.U_PERF.retired;

			for (c = 0; c < NCORE; c = c + 1) begin
				if (!en[c]) begin
					$display("PERF %0s core=%0s N/A (program uses RV32M; the baseline is RV32I only, D17)",
					         p_hex[p], c_name[c]);
				end else begin
					if (!end_done)                       fail("trace does not end with done; cycles undefined", c);
					if (c_done[c] !== 1'b1)              fail("did not reach done", c);
					if (c_result[c] !== end_result)      fail("wrong result", c);
					if (st_idx[c] != n_st)               fail("store count differs from trace", c);
					if (c == 0 && bug0 != 0)             fail("store stream differs from trace", c);
					if (c == 2 && c_exc[c] !== end_exc)  fail("exception differs from trace", c);
					if (c != 0 && c_ret[c] != n_commit)  fail("retired differs from trace commits", c);
					$display("PERF %0s core=%0s result=%h done=%b exception=%b cycles=%0d retired=%0d%0s CPI=%0.3f",
					         p_hex[p], c_name[c], c_result[c], c_done[c], c_exc[c], c_cycles[c], c_ret[c],
					         c == 0 ? "(trace)" : "", $itor(c_cycles[c]) / $itor(c_ret[c]));
					n_checks = n_checks + 1;
				end
			end
			if (TOP.U_PERF.cycles !== c_cycles[2]) begin
				n_fail = n_fail + 1;
				$display("TEST_FAIL baseline_counters %0s: tb count %0d != top_fpga_ooo counter %0d (counting rule differs from the board)",
				         p_hex[p], c_cycles[2], TOP.U_PERF.cycles);
			end
			if (TOPB1.U_PERF.cycles !== c_cycles[1] || TOPB1.U_PERF.retired !== c_ret[1] ||
			    TOPB1.result !== c_result[1] || TOPB1.done !== c_done[1]) begin
				n_fail = n_fail + 1;
				$display("TEST_FAIL baseline_counters %0s: top_fpga_base(pipe_m) cycles=%0d retired=%0d result=%h done=%b != tb copy %0d %0d %h %b",
				         p_hex[p], TOPB1.U_PERF.cycles, TOPB1.U_PERF.retired, TOPB1.result, TOPB1.done,
				         c_cycles[1], c_ret[1], c_result[1], c_done[1]);
			end
			if (en[0] && (TOPB0.U_PERF.cycles !== c_cycles[0] || TOPB0.result !== c_result[0] || TOPB0.done !== c_done[0])) begin
				n_fail = n_fail + 1;
				$display("TEST_FAIL baseline_counters %0s: top_fpga_base(pipe) cycles=%0d result=%h done=%b != tb copy %0d %h %b",
				         p_hex[p], TOPB0.U_PERF.cycles, TOPB0.result, TOPB0.done, c_cycles[0], c_result[0], c_done[0]);
			end
			if (!has_m && !bad0 && c_cycles[1] !== c_cycles[0]) begin
				n_fail = n_fail + 1;
				$display("TEST_FAIL baseline_counters %0s: pipe_m %0d cycles != pipe %0d on RV32I code",
				         p_hex[p], c_cycles[1], c_cycles[0]);
			end
			n_checks = n_checks + 4;
		end
		if (n_fail == 0) $display("TEST_PASS baseline_counters %0d", n_checks);
		else             $display("TEST_FAIL baseline_counters %0d failures", n_fail);
		$finish;
	end

endmodule
