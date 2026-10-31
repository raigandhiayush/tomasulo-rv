`timescale 1ns/1ps
`include "ooo_defs.vh"

module lsu #(
    parameter LSQ_N = `LSQ_N,
    parameter ROB_W = `ROB_W
) (
    input  wire                     clk,
    input  wire                     reset_n,
    // allocate (dispatch, program order)
    input  wire                     lq_al_valid,
    input  wire                     lq_al_store,
    input  wire [`F3_W-1:0]         lq_al_funct3,
    input  wire [ROB_W-1:0]         lq_al_tag,
    input  wire                     lq_al_qj_valid,
    input  wire [ROB_W-1:0]         lq_al_qj,
    input  wire [`XLEN-1:0]         lq_al_vj,
    input  wire                     lq_al_qk_valid,
    input  wire [ROB_W-1:0]         lq_al_qk,
    input  wire [`XLEN-1:0]         lq_al_vk,
    input  wire [`XLEN-1:0]         lq_al_imm,
    output wire                     lq_full,
    // the four buses (wake-up)
    input  wire [`NCDB-1:0]         cdb_valid,
    input  wire [`NCDB*ROB_W-1:0]   cdb_tag,
    input  wire [`NCDB*`XLEN-1:0]   cdb_value,
    // the LSU's own bus
    output wire                     cdb_lsu_valid,
    output wire [ROB_W-1:0]         cdb_lsu_tag,
    output wire [`XLEN-1:0]         cdb_lsu_value,
    // commit (ROB)
    input  wire                     cm_valid,
    input  wire [ROB_W-1:0]         cm_tag,         // also the ROB head
    input  wire                     cm_is_store,
    // mispredict recovery: ROB entries being removed
    input  wire [(1<<ROB_W)-1:0]    squash,
    // data memory
    output wire                     dmem_re,
    output wire [`XLEN-1:0]         dmem_raddr,
    input  wire [`XLEN-1:0]         dmem_rdata,
    input  wire                     dmem_stall,     // cache busy: start nothing
    input  wire                     dmem_rvalid,    // dmem_rdata holds the load's word
    output wire                     dmem_we,
    output wire [`XLEN-1:0]         dmem_waddr,
    output reg  [`XLEN-1:0]         dmem_wdata,
    output reg  [3:0]               dmem_wstrb
);

    localparam QW = (LSQ_N > 1) ? $clog2(LSQ_N) : 1;

    // ---- queue state ---------------------------------------------------------
    reg  [LSQ_N-1:0]        busy;
    reg  [LSQ_N-1:0]        is_st;
    reg  [`F3_W-1:0]        f3     [0:LSQ_N-1];
    reg  [ROB_W-1:0]        tag    [0:LSQ_N-1];
    reg  [LSQ_N-1:0]        qj_valid;
    reg  [ROB_W-1:0]        qj     [0:LSQ_N-1];
    reg  [`XLEN-1:0]        vj     [0:LSQ_N-1];
    reg  [LSQ_N-1:0]        qk_valid;
    reg  [ROB_W-1:0]        qk     [0:LSQ_N-1];
    reg  [`XLEN-1:0]        vk     [0:LSQ_N-1];
    reg  [`XLEN-1:0]        imm    [0:LSQ_N-1];
    reg  [LSQ_N-1:0]        sr_done;            // store has broadcast (SR)

    reg  [QW-1:0]           head;
    reg  [QW-1:0]           tail;
    reg  [QW:0]             count;

    // ---- load in flight (between LA and LW) ----------------------------------
    reg                     ld_pend;
    reg  [ROB_W-1:0]        ld_tag;
    reg  [`F3_W-1:0]        ld_f3;
    reg  [1:0]              ld_off;

    wire [QW-1:0] head_next = (head == LSQ_N-1) ? {QW{1'b0}} : head + 1'b1;
    wire [QW-1:0] tail_next = (tail == LSQ_N-1) ? {QW{1'b0}} : tail + 1'b1;

    assign lq_full = (count == LSQ_N);
    wire   do_alloc = lq_al_valid & ~lq_full;

    // ---- head decisions ------------------------------------------------------
    wire              h_busy  = busy[head];
    wire              h_st    = is_st[head];
    wire [`XLEN-1:0]  h_addr  = vj[head] + imm[head];
    wire [1:0]        h_off   = h_addr[1:0];

    // With speculation a load may be on the wrong path. Reading RAM is harmless,
    // but an MMIO load waits until it is the oldest instruction in the machine.
    wire spec      = (`SPEC_EN != 0);
    wire h_mmio    = (h_addr[31:28] == 4'h1);
    wire la_go     = h_busy & ~h_st & ~qj_valid[head] & ~dmem_stall
                   & ~(spec & squash[tag[head]])
                   & ~(spec & h_mmio & (tag[head] != cm_tag));
    wire sr_go     = h_busy &  h_st & ~sr_done[head] & ~qj_valid[head] & ~qk_valid[head]
                   & ~ld_pend & ~dmem_stall;                     // D13
    wire st_commit = h_busy &  h_st &  sr_done[head] & cm_valid & cm_is_store
                   & (cm_tag == tag[head]);
    wire do_pop    = la_go | st_commit;

    // ---- memory ports ----------------------------------------------------------
    assign dmem_re    = la_go;
    assign dmem_raddr = h_addr;
    assign dmem_we    = st_commit;
    assign dmem_waddr = h_addr;

    always @(*) begin
        case (f3[head])
            `F3_SB: begin
                dmem_wdata = {4{vk[head][7:0]}};
                dmem_wstrb = 4'b0001 << h_off;
            end
            `F3_SH: begin
                dmem_wdata = {2{vk[head][15:0]}};
                dmem_wstrb = h_off[1] ? 4'b1100 : 4'b0011;
            end
            default: begin                                     // SW
                dmem_wdata = vk[head];
                dmem_wstrb = 4'b1111;
            end
        endcase
    end

    // ---- load formatting (LW cycle) ------------------------------------------
    wire [7:0]  ld_byte = dmem_rdata >> {ld_off, 3'b000};
    wire [15:0] ld_half = ld_off[1] ? dmem_rdata[31:16] : dmem_rdata[15:0];
    reg  [`XLEN-1:0] ld_value;
    always @(*) begin
        case (ld_f3)
            `F3_LB:  ld_value = {{24{ld_byte[7]}},  ld_byte};
            `F3_LH:  ld_value = {{16{ld_half[15]}}, ld_half};
            `F3_LBU: ld_value = {24'd0, ld_byte};
            `F3_LHU: ld_value = {16'd0, ld_half};
            default: ld_value = dmem_rdata;                    // LW
        endcase
    end

    // ---- own bus: a load result (LW) or a store completion (SR), never both ----
    wire   ld_done       = ld_pend & dmem_rvalid;
    assign cdb_lsu_valid = ld_done | sr_go;
    assign cdb_lsu_tag   = ld_pend ? ld_tag   : tag[head];
    assign cdb_lsu_value = ld_pend ? ld_value : {`XLEN{1'b0}};

    // ---- mispredict recovery: squashed entries are a suffix of the queue ----------
    integer q;
    reg  [QW:0] n_sq;
    always @(*) begin
        n_sq = 0;
        for (q = 0; q < LSQ_N; q = q + 1)
            if (spec && busy[q] && squash[tag[q]]) n_sq = n_sq + 1'b1;
    end
    localparam [QW:0] LSQ_C = LSQ_N;
    wire [QW:0] tail_ext = {1'b0, tail} + LSQ_C - n_sq;
    wire [QW:0] tail_rew = (tail_ext >= LSQ_C) ? tail_ext - LSQ_C : tail_ext;

    // ---- state -------------------------------------------------------------------
    integer i, b;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            busy     <= {LSQ_N{1'b0}};
            is_st    <= {LSQ_N{1'b0}};
            qj_valid <= {LSQ_N{1'b0}};
            qk_valid <= {LSQ_N{1'b0}};
            sr_done  <= {LSQ_N{1'b0}};
            head     <= {QW{1'b0}};
            tail     <= {QW{1'b0}};
            count    <= {(QW+1){1'b0}};
            ld_pend  <= 1'b0;
            ld_tag   <= {ROB_W{1'b0}};
            ld_f3    <= {`F3_W{1'b0}};
            ld_off   <= 2'd0;
            for (i = 0; i < LSQ_N; i = i + 1) begin
                f3[i]  <= {`F3_W{1'b0}};
                tag[i] <= {ROB_W{1'b0}};
                qj[i]  <= {ROB_W{1'b0}};
                qk[i]  <= {ROB_W{1'b0}};
                vj[i]  <= {`XLEN{1'b0}};
                vk[i]  <= {`XLEN{1'b0}};
                imm[i] <= {`XLEN{1'b0}};
            end
        end else begin
            // wake-up from every bus
            for (i = 0; i < LSQ_N; i = i + 1)
                for (b = 0; b < `NCDB; b = b + 1)
                    if (busy[i] && cdb_valid[b]) begin
                        if (qj_valid[i] && qj[i] == cdb_tag[b*ROB_W +: ROB_W]) begin
                            vj[i]       <= cdb_value[b*`XLEN +: `XLEN];
                            qj_valid[i] <= 1'b0;
                        end
                        if (qk_valid[i] && qk[i] == cdb_tag[b*ROB_W +: ROB_W]) begin
                            vk[i]       <= cdb_value[b*`XLEN +: `XLEN];
                            qk_valid[i] <= 1'b0;
                        end
                    end

            // load in flight: from LA until its word arrives (LW)
            if (la_go) begin
                ld_pend <= 1'b1;
                ld_tag  <= tag[head];
                ld_f3   <= f3[head];
                ld_off  <= h_off;
            end else if (ld_done)
                ld_pend <= 1'b0;

            if (sr_go) sr_done[head] <= 1'b1;

            if (do_pop) begin
                busy[head] <= 1'b0;
                head       <= head_next;
            end

            // the tail slot is free whenever the queue is not full, so it never
            // collides with the head being popped
            if (do_alloc) begin
                busy[tail]     <= 1'b1;
                is_st[tail]    <= lq_al_store;
                f3[tail]       <= lq_al_funct3;
                tag[tail]      <= lq_al_tag;
                qj_valid[tail] <= lq_al_qj_valid;
                qj[tail]       <= lq_al_qj;
                vj[tail]       <= lq_al_vj;
                qk_valid[tail] <= lq_al_store & lq_al_qk_valid;
                qk[tail]       <= lq_al_qk;
                vk[tail]       <= lq_al_vk;
                imm[tail]      <= lq_al_imm;
                sr_done[tail]  <= 1'b0;
                tail           <= tail_next;
            end

            if (do_alloc && !do_pop)      count <= count + 1'b1;
            else if (!do_alloc && do_pop) count <= count - 1'b1;

            // Dispatch sends nothing in a flush cycle, so there is no allocation.
            // A squashed load in flight just forgets its result; if the cache or
            // memory is still working on it, dmem_stall holds the next operation.
            if (n_sq != 0) begin
                for (q = 0; q < LSQ_N; q = q + 1)
                    if (busy[q] && squash[tag[q]]) busy[q] <= 1'b0;
                tail  <= tail_rew[QW-1:0];
                count <= count - n_sq - (do_pop ? 1'b1 : 1'b0);
            end
            if (spec && ld_pend && squash[ld_tag] && !la_go)
                ld_pend <= 1'b0;
        end
    end

endmodule
