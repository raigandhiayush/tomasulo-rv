// tb_instr_queue.v -- self-checking testbench for instr_queue (owner D).
// Blueprint §6.3: fill to 4, push-when-full ignored (and flagged), empty pop,
// push+pop at 0..4 entries, flush (+ simultaneous push), no bypass (D5),
// async reset, and 10,000 random cycles against a software queue model.
//
// Model choices (from the spec):
//   * flush wins over push and pop; queue is empty after the edge.
//   * "full"/"empty" are judged on start-of-cycle occupancy, so a push at
//     count==DEPTH is dropped even if a pop happens in the same cycle.
//   * a pushed entry becomes visible on out_* only in the next cycle.
// Prints TEST_PASS instr_queue <n> or TEST_FAIL ... with cycle/expected/actual.
`timescale 1ns/1ps
`include "ooo_defs.vh"

module tb_instr_queue #(
    parameter DEPTH = 4            // override with: vvp ... or iverilog -Ptb_instr_queue.DEPTH=8
);
    localparam CW = $clog2(DEPTH + 1);   // width needed to hold 0..DEPTH

    reg         clk = 0, reset_n = 0;
    reg         flush = 0, push = 0, pop = 0;
    reg  [31:0] in_pc = 0, in_inst = 0;
    wire        out_valid;
    wire [31:0] out_pc, out_inst;
    wire [CW-1:0] count, free_slots;

    instr_queue #(.DEPTH(DEPTH)) dut (
        .clk(clk), .reset_n(reset_n), .flush(flush), .push(push),
        .in_pc(in_pc), .in_inst(in_inst), .pop(pop),
        .out_valid(out_valid), .out_pc(out_pc), .out_inst(out_inst),
        .count(count), .free_slots(free_slots));

    always #5 clk = ~clk;

    // ---------------- software model ----------------
    reg [31:0] m_pc   [0:DEPTH-1];
    reg [31:0] m_inst [0:DEPTH-1];
    integer    m_cnt;
    integer    i;

    task model_reset; begin m_cnt = 0; end endtask

    task model_step; // call at the clock edge with the inputs of this cycle
        integer k;
        begin
            if (flush) m_cnt = 0;
            else begin
                if (pop && m_cnt > 0) begin
                    for (k = 0; k < DEPTH-1; k = k + 1) begin
                        m_pc[k] = m_pc[k+1]; m_inst[k] = m_inst[k+1];
                    end
                    if (push && m_cnt < DEPTH) begin   // m_cnt before pop < DEPTH
                        m_pc[m_cnt-1] = in_pc; m_inst[m_cnt-1] = in_inst;
                    end else m_cnt = m_cnt - 1;
                end else if (push && m_cnt < DEPTH) begin
                    m_pc[m_cnt] = in_pc; m_inst[m_cnt] = in_inst;
                    m_cnt = m_cnt + 1;
                end
            end
        end
    endtask

    // ---------------- checking ----------------
    integer cyc = 0, nvec = 0, nfail = 0, dropped_pushes = 0;

    task fail(input [8*40-1:0] what, input [31:0] exp, input [31:0] act);
        begin
            nfail = nfail + 1;
            $display("TEST_FAIL instr_queue cycle=%0d %0s expected=%h actual=%h",
                     cyc, what, exp, act);
        end
    endtask

    task check_outputs;
        begin
            nvec = nvec + 1;
            if (out_valid !== (m_cnt != 0))          fail("out_valid", m_cnt != 0, out_valid);
            if (count     !== m_cnt[CW-1:0])            fail("count", m_cnt, count);
            if (free_slots!== ((DEPTH - m_cnt) & ((1 << CW) - 1)))       fail("free_slots", DEPTH - m_cnt, free_slots);
            if (m_cnt != 0) begin
                if (out_pc   !== m_pc[0])            fail("out_pc", m_pc[0], out_pc);
                if (out_inst !== m_inst[0])          fail("out_inst", m_inst[0], out_inst);
            end else begin
                // RTL drives 0 when empty; X would be a real problem downstream
                if (^out_pc === 1'bx || ^out_inst === 1'bx) fail("out_* is X when empty", 0, out_pc);
            end
        end
    endtask

    // one clock cycle with the given inputs; checks state seen during the cycle
    reg [31:0] seq = 32'h1000;
    task cycle(input f, input pu, input po);
        begin
            @(negedge clk);
            flush = f; push = pu; pop = po;
            in_pc = seq; in_inst = 32'hA5000000 ^ seq;
            #1 check_outputs;                // no-bypass: outputs must not reflect this push
            if (pu && !f && m_cnt == DEPTH) dropped_pushes = dropped_pushes + 1;
            @(posedge clk); model_step;
            if (pu) seq = seq + 4;
            cyc = cyc + 1;
        end
    endtask

    integer r, n;
    initial begin
        model_reset;
        // port width must be exactly clog2(DEPTH+1): 3 bits for DEPTH=4 (iface-v1)
        if ($bits(count) != CW || $bits(free_slots) != CW || (DEPTH == 4 && CW != 3)) begin
            nfail = nfail + 1;
            $display("TEST_FAIL instr_queue port width expected=%0d actual=%0d", CW, $bits(count));
        end
        repeat (2) @(posedge clk);
        #2 reset_n = 1;

        // 1. empty: pop on empty does nothing
        cycle(0,0,1); cycle(0,0,0);
        // 2. fill to 4, then push while full (must be ignored)
        for (n = 0; n < DEPTH; n = n + 1) cycle(0,1,0);
        cycle(0,1,0);   // dropped
        cycle(0,1,0);   // dropped
        if (dropped_pushes != 2) begin
            nfail = nfail + 1;
            $display("TEST_FAIL instr_queue cycle=%0d push-when-full count expected=2 actual=%0d", cyc, dropped_pushes);
        end
        // 3. push+pop simultaneously at 4 (push dropped, pop happens)
        cycle(0,1,1);
        // 4. drain, then push+pop at each occupancy 0..DEPTH-1
        for (n = 0; n < DEPTH; n = n + 1) cycle(0,0,1);
        cycle(0,1,1);                               // at 0: push only (pop on empty)
        for (n = 1; n < DEPTH; n = n + 1) begin
            cycle(0,1,1);                           // push+pop at occupancy n
            cycle(0,1,0);                           // grow to n+1
        end
        cycle(0,1,1);                               // at DEPTH (full): pop only
        // 5. pointer wrap-around: many push+pop pairs
        for (n = 0; n < 9; n = n + 1) cycle(0,1,1);
        // 6. flush with simultaneous push and pop
        cycle(1,1,1); cycle(0,0,0);
        // 7. flush when empty, then refill (pointers restart cleanly)
        cycle(1,0,0); cycle(0,1,0); cycle(0,1,0); cycle(0,0,1);
        // 8. async reset in the middle of a cycle
        cycle(0,1,0);
        @(negedge clk); flush = 0; push = 0; pop = 0;
        #2 reset_n = 0; #1;
        model_reset; check_outputs;
        #1 reset_n = 1;
        cycle(0,1,0); cycle(0,0,1);

        // 9. 10,000 random cycles
        for (n = 0; n < 10000; n = n + 1) begin
            r = $urandom % 100;
            cycle(r < 3, ($urandom % 100) < 60, ($urandom % 100) < 50);
        end

        if (nfail == 0) $display("TEST_PASS instr_queue %0d (DEPTH=%0d)", nvec, DEPTH);
        else            $display("TEST_FAIL instr_queue %0d failures out of %0d checks", nfail, nvec);
        $finish;
    end
endmodule
