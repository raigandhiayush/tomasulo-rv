// div_unit.v - RV32M divider for TOMA-RV (Person E)
`timescale 1ns/1ps
// Radix-2 restoring divider: DIV, DIVU, REM, REMU. One operation at a time.
// Ports follow SIGNALS_REFERENCE.md section 2.12; ROB_W comes from ooo_defs.vh.
//
// Timing contract (Q6, proposed by E, pending A's sign-off):
//   * Fixed latency for every input, corner cases included:
//     start sampled in cycle t  ->  done=1 for exactly one cycle in t+33
//     (34-cycle occupancy t..t+33, as planned in blueprint section 6.11).
//       t+1 .. t+32 : 32 restoring iterations; the last one also applies
//                     the sign fix and corner-case select
//       t+33        : done=1, result and done_tag valid
//   * busy is a registered output: 0 in cycle t, 1 in t+1 .. t+32, and 0 in
//     the done cycle t+33, so C's DIV RS (iss_accept = ~busy) can start the
//     next divide in t+33.
//   * result and done_tag hold their value after done until the next done.
//
// funct3 = funct3[1:0] of the M-extension divide instructions:
//   2'b00 DIV, 2'b01 DIVU, 2'b10 REM, 2'b11 REMU
//
// Corner cases (RISC-V spec, M extension):
//   x / 0        : quotient = 0xFFFFFFFF, remainder = dividend
//   INT_MIN / -1 : quotient = INT_MIN,    remainder = 0
//   remainder takes the sign of the dividend
//
// Reset: reset_n, active low, asynchronous (baseline convention).
// Pure Verilog-2001, no vendor primitives.

`include "ooo_defs.vh"

module div_unit #(
    parameter ROB_W = `ROB_W            // from ooo_defs.vh; do not hard-code
) (
    input  wire              clk,
    input  wire              reset_n,
    input  wire              start,     // ignored unless busy==0
    input  wire [`OP_MD_HI:0] funct3,
    input  wire [`XLEN-1:0]  a,         // dividend (rs1)
    input  wire [`XLEN-1:0]  b,         // divisor  (rs2)
    input  wire [ROB_W-1:0]  tag,
    input  wire [(1<<ROB_W)-1:0] squash, // ROB entries being removed
    output reg               busy,
    output reg               done,
    output reg  [`XLEN-1:0]  result,
    output reg  [ROB_W-1:0]  done_tag
);

    reg [4:0]        count;
    reg [31:0]       quo;               // shifts in quotient bits, shifts out dividend bits
    reg [31:0]       rem;
    reg [31:0]       dvs;               // |divisor|
    reg              neg_q, neg_r;      // sign of quotient / remainder
    reg              is_rem, div_zero;
    reg [ROB_W-1:0]  op_tag;

    wire is_signed = ~funct3[0];
    wire a_neg     = is_signed & a[31];
    wire b_neg     = is_signed & b[31];
    wire [31:0] a_abs = a_neg ? (~a + 32'd1) : a;
    wire [31:0] b_abs = b_neg ? (~b + 32'd1) : b;

    // one restoring step
    wire [32:0] rem_sh = {rem, quo[31]};
    wire [33:0] diff   = {1'b0, rem_sh} - {2'b00, dvs};
    wire        fits   = ~diff[33];
    wire [31:0] quo_nx = {quo[30:0], fits};
    wire [31:0] rem_nx = fits ? diff[31:0] : rem_sh[31:0];

    // final sign fix, used on the last iteration.
    // x/0: the loop already yields quo=0xFFFFFFFF and rem=|a|; skip the quotient
    // negation so DIV stays all ones. INT_MIN/-1 falls out naturally.
    wire [31:0] q_fixed = div_zero ? 32'hFFFF_FFFF : (neg_q ? (~quo_nx + 32'd1) : quo_nx);
    wire [31:0] r_fixed = neg_r ? (~rem_nx + 32'd1) : rem_nx;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            busy     <= 1'b0;
            done     <= 1'b0;
            count    <= 5'd0;
            quo      <= 32'd0;
            rem      <= 32'd0;
            dvs      <= 32'd0;
            neg_q    <= 1'b0;
            neg_r    <= 1'b0;
            is_rem   <= 1'b0;
            div_zero <= 1'b0;
            op_tag   <= {ROB_W{1'b0}};
            result   <= 32'd0;
            done_tag <= {ROB_W{1'b0}};
        end else begin
            done <= 1'b0;
            if (busy && squash[op_tag]) begin
                busy <= 1'b0;                   // abort: the divider is free next cycle
            end else if (!busy) begin
                if (start && squash[tag]) begin
                    // squashed in the cycle it would start
                end else if (start) begin
                    busy     <= 1'b1;
                    count    <= 5'd0;
                    quo      <= a_abs;
                    rem      <= 32'd0;
                    dvs      <= b_abs;
                    div_zero <= (b == 32'd0);
                    neg_q    <= a_neg ^ b_neg;
                    neg_r    <= a_neg;
                    is_rem   <= funct3[1];
                    op_tag   <= tag;
                end
            end else begin
                quo   <= quo_nx;
                rem   <= rem_nx;
                count <= count + 5'd1;
                if (count == 5'd31) begin
                    result   <= is_rem ? r_fixed : q_fixed;
                    done_tag <= op_tag;
                    done     <= 1'b1;
                    busy     <= 1'b0;
                end
            end
        end
    end

endmodule
