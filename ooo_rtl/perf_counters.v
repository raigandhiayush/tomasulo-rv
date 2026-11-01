// perf_counters.v - performance counters for TOMA-RV (Person E)
`timescale 1ns/1ps
// Ports follow SIGNALS_REFERENCE.md section 2.16; behaviour follows
// PROJECT_BLUEPRINT.md section 6.15.
//
// Contract:
//   * Every counter is a 32-bit register that adds 1 on a rising clk edge
//     when run=1 and its event input is 1 in that cycle:
//       cycles           : every cycle while run=1
//       retired          : commit_valid
//       ooo_count        : ooo_event
//       rob_stall_cycles : stall_rob
//       rs_stall_cycles  : stall_rs
//       hold_cycles      : hold
//       dcache_access_count / dcache_hit_count / dcache_miss_count :
//                          dc_access / dc_hit / dc_miss (cacheable requests
//                          accepted by l1_dcache; MMIO is not counted)
//       dcache_stall_cycles : dc_stall (l1_dcache busy: miss service or MMIO load)
//       branch_count / mispredict_count : br_commit / br_mispred (committed
//                          conditional branches, so wrong-path ones never count)
//   * run=0 freezes all twelve counters (they keep their value).
//   * reset_n is active low and asynchronous (baseline convention, same as
//     div_unit and regfile_2r1w): clears all twelve counters to 0.
//   * Outputs are the register values (no combinational path from inputs).
//   * At 0xFFFFFFFF a counter wraps to 0 (plain 32-bit add), as decided in
//     PROJECT_BLUEPRINT.md D21. The top drives run = rst_n_sync & ~done (D21).
//
// No ooo_defs.vh constant is used, so the file does not include it.
// Pure Verilog-2001, no vendor primitives.

module perf_counters (
    input  wire        clk,
    input  wire        reset_n,          // asynchronous, active low
    input  wire        run,              // count while 1 (0 after done)
    input  wire        commit_valid,     // one instruction retired
    input  wire        ooo_event,        // out-of-order completion event
    input  wire        stall_rob,        // stall-reason pulses
    input  wire        stall_rs,
    input  wire        hold,
    input  wire        dc_access,        // L1 data cache events (l1_dcache)
    input  wire        dc_hit,
    input  wire        dc_miss,
    input  wire        dc_stall,
    input  wire        br_commit,        // committed conditional branch
    input  wire        br_mispred,       // ... that had been mispredicted
    output reg  [31:0] cycles,
    output reg  [31:0] retired,
    output reg  [31:0] ooo_count,
    output reg  [31:0] rob_stall_cycles,
    output reg  [31:0] rs_stall_cycles,
    output reg  [31:0] hold_cycles,
    output reg  [31:0] dcache_access_count,
    output reg  [31:0] dcache_hit_count,
    output reg  [31:0] dcache_miss_count,
    output reg  [31:0] dcache_stall_cycles,
    output reg  [31:0] branch_count,
    output reg  [31:0] mispredict_count
);

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            cycles           <= 32'd0;
            retired          <= 32'd0;
            ooo_count        <= 32'd0;
            rob_stall_cycles <= 32'd0;
            rs_stall_cycles  <= 32'd0;
            hold_cycles      <= 32'd0;
            dcache_access_count <= 32'd0;
            dcache_hit_count    <= 32'd0;
            dcache_miss_count   <= 32'd0;
            dcache_stall_cycles <= 32'd0;
            branch_count        <= 32'd0;
            mispredict_count    <= 32'd0;
        end else if (run) begin
            cycles <= cycles + 32'd1;
            if (commit_valid) retired          <= retired          + 32'd1;
            if (ooo_event)    ooo_count        <= ooo_count        + 32'd1;
            if (stall_rob)    rob_stall_cycles <= rob_stall_cycles + 32'd1;
            if (stall_rs)     rs_stall_cycles  <= rs_stall_cycles  + 32'd1;
            if (hold)         hold_cycles      <= hold_cycles      + 32'd1;
            if (dc_access)    dcache_access_count <= dcache_access_count + 32'd1;
            if (dc_hit)       dcache_hit_count    <= dcache_hit_count    + 32'd1;
            if (dc_miss)      dcache_miss_count   <= dcache_miss_count   + 32'd1;
            if (dc_stall)     dcache_stall_cycles <= dcache_stall_cycles + 32'd1;
            if (br_commit)    branch_count        <= branch_count + 32'd1;
            if (br_mispred)   mispredict_count    <= mispredict_count + 32'd1;
        end
    end

endmodule
