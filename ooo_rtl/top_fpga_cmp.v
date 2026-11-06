// top_fpga_cmp.v - Nexys A7-100T board top that runs four cores side by side on the same
// program, so their cycle counts can be compared on the board from one bitstream.
//
//   core 0  pipe_m       in-order baseline, data_mem in 1 cycle
//   core 1  OoO fast     pipe_ooo with the L1 data cache, data_mem in 1 cycle (MEM_WAIT 0)
//   core 2  OoO slow     pipe_ooo with the L1 data cache, data_mem + SLOW_WAIT extra cycles
//                        (default `MEM_WAIT = 10): the same as the default single-core build
//   core 3  pipe_m slow  the baseline on the same slow memory as core 2 (mem_wait #(SLOW_WAIT));
//                        the core is clock-gated while memory is not ready (cmp_slice.v)
//
// Each core has its own instruction memory, data memory, MMIO and counters (cmp_slice.v).
// Cores 0-2 behave cycle for cycle like their single-core board tops (tb_top_fpga_cmp).
// All four leave reset on the same clock edge; each counter stops at its own core's done.
//
// Build with ROB_N = 16, ROB_W = 4 (synth_vivado.tcl does): the two OoO cores then have 16
// physical ROB entries, of which 4, 8 or 16 are used, chosen by switches (below).
//
// Ports and pins are the same as top_fpga_ooo, so top_fpga_ooo.xdc is used unchanged.
//
// ---- Switches -----------------------------------------------------------------------------
//   sw[15:14] page:  00 pipe_m   01 OoO fast   10 OoO slow   11 pipe_m on slow memory
//   sw[13:10] item (below)
//   sw[9]     1 = counters in decimal, 0 = hex (ratios are always decimal)
//   sw[8:7]   ROB size of both OoO cores: 00 = 8, 01 = 4, 10 or 11 = 16.
//             Read only while the cores are in reset: change it, then press CPU_RESET (or
//             load a program). Moving it during a run has no effect on that run.
//   All 16 switches are also readable by the programs at 0x1000_0008, as on the other tops.
//
//   Items (every page shows its own core; items 13-15 are the same on every page):
//     0 result (hex, or signed decimal)    7 D-cache stall cycles
//     1 cycles                             8 branches
//     2 instructions retired               9 branch mispredicts
//     3 ooo_count                         10 CPI = cycles / retired (3 places)
//     4 D-cache accesses                  11 D-cache hit rate = hits / accesses
//     5 D-cache hits                      12 mispredict rate = mispredicts / branches
//     6 D-cache misses
//    13 speed-up on slow memory   pipe_m slow cycles / OoO slow cycles  (same memory)
//    14 speed-up on fast memory   pipe_m cycles / OoO fast cycles       (same memory)
//    15 active ROB size of the OoO cores (4, 8 or 16)
//   pipe_m has no cache or predictor, so items 4-9 read 0 on its pages. A ratio with a zero
//   denominator shows "--------".
//
// ---- LEDs ---------------------------------------------------------------------------------
//   led[15] all four done      led[14] any core raised an exception
//   led[13] pipe_m done        led[12] OoO fast done      led[11] OoO slow done
//   led[10] all done and all four results equal (the cores agree)
//   led[9]  boot loader waiting for a program               led[8] pipe_m slow done
//   led[7:0] result[7:0] of the page's core
//
// ---- Boot loader ----------------------------------------------------------------------------
//   Hold BTNC while releasing CPU_RESET: all cores stay in reset while uart_loader receives
//   a program (frame format in uart_loader.v, tools/boot_frame.py, tools/send_program.ps1).
//   Every write goes to all four cores' memories, so they run the same program. On a good
//   checksum the board replies OK and all cores start on the same edge; a bad frame gets ERR
//   and they stay held. A plain CPU_RESET re-runs the loaded program on all four.
//   Outside load mode the UART is not connected to the cores: programs that use the UART do
//   not finish here. Use programs that end with the done store (the *_d8 and stream tests).
`timescale 1ns/1ps
`include "ooo_defs.vh"

module top_fpga_cmp
#(
	parameter  REFRESH_W = 17,          // 50 MHz / 2^17 = 381 Hz per digit
	parameter  SLOW_WAIT = `MEM_WAIT
)
(
	input                       clk,                // 100 MHz board clock
	input                       reset,              // active low (CPU_RESET)
	input       [15: 0]         sw,
	output      [15: 0]         led,
	output      [ 7: 0]         seg,                // {DP, CG, CF, CE, CD, CC, CB, CA}, active low
	output      [ 7: 0]         an,                 // active low
	input                       uart_rx,            // from the USB-UART bridge (idle high)
	output                      uart_tx,            // to the USB-UART bridge (idle high)
	input                       load_btn,           // BTNC, active high: held at reset = boot loader
	input       [ 3: 0]         btn                 // unused here (same constraints file)
);

// ---- clock (D7) ---------------------------------------------------------------------------
wire core_clk;
wire gate_src;          // what cmp_clkgate gates: the unbuffered MMCM output on the board
wire locked;
`ifdef TOMA_SIM
assign core_clk = clk;
assign gate_src = clk;
assign locked   = 1'b1;
`else
wire clk_fb, clk_fb_buf, clk_50;
MMCME2_BASE #(
	.CLKIN1_PERIOD   (10.0),    // 100 MHz in
	.DIVCLK_DIVIDE   (1),
	.CLKFBOUT_MULT_F (10.0),    // VCO 1000 MHz
	.CLKOUT0_DIVIDE_F(20.0)     // 50 MHz out
) u_mmcm (.CLKIN1(clk), .CLKFBIN(clk_fb_buf), .CLKFBOUT(clk_fb), .CLKOUT0(clk_50),
          .LOCKED(locked), .PWRDWN(1'b0), .RST(1'b0));
BUFG u_bufg_fb (.I(clk_fb), .O(clk_fb_buf));
BUFG u_bufg_clk(.I(clk_50), .O(core_clk));
assign gate_src = clk_50;
`endif

// ---- reset synchronizer: asynchronous assert, synchronous release -------------------------
wire rst_n_raw = reset & locked;
reg [1:0] rst_sync;
wire rst_n_sync = rst_sync[1];
always @(posedge core_clk or negedge rst_n_raw) begin
	if (!rst_n_raw) rst_sync <= 2'b00;
	else            rst_sync <= {rst_sync[0], 1'b1};
end

// ---- boot loader select (same logic as top_fpga_ooo) ----------------------------------------
reg [1:0] btn_sync;
always @(posedge core_clk) btn_sync <= {btn_sync[0], load_btn};
wire btn_held = btn_sync[1];

reg  core_rst_n;        // reset for all four cores, active low
reg  boot_load;         // 1: uart_loader owns the UART and the memory write ports
wire ld_loaded;
always @(posedge core_clk or negedge rst_n_raw) begin
	if (!rst_n_raw) begin
		core_rst_n <= 1'b0;
		boot_load  <= 1'b0;
	end else if (!rst_sync[1]) begin
		core_rst_n <= rst_sync[0] & ~btn_held;
		boot_load  <= rst_sync[0] &  btn_held;
	end else if (boot_load && ld_loaded) begin
		core_rst_n <= 1'b1;
		boot_load  <= 1'b0;
	end
end

// ---- ROB size select ------------------------------------------------------------------------
// sw[8:7] through two flip-flops that are not reset (so they are valid while the cores are
// held), copied into rob_sel only while core_rst_n = 0. The cores therefore always see a
// constant size from reset release to done, whatever the switches do during the run: the
// ROB never has to shrink below its occupancy, and each run measures exactly one size.
reg [1:0] rs_meta, rs_sync, rob_sel;
always @(posedge core_clk) begin
	rs_meta <= sw[8:7];
	rs_sync <= rs_meta;
	if (!core_rst_n) rob_sel <= rs_sync;
end
// requested size, clamped to the physical size before narrowing, so a build with a
// smaller ROB_N gets its full size instead of a truncated value
wire [5:0]      rob_req = (rob_sel == 2'b01) ? 6'd4 : (rob_sel == 2'b00) ? 6'd8 : 6'd16;
wire [5:0]      rob_c6  = (rob_req > `ROB_N) ? `ROB_N : rob_req;
wire [`ROB_W :0] rob_lim = rob_c6[`ROB_W :0];
wire [`ROB_W :0] rob_act = rob_lim;

// ---- UART and boot loader --------------------------------------------------------------------
wire        uart_rx_valid, uart_tx_ready;
wire [ 7:0] uart_rx_data;
wire        ld_rx_pop, ld_tx_push;
wire [ 7:0] ld_tx_data;
wire        ld_imem_we, ld_dmem_we;
wire [ 9:0] ld_imem_waddr, ld_dmem_waddr;
wire [31:0] ld_imem_wdata, ld_dmem_wdata;

uart_loader U_LOADER (
	.clk(core_clk), .reset_n(rst_n_sync), .active(boot_load),
	.rx_valid(uart_rx_valid), .rx_data(uart_rx_data), .rx_pop(ld_rx_pop),
	.tx_ready(uart_tx_ready), .tx_push(ld_tx_push), .tx_data(ld_tx_data),
	.imem_we(ld_imem_we), .imem_waddr(ld_imem_waddr), .imem_wdata(ld_imem_wdata),
	.dmem_we(ld_dmem_we), .dmem_waddr(ld_dmem_waddr), .dmem_wdata(ld_dmem_wdata),
	.loaded(ld_loaded));

uart U_UART (
	.clk(core_clk), .reset_n(rst_n_sync), .rx(uart_rx), .tx(uart_tx),
	.rx_valid(uart_rx_valid), .rx_data(uart_rx_data), .rx_pop(boot_load & ld_rx_pop),
	.rx_overflow(), .tx_ready(uart_tx_ready),
	.tx_push(boot_load & ld_tx_push), .tx_data(ld_tx_data), .tx_idle());

// ---- the four cores -----------------------------------------------------------------------------
wire [31:0] result  [0:3];
wire        done    [0:3];
wire        exc     [0:3];
wire        gce     [0:3];
wire [31:0] cycles  [0:3], retired [0:3], ooo_cnt [0:3];
wire [31:0] dc_acc  [0:3], dc_hit  [0:3], dc_miss [0:3], dc_stall [0:3];
wire [31:0] br_cnt  [0:3], br_mis  [0:3];

// core 3's clock: gate_src gated by its own enable
wire bslow_gclk;
cmp_clkgate U_GATE (.clk_in(gate_src), .ce(gce[3]), .gclk(bslow_gclk));

`define CMP_SLICE(NAME, IDX, KIND, WAITV, GCLK) \
cmp_slice #(.CORE(KIND), .MEM_WAIT(WAITV)) NAME ( \
	.clk(core_clk), .gclk(GCLK), .gce(gce[IDX]), .core_rst_n(core_rst_n), .rob_lim(rob_lim), \
	.sw(sw), .boot_load(boot_load), \
	.ld_imem_we(ld_imem_we), .ld_imem_waddr(ld_imem_waddr), .ld_imem_wdata(ld_imem_wdata), \
	.ld_dmem_we(ld_dmem_we), .ld_dmem_waddr(ld_dmem_waddr), .ld_dmem_wdata(ld_dmem_wdata), \
	.result(result[IDX]), .done(done[IDX]), .exception(exc[IDX]), \
	.cycles(cycles[IDX]), .retired(retired[IDX]), .ooo_count(ooo_cnt[IDX]), \
	.dc_access(dc_acc[IDX]), .dc_hit(dc_hit[IDX]), .dc_miss(dc_miss[IDX]), .dc_stall(dc_stall[IDX]), \
	.br_count(br_cnt[IDX]), .br_mispred(br_mis[IDX]));

`CMP_SLICE(U_BASE,  0, 1, 0,         1'b0)
`CMP_SLICE(U_FAST,  1, 2, 0,         1'b0)
`CMP_SLICE(U_SLOW,  2, 2, SLOW_WAIT, 1'b0)
`CMP_SLICE(U_BSLOW, 3, 3, SLOW_WAIT, bslow_gclk)
`undef CMP_SLICE

// ---- display selection ---------------------------------------------------------------------
reg [15:0] sw_meta, sw_sync;
always @(posedge core_clk or negedge rst_n_sync) begin
	if (!rst_n_sync) begin
		sw_meta <= 16'd0;
		sw_sync <= 16'd0;
	end else begin
		sw_meta <= sw;
		sw_sync <= sw_meta;
	end
end

wire [1:0] ci   = sw_sync[15:14];       // core shown on this page and on led[7:0]
wire [3:0] item = sw_sync[13:10];
wire       dec  = sw_sync[9];

localparam [1:0] M_HEX = 2'd0, M_DEC = 2'd1, M_SDEC = 2'd2, M_RATIO = 2'd3;

reg [1:0]  d_mode;
reg [31:0] d_a, d_b;
always @(*) begin
	d_mode = dec ? M_DEC : M_HEX;
	d_a    = 32'd0;
	d_b    = 32'd0;
	case (item)
		4'd0:  begin d_a = result[ci]; d_mode = dec ? M_SDEC : M_HEX; end
		4'd1:  d_a = cycles[ci];
		4'd2:  d_a = retired[ci];
		4'd3:  d_a = ooo_cnt[ci];
		4'd4:  d_a = dc_acc[ci];
		4'd5:  d_a = dc_hit[ci];
		4'd6:  d_a = dc_miss[ci];
		4'd7:  d_a = dc_stall[ci];
		4'd8:  d_a = br_cnt[ci];
		4'd9:  d_a = br_mis[ci];
		4'd10: begin d_mode = M_RATIO; d_a = cycles[ci]; d_b = retired[ci]; end
		4'd11: begin d_mode = M_RATIO; d_a = dc_hit[ci]; d_b = dc_acc[ci];  end
		4'd12: begin d_mode = M_RATIO; d_a = br_mis[ci]; d_b = br_cnt[ci];  end
		4'd13: begin d_mode = M_RATIO; d_a = cycles[3];  d_b = cycles[2];   end
		4'd14: begin d_mode = M_RATIO; d_a = cycles[0];  d_b = cycles[1];   end
		default: begin d_mode = M_DEC; d_a = {{(31-`ROB_W){1'b0}}, rob_act}; end
	endcase
end

// registered once so the display engine sees a clean value (and timing stays short)
reg [1:0]  d_mode_q;
reg [31:0] d_a_q, d_b_q;
always @(posedge core_clk or negedge rst_n_sync) begin
	if (!rst_n_sync) begin
		d_mode_q <= M_HEX; d_a_q <= 32'd0; d_b_q <= 32'd0;
	end else begin
		d_mode_q <= d_mode; d_a_q <= d_a; d_b_q <= d_b;
	end
end

cmp_display #(.REFRESH_W(REFRESH_W)) U_DISP (
	.clk(core_clk), .reset_n(rst_n_sync),
	.mode(d_mode_q), .a(d_a_q), .b(d_b_q),
	.seg(seg), .an(an), .dig(), .dp());

// ---- LEDs ----------------------------------------------------------------------------------
wire all_done = done[0] & done[1] & done[2] & done[3];
wire agree    = all_done && (result[0] == result[1]) && (result[1] == result[2]) &&
                (result[2] == result[3]);
assign led = {all_done, exc[0] | exc[1] | exc[2] | exc[3], done[0], done[1], done[2],
              agree, boot_load, done[3], result[ci][7:0]};

endmodule
