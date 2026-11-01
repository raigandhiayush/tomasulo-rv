// perf_counters.v - TOMA-RV performance counters (Person E)

    // Port list: SIGNALS_REFERENCE.md, section 2.16.
    // Required behaviour: PROJECT_BLUEPRINT.md, section 6.15.
    //
    // Counting rule: there are twelve 32-bit counters. On each rising clk edge,
    // a counter increments if run=1 and its event signal is high in that cycle.
    //
    //   counter               event          what it counts
    //   -------------------   ------------   ---------------------------------
    //   cycles                (none)         every cycle with run=1
    //   retired               commit_valid   committed instructions
    //   ooo_count             ooo_event      out-of-order events
    //   rob_stall_cycles      stall_rob      ROB stall cycles
    //   rs_stall_cycles       stall_rs       RS stall cycles
    //   hold_cycles           hold           hold cycles
    //   dcache_access_count   dc_access      cacheable requests accepted by l1_dcache
    //   dcache_hit_count      dc_hit         hits among those requests
    //   dcache_miss_count     dc_miss        misses among those requests
    //   dcache_stall_cycles   dc_stall       l1_dcache busy (miss service or MMIO load)
    //   branch_count          br_commit      committed conditional branches
    //   mispredict_count      br_mispred     mispredicts among those branches
    //
    //   MMIO requests are not included in the access, hit or miss counts. Branch
    //   events are taken at commit, so wrong-path branches are never counted.
    //
    // Freeze: with run=0, every counter holds its current value. The top level
    //   drives run = rst_n_sync & ~done (PROJECT_BLUEPRINT.md D21).
    // Reset: reset_n is active low and asynchronous, and it zeroes all counters.
    //   This is the baseline convention, also used by div_unit and regfile_2r1w.
    // Overflow: a plain 32-bit add, so 0xFFFFFFFF wraps to 0 (D21).
    // Outputs: driven directly by the registers, with no combinational path
    //   from any input.
    //
    // ooo_defs.vh is not included because none of its constants are needed.
    // Written in plain Verilog-2001 with no vendor primitives.
    
    `timescale 1ns / 1ps
    module perf_counters(
        input wire clk,
        input wire reset_n,      // asynchronous, active low
        input wire run,          // count while 1 (0 after done)
        input wire commit_valid, // one instruction retired
        input wire ooo_event,    // out-of-order completion event
        input wire stall_rob,    // stall-reason pulses
        input wire stall_rs,
        input wire hold,
        input wire dc_access, // L1 data cache events (l1_dcache)
        input wire dc_hit,
        input wire dc_miss,
        input wire dc_stall,
        input wire br_commit,  // committed conditional branch
        input wire br_mispred, // ... that had been mispredicted
        output reg [31:0] cycles,
        output reg [31:0] retired,
        output reg [31:0] ooo_count,
        output reg [31:0] rob_stall_cycles,
        output reg [31:0] rs_stall_cycles,
        output reg [31:0] hold_cycles,
        output reg [31:0] dcache_access_count,
        output reg [31:0] dcache_hit_count,
        output reg [31:0] dcache_miss_count,
        output reg [31:0] dcache_stall_cycles,
        output reg [31:0] branch_count,
        output reg [31:0] mispredict_count);

always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
    cycles
    <= 32'd0;
retired <= 32'd0;
ooo_count <= 32'd0;
rob_stall_cycles <= 32'd0;
rs_stall_cycles <= 32'd0;
hold_cycles <= 32'd0;
dcache_access_count <= 32'd0;
dcache_hit_count <= 32'd0;
dcache_miss_count <= 32'd0;
dcache_stall_cycles <= 32'd0;
branch_count <= 32'd0;
mispredict_count <= 32'd0;
end else if (run) begin
        cycles <= cycles + 32'd1;
if (commit_valid)
    retired <= retired + 32'd1;
if (ooo_event)
    ooo_count <= ooo_count + 32'd1;
if (stall_rob)
    rob_stall_cycles <= rob_stall_cycles + 32'd1;
if (stall_rs)
    rs_stall_cycles <= rs_stall_cycles + 32'd1;
if (hold)
    hold_cycles <= hold_cycles + 32'd1;
if (dc_access)
    dcache_access_count <= dcache_access_count + 32'd1;
if (dc_hit)
    dcache_hit_count <= dcache_hit_count + 32'd1;
if (dc_miss)
    dcache_miss_count <= dcache_miss_count + 32'd1;
if (dc_stall)
    dcache_stall_cycles <= dcache_stall_cycles + 32'd1;
if (br_commit)
    branch_count <= branch_count + 32'd1;
if (br_mispred)
    mispredict_count <= mispredict_count + 32'd1;
end
    end

    endmodule
