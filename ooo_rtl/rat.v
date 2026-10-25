// rat - Register Alias Table tracking speculative register renames for x1-x31.
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
	input       [ROB_W-1:0] cm_tag
);

	reg         [31: 1]     busy;
	reg         [ROB_W-1:0] tag     [31: 1];

	integer                 i;

	assign lk_busy1 = (lk_rs1 != 5'd0) & busy[lk_rs1];
	assign lk_tag1  = (lk_rs1 != 5'd0) ? tag[lk_rs1] : {ROB_W{1'b0}};
	assign lk_busy2 = (lk_rs2 != 5'd0) & busy[lk_rs2];
	assign lk_tag2  = (lk_rs2 != 5'd0) ? tag[lk_rs2] : {ROB_W{1'b0}};

	// Update RAT state: commit clears entry unless overridden by allocate.
	always @(posedge clk or negedge reset_n) begin
		if (!reset_n) begin
			busy <= 31'd0;
			for (i = 1; i < 32; i = i + 1)
				tag[i] <= {ROB_W{1'b0}};
		end else begin
			if (cm_valid && cm_rd != 5'd0 && busy[cm_rd] && tag[cm_rd] == cm_tag)
				busy[cm_rd] <= 1'b0;
			if (al_valid && al_rd != 5'd0) begin
				busy[al_rd] <= 1'b1;
				tag[al_rd]  <= al_tag;
			end
		end
	end

endmodule
