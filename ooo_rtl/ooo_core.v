//  ooo_core - top of the out-of-order core (owner: A, reviewers: B, C)
//  PROJECT_BLUEPRINT.md 6.14, SIGNALS_REFERENCE.md 2.2, decisions D14, D18, D19.
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
	input                       dmem_read_valid,    // 0: a read is outstanding (mem_wait)
	input                       dmem_write_valid,   // 0: write buffer full
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
	output      [`NCDB-1:0]     dbg_cdb_valid,
	// L1 data cache events (perf_counters): one-cycle pulses, stall is a level
	output                      dbg_dc_access,
	output                      dbg_dc_hit,
	output                      dbg_dc_miss,
	output                      dbg_dc_stall,
	// branch prediction (perf_counters): committed conditional branches
	output                      dbg_br_commit,
	output                      dbg_br_mispred
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

	// ---- branch speculation ---------------------------------------------------
	wire                        spec = (`SPEC_EN != 0);
	wire                        fq_pred;
	wire    [31: 0]             fq_target;
	wire                        pred_taken;
	wire    [31: 0]             pred_target;
	wire                        ck_full, ck_take, jal_learn;
	reg                         flush_valid;        // registered: mispredict recovery cycle
	reg     [`ROB_W-1:0]        flush_tag;
	reg     [31: 0]             flush_pc;
	wire    [(1<<`ROB_W)-1:0]   squash;
	wire    [31: 0]             br_res_pc;
	wire                        cm_is_cond, cm_taken, cm_mispred, cm_exc;
	wire                        d_exception;
	wire                        alu_br, alu_mispred, fe_br_valid;
	reg                         cm_exception;

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
		.br_valid       (fe_br_valid),
		.br_taken       (br_taken),
		.br_target      (br_target),
		.flush_valid    (flush_valid),
		.flush_pc       (flush_pc),
		.pred_taken     (pred_taken),
		.pred_target    (pred_target),
		.fq_pop         (fq_pop),
		.fq_valid       (fq_valid),
		.fq_pc          (fq_pc),
		.fq_inst        (fq_inst),
		.fq_pred        (fq_pred),
		.fq_target      (fq_target),
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
		.flush           (flush_valid),
		.pred_taken      (fq_pred),
		.pred_target     (fq_target),
		.ck_full         (ck_full),
		.ck_take         (ck_take),
		.jal_learn       (jal_learn),
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
		.exception       (d_exception),
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
		.cm_tag   (cm_tag),
		.ck_take        (ck_take),
		.ck_tag_in      (rob_al_tag),
		.ck_release     (alu_br & ~alu_mispred),
		.ck_release_tag (alu_iss_tag),
		.restore        (flush_valid),
		.restore_tag    (flush_tag),
		.squash         (squash),
		.ck_full        (ck_full)
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
		.rob_al_cond   (d_is_branch),
		.rob_al_exc    (d_cls == `CLS_NOP),
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
		.cm_is_cond    (cm_is_cond),
		.cm_taken      (cm_taken),
		.cm_mispred    (cm_mispred),
		.cm_exc        (cm_exc),
		.br_res_valid  (alu_br),
		.br_res_tag    (alu_iss_tag),
		.br_res_taken  (alu_taken),
		.br_res_mispred(alu_mispred),
		.br_res_pc     (br_res_pc),
		.flush_valid   (flush_valid),
		.flush_tag     (flush_tag),
		.squash        (squash),
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
		.iss_accept     (alu_iss_valid),
		.squash         (squash)
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
		.iss_accept     (mul_iss_valid),
		.squash         (squash)
	);

	mul_unit mul (
		.clk      (clk),
		.reset_n  (reset_n),
		.start    (mul_iss_valid),
		.funct3   (mul_iss_op[`OP_MD_HI:0]),
		.a        (mul_iss_vj),
		.b        (mul_iss_vk),
		.tag      (mul_iss_tag),
		.squash   (squash),
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
		.iss_accept     (~div_busy),
		.squash         (squash)
	);

	div_unit div (
		.clk      (clk),
		.reset_n  (reset_n),
		.start    (div_iss_valid & ~div_busy),
		.funct3   (div_iss_op[`OP_MD_HI:0]),
		.a        (div_iss_vj),
		.b        (div_iss_vk),
		.tag      (div_iss_tag),
		.squash   (squash),
		.busy     (div_busy),
		.done     (cdb_valid[`CDB_DIV]),
		.done_tag (cdb_tag[`CDB_DIV*`ROB_W +: `ROB_W]),
		.result   (cdb_value[`CDB_DIV*`XLEN +: `XLEN])
	);

	// LSU <-> L1 data cache
	wire                        lsu_re, lsu_we, lsu_stall, lsu_rvalid;
	wire    [31: 0]             lsu_raddr, lsu_rdata, lsu_waddr, lsu_wdata;
	wire    [ 3: 0]             lsu_wstrb;

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
		.squash         (squash),
		.dmem_re        (lsu_re),
		.dmem_raddr     (lsu_raddr),
		.dmem_rdata     (lsu_rdata),
		.dmem_stall     (lsu_stall),
		.dmem_rvalid    (lsu_rvalid),
		.dmem_we        (lsu_we),
		.dmem_waddr     (lsu_waddr),
		.dmem_wdata     (lsu_wdata),
		.dmem_wstrb     (lsu_wstrb)
	);

	// ---- L1 data cache between the LSU and the memory port (DC_EN = 0: none) ----
	// The LSU never reads and writes in the same cycle (both need the queue head,
	// which is either a load or a store), so its two ports merge into one request.
	generate
		if (`DC_EN) begin : g_dcache
			l1_dcache dcache (
				.clk         (clk),
				.reset_n     (reset_n),
				.req_valid   (lsu_re | lsu_we),
				.req_we      (lsu_we),
				.req_addr    (lsu_we ? lsu_waddr : lsu_raddr),
				.req_wdata   (lsu_wdata),
				.req_byte_en (lsu_wstrb),
				.stall       (lsu_stall),
				.resp_ready  (lsu_rvalid),
				.resp_data   (lsu_rdata),
				.mem_re      (dmem_re),
				.mem_raddr   (dmem_raddr),
				.mem_rdata   (dmem_rdata),
				.mem_read_valid  (dmem_read_valid),
				.mem_write_valid (dmem_write_valid),
				.mem_we      (dmem_we),
				.mem_waddr   (dmem_waddr),
				.mem_wdata   (dmem_wdata),
				.mem_wstrb   (dmem_wstrb),
				.ev_access   (dbg_dc_access),
				.ev_hit      (dbg_dc_hit),
				.ev_miss     (dbg_dc_miss),
				.ev_stall    (dbg_dc_stall)
			);
		end else begin : g_no_dcache
			assign dmem_re       = lsu_re;
			assign dmem_raddr    = lsu_raddr;
			assign dmem_we       = lsu_we;
			assign dmem_waddr    = lsu_waddr;
			assign dmem_wdata    = lsu_wdata;
			assign dmem_wstrb    = lsu_wstrb;
			assign lsu_rdata     = dmem_rdata;
			assign lsu_stall     = ~dmem_read_valid | ~dmem_write_valid;
			assign lsu_rvalid    = dmem_read_valid;
			assign dbg_dc_access = 1'b0;
			assign dbg_dc_hit    = 1'b0;
			assign dbg_dc_miss   = 1'b0;
			assign dbg_dc_stall  = 1'b0;
		end
	endgenerate

	assign cdb_valid[`CDB_ALU]                  = alu_iss_valid;
	assign cdb_tag[`CDB_ALU*`ROB_W +: `ROB_W]   = alu_iss_tag;
	// a branch has no destination, so its bus value carries the target to the ROB,
	// from where the committed branch trains the BTB
	assign cdb_value[`CDB_ALU*`XLEN +: `XLEN]   = (spec & alu_iss_op[`OP_BR_BIT]) ? alu_target : alu_result;

	assign br_valid  = alu_iss_valid & alu_is_ctrl;
	assign br_taken  = alu_taken;
	assign br_target = alu_target;

	// ---- mispredict detection and recovery ------------------------------------
	// Conditional branches resolve in the ALU; recovery runs one cycle later from
	// registers (flush_*), so the ALU compare does not drive the whole machine in
	// one cycle. A branch squashed by the recovery running right now is ignored.
	assign  alu_br      = spec & alu_iss_valid & alu_iss_op[`OP_BR_BIT];
	assign  alu_mispred = alu_br & (alu_taken != alu_iss_op[`OP_PRED_BIT]);
	assign  fe_br_valid = spec ? (alu_iss_valid & alu_iss_op[`OP_JALR_BIT]) : br_valid;

	always @(posedge clk or negedge reset_n) begin
		if (!reset_n) begin
			flush_valid <= 1'b0;
			flush_tag   <= {`ROB_W{1'b0}};
			flush_pc    <= 32'd0;
		end else if (alu_mispred && !squash[alu_iss_tag]) begin
			flush_valid <= 1'b1;
			flush_tag   <= alu_iss_tag;
			flush_pc    <= alu_taken ? alu_target : (br_res_pc + 32'd4);
		end else
			flush_valid <= 1'b0;
	end

	// an illegal instruction only counts once it commits (it may be on the wrong path)
	always @(posedge clk or negedge reset_n) begin
		if (!reset_n)                     cm_exception <= 1'b0;
		else if (cm_valid && cm_exc)      cm_exception <= 1'b1;
	end
	assign exception = spec ? cm_exception : d_exception;

	generate
		if (`SPEC_EN != 0) begin : g_bpred
			bpred bp (
				.clk        (clk),
				.reset_n    (reset_n),
				.f_pc       (imem_addr),
				.f_taken    (pred_taken),
				.f_target   (pred_target),
				.up_valid   (cm_valid & cm_is_cond),
				.up_pc      (cm_pc),
				.up_taken   (cm_taken),
				.up_target  (cm_value),
				.jal_valid  (jal_learn),
				.jal_pc     (fq_pc),
				.jal_target (d_br_target)
			);
		end else begin : g_no_bpred
			assign pred_taken  = 1'b0;
			assign pred_target = 32'd0;
		end
	endgenerate

	assign dbg_br_commit  = cm_valid & cm_is_cond;
	assign dbg_br_mispred = cm_valid & cm_is_cond & cm_mispred;

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
