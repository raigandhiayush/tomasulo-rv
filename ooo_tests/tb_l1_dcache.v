`timescale 1ns/1ps
`include "ooo_defs.vh"

module tbdc_harness #(
    parameter WAYS  = 2,
    parameter SETS  = 8,
    parameter WORDS = 4,
    parameter WB    = 1,
    parameter WAIT  = 0,        // mem_wait in front of data_mem (load latencies then vary)
    parameter NAME  = "H"
) (
    input  wire         clk,
    output reg          done,
    output integer      n_pass,
    output integer      n_fail
);
    localparam OFF_W   = $clog2(WORDS);
    localparam IDX_W   = $clog2(SETS);
    localparam MAXOPS  = 8192;
    localparam NRAND   = 6000;
    localparam [31:0] DEV = 32'h1000_0010;     // MMIO read/write register

    // ---- DUT and its memory system ---------------------------------------------
    reg                 reset_n = 1'b0;
    reg                 req_valid = 1'b0, req_we = 1'b0;
    reg     [31:0]      req_addr = 0, req_wdata = 0;
    reg     [3:0]       req_be = 0;
    wire                stall, resp_ready;
    wire    [31:0]      resp_data;
    wire                mem_re, mem_we;
    wire    [31:0]      mem_raddr, mem_waddr, mem_wdata, mem_rdata, ram_rdata;
    wire    [3:0]       mem_wstrb;
    wire                ev_access, ev_hit, ev_miss, ev_stall;

    l1_dcache #(.WAYS(WAYS), .SETS(SETS), .WORDS(WORDS), .WB(WB), .MEM_AW(12)) dut (
        .clk(clk), .reset_n(reset_n),
        .req_valid(req_valid), .req_we(req_we), .req_addr(req_addr),
        .req_wdata(req_wdata), .req_byte_en(req_be),
        .stall(stall), .resp_ready(resp_ready), .resp_data(resp_data),
        .mem_re(mem_re), .mem_raddr(mem_raddr), .mem_rdata(mem_rdata),
        .mem_read_valid(mem_read_valid), .mem_write_valid(mem_write_valid),
        .mem_we(mem_we), .mem_waddr(mem_waddr), .mem_wdata(mem_wdata), .mem_wstrb(mem_wstrb),
        .ev_access(ev_access), .ev_hit(ev_hit), .ev_miss(ev_miss), .ev_stall(ev_stall));

    wire w_mmio = (mem_waddr[31:28] == 4'h1);
    wire r_mmio = (mem_raddr[31:28] == 4'h1);
    wire        mem_read_valid, mem_write_valid, rm_re, rm_we;
    wire [31:0] rm_raddr, rm_waddr, rm_wdata;
    wire [3:0]  rm_wstrb;
    mem_wait #(.WAIT(WAIT), .WBUF_N(4)) MW (.clk(clk), .reset_n(reset_n),
                .re(mem_re & ~r_mmio), .raddr(mem_raddr),
                .we(mem_we & ~w_mmio), .waddr(mem_waddr), .wdata(mem_wdata), .wstrb(mem_wstrb),
                .read_valid(mem_read_valid), .write_valid(mem_write_valid),
                .ram_re(rm_re), .ram_raddr(rm_raddr), .ram_we(rm_we), .ram_waddr(rm_waddr),
                .ram_wdata(rm_wdata), .ram_wstrb(rm_wstrb));
    data_mem M (.clk(clk), .re(rm_re), .raddr(rm_raddr), .rdata(ram_rdata),
                .we(rm_we), .waddr(rm_waddr), .wdata(rm_wdata), .wstrb(rm_wstrb));

    // MMIO device: DEV is a register, any other MMIO word reads mmio_val(addr)
    function [31:0] mmio_val(input [31:0] a);
        mmio_val = {a[15:0] ^ 16'hC0DE, a[15:0]};
    endfunction
    function [31:0] merge(input [31:0] old, input [31:0] nw, input [3:0] be);
        merge = {be[3] ? nw[31:24] : old[31:24], be[2] ? nw[23:16] : old[23:16],
                 be[1] ? nw[15: 8] : old[15: 8], be[0] ? nw[ 7: 0] : old[ 7: 0]};
    endfunction
    reg     [31:0]      dev_reg;
    reg                 mm_q;
    reg     [31:0]      mm_val_q;
    always @(posedge clk) begin
        if (mem_re) begin
            mm_q     <= (mem_raddr[31:28] == 4'h1);
            mm_val_q <= (mem_raddr == DEV) ? dev_reg : mmio_val(mem_raddr);
        end
        if (mem_we && mem_waddr == DEV) dev_reg <= merge(dev_reg, mem_wdata, mem_wstrb);
    end
    assign mem_rdata = mm_q ? mm_val_q : ram_rdata;

    // ---- checking --------------------------------------------------------------------
    task check(input ok, input [8*48-1:0] what, input [31:0] got, input [31:0] exp);
        begin
            if (ok) n_pass = n_pass + 1;
            else begin
                n_fail = n_fail + 1;
                if (n_fail <= 15)
                    $display("TEST_FAIL l1_dcache %0s %0s: got %h expected %h (cycle %0d)",
                             NAME, what, got, exp, cyc);
            end
        end
    endtask

    integer cyc = 0;
    always @(posedge clk) cyc <= cyc + 1;

    // ---- operation list -------------------------------------------------------------
    reg            op_we [0:MAXOPS-1];
    reg   [31:0]   op_a  [0:MAXOPS-1];
    reg   [31:0]   op_d  [0:MAXOPS-1];
    reg   [3:0]    op_be [0:MAXOPS-1];
    integer        n_ops = 0;

    task add_ld(input [31:0] a);
        begin op_we[n_ops] = 0; op_a[n_ops] = a; op_d[n_ops] = 0; op_be[n_ops] = 4'hF; n_ops = n_ops + 1; end
    endtask
    task add_st(input [31:0] a, input [31:0] d, input [3:0] be);
        begin op_we[n_ops] = 1; op_a[n_ops] = a; op_d[n_ops] = d; op_be[n_ops] = be; n_ops = n_ops + 1; end
    endtask
    // the LSU's store formatting (SB / SH / SW)
    task add_sb(input [31:0] a, input [7:0] v);  add_st(a, {4{v}}, 4'b0001 << a[1:0]);           endtask
    task add_sh(input [31:0] a, input [15:0] v); add_st(a, {2{v}}, a[1] ? 4'b1100 : 4'b0011);    endtask
    task add_sw(input [31:0] a, input [31:0] v); add_st(a, v, 4'b1111);                          endtask

    // ---- golden memory and cache-state model ---------------------------------------------
    reg   [31:0]   gmem [0:1023];
    reg   [31:0]   gdev;
    reg            mvalid [0:1][0:SETS-1];
    reg            mdirty [0:1][0:SETS-1];
    reg   [31:0]   mtag   [0:1][0:SETS-1];
    reg            mlru   [0:SETS-1];

    // expected bus traffic and responses
    integer exp_rd = 0, exp_wr = 0, bus_rd = 0, bus_wr = 0;
    integer n_hit_pred = 0, n_miss_pred = 0, n_wb_pred = 0, n_mmio = 0;
    integer n_acc = 0, n_hit = 0, n_miss = 0;
    reg   [31:0]   q_val [0:15];        // pending load responses (in order)
    integer        q_lat [0:15];
    integer        q_acc [0:15];
    integer        q_wr = 0, q_rd = 0;
    reg            pend_valid = 0;      // the op driven this cycle (checked at the posedge)
    reg            pend_cache = 0, pend_hit = 0;

    integer i, w, set, tag, v;
    reg            is_mmio, hit_p, wb_p;
    integer        lat_p;
    reg   [31:0]   exp_v;

    // predict and apply one operation to the models; returns via globals
    task model_op(input we, input [31:0] a, input [31:0] d, input [3:0] be);
        begin
            is_mmio = (a[31:28] == 4'h1);
            hit_p = 0; wb_p = 0; lat_p = 1;
            if (is_mmio) begin
                n_mmio = n_mmio + 1;
                if (we) begin exp_wr = exp_wr + 1; if (a == DEV) gdev = merge(gdev, d, be); end
                else begin exp_rd = exp_rd + 1; exp_v = (a == DEV) ? gdev : mmio_val(a); end
            end else begin
                if (!we) exp_v = gmem[a[11:2]];
                else     gmem[a[11:2]] = merge(gmem[a[11:2]], d, be);
                set = (a >> (2 + OFF_W)) & (SETS - 1);
                tag = (a[11:0] >> (2 + OFF_W + IDX_W));
                for (w = 0; w < WAYS; w = w + 1)
                    if (mvalid[w][set] && mtag[w][set] == tag) begin hit_p = 1; v = w; end
                if (hit_p) begin
                    n_hit_pred = n_hit_pred + 1;
                    if (we && WB)  mdirty[v][set] = 1;
                    if (we && !WB) exp_wr = exp_wr + 1;
                    if (WAYS > 1)  mlru[set] = !v;
                end else begin
                    n_miss_pred = n_miss_pred + 1;
                    if (we && !WB) exp_wr = exp_wr + 1;          // no allocate
                    else begin
                        if (WAYS == 1)             v = 0;
                        else if (!mvalid[0][set])  v = 0;
                        else if (!mvalid[1][set])  v = 1;
                        else                       v = mlru[set];
                        wb_p = WB && mvalid[v][set] && mdirty[v][set];
                        if (wb_p) begin n_wb_pred = n_wb_pred + 1; exp_wr = exp_wr + WORDS; end
                        exp_rd = exp_rd + WORDS;
                        mvalid[v][set] = 1; mtag[v][set] = tag; mdirty[v][set] = we;
                        if (WAYS > 1) mlru[set] = !v;
                        lat_p = WORDS + 2 + (wb_p ? WORDS : 0);
                    end
                end
            end
        end
    endtask

    // ---- driver (negedge): check the response, then drive the next operation -------------
    integer op_i = 0;
    reg     running = 0;
    reg     gap;
    always @(negedge clk) if (running) begin
        if (resp_ready) begin
            check(q_rd != q_wr, "response with no load pending", resp_data, 0);
            if (q_rd != q_wr) begin
                check(resp_data === q_val[q_rd % 16], "load data", resp_data, q_val[q_rd % 16]);
                if (WAIT == 0)
                    check(cyc - q_acc[q_rd % 16] == q_lat[q_rd % 16], "load latency (cycles)",
                          cyc - q_acc[q_rd % 16], q_lat[q_rd % 16]);
                q_rd = q_rd + 1;
            end
        end else if (!stall)
            check(q_rd == q_wr, "stall = 0 with a load response still pending", q_wr - q_rd, 0);

        req_valid = 0;
        pend_valid = 0;
        gap = (op_i >= 60) && (($random & 3) == 0);      // directed part back to back
        if (!stall && op_i < n_ops && !gap) begin
            model_op(op_we[op_i], op_a[op_i], op_d[op_i], op_be[op_i]);
            req_valid = 1; req_we = op_we[op_i]; req_addr = op_a[op_i];
            req_wdata = op_d[op_i]; req_be = op_be[op_i];
            pend_valid = 1; pend_cache = !is_mmio; pend_hit = hit_p;
            if (!op_we[op_i]) begin
                q_val[q_wr % 16] = exp_v;
                q_lat[q_wr % 16] = lat_p;
                q_acc[q_wr % 16] = cyc;
                q_wr = q_wr + 1;
            end
            op_i = op_i + 1;
        end
    end

    // ---- monitor (posedge): events and bus traffic ----------------------------------------
    always @(posedge clk) if (running) begin
        if (mem_re) bus_rd = bus_rd + 1;
        if (mem_we) bus_wr = bus_wr + 1;
        if (mem_re && mem_we) check(0, "memory read and write in one cycle", 1, 0);
        if (ev_access) n_acc = n_acc + 1;
        if (ev_hit)    n_hit = n_hit + 1;
        if (ev_miss)   n_miss = n_miss + 1;
        if (pend_valid) begin
            check(!stall, "driver sent a request while stall = 1", 1, 0);
            check(ev_access === pend_cache, "ev_access", ev_access, pend_cache);
            if (pend_cache) begin
                check(ev_hit === pend_hit, "hit / miss vs cache-state model", ev_hit, pend_hit);
                check(ev_miss === !pend_hit, "ev_miss", ev_miss, !pend_hit);
            end
        end else
            check(!ev_access && !ev_hit && !ev_miss, "event without a request", ev_access, 0);
        check(ev_stall === stall, "ev_stall = stall", ev_stall, stall);
    end

    // ---- memory seen through the cache ----------------------------------------------------
    function [31:0] coherent(input integer word);
        integer l, k, hits;
        reg [31:0] a;
        begin
            a = word << 2;
            coherent = M.dmem[word];
            for (l = 0; l < WAYS * SETS; l = l + 1)
                if (dut.valid[l] && dut.tags[l] == (a >> (2 + OFF_W + IDX_W))
                    && (l % SETS) == ((a >> (2 + OFF_W)) & (SETS - 1)))
                    coherent = dut.data[l * WORDS + ((a >> 2) & (WORDS - 1))];
        end
    endfunction

    // ---- stimulus ------------------------------------------------------------------------
    reg [31:0] a, r;
    integer k, line_b;
    initial begin
        done = 0; n_pass = 0; n_fail = 0;
        line_b = 4 * WORDS;                              // bytes per line
        for (k = 0; k < 1024; k = k + 1) begin
            M.dmem[k] = 32'hA000_0000 | (k * 32'h0001_0101);
            gmem[k]   = M.dmem[k];
        end
        dev_reg = 32'h5EED_0000; gdev = dev_reg; mm_q = 0; mm_val_q = 0;
        for (k = 0; k < SETS; k = k + 1) begin
            mvalid[0][k] = 0; mvalid[1][k] = 0; mdirty[0][k] = 0; mdirty[1][k] = 0; mlru[k] = 0;
        end

        // directed part (addresses chosen per configuration: same-set lines are
        // way_bytes apart, way_bytes = SETS * line bytes)
        add_ld(32'h100);                                  // cold miss
        add_ld(32'h104);                                  // hit, same line
        add_sw(32'h108, 32'hDEAD_BEEF);                   // store hit
        add_ld(32'h108);                                  // RAW: load right after the store
        add_sb(32'h109, 8'h5A);                           // SB lane 1
        add_sh(32'h10A, 16'h1234);                        // SH upper half
        add_sb(32'h108, 8'h77);                           // SB lane 0
        add_ld(32'h108);                                  // merged word
        add_sh(32'h10C, 16'hBEEF);                        // SH lower half
        add_ld(32'h10C);
        // clean replacement in the set of 0x200 (no stores to these lines)
        add_ld(32'h200);
        add_ld(32'h200 + SETS * line_b);
        add_ld(32'h200);                                  // hit: the other way is LRU
        add_ld(32'h200 + 2 * SETS * line_b);              // miss: evicts a clean line
        add_ld(32'h200);
        add_ld(32'h200 + SETS * line_b);
        // dirty victim: store (WB: allocate + dirty), then two more lines of the set
        add_sw(32'h300, 32'hCAFE_0300);
        add_ld(32'h300 + SETS * line_b);
        add_ld(32'h300 + 2 * SETS * line_b);              // evicts the dirty line (WB)
        add_ld(32'h300 + 3 * SETS * line_b);
        add_ld(32'h300);                                  // must return the stored value
        // store miss (WT: no allocate) then load of the same word
        add_sw(32'h3F0, 32'h0BAD_F00D);
        add_ld(32'h3F0);
        // MMIO: pass-through, never cached, never written to data_mem
        add_ld(32'h1000_0008);
        add_sw(DEV, 32'h1122_3344);
        add_ld(DEV);
        add_sb(DEV + 2, 8'hEE);
        add_ld(DEV);
        add_ld(32'h1000_000C);
        add_ld(32'h0000_0010);                            // data_mem word aliased by DEV: unchanged
        add_sw(32'h1000_0000, 32'hFFFF_FFFF);             // MMIO store to a non-device word
        add_ld(32'h0000_0000);                            // its data_mem alias: unchanged
        // aliasing above 4 KB: data_mem decodes addr[11:2]
        add_sw(32'hFFFF_F120, 32'hA11A_5000);
        add_ld(32'h0000_0120);
        add_ld(32'h0ABC_D120);
        // back-to-back loads over several lines
        for (k = 0; k < 16; k = k + 1) add_ld(32'h400 + 4 * k);
        add_ld(32'h400);
        // pad the directed part to 60 operations
        while (n_ops < 60) add_ld(32'h104);

        // random part: a 1 KB region (conflicts in every set), aliases, MMIO
        for (k = 0; k < NRAND; k = k + 1) begin
            r = $random;
            case (r[3:0])
                4'd0:    a = 32'h1000_0000 | ({$random} % 8) << 2;            // MMIO
                4'd1:    a = 32'hFFFF_F000 | ({$random} % 256) << 2;          // alias
                default: a = ({$random} % 256) << 2;                          // 0x000-0x3FC
            endcase
            if (r[4] && r[5]) begin
                case ({$random} % 3)
                    0: add_sb(a | ({$random} & 3), $random);
                    1: add_sh(a | ({$random} & 2), $random);
                    default: add_sw(a, $random);
                endcase
            end else
                add_ld(a);
        end

        repeat (3) @(negedge clk);
        reset_n = 1;
        @(negedge clk);
        running = 1;
        wait (op_i == n_ops);
        @(negedge clk);                                  // the last request is accepted
        while (stall || q_rd != q_wr) @(negedge clk);
        repeat (3 + WAIT * 8) @(negedge clk);            // the write buffer drains
        running = 0;

        // ---- end-of-run checks
        check(q_rd == q_wr, "every load got exactly one response", q_rd, q_wr);
        check(n_acc == n_hit + n_miss, "accesses = hits + misses", n_acc, n_hit + n_miss);
        check(n_hit == n_hit_pred, "hit count vs model", n_hit, n_hit_pred);
        check(n_miss == n_miss_pred, "miss count vs model", n_miss, n_miss_pred);
        check(bus_rd == exp_rd, "memory-port reads vs model", bus_rd, exp_rd);
        check(bus_wr == exp_wr, "memory-port writes vs model", bus_wr, exp_wr);
        check(dev_reg === gdev, "MMIO device register", dev_reg, gdev);
        for (k = 0; k < 1024; k = k + 1) begin
            check(coherent(k) === gmem[k], "memory through the cache", coherent(k), gmem[k]);
            if (!WB) check(M.dmem[k] === gmem[k], "write-through: data_mem itself", M.dmem[k], gmem[k]);
        end
        if (WB) check(n_wb_pred > 0, "random run produced dirty write-backs", n_wb_pred, 1);
        $display("%0s: WAYS=%0d SETS=%0d WORDS=%0d WB=%0d: %0d ops (%0d MMIO), hits=%0d misses=%0d write-backs=%0d, bus reads=%0d writes=%0d, %0d checks, %0d failures",
                 NAME, WAYS, SETS, WORDS, WB, n_ops, n_mmio,
                 n_hit, n_miss, n_wb_pred, bus_rd, bus_wr, n_pass, n_fail);
        done = 1;
    end
endmodule


module tb_l1_dcache;
    reg clk = 1'b0;
    always #5 clk = ~clk;

    wire       d0, d1, d2, d3, d4;
    integer    p0, p1, p2, p3, p4, f0, f1, f2, f3, f4;

    tbdc_harness #(.WAYS(2), .SETS(8), .WORDS(4), .WB(1), .NAME("H0")) H0 (.clk(clk), .done(d0), .n_pass(p0), .n_fail(f0));
    tbdc_harness #(.WAYS(2), .SETS(8), .WORDS(4), .WB(0), .NAME("H1")) H1 (.clk(clk), .done(d1), .n_pass(p1), .n_fail(f1));
    tbdc_harness #(.WAYS(1), .SETS(4), .WORDS(8), .WB(1), .NAME("H2")) H2 (.clk(clk), .done(d2), .n_pass(p2), .n_fail(f2));

    tbdc_harness #(.WAYS(2), .SETS(8), .WORDS(4), .WB(1), .WAIT(5), .NAME("H3")) H3 (.clk(clk), .done(d3), .n_pass(p3), .n_fail(f3));
    tbdc_harness #(.WAYS(2), .SETS(8), .WORDS(4), .WB(0), .WAIT(5), .NAME("H4")) H4 (.clk(clk), .done(d4), .n_pass(p4), .n_fail(f4));

    initial begin
        #1;
        wait (d0 && d1 && d2 && d3 && d4);
        if (f0 + f1 + f2 + f3 + f4 == 0) $display("TEST_PASS l1_dcache %0d", p0 + p1 + p2 + p3 + p4);
        else                   $display("TEST_FAIL l1_dcache %0d failures, %0d passed", f0 + f1 + f2 + f3 + f4, p0 + p1 + p2 + p3 + p4);
        $finish;
    end
    initial begin
        #200_000_000;
        $display("TEST_FAIL l1_dcache timeout");
        $finish;
    end
endmodule
