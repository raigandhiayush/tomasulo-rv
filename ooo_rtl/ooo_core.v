// ooo_core - Out-of-order core top module.
`timescale 1ns/1ps
`include "ooo_defs.vh"

module ooo_core
#(
	parameter [31: 0] RESET = `RESET_PC
)
(
	input                       clk,
	input                       reset_n,

	output      [31: 0]         imem_addr,
	input       [31: 0]         imem_data,

	output                      dmem_re,
	output      [31: 0]         dmem_raddr,
	input       [31: 0]         dmem_rdata,
	output                      dmem_we,
	output      [31: 0]         dmem_waddr,
	output      [31: 0]         dmem_wdata,
	output      [ 3: 0]         dmem_wstrb,

	output                      exception,

	output                      dbg_commit_valid,
	output      [31: 0]         dbg_commit_pc,
	output      [ 4: 0]         dbg_commit_rd,
	output                      dbg_commit_has_rd,
	output      [31: 0]         dbg_commit_value,
	output                      dbg_commit_is_store,
	output                      dbg_ooo_event,
	output                      dbg_stall_rob,
	output                      dbg_stall_rs,
	output                      dbg_hold,
	output      [`NCDB-1:0]     dbg_cdb_valid
);

	wire    [`NCDB-1:0]         cdb_valid;
	wire    [`NCDB*`ROB_W-1:0]  cdb_tag;
	wire    [`NCDB*`XLEN-1:0]   cdb_value;

	wire                        fq_valid;
	wire    [31: 0]             fq_pc;
	wire    [31: 0]             fq_inst;
	wire                        fq_pop;
	wire                        hold;
	wire                        hold_set;
	wire                        redirect_valid;
	wire    [31: 0]             redirect_pc;
	wire                        br_valid;
	wire                        br_taken;
	wire    [31: 0]             br_target;

	wire    [`CLS_W-1:0]        d_cls;
	wire                        d_illegal;
	wire    [`F3_W-1:0]         d_funct3;
	wire                        d_sub;
	wire    [ 4: 0]             d_rs1, d_rs2, d_rd;
	wire                        d_uses_rs1, d_uses_rs2, d_writes_rd, d_use_imm;
	wire    [31: 0]             d_imm, d_pre_value, d_br_target;
	wire                        d_is_jal, d_is_jalr, d_is_branch;

	wire    [ 4: 0]             lk_rs1, lk_rs2;
	wire                        lk_busy1, lk_busy2;
	wire    [`ROB_W-1:0]        lk_tag1, lk_tag2;
	wire                        al_valid;
	wire    [ 4: 0]             al_rd;
	wire    [`ROB_W-1:0]        al_tag;

	wire    [31: 0]             rf_rdata1, rf_rdata2;

	wire    [`ROB_W-1:0]        rob_rd_tag1, rob_rd_tag2;
	wire                        rob_rd_ready1, rob_rd_ready2;
	wire    [31: 0]             rob_rd_value1, rob_rd_value2;
	wire                        rob_al_valid;
	wire    [`KIND_W-1:0]       rob_al_kind;
	wire                        rob_al_has_rd;
	wire    [ 4: 0]             rob_al_rd;
	wire    [31: 0]             rob_al_pc;
	wire                        rob_al_pre;
	wire    [31: 0]             rob_al_value;
	wire    [`ROB_W-1:0]        rob_al_tag;
	wire                        rob_full;

	wire                        cm_valid;
	wire    [`ROB_W-1:0]        cm_tag;
	wire                        cm_has_rd;
	wire    [ 4: 0]             cm_rd;
	wire    [31: 0]             cm_value;
	wire                        cm_is_store;
	wire    [31: 0]             cm_pc;
	wire                        ooo_event;

	wire                        rs_full_alu, rs_full_mul, rs_full_div, lq_full;

	wire                        alu_al_valid, alu_al_qj_valid, alu_al_qk_valid;
	wire    [`OP_W-1:0]         alu_al_op;
	wire    [`ROB_W-1:0]        alu_al_tag, alu_al_qj, alu_al_qk;
	wire    [31: 0]             alu_al_vj, alu_al_vk, alu_al_a;

	wire                        mul_al_valid, mul_al_qj_valid, mul_al_qk_valid;
	wire    [`OP_W-1:0]         mul_al_op;
	wire    [`ROB_W-1:0]        mul_al_tag, mul_al_qj, mul_al_qk;
	wire    [31: 0]             mul_al_vj, mul_al_vk, mul_al_a;

	wire                        div_al_valid, div_al_qj_valid, div_al_qk_valid;
	wire    [`OP_W-1:0]         div_al_op;
	wire    [`ROB_W-1:0]        div_al_tag, div_al_qj, div_al_qk;
	wire    [31: 0]             div_al_vj, div_al_vk, div_al_a;

	wire                        lq_al_valid, lq_al_store;
	wire    [ 2: 0]             lq_al_funct3;
	wire    [`ROB_W-1:0]        lq_al_tag, lq_al_qj, lq_al_qk;
	wire                        lq_al_qj_valid, lq_al_qk_valid;
	wire    [31: 0]             lq_al_vj, lq_al_vk, lq_al_imm;

	wire                        stall_rob, stall_rs;

	wire                        alu_iss_valid;
	wire    [`OP_W-1:0]         alu_iss_op;
	wire    [`ROB_W-1:0]        alu_iss_tag;
	wire    [`XLEN-1:0]         alu_iss_vj, alu_iss_vk, alu_iss_a;
	wire    [`XLEN-1:0]         alu_result;
	wire                        alu_is_ctrl;
	wire                        alu_taken;
	wire    [`XLEN-1:0]         alu_target;

	wire                        mul_iss_valid;
	wire    [`OP_W-1:0]         mul_iss_op;
	wire    [`ROB_W-1:0]        mul_iss_tag;
	wire    [`XLEN-1:0]         mul_iss_vj, mul_iss_vk, mul_iss_a;

	wire                        div_iss_valid;
	wire    [`OP_W-1:0]         div_iss_op;
	wire    [`ROB_W-1:0]        div_iss_tag;
	wire    [`XLEN-1:0]         div_iss_vj, div_iss_vk, div_iss_a;
	wire                        div_busy;

	ooo_frontend #(.RESET(RESET)) frontend (
		.clk            (clk),
		.reset_n        (reset_n),
		.imem_data      (imem_data),
		.imem_addr      (imem_addr),
		.redirect_valid (redirect_valid),
		.redirect_pc    (redirect_pc),
		.hold_set       (hold_set),
		.br_valid       (br_valid),
		.br_taken       (br_taken),
		.br_target      (br_target),
		.fq_pop         (fq_pop),
		.fq_valid       (fq_valid),
		.fq_pc          (fq_pc),
		.fq_inst        (fq_inst),
		.hold           (hold)
	);

	ooo_decode decode (
		.inst           (fq_inst),
		.pc             (fq_pc),
		.cls            (d_cls),
		.illegal        (d_illegal),
		.funct3         (d_funct3),
		.sub            (d_sub),
		.rs1            (d_rs1),
		.rs2            (d_rs2),
		.rd             (d_rd),
		.uses_rs1       (d_uses_rs1),
		.uses_rs2       (d_uses_rs2),
		.writes_rd      (d_writes_rd),
		.use_imm        (d_use_imm),
		.imm            (d_imm),
		.pre_value      (d_pre_value),
		.is_jal         (d_is_jal),
		.is_jalr        (d_is_jalr),
		.is_branch      (d_is_branch),
		.br_target      (d_br_target)
	);

	ooo_dispatch dispatch (
		.clk             (clk),
		.reset_n         (reset_n),
		.fq_valid        (fq_valid),
		.fq_pc           (fq_pc),
		.fq_pop          (fq_pop),
		.hold            (hold),
		.cls             (d_cls),
		.illegal         (d_illegal),
		.funct3          (d_funct3),
		.sub             (d_sub),
		.rs1             (d_rs1),
		.rs2             (d_rs2),
		.rd              (d_rd),
		.uses_rs1        (d_uses_rs1),
		.uses_rs2        (d_uses_rs2),
		.writes_rd       (d_writes_rd),
		.use_imm         (d_use_imm),
		.imm             (d_imm),
		.pre_value       (d_pre_value),
		.is_jal          (d_is_jal),
		.is_jalr         (d_is_jalr),
		.is_branch       (d_is_branch),
		.br_target       (d_br_target),
		.lk_rs1          (lk_rs1),
		.lk_rs2          (lk_rs2),
		.lk_busy1        (lk_busy1),
		.lk_tag1         (lk_tag1),
		.lk_busy2        (lk_busy2),
		.lk_tag2         (lk_tag2),
		.rf_rdata1       (rf_rdata1),
		.rf_rdata2       (rf_rdata2),
		.rob_rd_tag1     (rob_rd_tag1),
		.rob_rd_tag2     (rob_rd_tag2),
		.rob_rd_ready1   (rob_rd_ready1),
		.rob_rd_value1   (rob_rd_value1),
		.rob_rd_ready2   (rob_rd_ready2),
		.rob_rd_value2   (rob_rd_value2),
		.rob_al_valid    (rob_al_valid),
		.rob_al_kind     (rob_al_kind),
		.rob_al_has_rd   (rob_al_has_rd),
		.rob_al_rd       (rob_al_rd),
		.rob_al_pc       (rob_al_pc),
		.rob_al_pre      (rob_al_pre),
		.rob_al_value    (rob_al_value),
		.rob_al_tag      (rob_al_tag),
		.rob_full        (rob_full),
		.rs_full_alu     (rs_full_alu),
		.rs_full_mul     (rs_full_mul),
		.rs_full_div     (rs_full_div),
		.lq_full         (lq_full),
		.cdb_valid       (cdb_valid),
		.cdb_tag         (cdb_tag),
		.cdb_value       (cdb_value),
		.al_valid        (al_valid),
		.al_rd           (al_rd),
		.al_tag          (al_tag),
		.alu_al_valid    (alu_al_valid),
		.alu_al_op       (alu_al_op),
		.alu_al_tag      (alu_al_tag),
		.alu_al_qj_valid (alu_al_qj_valid),
		.alu_al_qj       (alu_al_qj),
		.alu_al_vj       (alu_al_vj),
		.alu_al_qk_valid (alu_al_qk_valid),
		.alu_al_qk       (alu_al_qk),
		.alu_al_vk       (alu_al_vk),
		.alu_al_a        (alu_al_a),
		.mul_al_valid    (mul_al_valid),
		.mul_al_op       (mul_al_op),
		.mul_al_tag      (mul_al_tag),
		.mul_al_qj_valid (mul_al_qj_valid),
		.mul_al_qj       (mul_al_qj),
		.mul_al_vj       (mul_al_vj),
		.mul_al_qk_valid (mul_al_qk_valid),
		.mul_al_qk       (mul_al_qk),
		.mul_al_vk       (mul_al_vk),
		.mul_al_a        (mul_al_a),
		.div_al_valid    (div_al_valid),
		.div_al_op       (div_al_op),
		.div_al_tag      (div_al_tag),
		.div_al_qj_valid (div_al_qj_valid),
		.div_al_qj       (div_al_qj),
		.div_al_vj       (div_al_vj),
		.div_al_qk_valid (div_al_qk_valid),
		.div_al_qk       (div_al_qk),
		.div_al_vk       (div_al_vk),
		.div_al_a        (div_al_a),
		.lq_al_valid     (lq_al_valid),
		.lq_al_store     (lq_al_store),
		.lq_al_funct3    (lq_al_funct3),
		.lq_al_tag       (lq_al_tag),
		.lq_al_qj_valid  (lq_al_qj_valid),
		.lq_al_qj        (lq_al_qj),
		.lq_al_vj        (lq_al_vj),
		.lq_al_qk_valid  (lq_al_qk_valid),
		.lq_al_qk        (lq_al_qk),
		.lq_al_vk        (lq_al_vk),
		.lq_al_imm       (lq_al_imm),
		.redirect_valid  (redirect_valid),
		.redirect_pc     (redirect_pc),
		.hold_set        (hold_set),
		.exception       (exception),
		.stall_rob       (stall_rob),
		.stall_rs        (stall_rs)
	);

	rat rat (
		.clk      (clk),
		.reset_n  (reset_n),
		.lk_rs1   (lk_rs1),
		.lk_rs2   (lk_rs2),
		.lk_busy1 (lk_busy1),
		.lk_tag1  (lk_tag1),
		.lk_busy2 (lk_busy2),
		.lk_tag2  (lk_tag2),
		.al_valid (al_valid),
		.al_rd    (al_rd),
		.al_tag   (al_tag),
		.cm_valid (cm_valid & cm_has_rd),
		.cm_rd    (cm_rd),
		.cm_tag   (cm_tag)
	);

	regfile_2r1w regfile (
		.clk     (clk),
		.reset_n (reset_n),
		.raddr1  (lk_rs1),
		.rdata1  (rf_rdata1),
		.raddr2  (lk_rs2),
		.rdata2  (rf_rdata2),
		.we      (cm_valid & cm_has_rd),
		.waddr   (cm_rd),
		.wdata   (cm_value)
	);

	rob rob (
		.clk           (clk),
		.reset_n       (reset_n),
		.rob_al_valid  (rob_al_valid),
		.rob_al_kind   (rob_al_kind),
		.rob_al_has_rd (rob_al_has_rd),
		.rob_al_rd     (rob_al_rd),
		.rob_al_pc     (rob_al_pc),
		.rob_al_pre    (rob_al_pre),
		.rob_al_value  (rob_al_value),
		.rob_al_tag    (rob_al_tag),
		.rob_full      (rob_full),
		.rob_empty     (),
		.rob_count     (),
		.rob_rd_tag1   (rob_rd_tag1),
		.rob_rd_tag2   (rob_rd_tag2),
		.rob_rd_ready1 (rob_rd_ready1),
		.rob_rd_ready2 (rob_rd_ready2),
		.rob_rd_value1 (rob_rd_value1),
		.rob_rd_value2 (rob_rd_value2),
		.cdb_valid     (cdb_valid),
		.cdb_tag       (cdb_tag),
		.cdb_value     (cdb_value),
		.cm_valid      (cm_valid),
		.cm_tag        (cm_tag),
		.cm_has_rd     (cm_has_rd),
		.cm_rd         (cm_rd),
		.cm_value      (cm_value),
		.cm_is_store   (cm_is_store),
		.cm_pc         (cm_pc),
		.ooo_event     (ooo_event)
	);

	rs_array #(.N(`RS_ALU_N)) rs_alu (
		.clk            (clk),
		.reset_n        (reset_n),
		.rs_al_valid    (alu_al_valid),
		.rs_al_op       (alu_al_op),
		.rs_al_tag      (alu_al_tag),
		.rs_al_qj_valid (alu_al_qj_valid),
		.rs_al_qj       (alu_al_qj),
		.rs_al_vj       (alu_al_vj),
		.rs_al_qk_valid (alu_al_qk_valid),
		.rs_al_qk       (alu_al_qk),
		.rs_al_vk       (alu_al_vk),
		.rs_al_a        (alu_al_a),
		.rs_full        (rs_full_alu),
		.cdb_valid      (cdb_valid),
		.cdb_tag        (cdb_tag),
		.cdb_value      (cdb_value),
		.iss_valid      (alu_iss_valid),
		.iss_op         (alu_iss_op),
		.iss_tag        (alu_iss_tag),
		.iss_vj         (alu_iss_vj),
		.iss_vk         (alu_iss_vk),
		.iss_a          (alu_iss_a),
		.iss_accept     (alu_iss_valid)
	);

	alu_fu alu (
		.op      (alu_iss_op),
		.vj      (alu_iss_vj),
		.vk      (alu_iss_vk),
		.a       (alu_iss_a),
		.result  (alu_result),
		.is_ctrl (alu_is_ctrl),
		.taken   (alu_taken),
		.target  (alu_target)
	);

	rs_array #(.N(`RS_MUL_N)) rs_mul (
		.clk            (clk),
		.reset_n        (reset_n),
		.rs_al_valid    (mul_al_valid),
		.rs_al_op       (mul_al_op),
		.rs_al_tag      (mul_al_tag),
		.rs_al_qj_valid (mul_al_qj_valid),
		.rs_al_qj       (mul_al_qj),
		.rs_al_vj       (mul_al_vj),
		.rs_al_qk_valid (mul_al_qk_valid),
		.rs_al_qk       (mul_al_qk),
		.rs_al_vk       (mul_al_vk),
		.rs_al_a        (mul_al_a),
		.rs_full        (rs_full_mul),
		.cdb_valid      (cdb_valid),
		.cdb_tag        (cdb_tag),
		.cdb_value      (cdb_value),
		.iss_valid      (mul_iss_valid),
		.iss_op         (mul_iss_op),
		.iss_tag        (mul_iss_tag),
		.iss_vj         (mul_iss_vj),
		.iss_vk         (mul_iss_vk),
		.iss_a          (mul_iss_a),
		.iss_accept     (mul_iss_valid)
	);

	mul_unit mul (
		.clk      (clk),
		.reset_n  (reset_n),
		.start    (mul_iss_valid),
		.funct3   (mul_iss_op[`OP_MD_HI:0]),
		.a        (mul_iss_vj),
		.b        (mul_iss_vk),
		.tag      (mul_iss_tag),
		.done     (cdb_valid[`CDB_MUL]),
		.done_tag (cdb_tag[`CDB_MUL*`ROB_W +: `ROB_W]),
		.result   (cdb_value[`CDB_MUL*`XLEN +: `XLEN])
	);

	rs_array #(.N(`RS_DIV_N)) rs_div (
		.clk            (clk),
		.reset_n        (reset_n),
		.rs_al_valid    (div_al_valid),
		.rs_al_op       (div_al_op),
		.rs_al_tag      (div_al_tag),
		.rs_al_qj_valid (div_al_qj_valid),
		.rs_al_qj       (div_al_qj),
		.rs_al_vj       (div_al_vj),
		.rs_al_qk_valid (div_al_qk_valid),
		.rs_al_qk       (div_al_qk),
		.rs_al_vk       (div_al_vk),
		.rs_al_a        (div_al_a),
		.rs_full        (rs_full_div),
		.cdb_valid      (cdb_valid),
		.cdb_tag        (cdb_tag),
		.cdb_value      (cdb_value),
		.iss_valid      (div_iss_valid),
		.iss_op         (div_iss_op),
		.iss_tag        (div_iss_tag),
		.iss_vj         (div_iss_vj),
		.iss_vk         (div_iss_vk),
		.iss_a          (div_iss_a),
		.iss_accept     (~div_busy)
	);

	div_unit div (
		.clk      (clk),
		.reset_n  (reset_n),
		.start    (div_iss_valid & ~div_busy),
		.funct3   (div_iss_op[`OP_MD_HI:0]),
		.a        (div_iss_vj),
		.b        (div_iss_vk),
		.tag      (div_iss_tag),
		.busy     (div_busy),
		.done     (cdb_valid[`CDB_DIV]),
		.done_tag (cdb_tag[`CDB_DIV*`ROB_W +: `ROB_W]),
		.result   (cdb_value[`CDB_DIV*`XLEN +: `XLEN])
	);

	lsu lsu (
		.clk            (clk),
		.reset_n        (reset_n),
		.lq_al_valid    (lq_al_valid),
		.lq_al_store    (lq_al_store),
		.lq_al_funct3   (lq_al_funct3),
		.lq_al_tag      (lq_al_tag),
		.lq_al_qj_valid (lq_al_qj_valid),
		.lq_al_qj       (lq_al_qj),
		.lq_al_vj       (lq_al_vj),
		.lq_al_qk_valid (lq_al_qk_valid),
		.lq_al_qk       (lq_al_qk),
		.lq_al_vk       (lq_al_vk),
		.lq_al_imm      (lq_al_imm),
		.lq_full        (lq_full),
		.cdb_valid      (cdb_valid),
		.cdb_tag        (cdb_tag),
		.cdb_value      (cdb_value),
		.cdb_lsu_valid  (cdb_valid[`CDB_LSU]),
		.cdb_lsu_tag    (cdb_tag[`CDB_LSU*`ROB_W +: `ROB_W]),
		.cdb_lsu_value  (cdb_value[`CDB_LSU*`XLEN +: `XLEN]),
		.cm_valid       (cm_valid),
		.cm_tag         (cm_tag),
		.cm_is_store    (cm_is_store),
		.dmem_re        (dmem_re),
		.dmem_raddr     (dmem_raddr),
		.dmem_rdata     (dmem_rdata),
		.dmem_we        (dmem_we),
		.dmem_waddr     (dmem_waddr),
		.dmem_wdata     (dmem_wdata),
		.dmem_wstrb     (dmem_wstrb)
	);

	assign cdb_valid[`CDB_ALU]                  = alu_iss_valid;
	assign cdb_tag[`CDB_ALU*`ROB_W +: `ROB_W]   = alu_iss_tag;
	assign cdb_value[`CDB_ALU*`XLEN +: `XLEN]   = alu_result;

	assign br_valid  = alu_iss_valid & alu_is_ctrl;
	assign br_taken  = alu_taken;
	assign br_target = alu_target;

	assign dbg_commit_valid    = cm_valid;
	assign dbg_commit_pc       = cm_pc;
	assign dbg_commit_rd       = cm_rd;
	assign dbg_commit_has_rd   = cm_has_rd;
	assign dbg_commit_value    = cm_value;
	assign dbg_commit_is_store = cm_is_store;
	assign dbg_ooo_event       = ooo_event;
	assign dbg_stall_rob       = stall_rob;
	assign dbg_stall_rs        = stall_rs;
	assign dbg_hold            = hold;
	assign dbg_cdb_valid       = cdb_valid;

endmodule
