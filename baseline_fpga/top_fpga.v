`timescale 1ns / 1ps

module top_fpga #(
	parameter IMEMSIZE = 4096,
	parameter DMEMSIZE = 4096
)(
	input  wire clk,    	// fast board clock (e.g. 100 MHz)
	input  wire reset,  	// active-low reset
 
 
output [15:0] led
    
);

wire [15:0] pc_disp = pipe_u.inst_fetch_pc[15:0];
wire exception;
	// 100 MHz to 1 Hz clock divider.
reg [25:0] clk_cnt;   	// enough for 50 million
reg    	slow_clk;

always @(posedge clk or negedge reset) begin
	if (!reset) begin
    	clk_cnt  <= 26'd0;
    	slow_clk <= 1'b0;
	end else begin
    	if (clk_cnt == 26'd49_999_999) begin
        	clk_cnt  <= 26'd0;
        	slow_clk <= ~slow_clk;   // toggle every 0.5 sec
    	end else begin
        	clk_cnt <= clk_cnt + 1'b1;
    	end
	end
end


	////////////////////////////////////////////////////////////
	// PIPE ↔ MEMORY WIRES
	////////////////////////////////////////////////////////////
	wire [31:0] inst_mem_read_data;
	wire    	inst_mem_is_valid;

	wire [31:0] dmem_read_data;
	wire    	dmem_write_valid;
	wire    	dmem_read_valid;
	wire [31:0] inst_mem_address;

    wire        dmem_read_ready;
    wire [31:0] dmem_read_address;

    wire   dmem_write_ready;
    wire [31:0] dmem_write_address;
    wire [31:0] dmem_write_data;
    wire [3:0]  dmem_write_byte;

	assign inst_mem_is_valid = 1'b1;
	assign dmem_write_valid  = 1'b1;
	assign dmem_read_valid   = 1'b1;
    assign led = pc_disp;

////////////////////////////////////////////////////////////
// PIPELINE CPU
////////////////////////////////////////////////////////////
pipe pipe_u (
	.clk(slow_clk),
	.reset(reset),
	.stall(1'b0),
	.exception(exception),
	.pc_out(),

	.inst_mem_is_valid(inst_mem_is_valid),
	.inst_mem_read_data(inst_mem_read_data),

	.dmem_read_data_temp(dmem_read_data),
	.dmem_write_valid(dmem_write_valid),
	.dmem_read_valid(dmem_read_valid),
	.inst_mem_address(inst_mem_address),
// TODO: Might have a few more port signals
	.dmem_read_ready(dmem_read_ready),
	.dmem_read_address(dmem_read_address),
	.dmem_write_ready(dmem_write_ready),
	.dmem_write_address(dmem_write_address),
	.dmem_write_data(dmem_write_data),
	.dmem_write_byte(dmem_write_byte)
);


////////////////////////////////////////////////////////////
// INSTRUCTION MEMORY  (matches instr_mem.v)
////////////////////////////////////////////////////////////
instr_mem IMEM (
	.clk(slow_clk),
	.pc(inst_mem_address),
	.instr(inst_mem_read_data)
);


////////////////////////////////////////////////////////////
// DATA MEMORY  (matches data_mem.v)
////////////////////////////////////////////////////////////
data_mem DMEM (
	.clk(slow_clk),

	.re(dmem_read_ready),
	.raddr(dmem_read_address),
	.rdata(dmem_read_data),

	.we(dmem_write_ready),
	.waddr(dmem_write_address),
	.wdata(dmem_write_data),
	.wstrb(dmem_write_byte)
);



endmodule