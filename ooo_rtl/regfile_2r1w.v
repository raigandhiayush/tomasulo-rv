// regfile_2r1w.v - RV32 integer register file (31 registers, 2 read ports, 1 write port).
`timescale 1ns/1ps

`include "ooo_defs.vh"

module regfile_2r1w (
    input  wire        clk,
    input  wire        reset_n,   // asynchronous, active low
    // read port 1 (rs1)
    input  wire [`REG_W-1:0] raddr1,
    output wire [`XLEN-1:0]  rdata1,
    // read port 2 (rs2)
    input  wire [`REG_W-1:0] raddr2,
    output wire [`XLEN-1:0]  rdata2,
    // write port
    input  wire        we,
    input  wire [`REG_W-1:0] waddr,
    input  wire [`XLEN-1:0]  wdata
);

    reg [`XLEN-1:0] regs [1:`NREG-1];
    integer i;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            for (i = 1; i < `NREG; i = i + 1)
                regs[i] <= {`XLEN{1'b0}};
        end else if (we && waddr != {`REG_W{1'b0}}) begin
            regs[waddr] <= wdata;
        end
    end

    assign rdata1 = (raddr1 == {`REG_W{1'b0}}) ? {`XLEN{1'b0}} : regs[raddr1];
    assign rdata2 = (raddr2 == {`REG_W{1'b0}}) ? {`XLEN{1'b0}} : regs[raddr2];

endmodule
