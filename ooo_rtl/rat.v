//  rat - register alias table (owner: A, reviewer: B)
//  PROJECT_BLUEPRINT.md 6.6, SIGNALS_REFERENCE.md 2.7.
//
//  31 entries for x1-x31, each {busy, tag}. x0 is never renamed.
//  Lookups are combinational from the state at the start of the cycle.
//  At the clock edge: commit clears an entry only if it still holds cm_tag;
//  a same-edge allocate on the same register wins (cycle rule 10).
//  ooo_core drives cm_valid = ROB cm_valid & cm_has_rd.
`timescale 1ns/1ps
`include "ooo_defs.vh"

module rat
#(
	parameter ROB_W = `ROB_W
)
(
	input                   clk,
	input                   reset_n,

	// lookup (dispatch)
	input       [ 4: 0]     lk_rs1,
	input       [ 4: 0]     lk_rs2,
	output                  lk_busy1,
	output      [ROB_W-1:0] lk_tag1,
	output                  lk_busy2,
	output      [ROB_W-1:0] lk_tag2,

	// allocate (dispatch)
	input                   al_valid,
	input       [ 4: 0]     al_rd,
	input       [ROB_W-1:0] al_tag,

	// commit (ROB head with has_rd)
	input                   cm_valid,
	input       [ 4: 0]     cm_rd,
	input       [ROB_W-1:0] cm_tag,

	// branch checkpoints: one per unresolved conditional branch
	input                   ck_take,            // branch dispatching with tag al_ck_tag
	input       [ROB_W-1:0] ck_tag_in,
	input                   ck_release,         // branch resolved correctly
	input       [ROB_W-1:0] ck_release_tag,
	input                   restore,            // mispredicted branch: back to its checkpoint
	input       [ROB_W-1:0] restore_tag,
	input       [(1<<ROB_W)-1:0] squash,        // ROB entries being removed
	output                  ck_full
);

	reg         [31: 1]     busy;
	reg         [ROB_W-1:0] tag     [31: 1];

	integer                 i, c;

	localparam              CK_N = `BR_CKPT_N;
	reg         [CK_N-1:0]  ck_valid;
	reg         [ROB_W-1:0] ck_id   [0:CK_N-1];
	reg         [31: 1]     ck_busy [0:CK_N-1];
	reg         [ROB_W-1:0] ck_map  [0:CK_N-1][31:1];

	reg                     ck_free_found, ck_rest_found;
	reg         [$clog2(CK_N+1)-1:0] ck_free, ck_rest;
	always @(*) begin
		ck_free_found = 1'b0; ck_free = 0;
		ck_rest_found = 1'b0; ck_rest = 0;
		for (c = CK_N-1; c >= 0; c = c - 1) begin
			if (!ck_valid[c]) begin ck_free_found = 1'b1; ck_free = c; end
			if (ck_valid[c] && ck_id[c] == restore_tag) begin ck_rest_found = 1'b1; ck_rest = c; end
		end
	end
	assign ck_full = &ck_valid;

	// state after this cycle's commit
	wire                    cm_clr = cm_valid && cm_rd != 5'd0 && busy[cm_rd] && tag[cm_rd] == cm_tag;

	assign lk_busy1 = (lk_rs1 != 5'd0) & busy[lk_rs1];
	assign lk_tag1  = (lk_rs1 != 5'd0) ? tag[lk_rs1] : {ROB_W{1'b0}};
	assign lk_busy2 = (lk_rs2 != 5'd0) & busy[lk_rs2];
	assign lk_tag2  = (lk_rs2 != 5'd0) ? tag[lk_rs2] : {ROB_W{1'b0}};

	// The only block that writes RAT state. Clear first, then allocate, so a
	// same-edge allocate on the same register overrides the clear.
	always @(posedge clk or negedge reset_n) begin
		if (!reset_n) begin
			busy <= 31'd0;
			for (i = 1; i < 32; i = i + 1)
				tag[i] <= {ROB_W{1'b0}};
			ck_valid <= {CK_N{1'b0}};
		end else begin
			if (cm_valid && cm_rd != 5'd0 && busy[cm_rd] && tag[cm_rd] == cm_tag)
				busy[cm_rd] <= 1'b0;
			if (al_valid && al_rd != 5'd0) begin
				busy[al_rd] <= 1'b1;
				tag[al_rd]  <= al_tag;
			end

			// every checkpoint sees every commit, so it is still right when restored
			for (c = 0; c < CK_N; c = c + 1)
				if (cm_valid && cm_rd != 5'd0 && ck_busy[c][cm_rd] && ck_map[c][cm_rd] == cm_tag)
					ck_busy[c][cm_rd] <= 1'b0;

			if (ck_take && ck_free_found) begin
				ck_valid[ck_free] <= 1'b1;
				ck_id[ck_free]    <= ck_tag_in;
				ck_busy[ck_free]  <= busy;
				if (cm_clr) ck_busy[ck_free][cm_rd] <= 1'b0;
				for (i = 1; i < 32; i = i + 1)
					ck_map[ck_free][i] <= tag[i];
			end

			for (c = 0; c < CK_N; c = c + 1)
				if (ck_valid[c] && (squash[ck_id[c]] || (ck_release && ck_id[c] == ck_release_tag)))
					ck_valid[c] <= 1'b0;

			if (restore && ck_rest_found) begin
				busy <= ck_busy[ck_rest];
				if (cm_valid && cm_rd != 5'd0 && ck_busy[ck_rest][cm_rd] && ck_map[ck_rest][cm_rd] == cm_tag)
					busy[cm_rd] <= 1'b0;
				for (i = 1; i < 32; i = i + 1)
					tag[i] <= ck_map[ck_rest][i];
				ck_valid[ck_rest] <= 1'b0;
			end
		end
	end

endmodule
