`include "ooo_defs.vh"

module mul_unit (
    input  wire             clk,
    input  wire             reset_n,
    input  wire             start,
    input  wire [1:0]       funct3,
    input  wire [31:0]      a,
    input  wire [31:0]      b,
    input  wire [`ROB_W-1:0] tag,
    output wire             done,
    output wire [`ROB_W-1:0] done_tag,
    output wire [31:0]      result
);

    wire a_signed = (funct3 != 2'b11);
    wire b_signed = ~funct3[1];

    wire [32:0] a_ext = {a_signed & a[31], a};
    wire [32:0] b_ext = {b_signed & b[31], b};

    reg [32:0]       s1_a;
    reg [32:0]       s1_b;
    reg [1:0]        s1_f3;
    always @(posedge clk) begin
        s1_a  <= a_ext;
        s1_b  <= b_ext;
        s1_f3 <= funct3;
    end

    reg              s1_valid;
    reg [`ROB_W-1:0]  s1_tag;
    reg              s2_valid;
    reg [`ROB_W-1:0]  s2_tag;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            s1_valid <= 1'b0;
            s1_tag   <= {`ROB_W{1'b0}};
            s2_valid <= 1'b0;
            s2_tag   <= {`ROB_W{1'b0}};
        end else begin
            s1_valid <= start;
            s1_tag   <= start ? tag : {`ROB_W{1'b0}};
            s2_valid <= s1_valid;
            s2_tag   <= s1_tag;
        end
    end

    wire signed [65:0] product = $signed(s1_a) * $signed(s1_b);

    reg [31:0] s2_result;
    always @(posedge clk) begin
        if (s1_f3 == 2'b00) s2_result <= product[31:0];
        else                s2_result <= product[63:32];
    end

    assign done     = s2_valid;
    assign done_tag = s2_valid ? s2_tag    : {`ROB_W{1'b0}};
    assign result   = s2_valid ? s2_result : 32'd0;

endmodule
