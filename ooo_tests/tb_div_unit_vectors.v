// tb_div_unit_vectors.v - Vector testbench for div_unit using precomputed reference values.
`timescale 1ns/1ps
`include "ooo_defs.vh"
module tb_div_unit_vectors;
    localparam ROB_W   = `ROB_W;
    localparam EXP_LAT = 33;                    // start in t -> done in t+33
    localparam MAXV    = 8192;                  // max vectors in the file
    localparam NGRP    = 32;

    reg clk = 0, reset_n = 0, start = 0;
    reg [`OP_MD_HI:0] funct3 = 0;
    reg [31:0] a = 0, b = 0;
    reg [ROB_W-1:0] tag = 0;
    wire busy, done;
    wire [31:0] result;
    wire [ROB_W-1:0] done_tag;

    div_unit dut (
        .clk(clk), .reset_n(reset_n), .start(start), .funct3(funct3),
        .a(a), .b(b), .tag(tag),
        .busy(busy), .done(done), .result(result), .done_tag(done_tag));

    always #5 clk = ~clk;
    integer cyc = 0;
    always @(posedge clk) cyc <= cyc + 1;

    reg [31:0] vec [0:5*MAXV-1];                // group funct3 a b expected
    reg [8*256-1:0] vfile;
    reg [8*256-1:0] line;
    integer fd, nf, nvec, v, t0, lat, g, fails, checks;
    integer gpass [0:NGRP-1];
    integer gfail [0:NGRP-1];
    reg [31:0] vg, vf, va, vb, ve;
    reg ok;

    initial begin
        if (!$value$plusargs("vectors=%s", vfile)) vfile = "../ooo_tests/vectors/div_unit_vectors.mem";
        // read "group funct3 a b expected" lines; lines starting with / are comments
        nvec = 0;
        fd = $fopen(vfile, "r");
        if (fd != 0) begin
            while (!$feof(fd) && nvec < MAXV) begin
                line = 0;
                if ($fgets(line, fd) > 0) begin
                    nf = $sscanf(line, "%h %h %h %h %h", vg, vf, va, vb, ve);
                    if (nf == 5) begin
                        vec[5*nvec] = vg; vec[5*nvec+1] = vf; vec[5*nvec+2] = va;
                        vec[5*nvec+3] = vb; vec[5*nvec+4] = ve;
                        nvec = nvec + 1;
                    end
                end
            end
            $fclose(fd);
        end
        if (nvec == 0) begin
            $display("TEST_FAIL div_unit: no vectors read from %0s", vfile);
            $finish;
        end
        for (g = 0; g < NGRP; g = g + 1) begin gpass[g] = 0; gfail[g] = 0; end
        fails = 0; checks = 0;

        repeat (3) @(negedge clk);
        reset_n = 1;

        for (v = 0; v < nvec; v = v + 1) begin
            vg = vec[5*v]; vf = vec[5*v+1]; va = vec[5*v+2]; vb = vec[5*v+3]; ve = vec[5*v+4];
            @(negedge clk);
            funct3 = vf[`OP_MD_HI:0]; a = va; b = vb; tag = v; start = 1; t0 = cyc;
            @(negedge clk);
            start = 0; a = ~va; b = ~vb;        // operands must already be latched
            ok = 1;
            while (!done && cyc - t0 < 100) begin
                if (!busy) ok = 0;              // busy must stay 1 until done
                @(negedge clk);
            end
            lat = cyc - t0;
            if (!done || lat != EXP_LAT || busy || result !== ve || done_tag !== v[ROB_W-1:0])
                ok = 0;
            checks = checks + 1;
            if (ok) gpass[vg] = gpass[vg] + 1;
            else begin
                gfail[vg] = gfail[vg] + 1; fails = fails + 1;
                $display("FAIL vector %0d group %0d funct3=%0d a=%h b=%h expected=%h got=%h latency=%0d busy_in_done=%b tag=%0d/%0d",
                         v, vg, vf, va, vb, ve, result, lat, busy, done_tag, v[ROB_W-1:0]);
            end
        end

        $display("group  passed  failed");
        for (g = 0; g < NGRP; g = g + 1)
            if (gpass[g] + gfail[g] > 0) $display("%5d  %6d  %6d", g, gpass[g], gfail[g]);
        $display("Vectors read from %0s: %0d", vfile, nvec);
        if (fails == 0) $display("TEST_PASS div_unit %0d", checks);
        else            $display("TEST_FAIL div_unit %0d failures of %0d", fails, checks);
        $finish;
    end
endmodule
