`timescale 1ns/1ps
`include "ooo_defs.vh"
// tb_ooo_frontend.v - Self-checking testbench for instruction fetch, queuing, and branch redirects.
module tb_ooo_frontend;

    localparam [31:0] KEY = 32'hABCD_0000;   // fake instruction = pc ^ KEY

    reg         clk, reset_n;
    reg  [31:0] imem_data;
    wire [31:0] imem_addr;

    reg         redirect_valid, hold_set, br_valid, br_taken;
    reg  [31:0] redirect_pc, br_target;
    reg         fq_pop;

    wire        fq_valid, hold;
    wire [31:0] fq_pc, fq_inst;

    ooo_frontend dut (
        .clk(clk), .reset_n(reset_n),
        .imem_data(imem_data), .imem_addr(imem_addr),
        .redirect_valid(redirect_valid), .redirect_pc(redirect_pc),
        .hold_set(hold_set),
        .br_valid(br_valid), .br_taken(br_taken), .br_target(br_target),
        .fq_pop(fq_pop),
        .fq_valid(fq_valid), .fq_pc(fq_pc), .fq_inst(fq_inst),
        .hold(hold)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    // instruction memory model: registered read, one cycle late, like instr_mem
    always @(posedge clk)
        imem_data <= imem_addr ^ KEY;

    integer n_pass, n_fail;
    integer cyc;          // free-running cycle count, used for "every third"
    integer pops;         // instructions consumed in the current test
    integer max_count;    // highest queue occupancy seen
    integer t;
    reg [31:0] exp_pc;    // PC the next popped instruction must carry
    reg [31:0] pc_a, pc_b;
    reg        hold_must_be_0;   // T0-T5 never drive hold_set

    // ---- cycle-accurate reference model of the spec (used by T12) ----
    // Rules it follows: fetch only if free_slots > in-flight; data arrives one
    // cycle late and is pushed with its PC; push into a full queue is ignored;
    // redirect (JAL, or taken branch/JALR) flushes the queue, drops the
    // in-flight fetch and loads the target; hold set by hold_set, cleared by
    // br_valid. Every cycle the DUT's outputs must equal the model's.
    reg [31:0] m_q [0:3];        // model queue, m_q[0] = head
    integer    m_cnt;
    reg [31:0] m_fpc, m_ppc;
    reg        m_pend, m_hold;
    integer    seed, i, r, kind, fails_shown, cnt_start;
    reg        r_pop, r_rv, r_hs, r_bv, r_bt, m_redirect, m_push, m_canf;
    reg [31:0] r_rpc, r_btgt, m_npc;

    task pass_or_fail;
        input [8*48:1] name;
        input          ok;
        begin
            if (ok) n_pass = n_pass + 1;
            else begin
                n_fail = n_fail + 1;
                $display("TEST_FAIL ooo_frontend [%0s] at t=%0t", name, $time);
            end
        end
    endtask

    // checks that run every cycle, whatever the test is doing
    task every_cycle_checks;
        begin
            if (dut.queue.count > max_count) max_count = dut.queue.count;
            // back-pressure: a push into a full queue would lose an instruction
            if (dut.push && dut.queue.count >= 4)
                pass_or_fail("never push into a full queue", 1'b0);
            if (hold_must_be_0 && hold !== 1'b0)
                pass_or_fail("hold stays 0 (no branches yet)", 1'b0);
        end
    endtask

    // dispatch consumes the head now: it must be exactly the next expected one
    task check_pop;
        begin
            pass_or_fail("popped head is valid",              fq_valid === 1'b1);
            pass_or_fail("popped PC is the next in sequence", fq_pc === exp_pc);
            pass_or_fail("popped word matches its PC",        fq_inst === (exp_pc ^ KEY));
            if (fq_pc !== exp_pc || fq_inst !== (exp_pc ^ KEY))
                $display("    expected pc=%h inst=%h, got pc=%h inst=%h",
                         exp_pc, exp_pc ^ KEY, fq_pc, fq_inst);
            exp_pc = exp_pc + 4;
            pops   = pops + 1;
        end
    endtask

    // -----------------------------------------------------------------------
    // one precisely controlled cycle: drive dispatch / resolve signals for
    // this cycle, let the clock edge happen, then drop all the pulses again.
    // Called just after an edge; returns just after the next edge.
    // -----------------------------------------------------------------------
    task cyc_ctl;
        input        do_pop;
        input        rv;          // redirect_valid (JAL at dispatch)
        input [31:0] rpc;
        input        hs;          // hold_set (branch / JALR dispatched)
        input        bv;          // br_valid
        input        bt;          // br_taken
        input [31:0] btgt;
        begin
            every_cycle_checks;
            if (do_pop) check_pop;
            fq_pop         = do_pop;
            redirect_valid = rv;   redirect_pc = rpc;
            hold_set       = hs;
            br_valid       = bv;   br_taken    = bt;   br_target = btgt;
            @(posedge clk); #1;
            cyc = cyc + 1;
            fq_pop = 1'b0;  redirect_valid = 1'b0;  hold_set = 1'b0;
            br_valid = 1'b0;  br_taken = 1'b0;
        end
    endtask

    task tick;      // a cycle where dispatch does nothing
        begin
            cyc_ctl(1'b0, 1'b0, 32'h0, 1'b0, 1'b0, 1'b0, 32'h0);
        end
    endtask

    // -----------------------------------------------------------------------
    // free-running dispatch for 'ncyc' cycles:
    //   mode 0 = never pop, 1 = pop every cycle, 3 = pop every third cycle
    // -----------------------------------------------------------------------
    task run;
        input integer mode;
        input integer ncyc;
        integer c;
        reg do_pop;
        begin
            for (c = 0; c < ncyc; c = c + 1) begin
                do_pop = fq_valid &&
                         ((mode == 1) || (mode == 3 && (cyc % 3 == 0)));
                cyc_ctl(do_pop, 1'b0, 32'h0, 1'b0, 1'b0, 1'b0, 32'h0);
            end
        end
    endtask

    task do_reset;
        begin
            fq_pop = 1'b0;  redirect_valid = 1'b0;  hold_set = 1'b0;
            br_valid = 1'b0;  br_taken = 1'b0;
            reset_n = 1'b0;
            #2 reset_n = 1'b1;
            exp_pc = `RESET_PC;
            pops = 0;  max_count = 0;
        end
    endtask

    // -----------------------------------------------------------------------
    initial begin
        n_pass = 0;  n_fail = 0;  cyc = 0;  pops = 0;  max_count = 0;
        hold_must_be_0 = 1'b1;
        reset_n        = 1'b0;
        imem_data      = 32'h0;
        redirect_valid = 1'b0;  redirect_pc = 32'h0;
        hold_set       = 1'b0;
        br_valid       = 1'b0;  br_taken = 1'b0;  br_target = 32'h0;
        fq_pop         = 1'b0;

        // ================= 16 Oct =================

        // ---------------- T0: reset ----------------
        repeat (2) @(posedge clk);
        #1;
        pass_or_fail("T0 imem_addr = 0 in reset",  imem_addr === `RESET_PC);
        pass_or_fail("T0 queue empty in reset",    fq_valid  === 1'b0);
        pass_or_fail("T0 hold = 0 in reset",       hold      === 1'b0);
        reset_n = 1'b1;
        exp_pc  = `RESET_PC;

        // ---------------- T1: pop every cycle ----------------
        pops = 0;
        run(1, 40);
        // fetch -> queue -> dispatch takes 2 cycles, then one per cycle
        pass_or_fail("T1 about one instruction per cycle", pops >= 35);
        if (pops < 35) $display("    only %0d pops in 40 cycles", pops);

        // ---------------- T2: pop every third cycle ----------------
        pops = 0;
        run(3, 60);
        pass_or_fail("T2 slow dispatch still drains", pops >= 18);

        // ---------------- T3: no pops, queue fills ----------------
        pops = 0;  max_count = 0;
        run(0, 15);
        pass_or_fail("T3 queue fills to exactly 4", dut.queue.count == 4);
        pass_or_fail("T3 never above 4",            max_count <= 4);
        pass_or_fail("T3 head still the oldest",    fq_valid === 1'b1 && fq_pc === exp_pc);
        pc_a = imem_addr;
        run(0, 5);
        pc_b = imem_addr;
        pass_or_fail("T3 fetch_pc stops moving",       pc_a === pc_b);
        pass_or_fail("T3 nothing in flight when full", dut.fetch_pending === 1'b0);

        // ---------------- T4: resume ----------------
        pops = 0;
        run(1, 30);
        pass_or_fail("T4 resumes after back-pressure", pops >= 25);

        // ---------------- T5: reset mid-run ----------------
        #2 reset_n = 1'b0;
        fq_pop = 1'b0;
        #1;
        pass_or_fail("T5 reset empties the queue at once", fq_valid  === 1'b0);
        pass_or_fail("T5 reset puts fetch_pc back to 0",   imem_addr === `RESET_PC);
        @(posedge clk); #1;
        reset_n = 1'b1;
        exp_pc  = `RESET_PC;
        pops = 0;
        run(1, 20);
        pass_or_fail("T5 restarts from PC 0 and runs", pops >= 15);

        // ================= 17 Oct =================
        hold_must_be_0 = 1'b0;

        // ---------------- T6: hold + NOT-taken branch ----------------
        do_reset;
        repeat (3) tick;                                    // let the queue fill
        // dispatch takes the branch at PC 0 and raises hold_set
        cyc_ctl(1'b1, 1'b0, 32'h0, 1'b1, 1'b0, 1'b0, 32'h0);
        pass_or_fail("T6 hold = 1 the cycle after hold_set", hold === 1'b1);
        repeat (6) tick;                                    // branch not resolved yet
        pass_or_fail("T6 hold stays 1 until resolve",       hold === 1'b1);
        pass_or_fail("T6 fetch keeps filling during hold",  dut.queue.count == 4);
        // resolves NOT taken
        cyc_ctl(1'b0, 1'b0, 32'h0, 1'b0, 1'b1, 1'b0, 32'h0000_0BAD);
        pass_or_fail("T6 not-taken clears hold",            hold === 1'b0);
        pass_or_fail("T6 not-taken flushes nothing",        dut.queue.count == 4);
        pass_or_fail("T6 head is the instr after the branch",
                     fq_valid === 1'b1 && fq_pc === exp_pc);
        pops = 0;
        run(1, 12);
        pass_or_fail("T6 sequence carries on after resolve", pops >= 8);

        // ---------------- T7: taken branch ----------------
        do_reset;
        repeat (3) tick;
        cyc_ctl(1'b1, 1'b0, 32'h0, 1'b1, 1'b0, 1'b0, 32'h0);   // branch at PC 0
        repeat (3) tick;                                       // wrong path fills in
        pass_or_fail("T7 hold = 1 before resolve",          hold === 1'b1);
        // cycle X: resolves TAKEN to 0x100
        cyc_ctl(1'b0, 1'b0, 32'h0, 1'b0, 1'b1, 1'b1, 32'h0000_0100);
        // now in X+1
        pass_or_fail("T7 hold cleared by the resolve",      hold === 1'b0);
        pass_or_fail("T7 queue flushed",                    fq_valid === 1'b0);
        pass_or_fail("T7 target fetched in X+1",            imem_addr === 32'h0000_0100);
        tick;                                               // X+2: target being queued
        pass_or_fail("T7 nothing from the wrong path in X+2", fq_valid === 1'b0);
        tick;                                               // X+3
        pass_or_fail("T7 target dispatchable at X+3",
                     fq_valid === 1'b1 && fq_pc === 32'h0000_0100);
        exp_pc = 32'h0000_0100;
        pops = 0;
        run(1, 12);
        pass_or_fail("T7 sequence continues from target",   pops >= 8);

        // ---------------- T8: JAL redirect at dispatch ----------------
        do_reset;
        repeat (3) tick;
        // cycle D: dispatch pops the JAL at PC 0 and redirects to 0x200
        cyc_ctl(1'b1, 1'b1, 32'h0000_0200, 1'b0, 1'b0, 1'b0, 32'h0);
        pass_or_fail("T8 JAL needs no hold",                hold === 1'b0);
        pass_or_fail("T8 queue flushed",                    fq_valid === 1'b0);
        pass_or_fail("T8 target fetched in D+1",            imem_addr === 32'h0000_0200);
        tick;
        pass_or_fail("T8 nothing from the wrong path in D+2", fq_valid === 1'b0);
        tick;
        pass_or_fail("T8 target dispatchable at D+3",
                     fq_valid === 1'b1 && fq_pc === 32'h0000_0200);
        exp_pc = 32'h0000_0200;
        pops = 0;
        run(1, 12);
        pass_or_fail("T8 sequence continues from target",   pops >= 8);

        // ---------------- T9: JALR resolving while the queue is FULL --------
        do_reset;
        repeat (3) tick;
        cyc_ctl(1'b1, 1'b0, 32'h0, 1'b1, 1'b0, 1'b0, 32'h0);   // JALR at PC 0
        repeat (8) tick;
        pass_or_fail("T9 queue full before resolve",        dut.queue.count == 4);
        cyc_ctl(1'b0, 1'b0, 32'h0, 1'b0, 1'b1, 1'b1, 32'h0000_0300);
        pass_or_fail("T9 full queue flushed",               fq_valid === 1'b0);
        pass_or_fail("T9 hold cleared",                     hold === 1'b0);
        tick;
        pass_or_fail("T9 still empty in X+2",               fq_valid === 1'b0);
        tick;
        pass_or_fail("T9 target dispatchable at X+3",
                     fq_valid === 1'b1 && fq_pc === 32'h0000_0300);
        exp_pc = 32'h0000_0300;
        pops = 0;
        run(1, 12);
        pass_or_fail("T9 sequence continues from target",   pops >= 8);

        // ---------------- T10: redirect while a push + fetch are in flight --
        do_reset;
        pops = 0;
        run(1, 6);                    // steady state: queue never full
        pass_or_fail("T10 precondition: a word is arriving now", dut.fetch_pending === 1'b1);
        pass_or_fail("T10 precondition: head valid",             fq_valid === 1'b1);
        // JAL at the head, redirect to 0x400 in the same cycle as that push
        cyc_ctl(1'b1, 1'b1, 32'h0000_0400, 1'b0, 1'b0, 1'b0, 32'h0);
        pass_or_fail("T10 pushed word was dropped",         fq_valid === 1'b0);
        // the wrong-path address sent in cycle D must not count as pending,
        // and the first fetch of the target goes out now (D+1)
        pass_or_fail("T10 in-flight fetch dropped",         dut.fetch_pending === 1'b0);
        pass_or_fail("T10 target fetched in D+1",           imem_addr === 32'h0000_0400);
        tick;
        pass_or_fail("T10 in-flight word never reaches the queue", fq_valid === 1'b0);
        tick;
        pass_or_fail("T10 target dispatchable at D+3",
                     fq_valid === 1'b1 && fq_pc === 32'h0000_0400);
        exp_pc = 32'h0000_0400;
        pops = 0;
        run(1, 12);
        pass_or_fail("T10 sequence continues from target",  pops >= 8);

        // ---------------- T11: exact straight-line latency ----------------
        // fetched in cycle t, in the queue in t+1, dispatchable in t+2 (rule 1)
        do_reset;                                            // cycle t starts now
        pass_or_fail("T11 PC 0 is fetched in cycle t",      imem_addr === 32'h0);
        pass_or_fail("T11 queue empty in cycle t",          fq_valid === 1'b0);
        tick;                                                // t+1
        pass_or_fail("T11 PC 4 fetched in t+1",             imem_addr === 32'h4);
        pass_or_fail("T11 PC 0 not visible yet in t+1",     fq_valid === 1'b0);
        tick;                                                // t+2
        pass_or_fail("T11 PC 0 dispatchable exactly at t+2",
                     fq_valid === 1'b1 && fq_pc === 32'h0 && fq_inst === (32'h0 ^ KEY));
        pass_or_fail("T11 PC 8 fetched in t+2",             imem_addr === 32'h8);

        // ---------------- T12: random stress against a reference model -----
        // 20,000 cycles of random dispatch / branch / JAL / resolve traffic that
        // follows the real protocol (no dispatch while hold, branches resolve
        // only while hold is up). EVERY cycle, imem_addr, fq_valid, fq_pc,
        // fq_inst and hold must equal the model exactly.
        do_reset;
        m_cnt = 0;  m_fpc = `RESET_PC;  m_ppc = 32'h0;  m_pend = 1'b0;  m_hold = 1'b0;
        seed = 2026;  fails_shown = 0;

        for (i = 0; i < 20000; i = i + 1) begin
            every_cycle_checks;

            // ---- 1. compare DUT outputs with the model (start-of-cycle state)
            if (imem_addr !== m_fpc || fq_valid !== (m_cnt != 0) || hold !== m_hold ||
                (m_cnt != 0 && (fq_pc !== m_q[0] || fq_inst !== (m_q[0] ^ KEY)))) begin
                pass_or_fail("T12 DUT matches the reference model", 1'b0);
                if (fails_shown < 10) begin
                    fails_shown = fails_shown + 1;
                    $display("    cycle %0d  model: addr=%h valid=%b pc=%h hold=%b",
                             i, m_fpc, (m_cnt != 0), m_q[0], m_hold);
                    $display("              dut  : addr=%h valid=%b pc=%h hold=%b",
                             imem_addr, fq_valid, fq_pc, hold);
                end
            end
            else
                pass_or_fail("T12 DUT matches the reference model", 1'b1);

            // ---- 2. pick this cycle's inputs (protocol-legal)
            r_pop = 0;  r_rv = 0;  r_hs = 0;  r_bv = 0;  r_bt = 0;
            r_rpc  = $random(seed) & 32'h0000_0FFC;
            r_btgt = $random(seed) & 32'h0000_0FFC;
            r = $random(seed) & 255;
            if (m_hold) begin
                if (r < 64) begin                     // the pending branch resolves
                    r_bv = 1'b1;
                    r_bt = $random(seed) & 1;
                end
            end
            else if (m_cnt != 0 && (r % 4 != 0)) begin  // dispatch takes the head
                r_pop = 1'b1;
                kind  = $random(seed) & 7;
                if (kind == 0)       r_rv = 1'b1;     // JAL
                else if (kind <= 2)  r_hs = 1'b1;     // branch / JALR
            end

            fq_pop = r_pop;  redirect_valid = r_rv;  redirect_pc = r_rpc;
            hold_set = r_hs; br_valid = r_bv;  br_taken = r_bt;  br_target = r_btgt;

            // ---- 3. advance the model by one cycle (all from start-of-cycle state)
            m_redirect = r_rv | (r_bv & r_bt);
            m_npc      = (r_bv & r_bt) ? r_btgt : r_rpc;
            m_push     = m_pend & ~m_redirect;
            m_canf     = ((4 - m_cnt) > m_pend);
            cnt_start  = m_cnt;

            if (m_redirect)
                m_cnt = 0;
            else begin
                if (r_pop && m_cnt != 0) begin
                    m_q[0] = m_q[1];  m_q[1] = m_q[2];  m_q[2] = m_q[3];
                    m_cnt  = m_cnt - 1;
                end
                if (m_push && cnt_start < 4) begin
                    m_q[m_cnt] = m_ppc;
                    m_cnt      = m_cnt + 1;
                end
            end

            if (m_redirect) begin
                m_fpc  = m_npc;
                m_pend = 1'b0;
            end
            else if (m_canf) begin
                m_ppc  = m_fpc;
                m_pend = 1'b1;
                m_fpc  = m_fpc + 4;
            end
            else
                m_pend = 1'b0;

            if (r_bv)       m_hold = 1'b0;
            else if (r_hs)  m_hold = 1'b1;

            // ---- 4. clock edge, then drop the pulses
            @(posedge clk); #1;
            fq_pop = 0;  redirect_valid = 0;  hold_set = 0;  br_valid = 0;  br_taken = 0;
        end

        // ---------------- verdict ----------------
        if (n_fail == 0)
            $display("TEST_PASS ooo_frontend %0d", n_pass);
        else
            $display("TEST_FAIL ooo_frontend %0d of %0d checks failed",
                     n_fail, n_pass + n_fail);
        $finish;
    end

endmodule
