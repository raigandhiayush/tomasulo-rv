// tb_ooo_core - Self-checking testbench for pipe_ooo / ooo_core.
`timescale 1ns/1ps
`include "ooo_defs.vh"

module tb_ooo_core;

	localparam N_RANDOM  = 60;
	localparam N_INSTR   = 300;
	localparam TIMEOUT   = 40000;
	localparam DBASE     = 32'h400;

	reg                 clk = 1'b0;
	reg                 reset_n = 1'b0;
	always #5 clk = ~clk;

	wire    [31: 0]     imem_addr, imem_data;
	wire                dmem_re, dmem_we;
	wire    [31: 0]     dmem_raddr, dmem_rdata, dmem_waddr, dmem_wdata;
	wire    [ 3: 0]     dmem_wstrb;
	wire                exception;
	wire                c_valid, c_has_rd, c_is_store, ooo_ev, st_rob, st_rs, hold;
	wire    [31: 0]     c_pc, c_value;
	wire    [ 4: 0]     c_rd;
	wire    [`NCDB-1:0] cdb_v;

	pipe_ooo DUT (
		.clk                 (clk),
		.reset               (reset_n),
		.stall               (1'b0),
		.exception           (exception),
		.pc_out              (),
		.inst_mem_is_valid   (1'b1),
		.inst_mem_read_data  (imem_data),
		.dmem_read_data_temp (dmem_rdata),
		.dmem_write_valid    (1'b1),
		.dmem_read_valid     (1'b1),
		.inst_mem_address    (imem_addr),
		.dmem_read_ready     (dmem_re),
		.dmem_read_address   (dmem_raddr),
		.dmem_write_ready    (dmem_we),
		.dmem_write_address  (dmem_waddr),
		.dmem_write_data     (dmem_wdata),
		.dmem_write_byte     (dmem_wstrb),
		.dbg_commit_valid    (c_valid),
		.dbg_commit_pc       (c_pc),
		.dbg_commit_rd       (c_rd),
		.dbg_commit_has_rd   (c_has_rd),
		.dbg_commit_value    (c_value),
		.dbg_commit_is_store (c_is_store),
		.dbg_ooo_event       (ooo_ev),
		.dbg_stall_rob       (st_rob),
		.dbg_stall_rs        (st_rs),
		.dbg_hold            (hold),
		.dbg_cdb_valid       (cdb_v)
	);

	instr_mem IMEM (.clk(clk), .pc(imem_addr), .instr(imem_data));
	data_mem  DMEM (.clk(clk), .re(dmem_re), .raddr(dmem_raddr), .rdata(dmem_rdata),
	                .we(dmem_we), .waddr(dmem_waddr), .wdata(dmem_wdata), .wstrb(dmem_wstrb));

	localparam [6:0] OP_LUI = 7'b0110111, OP_JAL = 7'b1101111, OP_JALR = 7'b1100111,
	                 OP_BR  = 7'b1100011, OP_LD  = 7'b0000011, OP_ST   = 7'b0100011,
	                 OP_ALI = 7'b0010011, OP_ALR = 7'b0110011;

	function [31:0] enc_r(input [6:0] f7, input [4:0] r2, input [4:0] r1, input [2:0] f3, input [4:0] d);
		enc_r = {f7, r2, r1, f3, d, OP_ALR};
	endfunction
	function [31:0] enc_i(input [11:0] im, input [4:0] r1, input [2:0] f3, input [4:0] d, input [6:0] op);
		enc_i = {im, r1, f3, d, op};
	endfunction
	function [31:0] enc_s(input [11:0] im, input [4:0] r2, input [4:0] r1, input [2:0] f3);
		enc_s = {im[11:5], r2, r1, f3, im[4:0], OP_ST};
	endfunction
	function [31:0] enc_b(input [12:0] im, input [4:0] r2, input [4:0] r1, input [2:0] f3);
		enc_b = {im[12], im[10:5], r2, r1, f3, im[4:1], im[11], OP_BR};
	endfunction
	function [31:0] enc_u(input [19:0] im, input [4:0] d);
		enc_u = {im, d, OP_LUI};
	endfunction
	function [31:0] enc_j(input [20:0] im, input [4:0] d);
		enc_j = {im[20], im[10:1], im[11], im[19:12], d, OP_JAL};
	endfunction

	reg     [31: 0]     prog   [0:1023];
	reg     [31: 0]     dinit  [0:1023];
	reg                 is_tgt [0:1023];
	integer             n_prog;
	integer             seed;

	task emit(input [31:0] w);
		begin
			prog[n_prog] = w;
			n_prog = n_prog + 1;
		end
	endtask

	function [31:0] iss_alu(input [2:0] f3, input alt, input [31:0] a, input [31:0] b);
		reg signed [31:0] sa, sra;
		begin
		sa  = a;
		sra = sa >>> b[4:0];
		case (f3)
			3'b000: iss_alu = alt ? a - b : a + b;
			3'b001: iss_alu = a << b[4:0];
			3'b010: iss_alu = ($signed(a) < $signed(b)) ? 32'd1 : 32'd0;
			3'b011: iss_alu = (a < b) ? 32'd1 : 32'd0;
			3'b100: iss_alu = a ^ b;
			3'b101: iss_alu = alt ? sra : (a >> b[4:0]);
			3'b110: iss_alu = a | b;
			default: iss_alu = a & b;
		endcase
		end
	endfunction

	function [31:0] iss_md(input [2:0] f3, input [31:0] a, input [31:0] b);
		reg [63:0] p;
		reg signed [31:0] sa, sb, sq, sr;
		begin
			sa = a;
			sb = b;
			sq = (b == 0) ? 0 : sa / sb;
			sr = (b == 0) ? 0 : sa % sb;
			case (f3)
				3'b000: begin p = a * b;                                 iss_md = p[31:0];  end
				3'b001: begin p = {{32{a[31]}}, a} * {{32{b[31]}}, b};   iss_md = p[63:32]; end
				3'b010: begin p = {{32{a[31]}}, a} * {32'd0, b};         iss_md = p[63:32]; end
				3'b011: begin p = {32'd0, a} * {32'd0, b};               iss_md = p[63:32]; end
				3'b100: iss_md = (b == 0) ? 32'hFFFF_FFFF :
				                 (a == 32'h8000_0000 && b == 32'hFFFF_FFFF) ? a :
				                 sq;
				3'b101: iss_md = (b == 0) ? 32'hFFFF_FFFF : a / b;
				3'b110: iss_md = (b == 0) ? a :
				                 (a == 32'h8000_0000 && b == 32'hFFFF_FFFF) ? 32'd0 :
				                 sr;
				default: iss_md = (b == 0) ? a : a % b;
			endcase
		end
	endfunction

	reg     [31: 0]     x      [0:31];
	reg     [31: 0]     rmem   [0:1023];
	reg     [31: 0]     r_pc;
	reg                 e_has_rd, e_store, e_illegal;
	reg     [ 4: 0]     e_rd;
	reg     [31: 0]     e_value, e_addr, e_wdata;
	reg     [ 3: 0]     e_wstrb;

	task iss_step;
		reg [31:0] in, a, b, im_i, im_s, im_b, im_j, addr, w, nx;
		reg [6:0]  op;
		reg [2:0]  f3;
		reg [6:0]  f7;
		reg [4:0]  d;
		reg [7:0]  by;
		reg [15:0] hw;
		reg        tk;
		begin
			in   = prog[r_pc[11:2]];
			op   = in[6:0];
			f3   = in[14:12];
			f7   = in[31:25];
			d    = in[11:7];
			a    = x[in[19:15]];
			b    = x[in[24:20]];
			im_i = {{20{in[31]}}, in[31:20]};
			im_s = {{20{in[31]}}, in[31:25], in[11:7]};
			im_b = {{19{in[31]}}, in[31], in[7], in[30:25], in[11:8], 1'b0};
			im_j = {{11{in[31]}}, in[31], in[19:12], in[20], in[30:21], 1'b0};
			e_has_rd = 1'b0; e_rd = 5'd0; e_value = 32'd0; e_store = 1'b0; e_illegal = 1'b0;
			e_addr = 32'd0; e_wdata = 32'd0; e_wstrb = 4'd0;
			nx = r_pc + 4;
			case (op)
				OP_LUI: begin e_has_rd = 1'b1; e_value = {in[31:12], 12'd0}; end
				OP_JAL: begin e_has_rd = 1'b1; e_value = r_pc + 4; nx = r_pc + im_j; end
				OP_JALR: begin e_has_rd = 1'b1; e_value = r_pc + 4; nx = (a + im_i) & ~32'd1; end
				OP_BR: begin
					case (f3)
						3'b000: tk = (a == b);
						3'b001: tk = (a != b);
						3'b100: tk = ($signed(a) <  $signed(b));
						3'b101: tk = ($signed(a) >= $signed(b));
						3'b110: tk = (a <  b);
						default: tk = (a >= b);
					endcase
					if (tk) nx = r_pc + im_b;
				end
				OP_LD: begin
					addr = a + im_i;
					w    = rmem[addr[11:2]];
					by   = w >> {addr[1:0], 3'b000};
					hw   = addr[1] ? w[31:16] : w[15:0];
					e_has_rd = 1'b1;
					case (f3)
						3'b000: e_value = {{24{by[7]}}, by};
						3'b001: e_value = {{16{hw[15]}}, hw};
						3'b100: e_value = {24'd0, by};
						3'b101: e_value = {16'd0, hw};
						default: e_value = w;
					endcase
				end
				OP_ST: begin
					addr = a + im_s;
					e_store = 1'b1;
					e_addr  = addr;
					case (f3)
						3'b000: begin e_wdata = {4{b[7:0]}};  e_wstrb = 4'b0001 << addr[1:0]; end
						3'b001: begin e_wdata = {2{b[15:0]}}; e_wstrb = addr[1] ? 4'b1100 : 4'b0011; end
						default: begin e_wdata = b; e_wstrb = 4'b1111; end
					endcase
					w = rmem[addr[11:2]];
					if (e_wstrb[0]) w[ 7: 0] = e_wdata[ 7: 0];
					if (e_wstrb[1]) w[15: 8] = e_wdata[15: 8];
					if (e_wstrb[2]) w[23:16] = e_wdata[23:16];
					if (e_wstrb[3]) w[31:24] = e_wdata[31:24];
					rmem[addr[11:2]] = w;
				end
				OP_ALI: begin e_has_rd = 1'b1; e_value = iss_alu(f3, (f3 == 3'b101) & in[30], a, im_i); end
				OP_ALR: begin
					e_has_rd = 1'b1;
					if (f7 == 7'b0000001) e_value = iss_md(f3, a, b);
					else                  e_value = iss_alu(f3, in[30], a, b);
				end
				default: e_illegal = 1'b1;
			endcase
			if (d == 5'd0) e_has_rd = 1'b0;
			if (e_has_rd) begin e_rd = d; x[d] = e_value; end
			r_pc = nx;
		end
	endtask

	integer n_checks = 0, n_fail = 0, n_commit = 0, n_ooo = 0, n_multi = 0, n_srob = 0, n_srs = 0;
	integer cyc, end_pc, done_run, i, j;

	task check(input ok, input [8*48-1:0] what, input [31:0] got, input [31:0] exp);
		begin
			n_checks = n_checks + 1;
			if (!ok) begin
				n_fail = n_fail + 1;
				if (n_fail <= 20)
					$display("TEST_FAIL ooo_core seed %0d cycle %0d pc %h: %0s got %h expected %h",
					         seed, cyc, r_pc, what, got, exp);
			end
		end
	endtask

	always @(posedge clk) if (reset_n && !done_run) begin
		cyc = cyc + 1;
		if (ooo_ev) n_ooo = n_ooo + 1;
		if (cdb_v[0] + cdb_v[1] + cdb_v[2] + cdb_v[3] >= 2) n_multi = n_multi + 1;
		if (st_rob) n_srob = n_srob + 1;
		if (st_rs)  n_srs  = n_srs + 1;
		if (c_valid) begin
			n_commit = n_commit + 1;
			check(c_pc === r_pc, "commit pc", c_pc, r_pc);
			if (c_pc === end_pc) done_run = 1;
			iss_step;
			check(c_has_rd === e_has_rd, "commit has_rd", c_has_rd, e_has_rd);
			if (e_has_rd) begin
				check(c_rd === e_rd, "commit rd", c_rd, e_rd);
				check(c_value === e_value, "commit value", c_value, e_value);
			end
			check(c_is_store === e_store, "commit is_store", c_is_store, e_store);
			check(dmem_we === e_store, "dmem write enable", dmem_we, e_store);
			if (e_store) begin
				check(dmem_waddr[11:2] === e_addr[11:2], "store word address", dmem_waddr, e_addr);
				check(dmem_wstrb === e_wstrb, "store byte lanes", dmem_wstrb, e_wstrb);
				for (j = 0; j < 4; j = j + 1)
					if (e_wstrb[j])
						check(dmem_wdata[8*j +: 8] === e_wdata[8*j +: 8], "store data byte", dmem_wdata, e_wdata);
			end
		end else
			check(dmem_we === 1'b0, "dmem write without store commit", dmem_we, 0);
	end

	task run(input exp_exception);
		begin
			reset_n = 1'b0;
			#1;
			for (i = 0; i < 1024; i = i + 1) begin
				IMEM.imem[i] = (i < n_prog) ? prog[i] : 32'h0000_0013;
				DMEM.dmem[i] = dinit[i];
				rmem[i]      = dinit[i];
			end
			for (i = 0; i < 32; i = i + 1) x[i] = 32'd0;
			r_pc     = 32'd0;
			end_pc   = (n_prog - 1) * 4;
			cyc      = 0;
			done_run = 0;
			repeat (3) @(negedge clk);
			reset_n = 1'b1;
			while (!done_run && cyc < TIMEOUT) @(negedge clk);
			check(done_run == 1, "program reached its end (timeout)", cyc, TIMEOUT);
			for (i = 1; i < 32; i = i + 1)
				check(DUT.core.regfile.regs[i] === x[i], "final register", DUT.core.regfile.regs[i], x[i]);
			check(exception === exp_exception, "exception flag", exception, exp_exception);
			done_run = 1;
		end
	endtask

	task gen_directed;
		begin
			n_prog = 0;
			emit(enc_u(20'h80000, 5'd1));
			emit(enc_i(12'hFFF, 5'd0, 3'b000, 5'd2, OP_ALI));
			emit(enc_r(7'b0000001, 5'd2, 5'd1, 3'b100, 5'd3));
			emit(enc_r(7'b0000001, 5'd2, 5'd1, 3'b110, 5'd4));
			emit(enc_r(7'b0000001, 5'd0, 5'd1, 3'b101, 5'd5));
			emit(enc_r(7'b0000001, 5'd0, 5'd1, 3'b110, 5'd6));
			emit(enc_r(7'b0000001, 5'd0, 5'd1, 3'b100, 5'd7));
			emit(enc_r(7'b0000001, 5'd1, 5'd1, 3'b001, 5'd8));
			emit(enc_r(7'b0000001, 5'd1, 5'd2, 3'b010, 5'd9));
			emit(enc_r(7'b0000001, 5'd2, 5'd2, 3'b011, 5'd10));
			emit(enc_r(7'b0000001, 5'd2, 5'd1, 3'b000, 5'd11));
			emit(enc_r(7'b0000000, 5'd3, 5'd1, 3'b000, 5'd12));
			emit(enc_r(7'b0000000, 5'd4, 5'd12, 3'b000, 5'd13));
			emit(enc_r(7'b0100000, 5'd13, 5'd12, 3'b101, 5'd14));
			emit(enc_i(12'h400, 5'd0, 3'b000, 5'd31, OP_ALI));
			emit(enc_s(12'd0, 5'd1, 5'd31, 3'b010));
			emit(enc_s(12'd5, 5'd2, 5'd31, 3'b000));
			emit(enc_s(12'd6, 5'd13, 5'd31, 3'b001));
			emit(enc_i(12'd0, 5'd31, 3'b010, 5'd15, OP_LD));
			emit(enc_i(12'd3, 5'd31, 3'b000, 5'd16, OP_LD));
			emit(enc_i(12'd3, 5'd31, 3'b100, 5'd17, OP_LD));
			emit(enc_i(12'd2, 5'd31, 3'b001, 5'd18, OP_LD));
			emit(enc_i(12'd2, 5'd31, 3'b101, 5'd19, OP_LD));
			emit(enc_i(12'd4, 5'd31, 3'b010, 5'd20, OP_LD));
			emit(enc_r(7'b0000000, 5'd20, 5'd15, 3'b000, 5'd21));
			emit(enc_b(13'd8, 5'd2, 5'd1, 3'b110));
			emit(enc_i(12'd1, 5'd0, 3'b000, 5'd22, OP_ALI));
			emit(enc_b(13'd8, 5'd2, 5'd1, 3'b100));
			emit(enc_i(12'd2, 5'd0, 3'b000, 5'd22, OP_ALI));
			emit(enc_j(21'd8, 5'd23));
			emit(enc_i(12'd3, 5'd0, 3'b000, 5'd22, OP_ALI));
			emit(enc_i((n_prog + 3) * 4 + 1, 5'd0, 3'b000, 5'd24, OP_ALI));
			emit(enc_i(12'd0, 5'd24, 3'b000, 5'd25, OP_JALR));
			emit(enc_i(12'd4, 5'd0, 3'b000, 5'd22, OP_ALI));
			emit(enc_r(7'b0000001, 5'd25, 5'd25, 3'b000, 5'd26));
			emit(enc_r(7'b0000001, 5'd26, 5'd26, 3'b000, 5'd26));
			emit(enc_r(7'b0000001, 5'd26, 5'd25, 3'b100, 5'd27));
			emit(enc_r(7'b0000000, 5'd27, 5'd26, 3'b000, 5'd28));
			emit(enc_r(7'b0000000, 5'd28, 5'd27, 3'b000, 5'd29));
			emit(32'h0000_0073);
			emit(32'hFFFF_FFFF);
			emit(enc_i(12'd7, 5'd0, 3'b000, 5'd30, OP_ALI));
			emit(enc_j(21'd0, 5'd0));
		end
	endtask

	task gen_random;
		integer k, r, t, sz, rd, r1, r2, f3, tg;
		reg [11:0] off;
		begin
			n_prog = 0;
			for (k = 0; k < 1024; k = k + 1) is_tgt[k] = 1'b0;
			emit(enc_i(12'h400, 5'd0, 3'b000, 5'd31, OP_ALI));
			emit(enc_i(12'h400, 5'd0, 3'b000, 5'd9, OP_ALI));
			for (k = 1; k <= 8; k = k + 1)
				emit(enc_i($random(seed), 5'd0, 3'b000, k, OP_ALI));
			emit(enc_u($random(seed), 5'd8));
			while (n_prog < N_INSTR) begin
				r  = {$random(seed)} % 100;
				rd = 1 + {$random(seed)} % 8;
				r1 = {$random(seed)} % 9;
				r2 = {$random(seed)} % 9;
				f3 = {$random(seed)} % 8;
				if (r < 22)
					emit(enc_r(((f3 == 0 || f3 == 5) && $random(seed) % 2) ? 7'b0100000 : 7'b0000000, r2, r1, f3, rd));
				else if (r < 38) begin
					off = $random(seed);
					if (f3 == 1)      off[11:5] = 7'b0000000;
					else if (f3 == 5) off[11:5] = ($random(seed) % 2) ? 7'b0100000 : 7'b0000000;
					emit(enc_i(off, r1, f3, rd, OP_ALI));
				end
				else if (r < 41)
					emit(enc_u($random(seed), rd));
				else if (r < 51)
					emit(enc_r(7'b0000001, r2, r1, f3 % 4, rd));
				else if (r < 55)
					emit(enc_r(7'b0000001, r2, r1, 4 + f3 % 4, rd));
				else if (r < 58)
					emit(enc_i({$random(seed)} % 60 * 4, 5'd31, 3'b000, 5'd9, OP_ALI));
				else if (r < 70) begin
					sz  = {$random(seed)} % 5;
					f3  = (sz == 0) ? 0 : (sz == 1) ? 1 : (sz == 2) ? 2 : (sz == 3) ? 4 : 5;
					off = (sz == 2) ? {$random(seed)} % 4 * 4 :
					      (sz == 1 || sz == 4) ? {$random(seed)} % 8 * 2 : {$random(seed)} % 16;
					emit(enc_i(off, ($random(seed) % 2) ? 5'd9 : 5'd31, f3, rd, OP_LD));
				end
				else if (r < 80) begin
					sz  = {$random(seed)} % 3;
					off = (sz == 2) ? {$random(seed)} % 4 * 4 :
					      (sz == 1) ? {$random(seed)} % 8 * 2 : {$random(seed)} % 16;
					emit(enc_s(off, r2, ($random(seed) % 2) ? 5'd9 : 5'd31, sz));
				end
				else if (r < 90) begin
					t = 1 + {$random(seed)} % 4;
					if (n_prog + t > N_INSTR) t = N_INSTR - n_prog;
					if (f3 == 2 || f3 == 3) f3 = 0;
					is_tgt[n_prog + t] = 1'b1;
					emit(enc_b(t * 4, r2, r1, f3));
				end
				else if (r < 94) begin
					t = 1 + {$random(seed)} % 4;
					if (n_prog + t > N_INSTR) t = N_INSTR - n_prog;
					is_tgt[n_prog + t] = 1'b1;
					emit(enc_j(t * 4, ($random(seed) % 2) ? rd : 5'd0));
				end
				else if (!is_tgt[n_prog + 1] && n_prog + 2 < N_INSTR) begin
					t  = 2 + {$random(seed)} % 4;
					if (n_prog + t > N_INSTR) t = N_INSTR - n_prog;
					tg = (n_prog + t) * 4;
					is_tgt[n_prog + t] = 1'b1;
					emit(enc_i(tg | ({$random(seed)} % 2), 5'd0, 3'b000, 5'd10, OP_ALI));
					emit(enc_i(12'd0, 5'd10, 3'b000, ($random(seed) % 2) ? rd : 5'd0, OP_JALR));
				end
				else
					emit(enc_r(7'b0000000, r2, r1, 3'b000, rd));
			end
			emit(enc_j(21'd0, 5'd0));
		end
	endtask

	integer n_test;

	initial begin
		done_run = 1;
		seed = 1;
		for (i = 0; i < 1024; i = i + 1) dinit[i] = $random(seed);
		gen_directed;
		run(1'b1);
		$display("directed: %0d commits, %0d checks, %0d failures", n_commit, n_checks, n_fail);
		for (n_test = 1; n_test <= N_RANDOM; n_test = n_test + 1) begin
			seed = 1000 + n_test;
			for (i = 0; i < 1024; i = i + 1) dinit[i] = $random(seed);
			gen_random;
			run(1'b0);
		end
		$display("random: %0d programs of %0d instructions", N_RANDOM, N_INSTR);
		$display("totals: %0d commits, %0d ooo_event cycles, %0d cycles with >=2 buses, %0d rob-full stalls, %0d rs-full stalls",
		         n_commit, n_ooo, n_multi, n_srob, n_srs);
		if (n_ooo == 0)   begin n_fail = n_fail + 1; $display("TEST_FAIL ooo_core no out-of-order completion seen"); end
		if (n_multi == 0) begin n_fail = n_fail + 1; $display("TEST_FAIL ooo_core never two buses in one cycle"); end
		if (n_fail == 0) $display("TEST_PASS ooo_core %0d", n_checks);
		else             $display("TEST_FAIL ooo_core %0d of %0d checks failed", n_fail, n_checks);
		$finish;
	end

endmodule
