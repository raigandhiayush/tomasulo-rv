`timescale 1ns/1ps
`include "ooo_defs.vh"
// tb_lsu.v - Self-checking testbench for lsu verifying load/store ordering and memory access.
module tb_lsu;

    localparam W = `ROB_W;

    reg clk = 0, reset_n = 0;
    always #5 clk = ~clk;

    // allocate port
    reg               al_valid, al_store, al_qjv, al_qkv;
    reg  [2:0]        al_f3;
    reg  [W-1:0]      al_tag, al_qj, al_qk;
    reg  [31:0]       al_vj, al_vk, al_imm;
    wire              lq_full;
    // buses 0..NCDB-2 from the tb; bus CDB_LSU is the DUT's own output, fed
    // back exactly as ooo_core will do it
    reg  [`NCDB-1:0]       tv;
    reg  [`NCDB*W-1:0]     tt;
    reg  [`NCDB*32-1:0]    tval;
    wire              lsu_v;
    wire [W-1:0]      lsu_t;
    wire [31:0]       lsu_val;
    reg  [`NCDB-1:0]       cdb_valid;
    reg  [`NCDB*W-1:0]     cdb_tag;
    reg  [`NCDB*32-1:0]    cdb_value;
    always @(*) begin
        cdb_valid = tv; cdb_tag = tt; cdb_value = tval;
        cdb_valid[`CDB_LSU]              = lsu_v;
        cdb_tag[`CDB_LSU*W +: W]         = lsu_t;
        cdb_value[`CDB_LSU*32 +: 32]     = lsu_val;
    end
    // commit port
    reg               cm_valid, cm_is_store;
    reg  [W-1:0]      cm_tag;
    // memory
    wire              re, we;
    wire [31:0]       raddr, waddr, wdata;
    wire [3:0]        wstrb;
`ifdef REAL_DMEM
    wire [31:0]       rdata;            // driven by the real data_mem
`else
    reg  [31:0]       rdata;
`endif

    lsu dut (
        .clk(clk), .reset_n(reset_n),
        .lq_al_valid(al_valid), .lq_al_store(al_store), .lq_al_funct3(al_f3), .lq_al_tag(al_tag),
        .lq_al_qj_valid(al_qjv), .lq_al_qj(al_qj), .lq_al_vj(al_vj),
        .lq_al_qk_valid(al_qkv), .lq_al_qk(al_qk), .lq_al_vk(al_vk), .lq_al_imm(al_imm),
        .lq_full(lq_full),
        .cdb_valid(cdb_valid), .cdb_tag(cdb_tag), .cdb_value(cdb_value),
        .cdb_lsu_valid(lsu_v), .cdb_lsu_tag(lsu_t), .cdb_lsu_value(lsu_val),
        .cm_valid(cm_valid), .cm_tag(cm_tag), .cm_is_store(cm_is_store),
        .dmem_re(re), .dmem_raddr(raddr), .dmem_rdata(rdata),
        .dmem_stall(1'b0), .dmem_rvalid(1'b1),          // no cache: original LSU timing
        .dmem_we(we), .dmem_waddr(waddr), .dmem_wdata(wdata), .dmem_wstrb(wstrb)
    );

`ifdef REAL_DMEM
    // ---- the real baseline data_mem (modules/memory.v) -----------------------
    data_mem u_dmem (.clk(clk), .re(re), .raddr(raddr), .rdata(rdata),
                     .we(we), .waddr(waddr), .wdata(wdata), .wstrb(wstrb));
    `define MEM u_dmem.dmem
`else
    // ---- data_mem model (SIGNALS_REFERENCE 1.3) ----------------------------
    reg [31:0] mem [0:1023];
    `define MEM mem
    reg [31:0] fwd;
    integer bl;
    always @(posedge clk) begin
        if (re) begin
            fwd = `MEM[raddr[11:2]];
            if (we && waddr[11:2] == raddr[11:2])
                for (bl = 0; bl < 4; bl = bl + 1) if (wstrb[bl]) fwd[8*bl +: 8] = wdata[8*bl +: 8];
            rdata <= fwd;
        end
        if (we)
            for (bl = 0; bl < 4; bl = bl + 1) if (wstrb[bl]) `MEM[waddr[11:2]][8*bl +: 8] <= wdata[8*bl +: 8];
    end

`endif

    integer n_pass = 0, n_fail = 0;
    integer i, j, c, off;

    task ok;
        input [8*52:1] name;
        input          cond;
        begin
            if (cond) n_pass = n_pass + 1;
            else begin
                n_fail = n_fail + 1;
                $display("TEST_FAIL lsu [%0s] at t=%0t", name, $time);
            end
        end
    endtask

    task step;
        begin
            @(posedge clk); #1;
            al_valid = 0; tv = 0; cm_valid = 0;
        end
    endtask

    task do_reset;
        begin
            al_valid = 0; tv = 0; cm_valid = 0;
            reset_n = 0; #2 reset_n = 1;
        end
    endtask

    // allocate: base/data either ready (q*v = 0, value) or waiting on a tag
    task alloc;
        input        st;
        input [2:0]  f;
        input [W-1:0] t;
        input        qjv;
        input [W-1:0] qj;
        input [31:0] vj;
        input        qkv;
        input [W-1:0] qk;
        input [31:0] vk;
        input [31:0] im;
        begin
            al_valid = 1; al_store = st; al_f3 = f; al_tag = t;
            al_qjv = qjv; al_qj = qj; al_vj = vj;
            al_qkv = qkv; al_qk = qk; al_vk = vk; al_imm = im;
        end
    endtask

    task ld;  input [2:0] f; input [W-1:0] t; input [31:0] addr;
        begin alloc(0, f, t, 0, 0, addr, 0, 0, 0, 0); end endtask
    task sto; input [2:0] f; input [W-1:0] t; input [31:0] addr; input [31:0] d;
        begin alloc(1, f, t, 0, 0, addr, 0, 0, d, 0); end endtask

    task bus;
        input integer k; input [W-1:0] t; input [31:0] v;
        begin tv[k] = 1; tt[k*W +: W] = t; tval[k*32 +: 32] = v; end
    endtask

    task commit;
        input st; input [W-1:0] t;
        begin cm_valid = 1; cm_is_store = st; cm_tag = t; end
    endtask

    // reference formatting (written independently of the DUT: via shifts of
    // a signed value rather than byte selects)
    function [31:0] fmt;
        input [2:0] f; input [31:0] word; input [1:0] o;
        reg signed [31:0] s;
        begin
            case (f)
                `F3_LB:  begin s = word << (8*(3-o)); fmt = s >>> 24; end
                `F3_LBU: fmt = (word >> (8*o)) & 32'hFF;
                `F3_LH:  begin s = word << (8*(2-o)); fmt = s >>> 16; end
                `F3_LHU: fmt = (word >> (8*o)) & 32'hFFFF;
                default: fmt = word;
            endcase
        end
    endfunction

    // ---- random-test bookkeeping (T13) -------------------------------------
    localparam NOPS = 4096;
    reg          o_st   [0:NOPS-1];
    reg  [2:0]   o_f3   [0:NOPS-1];
    reg  [W-1:0] o_tag  [0:NOPS-1];
    reg  [31:0]  o_addr [0:NOPS-1];
    reg  [31:0]  o_data [0:NOPS-1];   // store data (known once resolved)
    reg          o_dsrc_ld [0:NOPS-1];// store data comes from a load result
    integer      o_dld  [0:NOPS-1];   // ... that load's op index
    reg          o_done [0:NOPS-1];   // load returned / store did SR
    reg  [31:0]  o_res  [0:NOPS-1];   // load result
    integer      o_la   [0:NOPS-1];   // cycle of LA
    integer      o_dcyc [0:NOPS-1];   // cycle of its broadcast (ROB ready from the next cycle)
    reg  [31:0]  rmem   [0:1023];
    reg          tag_busy [0:`ROB_N-1];
    integer      tag_op   [0:`ROB_N-1];      // tag -> op index (LSU ops)
    reg          p_pend [0:`ROB_N-1];        // producer tags waiting to broadcast
    reg  [31:0]  p_val  [0:`ROB_N-1];
    integer n_ops, n_cm, seed, cyc, k, p, a, nf, la_cnt, d13_cnt, sr_cnt, fails_shown;
    integer last_la_op, oldest_st;
    reg     free_now [0:`ROB_N-1];
    reg     found, used_bus;
    reg [W-1:0] tq, tp;
    reg [31:0] base, expv, word;
    reg [3:0]  es;

    function [31:0] merge;              // apply a store to a word
        input [31:0] w; input [2:0] f; input [1:0] o; input [31:0] d;
        begin
            merge = w;
            case (f)
                `F3_SB: merge[8*o +: 8] = d[7:0];
                `F3_SH: merge[16*o[1] +: 16] = d[15:0];
                default: merge = d;
            endcase
        end
    endfunction

    initial begin
        al_valid = 0; al_store = 0; al_f3 = 0; al_tag = 0; al_qjv = 0; al_qj = 0; al_vj = 0;
        al_qkv = 0; al_qk = 0; al_vk = 0; al_imm = 0;
        tv = 0; tt = 0; tval = 0; cm_valid = 0; cm_is_store = 0; cm_tag = 0;
`ifndef REAL_DMEM
        rdata = 0;
`endif
        for (i = 0; i < 1024; i = i + 1) `MEM[i] = 32'h0;
        `MEM[4] = 32'h80FF_7F01;          // bytes 01 7F FF 80 at 0x10..0x13
        `MEM[5] = 32'h1234_ABCD;
        repeat (2) @(posedge clk); #1 reset_n = 1;

        // ---------------- T1 ----------------
        do_reset;
        ok("T1 not full after reset",       lq_full === 0);
        ok("T1 no bus, no memory access",   lsu_v === 0 && re === 0 && we === 0);

        // ---------------- T2: LW timing ----------------
        ld(`F3_LW, 3, 32'h14);                     // cycle c
        ok("T2 nothing in the allocation cycle", re === 0 && lsu_v === 0);
        step;                                      // c+1 = LA
        ok("T2 LA one cycle after allocation", re === 1 && raddr === 32'h14 && lsu_v === 0);
        step;                                      // c+2 = LW
        ok("T2 LW: result on cdb_lsu", lsu_v === 1 && lsu_t === 3 && lsu_val === 32'h1234_ABCD && re === 0);
        step;
        ok("T2 bus free afterwards", lsu_v === 0);

        // ---------------- T3: load formats ----------------
        for (off = 0; off < 4; off = off + 1) begin
            for (j = 0; j < 5; j = j + 1) begin
                case (j) 0: i = `F3_LB; 1: i = `F3_LBU; 2: i = `F3_LH; 3: i = `F3_LHU; default: i = `F3_LW; endcase
                if ((i == `F3_LW && off != 0) || ((i == `F3_LH || i == `F3_LHU) && off[0])) ;
                else begin
                    ld(i, 5, 32'h10 + off); step; step;
                    ok("T3 load format and alignment",
                       lsu_v === 1 && lsu_val === fmt(i, 32'h80FF_7F01, off));
                    if (lsu_val !== fmt(i, 32'h80FF_7F01, off))
                        $display("    f3=%0d off=%0d got %h exp %h", i, off, lsu_val, fmt(i, 32'h80FF_7F01, off));
                end
            end
        end
        ok("T3 LB 0x80 sign-extends", fmt(`F3_LB, 32'h80FF_7F01, 3) === 32'hFFFF_FF80);
        step;

        // ---------------- T4: stores ----------------
        for (off = 0; off < 4; off = off + 1) begin
            for (j = 0; j < 3; j = j + 1) begin
                i = (j == 0) ? `F3_SB : (j == 1) ? `F3_SH : `F3_SW;
                if ((i == `F3_SW && off != 0) || (i == `F3_SH && off[0])) ;
                else begin
                    `MEM[8] = 32'hAAAA_AAAA;
                    sto(i, 6, 32'h20 + off, 32'h1122_3344);
                    step;                                  // SR
                    ok("T4 SR: dummy completion on cdb_lsu", lsu_v === 1 && lsu_t === 6 && lsu_val === 0 && we === 0);
                    step; step;
                    ok("T4 no write and no rebroadcast before commit", we === 0 && lsu_v === 0 && `MEM[8] === 32'hAAAA_AAAA);
                    commit(1, 6); #1;
                    es = (i == `F3_SB) ? (4'b0001 << off) : (i == `F3_SH) ? (off[1] ? 4'b1100 : 4'b0011) : 4'b1111;
                    ok("T4 write in the commit cycle, byte lanes",
                       we === 1 && waddr === 32'h20 + off && wstrb === es &&
                       wdata === ((i == `F3_SB) ? 32'h4444_4444 : (i == `F3_SH) ? 32'h3344_3344 : 32'h1122_3344));
                    step;
                    ok("T4 memory holds the merged word", `MEM[8] === merge(32'hAAAA_AAAA, i, off, 32'h1122_3344));
                    ok("T4 entry freed, single write", we === 0 && lq_full === 0);
                end
            end
        end

        // ---------------- T5: store -> load, same address ----------------
        do_reset;
        `MEM[9] = 32'h0;
        sto(`F3_SW, 1, 32'h24, 32'hCAFE_F00D); step;     // SR next
        ld(`F3_LW, 2, 32'h24); step;                      // store SR here
        for (i = 0; i < 4; i = i + 1) begin
            ok("T5 load waits for the older store", re === 0);
            step;
        end
        commit(1, 1); #1;
        ok("T5 commit cycle: store writes, load not yet", we === 1 && re === 0);
        step;
        ok("T5 load starts the cycle after the commit", re === 1 && raddr === 32'h24);
        step;
        ok("T5 load returns the stored value", lsu_v === 1 && lsu_t === 2 && lsu_val === 32'hCAFE_F00D);
        step;

        // ---------------- T6: load -> store -> load ----------------
        do_reset;
        `MEM[10] = 32'h0000_0011;
        ld(`F3_LW, 1, 32'h28); step;                      // c1: L1 LA
        sto(`F3_SW, 2, 32'h28, 32'h0000_0022); step;      // c2: L1 LW (store waits, D13)
        ok("T6 first load sees the old value", lsu_v === 1 && lsu_t === 1 && lsu_val === 32'h11);
        ld(`F3_LW, 3, 32'h28); step;                      // c3: store SR
        ok("T6 store completes", lsu_v === 1 && lsu_t === 2);
        step;
        commit(0, 1); step;                               // load commit: ignored
        ok("T6 second load still waits", re === 0);
        commit(1, 2); step;
        ok("T6 second load starts after the store commit", re === 1);
        step;
        ok("T6 second load sees the new value", lsu_v === 1 && lsu_t === 3 && lsu_val === 32'h22);
        step;

        // ---------------- T7: queue full ----------------
        do_reset;
        for (i = 0; i < `LSQ_N; i = i + 1) begin
            ok("T7 not full yet", lq_full === 0);
            alloc(0, `F3_LW, i, 1, 7, 0, 0, 0, 0, 0); step;   // all wait on tag 7
        end
        ok("T7 full after LSQ_N allocations", lq_full === 1);
        alloc(0, `F3_LW, 6, 0, 0, 32'h30, 0, 0, 0, 0); step;  // ignored
        ok("T7 allocation while full ignored", lq_full === 1 && re === 0);
        bus(`CDB_MUL, 7, 32'h40); step;                       // every base wakes
        ok("T7 head load starts", re === 1 && lq_full === 1);
        alloc(0, `F3_LW, 6, 0, 0, 32'h30, 0, 0, 0, 0); step;  // full at start: dropped
        ok("T7 freed slot: same-cycle allocation dropped", lq_full === 0);
        alloc(0, `F3_LW, 6, 0, 0, 32'h30, 0, 0, 0, 0); step;  // accepted
        j = 0; c = 0;
        for (i = 0; i < 12; i = i + 1) begin
            if (lsu_v) c = c + 1;
            if (lsu_v && lsu_t == 6) j = j + 1;
            step;
        end
        ok("T7 freed slot reused next cycle (tag 6 once)", j == 1);
        ok("T7 no extra load from the dropped allocation", c == `LSQ_N);
        ok("T7 drained", lq_full === 0 && lsu_v === 0 && re === 0);

        // ---------------- T8: D13 own-bus rule ----------------
        do_reset;
        ld(`F3_LW, 1, 32'h14); step;                  // c: load LA
        ok("T8 load LA", re === 1);
        sto(`F3_SW, 2, 32'h40, 32'h5); step;          // c+1: load LW, store at head and ready
        ok("T8 c+1: bus carries the load, store waits", lsu_v === 1 && lsu_t === 1);
        step;                                         // c+2
        ok("T8 c+2: store SR one cycle later", lsu_v === 1 && lsu_t === 2 && lsu_val === 0);
        step;
        ok("T8 bus idle", lsu_v === 0);
        commit(1, 2); step;

        // ---------------- T9: back-to-back loads ----------------
        do_reset;
        ld(`F3_LW, 1, 32'h10); step;                  // L1 LA
        ok("T9 L1 LA", re === 1 && raddr === 32'h10);
        ld(`F3_LW, 2, 32'h14); step;                  // L1 LW + L2 LA
        ok("T9 L1 LW and L2 LA in the same cycle", lsu_v === 1 && lsu_t === 1 && re === 1 && raddr === 32'h14);
        step;
        ok("T9 L2 LW next cycle", lsu_v === 1 && lsu_t === 2 && lsu_val === 32'h1234_ABCD);
        step;

        // ---------------- T10: wake-up on each bus ----------------
        for (k = 0; k < `NCDB - 1; k = k + 1) begin  // bus CDB_LSU is the DUT's own: T13 covers it
            do_reset;
            alloc(0, `F3_LW, 1, 1, 5, 0, 0, 0, 0, 32'h4); step;   // base waits on tag 5
            ok("T10 load waits for its base", re === 0);
            bus(k, 5, 32'h10); step;
            ok("T10 base woken by bus k, address = value + imm", re === 1 && raddr === 32'h14);
            step; step;
        end
        do_reset;
        alloc(1, `F3_SW, 3, 1, 4, 0, 1, 6, 0, 32'h0); step;    // base tag 4, data tag 6
        bus(`CDB_ALU, 4, 32'h44); bus(`CDB_DIV, 6, 32'hD00D); step;
        ok("T10 base and data from two buses in one cycle", lsu_v === 1 && lsu_t === 3);
        step;
        commit(1, 3); #1;
        ok("T10 store uses both captured values", we === 1 && waddr === 32'h44 && wdata === 32'hD00D);
        step;

        // ---------------- T11: commits that must be ignored ----------------
        do_reset;
        sto(`F3_SW, 2, 32'h48, 32'h7); step; step;     // SR done
        commit(0, 2); #1;  ok("T11 non-store commit of the same tag ignored", we === 0); step;
        commit(1, 5); #1;  ok("T11 store commit of another tag ignored", we === 0); step;
        commit(1, 2); #1;  ok("T11 matching store commit writes", we === 1); step;

        // ---------------- T12: async reset mid-run ----------------
        do_reset;
        ld(`F3_LW, 1, 32'h10); step;
        sto(`F3_SW, 2, 32'h50, 32'h1); step;
        #2 reset_n = 0; #1;
        ok("T12 reset clears at once", lsu_v === 0 && re === 0 && we === 0 && lq_full === 0);
        reset_n = 1;
        ld(`F3_LW, 3, 32'h14); step; step;
        ok("T12 works after reset", lsu_v === 1 && lsu_t === 3 && lsu_val === 32'h1234_ABCD);
        step;

        // ---------------- T13: random traffic ----------------
        do_reset;
        for (i = 0; i < 1024; i = i + 1) begin `MEM[i] = $random; rmem[i] = `MEM[i]; end
        for (i = 0; i < `ROB_N; i = i + 1) begin tag_busy[i] = 0; p_pend[i] = 0; free_now[i] = 0; end
        n_ops = 0; n_cm = 0; seed = 77; la_cnt = 0; d13_cnt = 0; sr_cnt = 0; fails_shown = 0;
        for (cyc = 0; cyc < 30000 || n_cm < n_ops; cyc = cyc + 1) begin
            nf = n_fail;
            #1;
            // ---- 1. observe start-of-cycle outputs
            oldest_st = -1;                                   // oldest store not yet committed
            for (i = n_ops - 1; i >= n_cm; i = i - 1) if (o_st[i]) oldest_st = i;
            if (re) begin
                // must be the oldest load not yet started, with no older uncommitted store
                found = 0;
                for (i = n_cm; i < n_ops && !found; i = i + 1)
                    if (!o_st[i] && o_la[i] < 0) begin found = 1; a = i; end
                ok("T13 LA belongs to the oldest unstarted load", found && raddr === o_addr[a]);
                ok("T13 no load starts past an uncommitted store", oldest_st < 0 || oldest_st > a);
                o_la[a] = cyc; la_cnt = la_cnt + 1;
            end
            if (lsu_v) begin
                a = tag_op[lsu_t];
                ok("T13 bus tag belongs to a live op", tag_busy[lsu_t] && !o_done[a]);
                if (!o_st[a]) begin
                    ok("T13 LW exactly one cycle after LA", o_la[a] == cyc - 1);
                    expv = fmt(o_f3[a], rmem[o_addr[a][11:2]], o_addr[a][1:0]);
                    ok("T13 load value matches reference memory", lsu_val === expv);
                    o_res[a] = lsu_val;
                end else begin
                    ok("T13 store completion carries 0", lsu_val === 0);
                    sr_cnt = sr_cnt + 1;
                    if (a > 0) if (!o_st[a - 1] && o_la[a - 1] == cyc - 2) d13_cnt = d13_cnt + 1;
                end
                o_done[a] = 1; o_dcyc[a] = cyc;
            end
            ok("T13 no write outside a store commit", we === 0);

            // ---- 2. this cycle's inputs
            tv = 0;
            // producers broadcast on buses 0..NCDB-2
            for (k = 0; k < `NCDB - 1; k = k + 1)
                if ($random(seed) & 1) begin
                    tp = $random(seed); used_bus = 0;
                    for (j = 0; j < k; j = j + 1) if (tv[j] && tt[j*W +: W] == tp) used_bus = 1;
                    if (p_pend[tp] && !used_bus) begin
                        bus(k, tp, p_val[tp]);
                        p_pend[tp] = 0; free_now[tp] = 1;
                    end
                end
            // mini-ROB: one in-order commit per cycle
            if (n_cm < n_ops && o_done[n_cm] && o_dcyc[n_cm] < cyc && ($random(seed) % 3 != 0)) begin
                a = n_cm;
                commit(o_st[a], o_tag[a]);
                if (o_st[a]) begin
                    if (o_dsrc_ld[a]) o_data[a] = o_res[o_dld[a]];
                    #1;
                    es = (o_f3[a] == `F3_SB) ? (4'b0001 << o_addr[a][1:0]) :
                         (o_f3[a] == `F3_SH) ? (o_addr[a][1] ? 4'b1100 : 4'b0011) : 4'b1111;
                    word = merge(32'h0, o_f3[a], o_addr[a][1:0], o_data[a]);
                    ok("T13 store writes in its commit cycle",
                       we === 1 && waddr === o_addr[a] && wstrb === es && ((wdata ^ word) & {{8{es[3]}},{8{es[2]}},{8{es[1]}},{8{es[0]}}}) === 0);
                    rmem[o_addr[a][11:2]] = merge(rmem[o_addr[a][11:2]], o_f3[a], o_addr[a][1:0], o_data[a]);
                end
                free_now[o_tag[a]] = 1;
                n_cm = n_cm + 1;
            end
            // dispatch: allocate a new op (stop after 30000 cycles to drain)
            if (cyc < 30000 && !lq_full && n_ops < NOPS && ($random(seed) & 1)) begin
                // need a free tag for the op (and maybe one for a producer)
                found = 0;
                for (j = 0; j < `ROB_N && !found; j = j + 1) if (!tag_busy[j]) begin found = 1; tq = j; end
                if (found) begin
                    a = n_ops;
                    tag_busy[tq] = 1; tag_op[tq] = a;
                    o_st[a] = $random(seed) & 1;
                    case ($random(seed) % 3) 0: o_f3[a] = 3'b000; 1: o_f3[a] = 3'b001; default: o_f3[a] = 3'b010; endcase
                    if (!o_st[a] && ($random(seed) & 1)) o_f3[a] = o_f3[a] | 3'b100;   // LBU/LHU
                    if (o_f3[a] == 3'b110) o_f3[a] = 3'b010;
                    o_addr[a] = ($random(seed) & 32'h3C) | (($random(seed) & 3) & (o_f3[a][1] ? 0 : o_f3[a][0] ? 2 : 3));
                    o_tag[a] = tq; o_done[a] = 0; o_la[a] = -1; o_dsrc_ld[a] = 0; o_data[a] = $random(seed);
                    al_valid = 1; al_store = o_st[a]; al_f3 = o_f3[a]; al_tag = tq;
                    al_imm = $random(seed) & 32'hFF; base = o_addr[a] - al_imm;
                    al_qkv = 0; al_vk = o_data[a];
                    // base operand: ready, or waiting on a new producer
                    al_qjv = 0; al_vj = base;
                    if ($random(seed) & 1)
                        for (j = 0; j < `ROB_N; j = j + 1) if (!tag_busy[j] && !al_qjv) begin
                            al_qjv = 1; al_qj = j; tag_busy[j] = 1; p_pend[j] = 1; p_val[j] = base; al_vj = 0;
                        end
                    // store data: ready, a new producer, or an in-flight load's result
                    if (o_st[a]) begin
                        p = $random(seed) % 3;
                        if (p == 1) begin
                            for (j = 0; j < `ROB_N; j = j + 1) if (!tag_busy[j] && !al_qkv) begin
                                al_qkv = 1; al_qk = j; tag_busy[j] = 1; p_pend[j] = 1; p_val[j] = o_data[a]; al_vk = 0;
                            end
                        end else if (p == 2) begin
                            for (j = a - 1; j >= n_cm && j >= 0 && !o_dsrc_ld[a]; j = j - 1)
                                if (!o_st[j]) begin
                                    o_dsrc_ld[a] = 1; o_dld[a] = j;
                                    if (o_done[j]) begin al_vk = o_res[j]; end              // ROB value
                                    else if (lsu_v && lsu_t == o_tag[j]) al_vk = lsu_val;  // bypass
                                    else begin al_qkv = 1; al_qk = o_tag[j]; end            // wait on cdb_lsu
                                end
                        end
                    end
                    n_ops = n_ops + 1;
                end
            end
            if (n_fail != nf && fails_shown < 5) begin
                fails_shown = fails_shown + 1;
                $display("    (T13 cycle %0d, ops %0d committed %0d)", cyc, n_ops, n_cm);
            end
            @(posedge clk); #1;
            al_valid = 0; tv = 0; cm_valid = 0;
            for (j = 0; j < `ROB_N; j = j + 1) if (free_now[j]) begin tag_busy[j] = 0; free_now[j] = 0; end
            if (cyc > 200000) begin ok("T13 drains (no lost op)", 0); n_cm = n_ops; end
        end
        ok("T13 every op committed", n_cm == n_ops);
        $display("T13: %0d ops, %0d loads started, %0d store completions, %0d store SRs right after a load's LW",
                 n_ops, la_cnt, sr_cnt, d13_cnt);

        if (n_fail == 0) $display("TEST_PASS lsu %0d", n_pass);
        else             $display("TEST_FAIL lsu %0d of %0d checks failed", n_fail, n_pass + n_fail);
        $finish;
    end

endmodule
