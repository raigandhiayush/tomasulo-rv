`timescale 1ns/1ps
// instr_mem_wr - instruction memory with a write port, used only by top_fpga_ooo so the
// UART boot loader (uart_loader.v) can replace the program without a new bitstream.
//
// Reads are identical to instr_mem in modules/memory.v: one word per clock, registered,
// indexed by pc[11:2], and the same $readmemh default image. The array keeps the name
// imem, so testbenches that preload DUT.U_IMEM.imem still work. instr_mem itself is
// unchanged; the baseline cores and their testbenches keep using it.
//
// Being writable also means synthesis can no longer trim or merge bits based on the
// initial contents, so any program fits the same bitstream.
module instr_mem_wr (
    input  wire        clk,
    input  wire [31:0] pc,      // byte address
    output reg  [31:0] instr,
    input  wire        we,      // write port: boot loader only
    input  wire [ 9:0] waddr,   // word address
    input  wire [31:0] wdata
);
    (* ram_style = "block" *)
    reg [31:0] imem [0:1023];

    initial begin
        $readmemh("../mem_generator/imem_dmem/imem.hex", imem);
    end

    always @(posedge clk) begin
        if (we) imem[waddr] <= wdata;
        instr <= imem[pc[11:2]];
    end
endmodule
