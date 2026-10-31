`timescale 1ns/1ps
`include "ooo_defs.vh"

module rob #(
    parameter ROB_N = `ROB_N,
    parameter ROB_W = `ROB_W
) (
    input  wire                     clk,
    input  wire                     reset_n,
    // allocate (dispatch)
    input  wire                     rob_al_valid,
    input  wire [`KIND_W-1:0]       rob_al_kind,
    input  wire                     rob_al_has_rd,
    input  wire [`REG_W-1:0]        rob_al_rd,
    input  wire [`XLEN-1:0]         rob_al_pc,
    input  wire                     rob_al_pre,
    input  wire [`XLEN-1:0]         rob_al_value,
    input  wire                     rob_al_cond,    // conditional branch
    input  wire                     rob_al_exc,     // illegal instruction
    output wire [ROB_W-1:0]         rob_al_tag,
    output wire                     rob_full,
    output wire                     rob_empty,
    output wire [ROB_W:0]           rob_count,
    // operand read ports (dispatch)
    input  wire [ROB_W-1:0]         rob_rd_tag1,
    input  wire [ROB_W-1:0]         rob_rd_tag2,
    output wire                     rob_rd_ready1,
    output wire                     rob_rd_ready2,
    output wire [`XLEN-1:0]         rob_rd_value1,
    output wire [`XLEN-1:0]         rob_rd_value2,
    // the four buses
    input  wire [`NCDB-1:0]         cdb_valid,
    input  wire [`NCDB*ROB_W-1:0]   cdb_tag,
    input  wire [`NCDB*`XLEN-1:0]   cdb_value,
    // commit
    output wire                     cm_valid,
    output wire [ROB_W-1:0]         cm_tag,
    output wire                     cm_has_rd,
    output wire [`REG_W-1:0]        cm_rd,
    output wire [`XLEN-1:0]         cm_value,
    output wire                     cm_is_store,
    output wire [`XLEN-1:0]         cm_pc,
    output wire                     cm_is_cond,
    output wire                     cm_taken,
    output wire                     cm_mispred,
    output wire                     cm_exc,
    // branch resolve: outcome, and the branch's pc for the recovery address
    input  wire                     br_res_valid,
    input  wire [ROB_W-1:0]         br_res_tag,
    input  wire                     br_res_taken,
    input  wire                     br_res_mispred,
    output wire [`XLEN-1:0]         br_res_pc,
    // mispredict recovery: remove everything younger than flush_tag
    input  wire                     flush_valid,
    input  wire [ROB_W-1:0]         flush_tag,
    output reg  [ROB_N-1:0]         squash,
    // out-of-order completion evidence
    output reg                      ooo_event
);

    reg  [ROB_N-1:0]        valid;
    reg  [ROB_N-1:0]        ready;
    reg  [`KIND_W-1:0]      kind   [0:ROB_N-1];
    reg  [ROB_N-1:0]        has_rd;
    reg  [`REG_W-1:0]       rd     [0:ROB_N-1];
    reg  [`XLEN-1:0]        value  [0:ROB_N-1];
    reg  [`XLEN-1:0]        pc     [0:ROB_N-1];
    reg  [ROB_N-1:0]        is_cond;
    reg  [ROB_N-1:0]        taken;
    reg  [ROB_N-1:0]        mispred;
    reg  [ROB_N-1:0]        exc;
    reg  [ROB_N-1:0]        ooo_done;           // completed while an older entry waited

    reg  [ROB_W-1:0]        head;
    reg  [ROB_W-1:0]        tail;
    reg  [ROB_W:0]          count;

    wire do_alloc  = rob_al_valid & ~rob_full;
    wire do_commit = cm_valid;

    wire [ROB_W-1:0] head_next = (head == ROB_N-1) ? {ROB_W{1'b0}} : head + 1'b1;
    wire [ROB_W-1:0] tail_next = (tail == ROB_N-1) ? {ROB_W{1'b0}} : tail + 1'b1;

    // ---- status and allocate ------------------------------------------------
    assign rob_full   = (count == ROB_N);
    assign rob_empty  = (count == 0);
    assign rob_count  = count;
    assign rob_al_tag = tail;

    // ---- read ports ---------------------------------------------------------
    assign rob_rd_ready1 = valid[rob_rd_tag1] & ready[rob_rd_tag1];
    assign rob_rd_ready2 = valid[rob_rd_tag2] & ready[rob_rd_tag2];
    assign rob_rd_value1 = value[rob_rd_tag1];
    assign rob_rd_value2 = value[rob_rd_tag2];

    // ---- commit (head) ------------------------------------------------------
    assign cm_valid    = valid[head] & ready[head];
    assign cm_tag      = head;
    assign cm_has_rd   = has_rd[head];
    assign cm_rd       = rd[head];
    assign cm_value    = value[head];
    assign cm_is_store = (kind[head] == `KIND_STORE);
    assign cm_pc       = pc[head];
    assign cm_is_cond  = is_cond[head];
    assign cm_taken    = taken[head];
    assign cm_mispred  = mispred[head];
    assign cm_exc      = exc[head];
    assign br_res_pc   = pc[br_res_tag];

    // ---- mispredict recovery -------------------------------------------------
    // ROB_N is a power of 2, so ROB_W-bit subtraction gives the distance from head.
    wire [ROB_W-1:0] flush_dist = flush_tag - head;
    reg  [ROB_W-1:0] sq_t;
    integer s;
    always @(*) begin
        squash = {ROB_N{1'b0}};
        for (s = 0; s < ROB_N; s = s + 1) begin
            sq_t = s[ROB_W-1:0] - head;
            if (flush_valid && valid[s] && sq_t > flush_dist) squash[s] = 1'b1;
        end
    end

    // ---- ooo_event (D18) ----------------------------------------------------
    // With speculation, a wrong-path completion must not count, and only commit
    // knows which path was right: the event is one committed instruction that
    // finished while an older one was still waiting.
    integer k;
    reg     ooo_now;
    always @(*) begin
        ooo_now = 1'b0;
        for (k = 0; k < `NCDB; k = k + 1)
            if (cdb_valid[k] && cdb_tag[k*ROB_W +: ROB_W] != head &&
                valid[head] && !ready[head])
                ooo_now = 1'b1;
        ooo_event = (`SPEC_EN != 0) ? (cm_valid & ooo_done[head]) : ooo_now;
    end

    // ---- state --------------------------------------------------------------
    integer i, b;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            valid  <= {ROB_N{1'b0}};
            ready  <= {ROB_N{1'b0}};
            has_rd <= {ROB_N{1'b0}};
            is_cond  <= {ROB_N{1'b0}};
            taken    <= {ROB_N{1'b0}};
            mispred  <= {ROB_N{1'b0}};
            exc      <= {ROB_N{1'b0}};
            ooo_done <= {ROB_N{1'b0}};
            head   <= {ROB_W{1'b0}};
            tail   <= {ROB_W{1'b0}};
            count  <= {(ROB_W+1){1'b0}};
            for (i = 0; i < ROB_N; i = i + 1) begin
                kind[i]  <= `KIND_VALUE;
                rd[i]    <= {`REG_W{1'b0}};
                value[i] <= {`XLEN{1'b0}};
                pc[i]    <= {`XLEN{1'b0}};
            end
        end else begin
            // complete: one write port per bus, never the same entry twice
            for (b = 0; b < `NCDB; b = b + 1)
                if (cdb_valid[b] && valid[cdb_tag[b*ROB_W +: ROB_W]]) begin
                    ready[cdb_tag[b*ROB_W +: ROB_W]] <= 1'b1;
                    value[cdb_tag[b*ROB_W +: ROB_W]] <= cdb_value[b*`XLEN +: `XLEN];
                    if (cdb_tag[b*ROB_W +: ROB_W] != head && valid[head] && !ready[head])
                        ooo_done[cdb_tag[b*ROB_W +: ROB_W]] <= 1'b1;
                end

            if (br_res_valid) begin
                taken[br_res_tag]   <= br_res_taken;
                mispred[br_res_tag] <= br_res_mispred;
            end

            // commit frees the head (tail != head unless full, and a full ROB
            // ignores allocation, so commit and allocate never hit one entry)
            if (do_commit) begin
                valid[head] <= 1'b0;
                ready[head] <= 1'b0;
                head        <= head_next;
            end

            if (do_alloc) begin
                valid[tail]  <= 1'b1;
                ready[tail]  <= rob_al_pre;
                kind[tail]   <= rob_al_kind;
                has_rd[tail] <= rob_al_has_rd;
                rd[tail]     <= rob_al_rd;
                value[tail]  <= rob_al_pre ? rob_al_value : {`XLEN{1'b0}};
                pc[tail]     <= rob_al_pc;
                is_cond[tail]  <= rob_al_cond;
                taken[tail]    <= 1'b0;
                mispred[tail]  <= 1'b0;
                exc[tail]      <= rob_al_exc;
                ooo_done[tail] <= 1'b0;
                tail         <= tail_next;
            end

            if (do_alloc && !do_commit)      count <= count + 1'b1;
            else if (!do_alloc && do_commit) count <= count - 1'b1;

            // recovery runs last so it overrides a completion in the same cycle.
            // Dispatch sends nothing in a flush cycle, so there is no allocation.
            if (flush_valid) begin
                for (i = 0; i < ROB_N; i = i + 1)
                    if (squash[i]) begin
                        valid[i] <= 1'b0;
                        ready[i] <= 1'b0;
                    end
                tail  <= (flush_tag == ROB_N-1) ? {ROB_W{1'b0}} : flush_tag + 1'b1;
                count <= {1'b0, flush_dist} + 1'b1 - (do_commit ? 1'b1 : 1'b0);
            end
        end
    end

    // synthesis translate_off
    // A stale tag is the classic speculation bug: a squashed instruction still in a
    // functional unit completing a newer instruction that reused its ROB entry.
    // Broadcasting to a free entry means something was not killed.
    integer c_b;
    always @(posedge clk)
        if (reset_n)
            for (c_b = 0; c_b < `NCDB; c_b = c_b + 1)
                if (cdb_valid[c_b] === 1'b1 && valid[cdb_tag[c_b*ROB_W +: ROB_W]] === 1'b0)
                    $display("TEST_FAIL rob stale broadcast: bus %0d tag %0d is not allocated (t=%0t)",
                             c_b, cdb_tag[c_b*ROB_W +: ROB_W], $time);
    // synthesis translate_on

endmodule
