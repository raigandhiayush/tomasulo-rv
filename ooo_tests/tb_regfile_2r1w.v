// Self-checking testbench for regfile_2r1w verifying 2R1W access and x0 behavior.
`timescale 1ns/1ps
module tb_regfile_2r1w;
    reg clk = 0, reset_n = 0, we = 0;
    reg [4:0] raddr1 = 0, raddr2 = 0, waddr = 0;
    reg [31:0] wdata = 0;
    wire [31:0] rdata1, rdata2;

    regfile_2r1w dut (
        .clk(clk), .reset_n(reset_n),
        .raddr1(raddr1), .rdata1(rdata1),
        .raddr2(raddr2), .rdata2(rdata2),
        .we(we), .waddr(waddr), .wdata(wdata));

    always #5 clk = ~clk;

    reg [31:0] model [0:31];        // reference model, model[0] stays 0
    integer pass = 0, fail = 0;
    integer i, j, k, n;

    task check;
        input [31:0] got, exp;
        input [8*40-1:0] what;
        begin
            if (got === exp) pass = pass + 1;
            else begin
                fail = fail + 1;
                if (fail <= 20)
                    $display("FAIL %0s: got %h exp %h (r1=%0d r2=%0d w=%0d we=%b t=%0t)",
                             what, got, exp, raddr1, raddr2, waddr, we, $time);
            end
        end
    endtask

    // asynchronous reset: the model clears the moment reset_n falls
    always @(negedge reset_n) for (k = 1; k < 32; k = k + 1) model[k] = 0;

    // coverage of the cases that matter, counted over every cycle
    integer cov_collide = 0;        // write and read of the same register (x1..x31) in one cycle
    integer cov_both    = 0;        // both ports reading the register being written
    integer cov_x0w     = 0;        // write attempted to x0
    integer cov_nowe    = 0;        // we=0 with a nonzero waddr

    // Drive inputs just after a falling edge, check reads (start-of-cycle
    // values) just before the next rising edge, then commit to the model
    // after that edge.

    task cycle;
        input        w_en;
        input [4:0]  wa;
        input [31:0] wd;
        input [4:0]  ra1, ra2;
        begin
            we = w_en; waddr = wa; wdata = wd; raddr1 = ra1; raddr2 = ra2;
            #4;                                     // still before posedge
            check(rdata1, model[ra1], "rdata1");
            check(rdata2, model[ra2], "rdata2");
            if (reset_n && w_en && wa != 0 && (wa == ra1 || wa == ra2)) cov_collide = cov_collide + 1;
            if (reset_n && w_en && wa != 0 && wa == ra1 && wa == ra2)   cov_both    = cov_both + 1;
            if (w_en && wa == 0)  cov_x0w  = cov_x0w + 1;
            if (!w_en && wa != 0) cov_nowe = cov_nowe + 1;
            @(posedge clk); #1;
            if (reset_n && w_en && wa != 0) model[wa] = wd;
            @(negedge clk);
        end
    endtask

    initial begin
        for (i = 0; i < 32; i = i + 1) model[i] = 0;

        // 1. reset: hold reset_n low while writing garbage; nothing must land
        @(negedge clk);
        reset_n = 0;
        for (i = 0; i < 32; i = i + 1) cycle(1, i, 32'hDEAD0000 | i, i, 31 - i);
        reset_n = 1;
        for (i = 0; i < 32; i = i + 1) cycle(0, 0, 0, i, 31 - i);   // all read 0

        // 2. write every register with a unique pattern, read back on both ports
        for (i = 0; i < 32; i = i + 1) cycle(1, i, {i[7:0], ~i[7:0], i[7:0], 8'hA5}, 0, 0);
        for (i = 0; i < 32; i = i + 1) cycle(0, 0, 0, i, (i + 7) % 32);
        raddr1 = 0; raddr2 = 0; #1;
        check(rdata1, 32'd0, "x0 port1"); check(rdata2, 32'd0, "x0 port2");

        // 3. no write-through: read the register being written in the same cycle
        for (i = 1; i < 32; i = i + 1) begin
            cycle(1, i, 32'h12340000 + i, i, i);                    // old value expected
            cycle(0, 0, 0, i, i);                                   // new value next cycle
        end

        // 4. writes to x0 are ignored, with we high and nonzero data
        for (i = 0; i < 8; i = i + 1) cycle(1, 0, 32'hFFFFFFFF, 0, 0);

        // 5. we=0 must not write even with valid waddr/wdata
        for (i = 1; i < 32; i = i + 1) cycle(0, i, 32'hBAD0BAD0, i, i);

        // 6. reset mid-run clears x1..x31 (held across an edge with we high)
        for (i = 1; i < 32; i = i + 1) cycle(1, i, 32'h0F0F0000 + i, 0, 0);
        reset_n = 0; cycle(1, 3, 32'h55555555, 3, 4); reset_n = 1;
        for (i = 0; i < 32; i = i + 1) cycle(0, 0, 0, i, i);

        // 6b. asynchronous reset: reset_n pulsed low between clock edges,
        //     registers must read 0 before the next rising edge
        for (i = 1; i < 32; i = i + 1) cycle(1, i, 32'hA0A00000 + i, 0, 0);
        we = 0; raddr1 = 7; raddr2 = 31; #1;
        check(rdata1, 32'hA0A00007, "pre-async x7"); check(rdata2, 32'hA0A0001F, "pre-async x31");
        #1 reset_n = 0; #1 reset_n = 1; #1;                        // no clock edge in between
        check(rdata1, 32'd0, "async x7"); check(rdata2, 32'd0, "async x31");
        @(negedge clk);
        for (i = 0; i < 32; i = i + 1) cycle(0, 0, 0, i, i);

        // 8. every data bit of every register, both polarities, both ports:
        //    walking 1, walking 0, all 0, all 1 (catches stuck or swapped bits)
        for (i = 1; i < 32; i = i + 1) begin
            for (j = 0; j < 32; j = j + 1) begin
                cycle(1, i, 32'd1 << j, 0, 0);
                cycle(1, i, ~(32'd1 << j), i, i);   // reads the walking-1 value (old)
            end
            cycle(1, i, 32'h00000000, i, i);
            cycle(1, i, 32'hFFFFFFFF, i, i);
            cycle(0, 0, 0, i, i);
        end

        // 9. address decode: write one register, every other register unchanged
        for (i = 1; i < 32; i = i + 1) cycle(1, i, 32'h00000000, 0, 0);
        for (i = 1; i < 32; i = i + 1) begin
            cycle(1, i, 32'hC0DE0000 | i, 0, 0);
            for (j = 0; j < 32; j = j + 2) cycle(0, 0, 0, j, j + 1);
        end

        // 10. back-to-back writes to the same register: each value visible
        //     for exactly one cycle, the last one stays
        for (i = 1; i < 32; i = i + 1) begin
            cycle(1, i, 32'h11110000 + i, i, i);
            cycle(1, i, 32'h22220000 + i, i, i);
            cycle(1, i, 32'h33330000 + i, i, i);
            cycle(0, 0, 0, i, i);
            check(rdata1, 32'h33330000 + i, "b2b last");
        end

        // 11. one port reads the register being written (old value), the
        //     other reads a different register (unaffected); then swapped
        for (i = 1; i < 32; i = i + 1) begin
            cycle(1, i, 32'h44440000 + i, i, (i % 31) + 1);
            cycle(1, i, 32'h55550000 + i, (i % 31) + 1, i);
        end

        // 12. first cycle after reset release: a write lands, x0 still 0
        reset_n = 0; cycle(0, 0, 0, 0, 0); reset_n = 1;
        cycle(1, 31, 32'h87654321, 31, 0);      // old value 0 seen
        cycle(1, 1, 32'h0BADF00D, 31, 1);       // x31 = new value now
        cycle(0, 0, 0, 1, 31);

        // 13. random traffic against the model
        n = 20000;
        for (j = 0; j < n; j = j + 1)
            cycle($random, $random, $random, $random, $random);

        $display("coverage: collide=%0d both_ports=%0d x0_writes=%0d we0=%0d",
                 cov_collide, cov_both, cov_x0w, cov_nowe);
        if (cov_collide < 100 || cov_both < 31 || cov_x0w < 8 || cov_nowe < 31) begin
            fail = fail + 1;
            $display("FAIL coverage below minimum");
        end
        if (fail == 0) $display("TEST_PASS regfile_2r1w %0d", pass);
        else           $display("TEST_FAIL regfile_2r1w %0d failed, %0d passed", fail, pass);
        $finish;
    end
endmodule
