`timescale 1ns/1ps
`include "ooo_defs.vh"

`ifndef CMP_ROB
`define CMP_ROB 8
`endif
`ifndef CMP_END_INSN
`define CMP_END_INSN 32'h0000006F
`endif

module tb_top_fpga_cmp;
    localparam NPROG = 5, TIMEOUT = 200000, SEQN = 32768;
    localparam [1:0] ROB_CODE = (`CMP_ROB == 4) ? 2'b01 : (`CMP_ROB == 16) ? 2'b10 : 2'b00;

    reg clk = 1'b0;
    reg reset = 1'b0, rx = 1'b1, btn = 1'b0;
    reg [15:0] sw = 16'd0;
    always #5 clk = ~clk;

`ifdef CMP_VCD
    initial begin $dumpfile("tb_top_fpga_cmp.vcd"); $dumpvars(0, tb_top_fpga_cmp); end
`endif

    wire tx; wire [15:0] led; wire [7:0] seg, an;
    top_fpga_cmp #(.REFRESH_W(2)) DUT (.clk(clk), .reset(reset), .sw(sw), .led(led), .seg(seg), .an(an),
                                       .uart_rx(rx), .uart_tx(tx), .load_btn(btn), .btn(4'd0));

    // reference single-core tops
    wire [15:0] l0, l1, l2; wire [7:0] s0, s1, s2, a0, a1, a2; wire t1, t2, t0;
    top_fpga_base #(.CORE(1), .REFRESH_W(2)) RB (.clk(clk), .reset(reset), .sw(sw), .led(l0), .seg(s0), .an(a0),
                                                 .uart_rx(1'b1), .uart_tx(t0));
    top_fpga_ooo #(.REFRESH_W(2), .MEM_WAIT(0), .ROB_LIM(`CMP_ROB)) RF (.clk(clk), .reset(reset), .sw(sw), .led(l1), .seg(s1), .an(a1),
                                                    .uart_rx(1'b1), .uart_tx(t1), .load_btn(1'b0), .btn(4'd0));
    top_fpga_ooo #(.REFRESH_W(2), .ROB_LIM(`CMP_ROB)) RS (.clk(clk), .reset(reset), .sw(sw), .led(l2), .seg(s2), .an(a2),
                                      .uart_rx(1'b1), .uart_tx(t2), .load_btn(1'b0), .btn(4'd0));

    integer n_fail = 0, n_pass = 0, cyc = 0, i, k, p;
    always @(posedge clk) cyc <= cyc + 1;
    reg [8*24-1:0] phase = "start";
    reg [8*256-1:0] prog_name;

    task check(input ok, input [8*48-1:0] what, input [63:0] g, input [63:0] e);
        begin
            if (ok) n_pass = n_pass + 1;
            else begin
                n_fail = n_fail + 1;
                if (n_fail < 30) $display("TEST_FAIL top_fpga_cmp [%0s] %0s %0s: got %0h expected %0h (cycle %0d)",
                                          phase, prog_name, what, g, e, cyc);
            end
        end
    endtask

    // =========================================================================================
    // Tiny RV32IM assembler (functions return the 32-bit instruction word)
    // =========================================================================================
    function [31:0] enc_i(input [11:0] imm, input [4:0] rs1, input [2:0] f3, input [4:0] rd, input [6:0] opc);
        enc_i = {imm, rs1, f3, rd, opc};
    endfunction
    function [31:0] enc_r(input [6:0] f7, input [4:0] rs2, input [4:0] rs1, input [2:0] f3, input [4:0] rd);
        enc_r = {f7, rs2, rs1, f3, rd, 7'h33};
    endfunction
    function [31:0] enc_s(input [11:0] imm, input [4:0] rs2, input [4:0] rs1, input [2:0] f3);
        enc_s = {imm[11:5], rs2, rs1, f3, imm[4:0], 7'h23};
    endfunction
    function [31:0] enc_b(input [12:0] imm, input [4:0] rs2, input [4:0] rs1, input [2:0] f3);
        enc_b = {imm[12], imm[10:5], rs2, rs1, f3, imm[4:1], imm[11], 7'h63};
    endfunction
    function [31:0] enc_j(input [20:0] imm, input [4:0] rd);
        enc_j = {imm[20], imm[10:1], imm[11], imm[19:12], rd, 7'h6F};
    endfunction

    function [31:0] ADDI (input integer rd, input integer rs, input integer imm); ADDI  = enc_i(imm[11:0], rs[4:0], 3'd0, rd[4:0], 7'h13); endfunction
    function [31:0] ANDI (input integer rd, input integer rs, input integer imm); ANDI  = enc_i(imm[11:0], rs[4:0], 3'd7, rd[4:0], 7'h13); endfunction
    function [31:0] SLLI (input integer rd, input integer rs, input integer sh);  SLLI  = enc_i({7'd0, sh[4:0]}, rs[4:0], 3'd1, rd[4:0], 7'h13); endfunction
    function [31:0] SRLI (input integer rd, input integer rs, input integer sh);  SRLI  = enc_i({7'd0, sh[4:0]}, rs[4:0], 3'd5, rd[4:0], 7'h13); endfunction
    function [31:0] LUI  (input integer rd, input integer imm20);                 LUI   = {imm20[19:0], rd[4:0], 7'h37}; endfunction
    function [31:0] ADD  (input integer rd, input integer a, input integer b);    ADD   = enc_r(7'h00, b[4:0], a[4:0], 3'd0, rd[4:0]); endfunction
    function [31:0] EOR  (input integer rd, input integer a, input integer b);    EOR   = enc_r(7'h00, b[4:0], a[4:0], 3'd4, rd[4:0]); endfunction
    function [31:0] MUL  (input integer rd, input integer a, input integer b);    MUL   = enc_r(7'h01, b[4:0], a[4:0], 3'd0, rd[4:0]); endfunction
    function [31:0] MULH (input integer rd, input integer a, input integer b);    MULH  = enc_r(7'h01, b[4:0], a[4:0], 3'd1, rd[4:0]); endfunction
    function [31:0] MULHU(input integer rd, input integer a, input integer b);    MULHU = enc_r(7'h01, b[4:0], a[4:0], 3'd3, rd[4:0]); endfunction
    function [31:0] DIV  (input integer rd, input integer a, input integer b);    DIV   = enc_r(7'h01, b[4:0], a[4:0], 3'd4, rd[4:0]); endfunction
    function [31:0] DIVU (input integer rd, input integer a, input integer b);    DIVU  = enc_r(7'h01, b[4:0], a[4:0], 3'd5, rd[4:0]); endfunction
    function [31:0] REM  (input integer rd, input integer a, input integer b);    REM   = enc_r(7'h01, b[4:0], a[4:0], 3'd6, rd[4:0]); endfunction
    function [31:0] REMU (input integer rd, input integer a, input integer b);    REMU  = enc_r(7'h01, b[4:0], a[4:0], 3'd7, rd[4:0]); endfunction
    function [31:0] LW   (input integer rd, input integer off, input integer rs); LW    = enc_i(off[11:0], rs[4:0], 3'd2, rd[4:0], 7'h03); endfunction
    function [31:0] LH   (input integer rd, input integer off, input integer rs); LH    = enc_i(off[11:0], rs[4:0], 3'd1, rd[4:0], 7'h03); endfunction
    function [31:0] LBU  (input integer rd, input integer off, input integer rs); LBU   = enc_i(off[11:0], rs[4:0], 3'd4, rd[4:0], 7'h03); endfunction
    function [31:0] SW   (input integer rs2, input integer off, input integer rs1); SW  = enc_s(off[11:0], rs2[4:0], rs1[4:0], 3'd2); endfunction
    function [31:0] SH   (input integer rs2, input integer off, input integer rs1); SH  = enc_s(off[11:0], rs2[4:0], rs1[4:0], 3'd1); endfunction
    function [31:0] SB   (input integer rs2, input integer off, input integer rs1); SB  = enc_s(off[11:0], rs2[4:0], rs1[4:0], 3'd0); endfunction
    function [31:0] BEQ  (input integer a, input integer b, input integer off);  BEQ   = enc_b(off[12:0], b[4:0], a[4:0], 3'd0); endfunction
    function [31:0] BNE  (input integer a, input integer b, input integer off);  BNE   = enc_b(off[12:0], b[4:0], a[4:0], 3'd1); endfunction
    function [31:0] JAL  (input integer rd, input integer off);                   JAL   = enc_j(off[20:0], rd[4:0]); endfunction

    // ---- program image being built -----------------------------------------------------------
    reg [31:0] prog [0:1023];
    integer pc;
    task em(input [31:0] w);
        begin prog[pc] = w; pc = pc + 1; end
    endtask

    task build(input integer id);
        integer top, outer, inner;
        begin
            pc = 0;
            for (k = 0; k < 1024; k = k + 1) prog[k] = 32'd0;
            case (id)
            0: begin    // sum loop with some independent ALU work (branch predictor, ILP)
                prog_name = "gen_sum_loop";
                em(ADDI(1,0,0));  em(ADDI(2,0,1));  em(ADDI(3,0,51)); em(ADDI(6,0,0));
                top = pc;
                em(ADD(1,1,2));   em(EOR(4,1,2));   em(SLLI(5,4,3));  em(ADD(6,6,5));
                em(ADDI(2,2,1));  em(BNE(2,3,(top-pc)*4));
                em(ADD(7,1,6));
            end
            1: begin    // memory: word stores/loads, then byte/half stores into one word
                prog_name = "gen_mem";
                em(ADDI(10,0,512)); em(ADDI(1,0,0)); em(ADDI(2,0,16));
                top = pc;
                em(MUL(3,1,1));   em(SLLI(4,1,2));  em(ADD(4,4,10));  em(SW(3,0,4));
                em(ADDI(1,1,1));  em(BNE(1,2,(top-pc)*4));
                em(ADDI(1,0,0));  em(ADDI(5,0,0));
                top = pc;
                em(SLLI(4,1,2));  em(ADD(4,4,10));  em(LW(3,0,4));    em(ADD(5,5,3));
                em(ADDI(1,1,1));  em(BNE(1,2,(top-pc)*4));
                em(SW(0,64,10));  em(SB(5,65,10));  em(SH(5,66,10));  // byte strobes
                em(LW(6,64,10));  em(LBU(7,65,10)); em(LH(8,66,10));
                em(ADD(5,5,6));   em(ADD(5,5,7));   em(ADD(5,5,8));
            end
            2: begin    // RV32M: all ops, divide by zero, overflow, then a mul/div chain
                prog_name = "gen_muldiv";
                em(ADDI(1,0,1234)); em(ADDI(2,0,-77));
                em(MUL(3,1,2));   em(MULH(4,1,2));  em(MULHU(5,1,2));
                em(DIV(6,1,2));   em(REM(7,1,2));   em(DIVU(8,1,2));  em(REMU(9,1,2));
                em(DIV(11,1,0));  em(REM(12,1,0));  em(DIVU(13,1,0)); em(REMU(14,1,0));
                em(LUI(15,32'h80000)); em(ADDI(16,0,-1));
                em(DIV(17,15,16));em(REM(18,15,16));
                em(ADDI(20,0,0)); em(ADDI(21,0,1)); em(ADDI(22,0,20));
                top = pc;
                em(MUL(23,21,21));em(ADD(20,20,23));em(DIV(24,20,21));em(ADD(20,20,24));
                em(ADDI(21,21,1));em(BNE(21,22,(top-pc)*4));
                em(EOR(25,3,4));  em(EOR(25,25,6)); em(EOR(25,25,20));
            end
            3: begin    // branchy: Collatz step counts for n = 1..12 (data-dependent branches)
                prog_name = "gen_branchy";
                em(ADDI(1,0,1));  em(ADDI(2,0,13)); em(ADDI(9,0,0));  em(ADDI(6,0,1));
                outer = pc;
                em(ADD(3,1,0));
                inner = pc;
                em(ANDI(4,3,1));
                em(BEQ(4,0,20));                    // even -> inner+6
                em(SLLI(5,3,1));  em(ADD(3,5,3));   em(ADDI(3,3,1));
                em(JAL(0,8));                       // -> inner+7
                em(SRLI(3,3,1));                    // inner+6
                em(ADDI(9,9,1));                    // inner+7
                em(BNE(3,6,(inner-pc)*4));
                em(ADDI(1,1,1));  em(BNE(1,2,(outer-pc)*4));
                em(ADDI(10,0,768)); em(SW(9,0,10)); em(LW(11,0,10));
            end
            default: begin  // pointer chase through a table (cache hits/misses, load-use)
                prog_name = "gen_chase";
                em(ADDI(10,0,1024)); em(ADDI(1,0,0)); em(ADDI(2,0,64));
                top = pc;
                em(SLLI(5,1,2));  em(ADD(5,5,1));   em(ADDI(5,5,3));  em(ANDI(5,5,63));
                em(SLLI(4,1,2));  em(ADD(4,4,10));  em(SW(5,0,4));
                em(ADDI(1,1,1));  em(BNE(1,2,(top-pc)*4));
                em(ADDI(3,0,0));  em(ADDI(6,0,0));  em(ADDI(7,0,100)); em(ADDI(8,0,0));
                top = pc;
                em(SLLI(4,3,2));  em(ADD(4,4,10));  em(LW(3,0,4));    em(ADD(8,8,3));
                em(ADDI(6,6,1));  em(BNE(6,7,(top-pc)*4));
            end
            endcase
            em(`CMP_END_INSN);
        end
    endtask

    task preload;
        reg [31:0] w;
        begin
            for (k = 0; k < 1024; k = k + 1) begin
                w = prog[k];
                DUT.U_BASE.U_IMEM.imem[k] = w; DUT.U_FAST.U_IMEM.imem[k] = w;
                DUT.U_SLOW.U_IMEM.imem[k] = w; DUT.U_BSLOW.U_IMEM.imem[k] = w;
                RB.U_IMEM.imem[k] = w; RF.U_IMEM.imem[k] = w; RS.U_IMEM.imem[k] = w;
            end
        end
    endtask

    // ---- A: every-cycle comparison with the single-core tops -------------------------------
    reg cmp_on = 0;
    always @(negedge clk) if (cmp_on) begin
        if (DUT.U_BASE.result    !== RB.result)         check(0, "base result",    DUT.U_BASE.result, RB.result);
        if (DUT.U_BASE.done      !== RB.done)           check(0, "base done",      DUT.U_BASE.done, RB.done);
        if (DUT.U_BASE.exception !== RB.exception)      check(0, "base exception", DUT.U_BASE.exception, RB.exception);
        if (DUT.U_BASE.cycles    !== RB.U_PERF.cycles)  check(0, "base cycles",    DUT.U_BASE.cycles, RB.U_PERF.cycles);
        if (DUT.U_BASE.retired   !== RB.U_PERF.retired) check(0, "base retired",   DUT.U_BASE.retired, RB.U_PERF.retired);
        if (DUT.U_BASE.ooo_count !== 32'd0)             check(0, "base ooo_count", DUT.U_BASE.ooo_count, 0);
        if (DUT.U_BASE.dc_access !== 32'd0 || DUT.U_BASE.br_count !== 32'd0)
                                                        check(0, "base cache/branch counters", 1, 0);
    end
    `define CMP_OOO(S, R, NM) \
    always @(negedge clk) if (cmp_on) begin \
        if (DUT.S.result     !== R.result)                     check(0, {NM, " result"},     DUT.S.result, R.result); \
        if (DUT.S.done       !== R.done)                       check(0, {NM, " done"},       DUT.S.done, R.done); \
        if (DUT.S.exception  !== R.exception)                  check(0, {NM, " exception"},  DUT.S.exception, R.exception); \
        if (DUT.S.cycles     !== R.U_PERF.cycles)              check(0, {NM, " cycles"},     DUT.S.cycles, R.U_PERF.cycles); \
        if (DUT.S.retired    !== R.U_PERF.retired)             check(0, {NM, " retired"},    DUT.S.retired, R.U_PERF.retired); \
        if (DUT.S.ooo_count  !== R.U_PERF.ooo_count)           check(0, {NM, " ooo_count"},  DUT.S.ooo_count, R.U_PERF.ooo_count); \
        if (DUT.S.dc_access  !== R.U_PERF.dcache_access_count) check(0, {NM, " dc_access"},  DUT.S.dc_access, R.U_PERF.dcache_access_count); \
        if (DUT.S.dc_hit     !== R.U_PERF.dcache_hit_count)    check(0, {NM, " dc_hit"},     DUT.S.dc_hit, R.U_PERF.dcache_hit_count); \
        if (DUT.S.dc_miss    !== R.U_PERF.dcache_miss_count)   check(0, {NM, " dc_miss"},    DUT.S.dc_miss, R.U_PERF.dcache_miss_count); \
        if (DUT.S.dc_stall   !== R.U_PERF.dcache_stall_cycles) check(0, {NM, " dc_stall"},   DUT.S.dc_stall, R.U_PERF.dcache_stall_cycles); \
        if (DUT.S.br_count   !== R.U_PERF.branch_count)        check(0, {NM, " br_count"},   DUT.S.br_count, R.U_PERF.branch_count); \
        if (DUT.S.br_mispred !== R.U_PERF.mispredict_count)    check(0, {NM, " br_mispred"}, DUT.S.br_mispred, R.U_PERF.mispredict_count); \
    end
    `CMP_OOO(U_FAST, RF, "fast")
    `CMP_OOO(U_SLOW, RS, "slow")
    `undef CMP_OOO

    // core 3: request sequence vs core 0, gated-cycle count, and every cycle at MEM_WAIT = 0
    reg [68:0] seq0 [0:SEQN-1];
    integer n0 = 0, n3 = 0, frz = 0;
    reg [68:0] it;
    always @(negedge clk) if (cmp_on) begin
        if (DUT.U_BASE.dmem_re && DUT.U_BASE.done !== 1'b1) begin
            if (n0 < SEQN) seq0[n0] = {1'b0, DUT.U_BASE.dmem_raddr, 36'd0};
            n0 = n0 + 1;
        end
        if (DUT.U_BASE.dmem_we && DUT.U_BASE.done !== 1'b1) begin
            if (n0 < SEQN) seq0[n0] = {1'b1, DUT.U_BASE.dmem_waddr, DUT.U_BASE.dmem_wdata, DUT.U_BASE.dmem_wstrb};
            n0 = n0 + 1;
        end
        if (DUT.U_BSLOW.done === 1'b1) ;
        else if (DUT.U_BSLOW.en === 1'b1) begin
            if (DUT.U_BSLOW.dmem_re) begin
                it = {1'b0, DUT.U_BSLOW.dmem_raddr, 36'd0};
                if (n3 >= n0 || (n3 < SEQN && it !== seq0[n3])) check(0, "bslow request vs pipe_m", it, n3 < SEQN ? seq0[n3] : 0);
                n3 = n3 + 1;
            end
            if (DUT.U_BSLOW.dmem_we) begin
                it = {1'b1, DUT.U_BSLOW.dmem_waddr, DUT.U_BSLOW.dmem_wdata, DUT.U_BSLOW.dmem_wstrb};
                if (n3 >= n0 || (n3 < SEQN && it !== seq0[n3])) check(0, "bslow request vs pipe_m", it, n3 < SEQN ? seq0[n3] : 0);
                n3 = n3 + 1;
            end
        end else if (DUT.core_rst_n === 1'b1)
            frz = frz + 1;
        if (`MEM_WAIT == 0) begin
            if (DUT.U_BSLOW.result !== RB.result || DUT.U_BSLOW.done !== RB.done ||
                DUT.U_BSLOW.cycles !== RB.U_PERF.cycles || DUT.U_BSLOW.retired !== RB.U_PERF.retired ||
                DUT.U_BSLOW.exception !== RB.exception)
                check(0, "bslow vs top_fpga_base at MEM_WAIT 0", DUT.U_BSLOW.cycles, RB.U_PERF.cycles);
        end
    end
    task bslow_end;
        begin
            check(DUT.U_BSLOW.cycles === DUT.U_BASE.cycles + frz, "bslow cycles = pipe_m cycles + gated cycles",
                  DUT.U_BSLOW.cycles, DUT.U_BASE.cycles + frz);
            check(DUT.U_BSLOW.retired === DUT.U_BASE.retired, "bslow retired = pipe_m retired",
                  DUT.U_BSLOW.retired, DUT.U_BASE.retired);
            check(n3 == n0, "bslow request count = pipe_m", n3, n0);
            if (`MEM_WAIT == 0) check(frz == 0, "no gated cycles at MEM_WAIT 0", frz, 0);
            n0 = 0; n3 = 0; frz = 0;
        end
    endtask

    // sw[8:7] keeps moving during runs; the cores must ignore it until the next reset
    reg flip_on = 0;
    always @(negedge clk) if (flip_on && (cyc % 37) == 0) sw[8:7] = sw[8:7] + 2'd1;

    wire all_done = DUT.U_BASE.done & DUT.U_FAST.done & DUT.U_SLOW.done & DUT.U_BSLOW.done;
    task wait_all_done;
        integer w;
        begin
            w = 0;
            while (!all_done && w < TIMEOUT) begin @(negedge clk); w = w + 1; end
            repeat (5) @(negedge clk);
            check(all_done === 1'b1, "all four cores done", {DUT.U_BASE.done, DUT.U_FAST.done, DUT.U_SLOW.done, DUT.U_BSLOW.done}, 4'b1111);
        end
    endtask

    // ---- B: expected display ---------------------------------------------------------------------
    function [6:0] font(input [4:0] c);
        case (c)
            5'h00: font = 7'h3F;  5'h01: font = 7'h06;  5'h02: font = 7'h5B;  5'h03: font = 7'h4F;
            5'h04: font = 7'h66;  5'h05: font = 7'h6D;  5'h06: font = 7'h7D;  5'h07: font = 7'h07;
            5'h08: font = 7'h7F;  5'h09: font = 7'h6F;  5'h0A: font = 7'h77;  5'h0B: font = 7'h7C;
            5'h0C: font = 7'h39;  5'h0D: font = 7'h5E;  5'h0E: font = 7'h79;  5'h0F: font = 7'h71;
            5'd16: font = 7'h40;  default: font = 7'h00;
        endcase
    endfunction

    function [47:0] exp_disp(input [1:0] mode, input [31:0] a, input [31:0] b);
        reg [63:0] v, lim, t;
        reg neg, bad;
        reg [39:0] d;
        reg [7:0] pt;
        integer j, msd;
        begin
            d = {8{5'd17}}; pt = 8'd0; neg = 0; bad = 0; v = 0;
            if (mode == 2'd0) begin
                for (j = 0; j < 8; j = j + 1) d[5*j +: 5] = {1'b0, a[4*j +: 4]};
            end else begin
                if (mode == 2'd3) begin
                    if (b == 0) bad = 1; else v = ({32'd0, a} * 64'd1000) / {32'd0, b};
                    pt = 8'b0000_1000;
                end else if (mode == 2'd2 && a[31]) begin
                    neg = 1; v = {32'd0, -a};
                end else v = {32'd0, a};
                lim = neg ? 64'd10_000_000 : 64'd100_000_000;
                if (bad || v >= lim) begin
                    d = {8{5'd16}}; pt = 8'd0;
                end else begin
                    msd = (mode == 2'd3) ? 3 : 0;
                    t = v;
                    for (j = 0; j < 8; j = j + 1) begin
                        if (t % 10 != 0 && j > msd) msd = j;
                        t = t / 10;
                    end
                    t = v;
                    for (j = 0; j < 8; j = j + 1) begin
                        if (j <= msd) d[5*j +: 5] = t % 10;
                        t = t / 10;
                    end
                    if (neg) d[5*(msd+1) +: 5] = 5'd16;
                end
            end
            exp_disp = {pt, d};
        end
    endfunction

    function [31:0] cval(input integer core, input integer f);
        begin
            case (core)
                0: case (f) 0: cval = DUT.U_BASE.result; 1: cval = DUT.U_BASE.cycles; 2: cval = DUT.U_BASE.retired;
                            3: cval = DUT.U_BASE.ooo_count; 4: cval = DUT.U_BASE.dc_access; 5: cval = DUT.U_BASE.dc_hit;
                            6: cval = DUT.U_BASE.dc_miss; 7: cval = DUT.U_BASE.dc_stall; 8: cval = DUT.U_BASE.br_count;
                            default: cval = DUT.U_BASE.br_mispred; endcase
                1: case (f) 0: cval = DUT.U_FAST.result; 1: cval = DUT.U_FAST.cycles; 2: cval = DUT.U_FAST.retired;
                            3: cval = DUT.U_FAST.ooo_count; 4: cval = DUT.U_FAST.dc_access; 5: cval = DUT.U_FAST.dc_hit;
                            6: cval = DUT.U_FAST.dc_miss; 7: cval = DUT.U_FAST.dc_stall; 8: cval = DUT.U_FAST.br_count;
                            default: cval = DUT.U_FAST.br_mispred; endcase
                2: case (f) 0: cval = DUT.U_SLOW.result; 1: cval = DUT.U_SLOW.cycles; 2: cval = DUT.U_SLOW.retired;
                            3: cval = DUT.U_SLOW.ooo_count; 4: cval = DUT.U_SLOW.dc_access; 5: cval = DUT.U_SLOW.dc_hit;
                            6: cval = DUT.U_SLOW.dc_miss; 7: cval = DUT.U_SLOW.dc_stall; 8: cval = DUT.U_SLOW.br_count;
                            default: cval = DUT.U_SLOW.br_mispred; endcase
                default: case (f) 0: cval = DUT.U_BSLOW.result; 1: cval = DUT.U_BSLOW.cycles; 2: cval = DUT.U_BSLOW.retired;
                            3: cval = DUT.U_BSLOW.ooo_count; 4: cval = DUT.U_BSLOW.dc_access; 5: cval = DUT.U_BSLOW.dc_hit;
                            6: cval = DUT.U_BSLOW.dc_miss; 7: cval = DUT.U_BSLOW.dc_stall; 8: cval = DUT.U_BSLOW.br_count;
                            default: cval = DUT.U_BSLOW.br_mispred; endcase
            endcase
        end
    endfunction

    reg [1:0] e_mode; reg [31:0] e_a, e_b;
    task exp_sel(input [1:0] page, input [3:0] item, input dec);
        begin
            e_mode = dec ? 2'd1 : 2'd0; e_a = 0; e_b = 0;
            if (item <= 9) begin
                e_a = cval(page, item);
                if (item == 0) e_mode = dec ? 2'd2 : 2'd0;
            end
            else if (item == 10) begin e_mode = 3; e_a = cval(page, 1); e_b = cval(page, 2); end
            else if (item == 11) begin e_mode = 3; e_a = cval(page, 5); e_b = cval(page, 4); end
            else if (item == 12) begin e_mode = 3; e_a = cval(page, 9); e_b = cval(page, 8); end
            else if (item == 13) begin e_mode = 3; e_a = cval(3, 1);    e_b = cval(2, 1);    end
            else if (item == 14) begin e_mode = 3; e_a = cval(0, 1);    e_b = cval(1, 1);    end
            else begin e_mode = 1; e_a = `CMP_ROB; end
        end
    endtask

    task check_pins(input [47:0] e);
        integer q, dg;
        reg [7:0] eseg;
        begin
            for (q = 0; q < 64; q = q + 1) begin
                @(negedge clk);
                dg = -1;
                for (k = 0; k < 8; k = k + 1) if (an === ~(8'd1 << k)) dg = k;
                if (dg < 0) check(0, "an not one-hot low", an, 0);
                else begin
                    eseg = ~{e[40 + dg], font(e[5*dg +: 5])};
                    if (seg !== eseg) check(0, "seg pins (digit, seg)", {dg[7:0], seg}, {dg[7:0], eseg});
                end
            end
        end
    endtask

    task sweep_display;
        integer s;
        reg [47:0] e;
        reg [1:0] ci;
        reg [31:0] rci;
        begin
            for (s = 0; s < 128; s = s + 1) begin
                sw = {s[6:0], $random} & 16'hFFFF;
                sw[15:9] = s[6:0];
                repeat (200) @(negedge clk);
                exp_sel(sw[15:14], sw[13:10], sw[9]);
                e = exp_disp(e_mode, e_a, e_b);
                check({DUT.U_DISP.dp, DUT.U_DISP.dig} === e, "display digits", {DUT.U_DISP.dp, DUT.U_DISP.dig}, e);
                check_pins(e);
                ci  = sw[15:14];
                rci = cval(ci, 0);
                check(led === {1'b1, DUT.U_BASE.exception | DUT.U_FAST.exception | DUT.U_SLOW.exception | DUT.U_BSLOW.exception,
                               3'b111, (cval(0,0) == cval(1,0)) && (cval(1,0) == cval(2,0)) && (cval(2,0) == cval(3,0)),
                               1'b0, 1'b1, rci[7:0]},
                      "leds", led, 0);
            end
            sw = 16'd0;
        end
    endtask

    // ---- B: cmp_display alone ------------------------------------------------------------------
    reg [1:0] u_mode = 0; reg [31:0] u_a = 0, u_b = 0; reg u_rst = 0;
    wire [7:0] u_seg, u_an; wire [39:0] u_dig; wire [7:0] u_dp;
    cmp_display #(.REFRESH_W(2)) U_DUNIT (.clk(clk), .reset_n(u_rst), .mode(u_mode), .a(u_a), .b(u_b),
                                          .seg(u_seg), .an(u_an), .dig(u_dig), .dp(u_dp));
    task unit_one(input [1:0] md, input [31:0] va, input [31:0] vb);
        reg [47:0] e;
        begin
            u_mode = md; u_a = va; u_b = vb;
            repeat (160) @(negedge clk);
            e = exp_disp(md, va, vb);
            check({u_dp, u_dig} === e, "cmp_display unit", {md, va, vb}, e);
            if ({u_dp, u_dig} !== e) $display("   mode %0d a %0d (%h) b %0d: got %h expected %h", md, va, va, vb, {u_dp, u_dig}, e);
        end
    endtask
    reg [31:0] edges [0:15];
    task unit_tests;
        integer q, x, y;
        begin
            edges[0] = 0; edges[1] = 1; edges[2] = 9; edges[3] = 10; edges[4] = 999; edges[5] = 1000;
            edges[6] = 9_999_999; edges[7] = 10_000_000; edges[8] = 99_999_999; edges[9] = 100_000_000;
            edges[10] = 32'hFFFF_FFFF; edges[11] = 32'h8000_0000; edges[12] = 32'h7FFF_FFFF;
            edges[13] = -32'd9_999_999; edges[14] = -32'd10_000_000; edges[15] = 99_999;
            u_rst = 1;
            for (q = 0; q < 4; q = q + 1) for (x = 0; x < 16; x = x + 1) for (y = 0; y < 16; y = y + 1)
                if (q == 3 || y == 0) unit_one(q, edges[x], edges[y]);
            for (q = 0; q < 3000; q = q + 1) begin
                x = $random; y = $random;
                case (q % 5)
                    0: unit_one(q % 4, x, y);
                    1: unit_one(q % 4, x % 100_000, y % 1000);
                    2: unit_one(3, (x & 32'hFFFF), (y & 32'hFFFF) | 1);
                    3: unit_one(2, x % 20_000_000, 0);
                    default: unit_one(1, x & 32'h07FF_FFFF, 0);
                endcase
            end
        end
    endtask

    // ---- main ----------------------------------------------------------------------------------
    initial begin
        #1;
        for (p = 0; p < NPROG; p = p + 1) begin
            phase = "A same as single tops";
            build(p);                           // sets prog_name and the image
            preload;
            sw = 16'd0;
            sw[8:7] = ROB_CODE;                 // the size under test, read while in reset
            reset = 0; repeat (5) @(negedge clk);
            cmp_on = 1;
            reset = 1;
            repeat (6) @(negedge clk);          // cores out of reset: the switch is ignored from now on
            check(DUT.rob_act == `CMP_ROB, "active ROB size", DUT.rob_act, `CMP_ROB);
            flip_on = 1;
            wait_all_done;
            flip_on = 0;
            check(DUT.rob_act == `CMP_ROB, "active ROB size after flipping sw[8:7]", DUT.rob_act, `CMP_ROB);
            check(DUT.U_BASE.result === DUT.U_FAST.result && DUT.U_FAST.result === DUT.U_SLOW.result &&
                  DUT.U_SLOW.result === DUT.U_BSLOW.result,
                  "four results agree", DUT.U_BASE.result, DUT.U_BSLOW.result);
            bslow_end;
            check(RB.done === 1'b1 && RF.done === 1'b1 && RS.done === 1'b1, "reference tops done", 0, 1);
            $display("CMP rob=%0d %0s result=%h cycles pipe_m=%0d ooo_fast=%0d ooo_slow=%0d pipe_m_slow=%0d retired=%0d speedup_fast=%0.3f speedup_slow=%0.3f",
                     `CMP_ROB, prog_name, DUT.U_BASE.result, DUT.U_BASE.cycles, DUT.U_FAST.cycles, DUT.U_SLOW.cycles,
                     DUT.U_BSLOW.cycles, DUT.U_BASE.retired,
                     $itor(DUT.U_BASE.cycles) / $itor(DUT.U_FAST.cycles),
                     $itor(DUT.U_BSLOW.cycles) / $itor(DUT.U_SLOW.cycles));
`ifndef CMP_QUICK
            if (p == 1 || p == 2 || p == 4) begin
                phase = "B display and LEDs";
                sweep_display;
            end
`endif
            cmp_on = 0;
        end
`ifndef CMP_QUICK
        prog_name = "cmp_display";
        phase = "B display unit";
        unit_tests;
`endif
        if (n_fail == 0) $display("TEST_PASS top_fpga_cmp %0d", n_pass);
        else             $display("TEST_FAIL top_fpga_cmp %0d failures, %0d checks passed", n_fail, n_pass);
        $finish;
    end
endmodule
