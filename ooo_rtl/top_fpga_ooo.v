
//  top_fpga_ooo - Nexys A7-100T board top for pipe_ooo (owner: E, reviewer: B)
//  PROJECT_BLUEPRINT.md 6.16, SIGNALS_REFERENCE.md 2.17, decisions D7, D8,
//  D20, D21, D22.
//
//
//  Contents: 100 -> 50 MHz MMCM (D7), reset synchronizer, instr_mem, data_mem,
//  pipe_ooo, perf_counters, MMIO decode, 7-segment driver, LEDs.
//
//
//  MMIO (D8, D20, D22), matched on the full word address [31:2] (byte lanes
//  come from dmem_write_byte; the LSU formats load bytes from the word):
//    store 0x1000_0000 : result, written per byte lane from dmem_write_byte
//    store 0x1000_0004 : any store sets done (cleared only by reset)
//    load  0x1000_0008 : {16'd0, sw} (sw through a two-flip-flop synchronizer)
//    any other address with [31:28] = 4'h1: store dropped, load returns 0.
//  MMIO stores never write data_mem. The read-data mux selects on the read
//  address registered in the LA cycle (data_mem returns data one cycle later).
//
//
//  Counters (D21): run = rst_n_sync & ~done, so the edge that latches done is
//  the last one counted.
//
//  Seven-segment display: shows one 8-digit hex value, chosen by the switches.
//
//    sw[12] sw[13] sw[15:14]   value shown
//    ------ ------ ---------   -----------------
//      0      0       00       result
//      0      0       01       cycle count
//      0      0       10       instructions retired
//      0      0       11       ooo_count
//      0      1       00       L1 D-cache accesses
//      0      1       01       L1 D-cache hits
//      0      1       10       L1 D-cache misses
//      0      1       11       L1 D-cache stall cycles
//      1      x       0x       branches
//      1      x       1x       branch mispredicts
//
//  sw[12] takes priority over sw[13]. In branch mode only sw[14] matters.
//
//  LEDs: led[15] is done, led[14] is exception, led[13:0] mirror result[13:0].
//
//  Data memory latency: the mem_wait block is placed between the core and
//  data_mem, and its delay is set by MEM_WAIT in ooo_defs.vh. Setting MEM_WAIT
//  to 0 leaves data_mem timing unchanged. MMIO accesses always bypass mem_wait.
//
//  Simulation: define TOMA_SIM at compile time to remove the MMCM, which makes
//  core_clk the same as clk. Testbenches rely on the instance names U_IMEM,
//  U_DMEM, U_CORE and U_PERF, so keep them as they are.

`timescale 1ns/1ps
`include "ooo_defs.vh"

module top_fpga_ooo
#(
	parameter  REFRESH_W = 17      // 50 MHz / 2^17 = 381 Hz per digit
)
(
	input                       clk,                // 100 MHz board clock
	input                       reset,              // active low
	input       [15: 0]         sw,
	output      [15: 0]         led,
	output      [ 7: 0]         seg,                // {DP, CG, CF, CE, CD, CC, CB, CA}, active low
	output      [ 7: 0]         an                  // active low
);

localparam [31:0] MMIO_RESULT = 32'h1000_0000;
localparam [31:0] MMIO_DONE = 32'h1000_0004;
localparam [31:0] MMIO_SW = 32'h1000_0008;

// ---- clock (D7) -------------------------------------------------------
wire core_clk;
wire locked;

`ifdef TOMA_SIM
    assign core_clk = clk;
assign locked = 1'b1;
`else wire clk_fb, clk_fb_buf, clk_50;

MMCME2_BASE #(
        .CLKIN1_PERIOD(10.0), // 100 MHz in
        .DIVCLK_DIVIDE(1),
        .CLKFBOUT_MULT_F(10.0), // VCO 1000 MHz
        .CLKOUT0_DIVIDE_F(20.0) // 50 MHz out
    )u_mmcm(.CLKIN1(clk),
            .CLKFBIN(clk_fb_buf),
            .CLKFBOUT(clk_fb),
            .CLKOUT0(clk_50),
            .LOCKED(locked),
            .PWRDWN(1'b0),
            .RST(1'b0));
BUFG u_bufg_fb(.I(clk_fb), .O(clk_fb_buf));
BUFG u_bufg_clk(.I(clk_50), .O(core_clk));
`endif

    // ---- reset synchronizer: asynchronous assert, synchronous release ---------
    wire rst_n_raw = reset & locked;
reg [1:0] rst_sync;
wire rst_n_sync = rst_sync[1];

always @(posedge core_clk or negedge rst_n_raw) begin
    if (!rst_n_raw) rst_sync
    <= 2'b00;
else rst_sync <= {rst_sync[0], 1'b1};
end

// ---- core and memories --------------------------------------------------
wire [31:0] imem_addr,
    imem_data;
wire dmem_re, dmem_we;
wire [31:0] dmem_raddr, dmem_rdata, dmem_waddr, dmem_wdata;
wire [3:0] dmem_wstrb;
wire [31:0] ram_rdata;
wire exception;
wire dbg_commit_valid, dbg_ooo_event, dbg_stall_rob, dbg_stall_rs, dbg_hold;
wire dbg_dc_access, dbg_dc_hit, dbg_dc_miss, dbg_dc_stall;
wire dbg_br_commit, dbg_br_mispred;
wire mem_read_valid, mem_write_valid;
wire ram_re, ram_we;
wire [31:0] ram_raddr, ram_waddr, ram_wdata;
wire [3:0] ram_wstrb;

pipe_ooo U_CORE(
        .clk(core_clk),
        .reset(rst_n_sync),
        .stall(1'b0),
        .exception(exception),
        .pc_out(),
        .inst_mem_is_valid(1'b1),
        .inst_mem_read_data(imem_data),
        .dmem_read_data_temp(dmem_rdata),
        .dmem_write_valid(mem_write_valid),
        .dmem_read_valid(mem_read_valid),
        .inst_mem_address(imem_addr),
        .dmem_read_ready(dmem_re),
        .dmem_read_address(dmem_raddr),
        .dmem_write_ready(dmem_we),
        .dmem_write_address(dmem_waddr),
        .dmem_write_data(dmem_wdata),
        .dmem_write_byte(dmem_wstrb),
        .dbg_commit_valid(dbg_commit_valid),
        .dbg_commit_pc(),
        .dbg_commit_rd(),
        .dbg_commit_has_rd(),
        .dbg_commit_value(),
        .dbg_commit_is_store(),
        .dbg_ooo_event(dbg_ooo_event),
        .dbg_stall_rob(dbg_stall_rob),
        .dbg_stall_rs(dbg_stall_rs),
        .dbg_hold(dbg_hold),
        .dbg_cdb_valid(),
        .dbg_dc_access(dbg_dc_access),
        .dbg_dc_hit(dbg_dc_hit),
        .dbg_dc_miss(dbg_dc_miss),
        .dbg_dc_stall(dbg_dc_stall),
        .dbg_br_commit(dbg_br_commit),
        .dbg_br_mispred(dbg_br_mispred));

wire w_mmio = (dmem_waddr [31:28] == 4'h1);
wire r_mmio = (dmem_raddr [31:28] == 4'h1);

instr_mem U_IMEM(.clk(core_clk), .pc(imem_addr), .instr(imem_data));
mem_wait U_MEMW(.clk(core_clk), .reset_n(rst_n_sync),
                .re(dmem_re & ~r_mmio), .raddr(dmem_raddr),
                .we(dmem_we & ~w_mmio), .waddr(dmem_waddr), .wdata(dmem_wdata), .wstrb(dmem_wstrb),
                .read_valid(mem_read_valid), .write_valid(mem_write_valid),
                .ram_re(ram_re), .ram_raddr(ram_raddr),
                .ram_we(ram_we), .ram_waddr(ram_waddr), .ram_wdata(ram_wdata), .ram_wstrb(ram_wstrb));
data_mem U_DMEM(.clk(core_clk), .re(ram_re), .raddr(ram_raddr), .rdata(ram_rdata),
                .we(ram_we), .waddr(ram_waddr), .wdata(ram_wdata), .wstrb(ram_wstrb));

// ---- MMIO (D8, D20, D22) ------------------------------------------------
reg [31:0] result;
reg done;
reg [15:0] sw_meta, sw_sync;
reg rd_sw, rd_zero;

always @(posedge core_clk or negedge rst_n_sync) begin
    if (!rst_n_sync) begin
    sw_meta
    <= 16'd0;
sw_sync <= 16'd0;
end else begin
        sw_meta <= sw;
sw_sync <= sw_meta;
end
    end

        integer b;
always @(posedge core_clk or negedge rst_n_sync) begin
    if (!rst_n_sync)
        result
    <= 32'd0;
else if (dmem_we && dmem_waddr [31:2] == MMIO_RESULT [31:2]) for (b = 0; b < 4; b = b + 1) if (dmem_wstrb[b]) result [8 * b +:8] <= dmem_wdata [8 * b +:8];
end

        always @(posedge core_clk or negedge rst_n_sync) begin
    if (!rst_n_sync) done
    <= 1'b0;
else if (dmem_we && dmem_waddr [31:2] == MMIO_DONE [31:2]) done <= 1'b1;
end

        // read source, registered in the LA cycle and held like data_mem.rdata
        always @(posedge core_clk or negedge rst_n_sync) begin
    if (!rst_n_sync) begin
    rd_sw
    <= 1'b0;
rd_zero <= 1'b0;
end else if (dmem_re) begin
        rd_sw <= (dmem_raddr [31:2] == MMIO_SW [31:2]);
rd_zero <= r_mmio && (dmem_raddr [31:2] != MMIO_SW [31:2]);
end
    end

        assign dmem_rdata = rd_sw ? {16'd0, sw_sync} : rd_zero ? 32'd0
                                                               : ram_rdata;

// ---- performance counters (D21) ------------------------------------------
wire [31:0] cycles, retired, ooo_count;
wire [31:0] dc_access, dc_hit, dc_miss, dc_stall;
wire [31:0] br_count, br_mispred;

perf_counters U_PERF(
        .clk(core_clk),
        .reset_n(rst_n_sync),
        .run(rst_n_sync & ~done),
        .commit_valid(dbg_commit_valid),
        .ooo_event(dbg_ooo_event),
        .stall_rob(dbg_stall_rob),
        .stall_rs(dbg_stall_rs),
        .hold(dbg_hold),
        .dc_access(dbg_dc_access),
        .dc_hit(dbg_dc_hit),
        .dc_miss(dbg_dc_miss),
        .dc_stall(dbg_dc_stall),
        .br_commit(dbg_br_commit),
        .br_mispred(dbg_br_mispred),
        .cycles(cycles),
        .retired(retired),
        .ooo_count(ooo_count),
        .rob_stall_cycles(),
        .rs_stall_cycles(),
        .hold_cycles(),
        .dcache_access_count(dc_access),
        .dcache_hit_count(dc_hit),
        .dcache_miss_count(dc_miss),
        .dcache_stall_cycles(dc_stall),
        .branch_count(br_count),
        .mispredict_count(br_mispred));

// ---- LEDs and 7-segment display -----------------------------------------
assign led = {done, exception, result [13:0]};

reg [31:0] disp;
always @(*) begin
    if (sw_sync[12]) disp = sw_sync[14] ? br_mispred : br_count;
        else case (sw_sync[15:13])
			3'b000:  disp = result;
        3'b010 : disp = cycles;
        3'b100 : disp = retired;
        3'b110 : disp = ooo_count;
        3'b001 : disp = dc_access;
        3'b011 : disp = dc_hit;
        3'b101 : disp = dc_miss;
        default:
        disp = dc_stall;
        endcase
            end

        reg [REFRESH_W + 2:0] refresh;
        always @(posedge core_clk or negedge rst_n_sync) begin
            if (!rst_n_sync) refresh
            <= {(REFRESH_W + 3){1'b0}};
        else refresh <= refresh + 1'b1;
        end

        wire [2:0] digit = refresh [REFRESH_W + 2:REFRESH_W];
        wire [3:0] nib = disp [4 * digit +:4];
        reg [6:0] font; // {g, f, e, d, c, b, a}, active high
        always @(*) begin
            case (nib)4'h0:
        font = 7'h3F;
        4'h1 : font = 7'h06;
        4'h2 : font = 7'h5B;
        4'h3 : font = 7'h4F;
        4'h4 : font = 7'h66;
        4'h5 : font = 7'h6D;
        4'h6 : font = 7'h7D;
        4'h7 : font = 7'h07;
        4'h8 : font = 7'h7F;
        4'h9 : font = 7'h6F;
        4'hA : font = 7'h77;
        4'hB : font = 7'h7C;
        4'hC : font = 7'h39;
        4'hD : font = 7'h5E;
        4'hE : font = 7'h79;
        default:
        font = 7'h71;
        endcase
            end

                assign seg = ~{1'b0, font}; // DP off
        assign an = ~(8'd1 << digit);

        endmodule
