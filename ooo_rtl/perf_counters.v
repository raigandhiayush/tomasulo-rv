// perf_counters.v - Hardware performance counters for TOMA-RV.
`timescale 1ns/1ps
// 32-bit event counters active while run=1.

module perf_counters (
    input  wire        clk,
    input  wire        reset_n,          // asynchronous, active low
    input  wire        run,              // count while 1 (0 after done)
    input  wire        commit_valid,     // one instruction retired
    input  wire        ooo_event,        // out-of-order completion event
    input  wire        stall_rob,        // stall-reason pulses
    input  wire        stall_rs,
    input  wire        hold,
    output reg  [31:0] cycles,
    output reg  [31:0] retired,
    output reg  [31:0] ooo_count,
    output reg  [31:0] rob_stall_cycles,
    output reg  [31:0] rs_stall_cycles,
    output reg  [31:0] hold_cycles
);

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            cycles           <= 32'd0;
            retired          <= 32'd0;
            ooo_count        <= 32'd0;
            rob_stall_cycles <= 32'd0;
            rs_stall_cycles  <= 32'd0;
            hold_cycles      <= 32'd0;
        end else if (run) begin
            cycles <= cycles + 32'd1;
            if (commit_valid) retired          <= retired          + 32'd1;
            if (ooo_event)    ooo_count        <= ooo_count        + 32'd1;
            if (stall_rob)    rob_stall_cycles <= rob_stall_cycles + 32'd1;
            if (stall_rs)     rs_stall_cycles  <= rs_stall_cycles  + 32'd1;
            if (hold)         hold_cycles      <= hold_cycles      + 32'd1;
        end
    end

endmodule
