`timescale 1ns/1ps
`include "ooo_defs.vh"
// tb_rob.v - Self-checking testbench for reorder buffer allocation, completion, and commit.
module tb_rob;

    localparam N = `ROB_N;
    localparam W = `ROB_W;

    reg clk = 0, reset_n = 0;
    always #5 clk = ~clk;

    reg                    al_valid, al_has_rd, al_pre;
    reg  [`KIND_W-1:0]     al_kind;
    reg  [`REG_W-1:0]      al_rd;
    reg  [`XLEN-1:0]       al_pc, al_value;
    wire [W-1:0]           al_tag;
    wire                   full, empty;
    wire [W:0]             count;
    reg  [W-1:0]           rt1, rt2;
    wire                   rr1, rr2;
    wire [`XLEN-1:0]       rv1, rv2;
    reg  [`NCDB-1:0]       cv;
    reg  [`NCDB*W-1:0]     ct;
    reg  [`NCDB*`XLEN-1:0] cval;
    wire                   cm_valid, cm_has_rd, cm_is_store, ooo;
    wire [W-1:0]           cm_tag;
    wire [`REG_W-1:0]      cm_rd;
    wire [`XLEN-1:0]       cm_value, cm_pc;

    rob dut (
        .clk(clk), .reset_n(reset_n),
        .rob_al_valid(al_valid), .rob_al_kind(al_kind), .rob_al_has_rd(al_has_rd),
        .rob_al_rd(al_rd), .rob_al_pc(al_pc), .rob_al_pre(al_pre), .rob_al_value(al_value),
        .rob_al_tag(al_tag), .rob_full(full), .rob_empty(empty), .rob_count(count),
        .rob_rd_tag1(rt1), .rob_rd_tag2(rt2),
        .rob_rd_ready1(rr1), .rob_rd_ready2(rr2), .rob_rd_value1(rv1), .rob_rd_value2(rv2),
        .cdb_valid(cv), .cdb_tag(ct), .cdb_value(cval),
        .cm_valid(cm_valid), .cm_tag(cm_tag), .cm_has_rd(cm_has_rd), .cm_rd(cm_rd),
        .cm_value(cm_value), .cm_is_store(cm_is_store), .cm_pc(cm_pc),
        .ooo_event(ooo)
    );

    integer n_pass = 0, n_fail = 0;
    integer i, k, c;

    task ok;
        input [8*48:1] name;
        input          cond;
        begin
            if (cond) n_pass = n_pass + 1;
            else begin
                n_fail = n_fail + 1;
                $display("TEST_FAIL rob [%0s] at t=%0t", name, $time);
            end
        end
    endtask

    task step;                      // one clock, then drop the one-cycle pulses
        begin
            @(posedge clk); #1;
            al_valid = 1'b0;
            cv       = {`NCDB{1'b0}};
        end
    endtask

    task do_reset;
        begin
            al_valid = 0; cv = 0;
            reset_n = 0; #2 reset_n = 1;
        end
    endtask

    // put one allocation on the port (takes effect at the next edge)
    task alloc;
        input [`KIND_W-1:0] kd;
        input               hrd;
        input [`REG_W-1:0]  r;
        input [`XLEN-1:0]   p;
        input               pre;
        input [`XLEN-1:0]   v;
        begin
            al_valid = 1; al_kind = kd; al_has_rd = hrd; al_rd = r;
            al_pc = p; al_pre = pre; al_value = v;
        end
    endtask

    task bcast;
        input integer     bus;
        input [W-1:0]     t;
        input [`XLEN-1:0] v;
        begin
            cv[bus] = 1'b1;
            ct[bus*W +: W] = t;
            cval[bus*`XLEN +: `XLEN] = v;
        end
    endtask

    // ---- cycle-accurate model for T12 --------------------------------------
    reg              m_valid [0:N-1];
    reg              m_ready [0:N-1];
    reg [`KIND_W-1:0] m_kind [0:N-1];
    reg              m_hrd   [0:N-1];
    reg [`REG_W-1:0] m_rd    [0:N-1];
    reg [`XLEN-1:0]  m_val   [0:N-1];
    reg [`XLEN-1:0]  m_pc    [0:N-1];
    integer m_head, m_tail, m_cnt, seed, fails_shown, commits, multi;
    reg     m_cm, m_alloc, e_ooo, used;
    reg [W-1:0] pick;

    initial begin
        al_valid = 0; al_kind = 0; al_has_rd = 0; al_rd = 0; al_pc = 0; al_pre = 0; al_value = 0;
        rt1 = 0; rt2 = 0; cv = 0; ct = 0; cval = 0;
        repeat (2) @(posedge clk); #1 reset_n = 1;

        // ---------------- T1 ----------------
        do_reset;
        ok("T1 empty after reset",   empty === 1 && full === 0 && count === 0);
        ok("T1 tail starts at 0",    al_tag === 0);
        ok("T1 nothing commits",     cm_valid === 0);
        ok("T1 no ooo_event",        ooo === 0);

        // ---------------- T2: fill ----------------
        for (i = 0; i < N; i = i + 1) begin
            ok("T2 tag is the next entry", al_tag === i);
            alloc(`KIND_VALUE, 1, i + 1, 32'h1000 + 4*i, 0, 0);
            step;
        end
        ok("T2 full after ROB_N allocations", full === 1 && count === N && empty === 0);
        alloc(`KIND_VALUE, 1, 9, 32'hDEAD, 1, 32'hBAD);   // must be ignored
        step;
        ok("T2 allocate while full ignored", full === 1 && count === N && al_tag === 0);
        ok("T2 head not ready, no commit",   cm_valid === 0);

        // ---------------- T3: reverse completion ----------------
        for (i = N - 1; i >= 1; i = i - 1) begin
            bcast(i % `NCDB, i, 32'hA000 + i);
            step;
            ok("T3 younger done, head waits", cm_valid === 0);
        end
        bcast(`CDB_DIV, 0, 32'hA000);
        ok("T3 head not committed in its W cycle", cm_valid === 0);
        step;
        for (i = 0; i < N; i = i + 1) begin
            ok("T3 commits in order, one per cycle",
               cm_valid === 1 && cm_tag === i && cm_value === 32'hA000 + i &&
               cm_rd === i + 1 && cm_pc === 32'h1000 + 4*i && cm_has_rd === 1);
            step;
        end
        ok("T3 empty after draining", empty === 1 && cm_valid === 0);

        // ---------------- T4: four buses at once ----------------
        do_reset;
        for (i = 0; i < `NCDB; i = i + 1) begin alloc(`KIND_VALUE, 1, 5, 0, 0, 0); step; end
        for (k = 0; k < `NCDB; k = k + 1) bcast(k, `NCDB - 1 - k, 32'hB000 + k);
        step;
        for (i = 0; i < `NCDB; i = i + 1) begin
            ok("T4 every bus wrote its entry",
               cm_valid === 1 && cm_tag === i && cm_value === 32'hB000 + (`NCDB - 1 - i));
            step;
        end

        // ---------------- T5: allocate + commit in one cycle ----------------
        do_reset;
        for (i = 0; i < N; i = i + 1) begin alloc(`KIND_VALUE, 1, 1, 0, 0, 0); step; end
        bcast(`CDB_ALU, 0, 32'h55); step;
        ok("T5 full, head ready", full === 1 && cm_valid === 1);
        alloc(`KIND_VALUE, 1, 2, 0, 1, 32'h66);            // same cycle as commit
        step;
        ok("T5 at full: alloc ignored, commit done", count === N - 1 && full === 0 && al_tag === 0);
        alloc(`KIND_VALUE, 1, 2, 0, 1, 32'h66);
        step;
        ok("T5 freed entry reusable next cycle", count === N && full === 1);

        do_reset;
        alloc(`KIND_VALUE, 1, 3, 0, 1, 32'h77); step;      // count 1, ready
        ok("T5 count 1, head ready", count === 1 && cm_valid === 1);
        alloc(`KIND_VALUE, 1, 4, 0, 1, 32'h88); step;      // commit + alloc
        ok("T5 at count 1: count unchanged", count === 1 && cm_valid === 1 && cm_tag === 1 && cm_value === 32'h88);
        step;
        ok("T5 then empty", empty === 1);

        // ---------------- T6: pre-completed, no broadcast ----------------
        do_reset;
        alloc(`KIND_VALUE, 1, 7, 32'h40, 1, 32'h12345000); // LUI-like
        ok("T6 not committable in its allocation cycle", cm_valid === 0);
        step;
        alloc(`KIND_VALUE, 0, 0, 32'h44, 1, 32'h0);         // CLS_NOP: has_rd = 0
        ok("T6 CLS_PRE retires without a bus", cm_valid === 1 && cm_value === 32'h12345000 && cm_rd === 7);
        step;
        ok("T6 CLS_NOP retires, writes nothing", cm_valid === 1 && cm_has_rd === 0 && cm_pc === 32'h44);
        step;
        ok("T6 empty", empty === 1);

        // ---------------- T7: JALR link via cdb_alu ----------------
        do_reset;
        alloc(`KIND_BRANCH, 1, 1, 32'h200, 0, 32'hFFFF_FFFF);  // value must be ignored
        step;
        ok("T7 JALR waits for its bus", cm_valid === 0);
        bcast(`CDB_ALU, 0, 32'h204);
        step;
        ok("T7 link value from cdb_alu", cm_valid === 1 && cm_value === 32'h204 && cm_has_rd === 1 && cm_is_store === 0);
        step;

        // ---------------- T8: read ports ----------------
        do_reset;
        alloc(`KIND_VALUE, 1, 1, 0, 0, 0); step;
        alloc(`KIND_VALUE, 1, 2, 0, 1, 32'hC0FFEE); step;
        rt1 = 0; rt2 = 1; #1;
        ok("T8 port1 not ready", rr1 === 0);
        ok("T8 port2 pre-completed value", rr2 === 1 && rv2 === 32'hC0FFEE);
        bcast(`CDB_MUL, 0, 32'h99); #1;
        ok("T8 no same-cycle write-through", rr1 === 0);
        step;
        ok("T8 port1 ready next cycle", rr1 === 1 && rv1 === 32'h99);

        // ---------------- T9: ooo_event ----------------
        do_reset;
        #1 ok("T9 empty ROB: no event", ooo === 0);
        alloc(`KIND_VALUE, 1, 1, 0, 0, 0); step;
        alloc(`KIND_VALUE, 1, 2, 0, 0, 0); step;
        bcast(`CDB_LSU, 1, 32'h1); #1;
        ok("T9 younger completes while head waits", ooo === 1);
        step;
        bcast(`CDB_DIV, 0, 32'h2); #1;
        ok("T9 head's own tag is not an event", ooo === 0);
        step;
        ok("T9 no bus, no event", ooo === 0);

        // ---------------- T10: store kind ----------------
        do_reset;
        alloc(`KIND_STORE, 0, 0, 32'h300, 0, 0); step;
        bcast(`CDB_LSU, 0, 32'h0); step;
        ok("T10 store commit flagged", cm_valid === 1 && cm_is_store === 1 && cm_has_rd === 0);
        step;

        // ---------------- T11: async reset mid-run ----------------
        do_reset;
        alloc(`KIND_VALUE, 1, 1, 0, 1, 32'h1); step;
        alloc(`KIND_VALUE, 1, 1, 0, 1, 32'h2); step;
        #2 reset_n = 0; #1;
        ok("T11 reset clears at once", empty === 1 && count === 0 && cm_valid === 0 && al_tag === 0);
        reset_n = 1;
        alloc(`KIND_VALUE, 1, 3, 0, 1, 32'h3); step;
        ok("T11 works after reset", cm_valid === 1 && cm_tag === 0 && cm_value === 32'h3);
        step;

        // ---------------- T12: random vs model ----------------
        do_reset;
        for (i = 0; i < N; i = i + 1) m_valid[i] = 0;
        m_head = 0; m_tail = 0; m_cnt = 0; seed = 2026; fails_shown = 0; commits = 0; multi = 0;
        for (c = 0; c < 20000; c = c + 1) begin
            // compare start-of-cycle outputs
            m_cm = m_valid[m_head] && m_ready[m_head];
            rt1 = $random(seed); rt2 = $random(seed);
            // pick this cycle's broadcasts: distinct, valid, not-yet-ready entries
            cv = 0;
            for (k = 0; k < `NCDB; k = k + 1)
                if ($random(seed) & 1) begin
                    pick = $random(seed);
                    used = 0;
                    for (i = 0; i < k; i = i + 1) if (cv[i] && ct[i*W +: W] == pick) used = 1;
                    if (m_valid[pick] && !m_ready[pick] && !used) begin
                        cv[k] = 1; ct[k*W +: W] = pick; cval[k*`XLEN +: `XLEN] = $random(seed);
                    end
                end
            if (cv[0] + cv[1] + cv[2] + cv[3] >= 2) multi = multi + 1;
            e_ooo = 0;
            for (k = 0; k < `NCDB; k = k + 1)
                if (cv[k] && ct[k*W +: W] != m_head && m_valid[m_head] && !m_ready[m_head]) e_ooo = 1;
            #1;
            if (count !== m_cnt || full !== (m_cnt == N) || empty !== (m_cnt == 0) ||
                al_tag !== m_tail || cm_valid !== m_cm || ooo !== e_ooo ||
                (m_cm && (cm_tag !== m_head || cm_value !== m_val[m_head] || cm_rd !== m_rd[m_head] ||
                          cm_has_rd !== m_hrd[m_head] || cm_pc !== m_pc[m_head] ||
                          cm_is_store !== (m_kind[m_head] == `KIND_STORE))) ||
                rr1 !== (m_valid[rt1] && m_ready[rt1]) || rr2 !== (m_valid[rt2] && m_ready[rt2]) ||
                (rr1 && rv1 !== m_val[rt1]) || (rr2 && rv2 !== m_val[rt2])) begin
                ok("T12 DUT matches the model", 0);
                if (fails_shown < 8) begin
                    fails_shown = fails_shown + 1;
                    $display("    cycle %0d: model cnt=%0d head=%0d tail=%0d cm=%b ooo=%b | dut cnt=%0d tag=%0d cm=%b ooo=%b",
                             c, m_cnt, m_head, m_tail, m_cm, e_ooo, count, al_tag, cm_valid, ooo);
                end
            end else ok("T12 DUT matches the model", 1);

            // random allocation
            al_valid = ($random(seed) % 3) != 0;
            al_kind = $random(seed) % 3; al_has_rd = $random(seed); al_rd = $random(seed);
            al_pc = $random(seed); al_pre = ($random(seed) % 4) == 0; al_value = $random(seed);
            m_alloc = al_valid && (m_cnt != N);

            // model next state
            for (k = 0; k < `NCDB; k = k + 1)
                if (cv[k]) begin m_ready[ct[k*W +: W]] = 1; m_val[ct[k*W +: W]] = cval[k*`XLEN +: `XLEN]; end
            if (m_cm) begin m_valid[m_head] = 0; m_head = (m_head + 1) % N; commits = commits + 1; end
            if (m_alloc) begin
                m_valid[m_tail] = 1; m_ready[m_tail] = al_pre; m_kind[m_tail] = al_kind;
                m_hrd[m_tail] = al_has_rd; m_rd[m_tail] = al_rd; m_pc[m_tail] = al_pc;
                m_val[m_tail] = al_pre ? al_value : 0;
                m_tail = (m_tail + 1) % N;
            end
            m_cnt = m_cnt + m_alloc - m_cm;
            @(posedge clk); #1;
            al_valid = 0; cv = 0;
        end
        $display("T12: %0d commits, %0d cycles with >=2 buses active", commits, multi);

        if (n_fail == 0) $display("TEST_PASS rob %0d", n_pass);
        else             $display("TEST_FAIL rob %0d of %0d checks failed", n_fail, n_pass + n_fail);
        $finish;
    end

endmodule
