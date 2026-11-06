// cmp_clkgate.v - glitch-free clock gate for the slow-memory baseline in top_fpga_cmp.
`timescale 1ns/1ps

module cmp_clkgate (
    input  wire clk_in,
    input  wire ce,
    output wire gclk
);
`ifdef TOMA_SIM
    reg ce_l = 1'b0;
    always @(clk_in or ce)
        if (!clk_in) ce_l = ce;
    assign gclk = clk_in & ce_l;
`else
    BUFGCE u_bufgce (.I(clk_in), .CE(ce), .O(gclk));
`endif
endmodule
