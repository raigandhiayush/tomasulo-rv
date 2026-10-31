`timescale 1ns/1ps
// bpred.v - branch predictor: direct-mapped BTB + 2-bit bimodal table (TOMA-RV)
//
// Fetch side (combinational, in the fetch cycle): f_taken = 1 and f_target when
// f_pc hits a valid BTB entry and the entry is a JAL or the branch's 2-bit counter
// says taken. Anything else is predicted fall-through.
//
// Update side:
//   * conditional branches at commit (up_*): the counter moves towards the outcome
//     and a taken branch is written to the BTB. Only committed branches train the
//     predictor, so wrong-path branches cannot pollute it.
//   * JAL at dispatch (jal_*) when it was not already predicted correctly.
//
// A prediction is only a hint: ooo_dispatch checks it against the decoded
// instruction, and a branch is checked again when it resolves, so a stale entry
// costs cycles and cannot change the architectural result.
// Counters reset to 01 (weakly not taken). reset_n: active low, asynchronous.
`include "ooo_defs.vh"

module bpred #(
    parameter BTB_N = `BTB_N,
    parameter BHT_N = `BHT_N
) (
    input  wire              clk,
    input  wire              reset_n,
    // fetch
    input  wire [`XLEN-1:0]  f_pc,
    output wire              f_taken,
    output wire [`XLEN-1:0]  f_target,
    // committed conditional branch
    input  wire              up_valid,
    input  wire [`XLEN-1:0]  up_pc,
    input  wire              up_taken,
    input  wire [`XLEN-1:0]  up_target,
    // JAL seen at dispatch
    input  wire              jal_valid,
    input  wire [`XLEN-1:0]  jal_pc,
    input  wire [`XLEN-1:0]  jal_target
);
    localparam BTB_W = $clog2(BTB_N);
    localparam BHT_W = $clog2(BHT_N);
    localparam TAG_W = 10 - BTB_W;              // pc[11:2]: instr_mem decodes these bits

    reg  [BTB_N-1:0]    btb_valid;
    reg  [BTB_N-1:0]    btb_uncond;
    reg  [TAG_W-1:0]    btb_tag    [0:BTB_N-1];
    reg  [`XLEN-1:0]    btb_target [0:BTB_N-1];
    reg  [1:0]          bht        [0:BHT_N-1];

    wire [BTB_W-1:0]    f_idx = f_pc[2 +: BTB_W];
    wire                f_hit = btb_valid[f_idx] && btb_tag[f_idx] == f_pc[2+BTB_W +: TAG_W];

    assign f_taken  = f_hit & (btb_uncond[f_idx] | bht[f_pc[2 +: BHT_W]][1]);
    assign f_target = btb_target[f_idx];

    wire [BTB_W-1:0]    u_idx = up_pc[2 +: BTB_W];
    wire [BHT_W-1:0]    u_bht = up_pc[2 +: BHT_W];
    wire [BTB_W-1:0]    j_idx = jal_pc[2 +: BTB_W];

    integer i;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            btb_valid  <= {BTB_N{1'b0}};
            btb_uncond <= {BTB_N{1'b0}};
            for (i = 0; i < BHT_N; i = i + 1) bht[i] <= 2'b01;
        end else begin
            if (up_valid) begin
                if (up_taken && bht[u_bht] != 2'b11) bht[u_bht] <= bht[u_bht] + 2'b01;
                if (!up_taken && bht[u_bht] != 2'b00) bht[u_bht] <= bht[u_bht] - 2'b01;
                if (up_taken) begin
                    btb_valid[u_idx]  <= 1'b1;
                    btb_uncond[u_idx] <= 1'b0;
                    btb_tag[u_idx]    <= up_pc[2+BTB_W +: TAG_W];
                    btb_target[u_idx] <= up_target;
                end
            end
            if (jal_valid) begin
                btb_valid[j_idx]  <= 1'b1;
                btb_uncond[j_idx] <= 1'b1;
                btb_tag[j_idx]    <= jal_pc[2+BTB_W +: TAG_W];
                btb_target[j_idx] <= jal_target;
            end
        end
    end
endmodule
