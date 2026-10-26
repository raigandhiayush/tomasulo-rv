// top_fpga_ooo - Nexys A7 FPGA top module integrating processor core, memory, and MMIO.
`timescale 1ns/1ps
`include "ooo_defs.vh"

module top_fpga_ooo
#(
	parameter                   REFRESH_W = 17      // 50 MHz / 2^17 = 381 Hz per digit
)
(
	input                       clk,                // 100 MHz board clock
	input                       reset,              // active low
	input       [15: 0]         sw,
	output      [15: 0]         led,
	output      [ 7: 0]         seg,                // {DP, CG, CF, CE, CD, CC, CB, CA}, active low
	output      [ 7: 0]         an                  // active low
);

	localparam [31: 0] MMIO_RESULT = 32'h1000_0000;
	localparam [31: 0] MMIO_DONE   = 32'h1000_0004;
	localparam [31: 0] MMIO_SW     = 32'h1000_0008;

	// Clock generation
	wire                        core_clk;
	wire                        locked;

// `ifdef TOMA_SIM
// 	assign core_clk = clk;
// 	assign locked   = 1'b1;
// `else
// 	wire                        clk_fb, clk_fb_buf, clk_50;

// 	MMCME2_BASE #(
// 		.CLKIN1_PERIOD      (10.0),             // 100 MHz in
// 		.DIVCLK_DIVIDE      (1),
// 		.CLKFBOUT_MULT_F    (10.0),             // VCO 1000 MHz
// 		.CLKOUT0_DIVIDE_F   (20.0)              // 50 MHz out
// 	) u_mmcm (
// 		.CLKIN1             (clk),
// 		.CLKFBIN            (clk_fb_buf),
// 		.CLKFBOUT           (clk_fb),
// 		.CLKOUT0            (clk_50),
// 		.LOCKED             (locked),
// 		.PWRDWN             (1'b0),
// 		.RST                (1'b0)
// 	);
// 	BUFG u_bufg_fb  (.I(clk_fb), .O(clk_fb_buf));
// 	BUFG u_bufg_clk (.I(clk_50), .O(core_clk));
// `endif

	// Reset synchronizer
	wire                        rst_n_raw = reset & locked;
	reg     [ 1: 0]             rst_sync;
	wire                        rst_n_sync = rst_sync[1];

	always @(posedge core_clk or negedge rst_n_raw) begin
		if (!rst_n_raw) rst_sync <= 2'b00;
		else            rst_sync <= {rst_sync[0], 1'b1};
	end

	// Core and memory instances
	wire    [31: 0]             imem_addr, imem_data;
	wire                        dmem_re, dmem_we;
	wire    [31: 0]             dmem_raddr, dmem_rdata, dmem_waddr, dmem_wdata;
	wire    [ 3: 0]             dmem_wstrb;
	wire    [31: 0]             ram_rdata;
	wire                        exception;
	wire                        dbg_commit_valid, dbg_ooo_event, dbg_stall_rob, dbg_stall_rs, dbg_hold;

	pipe_ooo U_CORE (
		.clk                 (core_clk),
		.reset               (rst_n_sync),
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
		.dbg_commit_valid    (dbg_commit_valid),
		.dbg_commit_pc       (),
		.dbg_commit_rd       (),
		.dbg_commit_has_rd   (),
		.dbg_commit_value    (),
		.dbg_commit_is_store (),
		.dbg_ooo_event       (dbg_ooo_event),
		.dbg_stall_rob       (dbg_stall_rob),
		.dbg_stall_rs        (dbg_stall_rs),
		.dbg_hold            (dbg_hold),
		.dbg_cdb_valid       ()
	);

	wire                        w_mmio = (dmem_waddr[31:28] == 4'h1);
	wire                        r_mmio = (dmem_raddr[31:28] == 4'h1);

	instr_mem U_IMEM (.clk(core_clk), .pc(imem_addr), .instr(imem_data));
	data_mem  U_DMEM (.clk(core_clk), .re(dmem_re), .raddr(dmem_raddr), .rdata(ram_rdata),
	                  .we(dmem_we & ~w_mmio), .waddr(dmem_waddr), .wdata(dmem_wdata), .wstrb(dmem_wstrb));

	// MMIO decode and registers
	reg     [31: 0]             result;
	reg                         done;
	reg     [15: 0]             sw_meta, sw_sync;
	reg                         rd_sw, rd_zero;

	always @(posedge core_clk or negedge rst_n_sync) begin
		if (!rst_n_sync) begin
			sw_meta <= 16'd0;
			sw_sync <= 16'd0;
		end else begin
			sw_meta <= sw;
			sw_sync <= sw_meta;
		end
	end

	integer                     b;
	always @(posedge core_clk or negedge rst_n_sync) begin
		if (!rst_n_sync)
			result <= 32'd0;
		else if (dmem_we && dmem_waddr[31:2] == MMIO_RESULT[31:2])
			for (b = 0; b < 4; b = b + 1)
				if (dmem_wstrb[b]) result[8*b +: 8] <= dmem_wdata[8*b +: 8];
	end

	always @(posedge core_clk or negedge rst_n_sync) begin
		if (!rst_n_sync)                             done <= 1'b0;
		else if (dmem_we && dmem_waddr[31:2] == MMIO_DONE[31:2]) done <= 1'b1;
	end

	// Registered read mux
	always @(posedge core_clk or negedge rst_n_sync) begin
		if (!rst_n_sync) begin
			rd_sw   <= 1'b0;
			rd_zero <= 1'b0;
		end else if (dmem_re) begin
			rd_sw   <= (dmem_raddr[31:2] == MMIO_SW[31:2]);
			rd_zero <= r_mmio && (dmem_raddr[31:2] != MMIO_SW[31:2]);
		end
	end

	assign dmem_rdata = rd_sw   ? {16'd0, sw_sync} :
	                    rd_zero ? 32'd0 :
	                              ram_rdata;

	// Performance counters
	wire    [31: 0]             cycles, retired, ooo_count;

	perf_counters U_PERF (
		.clk                 (core_clk),
		.reset_n             (rst_n_sync),
		.run                 (rst_n_sync & ~done),
		.commit_valid        (dbg_commit_valid),
		.ooo_event           (dbg_ooo_event),
		.stall_rob           (dbg_stall_rob),
		.stall_rs            (dbg_stall_rs),
		.hold                (dbg_hold),
		.cycles              (cycles),
		.retired             (retired),
		.ooo_count           (ooo_count),
		.rob_stall_cycles    (),
		.rs_stall_cycles     (),
		.hold_cycles         ()
	);

	// Display and LED driver
	assign led = {done, exception, result[13:0]};

	reg     [31: 0]             disp;
	always @(*) begin
		case (sw_sync[15:14])
			2'b00:   disp = result;
			2'b01:   disp = cycles;
			2'b10:   disp = retired;
			default: disp = ooo_count;
		endcase
	end

	reg     [REFRESH_W+2: 0]    refresh;
	always @(posedge core_clk or negedge rst_n_sync) begin
		if (!rst_n_sync) refresh <= {(REFRESH_W+3){1'b0}};
		else             refresh <= refresh + 1'b1;
	end

	wire    [ 2: 0]             digit = refresh[REFRESH_W+2:REFRESH_W];
	wire    [ 3: 0]             nib   = disp[4*digit +: 4];
	reg     [ 6: 0]             font;                   // {g, f, e, d, c, b, a}, active high
	always @(*) begin
		case (nib)
			4'h0: font = 7'h3F;  4'h1: font = 7'h06;  4'h2: font = 7'h5B;  4'h3: font = 7'h4F;
			4'h4: font = 7'h66;  4'h5: font = 7'h6D;  4'h6: font = 7'h7D;  4'h7: font = 7'h07;
			4'h8: font = 7'h7F;  4'h9: font = 7'h6F;  4'hA: font = 7'h77;  4'hB: font = 7'h7C;
			4'hC: font = 7'h39;  4'hD: font = 7'h5E;  4'hE: font = 7'h79;  default: font = 7'h71;
		endcase
	end

	assign seg = ~{1'b0, font};                         // DP off
	assign an  = ~(8'd1 << digit);

endmodule
