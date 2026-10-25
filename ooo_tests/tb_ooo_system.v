// tb_ooo_system - Integration testbench comparing pipe_ooo execution with baseline pipeline.
`timescale 1ns/1ps
`include "ooo_defs.vh"

module tb_ooo_system;

	localparam CYCLES  = 600;
	localparam MIN_ST  = 20;
	localparam MAX_ST  = 256;

	reg         clk = 1'b0;
	reg         reset = 1'b0;
	always #5 clk = ~clk;

	wire [31:0] b_iaddr, b_idata, b_raddr, b_rdata, b_waddr, b_wdata;
	wire        b_re, b_we, b_exc;
	wire [ 3:0] b_wstrb;

	wire [31:0] o_iaddr, o_idata, o_raddr, o_rdata, o_waddr, o_wdata;
	wire        o_re, o_we, o_exc;
	wire [ 3:0] o_wstrb;
	wire        o_commit;

	pipe BASE (
		.clk(clk), .reset(reset), .stall(1'b0), .exception(b_exc), .pc_out(),
		.inst_mem_is_valid(1'b1), .inst_mem_read_data(b_idata), .inst_mem_address(b_iaddr),
		.dmem_read_data_temp(b_rdata), .dmem_write_valid(1'b1), .dmem_read_valid(1'b1),
		.dmem_read_ready(b_re), .dmem_read_address(b_raddr),
		.dmem_write_ready(b_we), .dmem_write_address(b_waddr),
		.dmem_write_data(b_wdata), .dmem_write_byte(b_wstrb)
	);
	instr_mem B_IMEM (.clk(clk), .pc(b_iaddr), .instr(b_idata));
	data_mem  B_DMEM (.clk(clk), .re(b_re), .raddr(b_raddr), .rdata(b_rdata),
	                  .we(b_we), .waddr(b_waddr), .wdata(b_wdata), .wstrb(b_wstrb));

	pipe_ooo OOO (
		.clk(clk), .reset(reset), .stall(1'b0), .exception(o_exc), .pc_out(),
		.inst_mem_is_valid(1'b1), .inst_mem_read_data(o_idata), .inst_mem_address(o_iaddr),
		.dmem_read_data_temp(o_rdata), .dmem_write_valid(1'b1), .dmem_read_valid(1'b1),
		.dmem_read_ready(o_re), .dmem_read_address(o_raddr),
		.dmem_write_ready(o_we), .dmem_write_address(o_waddr),
		.dmem_write_data(o_wdata), .dmem_write_byte(o_wstrb),
		.dbg_commit_valid(o_commit), .dbg_commit_pc(), .dbg_commit_rd(), .dbg_commit_has_rd(),
		.dbg_commit_value(), .dbg_commit_is_store(), .dbg_ooo_event(), .dbg_stall_rob(),
		.dbg_stall_rs(), .dbg_hold(), .dbg_cdb_valid()
	);
	instr_mem O_IMEM (.clk(clk), .pc(o_iaddr), .instr(o_idata));
	data_mem  O_DMEM (.clk(clk), .re(o_re), .raddr(o_raddr), .rdata(o_rdata),
	                  .we(o_we), .waddr(o_waddr), .wdata(o_wdata), .wstrb(o_wstrb));

	reg  [67:0] b_st [0:MAX_ST-1];
	reg  [67:0] o_st [0:MAX_ST-1];
	integer     n_b = 0, n_o = 0, n_commit = 0, n_exc = 0, n_fail = 0, i, j;
	reg  [31:0] offset;

	function [31:0] lanes(input [31:0] d, input [3:0] s);
		for (j = 0; j < 4; j = j + 1)
			lanes[8*j +: 8] = s[j] ? d[8*j +: 8] : 8'h00;
	endfunction

	always @(posedge clk) if (reset) begin
		if (b_we && n_b < MAX_ST) begin b_st[n_b] = {b_waddr, lanes(b_wdata, b_wstrb), b_wstrb}; n_b = n_b + 1; end
		if (o_we && n_o < MAX_ST) begin o_st[n_o] = {o_waddr, lanes(o_wdata, o_wstrb), o_wstrb}; n_o = n_o + 1; end
		if (o_commit) n_commit = n_commit + 1;
		if (o_exc)    n_exc = n_exc + 1;
	end

	initial begin
		#100 reset = 1'b1;
		repeat (CYCLES) @(posedge clk);
		#1;
		if (n_o < MIN_ST || n_b < MIN_ST) begin
			n_fail = n_fail + 1;
			$display("TEST_FAIL ooo_system too few stores: baseline %0d, pipe_ooo %0d", n_b, n_o);
		end
		offset = o_st[0][67:36] - b_st[0][67:36];
		for (i = 0; i < n_o && i < n_b; i = i + 1)
			if (o_st[i][35:0] !== b_st[i][35:0] || o_st[i][67:36] - b_st[i][67:36] !== offset) begin
				n_fail = n_fail + 1;
				$display("TEST_FAIL ooo_system store %0d: pipe_ooo addr=%h data=%h strb=%b, baseline addr=%h data=%h strb=%b",
				         i, o_st[i][67:36], o_st[i][35:4], o_st[i][3:0], b_st[i][67:36], b_st[i][35:4], b_st[i][3:0]);
			end
		if (n_exc != 0) begin
			n_fail = n_fail + 1;
			$display("TEST_FAIL ooo_system pipe_ooo exception high in %0d cycles", n_exc);
		end
		$display("%0d cycles: baseline %0d stores, pipe_ooo %0d stores and %0d commits; address offset %h",
		         CYCLES, n_b, n_o, n_commit, offset);
		if (n_fail == 0) $display("TEST_PASS ooo_system %0d", (n_o < n_b) ? n_o : n_b);
		else             $display("TEST_FAIL ooo_system %0d mismatches", n_fail);
		$finish;
	end

endmodule
