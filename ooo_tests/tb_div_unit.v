// tb_div_unit.v - Self-checking testbench for div_unit verifying timing and edge cases.
`timescale 1ns/1ps
`include "ooo_defs.vh"
module tb_div_unit;
    localparam ROB_W = `ROB_W;
    localparam EXP_LAT = 33;          // start sampled in t -> done in t+33

    reg clk = 0, reset_n = 0, start = 0;
    reg [1:0] op = 0;
    reg [31:0] a = 0, b = 0;
    reg [ROB_W-1:0] tag_in = 0;
    wire busy, done;
    wire [31:0] result;
    wire [ROB_W-1:0] tag_out;

    div_unit #(.ROB_W(ROB_W)) dut (
        .clk(clk), .reset_n(reset_n), .start(start), .funct3(op),
        .a(a), .b(b), .tag(tag_in),
        .busy(busy), .done(done), .result(result), .done_tag(tag_out));

    always #5 clk = ~clk;

    integer pass = 0, fail = 0, cyc = 0;
    integer lat_min = 1000, lat_max = 0;
    always @(posedge clk) cyc <= cyc + 1;

    // RISC-V reference model
    // Signed ops go through signed regs: inside ?: with unsigned operands
    // Verilog would silently evaluate $signed(x)/$signed(y) as unsigned.
    function [31:0] ref_div;
        input [1:0] f; input [31:0] x, y;
        reg signed [31:0] sx, sy, sq, sr;
        begin
            sx = x; sy = y;
            sq = (sy == 0) ? 0 : sx / sy;
            sr = (sy == 0) ? 0 : sx % sy;
            case (f)
            2'b00: if (y == 0) ref_div = 32'hFFFFFFFF;
                   else if (x == 32'h80000000 && y == 32'hFFFFFFFF) ref_div = 32'h80000000;
                   else ref_div = sq;
            2'b01: ref_div = (y == 0) ? 32'hFFFFFFFF : x / y;
            2'b10: if (y == 0) ref_div = x;
                   else if (x == 32'h80000000 && y == 32'hFFFFFFFF) ref_div = 32'h0;
                   else ref_div = sr;
            2'b11: ref_div = (y == 0) ? x : x % y;
            endcase
        end
    endfunction

    task check(input cond, input [8*48-1:0] what);
        begin
            if (cond) pass = pass + 1;
            else begin fail = fail + 1; $display("FAIL: %0s (cyc %0d)", what, cyc); end
        end
    endtask

    // Issue one op with start held for exactly one cycle, then watch every
    // cycle until done: busy must be 1 in between and 0 in the done cycle.
    task run_op(input [1:0] f, input [31:0] x, input [31:0] y);
        integer t0, lat; reg [31:0] exp; reg [ROB_W-1:0] tg;
        begin
            exp = ref_div(f, x, y);
            tg  = $random;
            @(negedge clk);
            check(!busy, "busy low before start");
            op = f; a = x; b = y; tag_in = tg; start = 1; t0 = cyc;
            @(negedge clk);
            start = 0; a = 32'hDEADBEEF; b = 32'hDEADBEEF; op = ~f; // operands must be latched
            while (!done) begin
                if (!busy) begin fail = fail + 1; $display("FAIL: busy dropped early at +%0d", cyc - t0); end
                @(negedge clk);
                if (cyc - t0 > 100) begin fail = fail + 1; $display("FAIL: timeout"); disable run_op; end
            end
            lat = cyc - t0;
            if (lat < lat_min) lat_min = lat;
            if (lat > lat_max) lat_max = lat;
            check(lat == EXP_LAT, "latency == EXP_LAT");
            check(!busy, "busy low in done cycle");
            check(tag_out == tg, "tag_out");
            if (result !== exp)
                $display("FAIL: op=%0d a=%h b=%h got=%h exp=%h", f, x, y, result, exp);
            check(result === exp, "result");
            if ($test$plusargs("trace")) $display("TRACE %0d %h %h %h", f, x, y, result);
            @(negedge clk);
            check(!done, "done is a 1-cycle pulse");
            check(result === exp, "result held after done");
        end
    endtask

    integer i, k;
    reg [31:0] ra, rb;
    reg [31:0] corners [0:15];
    integer x, y, j, d0;
    integer t0, lat;
    reg [31:0] e1, e2;

    initial begin
        reset_n = 0;
        corners[0] = 32'h0;        corners[1] = 32'h1;
        corners[2] = 32'hFFFFFFFF; corners[3] = 32'h80000000;
        corners[4] = 32'h7FFFFFFF; corners[5] = 32'd7;
        corners[6] = 32'hFFFFFFF9; corners[7] = 32'd2;
        corners[8] = 32'hFFFFFFFE; corners[9] = 32'h12345678;
        corners[10] = 32'h80000001; corners[11] = 32'h7FFFFFFE;
        corners[12] = 32'h00010000; corners[13] = 32'hFFFF0000;
        corners[14] = 32'd3;        corners[15] = 32'hFFFFFFFD;

        // 0. start asserted during reset is ignored; outputs clean after reset
        op = 2'b00; a = 32'd10; b = 32'd2; start = 1;
        repeat (3) @(negedge clk);
        start = 0; reset_n = 1;
        check(!busy && !done && result == 0, "clean outputs after reset");
        repeat (40) begin
            if (busy || done) begin fail = fail + 1; $display("FAIL: start during reset was accepted"); end
            @(negedge clk);
        end

        // 1. every corner x corner pair, all four ops (includes x/0, 0/0, INT_MIN/-1)
        for (k = 0; k < 4; k = k + 1)
            for (i = 0; i < 256; i = i + 1)
                run_op(k[1:0], corners[i / 16], corners[i % 16]);

        // 1b. exhaustive small operands -10..10 x -10..10, all four ops
        for (k = 0; k < 4; k = k + 1)
            for (x = -10; x <= 10; x = x + 1)
                for (y = -10; y <= 10; y = y + 1)
                    run_op(k[1:0], x, y);

        // 1c. walking-one divisors and dividends (every bit position)
        for (j = 0; j < 32; j = j + 1)
            for (k = 0; k < 4; k = k + 1) begin
                run_op(k[1:0], 32'hFFFFFFFF, 32'd1 << j);
                run_op(k[1:0], 32'd1 << j, 32'd3);
            end

        // 2. random operands (some small divisors to hit wide quotients)
        for (i = 0; i < 400; i = i + 1) begin
            ra = $random; rb = $random;
            if (i % 4 == 1) rb = rb[7:0];
            if (i % 4 == 2) rb = {{28{rb[31]}}, rb[3:0]};
            run_op(i[1:0], ra, rb);
        end

        // 3. back-to-back: second start in the done cycle of the first
        @(negedge clk);
        op = 2'b00; a = -32'd100; b = 32'd7; tag_in = 3'd5; start = 1; t0 = cyc;
        @(negedge clk); start = 0;
        while (!done) @(negedge clk);
        check(cyc - t0 == EXP_LAT, "b2b: first latency");
        check(result == ref_div(2'b00, -32'd100, 32'd7) && tag_out == 3'd5, "b2b: first result");
        check(!busy, "b2b: busy low in done cycle");
        op = 2'b10; a = -32'd100; b = 32'd7; tag_in = 3'd6; start = 1; t0 = cyc;  // start in done cycle
        @(negedge clk); start = 0;
        check(busy, "b2b: second op accepted");
        while (!done) @(negedge clk);
        check(cyc - t0 == EXP_LAT, "b2b: second latency");
        check(result == ref_div(2'b10, -32'd100, 32'd7) && tag_out == 3'd6, "b2b: second result");

        // 4. start while busy is ignored
        @(negedge clk);
        op = 2'b01; a = 32'd1000; b = 32'd10; tag_in = 3'd1; start = 1; t0 = cyc;
        @(negedge clk); op = 2'b01; a = 32'd9; b = 32'd3; tag_in = 3'd2;  // start still high: must be ignored
        repeat (5) @(negedge clk); start = 0;
        while (!done) @(negedge clk);
        check(cyc - t0 == EXP_LAT && result == 32'd100 && tag_out == 3'd1, "start while busy ignored");
        @(negedge clk);
        // the held-high start in the done cycle above was released, so unit must be idle
        check(!busy && !done, "idle after op");

        // 5. asynchronous reset mid-operation: clears at once, no done, next op correct
        op = 2'b00; a = 32'd50; b = 32'd5; tag_in = 3'd3; start = 1;
        @(negedge clk); start = 0;
        repeat (10) @(negedge clk);
        #2 reset_n = 0; #1;
        check(!busy && !done, "async reset clears busy without a clock edge");
        reset_n = 1;
        for (i = 0; i < 40; i = i + 1) begin
            @(negedge clk);
            if (done) begin fail = fail + 1; $display("FAIL: done after reset"); end
        end
        run_op(2'b11, 32'd50, 32'd7);

        // 6. every tag value comes back unchanged
        for (j = 0; j < `ROB_N; j = j + 1) begin
            @(negedge clk);
            op = 2'b00; a = 32'd20; b = 32'd4; tag_in = j; start = 1;
            @(negedge clk); start = 0;
            while (!done) @(negedge clk);
            check(tag_out == j && result == 32'd5, "tag sweep");
        end

        // 7. reset in the middle of an op: no done, idle, next op correct
        @(negedge clk);
        op = 2'b00; a = 32'd99; b = 32'd9; start = 1;
        @(negedge clk); start = 0;
        repeat (15) @(negedge clk);
        reset_n = 0; @(negedge clk); reset_n = 1;
        check(!busy, "reset mid-op clears busy");
        for (i = 0; i < 40; i = i + 1) begin
            if (done) begin fail = fail + 1; $display("FAIL: done after reset"); end
            @(negedge clk);
        end
        run_op(2'b00, 32'hFFFFFF9D, 32'd9);   // -99 / 9

        // 8. asynchronous reset in the last busy cycle (t+32): no done
        @(negedge clk);
        op = 2'b01; a = 32'd8; b = 32'd2; start = 1; t0 = cyc;
        @(negedge clk); start = 0;
        while (cyc - t0 < EXP_LAT - 1) @(negedge clk);
        check(busy, "busy in t+32");
        #2 reset_n = 0; #1 reset_n = 1;
        check(!busy && !done, "reset in t+32 suppresses done");
        repeat (5) begin
            @(negedge clk);
            if (done) begin fail = fail + 1; $display("FAIL: done after late reset"); end
        end

        // 10. start held high for two ops: second accepted in the done cycle
        op = 2'b00; a = 32'd77; b = 32'd7; tag_in = 3'd4; start = 1; t0 = cyc;
        @(negedge clk);
        while (!done) @(negedge clk);
        check(cyc - t0 == EXP_LAT && result == 32'd11 && tag_out == 3'd4, "held start: first op");
        a = 32'd78; b = 32'd7; tag_in = 3'd7; d0 = cyc;   // still start=1 in done cycle
        @(negedge clk); start = 0;
        check(busy, "held start: second op accepted in done cycle");
        while (!done) @(negedge clk);
        check(cyc - d0 == EXP_LAT && result == 32'd11 && tag_out == 3'd7, "held start: second op");

        $display("Measured DIV latency: min %0d, max %0d cycles (start cycle -> done cycle)", lat_min, lat_max);
        if (fail == 0) $display("TEST_PASS div_unit %0d", pass);
        else           $display("TEST_FAIL div_unit %0d failures, %0d passes", fail, pass);
        $finish;
    end
endmodule
