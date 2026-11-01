`timescale 1ns/1ps
`include "ooo_defs.vh"
// tb_alu_path.v - Integration testbench for the ALU execution loop (RS -> alu_fu -> CDB).
module tb_alu_path;

    // op encodings (D16): [2:0] funct3, [3] sub/sra, [4] is_branch, [5] is_jalr
    localparam [7:0] OP_ADD  = 8'h00, OP_SUB  = 8'h08,
                     OP_BEQ  = 8'h10, OP_BNE  = 8'h11, OP_BLT = 8'h14,
                     OP_JALR = 8'h20;

    reg clk, reset_n;

    // dispatch side (allocate port of the ALU RS)
    reg                al_valid;
    reg  [7:0]         al_op;
    reg  [`ROB_W-1:0]  al_tag, al_qj, al_qk;
    reg                al_qjv, al_qkv;
    reg  [31:0]        al_vj, al_vk, al_a;

    // buses 1..NCDB-1 (MUL, DIV, LSU) are driven by the testbench
    reg  [`NCDB-2:0]          ov;
    reg  [(`NCDB-1)*`ROB_W-1:0] otag;
    reg  [(`NCDB-1)*32-1:0]   oval;

    // ALU slice wires
    wire               iss_valid;
    wire [7:0]         iss_op;
    wire [`ROB_W-1:0]  iss_tag;
    wire [31:0]        iss_vj, iss_vk, iss_a;
    wire [31:0]        alu_result, alu_target;
    wire               alu_is_ctrl, alu_taken;
    wire               rs_full;

    // the four buses: bus 0 = cdb_alu (from the slice), buses 1.. from the tb
    wire [`NCDB-1:0]        cdb_valid = {ov,   iss_valid};
    wire [`NCDB*`ROB_W-1:0] cdb_tag   = {otag, iss_tag};
    wire [`NCDB*32-1:0]     cdb_value = {oval, alu_result};

    // branch resolve path (what goes to ooo_frontend)
    wire        br_valid  = iss_valid & alu_is_ctrl;
    wire        br_taken  = alu_taken;
    wire [31:0] br_target = alu_target;

    rs_array #(.N(`RS_ALU_N)) u_rs_alu (
        .clk(clk), .reset_n(reset_n),
        .rs_al_valid(al_valid), .rs_al_op(al_op), .rs_al_tag(al_tag),
        .rs_al_qj_valid(al_qjv), .rs_al_qj(al_qj), .rs_al_vj(al_vj),
        .rs_al_qk_valid(al_qkv), .rs_al_qk(al_qk), .rs_al_vk(al_vk),
        .rs_al_a(al_a), .rs_full(rs_full),
        .cdb_valid(cdb_valid), .cdb_tag(cdb_tag), .cdb_value(cdb_value),
        .iss_valid(iss_valid), .iss_op(iss_op), .iss_tag(iss_tag),
        .iss_vj(iss_vj), .iss_vk(iss_vk), .iss_a(iss_a),
        .iss_accept(iss_valid)
    );

    alu_fu u_alu (
        .op(iss_op), .vj(iss_vj), .vk(iss_vk), .a(iss_a),
        .result(alu_result), .is_ctrl(alu_is_ctrl),
        .taken(alu_taken), .target(alu_target)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    integer n_pass, n_fail;

    // -----------------------------------------------------------------------
    task step;                  // one clock, then drop the one-cycle pulses
        begin
            @(posedge clk); #1;
            al_valid = 1'b0;
            ov       = {(`NCDB-1){1'b0}};
        end
    endtask

    task do_reset;
        begin
            al_valid = 1'b0;
            ov       = {(`NCDB-1){1'b0}};
            reset_n  = 1'b0;
            #2 reset_n = 1'b1;
        end
    endtask

    task alloc;
        input [7:0]        op;
        input [`ROB_W-1:0] t;
        input              qjv;
        input [`ROB_W-1:0] qj;
        input [31:0]       vj;
        input              qkv;
        input [`ROB_W-1:0] qk;
        input [31:0]       vk;
        input [31:0]       a;
        begin
            al_valid = 1'b1;
            al_op  = op;   al_tag = t;
            al_qjv = qjv;  al_qj  = qj;  al_vj = vj;
            al_qkv = qkv;  al_qk  = qk;  al_vk = vk;
            al_a   = a;
        end
    endtask

    // drive testbench bus k (1 = MUL, 2 = DIV, 3 = LSU) for this cycle
    task bus;
        input integer      k;
        input [`ROB_W-1:0] t;
        input [31:0]       v;
        begin
            ov[k-1]                         = 1'b1;
            otag[(k-1)*`ROB_W +: `ROB_W]    = t;
            oval[(k-1)*32 +: 32]            = v;
        end
    endtask

    task pass_or_fail;
        input [8*44:1] name;
        input          ok;
        begin
            if (ok) n_pass = n_pass + 1;
            else begin
                n_fail = n_fail + 1;
                $display("TEST_FAIL alu_path [%0s] at t=%0t", name, $time);
            end
        end
    endtask

    // what is on cdb_alu right now? (e_v = 0: nothing may be broadcast)
    task chk_alu;
        input [8*44:1]     name;
        input              e_v;
        input [`ROB_W-1:0] e_t;
        input [31:0]       e_val;
        reg ok;
        begin
            ok = (cdb_valid[`CDB_ALU] === e_v) &&
                 (!e_v || (iss_tag === e_t && alu_result === e_val));
            pass_or_fail(name, ok);
            if (!ok) begin
                $display("    expected cdb_alu: valid=%b tag=%0d value=%h", e_v, e_t, e_val);
                $display("    got      cdb_alu: valid=%b tag=%0d value=%h",
                         cdb_valid[`CDB_ALU], iss_tag, alu_result);
            end
        end
    endtask

    // what is on the branch resolve path right now?
    task chk_br;
        input [8*44:1] name;
        input          e_v;
        input          e_taken;
        input [31:0]   e_tgt;
        reg ok;
        begin
            ok = (br_valid === e_v) &&
                 (!e_v || (br_taken === e_taken && br_target === e_tgt));
            pass_or_fail(name, ok);
            if (!ok) begin
                $display("    expected br: valid=%b taken=%b target=%h", e_v, e_taken, e_tgt);
                $display("    got      br: valid=%b taken=%b target=%h", br_valid, br_taken, br_target);
            end
        end
    endtask

    // -----------------------------------------------------------------------
    initial begin
        n_pass = 0;  n_fail = 0;
        reset_n = 1'b0;
        al_valid = 0;  al_op = 0;  al_tag = 0;
        al_qjv = 0;  al_qj = 0;  al_vj = 0;
        al_qkv = 0;  al_qk = 0;  al_vk = 0;  al_a = 0;
        ov = 0;  otag = 0;  oval = 0;
        repeat (2) @(posedge clk);
        #1 reset_n = 1'b1;

        // ---------------- T1: dependent pair ----------------
        // I1: add tag1 = x(tag5 from MUL) + 7      I2: add tag2 = I1 + 3
        do_reset;
        alloc(OP_ADD, 3'd1, 1'b1, 3'd5, 32'd0, 1'b0, 3'd0, 32'd7, 32'd0);
        chk_alu("T1 nothing broadcast yet",            1'b0, 0, 0);
        step;                                                       // c1
        alloc(OP_ADD, 3'd2, 1'b1, 3'd1, 32'd0, 1'b0, 3'd0, 32'd3, 32'd0);
        chk_alu("T1 I1 waits for its operand",         1'b0, 0, 0);
        step;                                                       // c2
        bus(1, 3'd5, 32'd5);                                        // MUL delivers 5
        chk_alu("T1 not ready in the broadcast cycle", 1'b0, 0, 0);
        step;                                                       // c3 = W
        chk_alu("T1 I1 executes + broadcasts 12",      1'b1, 3'd1, 32'd12);
        chk_br ("T1 an add is not a branch",           1'b0, 0, 0);
        step;                                                       // c4 = W+1
        chk_alu("T1 I2 back-to-back: 12+3 = 15",       1'b1, 3'd2, 32'd15);
        step;                                                       // c5
        chk_alu("T1 nothing left",                     1'b0, 0, 0);

        // ---------------- T2: three-instruction chain ----------------
        do_reset;
        alloc(OP_ADD, 3'd1, 1'b1, 3'd5, 32'd0, 1'b0, 3'd0, 32'd1, 32'd0);  step;
        alloc(OP_ADD, 3'd2, 1'b1, 3'd1, 32'd0, 1'b0, 3'd0, 32'd2, 32'd0);  step;
        alloc(OP_SUB, 3'd3, 1'b1, 3'd2, 32'd0, 1'b0, 3'd0, 32'd3, 32'd0);  step;
        bus(1, 3'd5, 32'd10);
        chk_alu("T2 chain waiting",                    1'b0, 0, 0);
        step;
        chk_alu("T2 I1 = 10+1 = 11",                   1'b1, 3'd1, 32'd11);
        step;
        chk_alu("T2 I2 = 11+2 = 13 (next cycle)",      1'b1, 3'd2, 32'd13);
        step;
        chk_alu("T2 I3 = 13-3 = 10 (next cycle)",      1'b1, 3'd3, 32'd10);
        step;
        chk_alu("T2 chain done",                       1'b0, 0, 0);

        // ---------------- T3: branches ----------------
        do_reset;
        alloc(OP_BEQ, 3'd3, 1'b0, 3'd0, 32'd4, 1'b0, 3'd0, 32'd4, 32'h0000_1000);
        chk_br ("T3 no resolve in the alloc cycle",    1'b0, 0, 0);
        step;
        chk_br ("T3 BEQ equal resolves taken",         1'b1, 1'b1, 32'h0000_1000);
        chk_alu("T3 branch broadcasts 0 on cdb_alu",   1'b1, 3'd3, 32'd0);
        step;
        chk_br ("T3 resolve lasts one cycle",          1'b0, 0, 0);

        alloc(OP_BNE, 3'd4, 1'b0, 3'd0, 32'd4, 1'b0, 3'd0, 32'd4, 32'h0000_2000);
        step;
        chk_br ("T3 BNE equal resolves not taken",     1'b1, 1'b0, 32'h0000_2000);
        chk_alu("T3 BNE broadcasts 0",                 1'b1, 3'd4, 32'd0);
        step;

        alloc(OP_BLT, 3'd5, 1'b0, 3'd0, 32'hFFFF_FFFF, 1'b0, 3'd0, 32'd1, 32'h0000_3000);
        step;
        chk_br ("T3 BLT -1 < 1 taken (signed)",        1'b1, 1'b1, 32'h0000_3000);
        step;

        // ---------------- T4: JALR ----------------
        // vj = rs1 = 0x101, vk = link (pc+4) = 0x2004, a = imm = 0
        alloc(OP_JALR, 3'd6, 1'b0, 3'd0, 32'h0000_0101, 1'b0, 3'd0, 32'h0000_2004, 32'd0);
        step;
        chk_alu("T4 JALR puts the link on cdb_alu",    1'b1, 3'd6, 32'h0000_2004);
        chk_br ("T4 JALR taken, bit 0 cleared",        1'b1, 1'b1, 32'h0000_0100);
        step;

        // ---------------- T5: cdb_alu + cdb_mul in the same cycle ----------------
        // P: add tag1 = x(tag4 from DIV) + 100
        // C: add tag2 = P (cdb_alu) + y(tag6 from MUL)
        do_reset;
        alloc(OP_ADD, 3'd1, 1'b1, 3'd4, 32'd0, 1'b0, 3'd0, 32'd100, 32'd0);  step;
        alloc(OP_ADD, 3'd2, 1'b1, 3'd1, 32'd0, 1'b1, 3'd6, 32'd0,   32'd0);  step;
        bus(2, 3'd4, 32'd23);                                   // DIV delivers 23
        step;
        // P broadcasts 123 on cdb_alu while MUL broadcasts tag 6 = 1000
        bus(1, 3'd6, 32'd1000);
        chk_alu("T5 P broadcasts 123 on cdb_alu",      1'b1, 3'd1, 32'd123);
        pass_or_fail("T5 ALU and MUL buses active together",
                     cdb_valid[`CDB_ALU] === 1'b1 && cdb_valid[`CDB_MUL] === 1'b1);
        step;
        chk_alu("T5 C got both: 123 + 1000 = 1123",    1'b1, 3'd2, 32'd1123);
        step;
        chk_alu("T5 done",                             1'b0, 0, 0);

        // ---------------- verdict ----------------
        if (n_fail == 0)
            $display("TEST_PASS alu_path %0d", n_pass);
        else
            $display("TEST_FAIL alu_path %0d of %0d checks failed",
                     n_fail, n_pass + n_fail);
        $finish;
    end

endmodule
