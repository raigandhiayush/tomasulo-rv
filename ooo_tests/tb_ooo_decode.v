// tb_ooo_decode.v -- self-checking testbench for ooo_decode (owner D).
// Blueprint §6.2 test groups:
//   (1) every baseline RV32I instruction (36) -- encoded by helper functions
//       and also a few real machine words as they appear in code.dis;
//   (2) all 8 RV32M encodings;
//   (3) unsupported words (ECALL, EBREAK, FENCE, CSR, 0x00000000, AUIPC with
//       SUPPORT_AUIPC=0, bad funct3/funct7) give illegal=1, cls=CLS_NOP;
//   (4) negative immediates for every format.
// Plus: 200,000 random words checked for legality against the RISC-V
// MATCH/MASK table (riscv-opcodes style, independent of the RTL's case code),
// and 50,000 random legal instructions whose fields/immediates are encoded by
// the testbench and must decode back exactly.
//
// Field conventions checked (decided by the RTL, consistent with
// SIGNALS_REFERENCE §2.5): unused rs1/rs2/rd fields are 0; funct3 is 0 for
// LUI/AUIPC/JAL/JALR; imm=0 for R-type; pre_value=0 except PRE classes and
// JALR (pc+4); br_target=0 except branches/JAL (pc+imm).
// JALR br_target is NOT checked: the spec leaves it open (RS 'a' = imm, D16).
// Prints TEST_PASS ooo_decode <n> or TEST_FAIL ... with expected/actual.
`timescale 1ns/1ps
`include "ooo_defs.vh"

module tb_ooo_decode;
    reg  [31:0] inst = 0, pc = 0;

    // DUT 0: default (AUIPC illegal); DUT 1: SUPPORT_AUIPC=1 (Goal G3)
    wire [2:0]  cls      [0:1];
    wire        illegal  [0:1];
    wire [2:0]  funct3   [0:1];
    wire        sub      [0:1];
    wire [4:0]  rs1 [0:1], rs2 [0:1], rd [0:1];
    wire        uses_rs1 [0:1], uses_rs2 [0:1], writes_rd [0:1], use_imm [0:1];
    wire [31:0] imm [0:1], pre_value [0:1], br_target [0:1];
    wire        is_jal [0:1], is_jalr [0:1], is_branch [0:1];

    genvar g;
    generate for (g = 0; g < 2; g = g + 1) begin : dut
        ooo_decode #(.SUPPORT_AUIPC(g)) u (
            .inst(inst), .pc(pc), .cls(cls[g]), .illegal(illegal[g]), .funct3(funct3[g]),
            .sub(sub[g]), .rs1(rs1[g]), .rs2(rs2[g]), .rd(rd[g]),
            .uses_rs1(uses_rs1[g]), .uses_rs2(uses_rs2[g]), .writes_rd(writes_rd[g]),
            .use_imm(use_imm[g]), .imm(imm[g]), .pre_value(pre_value[g]),
            .is_jal(is_jal[g]), .is_jalr(is_jalr[g]), .is_branch(is_branch[g]),
            .br_target(br_target[g]));
    end endgenerate

    // ---------------- encoders (independent of the RTL) ----------------
    localparam [6:0] OP_LUI=7'h37, OP_AUIPC=7'h17, OP_JAL=7'h6f, OP_JALR=7'h67,
                     OP_BR=7'h63, OP_LD=7'h03, OP_ST=7'h23, OP_I=7'h13, OP_R=7'h33;

    function [31:0] enc_r(input [6:0] f7, input [4:0] s2, input [4:0] s1, input [2:0] f3, input [4:0] d, input [6:0] op);
        enc_r = {f7, s2, s1, f3, d, op};
    endfunction
    function [31:0] enc_i(input [11:0] im, input [4:0] s1, input [2:0] f3, input [4:0] d, input [6:0] op);
        enc_i = {im, s1, f3, d, op};
    endfunction
    function [31:0] enc_s(input [11:0] im, input [4:0] s2, input [4:0] s1, input [2:0] f3);
        enc_s = {im[11:5], s2, s1, f3, im[4:0], OP_ST};
    endfunction
    function [31:0] enc_b(input [12:0] im, input [4:0] s2, input [4:0] s1, input [2:0] f3);
        enc_b = {im[12], im[10:5], s2, s1, f3, im[4:1], im[11], OP_BR};
    endfunction
    function [31:0] enc_u(input [19:0] im, input [4:0] d, input [6:0] op);
        enc_u = {im, d, op};
    endfunction
    function [31:0] enc_j(input [20:0] im, input [4:0] d);
        enc_j = {im[20], im[10:1], im[11], im[19:12], d, OP_JAL};
    endfunction

    // ---------------- checking ----------------
    integer nvec = 0, nfail = 0;
    reg [8*12-1:0] cur_name;

    task fail(input [8*12-1:0] what, input [31:0] exp, input [31:0] act, input integer d);
        begin
            nfail = nfail + 1;
            if (nfail <= 30)
                $display("TEST_FAIL ooo_decode %0s inst=%h pc=%h dut%0d %0s expected=%h actual=%h",
                         cur_name, inst, pc, d, what, exp, act);
        end
    endtask

    // Full expected-value check of one decoded instruction on DUT d.
    task expect_all(input integer d,
                    input [2:0] e_cls, input e_ill, input [2:0] e_f3, input e_sub,
                    input [4:0] e_rs1, input [4:0] e_rs2, input [4:0] e_rd,
                    input e_u1, input e_u2, input e_wr, input e_ui,
                    input [31:0] e_imm, input [31:0] e_pre,
                    input e_jal, input e_jalr, input e_br,
                    input [31:0] e_bt, input chk_bt);
        begin
            nvec = nvec + 1;
            if (cls[d]       !== e_cls) fail("cls",       e_cls, cls[d], d);
            if (illegal[d]   !== e_ill) fail("illegal",   e_ill, illegal[d], d);
            if (funct3[d]    !== e_f3)  fail("funct3",    e_f3,  funct3[d], d);
            if (sub[d]       !== e_sub) fail("sub",       e_sub, sub[d], d);
            if (rs1[d]       !== e_rs1) fail("rs1",       e_rs1, rs1[d], d);
            if (rs2[d]       !== e_rs2) fail("rs2",       e_rs2, rs2[d], d);
            if (rd[d]        !== e_rd)  fail("rd",        e_rd,  rd[d], d);
            if (uses_rs1[d]  !== e_u1)  fail("uses_rs1",  e_u1,  uses_rs1[d], d);
            if (uses_rs2[d]  !== e_u2)  fail("uses_rs2",  e_u2,  uses_rs2[d], d);
            if (writes_rd[d] !== e_wr)  fail("writes_rd", e_wr,  writes_rd[d], d);
            if (use_imm[d]   !== e_ui)  fail("use_imm",   e_ui,  use_imm[d], d);
            if (imm[d]       !== e_imm) fail("imm",       e_imm, imm[d], d);
            if (pre_value[d] !== e_pre) fail("pre_value", e_pre, pre_value[d], d);
            if (is_jal[d]    !== e_jal) fail("is_jal",    e_jal, is_jal[d], d);
            if (is_jalr[d]   !== e_jalr)fail("is_jalr",   e_jalr,is_jalr[d], d);
            if (is_branch[d] !== e_br)  fail("is_branch", e_br,  is_branch[d], d);
            if (chk_bt && br_target[d] !== e_bt) fail("br_target", e_bt, br_target[d], d);
        end
    endtask

    task expect_illegal(input integer d);
        expect_all(d, `CLS_NOP, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1);
    endtask

    // Kinds used by the generic per-format checker
    localparam K_R=0, K_M=1, K_I=2, K_SH=3, K_LD=4, K_ST=5, K_BR=6, K_JAL=7, K_JALR=8, K_LUI=9, K_AUIPC=10;

    // Encode an instruction of the given kind, apply it, and check both DUTs.
    task run(input integer kind, input [2:0] f3, input alt, input [4:0] s1, input [4:0] s2,
             input [4:0] d, input [31:0] immv, input [31:0] pcv);
        reg [31:0] w, sx;
        integer   k;
        begin
            case (kind)
                K_R:    w = enc_r(alt ? 7'h20 : 7'h00, s2, s1, f3, d, OP_R);
                K_M:    w = enc_r(7'h01, s2, s1, f3, d, OP_R);
                K_I:    w = enc_i(immv[11:0], s1, f3, d, OP_I);
                K_SH:   w = enc_i({alt ? 7'h20 : 7'h00, immv[4:0]}, s1, f3, d, OP_I);
                K_LD:   w = enc_i(immv[11:0], s1, f3, d, OP_LD);
                K_ST:   w = enc_s(immv[11:0], s2, s1, f3);
                K_BR:   w = enc_b(immv[12:0], s2, s1, f3);
                K_JAL:  w = enc_j(immv[20:0], d);
                K_JALR: w = enc_i(immv[11:0], s1, 3'b000, d, OP_JALR);
                K_LUI:  w = enc_u(immv[31:12], d, OP_LUI);
                default:w = enc_u(immv[31:12], d, OP_AUIPC);
            endcase
            inst = w; pc = pcv; #1;
            for (k = 0; k < 2; k = k + 1) case (kind)
                K_R:    expect_all(k, `CLS_ALU, 0, f3, alt, s1, s2, d, 1, 1, d != 0, 0, 0, 0, 0,0,0, 0, 1);
                K_M:    expect_all(k, f3[2] ? `CLS_DIV : `CLS_MUL, 0, f3, 0, s1, s2, d, 1, 1, d != 0, 0, 0, 0, 0,0,0, 0, 1);
                K_I:    expect_all(k, `CLS_ALU, 0, f3, 0, s1, 0, d, 1, 0, d != 0, 1,
                                   {{20{immv[11]}}, immv[11:0]}, 0, 0,0,0, 0, 1);
                K_SH:   expect_all(k, `CLS_ALU, 0, f3, alt & (f3 == 3'b101), s1, 0, d, 1, 0, d != 0, 1,
                                   {20'd0, alt ? 7'h20 : 7'h00, immv[4:0]}, 0, 0,0,0, 0, 1);
                K_LD:   expect_all(k, `CLS_LD, 0, f3, 0, s1, 0, d, 1, 0, d != 0, 1,
                                   {{20{immv[11]}}, immv[11:0]}, 0, 0,0,0, 0, 1);
                K_ST:   expect_all(k, `CLS_ST, 0, f3, 0, s1, s2, 0, 1, 1, 0, 1,
                                   {{20{immv[11]}}, immv[11:0]}, 0, 0,0,0, 0, 1);
                K_BR:   begin sx = {{19{immv[12]}}, immv[12:1], 1'b0};
                        expect_all(k, `CLS_BR, 0, f3, 0, s1, s2, 0, 1, 1, 0, 0,
                                   sx, 0, 0,0,1, pcv + sx, 1); end
                K_JAL:  begin sx = {{11{immv[20]}}, immv[20:1], 1'b0};
                        expect_all(k, `CLS_PRE, 0, 0, 0, 0, 0, d, 0, 0, d != 0, 0,
                                   sx, pcv + 4, 1,0,0, pcv + sx, 1); end
                K_JALR: expect_all(k, `CLS_BR, 0, 0, 0, s1, 0, d, 1, 0, d != 0, 0,
                                   {{20{immv[11]}}, immv[11:0]}, pcv + 4, 0,1,0, 0, 0);
                K_LUI:  expect_all(k, `CLS_PRE, 0, 0, 0, 0, 0, d, 0, 0, d != 0, 0,
                                   {immv[31:12], 12'd0}, {immv[31:12], 12'd0}, 0,0,0, 0, 1);
                default: if (k == 0) expect_illegal(0);
                         else expect_all(1, `CLS_PRE, 0, 0, 0, 0, 0, d, 0, 0, d != 0, 0,
                                   {immv[31:12], 12'd0}, pcv + {immv[31:12], 12'd0}, 0,0,0, 0, 1);
            endcase
        end
    endtask

    // ---------------- MATCH/MASK legality reference (RISC-V spec tables) ----------------
    reg [31:0] t_match [0:44];
    reg [31:0] t_mask  [0:44];
    reg [2:0]  t_cls   [0:44];
    integer    t_n;
    task add(input [31:0] m, input [31:0] k, input [2:0] c);
        begin t_match[t_n] = m; t_mask[t_n] = k; t_cls[t_n] = c; t_n = t_n + 1; end
    endtask
    // returns table index or -1
    function integer lookup(input [31:0] w, input aui);
        integer q;
        begin
            lookup = -1;
            for (q = 0; q < t_n; q = q + 1)
                if ((w & t_mask[q]) == t_match[q] && (aui || t_match[q] != 32'h17)) lookup = q;
        end
    endfunction

    // ---------------- stimulus ----------------
    integer n, kind, q, dd;
    reg [2:0]  rf3;
    reg [31:0] rimm, rpc;
    reg        ralt;

    initial begin
        t_n = 0;
        add(32'h00000037, 32'h0000007f, `CLS_PRE); // lui
        add(32'h00000017, 32'h0000007f, `CLS_PRE); // auipc (DUT1 only)
        add(32'h0000006f, 32'h0000007f, `CLS_PRE); // jal
        add(32'h00000067, 32'h0000707f, `CLS_BR);  // jalr
        add(32'h00000063, 32'h0000707f, `CLS_BR);  add(32'h00001063, 32'h0000707f, `CLS_BR);
        add(32'h00004063, 32'h0000707f, `CLS_BR);  add(32'h00005063, 32'h0000707f, `CLS_BR);
        add(32'h00006063, 32'h0000707f, `CLS_BR);  add(32'h00007063, 32'h0000707f, `CLS_BR);
        add(32'h00000003, 32'h0000707f, `CLS_LD);  add(32'h00001003, 32'h0000707f, `CLS_LD);
        add(32'h00002003, 32'h0000707f, `CLS_LD);  add(32'h00004003, 32'h0000707f, `CLS_LD);
        add(32'h00005003, 32'h0000707f, `CLS_LD);
        add(32'h00000023, 32'h0000707f, `CLS_ST);  add(32'h00001023, 32'h0000707f, `CLS_ST);
        add(32'h00002023, 32'h0000707f, `CLS_ST);
        add(32'h00000013, 32'h0000707f, `CLS_ALU); add(32'h00002013, 32'h0000707f, `CLS_ALU);
        add(32'h00003013, 32'h0000707f, `CLS_ALU); add(32'h00004013, 32'h0000707f, `CLS_ALU);
        add(32'h00006013, 32'h0000707f, `CLS_ALU); add(32'h00007013, 32'h0000707f, `CLS_ALU);
        add(32'h00001013, 32'hfe00707f, `CLS_ALU); add(32'h00005013, 32'hfe00707f, `CLS_ALU);
        add(32'h40005013, 32'hfe00707f, `CLS_ALU);
        add(32'h00000033, 32'hfe00707f, `CLS_ALU); add(32'h40000033, 32'hfe00707f, `CLS_ALU);
        add(32'h00001033, 32'hfe00707f, `CLS_ALU); add(32'h00002033, 32'hfe00707f, `CLS_ALU);
        add(32'h00003033, 32'hfe00707f, `CLS_ALU); add(32'h00004033, 32'hfe00707f, `CLS_ALU);
        add(32'h00005033, 32'hfe00707f, `CLS_ALU); add(32'h40005033, 32'hfe00707f, `CLS_ALU);
        add(32'h00006033, 32'hfe00707f, `CLS_ALU); add(32'h00007033, 32'hfe00707f, `CLS_ALU);
        for (q = 0; q < 8; q = q + 1)
            add(32'h02000033 | (q << 12), 32'hfe00707f, q < 4 ? `CLS_MUL : `CLS_DIV);

        // ===== (1)+(2) every supported instruction, typical and x0 destinations =====
        cur_name = "R-ALU";
        for (q = 0; q < 8; q = q + 1) begin
            run(K_R, q, 0, 5'd11, 5'd12, 5'd10, 0, 32'h100);
            if (q == 0 || q == 5) run(K_R, q, 1, 5'd31, 5'd1, 5'd31, 0, 32'h100); // SUB, SRA
        end
        cur_name = "RV32M";
        for (q = 0; q < 8; q = q + 1) begin
            run(K_M, q, 0, 5'd5, 5'd6, 5'd7, 0, 32'h104);
            run(K_M, q, 0, 5'd5, 5'd6, 5'd0, 0, 32'h104);   // rd = x0: writes_rd = 0
        end
        cur_name = "I-ALU";
        run(K_I, 3'b000, 0, 5'd2, 0, 5'd2, 32'hFFFFFFE0, 32'h0);   // addi sp,sp,-32
        run(K_I, 3'b010, 0, 5'd3, 0, 5'd4, 32'h000007FF, 32'h0);   // slti  +2047
        run(K_I, 3'b011, 0, 5'd3, 0, 5'd4, 32'hFFFFF800, 32'h0);   // sltiu -2048
        run(K_I, 3'b100, 0, 5'd3, 0, 5'd4, 32'hFFFFFFFF, 32'h0);   // xori  -1
        run(K_I, 3'b110, 0, 5'd3, 0, 5'd4, 32'h00000555, 32'h0);   // ori
        run(K_I, 3'b111, 0, 5'd3, 0, 5'd0, 32'h00000F0F, 32'h0);   // andi rd=x0, neg imm
        run(K_I, 3'b000, 0, 5'd0, 0, 5'd0, 32'h0, 32'h0);          // nop = addi x0,x0,0
        cur_name = "shift-imm";
        run(K_SH, 3'b001, 0, 5'd9, 0, 5'd8, 31, 32'h0);            // slli 31
        run(K_SH, 3'b101, 0, 5'd9, 0, 5'd8, 0,  32'h0);            // srli 0
        run(K_SH, 3'b101, 1, 5'd9, 0, 5'd8, 17, 32'h0);            // srai 17 -> sub=1
        cur_name = "load";
        run(K_LD, 3'b000, 0, 5'd1, 0, 5'd5, 32'hFFFFFFFF, 32'h0);  // lb  -1
        run(K_LD, 3'b001, 0, 5'd1, 0, 5'd5, 32'h00000002, 32'h0);  // lh
        run(K_LD, 3'b010, 0, 5'd2, 0, 5'd1, 32'h0000001C, 32'h0);  // lw ra,28(sp)
        run(K_LD, 3'b100, 0, 5'd1, 0, 5'd5, 32'hFFFFF800, 32'h0);  // lbu -2048
        run(K_LD, 3'b101, 0, 5'd1, 0, 5'd0, 32'h000007FF, 32'h0);  // lhu, rd=x0
        cur_name = "store";
        run(K_ST, 3'b000, 0, 5'd1, 5'd7, 0, 32'hFFFFFFFF, 32'h0);  // sb -1
        run(K_ST, 3'b001, 0, 5'd1, 5'd7, 0, 32'hFFFFF800, 32'h0);  // sh -2048
        run(K_ST, 3'b010, 0, 5'd2, 5'd1, 0, 32'h0000001C, 32'h0);  // sw ra,28(sp)
        cur_name = "branch";
        for (q = 0; q < 8; q = q + 1) if (q != 2 && q != 3) begin
            run(K_BR, q, 0, 5'd8, 5'd0, 0, 32'hFFFFFFF8, 32'h200);  // -8
            run(K_BR, q, 0, 5'd8, 5'd9, 0, 32'h00000FFE, 32'h200);  // +4094 (max)
            run(K_BR, q, 0, 5'd8, 5'd9, 0, 32'hFFFFF000, 32'h2000); // -4096 (min)
        end
        cur_name = "jal";
        run(K_JAL, 0, 0, 0, 0, 5'd1, 32'hFFFFFFFC, 32'h40);        // jal ra,-4
        run(K_JAL, 0, 0, 0, 0, 5'd0, 32'h000FFFFE, 32'h40);        // j +max
        run(K_JAL, 0, 0, 0, 0, 5'd1, 32'hFFF00000, 32'h00100000);  // jal -min
        cur_name = "jalr";
        run(K_JALR, 0, 0, 5'd1, 0, 5'd0, 32'h0, 32'h80);           // ret
        run(K_JALR, 0, 0, 5'd6, 0, 5'd1, 32'hFFFFFFF0, 32'h80);    // jalr ra,-16(t1)
        cur_name = "lui/auipc";
        run(K_LUI,   0, 0, 0, 0, 5'd1, 32'h80000000, 32'h0);
        run(K_LUI,   0, 0, 0, 0, 5'd0, 32'h12345000, 32'h0);
        run(K_AUIPC, 0, 0, 0, 0, 5'd3, 32'hFFFFF000, 32'h1000);

        // ===== real machine words (as gcc emits them) =====
        cur_name = "real-words";
        inst = 32'hfe010113; pc = 0; #1;   // addi sp,sp,-32
        for (dd = 0; dd < 2; dd = dd + 1)
            expect_all(dd, `CLS_ALU,0,0,0, 2,0,2, 1,0,1,1, 32'hFFFFFFE0, 0, 0,0,0, 0,1);
        inst = 32'h00008067; pc = 32'h3c; #1;   // ret
        for (dd = 0; dd < 2; dd = dd + 1)
            expect_all(dd, `CLS_BR,0,0,0, 1,0,0, 1,0,0,0, 0, 32'h40, 0,1,0, 0,0);
        inst = 32'h00112e23; pc = 0; #1;   // sw ra,28(sp)
        for (dd = 0; dd < 2; dd = dd + 1)
            expect_all(dd, `CLS_ST,0,3'b010,0, 2,1,0, 1,1,0,1, 28, 0, 0,0,0, 0,1);
        inst = 32'h02c58533; pc = 0; #1;   // mul a0,a1,a2
        for (dd = 0; dd < 2; dd = dd + 1)
            expect_all(dd, `CLS_MUL,0,0,0, 11,12,10, 1,1,1,0, 0, 0, 0,0,0, 0,1);
        inst = 32'hffdff0ef; pc = 32'h20; #1;  // jal ra,-4
        for (dd = 0; dd < 2; dd = dd + 1)
            expect_all(dd, `CLS_PRE,0,0,0, 0,0,1, 0,0,1,0, 32'hFFFFFFFC, 32'h24, 1,0,0, 32'h1C,1);
        inst = 32'hfe000ce3; pc = 32'h30; #1;  // beq zero,zero,-8
        for (dd = 0; dd < 2; dd = dd + 1)
            expect_all(dd, `CLS_BR,0,0,0, 0,0,0, 1,1,0,0, 32'hFFFFFFF8, 0, 0,0,1, 32'h28,1);
        inst = 32'h800000b7; pc = 0; #1;   // lui ra,0x80000
        for (dd = 0; dd < 2; dd = dd + 1)
            expect_all(dd, `CLS_PRE,0,0,0, 0,0,1, 0,0,1,0, 32'h80000000, 32'h80000000, 0,0,0, 0,1);

        // ===== (3) unsupported / malformed words =====
        cur_name = "illegal";
        for (q = 0; q < 14; q = q + 1) begin
            case (q)
                0:  inst = 32'h00000073;  // ecall
                1:  inst = 32'h00100073;  // ebreak
                2:  inst = 32'h0ff0000f;  // fence
                3:  inst = 32'h30002573;  // csrr a0, mstatus
                4:  inst = 32'h00000000;  // all zero
                5:  inst = 32'hFFFFFFFF;  // all ones
                6:  inst = 32'h00001067;  // jalr with funct3=001
                7:  inst = 32'h00002063;  // branch funct3=010
                8:  inst = 32'h00003063;  // branch funct3=011
                9:  inst = 32'h00003003;  // load funct3=011 (ld, RV64)
                10: inst = 32'h00003023;  // store funct3=011 (sd, RV64)
                11: inst = 32'h40001033;  // sll with funct7=0100000
                12: inst = 32'h02001013;  // slli with imm[11:5]=0000001 (RV64 shamt)
                13: inst = 32'h80000033;  // add with funct7=1000000
            endcase
            pc = 32'h44; #1;
            expect_illegal(0); expect_illegal(1);
        end
        inst = 32'h00001517; pc = 32'h100; #1;  // auipc a0,1: illegal on DUT0 only
        expect_illegal(0);

        // ===== random words vs MATCH/MASK table (200,000) =====
        cur_name = "rand-word";
        for (n = 0; n < 200000; n = n + 1) begin
            inst = $urandom;
            if (n % 2) inst[6:0] = (n % 4 == 1) ? OP_R : OP_I;   // densify near-legal space
            if (n % 8 == 3) inst[1:0] = 2'b11;
            pc = {$urandom, 2'b00};
            #1;
            for (dd = 0; dd < 2; dd = dd + 1) begin
                q = lookup(inst, dd);
                nvec = nvec + 1;
                if (illegal[dd] !== (q < 0)) fail("illegal", q < 0, illegal[dd], dd);
                else if (q < 0) begin
                    if (cls[dd] !== `CLS_NOP || writes_rd[dd] !== 0 || uses_rs1[dd] !== 0 || uses_rs2[dd] !== 0)
                        fail("illegal-fields", 0, {cls[dd], writes_rd[dd], uses_rs1[dd], uses_rs2[dd]}, dd);
                end else begin
                    if (cls[dd] !== t_cls[q]) fail("cls", t_cls[q], cls[dd], dd);
                    if (writes_rd[dd] && rd[dd] == 0) fail("writes_rd&x0", 0, 1, dd);
                    if (!uses_rs2[dd] && rs2[dd] != 0) fail("rs2-unused", 0, rs2[dd], dd);
                end
            end
        end

        // ===== random legal instructions: encode -> decode round trip (50,000) =====
        cur_name = "round-trip";
        for (n = 0; n < 50000; n = n + 1) begin
            kind = $urandom % 11;
            rf3  = $urandom; ralt = $urandom; rimm = $urandom; rpc = {$urandom, 2'b00};
            case (kind)
                K_R:  if (!(rf3 == 0 || rf3 == 5)) ralt = 0;
                K_I:  while (rf3 == 1 || rf3 == 5) rf3 = $urandom;
                K_SH: begin rf3 = ($urandom % 2) ? 3'b001 : 3'b101; if (rf3 == 1) ralt = 0; end
                K_LD: while (rf3 == 3 || rf3 == 6 || rf3 == 7) rf3 = $urandom;
                K_ST: rf3 = $urandom % 3;
                K_BR: while (rf3 == 2 || rf3 == 3) rf3 = $urandom;
                default: ;
            endcase
            run(kind, rf3, ralt, $urandom, $urandom, $urandom, rimm, rpc);
        end

        if (nfail == 0) $display("TEST_PASS ooo_decode %0d", nvec);
        else            $display("TEST_FAIL ooo_decode %0d failures out of %0d checks", nfail, nvec);
        $finish;
    end
endmodule
