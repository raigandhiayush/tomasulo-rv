// tb_perf_counters.v - Self-checking testbench for hardware performance counters.
`timescale 1ns/1ps
module tb_perf_counters;
    reg clk = 0, reset_n;           // x until time 0, then 0: a real falling edge
    reg run = 0, commit_valid = 0, ooo_event = 0;
    reg stall_rob = 0, stall_rs = 0, hold = 0;
    wire [31:0] cycles, retired, ooo_count;
    wire [31:0] rob_stall_cycles, rs_stall_cycles, hold_cycles;
    // L1 data cache events: random in every cycle() (0 outside it)
    reg dc_access = 0, dc_hit = 0, dc_miss = 0, dc_stall = 0;
    reg br_commit = 0, br_mispred = 0;
    wire [31:0] branch_count, mispredict_count;
    wire [31:0] dcache_access_count, dcache_hit_count, dcache_miss_count, dcache_stall_cycles;

    perf_counters dut (
        .clk(clk), .reset_n(reset_n),
        .run(run), .commit_valid(commit_valid), .ooo_event(ooo_event),
        .stall_rob(stall_rob), .stall_rs(stall_rs), .hold(hold),
        .dc_access(dc_access), .dc_hit(dc_hit), .dc_miss(dc_miss), .dc_stall(dc_stall),
        .br_commit(br_commit), .br_mispred(br_mispred),
        .cycles(cycles), .retired(retired), .ooo_count(ooo_count),
        .rob_stall_cycles(rob_stall_cycles), .rs_stall_cycles(rs_stall_cycles),
        .hold_cycles(hold_cycles),
        .dcache_access_count(dcache_access_count), .dcache_hit_count(dcache_hit_count),
        .dcache_miss_count(dcache_miss_count), .dcache_stall_cycles(dcache_stall_cycles),
        .branch_count(branch_count), .mispredict_count(mispredict_count));

    always #5 clk = ~clk;

    // testbench count (reference model), one per counter
    reg [31:0] m_cycles, m_retired, m_ooo, m_rob, m_rs, m_hold;
    reg [31:0] m_dacc, m_dhit, m_dmiss, m_dstall, m_brc, m_brm;
    integer    cov_dc = 0;      // cache events counted while run=1
    integer pass = 0, fail = 0;
    integer j;

    task check;
        input [31:0] got, exp;
        input [8*24-1:0] what;
        begin
            if (got === exp) pass = pass + 1;
            else begin
                fail = fail + 1;
                if (fail <= 20)
                    $display("TEST_FAIL perf_counters %0s: got %h exp %h t=%0t",
                             what, got, exp, $time);
            end
        end
    endtask

    task check_all;
        begin
            check(cycles,           m_cycles,  "cycles");
            check(retired,          m_retired, "retired");
            check(ooo_count,        m_ooo,     "ooo_count");
            check(rob_stall_cycles, m_rob,     "rob_stall_cycles");
            check(rs_stall_cycles,  m_rs,      "rs_stall_cycles");
            check(hold_cycles,      m_hold,    "hold_cycles");
            check(dcache_access_count, m_dacc,   "dcache_access_count");
            check(dcache_hit_count,    m_dhit,   "dcache_hit_count");
            check(dcache_miss_count,   m_dmiss,  "dcache_miss_count");
            check(dcache_stall_cycles, m_dstall, "dcache_stall_cycles");
            check(branch_count,        m_brc,    "branch_count");
            check(mispredict_count,    m_brm,    "mispredict_count");
        end
    endtask

    task model_clear;
        begin
            m_cycles = 0; m_retired = 0; m_ooo = 0; m_rob = 0; m_rs = 0; m_hold = 0;
            m_dacc = 0; m_dhit = 0; m_dmiss = 0; m_dstall = 0; m_brc = 0; m_brm = 0;
        end
    endtask

    // coverage of the cases that matter
    integer cov_run_ev   = 0;   // run=1 with each event input high, summed
    integer cov_frz_ev   = 0;   // run=0 with at least one event input high
    integer cov_all_ev   = 0;   // run=1 and all five event inputs high together
    integer cov_wrap     = 0;   // counters observed wrapping 0xFFFFFFFF -> 0
    integer cov_reset    = 0;   // asynchronous resets applied mid-cycle

    // One clock cycle: drive inputs after the falling edge, let the rising
    // edge happen, update the model, then check all outputs 1 ns later.
    task cycle;
        input r, cv, oe, sb, ss, h;
        begin
            @(negedge clk);
            run = r; commit_valid = cv; ooo_event = oe;
            stall_rob = sb; stall_rs = ss; hold = h;
            dc_access = $random; dc_hit = $random; dc_miss = $random; dc_stall = $random;
            br_commit = $random; br_mispred = $random;
            @(posedge clk);
            if (reset_n && r) begin
                if (dc_access) m_dacc   = m_dacc   + 1;
                if (dc_hit)    m_dhit   = m_dhit   + 1;
                if (dc_miss)   m_dmiss  = m_dmiss  + 1;
                if (dc_stall)  m_dstall = m_dstall + 1;
                if (br_commit)  m_brc = m_brc + 1;
                if (br_mispred) m_brm = m_brm + 1;
                cov_dc = cov_dc + dc_access + dc_hit + dc_miss + dc_stall;
                m_cycles = m_cycles + 1;
                if (cv) m_retired = m_retired + 1;
                if (oe) m_ooo     = m_ooo + 1;
                if (sb) m_rob     = m_rob + 1;
                if (ss) m_rs      = m_rs + 1;
                if (h)  m_hold    = m_hold + 1;
                cov_run_ev = cov_run_ev + cv + oe + sb + ss + h;
                if (cv && oe && sb && ss && h) cov_all_ev = cov_all_ev + 1;
            end
            if (reset_n && !r && (cv | oe | sb | ss | h)) cov_frz_ev = cov_frz_ev + 1;
            #1;
            check_all;
            dc_access = 0; dc_hit = 0; dc_miss = 0; dc_stall = 0; br_commit = 0; br_mispred = 0;
        end
    endtask

    // Asynchronous reset in the middle of a cycle: outputs must clear before
    // the next clock edge, and stay 0 for edges while reset_n is low.
    task async_reset;
        input integer low_cycles;
        integer k;
        begin
            @(negedge clk); #2;
            reset_n = 0; model_clear;
            #1;                                    // still before the posedge
            check_all;
            cov_reset = cov_reset + 1;
            for (k = 0; k < low_cycles; k = k + 1)
                cycle(1, 1, 1, 1, 1, 1);           // all events high, reset wins
            @(negedge clk); #2;
            run = 0; reset_n = 1;                  // release away from an edge, run low over the next edge
        end
    endtask

    // Load every counter near the top so rollover is reachable in a few
    // cycles. Hierarchical write into the DUT register (the design file is
    // not changed); done on the falling edge, away from the counting edge.
    task preload;
        input [31:0] v;
        begin
            @(negedge clk);
            run = 0;                    // run low over the edge before the next cycle()
            dut.cycles = v; dut.retired = v; dut.ooo_count = v;
            dut.rob_stall_cycles = v; dut.rs_stall_cycles = v; dut.hold_cycles = v;
            m_cycles = v; m_retired = v; m_ooo = v; m_rob = v; m_rs = v; m_hold = v;
            dut.dcache_access_count = v; dut.dcache_hit_count = v;
            dut.dcache_miss_count = v;   dut.dcache_stall_cycles = v;
            m_dacc = v; m_dhit = v; m_dmiss = v; m_dstall = v;
            dut.branch_count = v; dut.mispredict_count = v; m_brc = v; m_brm = v;
            #1;
            check_all;
        end
    endtask

    // Load each counter with its own value (independence and per-bit carry).
    task preload6;
        input [31:0] v0, v1, v2, v3, v4, v5;
        begin
            @(negedge clk);
            run = 0;
            dut.cycles = v0; dut.retired = v1; dut.ooo_count = v2;
            dut.rob_stall_cycles = v3; dut.rs_stall_cycles = v4; dut.hold_cycles = v5;
            m_cycles = v0; m_retired = v1; m_ooo = v2; m_rob = v3; m_rs = v4; m_hold = v5;
            #1;
            check_all;
        end
    endtask

    integer cov_combo  = 0;     // input combinations {run, 5 events} applied (all 64, twice)
    integer cov_carry  = 0;     // carry positions checked (31 per counter)
    integer cov_glitch = 0;     // pulses between edges that must not count
    integer w, c, b;
    reg [5:0] cmb;

    initial begin
        reset_n = 0; model_clear;

        // 1. power-up in reset: outputs 0, clock edges do not count
        #1; check_all;
        for (j = 0; j < 4; j = j + 1) cycle(1, 1, 1, 1, 1, 1);
        @(negedge clk); #2; run = 0; reset_n = 1;  // run low over the next edge

        // 2. run=0 after reset: nothing counts even with every event high
        for (j = 0; j < 5; j = j + 1) cycle(0, 1, 1, 1, 1, 1);

        // 3. increment, one input at a time: only its counter (and cycles) moves
        for (j = 0; j < 3; j = j + 1) begin
            cycle(1, 0, 0, 0, 0, 0);
            cycle(1, 1, 0, 0, 0, 0);
            cycle(1, 0, 1, 0, 0, 0);
            cycle(1, 0, 0, 1, 0, 0);
            cycle(1, 0, 0, 0, 1, 0);
            cycle(1, 0, 0, 0, 0, 1);
        end
        // all events in one cycle, back to back
        for (j = 0; j < 10; j = j + 1) cycle(1, 1, 1, 1, 1, 1);
        // explicit values after step 3: 3*6 + 10 cycles, 3 + 10 of each event
        check(cycles,  32'd28, "cycles after inc");
        check(retired, 32'd13, "retired after inc");
        check(hold_cycles, 32'd13, "hold after inc");

        // 4. run=0 freezes all, then counting resumes from the frozen value
        for (j = 0; j < 20; j = j + 1) cycle(0, $random, $random, $random, $random, $random);
        cycle(1, 1, 0, 0, 0, 0);
        check(cycles, 32'd29, "cycles resume");

        // 5. asynchronous reset mid-run clears all; first cycle after release counts
        async_reset(3);
        cycle(1, 1, 1, 0, 0, 0);
        check(cycles,  32'd1, "cycles 1st after rst");
        check(retired, 32'd1, "retired 1st after rst");

        // 6. 1,000 random cycles (blueprint 6.15), run high ~3/4 of the time
        for (j = 0; j < 1000; j = j + 1)
            cycle(($random & 3) != 0, $random, $random, $random, $random, $random);

        // 7. rollover: each counter goes 0xFFFFFFFE -> 0xFFFFFFFF -> 0 -> 1
        preload(32'hFFFF_FFFE);
        for (j = 0; j < 3; j = j + 1) cycle(1, 1, 1, 1, 1, 1);
        check(cycles, 32'd1, "cycles wrapped");
        if (cycles == 32'd1 && retired == 32'd1 && hold_cycles == 32'd1) cov_wrap = cov_wrap + 6;
        //    run=0 at 0xFFFFFFFF holds (does not wrap)
        preload(32'hFFFF_FFFF);
        for (j = 0; j < 4; j = j + 1) cycle(0, 1, 1, 1, 1, 1);
        //    one event only wraps only that counter (cycles wraps too)
        cycle(1, 0, 0, 0, 0, 1);
        check(hold_cycles, 32'd0, "hold wrapped alone");
        check(retired, 32'hFFFF_FFFF, "retired held");

        // 8. reset after rollover, then a second 1,000-cycle random run with
        //    random asynchronous resets in it
        async_reset(1);
        for (j = 0; j < 1000; j = j + 1) begin
            w = $random & 255;
            if (w == 0) async_reset(($random & 3));
            else cycle(($random & 3) != 0, $random, $random, $random, $random, $random);
        end

        // 9. every combination of {run, commit_valid, ooo_event, stall_rob,
        //    stall_rs, hold}: 64 combinations, in increasing then decreasing
        //    order, so each counter is checked against every other input
        async_reset(0);
        for (c = 0; c < 128; c = c + 1) begin
            cmb = (c < 64) ? c[5:0] : 6'd63 - c[5:0];
            cycle(cmb[5], cmb[0], cmb[1], cmb[2], cmb[3], cmb[4]);
            cov_combo = cov_combo + 1;
        end
        //    explicit totals: run=1 in 64 of 128 cycles; each event is 1 in
        //    half of those 64
        check(cycles,           32'd64, "combo cycles");
        check(retired,          32'd32, "combo retired");
        check(ooo_count,        32'd32, "combo ooo_count");
        check(rob_stall_cycles, 32'd32, "combo rob_stall");
        check(rs_stall_cycles,  32'd32, "combo rs_stall");
        check(hold_cycles,      32'd32, "combo hold");

        // 10. no carry-over: events seen while run=0 are not counted later
        async_reset(0);
        for (j = 0; j < 5; j = j + 1) cycle(0, 1, 1, 1, 1, 1);
        cycle(1, 0, 0, 0, 0, 0);
        check(cycles,  32'd1, "carryover cycles");
        check(retired, 32'd0, "carryover retired");
        check(hold_cycles, 32'd0, "carryover hold");

        // 11. carry into every bit: each counter at 2^k - 1 steps to 2^k
        //     (k = 1..31), including 0x7FFFFFFF -> 0x80000000
        for (b = 1; b < 32; b = b + 1) begin
            preload6((32'd1 << b) - 1, (32'd1 << b) - 1, (32'd1 << b) - 1,
                     (32'd1 << b) - 1, (32'd1 << b) - 1, (32'd1 << b) - 1);
            cycle(1, 1, 1, 1, 1, 1);
            check(cycles, 32'd1 << b, "carry cycles");
            check(hold_cycles, 32'd1 << b, "carry hold");
            cov_carry = cov_carry + 6;
        end

        // 12. independence: each counter wraps alone while the others hold
        //     their own different values
        for (c = 1; c < 6; c = c + 1) begin
            preload6(32'h0000_1000,
                     (c == 1) ? 32'hFFFF_FFFF : 32'h1111_1111,
                     (c == 2) ? 32'hFFFF_FFFF : 32'h2222_2222,
                     (c == 3) ? 32'hFFFF_FFFF : 32'h3333_3333,
                     (c == 4) ? 32'hFFFF_FFFF : 32'h4444_4444,
                     (c == 5) ? 32'hFFFF_FFFF : 32'h5555_5555);
            cycle(1, c == 1, c == 2, c == 3, c == 4, c == 5);
            cov_wrap = cov_wrap + 1;
        end
        //     cycles wraps alone (no event inputs)
        preload6(32'hFFFF_FFFF, 32'h1111_1111, 32'h2222_2222,
                 32'h3333_3333, 32'h4444_4444, 32'h5555_5555);
        cycle(1, 0, 0, 0, 0, 0);
        check(cycles, 32'd0, "cycles wrapped alone");
        check(retired, 32'h1111_1111, "retired kept");
        cov_wrap = cov_wrap + 1;

        // 13. pulses between clock edges are not counted (inputs are sampled
        //     only at the rising edge); run dropping between edges does not
        //     stop a count when it is 1 at the edge
        async_reset(0);
        for (j = 0; j < 10; j = j + 1) begin
            @(negedge clk);
            run = 0; commit_valid = 0; ooo_event = 0; stall_rob = 0; stall_rs = 0; hold = 0;
            #1; run = 1; commit_valid = 1; ooo_event = 1; stall_rob = 1; stall_rs = 1; hold = 1;
            #2; run = 0; commit_valid = 0; ooo_event = 0; stall_rob = 0; stall_rs = 0; hold = 0;
            @(posedge clk); #1;
            check_all;                                 // still all 0
            cov_glitch = cov_glitch + 1;
        end
        for (j = 0; j < 10; j = j + 1) begin
            @(negedge clk);
            run = 0; #1; run = 1; commit_valid = 1;   // run glitches low, then 1 at the edge
            @(posedge clk);
            m_cycles = m_cycles + 1; m_retired = m_retired + 1;
            #1; check_all;
        end
        check(cycles, 32'd10, "glitch cycles");

        // 14. reset_n falling at the same instant as a rising clock edge with
        //     every input 1: reset wins, all 0
        @(negedge clk);
        run = 1; commit_valid = 1; ooo_event = 1; stall_rob = 1; stall_rs = 1; hold = 1;
        @(posedge clk) reset_n = 0;
        model_clear;
        #1; check_all;
        cov_reset = cov_reset + 1;
        @(negedge clk); #2; run = 0; reset_n = 1;
        cycle(1, 1, 1, 1, 1, 1);                        // counts 1 after release

        // 15. a 1 ns reset pulse between edges clears everything
        for (j = 0; j < 7; j = j + 1) cycle(1, 1, 0, 1, 0, 1);
        @(negedge clk); #2;
        reset_n = 0; #1; reset_n = 1; model_clear;
        #1; check_all;
        cov_reset = cov_reset + 1;
        run = 0;                                        // run low over the next edge
        cycle(1, 0, 1, 0, 1, 0);

        // 16. long runs: 100,000 cycles with every input 1 (exact totals),
        //     then 10,000 cycles with run toggling every cycle
        async_reset(0);
        for (j = 0; j < 100000; j = j + 1) cycle(1, 1, 1, 1, 1, 1);
        check(cycles,          32'd100000, "long cycles");
        check(rs_stall_cycles, 32'd100000, "long rs_stall");
        for (j = 0; j < 10000; j = j + 1) cycle(j & 1, 1, 1, 1, 1, 1);
        check(ooo_count, 32'd105000, "toggle ooo_count");

        $display("coverage: run_events=%0d frozen_events=%0d all_events=%0d wraps=%0d async_resets=%0d combos=%0d carries=%0d glitches=%0d dcache_events=%0d",
                 cov_run_ev, cov_frz_ev, cov_all_ev, cov_wrap, cov_reset, cov_combo, cov_carry, cov_glitch, cov_dc);
        if (cov_run_ev < 2000 || cov_frz_ev < 200 || cov_all_ev < 30 || cov_wrap < 12 || cov_reset < 6
            || cov_combo != 128 || cov_carry != 186 || cov_glitch != 10 || cov_dc < 2000) begin
            fail = fail + 1;
            $display("TEST_FAIL perf_counters coverage below minimum");
        end
        if (fail == 0) $display("TEST_PASS perf_counters %0d", pass);
        else           $display("TEST_FAIL perf_counters %0d failed, %0d passed", fail, pass);
        $finish;
    end
endmodule
