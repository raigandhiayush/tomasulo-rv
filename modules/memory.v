module instr_mem (
	input  wire    	clk,
	input  wire [31:0] pc, 	// byte address
	output reg  [31:0] instr
);

	// 4 KB instruction memory (1024 words)
	(* ram_style = "block" *)
	reg [31:0] imem [0:1023];

	// Initialize instruction memory from hex file
	initial begin
    	$readmemh("../mem_generator/imem_dmem/imem.hex", imem);
	end

	// Synchronous instruction fetch using word-aligned PC
	always @(posedge clk) begin
    	instr <= imem[pc[11:2]];	// word address
	end

endmodule



// Data Memory (DMEM)
module data_mem (
	input     	clk,

	// Read port
	input     	re,
	input  [31:0] raddr,   // byte address
	output reg [31:0] rdata,

	// Write port
	input     	we,
	input  [31:0] waddr,   // byte address
	input  [31:0] wdata,
	input  [3:0]  wstrb
);

	// 4 KB data memory (1024 words)
	reg [31:0] dmem [0:1023];
	// Decode byte address to word index
	wire [9:0] rindex = raddr[11:2];
	wire [9:0] windex = waddr[11:2];

	// Data memory initialization

	// Synchronous write and read logic with byte masking and forwarding.

	always @(posedge clk) begin
    	// ---- WRITE ----
    	if (we) begin
        	if (wstrb[0]) dmem[windex][7:0]   <= wdata[7:0];
        	if (wstrb[1]) dmem[windex][15:8]  <= wdata[15:8];
        	if (wstrb[2]) dmem[windex][23:16] <= wdata[23:16];// TODO-DMEM-3
        	if (wstrb[3]) dmem[windex][31:24] <= wdata[31:24];// TODO-DMEM-3
    	end

    	// ---- READ (1-cycle latency, RAW-safe) ----
    	if (re) begin
        	if (we && (rindex == windex)) begin
            	// Byte-level forwarding
            	rdata[7:0]   <= wstrb[0] ? wdata[7:0]   : dmem[rindex][7:0];
            	rdata[15:8]  <= wstrb[1] ? wdata[15:8]  : dmem[rindex][15:8];// TODO-DMEM-3
            	rdata[23:16] <= wstrb[2] ? wdata[23:16] : dmem[rindex][23:16];// TODO-DMEM-3
            	rdata[31:24] <= wstrb[3] ? wdata[31:24] : dmem[rindex][31:24];// TODO-DMEM-3
        	end
        	else begin
            	rdata <= dmem[rindex];
        	end
    	end
    	// else: rdata holds value (exact match to original)
	end

endmodule