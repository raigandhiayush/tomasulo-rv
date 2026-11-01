// tb_bpred.v - self-checking testbench for bpred.v (BTB + 2-bit counters)
`timescale 1ns/1ps
`include "ooo_defs.vh"
module tb_bpred;
    reg clk = 0, reset_n = 0;
    always #5 clk = ~clk;
    reg  [31:0] f_pc = 0, up_pc = 0, up_target = 0, jal_pc = 0, jal_target = 0;
    reg         up_valid = 0, up_taken = 0, jal_valid = 0;
    wire        f_taken;
    wire [31:0] f_target;
    bpred dut (.clk(clk), .reset_n(reset_n), .f_pc(f_pc), .f_taken(f_taken), .f_target(f_target),
               .up_valid(up_valid), .up_pc(up_pc), .up_taken(up_taken), .up_target(up_target),
               .jal_valid(jal_valid), .jal_pc(jal_pc), .jal_target(jal_target));
    integer n_pass = 0, n_fail = 0, i, j;
    task check(input ok, input [8*40-1:0] what, input [31:0] got, input [31:0] exp);
        begin
            if (ok) n_pass = n_pass + 1;
            else begin n_fail = n_fail + 1; $display("TEST_FAIL bpred %0s: got %h expected %h (t=%0t)", what, got, exp, $time); end
        end
    endtask
    task branch(input [31:0] pc, input t, input [31:0] tg);
        begin
            @(negedge clk); up_valid = 1; up_pc = pc; up_taken = t; up_target = tg;
            @(negedge clk); up_valid = 0;
        end
    endtask
    task jal(input [31:0] pc, input [31:0] tg);
        begin
            @(negedge clk); jal_valid = 1; jal_pc = pc; jal_target = tg;
            @(negedge clk); jal_valid = 0;
        end
    endtask
    task expect_pred(input [31:0] pc, input t, input [31:0] tg, input [8*40-1:0] what);
        begin
            f_pc = pc; #1;
            check(f_taken === t, what, f_taken, t);
            if (t) check(f_target === tg, "target", f_target, tg);
        end
    endtask
    initial begin
        repeat (3) @(negedge clk);
        reset_n = 1;
        @(negedge clk);
        // nothing predicted after reset
        for (i = 0; i < 1024; i = i + 1) expect_pred(i * 4, 0, 0, "empty BTB");
        // counter starts at 01: one taken -> 10 -> predicted taken, BTB written
        expect_pred(32'h40, 0, 0, "before first taken");
        branch(32'h40, 1, 32'h100);
        expect_pred(32'h40, 1, 32'h100, "after one taken");
        // saturates at 11: two more taken, one not-taken still predicts taken
        branch(32'h40, 1, 32'h100); branch(32'h40, 1, 32'h100); branch(32'h40, 1, 32'h100);
        branch(32'h40, 0, 32'h100);
        expect_pred(32'h40, 1, 32'h100, "11 -> 10 still taken");
        branch(32'h40, 0, 32'h100);
        expect_pred(32'h40, 0, 0, "10 -> 01 not taken");
        // saturates at 00: needs two taken to predict taken again
        branch(32'h40, 0, 32'h100); branch(32'h40, 0, 32'h100); branch(32'h40, 0, 32'h100);
        branch(32'h40, 1, 32'h100);
        expect_pred(32'h40, 0, 0, "00 -> 01 not taken");
        branch(32'h40, 1, 32'h100);
        expect_pred(32'h40, 1, 32'h100, "01 -> 10 taken");
        // a not-taken branch never enters the BTB
        branch(32'h80, 0, 32'h200); branch(32'h80, 0, 32'h200);
        expect_pred(32'h80, 0, 0, "not-taken not in BTB");
        // tag check: same BTB index, different pc
        expect_pred(32'h40 + (`BTB_N * 4), 0, 0, "BTB tag mismatch");
        // replacement: the other pc takes the entry
        branch(32'h40 + (`BTB_N * 4), 1, 32'h300);
        branch(32'h40 + (`BTB_N * 4), 1, 32'h300);
        expect_pred(32'h40 + (`BTB_N * 4), 1, 32'h300, "new entry");
        expect_pred(32'h40, 0, 0, "evicted entry");
        // JAL: predicted taken whatever the counter says
        jal(32'hC0, 32'h400);
        expect_pred(32'hC0, 1, 32'h400, "JAL");
        branch(32'hC0, 0, 32'h400); branch(32'hC0, 0, 32'h400); branch(32'hC0, 0, 32'h400);
        expect_pred(32'hC0, 1, 32'h400, "JAL ignores the counter");
        // reset clears the BTB and the counters (asynchronous)
        @(negedge clk); reset_n = 0; #1;
        for (j = 0; j < 256; j = j + 1) expect_pred(j * 4, 0, 0, "reset");
        @(negedge clk); reset_n = 1;
        @(negedge clk);
        branch(32'h40, 1, 32'h100);
        expect_pred(32'h40, 1, 32'h100, "counter back at 01 after reset");
        if (n_fail == 0) $display("TEST_PASS bpred %0d", n_pass);
        else             $display("TEST_FAIL bpred %0d failures, %0d passed", n_fail, n_pass);
        $finish;
    end
endmodule
