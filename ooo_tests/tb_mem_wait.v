// tb_mem_wait.v - self-checking testbench for mem_wait.v with the real data_mem.
// Three instances (WAIT = 0, 3, 10). Exact read timing, burst timing, write buffer
// back-pressure, a read seeing every earlier store, and random traffic against a
// golden memory.
`timescale 1ns/1ps
`include "ooo_defs.vh"
module tbmw_h #(parameter WAIT = 3, parameter NAME = "M") (input wire clk, output reg done, output integer n_pass, output integer n_fail);
    reg         reset_n = 0, re = 0, we = 0;
    reg  [31:0] raddr = 0, waddr = 0, wdata = 0;
    reg  [3:0]  wstrb = 0;
    wire        read_valid, write_valid, ram_re, ram_we;
    wire [31:0] ram_raddr, ram_waddr, ram_wdata, rdata;
    wire [3:0]  ram_wstrb;
    mem_wait #(.WAIT(WAIT), .WBUF_N(4)) dut (.clk(clk), .reset_n(reset_n), .re(re), .raddr(raddr), .we(we),
        .waddr(waddr), .wdata(wdata), .wstrb(wstrb), .read_valid(read_valid), .write_valid(write_valid),
        .ram_re(ram_re), .ram_raddr(ram_raddr), .ram_we(ram_we), .ram_waddr(ram_waddr),
        .ram_wdata(ram_wdata), .ram_wstrb(ram_wstrb));
    data_mem M (.clk(clk), .re(ram_re), .raddr(ram_raddr), .rdata(rdata),
                .we(ram_we), .waddr(ram_waddr), .wdata(ram_wdata), .wstrb(ram_wstrb));
    reg [31:0] g [0:1023];
    integer i, k, cyc = 0;
    always @(posedge clk) cyc <= cyc + 1;
    task check(input ok, input [8*44-1:0] what, input [31:0] got, input [31:0] exp);
        begin
            if (ok) n_pass = n_pass + 1;
            else begin
                n_fail = n_fail + 1;
                if (n_fail < 12) $display("TEST_FAIL mem_wait %0s %0s: got %h expected %h (cycle %0d)", NAME, what, got, exp, cyc);
            end
        end
    endtask
    // read: returns the data and the cycles from the request to the data
    reg [31:0] rd_val; integer rd_lat;
    task read(input [31:0] a);
        integer c0;
        begin
            while (!read_valid) @(negedge clk);
            re = 1; raddr = a; c0 = cyc;
            @(negedge clk); re = 0;
            while (!read_valid) @(negedge clk);
            rd_val = rdata; rd_lat = cyc - c0;
        end
    endtask
    function [31:0] mg(input [31:0] o, input [31:0] n, input [3:0] s);
        mg = {s[3]?n[31:24]:o[31:24], s[2]?n[23:16]:o[23:16], s[1]?n[15:8]:o[15:8], s[0]?n[7:0]:o[7:0]};
    endfunction
    task write(input [31:0] a, input [31:0] d, input [3:0] s);
        begin
            while (!write_valid) @(negedge clk);
            we = 1; waddr = a; wdata = d; wstrb = s;
            g[a[11:2]] = mg(g[a[11:2]], d, s);
            @(negedge clk); we = 0;
        end
    endtask
    reg [31:0] a, d;
    initial begin
        done = 0; n_pass = 0; n_fail = 0;
        for (i = 0; i < 1024; i = i + 1) begin M.dmem[i] = 32'hB000_0000 + i; g[i] = M.dmem[i]; end
        repeat (3) @(negedge clk);
        reset_n = 1; @(negedge clk);
        // read timing: first access WAIT + 1, the next word 1, another word WAIT + 1
        read(32'h100);
        check(rd_val === g[64], "first read data", rd_val, g[64]);
        check(rd_lat == WAIT + 1, "first read latency", rd_lat, WAIT + 1);
        read(32'h104);
        check(rd_val === g[65], "next-word read data", rd_val, g[65]);
        check(rd_lat == 1, "next-word read latency", rd_lat, 1);
        read(32'h108);
        check(rd_lat == 1, "burst continues", rd_lat, 1);
        read(32'h200);
        check(rd_val === g[128], "jump data", rd_val, g[128]);
        check(rd_lat == WAIT + 1, "jump latency", rd_lat, WAIT + 1);
        // a read sees every earlier store, even still buffered
        write(32'h300, 32'h1111_1111, 4'hF);
        write(32'h400, 32'h2222_2222, 4'hF);
        write(32'h300, 32'hAB00_0000, 4'b1000);
        read(32'h300);
        check(rd_val === g[192], "read after buffered stores", rd_val, g[192]);
        read(32'h400);
        check(rd_val === g[256], "read after buffered stores 2", rd_val, g[256]);
        // back-pressure: write_valid falls once the buffer is full, and nothing is lost
        if (WAIT > 0) begin
            write(32'h500, 1, 4'hF); write(32'h600, 2, 4'hF); write(32'h700, 3, 4'hF); write(32'h800, 4, 4'hF);
            #1 check(write_valid === 1'b0 || dut.g_wait.w_cnt < 4, "write_valid with a full buffer", write_valid, 0);
            write(32'h900, 5, 4'hF);
        end
        // random traffic
        for (k = 0; k < 4000; k = k + 1) begin
            a = ({$random} % 1024) << 2;
            if (({$random} % 4) == 0) a = waddr + 4;
            d = $random;
            if ($random & 1) write(a, d, 1 + {$random} % 15);
            else begin
                read(a);
                check(rd_val === g[a[11:2]], "random read", rd_val, g[a[11:2]]);
            end
        end
        // the buffer drains; data_mem ends up equal to the golden memory
        repeat (WAIT * 8 + 8) @(negedge clk);
        for (i = 0; i < 1024; i = i + 1) check(M.dmem[i] === g[i], "final memory", M.dmem[i], g[i]);
        done = 1;
    end
endmodule

module tb_mem_wait;
    reg clk = 0;
    always #5 clk = ~clk;
    wire d0, d1, d2;
    integer p0, p1, p2, f0, f1, f2;
    tbmw_h #(.WAIT(0),  .NAME("W0"))  H0 (.clk(clk), .done(d0), .n_pass(p0), .n_fail(f0));
    tbmw_h #(.WAIT(3),  .NAME("W3"))  H1 (.clk(clk), .done(d1), .n_pass(p1), .n_fail(f1));
    tbmw_h #(.WAIT(10), .NAME("W10")) H2 (.clk(clk), .done(d2), .n_pass(p2), .n_fail(f2));
    initial begin
        #1;
        wait (d0 && d1 && d2);
        if (f0 + f1 + f2 == 0) $display("TEST_PASS mem_wait %0d", p0 + p1 + p2);
        else                   $display("TEST_FAIL mem_wait %0d failures, %0d passed", f0 + f1 + f2, p0 + p1 + p2);
        $finish;
    end
endmodule
