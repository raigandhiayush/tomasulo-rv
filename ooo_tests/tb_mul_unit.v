// tb_mul_unit.v -- self-checking testbench for mul_unit (owner D).
// Blueprint §6.10: all sign combinations of {0,1,-1,2,0x7FFFFFFF,0x80000000,
// 0xFFFFFFFF,...} for MUL/MULH/MULHSU/MULHU; 100,000 random pairs; back-to-back
// starts on consecutive cycles with different tags; latency start t -> done t+2.
//
// Golden model is independent of the RTL's 33x33 trick: operands are
// extended to 64 bits (sign- or zero-) and multiplied mod 2^64, which gives
// the exact low 64 bits of the true product.
// Prints TEST_PASS mul_unit <n> or TEST_FAIL ... with cycle/expected/actual.
`timescale 1ns/1ps
`include "ooo_defs.vh"

module tb_mul_unit;
    localparam ROB_W = `ROB_W;
    localparam LAT   = 2;              // start in t -> done in t+2

    reg               clk = 0, reset_n = 0;
    reg               start = 0;
    reg  [1:0]        funct3 = 0;
    reg  [31:0]       a = 0, b = 0;
    reg  [ROB_W-1:0]  tag = 0;
    wire              done;
    wire [ROB_W-1:0]  done_tag;
    wire [31:0]       result;

    mul_unit dut (
        .clk(clk), .reset_n(reset_n), .start(start), .funct3(funct3),
        .a(a), .b(b), .tag(tag), .done(done), .done_tag(done_tag), .result(result));

    always #5 clk = ~clk;

    function [31:0] golden(input [1:0] f, input [31:0] x, input [31:0] y);
        reg [63:0] xe, ye, p;
        begin
            xe = (f == 2'b11)  ? {32'd0, x} : {{32{x[31]}}, x};   // MULHU: a unsigned
            ye = (f[1] == 1'b1)? {32'd0, y} : {{32{y[31]}}, y};   // MULHSU/MULHU: b unsigned
            p  = xe * ye;
            golden = (f == 2'b00) ? p[31:0] : p[63:32];
        end
    endfunction

    reg [1:0]  sb_f [0:0];
    reg [31:0] sb_a [0:0], sb_b [0:0];   // operands of the checked op, for messages

    integer cyc = 0, nvec = 0, nfail = 0, i, j, k;

    task fail(input [8*24-1:0] what, input [31:0] exp, input [31:0] act, input integer slot);
        begin
            nfail = nfail + 1;
            if (nfail <= 20)
                $display("TEST_FAIL mul_unit cycle=%0d %0s op=%0d a=%h b=%h expected=%h actual=%h",
                         cyc, what, sb_f[slot], sb_a[slot], sb_b[slot], exp, act);
        end
    endtask

    // shift-register scoreboard: slot 0 = this cycle's issue, slot LAT = issued LAT cycles ago
    reg              q_v   [0:LAT];
    reg [ROB_W-1:0]  q_tag [0:LAT];
    reg [31:0]       q_res [0:LAT];
    reg [1:0]        q_f   [0:LAT];
    reg [31:0]       q_a   [0:LAT], q_b [0:LAT];

    integer sh;   // private loop variable of 'issue'
    task issue(input s, input [1:0] f, input [31:0] x, input [31:0] y, input [ROB_W-1:0] t);
        begin
            @(negedge clk);
            start = s; funct3 = f; a = x; b = y; tag = t;
            // shift: slot 0 = this cycle's issue, slot LAT = issued LAT cycles ago
            for (sh = LAT; sh > 0; sh = sh - 1) begin
                q_v[sh] = q_v[sh-1]; q_tag[sh] = q_tag[sh-1]; q_res[sh] = q_res[sh-1];
                q_f[sh] = q_f[sh-1]; q_a[sh] = q_a[sh-1]; q_b[sh] = q_b[sh-1];
            end
            q_v[0] = s; q_tag[0] = t; q_res[0] = golden(f, x, y);
            q_f[0] = f; q_a[0] = x; q_b[0] = y;
            #1;
            nvec = nvec + 1;
            sb_f[0] = q_f[LAT]; sb_a[0] = q_a[LAT]; sb_b[0] = q_b[LAT];  // for messages
            if (done !== q_v[LAT]) fail("done", q_v[LAT], done, 0);
            else if (done) begin
                if (done_tag !== q_tag[LAT]) fail("done_tag", q_tag[LAT], done_tag, 0);
                if (result   !== q_res[LAT]) fail("result",   q_res[LAT], result,   0);
            end
            @(posedge clk);
            cyc = cyc + 1;
        end
    endtask

    task flush_pipe; begin for (k = 0; k <= LAT; k = k + 1) issue(0, 0, 0, 0, 0); end endtask

    reg [31:0] corner [0:9];
    reg [31:0] x, y;
    reg [1:0]  f;
    integer    n, ntag;

    initial begin
        for (k = 0; k <= LAT; k = k + 1) q_v[k] = 0;
        corner[0] = 32'h00000000; corner[1] = 32'h00000001; corner[2] = 32'hFFFFFFFF;
        corner[3] = 32'h00000002; corner[4] = 32'h7FFFFFFF; corner[5] = 32'h80000000;
        corner[6] = 32'h80000001; corner[7] = 32'hFFFFFFFE; corner[8] = 32'h0000FFFF;
        corner[9] = 32'hFFFF0000;
        repeat (2) @(posedge clk);
        #2 reset_n = 1;

        // 1. isolated operations: exact latency, nothing on the bus otherwise
        issue(1, 2'b00, 32'd6, 32'd7, 3'd5);
        flush_pipe;

        // 2. corner table: every op x every corner pair, issued back-to-back
        ntag = 0;
        for (n = 0; n < 4; n = n + 1)
            for (i = 0; i < 10; i = i + 1)
                for (j = 0; j < 10; j = j + 1) begin
                    issue(1, n[1:0], corner[i], corner[j], ntag[ROB_W-1:0]);
                    ntag = ntag + 1;
                end
        flush_pipe;

        // 3. spot values worked by hand: proves the golden model itself
        //    (the scoreboard then ties the DUT to the golden model)
        if (golden(2'b01, 32'h80000000, 32'h80000000) !== 32'h40000000 ||  // MULH  (-2^31)^2
            golden(2'b10, 32'hFFFFFFFF, 32'hFFFFFFFF) !== 32'hFFFFFFFF ||  // MULHSU -1*(2^32-1)
            golden(2'b11, 32'hFFFFFFFF, 32'hFFFFFFFF) !== 32'hFFFFFFFE ||  // MULHU (2^32-1)^2
            golden(2'b01, 32'hFFFFFFFF, 32'h00000001) !== 32'hFFFFFFFF ||  // MULH  -1*1
            golden(2'b11, 32'hFFFFFFFF, 32'h00000002) !== 32'h00000001 ||  // MULHU
            golden(2'b00, 32'h80000000, 32'hFFFFFFFF) !== 32'h80000000) begin
            nfail = nfail + 1;
            $display("TEST_FAIL mul_unit golden-model self-check failed");
        end
        issue(1, 2'b01, 32'h80000000, 32'h80000000, 0);
        issue(1, 2'b10, 32'hFFFFFFFF, 32'hFFFFFFFF, 1);
        issue(1, 2'b11, 32'hFFFFFFFF, 32'hFFFFFFFF, 2);
        flush_pipe;

        // 4. reset in flight: an operation started before reset must never appear
        issue(1, 2'b00, 32'd3, 32'd3, 3'd1);
        @(negedge clk); start = 0; #2 reset_n = 0; #1;
        if (done !== 1'b0) begin nfail = nfail + 1;
            $display("TEST_FAIL mul_unit cycle=%0d done during reset expected=0 actual=%b", cyc, done); end
        for (k = 0; k <= LAT; k = k + 1) q_v[k] = 0;
        @(posedge clk); #1 reset_n = 1;
        flush_pipe;

        // 5. 100,000 random pairs, ~75% start rate, random tags, 25% corner operands
        for (n = 0; n < 100000; n = n + 1) begin
            x = (($urandom % 4) == 0) ? corner[$urandom % 10] : $urandom;
            y = (($urandom % 4) == 0) ? corner[$urandom % 10] : $urandom;
            issue(($urandom % 4) != 0, $urandom % 4, x, y, $urandom % `ROB_N);
        end
        flush_pipe;

        if (nfail == 0) $display("TEST_PASS mul_unit %0d", nvec);
        else            $display("TEST_FAIL mul_unit %0d failures out of %0d checks", nfail, nvec);
        $finish;
    end
endmodule
