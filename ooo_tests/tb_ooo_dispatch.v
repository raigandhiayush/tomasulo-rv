// tb_ooo_dispatch - Self-checking testbench for instruction dispatch and reservation station allocation.
`timescale 1ns/1ps
`include "ooo_defs.vh"

module tb_ooo_dispatch;

	localparam ROB_W = `ROB_W;
	localparam NCDB  = `NCDB;

	reg                     clk = 1'b0;
	reg                     reset_n = 1'b0;
	always #5 clk = ~clk;

	reg                     fq_valid, hold;
	reg     [31: 0]         fq_pc, inst;
	reg                     lk_busy1, lk_busy2;
	reg     [ROB_W-1:0]     lk_tag1, lk_tag2;
	reg     [31: 0]         rf_rdata1, rf_rdata2;
	reg                     rob_rd_ready1, rob_rd_ready2;
	reg     [31: 0]         rob_rd_value1, rob_rd_value2;
	reg     [ROB_W-1:0]     rob_al_tag;
	reg                     rob_full, rs_full_alu, rs_full_mul, rs_full_div, lq_full;
	reg     [NCDB-1:0]      cdb_valid;
	reg     [NCDB*ROB_W-1:0] cdb_tag;
	reg     [NCDB*32-1:0]   cdb_value;

	wire    [`CLS_W-1:0]    cls;
	wire                    illegal, sub, uses_rs1, uses_rs2, writes_rd, use_imm;
	wire                    is_jal, is_jalr, is_branch;
	wire    [ 2: 0]         funct3;
	wire    [ 4: 0]         rs1, rs2, rd;
	wire    [31: 0]         imm, pre_value, br_target;

	wire                    fq_pop;
	wire    [ 4: 0]         lk_rs1, lk_rs2;
	wire    [ROB_W-1:0]     rob_rd_tag1, rob_rd_tag2;
	wire                    rob_al_valid, rob_al_has_rd, rob_al_pre;
	wire    [ 1: 0]         rob_al_kind;
	wire    [ 4: 0]         rob_al_rd;
	wire    [31: 0]         rob_al_pc, rob_al_value;
	wire                    al_valid;
	wire    [ 4: 0]         al_rd;
	wire    [ROB_W-1:0]     al_tag;
	wire                    alu_v, alu_qjv, alu_qkv, mul_v, mul_qjv, mul_qkv, div_v, div_qjv, div_qkv;
	wire    [`OP_W-1:0]     alu_op, mul_op, div_op;
	wire    [ROB_W-1:0]     alu_tag, alu_qj, alu_qk, mul_tag, mul_qj, mul_qk, div_tag, div_qj, div_qk;
	wire    [31: 0]         alu_vj, alu_vk, alu_a, mul_vj, mul_vk, mul_a, div_vj, div_vk, div_a;
	wire                    lq_v, lq_st, lq_qjv, lq_qkv;
	wire    [ 2: 0]         lq_f3;
	wire    [ROB_W-1:0]     lq_tag, lq_qj, lq_qk;
	wire    [31: 0]         lq_vj, lq_vk, lq_imm;
	wire                    redirect_valid, hold_set, exception, stall_rob, stall_rs;
	wire    [31: 0]         redirect_pc;

	ooo_decode DEC (
		.inst(inst), .pc(fq_pc), .cls(cls), .illegal(illegal), .funct3(funct3), .sub(sub),
		.rs1(rs1), .rs2(rs2), .rd(rd), .uses_rs1(uses_rs1), .uses_rs2(uses_rs2),
		.writes_rd(writes_rd), .use_imm(use_imm), .imm(imm), .pre_value(pre_value),
		.is_jal(is_jal), .is_jalr(is_jalr), .is_branch(is_branch), .br_target(br_target)
	);

	ooo_dispatch DUT (
		.clk(clk), .reset_n(reset_n),
		.fq_valid(fq_valid), .fq_pc(fq_pc), .fq_pop(fq_pop), .hold(hold),
		.cls(cls), .illegal(illegal), .funct3(funct3), .sub(sub), .rs1(rs1), .rs2(rs2), .rd(rd),
		.uses_rs1(uses_rs1), .uses_rs2(uses_rs2), .writes_rd(writes_rd), .use_imm(use_imm),
		.imm(imm), .pre_value(pre_value), .is_jal(is_jal), .is_jalr(is_jalr),
		.is_branch(is_branch), .br_target(br_target),
		.lk_rs1(lk_rs1), .lk_rs2(lk_rs2), .lk_busy1(lk_busy1), .lk_tag1(lk_tag1),
		.lk_busy2(lk_busy2), .lk_tag2(lk_tag2), .rf_rdata1(rf_rdata1), .rf_rdata2(rf_rdata2),
		.rob_rd_tag1(rob_rd_tag1), .rob_rd_tag2(rob_rd_tag2),
		.rob_rd_ready1(rob_rd_ready1), .rob_rd_value1(rob_rd_value1),
		.rob_rd_ready2(rob_rd_ready2), .rob_rd_value2(rob_rd_value2),
		.rob_al_valid(rob_al_valid), .rob_al_kind(rob_al_kind), .rob_al_has_rd(rob_al_has_rd),
		.rob_al_rd(rob_al_rd), .rob_al_pc(rob_al_pc), .rob_al_pre(rob_al_pre),
		.rob_al_value(rob_al_value), .rob_al_tag(rob_al_tag),
		.rob_full(rob_full), .rs_full_alu(rs_full_alu), .rs_full_mul(rs_full_mul),
		.rs_full_div(rs_full_div), .lq_full(lq_full),
		.cdb_valid(cdb_valid), .cdb_tag(cdb_tag), .cdb_value(cdb_value),
		.al_valid(al_valid), .al_rd(al_rd), .al_tag(al_tag),
		.alu_al_valid(alu_v), .alu_al_op(alu_op), .alu_al_tag(alu_tag),
		.alu_al_qj_valid(alu_qjv), .alu_al_qj(alu_qj), .alu_al_vj(alu_vj),
		.alu_al_qk_valid(alu_qkv), .alu_al_qk(alu_qk), .alu_al_vk(alu_vk), .alu_al_a(alu_a),
		.mul_al_valid(mul_v), .mul_al_op(mul_op), .mul_al_tag(mul_tag),
		.mul_al_qj_valid(mul_qjv), .mul_al_qj(mul_qj), .mul_al_vj(mul_vj),
		.mul_al_qk_valid(mul_qkv), .mul_al_qk(mul_qk), .mul_al_vk(mul_vk), .mul_al_a(mul_a),
		.div_al_valid(div_v), .div_al_op(div_op), .div_al_tag(div_tag),
		.div_al_qj_valid(div_qjv), .div_al_qj(div_qj), .div_al_vj(div_vj),
		.div_al_qk_valid(div_qkv), .div_al_qk(div_qk), .div_al_vk(div_vk), .div_al_a(div_a),
		.lq_al_valid(lq_v), .lq_al_store(lq_st), .lq_al_funct3(lq_f3), .lq_al_tag(lq_tag),
		.lq_al_qj_valid(lq_qjv), .lq_al_qj(lq_qj), .lq_al_vj(lq_vj),
		.lq_al_qk_valid(lq_qkv), .lq_al_qk(lq_qk), .lq_al_vk(lq_vk), .lq_al_imm(lq_imm),
		.redirect_valid(redirect_valid), .redirect_pc(redirect_pc), .hold_set(hold_set),
		.exception(exception), .stall_rob(stall_rob), .stall_rs(stall_rs)
	);

	integer n_vec = 0, n_fail = 0, k;

	task ok(input cond, input [8*56-1:0] what);
		begin
			n_vec = n_vec + 1;
			if (!cond) begin
				n_fail = n_fail + 1;
				$display("TEST_FAIL ooo_dispatch t=%0t inst=%h: %0s", $time, inst, what);
			end
		end
	endtask

	task idle_inputs;
		begin
			fq_valid = 1'b1; hold = 1'b0; fq_pc = 32'h0000_0100;
			lk_busy1 = 1'b0; lk_busy2 = 1'b0; lk_tag1 = 0; lk_tag2 = 0;
			rf_rdata1 = 32'h1111_1111; rf_rdata2 = 32'h2222_2222;
			rob_rd_ready1 = 1'b0; rob_rd_ready2 = 1'b0;
			rob_rd_value1 = 32'hAAAA_0001; rob_rd_value2 = 32'hAAAA_0002;
			rob_al_tag = 3'd5;
			rob_full = 1'b0; rs_full_alu = 1'b0; rs_full_mul = 1'b0; rs_full_div = 1'b0; lq_full = 1'b0;
			cdb_valid = 0; cdb_tag = 0; cdb_value = 0;
		end
	endtask

	task bus(input integer b, input [ROB_W-1:0] t, input [31:0] v);
		begin
			cdb_valid[b]               = 1'b1;
			cdb_tag[b*ROB_W +: ROB_W]  = t;
			cdb_value[b*32 +: 32]      = v;
		end
	endtask

	function [31:0] r_type(input [6:0] f7, input [4:0] r2, input [4:0] r1, input [2:0] f3, input [4:0] d);
		r_type = {f7, r2, r1, f3, d, 7'b0110011};
	endfunction

	localparam [31:0] ADD   = 32'h0020_81B3;
	localparam [31:0] ADDI  = 32'hFFF0_8193;
	localparam [31:0] SRAI  = 32'h4030_D193;
	localparam [31:0] SUB   = 32'h4020_81B3;
	localparam [31:0] BLT   = 32'h0020_C463;
	localparam [31:0] JALR  = 32'h0100_81E7;
	localparam [31:0] MULH  = 32'h0220_91B3;
	localparam [31:0] REMU  = 32'h0220_F1B3;
	localparam [31:0] LH    = 32'hFFC0_9183;
	localparam [31:0] SB    = 32'h0020_8223;
	localparam [31:0] LUI   = 32'h1234_51B7;
	localparam [31:0] JAL   = 32'h0100_01EF;
	localparam [31:0] ADDX0 = 32'h0020_8033;
	localparam [31:0] ILL   = 32'hFFFF_FFFF;

	initial begin
		idle_inputs;
		inst = ADD;
		#2 reset_n = 1'b1;

		#1 ok(fq_pop && rob_al_valid && alu_v && !mul_v && !div_v && !lq_v, "ADD fires into the ALU RS only");
		ok(lk_rs1 == 1 && lk_rs2 == 2, "RAT lookup addresses");
		ok(!alu_qjv && alu_vj == 32'h1111_1111 && !alu_qkv && alu_vk == 32'h2222_2222, "ARF operands");
		ok(al_valid && al_rd == 3 && al_tag == 5 && alu_tag == 5, "RAT allocate with the ROB tag");
		ok(rob_al_kind == `KIND_VALUE && rob_al_has_rd && rob_al_rd == 3 && !rob_al_pre && rob_al_pc == 32'h100, "ROB allocate fields");
		ok(alu_op == 8'h00 && alu_a == 0, "ADD op encoding");
		ok(!stall_rob && !stall_rs && !hold_set && !redirect_valid, "no stall, hold or redirect");

		lk_busy1 = 1'b1; lk_tag1 = 3'd2; rob_rd_ready1 = 1'b1;
		#1 ok(rob_rd_tag1 == 2 && !alu_qjv && alu_vj == 32'hAAAA_0001, "ROB ready value");
		bus(0, 3'd2, 32'hBBBB_0000);
		#1 ok(!alu_qjv && alu_vj == 32'hAAAA_0001, "ROB ready wins over a bus");
		rob_rd_ready1 = 1'b0; cdb_valid = 0;
		#1 ok(alu_qjv && alu_qj == 2, "wait on tag");
		for (k = 0; k < NCDB; k = k + 1) begin
			cdb_valid = 0;
			bus(k, 3'd2, 32'hC000_0000 + k);
			#1 ok(!alu_qjv && alu_vj == 32'hC000_0000 + k, "rs1 bypass from bus k");
		end
		cdb_valid = 0;
		bus(1, 3'd6, 32'hDEAD_0001);
		#1 ok(alu_qjv && alu_qj == 2, "bus with another tag is ignored");
		lk_busy2 = 1'b1; lk_tag2 = 3'd4;
		cdb_valid = 0;
		bus(1, 3'd2, 32'h0000_1111);
		bus(3, 3'd4, 32'h0000_3333);
		#1 ok(!alu_qjv && alu_vj == 32'h1111 && !alu_qkv && alu_vk == 32'h3333, "rs1 and rs2 from two buses in one cycle");
		cdb_valid = 0;
		bus(2, 3'd2, 32'h0000_2222);
		bus(0, 3'd4, 32'h0000_0444);
		#1 ok(!alu_qjv && alu_vj == 32'h2222 && !alu_qkv && alu_vk == 32'h0444, "two buses, roles swapped");
		cdb_valid = 0;
		#1 ok(alu_qjv && alu_qj == 2 && alu_qkv && alu_qk == 4, "both operands wait");

		idle_inputs;
		inst = 32'h0000_01B3;
		lk_busy1 = 1'b1; lk_busy2 = 1'b1;
		#1 ok(!alu_qjv && alu_vj == 0 && !alu_qkv && alu_vk == 0, "x0 sources read 0");

		idle_inputs;
		inst = ADDI;
		lk_busy2 = 1'b1; lk_tag2 = 3'd1;
		#1 ok(alu_v && !alu_qkv && alu_vk == 32'hFFFF_FFFF && alu_op == 8'h00, "ADDI: immediate in vk");
		inst = SRAI;
		#1 ok(alu_v && alu_vk[4:0] == 3 && alu_op == 8'h0D, "SRAI: op sub/sra bit and funct3");
		inst = SUB;
		#1 ok(alu_op == 8'h08, "SUB op encoding");

		idle_inputs;
		inst = BLT;
		#1 ok(alu_v && alu_op == 8'h14 && alu_a == 32'h108, "BLT: is_branch, funct3, a = pc+imm");
		ok(hold_set && rob_al_kind == `KIND_BRANCH && !rob_al_has_rd && !al_valid, "BLT: hold, branch kind, no rd");
		ok(alu_vj == 32'h1111_1111 && alu_vk == 32'h2222_2222, "BLT operands");

		idle_inputs;
		inst = JALR;
		lk_busy2 = 1'b1;
		#1 ok(alu_v && alu_op == 8'h20 && alu_vk == 32'h104 && !alu_qkv && alu_a == 32'h10, "JALR: vk = pc+4, a = imm (D15)");
		ok(hold_set && rob_al_kind == `KIND_BRANCH && rob_al_has_rd && al_valid && al_rd == 3 && !rob_al_pre, "JALR: hold, link register renamed");

		idle_inputs;
		inst = MULH;
		lk_busy2 = 1'b1; lk_tag2 = 3'd7;
		#1 ok(mul_v && !alu_v && !div_v && mul_op == 8'h01 && mul_qkv && mul_qk == 7 && mul_vj == 32'h1111_1111, "MULH into the MUL RS");
		inst = REMU;
		#1 ok(div_v && !mul_v && div_op == 8'h07 && div_qkv && div_qk == 7, "REMU into the DIV RS");

		idle_inputs;
		inst = LH;
		lk_busy2 = 1'b1;
		#1 ok(lq_v && !lq_st && lq_f3 == 3'b001 && lq_imm == 32'hFFFF_FFFC && !lq_qjv && lq_vj == 32'h1111_1111 && !lq_qkv, "LH into the LSQ");
		ok(rob_al_kind == `KIND_VALUE && al_valid && !alu_v, "LH: value kind, rd renamed");
		inst = SB;
		lk_busy2 = 1'b1; lk_tag2 = 3'd3;
		#1 ok(lq_v && lq_st && lq_f3 == 3'b000 && lq_imm == 4 && lq_qkv && lq_qk == 3, "SB: store data waits");
		ok(rob_al_kind == `KIND_STORE && !rob_al_has_rd && !al_valid, "SB: store kind, no rd");

		idle_inputs;
		inst = LUI;
		rs_full_alu = 1'b1; rs_full_mul = 1'b1; rs_full_div = 1'b1; lq_full = 1'b1;
		#1 ok(fq_pop && rob_al_pre && rob_al_value == 32'h1234_5000 && !alu_v && !lq_v && al_valid, "LUI: ready at dispatch, no RS");
		inst = JAL;
		#1 ok(fq_pop && rob_al_pre && rob_al_value == 32'h104 && redirect_valid && redirect_pc == 32'h110 && !hold_set, "JAL: link value and redirect");
		inst = ADDX0;
		rs_full_alu = 1'b0;
		#1 ok(alu_v && !al_valid && !rob_al_has_rd, "rd = x0 is not renamed");

		idle_inputs;
		inst = ADD;
		rob_full = 1'b1;
		#1 ok(!fq_pop && !rob_al_valid && !alu_v && !al_valid && stall_rob && !stall_rs, "ROB full stalls");
		rob_full = 1'b0; rs_full_alu = 1'b1;
		#1 ok(!fq_pop && !rob_al_valid && !alu_v && !al_valid && stall_rs && !stall_rob, "ALU RS full stalls");
		inst = BLT;
		#1 ok(!fq_pop && !hold_set && stall_rs, "branch waits for the ALU RS");
		rs_full_alu = 1'b0; rs_full_mul = 1'b1; inst = MULH;
		#1 ok(!fq_pop && !mul_v && stall_rs, "MUL RS full stalls");
		inst = ADD;
		#1 ok(fq_pop && alu_v, "full MUL RS does not block ALU");
		rs_full_mul = 1'b0; rs_full_div = 1'b1; inst = REMU;
		#1 ok(!fq_pop && !div_v && stall_rs, "DIV RS full stalls");
		rs_full_div = 1'b0; lq_full = 1'b1; inst = LH;
		#1 ok(!fq_pop && !lq_v && stall_rs, "LSQ full stalls a load");
		inst = SB;
		#1 ok(!fq_pop && !lq_v && stall_rs, "LSQ full stalls a store");
		lq_full = 1'b0; hold = 1'b1; inst = ADD;
		#1 ok(!fq_pop && !rob_al_valid && !stall_rob && !stall_rs, "hold blocks dispatch");
		hold = 1'b0; fq_valid = 1'b0;
		#1 ok(!fq_pop && !rob_al_valid && !alu_v && !stall_rob && !stall_rs, "empty queue: nothing happens");

		idle_inputs;
		inst = ILL;
		#1 ok(fq_pop && rob_al_pre && !rob_al_has_rd && rob_al_kind == `KIND_VALUE && rob_al_value == 0 && !alu_v && !lq_v && !al_valid, "illegal: NOP entry (D12)");
		ok(!exception, "exception clear before the clock");
		@(posedge clk); #1;
		ok(exception, "exception set after an illegal dispatch");
		inst = ADD;
		@(posedge clk); #1;
		ok(exception, "exception is sticky");
		rob_full = 1'b1; inst = ILL;
		reset_n = 1'b0; #1;
		ok(!exception, "reset clears exception");
		reset_n = 1'b1;
		@(posedge clk); #1;
		ok(!exception, "stalled illegal instruction does not set exception");

		if (n_fail == 0) $display("TEST_PASS ooo_dispatch %0d", n_vec);
		else             $display("TEST_FAIL ooo_dispatch %0d of %0d vectors failed", n_fail, n_vec);
		$finish;
	end

endmodule
