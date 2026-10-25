// ooo_dispatch - Instruction rename, dispatch, and reservation station allocation.
`timescale 1ns/1ps
`include "ooo_defs.vh"

module ooo_dispatch
#(
	parameter ROB_W = `ROB_W,
	parameter NCDB  = `NCDB
)
(
	input                       clk,
	input                       reset_n,

	input                       fq_valid,
	input       [31: 0]         fq_pc,
	output                      fq_pop,
	input                       hold,

	input       [ 2: 0]         cls,
	input                       illegal,
	input       [ 2: 0]         funct3,
	input                       sub,
	input       [ 4: 0]         rs1,
	input       [ 4: 0]         rs2,
	input       [ 4: 0]         rd,
	input                       uses_rs1,
	input                       uses_rs2,
	input                       writes_rd,
	input                       use_imm,
	input       [31: 0]         imm,
	input       [31: 0]         pre_value,
	input                       is_jal,
	input                       is_jalr,
	input                       is_branch,
	input       [31: 0]         br_target,

	output      [ 4: 0]         lk_rs1,
	output      [ 4: 0]         lk_rs2,
	input                       lk_busy1,
	input       [ROB_W-1:0]     lk_tag1,
	input                       lk_busy2,
	input       [ROB_W-1:0]     lk_tag2,

	input       [31: 0]         rf_rdata1,
	input       [31: 0]         rf_rdata2,

	output      [ROB_W-1:0]     rob_rd_tag1,
	output      [ROB_W-1:0]     rob_rd_tag2,
	input                       rob_rd_ready1,
	input       [31: 0]         rob_rd_value1,
	input                       rob_rd_ready2,
	input       [31: 0]         rob_rd_value2,

	output                      rob_al_valid,
	output      [ 1: 0]         rob_al_kind,
	output                      rob_al_has_rd,
	output      [ 4: 0]         rob_al_rd,
	output      [31: 0]         rob_al_pc,
	output                      rob_al_pre,
	output      [31: 0]         rob_al_value,
	input       [ROB_W-1:0]     rob_al_tag,

	input                       rob_full,
	input                       rs_full_alu,
	input                       rs_full_mul,
	input                       rs_full_div,
	input                       lq_full,

	input       [NCDB-1:0]      cdb_valid,
	input       [NCDB*ROB_W-1:0] cdb_tag,
	input       [NCDB*32-1:0]   cdb_value,

	output                      al_valid,
	output      [ 4: 0]         al_rd,
	output      [ROB_W-1:0]     al_tag,

	output                      alu_al_valid,
	output      [`OP_W-1:0]     alu_al_op,
	output      [ROB_W-1:0]     alu_al_tag,
	output                      alu_al_qj_valid,
	output      [ROB_W-1:0]     alu_al_qj,
	output      [31: 0]         alu_al_vj,
	output                      alu_al_qk_valid,
	output      [ROB_W-1:0]     alu_al_qk,
	output      [31: 0]         alu_al_vk,
	output      [31: 0]         alu_al_a,

	output                      mul_al_valid,
	output      [`OP_W-1:0]     mul_al_op,
	output      [ROB_W-1:0]     mul_al_tag,
	output                      mul_al_qj_valid,
	output      [ROB_W-1:0]     mul_al_qj,
	output      [31: 0]         mul_al_vj,
	output                      mul_al_qk_valid,
	output      [ROB_W-1:0]     mul_al_qk,
	output      [31: 0]         mul_al_vk,
	output      [31: 0]         mul_al_a,

	output                      div_al_valid,
	output      [`OP_W-1:0]     div_al_op,
	output      [ROB_W-1:0]     div_al_tag,
	output                      div_al_qj_valid,
	output      [ROB_W-1:0]     div_al_qj,
	output      [31: 0]         div_al_vj,
	output                      div_al_qk_valid,
	output      [ROB_W-1:0]     div_al_qk,
	output      [31: 0]         div_al_vk,
	output      [31: 0]         div_al_a,

	output                      lq_al_valid,
	output                      lq_al_store,
	output      [ 2: 0]         lq_al_funct3,
	output      [ROB_W-1:0]     lq_al_tag,
	output                      lq_al_qj_valid,
	output      [ROB_W-1:0]     lq_al_qj,
	output      [31: 0]         lq_al_vj,
	output                      lq_al_qk_valid,
	output      [ROB_W-1:0]     lq_al_qk,
	output      [31: 0]         lq_al_vk,
	output      [31: 0]         lq_al_imm,

	output                      redirect_valid,
	output      [31: 0]         redirect_pc,
	output                      hold_set,

	output reg                  exception,
	output                      stall_rob,
	output                      stall_rs
);

	reg                     byp1_hit, byp2_hit;
	reg         [31: 0]     byp1_value, byp2_value;
	integer                 k;

	always @(*) begin
		byp1_hit   = 1'b0;
		byp1_value = 32'd0;
		byp2_hit   = 1'b0;
		byp2_value = 32'd0;
		for (k = 0; k < NCDB; k = k + 1) begin
			if (cdb_valid[k] && cdb_tag[k*ROB_W +: ROB_W] == lk_tag1) begin
				byp1_hit   = 1'b1;
				byp1_value = cdb_value[k*32 +: 32];
			end
			if (cdb_valid[k] && cdb_tag[k*ROB_W +: ROB_W] == lk_tag2) begin
				byp2_hit   = 1'b1;
				byp2_value = cdb_value[k*32 +: 32];
			end
		end
	end

	reg                     op1_wait, op2_wait;
	reg         [31: 0]     op1_value, op2_value;

	always @(*) begin
		op1_wait  = 1'b0;
		op1_value = 32'd0;
		if (rs1 == 5'd0)
			op1_value = 32'd0;
		else if (!lk_busy1)
			op1_value = rf_rdata1;
		else if (rob_rd_ready1)
			op1_value = rob_rd_value1;
		else if (byp1_hit)
			op1_value = byp1_value;
		else
			op1_wait  = 1'b1;
	end

	always @(*) begin
		op2_wait  = 1'b0;
		op2_value = 32'd0;
		if (rs2 == 5'd0)
			op2_value = 32'd0;
		else if (!lk_busy2)
			op2_value = rf_rdata2;
		else if (rob_rd_ready2)
			op2_value = rob_rd_value2;
		else if (byp2_hit)
			op2_value = byp2_value;
		else
			op2_wait  = 1'b1;
	end

	wire cls_alu = (cls == `CLS_ALU) | (cls == `CLS_BR);
	wire cls_mul = (cls == `CLS_MUL);
	wire cls_div = (cls == `CLS_DIV);
	wire cls_mem = (cls == `CLS_LD) | (cls == `CLS_ST);
	wire cls_st  = (cls == `CLS_ST);
	wire cls_pre = (cls == `CLS_PRE) | (cls == `CLS_NOP);
	wire cls_nop = (cls == `CLS_NOP);

	wire class_ok = (cls_alu & ~rs_full_alu) |
	                (cls_mul & ~rs_full_mul) |
	                (cls_div & ~rs_full_div) |
	                (cls_mem & ~lq_full)     |
	                 cls_pre;

	wire try  = fq_valid & ~hold;
	wire fire = try & ~rob_full & class_ok;

	assign stall_rob = try & rob_full;
	assign stall_rs  = try & ~rob_full & ~class_ok;
	assign fq_pop    = fire;

	assign lk_rs1      = rs1;
	assign lk_rs2      = rs2;
	assign rob_rd_tag1 = lk_tag1;
	assign rob_rd_tag2 = lk_tag2;

	assign rob_al_valid  = fire;
	assign rob_al_kind   = cls_st                ? `KIND_STORE  :
	                       (cls == `CLS_BR)      ? `KIND_BRANCH : `KIND_VALUE;
	assign rob_al_has_rd = writes_rd & ~cls_nop;
	assign rob_al_rd     = rob_al_has_rd ? rd : 5'd0;
	assign rob_al_pc     = fq_pc;
	assign rob_al_pre    = cls_pre;
	assign rob_al_value  = (cls == `CLS_PRE) ? pre_value : 32'd0;

	assign al_valid = fire & rob_al_has_rd;
	assign al_rd    = rd;
	assign al_tag   = rob_al_tag;

	wire                rs_qk_valid = ~use_imm & ~is_jalr & op2_wait;
	wire    [31: 0]     rs_vk       = is_jalr ? pre_value :
	                                  use_imm ? imm       : op2_value;
	wire    [31: 0]     rs_a        = is_branch ? br_target :
	                                  is_jalr   ? imm       : 32'd0;
	wire    [`OP_W-1:0] rs_op;

	assign rs_op[`OP_F3_HI:`OP_F3_LO] = funct3;
	assign rs_op[`OP_ALT_BIT]         = sub;
	assign rs_op[`OP_BR_BIT]          = is_branch;
	assign rs_op[`OP_JALR_BIT]        = is_jalr;
	assign rs_op[`OP_W-1:`OP_JALR_BIT+1] = {(`OP_W-`OP_JALR_BIT-1){1'b0}};

	assign alu_al_valid    = fire & cls_alu;
	assign alu_al_op       = rs_op;
	assign alu_al_tag      = rob_al_tag;
	assign alu_al_qj_valid = op1_wait;
	assign alu_al_qj       = lk_tag1;
	assign alu_al_vj       = op1_value;
	assign alu_al_qk_valid = rs_qk_valid;
	assign alu_al_qk       = lk_tag2;
	assign alu_al_vk       = rs_vk;
	assign alu_al_a        = rs_a;

	assign mul_al_valid    = fire & cls_mul;
	assign mul_al_op       = rs_op;
	assign mul_al_tag      = rob_al_tag;
	assign mul_al_qj_valid = op1_wait;
	assign mul_al_qj       = lk_tag1;
	assign mul_al_vj       = op1_value;
	assign mul_al_qk_valid = op2_wait;
	assign mul_al_qk       = lk_tag2;
	assign mul_al_vk       = op2_value;
	assign mul_al_a        = 32'd0;

	assign div_al_valid    = fire & cls_div;
	assign div_al_op       = rs_op;
	assign div_al_tag      = rob_al_tag;
	assign div_al_qj_valid = op1_wait;
	assign div_al_qj       = lk_tag1;
	assign div_al_vj       = op1_value;
	assign div_al_qk_valid = op2_wait;
	assign div_al_qk       = lk_tag2;
	assign div_al_vk       = op2_value;
	assign div_al_a        = 32'd0;

	assign lq_al_valid    = fire & cls_mem;
	assign lq_al_store    = cls_st;
	assign lq_al_funct3   = funct3;
	assign lq_al_tag      = rob_al_tag;
	assign lq_al_qj_valid = op1_wait;
	assign lq_al_qj       = lk_tag1;
	assign lq_al_vj       = op1_value;
	assign lq_al_qk_valid = cls_st & op2_wait;
	assign lq_al_qk       = lk_tag2;
	assign lq_al_vk       = op2_value;
	assign lq_al_imm      = imm;

	assign redirect_valid = fire & is_jal;
	assign redirect_pc    = br_target;
	assign hold_set       = fire & (cls == `CLS_BR);

	always @(posedge clk or negedge reset_n) begin
		if (!reset_n)
			exception <= 1'b0;
		else if (fire && cls_nop)
			exception <= 1'b1;
	end

endmodule
