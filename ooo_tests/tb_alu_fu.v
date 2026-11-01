`timescale 1ns/1ps
// tb_alu_fu.v - Self-checking testbench for alu_fu arithmetic, branches, and jumps.
module tb_alu_fu;

    reg  [7:0]  op;
    reg  [31:0] vj, vk, a;
    wire [31:0] result, target;
    wire        is_ctrl, taken;

    alu_fu dut (
        .op(op), .vj(vj), .vk(vk), .a(a),
        .result(result), .is_ctrl(is_ctrl), .taken(taken), .target(target)
    );

    // op encoding (D16): [2:0] funct3, [3] sub/sra, [4] is_branch, [5] is_jalr
    localparam [7:0] OP_ADD  = 8'h00, OP_SUB  = 8'h08,
                     OP_SLL  = 8'h01, OP_SLT  = 8'h02, OP_SLTU = 8'h03,
                     OP_XOR  = 8'h04, OP_SRL  = 8'h05, OP_SRA  = 8'h0D,
                     OP_OR   = 8'h06, OP_AND  = 8'h07;

    localparam [7:0] OP_BEQ  = 8'h10, OP_BNE  = 8'h11,
                     OP_BLT  = 8'h14, OP_BGE  = 8'h15,
                     OP_BLTU = 8'h16, OP_BGEU = 8'h17;

    localparam [7:0] OP_JALR = 8'h20;

    localparam [31:0] BR_TGT = 32'h0000_1000;   // any target will do for branches

    integer n_pass, n_fail;

    // -----------------------------------------------------------------------
    // the one place that actually compares things
    // -----------------------------------------------------------------------
    task check;
        input [8*24:1] name;
        input [7:0]    t_op;
        input [31:0]   t_vj, t_vk, t_a;
        input [31:0]   e_result;
        input          e_ctrl, e_taken;
        input [31:0]   e_target;
        begin
            op = t_op; vj = t_vj; vk = t_vk; a = t_a;
            #1;
            if (result === e_result && is_ctrl === e_ctrl &&
                taken  === e_taken  && target  === e_target) begin
                n_pass = n_pass + 1;
            end else begin
                n_fail = n_fail + 1;
                $display("TEST_FAIL alu_fu [%0s] at t=%0t  op=%h vj=%h vk=%h a=%h",
                         name, $time, t_op, t_vj, t_vk, t_a);
                $display("    expected: result=%h is_ctrl=%b taken=%b target=%h",
                         e_result, e_ctrl, e_taken, e_target);
                $display("    got     : result=%h is_ctrl=%b taken=%b target=%h",
                         result, is_ctrl, taken, target);
            end
        end
    endtask

    // plain ALU op: not control flow, so ctrl/taken/target must all stay 0
    task alu_chk;
        input [8*24:1] name;
        input [7:0]    t_op;
        input [31:0]   t_vj, t_vk, e_result;
        begin
            check(name, t_op, t_vj, t_vk, 32'h0, e_result, 1'b0, 1'b0, 32'h0);
        end
    endtask

    // conditional branch: result is always 0, target is always a,
    // only 'taken' depends on the comparison
    task br_chk;
        input [8*24:1] name;
        input [7:0]    t_op;
        input [31:0]   t_vj, t_vk;
        input          e_taken;
        begin
            check(name, t_op, t_vj, t_vk, BR_TGT, 32'h0, 1'b1, e_taken, BR_TGT);
        end
    endtask

    // -----------------------------------------------------------------------
    // reference model for the random section. SRA is written differently
    // from the DUT on purpose (shift + fill mask), so the two don't share a bug.
    // -----------------------------------------------------------------------
    function [31:0] ref_alu;
        input [7:0]  f_op;
        input [31:0] x, y;
        reg   [4:0]  sh;
        begin
            sh = y[4:0];
            case (f_op)
                OP_ADD:  ref_alu = x + y;
                OP_SUB:  ref_alu = x - y;
                OP_SLL:  ref_alu = x << sh;
                OP_SLT:  ref_alu = ($signed(x) < $signed(y)) ? 32'd1 : 32'd0;
                OP_SLTU: ref_alu = (x < y) ? 32'd1 : 32'd0;
                OP_XOR:  ref_alu = x ^ y;
                OP_SRL:  ref_alu = x >> sh;
                OP_SRA:  ref_alu = (x >> sh) | (x[31] ? ~(32'hFFFF_FFFF >> sh) : 32'h0);
                OP_OR:   ref_alu = x | y;
                OP_AND:  ref_alu = x & y;
                default: ref_alu = 32'h0;
            endcase
        end
    endfunction

    reg [7:0]  alu_ops [0:9];
    reg [31:0] rx, ry;
    reg [7:0]  rop;
    integer    i, seed;

    initial begin
        n_pass = 0;
        n_fail = 0;
        op = 0; vj = 0; vk = 0; a = 0;

        // ---------------- 1. register ALU ops ----------------
        alu_chk("ADD basic",        OP_ADD, 32'd5,         32'd7,         32'd12);
        alu_chk("ADD wraps",        OP_ADD, 32'hFFFF_FFFF, 32'd1,         32'h0);
        alu_chk("ADD overflow",     OP_ADD, 32'h7FFF_FFFF, 32'd1,         32'h8000_0000);
        alu_chk("SUB basic",        OP_SUB, 32'd7,         32'd5,         32'd2);
        alu_chk("SUB negative",     OP_SUB, 32'd5,         32'd7,         32'hFFFF_FFFE);
        alu_chk("SUB 0-1",          OP_SUB, 32'd0,         32'd1,         32'hFFFF_FFFF);

        alu_chk("SLT -1<1",         OP_SLT, 32'hFFFF_FFFF, 32'd1,         32'd1);
        alu_chk("SLT 1<-1",         OP_SLT, 32'd1,         32'hFFFF_FFFF, 32'd0);
        alu_chk("SLT min<1",        OP_SLT, 32'h8000_0000, 32'd1,         32'd1);
        alu_chk("SLT equal",        OP_SLT, 32'd42,        32'd42,        32'd0);
        alu_chk("SLTU big<1",       OP_SLTU,32'hFFFF_FFFF, 32'd1,         32'd0);
        alu_chk("SLTU 1<big",       OP_SLTU,32'd1,         32'hFFFF_FFFF, 32'd1);
        alu_chk("SLTU 8000..<1",    OP_SLTU,32'h8000_0000, 32'd1,         32'd0);
        alu_chk("SLTU 0<0",         OP_SLTU,32'd0,         32'd0,         32'd0);

        alu_chk("XOR",              OP_XOR, 32'hF0F0_F0F0, 32'hFF00_FF00, 32'h0FF0_0FF0);
        alu_chk("OR",               OP_OR,  32'hF0F0_F0F0, 32'h0F0F_0F0F, 32'hFFFF_FFFF);
        alu_chk("AND",              OP_AND, 32'hF0F0_F0F0, 32'hFF00_FF00, 32'hF000_F000);

        // an ALU op must not leak 'a' into target
        check  ("ADD ignores a",    OP_ADD, 32'd1, 32'd2, 32'h0000_1234,
                                    32'd3, 1'b0, 1'b0, 32'h0);

        // ---------------- 2. immediate forms (imm already in vk) -------------
        alu_chk("ADDI x+(-1)",      OP_ADD, 32'd10,        32'hFFFF_FFFF, 32'd9);
        alu_chk("SLTI -5<-3",       OP_SLT, 32'hFFFF_FFFB, 32'hFFFF_FFFD, 32'd1);
        alu_chk("SLTIU 5<u -1",     OP_SLTU,32'd5,         32'hFFFF_FFFF, 32'd1);
        alu_chk("XORI -1 (NOT)",    OP_XOR, 32'h1234_5678, 32'hFFFF_FFFF, 32'hEDCB_A987);
        alu_chk("ORI",              OP_OR,  32'h1234_0000, 32'h0000_0ABC, 32'h1234_0ABC);
        alu_chk("ANDI 0xFF",        OP_AND, 32'h1234_5678, 32'h0000_00FF, 32'h0000_0078);
        alu_chk("SLLI 3",           OP_SLL, 32'd1,         32'd3,         32'd8);
        alu_chk("SRLI 8",           OP_SRL, 32'hABCD_0000, 32'd8,         32'h00AB_CD00);
        alu_chk("SRAI 8",           OP_SRA, 32'hABCD_0000, 32'd8,         32'hFFAB_CD00);

        // ---------------- 3. shift amounts: only vk[4:0] counts --------------
        alu_chk("SLL by 0",         OP_SLL, 32'd1,         32'd0,         32'd1);
        alu_chk("SLL by 31",        OP_SLL, 32'd1,         32'd31,        32'h8000_0000);
        alu_chk("SLL by 32 = by 0", OP_SLL, 32'd1,         32'd32,        32'd1);
        alu_chk("SLL by 33 = by 1", OP_SLL, 32'd1,         32'd33,        32'd2);
        alu_chk("SLL high bits",    OP_SLL, 32'd1,         32'hFFFF_FFE1, 32'd2);

        alu_chk("SRL by 4",         OP_SRL, 32'h8000_0000, 32'd4,         32'h0800_0000);
        alu_chk("SRL by 31",        OP_SRL, 32'h8000_0000, 32'd31,        32'd1);
        alu_chk("SRL by 32 = by 0", OP_SRL, 32'h8000_0000, 32'd32,        32'h8000_0000);
        alu_chk("SRL by 33 = by 1", OP_SRL, 32'h8000_0000, 32'd33,        32'h4000_0000);

        // the one that catches the ?: signedness trap
        alu_chk("SRA min by 4",     OP_SRA, 32'h8000_0000, 32'd4,         32'hF800_0000);
        alu_chk("SRA min by 31",    OP_SRA, 32'h8000_0000, 32'd31,        32'hFFFF_FFFF);
        alu_chk("SRA by 32 = by 0", OP_SRA, 32'h8000_0000, 32'd32,        32'h8000_0000);
        alu_chk("SRA by 33 = by 1", OP_SRA, 32'h8000_0000, 32'd33,        32'hC000_0000);
        alu_chk("SRA -8 by 1",      OP_SRA, 32'hFFFF_FFF8, 32'd1,         32'hFFFF_FFFC);
        alu_chk("SRA positive",     OP_SRA, 32'h4000_0000, 32'd4,         32'h0400_0000);

        // ---------------- 4. branches ----------------
        br_chk("BEQ equal",         OP_BEQ,  32'd5,         32'd5,         1'b1);
        br_chk("BEQ differ",        OP_BEQ,  32'd5,         32'd6,         1'b0);
        br_chk("BNE equal",         OP_BNE,  32'd5,         32'd5,         1'b0);
        br_chk("BNE differ",        OP_BNE,  32'd5,         32'd6,         1'b1);

        br_chk("BLT less",          OP_BLT,  32'd2,         32'd3,         1'b1);
        br_chk("BLT equal",         OP_BLT,  32'd3,         32'd3,         1'b0);
        br_chk("BLT greater",       OP_BLT,  32'd4,         32'd3,         1'b0);
        br_chk("BLT -1<1",          OP_BLT,  32'hFFFF_FFFF, 32'd1,         1'b1);
        br_chk("BLT min<max",       OP_BLT,  32'h8000_0000, 32'h7FFF_FFFF, 1'b1);

        br_chk("BGE less",          OP_BGE,  32'd2,         32'd3,         1'b0);
        br_chk("BGE equal",         OP_BGE,  32'd3,         32'd3,         1'b1);
        br_chk("BGE greater",       OP_BGE,  32'd4,         32'd3,         1'b1);
        br_chk("BGE -1>=1",         OP_BGE,  32'hFFFF_FFFF, 32'd1,         1'b0);

        br_chk("BLTU less",         OP_BLTU, 32'd2,         32'd3,         1'b1);
        br_chk("BLTU equal",        OP_BLTU, 32'd3,         32'd3,         1'b0);
        br_chk("BLTU greater",      OP_BLTU, 32'd4,         32'd3,         1'b0);
        br_chk("BLTU big<1",        OP_BLTU, 32'hFFFF_FFFF, 32'd1,         1'b0);
        br_chk("BLTU min<max",      OP_BLTU, 32'h8000_0000, 32'h7FFF_FFFF, 1'b0);

        br_chk("BGEU less",         OP_BGEU, 32'd2,         32'd3,         1'b0);
        br_chk("BGEU equal",        OP_BGEU, 32'd3,         32'd3,         1'b1);
        br_chk("BGEU greater",      OP_BGEU, 32'd4,         32'd3,         1'b1);
        br_chk("BGEU big>=1",       OP_BGEU, 32'hFFFF_FFFF, 32'd1,         1'b1);

        // ---------------- 5. JALR ----------------
        // vj = rs1, vk = link value (pc+4), a = imm
        check("JALR basic",  OP_JALR, 32'h0000_0100, 32'h0000_2004, 32'd4,
                             32'h0000_2004, 1'b1, 1'b1, 32'h0000_0104);
        check("JALR odd",    OP_JALR, 32'h0000_0101, 32'h0000_2004, 32'd0,
                             32'h0000_2004, 1'b1, 1'b1, 32'h0000_0100);
        check("JALR neg imm",OP_JALR, 32'h0000_0100, 32'h0000_3008, 32'hFFFF_FFFF,
                             32'h0000_3008, 1'b1, 1'b1, 32'h0000_00FE);

        // ---------------- 6. random ALU vectors ----------------
        alu_ops[0] = OP_ADD;  alu_ops[1] = OP_SUB;  alu_ops[2] = OP_SLL;
        alu_ops[3] = OP_SLT;  alu_ops[4] = OP_SLTU; alu_ops[5] = OP_XOR;
        alu_ops[6] = OP_SRL;  alu_ops[7] = OP_SRA;  alu_ops[8] = OP_OR;
        alu_ops[9] = OP_AND;

        seed = 2026;
        for (i = 0; i < 2000; i = i + 1) begin
            rx  = $random(seed);
            ry  = $random(seed);
            rop = alu_ops[($random(seed) & 32'h7FFF_FFFF) % 10];
            alu_chk("random", rop, rx, ry, ref_alu(rop, rx, ry));
        end

        // ---------------- verdict ----------------
        if (n_fail == 0)
            $display("TEST_PASS alu_fu %0d", n_pass);
        else
            $display("TEST_FAIL alu_fu %0d of %0d vectors failed",
                     n_fail, n_pass + n_fail);
        $finish;
    end

endmodule
