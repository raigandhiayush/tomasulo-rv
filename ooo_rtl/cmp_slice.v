// cmp_slice.v - one core of the comparison board top (top_fpga_cmp), with its own
// instruction memory, data memory, MMIO and performance counters.
//
//   CORE = 1   pipe_m (in-order baseline with MUL/DIV), data_mem answers in 1 cycle
//   CORE = 2   pipe_ooo (Tomasulo core with the L1 data cache), behind mem_wait #(MEM_WAIT),
//              active ROB size rob_lim
//   CORE = 3   pipe_m behind mem_wait #(MEM_WAIT): the baseline on slow memory (see below)
//
// CORE 1 and 2 behave cycle for cycle like the single-core board tops:
//   CORE = 1 like top_fpga_base #(.CORE(1)),
//   CORE = 2 like top_fpga_ooo #(.MEM_WAIT(MEM_WAIT), .ROB_LIM(rob_lim)),
// for every program that uses only result, done, switches and the cycle counter.
// tb_top_fpga_cmp checks that, counter by counter, every cycle.
//
// CORE = 3, slow memory for a core that cannot wait. pipe_m expects every load's data one
// cycle after the request and has no working wait input. Instead of changing it, the
// whole core runs on gclk, a copy of clk that the top gates with ce (cmp_clkgate). ce = 0
// in every cycle where memory is not ready: a read is still being served by mem_wait, or
// the core wants to write and the write buffer is full. While ce = 0 every flip-flop of
// the core holds, so the core sees exactly the 1-cycle memory it was built for, with the
// waiting cycles cut out of its time line. That is what an in-order pipeline that stalls
// on a memory access does. Everything outside the core (memories, mem_wait, MMIO and the
// cycle counter) runs on clk, so cycles counts the waiting cycles too. Every action the
// core takes (memory requests, MMIO stores, retire pulses) is gated with ce, so it counts
// once. The memory model is the same mem_wait, with the same WAIT, write buffer and
// sequential-access rule, as the slow OoO core: the comparison between the two is fair.
//
// MMIO (same addresses as top_fpga_ooo):
//   store 0x1000_0000 result, store 0x1000_0004 done,
//   load  0x1000_0008 {16'd0, sw}, load 0x1000_0028 cycle counter.
//   Every other MMIO load returns 0 and every other MMIO store is ignored: the slices have
//   no UART or buttons (the UART belongs to the boot loader), so a program that waits for
//   UART input or output never finishes here.
//
// Boot loader: while boot_load = 1 the core is held in reset (core_rst_n = 0, driven by
// the top) and the loader's write ports fill imem and dmem. All three slices get the
// same writes, so they hold the same program.
//
// Instance names U_CORE, U_IMEM, U_DMEM, U_PERF match the single-core tops, so
// testbenches can preload DUT.<slice>.U_IMEM.imem.
`timescale 1ns/1ps
`include "ooo_defs.vh"

module cmp_slice #(
    parameter CORE     = 2,         // 1 = pipe_m, 2 = pipe_ooo, 3 = pipe_m on slow memory
    parameter MEM_WAIT = 0          // CORE 2 and 3: data_mem extra cycles (mem_wait.v)
) (
    input  wire        clk,
    input  wire        gclk,        // CORE 3: gated clk for the core (cmp_clkgate); else unused
    output wire        gce,         // CORE 3: enable that gates gclk; 1 for the other cores
    input  wire        core_rst_n,  // active low: reset for the core and everything it sees
    input  wire [`ROB_W :0] rob_lim,
    input  wire [15:0] sw,          // board switches (raw; synchronized here)
    // boot loader write ports (used while boot_load = 1)
    input  wire        boot_load,
    input  wire        ld_imem_we,
    input  wire [ 9:0] ld_imem_waddr,
    input  wire [31:0] ld_imem_wdata,
    input  wire        ld_dmem_we,
    input  wire [ 9:0] ld_dmem_waddr,
    input  wire [31:0] ld_dmem_wdata,
    // results and counters
    output reg  [31:0] result,
    output reg         done,
    output wire        exception,
    output wire [31:0] cycles,
    output wire [31:0] retired,
    output wire [31:0] ooo_count,
    output wire [31:0] dc_access,
    output wire [31:0] dc_hit,
    output wire [31:0] dc_miss,
    output wire [31:0] dc_stall,
    output wire [31:0] br_count,
    output wire [31:0] br_mispred
);
    localparam [31:0] MMIO_RESULT = 32'h1000_0000;
    localparam [31:0] MMIO_DONE   = 32'h1000_0004;
    localparam [31:0] MMIO_SW     = 32'h1000_0008;
    localparam [31:0] MMIO_CYC    = `MMIO_CYCLES;

    wire [31:0] imem_addr, imem_data;
    wire        dmem_re, dmem_we;
    wire [31:0] dmem_raddr, dmem_rdata, dmem_waddr, dmem_wdata;
    wire [ 3:0] dmem_wstrb;
    wire [31:0] ram_rdata;
    wire        dbg_commit_valid, dbg_ooo_event, dbg_stall_rob, dbg_stall_rs, dbg_hold;
    wire        dbg_dc_access, dbg_dc_hit, dbg_dc_miss, dbg_dc_stall;
    wire        dbg_br_commit, dbg_br_mispred;
    wire        mem_read_valid, mem_write_valid;
    wire        ram_re, ram_we;
    wire [31:0] ram_raddr, ram_waddr, ram_wdata;
    wire [ 3:0] ram_wstrb;

    wire w_mmio = (dmem_waddr[31:28] == 4'h1);
    wire r_mmio = (dmem_raddr[31:28] == 4'h1);

    generate
        if (CORE == 1) begin : g_core
            pipe_m U_CORE (
                .clk                 (clk),
                .reset               (core_rst_n),
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
                .dbg_retire          (dbg_commit_valid)
            );
            // in-order core: no out-of-order events, no cache, no predictor
            assign dbg_ooo_event = 1'b0;
            assign dbg_stall_rob = 1'b0;
            assign dbg_stall_rs  = 1'b0;
            assign dbg_hold      = 1'b0;
            assign dbg_dc_access = 1'b0;
            assign dbg_dc_hit    = 1'b0;
            assign dbg_dc_miss   = 1'b0;
            assign dbg_dc_stall  = 1'b0;
            assign dbg_br_commit = 1'b0;
            assign dbg_br_mispred = 1'b0;
            // data_mem directly, as in top_fpga_base (no wait support in the baseline)
            assign ram_re    = dmem_re;
            assign ram_raddr = dmem_raddr;
            assign ram_we    = dmem_we & ~w_mmio;
            assign ram_waddr = dmem_waddr;
            assign ram_wdata = dmem_wdata;
            assign ram_wstrb = dmem_wstrb;
            assign mem_read_valid  = 1'b1;
            assign mem_write_valid = 1'b1;
            assign gce             = 1'b1;
        end else if (CORE == 3) begin : g_core
            pipe_m U_CORE (
                .clk                 (gclk),
                .reset               (core_rst_n),
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
                .dbg_retire          (dbg_commit_valid)
            );
            assign dbg_ooo_event = 1'b0;
            assign dbg_stall_rob = 1'b0;
            assign dbg_stall_rs  = 1'b0;
            assign dbg_hold      = 1'b0;
            assign dbg_dc_access = 1'b0;
            assign dbg_dc_hit    = 1'b0;
            assign dbg_dc_miss   = 1'b0;
            assign dbg_dc_stall  = 1'b0;
            assign dbg_br_commit = 1'b0;
            assign dbg_br_mispred = 1'b0;
            // memory ready for whatever the core does this cycle: no read still in mem_wait,
            // and room in the write buffer if it writes. Requests go out only when ce = 1.
            wire want_w = dmem_we & ~w_mmio;
            assign gce = mem_read_valid & (mem_write_valid | ~want_w);
            mem_wait #(.WAIT(MEM_WAIT)) U_MEMW (
                .clk(clk), .reset_n(core_rst_n),
                .re(dmem_re & ~r_mmio & gce), .raddr(dmem_raddr),
                .we(want_w & gce), .waddr(dmem_waddr), .wdata(dmem_wdata), .wstrb(dmem_wstrb),
                .read_valid(mem_read_valid), .write_valid(mem_write_valid),
                .ram_re(ram_re), .ram_raddr(ram_raddr),
                .ram_we(ram_we), .ram_waddr(ram_waddr), .ram_wdata(ram_wdata), .ram_wstrb(ram_wstrb));
        end else begin : g_core
            pipe_ooo U_CORE (
                .clk                 (clk),
                .reset               (core_rst_n),
                .rob_lim             (rob_lim),
                .stall               (1'b0),
                .exception           (exception),
                .pc_out              (),
                .inst_mem_is_valid   (1'b1),
                .inst_mem_read_data  (imem_data),
                .dmem_read_data_temp (dmem_rdata),
                .dmem_write_valid    (mem_write_valid),
                .dmem_read_valid     (mem_read_valid),
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
                .dbg_cdb_valid       (),
                .dbg_dc_access       (dbg_dc_access),
                .dbg_dc_hit          (dbg_dc_hit),
                .dbg_dc_miss         (dbg_dc_miss),
                .dbg_dc_stall        (dbg_dc_stall),
                .dbg_br_commit       (dbg_br_commit),
                .dbg_br_mispred      (dbg_br_mispred)
            );
            mem_wait #(.WAIT(MEM_WAIT)) U_MEMW (
                .clk(clk), .reset_n(core_rst_n),
                .re(dmem_re & ~r_mmio), .raddr(dmem_raddr),
                .we(dmem_we & ~w_mmio), .waddr(dmem_waddr), .wdata(dmem_wdata), .wstrb(dmem_wstrb),
                .read_valid(mem_read_valid), .write_valid(mem_write_valid),
                .ram_re(ram_re), .ram_raddr(ram_raddr),
                .ram_we(ram_we), .ram_waddr(ram_waddr), .ram_wdata(ram_wdata), .ram_wstrb(ram_wstrb));
            assign gce = 1'b1;
        end
    endgenerate

    // en: the core really acts this cycle (always 1 except for CORE 3 while memory waits)
    wire en = gce;

    // The instruction memory answers one cycle after the pc, like a pipeline register, so for
    // CORE 3 it must freeze with the core: on clk it would keep re-reading during a wait and
    // the core would wake up with the instruction of its next pc instead of its current one.
    // (data_mem needs nothing: its rdata only changes on a read, and reads go out with ce.)
    // gclk runs whenever the core is in reset, so the boot loader can still write.
    wire imem_clk;
    generate
        if (CORE == 3) begin : g_imem_clk
            assign imem_clk = gclk;
        end else begin : g_imem_clk
            assign imem_clk = clk;
        end
    endgenerate
    instr_mem_wr U_IMEM (.clk(imem_clk), .pc(imem_addr), .instr(imem_data),
                         .we(ld_imem_we), .waddr(ld_imem_waddr), .wdata(ld_imem_wdata));
    // while loading, the boot loader owns the data_mem write port (whole words)
    data_mem U_DMEM (.clk(clk), .re(ram_re), .raddr(ram_raddr), .rdata(ram_rdata),
                     .we   (boot_load ? ld_dmem_we : ram_we),
                     .waddr(boot_load ? {20'd0, ld_dmem_waddr, 2'b00} : ram_waddr),
                     .wdata(boot_load ? ld_dmem_wdata : ram_wdata),
                     .wstrb(boot_load ? 4'hF : ram_wstrb));

    // ---- MMIO ------------------------------------------------------------------
    reg [15:0] sw_meta, sw_sync;
    reg        rd_sw, rd_cyc, rd_zero;
    always @(posedge clk or negedge core_rst_n) begin
        if (!core_rst_n) begin
            sw_meta <= 16'd0;
            sw_sync <= 16'd0;
        end else begin
            sw_meta <= sw;
            sw_sync <= sw_meta;
        end
    end

    integer b;
    always @(posedge clk or negedge core_rst_n) begin
        if (!core_rst_n)
            result <= 32'd0;
        else if (en && dmem_we && dmem_waddr[31:2] == MMIO_RESULT[31:2])
            for (b = 0; b < 4; b = b + 1)
                if (dmem_wstrb[b]) result[8*b +: 8] <= dmem_wdata[8*b +: 8];
    end

    always @(posedge clk or negedge core_rst_n) begin
        if (!core_rst_n)                                         done <= 1'b0;
        else if (en && dmem_we && dmem_waddr[31:2] == MMIO_DONE[31:2]) done <= 1'b1;
    end

    // read source, registered in the request cycle and held like data_mem.rdata
    reg [31:0] rd_cyc_val;
    wire sel_sw  = (dmem_raddr[31:2] == MMIO_SW [31:2]);
    wire sel_cyc = (dmem_raddr[31:2] == MMIO_CYC[31:2]);
    always @(posedge clk or negedge core_rst_n) begin
        if (!core_rst_n) begin
            rd_sw <= 1'b0; rd_cyc <= 1'b0; rd_zero <= 1'b0; rd_cyc_val <= 32'd0;
        end else if (dmem_re && en) begin
            rd_sw      <= sel_sw;
            rd_cyc     <= sel_cyc;
            rd_cyc_val <= cycles;
            rd_zero    <= r_mmio && !sel_sw && !sel_cyc;
        end
    end
    assign dmem_rdata = rd_sw   ? {16'd0, sw_sync} :
                        rd_cyc  ? rd_cyc_val :
                        rd_zero ? 32'd0 :
                                  ram_rdata;

    // ---- performance counters (D21): count from reset release until done ---------
    perf_counters U_PERF (
        .clk                 (clk),
        .reset_n             (core_rst_n),
        .run                 (core_rst_n & ~done),
        .commit_valid        (dbg_commit_valid & en),
        .ooo_event           (dbg_ooo_event),
        .stall_rob           (dbg_stall_rob),
        .stall_rs            (dbg_stall_rs),
        .hold                (dbg_hold),
        .dc_access           (dbg_dc_access),
        .dc_hit              (dbg_dc_hit),
        .dc_miss             (dbg_dc_miss),
        .dc_stall            (dbg_dc_stall),
        .br_commit           (dbg_br_commit),
        .br_mispred          (dbg_br_mispred),
        .cycles              (cycles),
        .retired             (retired),
        .ooo_count           (ooo_count),
        .rob_stall_cycles    (),
        .rs_stall_cycles     (),
        .hold_cycles         (),
        .dcache_access_count (dc_access),
        .dcache_hit_count    (dc_hit),
        .dcache_miss_count   (dc_miss),
        .dcache_stall_cycles (dc_stall),
        .branch_count        (br_count),
        .mispredict_count    (br_mispred)
    );
endmodule
