// regfile_2r1w.v - RV32 integer register file for TOMA-RV (Person E)
`timescale 1ns/1ps
// 31 x 32-bit registers (x1..x31), 2 read ports, 1 write port.
//
// Contract:
//   * x0 always reads 0; a write to x0 is ignored.
//   * reset_n is active low and asynchronous (baseline convention, same as
//     div_unit): clears x1..x31.
//   * Reads are combinational from the array and return the value held at
//     the start of the cycle. There is NO write-through: a read of the
//     register being written in the same cycle returns the OLD value; the
//     new value is visible from the next cycle. Any bypass belongs to the
//     rename / operand-read logic, not here.
//
// Because every register is reset, synthesis builds this from flip-flops
// (31 x 32 = 992 FFs) rather than LUTRAM. That is fine on the Nexys A7.
//
// Pure Verilog-2001, no vendor primitives.

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
