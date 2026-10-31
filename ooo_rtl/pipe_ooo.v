//  pipe_ooo - baseline `pipe` port wrapper around ooo_core (owner: A, reviewer: B)
//  PROJECT_BLUEPRINT.md 6.14, SIGNALS_REFERENCE.md 2.1, decision D18.
`timescale 1ns/1ps
`include "ooo_defs.vh"

module pipe_ooo
#(
	parameter [31: 0]           RESET = 32'h0000_0000
)
(
	input                       clk,
	input                       reset,
	input                       stall,
	output                      exception,
	output      [31: 0]         pc_out,

	input                       inst_mem_is_valid,
	input       [31: 0]         inst_mem_read_data,
	input       [31: 0]         dmem_read_data_temp,
	input                       dmem_write_valid,
	input                       dmem_read_valid,
	output      [31: 0]         inst_mem_address,
	output                      dmem_read_ready,
	output      [31: 0]         dmem_read_address,
	output                      dmem_write_ready,
	output      [31: 0]         dmem_write_address,
	output      [31: 0]         dmem_write_data,
	output      [ 3: 0]         dmem_write_byte,

	output                      dbg_commit_valid,
	output      [31: 0]         dbg_commit_pc,
	output      [ 4: 0]         dbg_commit_rd,
	output                      dbg_commit_has_rd,
	output      [31: 0]         dbg_commit_value,
	output                      dbg_commit_is_store,
	output                      dbg_ooo_event,
	output                      dbg_stall_rob,
	output                      dbg_stall_rs,
	output                      dbg_hold,
	output      [`NCDB-1:0]     dbg_cdb_valid,
	output                      dbg_dc_access,      // L1 data cache events
	output                      dbg_dc_hit,
	output                      dbg_dc_miss,
	output                      dbg_dc_stall,
	output                      dbg_br_commit,      // branch prediction events
	output                      dbg_br_mispred
);

	ooo_core #(.RESET(RESET)) core (
		.clk                 (clk),
		.reset_n             (reset),
		.imem_addr           (inst_mem_address),
		.imem_data           (inst_mem_read_data),
		.dmem_re             (dmem_read_ready),
		.dmem_raddr          (dmem_read_address),
		.dmem_rdata          (dmem_read_data_temp),
		.dmem_read_valid     (dmem_read_valid),
		.dmem_write_valid    (dmem_write_valid),
		.dmem_we             (dmem_write_ready),
		.dmem_waddr          (dmem_write_address),
		.dmem_wdata          (dmem_write_data),
		.dmem_wstrb          (dmem_write_byte),
		.exception           (exception),
		.dbg_commit_valid    (dbg_commit_valid),
		.dbg_commit_pc       (dbg_commit_pc),
		.dbg_commit_rd       (dbg_commit_rd),
		.dbg_commit_has_rd   (dbg_commit_has_rd),
		.dbg_commit_value    (dbg_commit_value),
		.dbg_commit_is_store (dbg_commit_is_store),
		.dbg_ooo_event       (dbg_ooo_event),
		.dbg_stall_rob       (dbg_stall_rob),
		.dbg_stall_rs        (dbg_stall_rs),
		.dbg_hold            (dbg_hold),
		.dbg_cdb_valid       (dbg_cdb_valid),
		.dbg_dc_access       (dbg_dc_access),
		.dbg_dc_hit          (dbg_dc_hit),
		.dbg_dc_miss         (dbg_dc_miss),
		.dbg_dc_stall        (dbg_dc_stall),
		.dbg_br_commit       (dbg_br_commit),
		.dbg_br_mispred      (dbg_br_mispred)
	);

	assign pc_out = inst_mem_address;

endmodule
