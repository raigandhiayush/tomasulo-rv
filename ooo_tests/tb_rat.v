// tb_rat - Self-checking testbench for the Register Alias Table.
`timescale 1ns/1ps
`include "ooo_defs.vh"

module tb_rat;

	localparam ROB_W = `ROB_W;
	localparam N_RANDOM = 5000;

	reg                 clk;
	reg                 reset_n;
	reg     [ 4: 0]     lk_rs1, lk_rs2;
	wire                lk_busy1, lk_busy2;
	wire    [ROB_W-1:0] lk_tag1, lk_tag2;
	reg                 al_valid;
	reg     [ 4: 0]     al_rd;
	reg     [ROB_W-1:0] al_tag;
	reg                 cm_valid;
	reg     [ 4: 0]     cm_rd;
	reg     [ROB_W-1:0] cm_tag;

	rat #(.ROB_W(ROB_W)) DUT (
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
		.cm_valid (cm_valid),
		.cm_rd    (cm_rd),
		.cm_tag   (cm_tag)
	);

	initial clk = 1'b0;
	always #5 clk = ~clk;

	integer cycle;
	initial cycle = 0;
	always @(posedge clk) cycle = cycle + 1;

	integer n_vectors;
	integer n_fail;

	// Testbench model of the RAT
	reg                 m_busy  [0:31];
	reg     [ROB_W-1:0] m_tag   [0:31];

	integer i, r;

	task model_reset;
		begin
			for (i = 0; i < 32; i = i + 1) begin
				m_busy[i] = 1'b0;
				m_tag[i]  = {ROB_W{1'b0}};
			end
		end
	endtask

	// Apply the same edge update the RAT spec defines (rule 10).
	task model_edge;
		begin
			if (cm_valid && cm_rd != 0 && m_busy[cm_rd] && m_tag[cm_rd] == cm_tag)
				m_busy[cm_rd] = 1'b0;
			if (al_valid && al_rd != 0) begin
				m_busy[al_rd] = 1'b1;
				m_tag[al_rd]  = al_tag;
			end
		end
	endtask

	task idle_inputs;
		begin
			al_valid = 1'b0; al_rd = 5'd0; al_tag = {ROB_W{1'b0}};
			cm_valid = 1'b0; cm_rd = 5'd0; cm_tag = {ROB_W{1'b0}};
		end
	endtask

	// Inputs change on the falling edge; one rising edge applies them.
	task step;
		begin
			@(posedge clk);
			model_edge;
			@(negedge clk);
			idle_inputs;
		end
	endtask

	task fail;
		input [8*48-1:0] what;
		input [31:0]     expected;
		input [31:0]     actual;
		begin
			n_fail = n_fail + 1;
			$display("TEST_FAIL rat cycle=%0d %0s expected=%0h actual=%0h",
			         cycle, what, expected, actual);
		end
	endtask

	// Look up register rs on both ports and compare with expected values.
	task check_reg;
		input [8*48-1:0] what;
		input [4:0]      rs;
		input            exp_busy;
		input [ROB_W-1:0] exp_tag;
		begin
			lk_rs1 = rs;
			lk_rs2 = rs;
			#1;
			n_vectors = n_vectors + 1;
			if (lk_busy1 !== exp_busy) fail({what, " busy1"}, exp_busy, lk_busy1);
			if (lk_busy2 !== exp_busy) fail({what, " busy2"}, exp_busy, lk_busy2);
			if (exp_busy && lk_tag1 !== exp_tag) fail({what, " tag1"}, exp_tag, lk_tag1);
			if (exp_busy && lk_tag2 !== exp_tag) fail({what, " tag2"}, exp_tag, lk_tag2);
		end
	endtask

	// Compare every register on both ports against the model.
	task check_all_vs_model;
		input [8*48-1:0] what;
		begin
			for (r = 0; r < 32; r = r + 1) begin
				lk_rs1 = r[4:0];
				lk_rs2 = 5'd31 - r[4:0];
				#1;
				n_vectors = n_vectors + 1;
				if (lk_busy1 !== m_busy[r])
					fail({what, " busy1"}, {r[15:0], 15'd0, m_busy[r]}, {r[15:0], 15'd0, lk_busy1});
				if (m_busy[r] && lk_tag1 !== m_tag[r])
					fail({what, " tag1"}, {r[15:0], 13'd0, m_tag[r]}, {r[15:0], 13'd0, lk_tag1});
				if (lk_busy2 !== m_busy[31 - r])
					fail({what, " busy2"}, m_busy[31 - r], lk_busy2);
				if (m_busy[31 - r] && lk_tag2 !== m_tag[31 - r])
					fail({what, " tag2"}, m_tag[31 - r], lk_tag2);
			end
		end
	endtask

	task do_reset;
		begin
			reset_n = 1'b0;
			model_reset;
			@(negedge clk);
			@(negedge clk);
			reset_n = 1'b1;
		end
	endtask

	initial begin
		n_vectors = 0;
		n_fail    = 0;
		lk_rs1    = 5'd0;
		lk_rs2    = 5'd0;
		idle_inputs;
		reset_n   = 1'b1;
		model_reset;

		// 1. Reset: every entry not busy; x0 never busy.
		do_reset;
		check_all_vs_model("reset");

		// 2. Allocate rd=5, tag 3: busy, tag 3 on both ports.
		al_valid = 1'b1; al_rd = 5'd5; al_tag = 3;
		step;
		check_reg("allocate x5", 5'd5, 1'b1, 3);

		// 3. Matching commit rd=5, tag 3: entry clears.
		cm_valid = 1'b1; cm_rd = 5'd5; cm_tag = 3;
		step;
		check_reg("matching commit x5", 5'd5, 1'b0, 0);

		// 4. Stale commit: RAT[5] = tag 6; commit rd=5 tag 3 -> stays tag 6.
		al_valid = 1'b1; al_rd = 5'd5; al_tag = 6;
		step;
		cm_valid = 1'b1; cm_rd = 5'd5; cm_tag = 3;
		step;
		check_reg("stale commit x5", 5'd5, 1'b1, 6);
		cm_valid = 1'b1; cm_rd = 5'd5; cm_tag = 6;
		step;
		check_reg("stale then matching commit x5", 5'd5, 1'b0, 0);

		// 5. Two writers (WAW, scenario A x5): tag 3 then tag 6; commit tag 3.
		al_valid = 1'b1; al_rd = 5'd5; al_tag = 3;
		step;
		al_valid = 1'b1; al_rd = 5'd5; al_tag = 6;
		step;
		check_reg("WAW younger writer", 5'd5, 1'b1, 6);
		cm_valid = 1'b1; cm_rd = 5'd5; cm_tag = 3;
		step;
		check_reg("WAW older commit keeps younger", 5'd5, 1'b1, 6);
		cm_valid = 1'b1; cm_rd = 5'd5; cm_tag = 6;
		step;
		check_reg("WAW younger commit", 5'd5, 1'b0, 0);

		// 6. Same-edge collision: RAT[5] = tag 3; commit tag 3 and allocate
		//    rd=5/tag 6 on the same edge -> busy with tag 6.
		al_valid = 1'b1; al_rd = 5'd5; al_tag = 3;
		step;
		cm_valid = 1'b1; cm_rd = 5'd5; cm_tag = 3;
		al_valid = 1'b1; al_rd = 5'd5; al_tag = 6;
		step;
		check_reg("same-edge allocate wins", 5'd5, 1'b1, 6);
		//    Same edge, different registers: both take effect.
		al_valid = 1'b1; al_rd = 5'd7; al_tag = 2;
		step;
		cm_valid = 1'b1; cm_rd = 5'd7; cm_tag = 2;
		al_valid = 1'b1; al_rd = 5'd9; al_tag = 4;
		step;
		check_reg("same-edge other reg cleared", 5'd7, 1'b0, 0);
		check_reg("same-edge other reg allocated", 5'd9, 1'b1, 4);
		//    Same edge, re-allocate with the same tag value (tag reuse).
		cm_valid = 1'b1; cm_rd = 5'd9; cm_tag = 4;
		al_valid = 1'b1; al_rd = 5'd9; al_tag = 4;
		step;
		check_reg("same-edge same tag stays busy", 5'd9, 1'b1, 4);

		// 7. x0: allocate and commit rd=0 change nothing; x0 never busy.
		al_valid = 1'b1; al_rd = 5'd0; al_tag = 5;
		step;
		check_reg("x0 allocate", 5'd0, 1'b0, 0);
		cm_valid = 1'b1; cm_rd = 5'd0; cm_tag = 5;
		step;
		check_reg("x0 commit", 5'd0, 1'b0, 0);
		check_all_vs_model("after x0");

		// 8. Non-register commit: cm_valid low (has_rd = 0) with a matching
		//    rd/tag leaves the entry busy.
		al_valid = 1'b1; al_rd = 5'd12; al_tag = 1;
		step;
		cm_valid = 1'b0; cm_rd = 5'd12; cm_tag = 1;
		step;
		check_reg("cm_valid low no clear", 5'd12, 1'b1, 1);
		//    Commit to a register that is not busy: no change.
		cm_valid = 1'b1; cm_rd = 5'd13; cm_tag = 1;
		step;
		check_reg("commit idle reg", 5'd13, 1'b0, 0);

		// 9. Asynchronous reset: busy bits clear without a clock edge.
		al_valid = 1'b1; al_rd = 5'd31; al_tag = 7;
		step;
		check_reg("before async reset", 5'd31, 1'b1, 7);
		#2;
		reset_n = 1'b0;
		model_reset;
		#1;
		check_all_vs_model("async reset");
		@(negedge clk);
		reset_n = 1'b1;

		// 10. Random allocate/commit traffic against the model.
		for (i = 0; i < N_RANDOM; i = i + 1) begin
			al_valid = $random;
			al_rd    = $random;
			al_tag   = $random;
			cm_valid = $random;
			// Commit mostly the current mapping so clears are exercised.
			cm_rd    = (($random & 3) == 0) ? $random : al_rd;
			cm_tag   = (($random & 1) == 0) ? m_tag[cm_rd] : $random;
			// Occasionally collide allocate and commit on the same register.
			if (($random & 7) == 0) begin
				cm_valid = 1'b1;
				cm_rd    = al_rd;
				cm_tag   = m_tag[al_rd];
			end
			step;
			lk_rs1 = $random;
			lk_rs2 = $random;
			#1;
			n_vectors = n_vectors + 1;
			if (lk_busy1 !== m_busy[lk_rs1]) fail("random busy1", m_busy[lk_rs1], lk_busy1);
			if (m_busy[lk_rs1] && lk_tag1 !== m_tag[lk_rs1]) fail("random tag1", m_tag[lk_rs1], lk_tag1);
			if (lk_busy2 !== m_busy[lk_rs2]) fail("random busy2", m_busy[lk_rs2], lk_busy2);
			if (m_busy[lk_rs2] && lk_tag2 !== m_tag[lk_rs2]) fail("random tag2", m_tag[lk_rs2], lk_tag2);
		end
		check_all_vs_model("after random");

		if (n_fail == 0)
			$display("TEST_PASS rat %0d", n_vectors);
		else
			$display("TEST_FAIL rat %0d failures out of %0d vectors", n_fail, n_vectors);
		$finish;
	end

endmodule
