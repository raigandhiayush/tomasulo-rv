`include "ooo_defs.vh"

module ooo_decode #(
    parameter SUPPORT_AUIPC = 0
) (
    input  wire [31:0] inst,
    input  wire [31:0] pc,
    output reg  [2:0]  cls,
    output reg         illegal,
    output reg  [2:0]  funct3,
    output reg         sub,
    output reg  [4:0]  rs1,
    output reg  [4:0]  rs2,
    output reg  [4:0]  rd,
    output reg         uses_rs1,
    output reg         uses_rs2,
    output reg         writes_rd,
    output reg         use_imm,
    output reg  [31:0] imm,
    output reg  [31:0] pre_value,
    output reg         is_jal,
    output reg         is_jalr,
    output reg         is_branch,
    output reg  [31:0] br_target
);

    localparam [6:0] OP_LUI    = 7'b0110111;
    localparam [6:0] OP_AUIPC  = 7'b0010111;
    localparam [6:0] OP_JAL    = 7'b1101111;
    localparam [6:0] OP_JALR   = 7'b1100111;
    localparam [6:0] OP_BRANCH = 7'b1100011;
    localparam [6:0] OP_LOAD   = 7'b0000011;
    localparam [6:0] OP_STORE  = 7'b0100011;
    localparam [6:0] OP_ARITHI = 7'b0010011;
    localparam [6:0] OP_ARITHR = 7'b0110011;

    wire [6:0] opcode = inst[6:0];
    wire [2:0] f3     = inst[14:12];
    wire [6:0] f7     = inst[31:25];
    wire [4:0] r1     = inst[19:15];
    wire [4:0] r2     = inst[24:20];
    wire [4:0] r_d    = inst[11:7];

    wire [31:0] imm_i = {{20{inst[31]}}, inst[31:20]};
    wire [31:0] imm_s = {{20{inst[31]}}, inst[31:25], inst[11:7]};
    wire [31:0] imm_b = {{19{inst[31]}}, inst[31], inst[7], inst[30:25], inst[11:8], 1'b0};
    wire [31:0] imm_u = {inst[31:12], 12'b0};
    wire [31:0] imm_j = {{11{inst[31]}}, inst[31], inst[19:12], inst[20], inst[30:21], 1'b0};

    wire [31:0] pc_plus4 = pc + 32'd4;

    always @* begin

        cls       = `CLS_NOP;
        illegal   = 1'b1;
        funct3    = 3'd0;
        sub       = 1'b0;
        rs1       = 5'd0;
        rs2       = 5'd0;
        rd        = 5'd0;
        uses_rs1  = 1'b0;
        uses_rs2  = 1'b0;
        writes_rd = 1'b0;
        use_imm   = 1'b0;
        imm       = 32'd0;
        pre_value = 32'd0;
        is_jal    = 1'b0;
        is_jalr   = 1'b0;
        is_branch = 1'b0;
        br_target = 32'd0;

        case (opcode)

            OP_LUI: begin
                cls       = `CLS_PRE;
                illegal   = 1'b0;
                rd        = r_d;
                writes_rd = (r_d != 5'd0);
                imm       = imm_u;
                pre_value = imm_u;
            end

            OP_AUIPC: begin
                if (SUPPORT_AUIPC != 0) begin
                    cls       = `CLS_PRE;
                    illegal   = 1'b0;
                    rd        = r_d;
                    writes_rd = (r_d != 5'd0);
                    imm       = imm_u;
                    pre_value = pc + imm_u;
                end
            end

            OP_JAL: begin
                cls       = `CLS_PRE;
                illegal   = 1'b0;
                rd        = r_d;
                writes_rd = (r_d != 5'd0);
                imm       = imm_j;
                pre_value = pc_plus4;
                is_jal    = 1'b1;
                br_target = pc + imm_j;
            end

            OP_JALR: begin
                if (f3 == 3'b000) begin
                    cls       = `CLS_BR;
                    illegal   = 1'b0;
                    rs1       = r1;
                    uses_rs1  = 1'b1;
                    rd        = r_d;
                    writes_rd = (r_d != 5'd0);
                    imm       = imm_i;
                    pre_value = pc_plus4;
                    is_jalr   = 1'b1;
                    br_target = imm_i;
                end
            end

            OP_BRANCH: begin
                if (f3 != 3'b010 && f3 != 3'b011) begin
                    cls       = `CLS_BR;
                    illegal   = 1'b0;
                    funct3    = f3;
                    rs1       = r1;
                    rs2       = r2;
                    uses_rs1  = 1'b1;
                    uses_rs2  = 1'b1;
                    imm       = imm_b;
                    is_branch = 1'b1;
                    br_target = pc + imm_b;
                end
            end

            OP_LOAD: begin

                if (f3 == 3'b000 || f3 == 3'b001 || f3 == 3'b010 ||
                    f3 == 3'b100 || f3 == 3'b101) begin
                    cls       = `CLS_LD;
                    illegal   = 1'b0;
                    funct3    = f3;
                    rs1       = r1;
                    uses_rs1  = 1'b1;
                    rd        = r_d;
                    writes_rd = (r_d != 5'd0);
                    use_imm   = 1'b1;
                    imm       = imm_i;
                end
            end

            OP_STORE: begin

                if (f3 == 3'b000 || f3 == 3'b001 || f3 == 3'b010) begin
                    cls       = `CLS_ST;
                    illegal   = 1'b0;
                    funct3    = f3;
                    rs1       = r1;
                    rs2       = r2;
                    uses_rs1  = 1'b1;
                    uses_rs2  = 1'b1;
                    use_imm   = 1'b1;
                    imm       = imm_s;
                end
            end

            OP_ARITHI: begin

                if ((f3 == 3'b001 && f7 == 7'b0000000) ||
                    (f3 == 3'b101 && (f7 == 7'b0000000 || f7 == 7'b0100000)) ||
                    (f3 != 3'b001 && f3 != 3'b101)) begin
                    cls       = `CLS_ALU;
                    illegal   = 1'b0;
                    funct3    = f3;
                    sub       = (f3 == 3'b101) & inst[30];
                    rs1       = r1;
                    uses_rs1  = 1'b1;
                    rd        = r_d;
                    writes_rd = (r_d != 5'd0);
                    use_imm   = 1'b1;
                    imm       = imm_i;
                end
            end

            OP_ARITHR: begin
                if (f7 == 7'b0000001) begin

                    cls       = f3[2] ? `CLS_DIV : `CLS_MUL;
                    illegal   = 1'b0;
                    funct3    = f3;
                    rs1       = r1;
                    rs2       = r2;
                    uses_rs1  = 1'b1;
                    uses_rs2  = 1'b1;
                    rd        = r_d;
                    writes_rd = (r_d != 5'd0);
                end else if (f7 == 7'b0000000 ||
                             (f7 == 7'b0100000 && (f3 == 3'b000 || f3 == 3'b101))) begin
                    cls       = `CLS_ALU;
                    illegal   = 1'b0;
                    funct3    = f3;
                    sub       = inst[30];
                    rs1       = r1;
                    rs2       = r2;
                    uses_rs1  = 1'b1;
                    uses_rs2  = 1'b1;
                    rd        = r_d;
                    writes_rd = (r_d != 5'd0);
                end
            end

            default: begin

            end
        endcase
    end

endmodule
