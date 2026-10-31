`timescale 1ns/1ps
`include "ooo_defs.vh"

module instr_queue #(
    parameter DEPTH = `IQ_DEPTH,
    parameter CW    = $clog2(DEPTH + 1)
) (
    input  wire        clk,
    input  wire        reset_n,
    input  wire        flush,
    input  wire        push,
    input  wire [`XLEN-1:0] in_pc,
    input  wire [`XLEN-1:0] in_inst,
    input  wire        in_pred,
    input  wire [`XLEN-1:0] in_target,
    input  wire        pop,
    output wire        out_valid,
    output wire [`XLEN-1:0] out_pc,
    output wire [`XLEN-1:0] out_inst,
    output wire        out_pred,
    output wire [`XLEN-1:0] out_target,
    output wire [CW-1:0] count,
    output wire [CW-1:0] free_slots
);

    localparam PW = (DEPTH > 1) ? $clog2(DEPTH) : 1;
    localparam [CW-1:0] DEPTH_C = DEPTH;

    reg [`XLEN-1:0] pc_mem   [0:DEPTH-1];
    reg [`XLEN-1:0] inst_mem [0:DEPTH-1];
    reg             pred_mem [0:DEPTH-1];
    reg [`XLEN-1:0] target_mem [0:DEPTH-1];
    reg [PW-1:0] head;
    reg [PW-1:0] tail;
    reg [CW-1:0]   cnt;

    wire full  = (cnt == DEPTH_C);
    wire empty = (cnt == {CW{1'b0}});

    wire do_push = push & ~flush & ~full;
    wire do_pop  = pop  & ~flush & ~empty;

    wire [PW-1:0] head_next = (head == DEPTH-1) ? {PW{1'b0}} : (head + 1'b1);
    wire [PW-1:0] tail_next = (tail == DEPTH-1) ? {PW{1'b0}} : (tail + 1'b1);

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            head <= {PW{1'b0}};
            tail <= {PW{1'b0}};
            cnt  <= {CW{1'b0}};
        end else if (flush) begin
            head <= {PW{1'b0}};
            tail <= {PW{1'b0}};
            cnt  <= {CW{1'b0}};
        end else begin
            if (do_push) tail <= tail_next;
            if (do_pop)  head <= head_next;
            if (do_push && !do_pop)      cnt <= cnt + 1'b1;
            else if (!do_push && do_pop) cnt <= cnt - 1'b1;
        end
    end

    always @(posedge clk) begin
        if (do_push) begin
            pc_mem[tail]   <= in_pc;
            inst_mem[tail] <= in_inst;
            pred_mem[tail]   <= in_pred;
            target_mem[tail] <= in_target;
        end
    end

    assign out_valid  = ~empty;
    assign out_pc     = empty ? {`XLEN{1'b0}} : pc_mem[head];
    assign out_inst   = empty ? {`XLEN{1'b0}} : inst_mem[head];
    assign out_pred   = empty ? 1'b0 : pred_mem[head];
    assign out_target = empty ? {`XLEN{1'b0}} : target_mem[head];
    assign count      = cnt;
    assign free_slots = DEPTH_C - cnt;

endmodule