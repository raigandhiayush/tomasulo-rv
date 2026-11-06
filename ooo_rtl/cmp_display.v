// cmp_display.v - 8-digit 7-segment driver for top_fpga_cmp, with decimal and ratio modes.
//
//   mode 0  HEX   a as 8 hex digits
//   mode 1  DEC   a as an unsigned decimal number, leading zeros blank
//   mode 2  SDEC  a as a signed decimal number ('-' in front when negative)
//   mode 3  RATIO a / b in decimal with 3 places, e.g. 2.034 (a * 1000 / b, rounded down)
//
// A number that does not fit in 8 digits (7 digits and '-' when negative) shows "--------",
// and so does a ratio with b = 0.
//
// The value is converted by a small sequential engine that loops forever: latch the
// inputs, divide (ratio only, 42 cycles), convert to decimal (double dabble, 27 cycles),
// copy to the digit registers. A new value appears about 75 clock cycles after the inputs
// change, much faster than the eye can see; the display never shows a half-built number.
//
// Digit codes in dig (5 bits per digit, digit 0 = rightmost): 0-15 hex digit, 16 '-',
// 17 blank. dp has one bit per digit (1 = decimal point on). Testbenches read dig and dp.
`timescale 1ns/1ps

module cmp_display #(
    parameter REFRESH_W = 17        // 50 MHz / 2^17 = 381 Hz per digit
) (
    input  wire        clk,
    input  wire        reset_n,     // active low, asynchronous
    input  wire [ 1:0] mode,
    input  wire [31:0] a,
    input  wire [31:0] b,
    output wire [ 7:0] seg,         // {DP, CG, CF, CE, CD, CC, CB, CA}, active low
    output wire [ 7:0] an,          // active low
    output reg  [39:0] dig,         // 8 x 5-bit digit codes
    output reg  [ 7:0] dp
);
    localparam [4:0] C_DASH = 5'd16, C_BLANK = 5'd17;
    localparam [2:0] S_LATCH = 3'd0, S_DIV = 3'd1, S_QCHK = 3'd2, S_BCD = 3'd3, S_OUT = 3'd4;

    reg  [ 2:0] st;
    reg  [ 1:0] m;                  // latched mode
    reg  [31:0] hexv;               // latched a for HEX
    reg         neg;                // SDEC: a was negative
    reg         bad;                // does not fit, or ratio with b = 0
    reg  [31:0] den;
    reg  [32:0] r;                  // divider remainder
    reg  [41:0] n;                  // dividend bits shifting out, quotient shifting in
    reg  [ 5:0] cnt;
    reg  [26:0] bin;                // value being converted (fits: < 10^8 < 2^27)
    reg  [31:0] bcd;                // 8 BCD digits
    reg  [39:0] dig_n;
    reg  [ 7:0] dp_n;

    // a * 1000 = a * 1024 - a * 16 - a * 8 (no multiplier)
    wire [41:0] a1000 = ({10'd0, a} << 10) - ({10'd0, a} << 4) - ({10'd0, a} << 3);
    wire [31:0] a_abs = a[31] ? (~a + 32'd1) : a;

    // restoring division step
    wire [32:0] r_sh = {r[31:0], n[41]};
    wire        ge   = (r_sh >= {1'b0, den});

    // double-dabble step: add 3 to each BCD digit >= 5, then shift
    reg  [31:0] bcd_adj;
    integer k;
    always @(*) begin
        for (k = 0; k < 8; k = k + 1)
            bcd_adj[4*k +: 4] = (bcd[4*k +: 4] >= 4'd5) ? bcd[4*k +: 4] + 4'd3 : bcd[4*k +: 4];
    end

    // decimal limit: 8 digits, or 7 when a '-' is needed
    function [41:0] limit(input is_neg);
        limit = is_neg ? 42'd10_000_000 : 42'd100_000_000;
    endfunction

    // final digits from bcd: leading zeros blank down to digit `keep`, '-' in front if neg
    reg  [39:0] fmt_dig;
    reg  [ 7:0] fmt_dp;
    reg         lead;
    integer j;
    always @(*) begin
        fmt_dig = {8{C_BLANK}};
        fmt_dp  = 8'd0;
        lead    = 1'b1;             // assigned on every path: no latch
        if (m == 2'd0) begin
            for (j = 0; j < 8; j = j + 1) fmt_dig[5*j +: 5] = {1'b0, hexv[4*j +: 4]};
        end else if (bad) begin
            fmt_dig = {8{C_DASH}};
        end else begin
            lead = 1'b1;
            for (j = 7; j >= 0; j = j - 1) begin
                if (bcd[4*j +: 4] != 4'd0 || j == 0 || (m == 2'd3 && j <= 3)) lead = 1'b0;
                if (!lead) fmt_dig[5*j +: 5] = {1'b0, bcd[4*j +: 4]};
            end
            // '-' goes in the blank digit just left of the first shown digit
            if (neg) begin
                // scan from the left, so the '-' just placed is not seen as a shown digit
                for (j = 7; j >= 1; j = j - 1)
                    if (fmt_dig[5*j +: 5] == C_BLANK && fmt_dig[5*(j-1) +: 5] != C_BLANK)
                        fmt_dig[5*j +: 5] = C_DASH;
            end
            if (m == 2'd3) fmt_dp[3] = 1'b1;
        end
    end

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            st <= S_LATCH; m <= 2'd0; hexv <= 32'd0; neg <= 1'b0; bad <= 1'b0;
            den <= 32'd0; r <= 33'd0; n <= 42'd0; cnt <= 6'd0; bin <= 27'd0; bcd <= 32'd0;
            dig <= {8{C_BLANK}}; dp <= 8'd0;
        end else begin
            case (st)
                S_LATCH: begin
                    m <= mode; hexv <= a; bcd <= 32'd0;
                    neg <= (mode == 2'd2) && a[31];
                    bad <= 1'b0;
                    if (mode == 2'd3) begin
                        den <= b; r <= 33'd0; n <= a1000; cnt <= 6'd42;
                        if (b == 32'd0) begin bad <= 1'b1; st <= S_OUT; end
                        else             st <= S_DIV;
                    end else if (mode == 2'd0) begin
                        st <= S_OUT;
                    end else begin
                        // DEC / SDEC
                        if ({10'd0, (mode == 2'd2) ? a_abs : a} >= limit((mode == 2'd2) && a[31])) begin
                            bad <= 1'b1; st <= S_OUT;
                        end else begin
                            bin <= ((mode == 2'd2) ? a_abs[26:0] : a[26:0]);
                            cnt <= 6'd27; st <= S_BCD;
                        end
                    end
                end
                S_DIV: begin
                    r   <= ge ? r_sh - {1'b0, den} : r_sh;
                    n   <= {n[40:0], ge};
                    cnt <= cnt - 6'd1;
                    if (cnt == 6'd1) st <= S_QCHK;
                end
                S_QCHK: begin                              // quotient ready in n
                    if (n >= limit(1'b0)) begin bad <= 1'b1; st <= S_OUT; end
                    else begin bin <= n[26:0]; cnt <= 6'd27; st <= S_BCD; end
                end
                S_BCD: begin
                    bcd <= {bcd_adj[30:0], bin[26]};
                    bin <= {bin[25:0], 1'b0};
                    cnt <= cnt - 6'd1;
                    if (cnt == 6'd1) st <= S_OUT;
                end
                default: begin                             // S_OUT
                    dig <= fmt_dig;
                    dp  <= fmt_dp;
                    st  <= S_LATCH;
                end
            endcase
        end
    end

    // ---- multiplexed drive ---------------------------------------------------------
    reg [REFRESH_W+2:0] refresh;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) refresh <= {(REFRESH_W+3){1'b0}};
        else          refresh <= refresh + 1'b1;
    end
    wire [2:0] digit = refresh[REFRESH_W+2:REFRESH_W];
    wire [4:0] code  = dig[5*digit +: 5];
    reg  [6:0] font;                // {g, f, e, d, c, b, a}, active high
    always @(*) begin
        case (code)
            5'h00: font = 7'h3F;  5'h01: font = 7'h06;  5'h02: font = 7'h5B;  5'h03: font = 7'h4F;
            5'h04: font = 7'h66;  5'h05: font = 7'h6D;  5'h06: font = 7'h7D;  5'h07: font = 7'h07;
            5'h08: font = 7'h7F;  5'h09: font = 7'h6F;  5'h0A: font = 7'h77;  5'h0B: font = 7'h7C;
            5'h0C: font = 7'h39;  5'h0D: font = 7'h5E;  5'h0E: font = 7'h79;  5'h0F: font = 7'h71;
            C_DASH: font = 7'h40;
            default: font = 7'h00;  // blank
        endcase
    end
    assign seg = ~{dp[digit], font};
    assign an  = ~(8'd1 << digit);
endmodule
