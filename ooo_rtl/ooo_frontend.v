`timescale 1ns/1ps
`include "ooo_defs.vh"
module ooo_frontend #(
      parameter [`XLEN-1:0] RESET = `RESET_PC
      )
      (
      input clk,
      input reset_n,
      input [`XLEN-1:0] imem_data,
      output [`XLEN-1:0] imem_addr,
      input redirect_valid,
      input [`XLEN-1:0] redirect_pc,
      input hold_set,
      input br_valid,
      input br_taken,
      input [`XLEN-1:0] br_target,
      input fq_pop,
      output fq_valid,
      output [`XLEN-1:0] fq_pc,
      output [`XLEN-1:0] fq_inst,
      output reg hold
);
      localparam IQ_CW = $clog2(`IQ_DEPTH + 1);   // instr_queue count width
      reg [`XLEN-1:0] fetch_pc;
      reg fetch_pending;
      reg [`XLEN-1:0] pend_pc;
      wire [IQ_CW-1:0] free_slots;
      wire push, can_fetch;
      wire redirect;
      wire[`XLEN-1:0] new_pc;

      instr_queue #(.DEPTH(`IQ_DEPTH)) queue(
            .clk(clk),
            .reset_n(reset_n),
            .flush(redirect),
            .push(push),
            .in_pc(pend_pc),
            .in_inst(imem_data),
            .pop(fq_pop),
            .out_valid(fq_valid),
            .out_pc(fq_pc),
            .out_inst(fq_inst),
            .count(),
            .free_slots(free_slots)
      );

      assign can_fetch=(free_slots>fetch_pending);
      assign push=fetch_pending&(~redirect);
      assign imem_addr=fetch_pc;
      assign redirect=redirect_valid|(br_valid&br_taken);
      assign new_pc=(br_valid&br_taken)? br_target:redirect_pc;

      // assign hold=1'b0;
      always @(posedge clk or negedge reset_n)
      begin
            if(!reset_n)
            begin
                  fetch_pc<=RESET;
                  fetch_pending<=1'b0;
                  pend_pc<={`XLEN{1'b0}};
            end
            else if(redirect)
            begin

                  fetch_pending<=1'b0;
                  fetch_pc<=new_pc;

            end
            else if(can_fetch)
            begin
                  fetch_pending<=1'b1;
                  pend_pc<=fetch_pc;
                  fetch_pc<=fetch_pc+4;

            end
            else
            begin
                  fetch_pending<=0;      
            end
      end
      always @(posedge clk or negedge reset_n)
      begin
            if(!reset_n)
            begin
                  hold<=1'b0;
            end
            else if(br_valid)
            begin
                  hold<=1'b0;
            end
            else if(hold_set)
            begin
                  hold<=1'b1;
            end
      end

endmodule
