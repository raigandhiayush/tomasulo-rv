`timescale 1ns/1ps
`include "ooo_defs.vh"
// tb_rs_array.v - Self-checking testbench for reservation stations verifying allocation, wakeup, and issue.
module tb_rs_array;

    reg clk, reset_n;

    // allocate port (shared by both DUTs)
    reg                  al_valid;
    reg  [7:0]           al_op;
    reg  [`ROB_W-1:0]    al_tag, al_qj, al_qk;
    reg                  al_qjv, al_qkv;
    reg  [31:0]          al_vj, al_vk, al_a;

    // the four buses (shared)
    reg  [`NCDB-1:0]        cdb_valid;
    reg  [`NCDB*`ROB_W-1:0] cdb_tag;
    reg  [32*`NCDB-1:0]     cdb_value;

    // each DUT gets its own accept so we can hold one back
    reg acc, acc1;

    wire                 full,  iv;
    wire [7:0]           iop;
    wire [`ROB_W-1:0]    itag;
    wire [31:0]          ivj, ivk, ia;

    wire                 full1, iv1;
    wire [7:0]           iop1;
    wire [`ROB_W-1:0]    itag1;
    wire [31:0]          ivj1, ivk1, ia1;

    rs_array #(.N(3)) dut (
        .clk(clk), .reset_n(reset_n),
        .rs_al_valid(al_valid), .rs_al_op(al_op), .rs_al_tag(al_tag),
        .rs_al_qj_valid(al_qjv), .rs_al_qj(al_qj), .rs_al_vj(al_vj),
        .rs_al_qk_valid(al_qkv), .rs_al_qk(al_qk), .rs_al_vk(al_vk),
        .rs_al_a(al_a), .rs_full(full),
        .cdb_valid(cdb_valid), .cdb_tag(cdb_tag), .cdb_value(cdb_value),
        .iss_valid(iv), .iss_op(iop), .iss_tag(itag),
        .iss_vj(ivj), .iss_vk(ivk), .iss_a(ia), .iss_accept(acc)
    );

    rs_array #(.N(1)) dut1 (
        .clk(clk), .reset_n(reset_n),
        .rs_al_valid(al_valid), .rs_al_op(al_op), .rs_al_tag(al_tag),
        .rs_al_qj_valid(al_qjv), .rs_al_qj(al_qj), .rs_al_vj(al_vj),
        .rs_al_qk_valid(al_qkv), .rs_al_qk(al_qk), .rs_al_vk(al_vk),
        .rs_al_a(al_a), .rs_full(full1),
        .cdb_valid(cdb_valid), .cdb_tag(cdb_tag), .cdb_value(cdb_value),
        .iss_valid(iv1), .iss_op(iop1), .iss_tag(itag1),
        .iss_vj(ivj1), .iss_vk(ivk1), .iss_a(ia1), .iss_accept(acc1)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;      // 10 ns period, rising edges at 5, 15, 25 ...

    integer n_pass, n_fail, kk;

    // -----------------------------------------------------------------------
    // little helpers
    // -----------------------------------------------------------------------
    task step;                  // one clock, then drop the one-cycle pulses
        begin
            @(posedge clk); #1;
            al_valid  = 1'b0;
            cdb_valid = {`NCDB{1'b0}};
        end
    endtask

    task do_reset;              // short async reset pulse between edges
        begin
            al_valid  = 1'b0;
            cdb_valid = {`NCDB{1'b0}};
            acc  = 1'b0;
            acc1 = 1'b0;
            reset_n = 1'b0;
            #2;
            reset_n = 1'b1;
        end
    endtask

    // put one instruction on the allocate port (takes effect at the next edge)
    task alloc;
        input [`ROB_W-1:0] t;
        input              qjv;
        input [`ROB_W-1:0] qj;
        input [31:0]       vj;
        input              qkv;
        input [`ROB_W-1:0] qk;
        input [31:0]       vk;
        begin
            al_valid = 1'b1;
            al_op    = 8'h00;
            al_tag   = t;
            al_qjv   = qjv;  al_qj = qj;  al_vj = vj;
            al_qkv   = qkv;  al_qk = qk;  al_vk = vk;
            al_a     = 32'h0;
        end
    endtask

    task alloc_ready;           // both operands already known
        input [`ROB_W-1:0] t;
        input [31:0]       vj, vk;
        begin
            alloc(t, 1'b0, {`ROB_W{1'b0}}, vj, 1'b0, {`ROB_W{1'b0}}, vk);
        end
    endtask

    // drive bus k with {tag, value} for this cycle
    task bcast;
        input integer      k;
        input [`ROB_W-1:0] t;
        input [31:0]       v;
        begin
            cdb_valid[k]                = 1'b1;
            cdb_tag[k*`ROB_W +: `ROB_W] = t;
            cdb_value[k*32 +: 32]       = v;
        end
    endtask

    // -----------------------------------------------------------------------
    // checks
    // -----------------------------------------------------------------------
    task pass_or_fail;
        input [8*44:1] name;
        input          ok;
        begin
            if (ok) n_pass = n_pass + 1;
            else begin
                n_fail = n_fail + 1;
                $display("TEST_FAIL rs_array [%0s] at t=%0t", name, $time);
            end
        end
    endtask

    // issue port of the N=3 station. If e_v = 0 only iss_valid is checked.
    task chk_iss;
        input [8*44:1]     name;
        input              e_v;
        input [`ROB_W-1:0] e_t;
        input [31:0]       e_vj, e_vk;
        reg ok;
        begin
            ok = (iv === e_v) &&
                 (!e_v || (itag === e_t && ivj === e_vj && ivk === e_vk));
            pass_or_fail(name, ok);
            if (!ok) begin
                $display("    expected: iss_valid=%b tag=%0d vj=%h vk=%h", e_v, e_t, e_vj, e_vk);
                $display("    got     : iss_valid=%b tag=%0d vj=%h vk=%h", iv,  itag, ivj,  ivk);
            end
        end
    endtask

    task chk_full;
        input [8*44:1] name;
        input          e_full;
        begin
            pass_or_fail(name, full === e_full);
            if (full !== e_full)
                $display("    expected rs_full=%b, got %b", e_full, full);
        end
    endtask

    // issue port + full of the N=1 station
    task chk_div;
        input [8*44:1]     name;
        input              e_v;
        input [`ROB_W-1:0] e_t;
        input              e_full;
        reg ok;
        begin
            ok = (iv1 === e_v) && (full1 === e_full) && (!e_v || itag1 === e_t);
            pass_or_fail(name, ok);
            if (!ok) begin
                $display("    expected: iss_valid=%b tag=%0d full=%b", e_v, e_t, e_full);
                $display("    got     : iss_valid=%b tag=%0d full=%b", iv1, itag1, full1);
            end
        end
    endtask

    // -----------------------------------------------------------------------
    initial begin
        n_pass = 0;  n_fail = 0;
        reset_n  = 1'b0;
        al_valid = 1'b0;  al_op = 0;  al_tag = 0;
        al_qjv = 0;  al_qj = 0;  al_vj = 0;
        al_qkv = 0;  al_qk = 0;  al_vk = 0;  al_a = 0;
        cdb_valid = 0;  cdb_tag = 0;  cdb_value = 0;
        acc = 0;  acc1 = 0;
        repeat (2) @(posedge clk);
        #1 reset_n = 1'b1;

        // ---------------- T1: ready at allocation ----------------
        do_reset;
        alloc_ready(3'd1, 32'd10, 32'd20);
        al_op = 8'h0D;  al_a = 32'h0000_1234;
        chk_iss ("T1 not visible in alloc cycle", 1'b0, 0, 0, 0);
        chk_full("T1 empty RS is not full",       1'b0);
        step;
        chk_iss ("T1 issues the next cycle",      1'b1, 3'd1, 32'd10, 32'd20);
        pass_or_fail("T1 op and a carried through", iop === 8'h0D && ia === 32'h0000_1234);
        acc = 1'b1;  step;  acc = 1'b0;
        chk_iss ("T1 entry freed after accept",   1'b0, 0, 0, 0);
        chk_full("T1 not full after free",        1'b0);

        // ---------------- T2: wake-up on every bus ----------------
        for (kk = 0; kk < `NCDB; kk = kk + 1) begin
            // operand j waits for tag 5
            do_reset;
            alloc(3'd2, 1'b1, 3'd5, 32'd0, 1'b0, 3'd0, 32'd7);
            step;
            chk_iss("T2 qj waiting, not ready",       1'b0, 0, 0, 0);
            bcast(kk, 3'd5, 32'd100 + kk);
            chk_iss("T2 qj not ready in bcast cycle", 1'b0, 0, 0, 0);
            step;
            chk_iss("T2 qj woken by bus kk",          1'b1, 3'd2, 32'd100 + kk, 32'd7);
            acc = 1'b1;  step;  acc = 1'b0;

            // operand k waits for tag 5
            do_reset;
            alloc(3'd2, 1'b0, 3'd0, 32'd8, 1'b1, 3'd5, 32'd0);
            step;
            chk_iss("T2 qk waiting, not ready",       1'b0, 0, 0, 0);
            bcast(kk, 3'd5, 32'd200 + kk);
            step;
            chk_iss("T2 qk woken by bus kk",          1'b1, 3'd2, 32'd8, 32'd200 + kk);
            acc = 1'b1;  step;  acc = 1'b0;
        end

        // ---------------- T3: two buses in one cycle ----------------
        // both operands of ONE entry, released together (MUL + DIV buses)
        do_reset;
        alloc(3'd3, 1'b1, 3'd4, 32'd0, 1'b1, 3'd6, 32'd0);
        step;
        chk_iss("T3 both waiting",                   1'b0, 0, 0, 0);
        bcast(1, 3'd4, 32'hAAAA_AAAA);
        bcast(2, 3'd6, 32'hBBBB_BBBB);
        step;
        chk_iss("T3 both operands, MUL+DIV buses",   1'b1, 3'd3, 32'hAAAA_AAAA, 32'hBBBB_BBBB);
        acc = 1'b1;  step;  acc = 1'b0;

        // same thing on the other two buses, roles swapped
        do_reset;
        alloc(3'd3, 1'b1, 3'd4, 32'd0, 1'b1, 3'd6, 32'd0);
        step;
        bcast(3, 3'd4, 32'h1111_1111);
        bcast(0, 3'd6, 32'h2222_2222);
        step;
        chk_iss("T3 both operands, LSU+ALU buses",   1'b1, 3'd3, 32'h1111_1111, 32'h2222_2222);
        acc = 1'b1;  step;  acc = 1'b0;

        // two DIFFERENT entries woken by two buses in the same cycle
        do_reset;
        alloc(3'd1, 1'b1, 3'd4, 32'd0, 1'b0, 3'd0, 32'd1);
        step;
        alloc(3'd2, 1'b1, 3'd6, 32'd0, 1'b0, 3'd0, 32'd2);
        step;
        bcast(1, 3'd4, 32'h0000_0044);
        bcast(2, 3'd6, 32'h0000_0066);
        step;
        chk_iss("T3 two entries woken, older first", 1'b1, 3'd1, 32'h44, 32'd1);
        acc = 1'b1;  step;
        chk_iss("T3 then the younger one",           1'b1, 3'd2, 32'h66, 32'd2);
        step;  acc = 1'b0;
        chk_iss("T3 both gone",                      1'b0, 0, 0, 0);

        // ---------------- T4: no false wake-ups ----------------
        do_reset;
        alloc(3'd1, 1'b1, 3'd5, 32'd0, 1'b0, 3'd0, 32'd9);
        step;
        cdb_tag[0 +: `ROB_W] = 3'd5;            // right tag on bus 0 ...
        cdb_value[31:0]      = 32'hDEAD_DEAD;   // ... but cdb_valid stays 0
        step;
        chk_iss("T4 no wake when cdb_valid = 0",  1'b0, 0, 0, 0);
        bcast(0, 3'd6, 32'hBEEF_BEEF);           // valid, wrong tag
        step;
        chk_iss("T4 no wake on a different tag",  1'b0, 0, 0, 0);
        bcast(2, 3'd5, 32'h0000_0077);           // now the real one
        step;
        chk_iss("T4 wakes on the right tag",      1'b1, 3'd1, 32'h77, 32'd9);
        acc = 1'b1;  step;  acc = 1'b0;

        // ---------------- T5: oldest first, all ready ----------------
        do_reset;
        alloc_ready(3'd1, 32'd11, 32'd0);  step;
        alloc_ready(3'd2, 32'd22, 32'd0);  step;
        alloc_ready(3'd3, 32'd33, 32'd0);  step;
        chk_full("T5 full after 3 allocations",   1'b1);
        chk_iss ("T5 offers the oldest (tag 1)",  1'b1, 3'd1, 32'd11, 32'd0);
        acc = 1'b1;  step;
        chk_full("T5 not full after one issue",   1'b0);
        chk_iss ("T5 then tag 2",                 1'b1, 3'd2, 32'd22, 32'd0);
        step;
        chk_iss ("T5 then tag 3",                 1'b1, 3'd3, 32'd33, 32'd0);
        step;  acc = 1'b0;
        chk_iss ("T5 empty again",                1'b0, 0, 0, 0);

        // ---------------- T6: older entry wakes up late ----------------
        do_reset;
        alloc(3'd1, 1'b1, 3'd7, 32'd0, 1'b0, 3'd0, 32'd1);  step;   // older, waiting
        alloc_ready(3'd2, 32'd22, 32'd2);                    step;   // younger, ready
        chk_iss("T6 only the younger is ready",   1'b1, 3'd2, 32'd22, 32'd2);
        bcast(3, 3'd7, 32'h0000_0055);
        step;
        chk_iss("T6 older wins once it is ready", 1'b1, 3'd1, 32'h55, 32'd1);
        acc = 1'b1;  step;
        chk_iss("T6 then the younger",            1'b1, 3'd2, 32'd22, 32'd2);
        step;  acc = 1'b0;
        chk_iss("T6 empty again",                 1'b0, 0, 0, 0);

        // ---------------- T7: full, ignore, reuse next cycle ----------------
        do_reset;
        alloc_ready(3'd1, 32'd11, 32'd0);  step;
        alloc_ready(3'd2, 32'd22, 32'd0);  step;
        alloc_ready(3'd3, 32'd33, 32'd0);  step;
        chk_full("T7 full",                       1'b1);
        alloc_ready(3'd4, 32'd44, 32'd0);  step;          // must be ignored
        chk_full("T7 still full",                 1'b1);
        chk_iss ("T7 ignored alloc changed nothing", 1'b1, 3'd1, 32'd11, 32'd0);

        // issue tag 1 and try to allocate tag 4 in the SAME cycle:
        // rs_full was 1 at the start of the cycle, so tag 4 must be dropped
        acc = 1'b1;
        alloc_ready(3'd4, 32'd44, 32'd0);
        step;
        acc = 1'b0;
        chk_full("T7 one slot free after issue",  1'b0);
        chk_iss ("T7 next oldest is tag 2",       1'b1, 3'd2, 32'd22, 32'd0);

        alloc_ready(3'd5, 32'd55, 32'd0);  step;          // next cycle: allowed
        chk_full("T7 freed slot reused next cycle", 1'b1);
        acc = 1'b1;  step;
        chk_iss ("T7 drain: tag 3",               1'b1, 3'd3, 32'd33, 32'd0);
        step;
        chk_iss ("T7 drain: tag 5 (4 never got in)", 1'b1, 3'd5, 32'd55, 32'd0);
        step;  acc = 1'b0;
        chk_iss ("T7 drained",                    1'b0, 0, 0, 0);

        // ---------------- T8: DIV station, accept held low ----------------
        do_reset;
        alloc_ready(3'd6, 32'd9, 32'd3);  step;
        chk_div("T8 DIV entry offered",           1'b1, 3'd6, 1'b1);
        step;  step;
        chk_div("T8 still held, accept low",      1'b1, 3'd6, 1'b1);
        alloc_ready(3'd7, 32'd1, 32'd1);  step;            // full: ignored
        chk_div("T8 second alloc ignored",        1'b1, 3'd6, 1'b1);
        acc1 = 1'b1;  step;  acc1 = 1'b0;
        chk_div("T8 freed once accept goes high", 1'b0, 0, 1'b0);

        // ---------------- T9: async reset mid-test ----------------
        do_reset;
        alloc_ready(3'd1, 32'd11, 32'd0);                  step;
        alloc(3'd2, 1'b1, 3'd5, 32'd0, 1'b0, 3'd0, 32'd0); step;
        chk_iss("T9 has an entry before reset",   1'b1, 3'd1, 32'd11, 32'd0);
        #2 reset_n = 1'b0;                     // between edges
        #1;
        chk_iss ("T9 reset clears at once",       1'b0, 0, 0, 0);
        chk_full("T9 not full after reset",       1'b0);
        reset_n = 1'b1;
        alloc_ready(3'd3, 32'd33, 32'd0);  step;
        chk_iss ("T9 works normally after reset", 1'b1, 3'd3, 32'd33, 32'd0);
        acc = 1'b1;  step;  acc = 1'b0;
        chk_iss ("T9 empty again",                1'b0, 0, 0, 0);

        // ---------------- verdict ----------------
        if (n_fail == 0)
            $display("TEST_PASS rs_array %0d", n_pass);
        else
            $display("TEST_FAIL rs_array %0d of %0d checks failed",
                     n_fail, n_pass + n_fail);
        $finish;
    end

endmodule
