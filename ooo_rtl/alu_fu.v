`timescale 1ns/1ps
`include "ooo_defs.vh"
module alu_fu(
      input [`OP_W-1:0] op,
      input [`XLEN-1:0] vj,
      input [`XLEN-1:0] vk,
      input [`XLEN-1:0] a,
      output reg [`XLEN-1:0] result,
      output reg is_ctrl,
      output reg taken,
      output reg [`XLEN-1:0] target
);
localparam [`XLEN-1:0] ZERO = 0, ONE = 1;
wire [`F3_W-1:0] f3;
wire alt, is_branch, is_jalr;
assign f3=op[`OP_F3_HI:`OP_F3_LO];
assign alt=op[`OP_ALT_BIT];
assign is_branch=op[`OP_BR_BIT];
assign is_jalr=op[`OP_JALR_BIT];
always @(*)
begin
      is_ctrl = 1'b0;
      taken = 1'b0;
      target = ZERO;
      result = ZERO;
      if(is_jalr)
      begin
            result=vk;
            target=(vj+a)&(~ONE);
            taken=1'b1;
            is_ctrl=1'b1;
      end
      else if(is_branch)
      begin
            case(f3)
                  3'b000: taken=(vj==vk)? 1'b1:1'b0; //BEQ
                  3'b001: taken=(vj!=vk)? 1'b1:1'b0; //BNE
                  3'b100: taken=($signed(vj)<$signed(vk))? 1'b1:1'b0; //BLT
                  3'b101: taken=($signed(vj)>=$signed(vk))? 1'b1:1'b0; //BGE
                  3'b110: taken=(vj<vk)? 1'b1:1'b0; //BLTU
                  3'b111: taken=(vj>=vk)? 1'b1:1'b0; //BGEU
            endcase
            target=a;
            is_ctrl=1'b1;
      end
      else
      begin
            taken=1'b0;
            target=0;
            is_ctrl=1'b0;
            case(f3)
                  3'b000: result=alt? vj-vk:vj+vk; //ADD/SUB
                  3'b001: result=vj<<vk[4:0]; //SLL
                  3'b010: result=($signed(vj)<$signed(vk))? ONE:ZERO; //SLT
                  3'b011: result=(vj<vk)? ONE:ZERO; //SLTU
                  3'b100: result=vj^vk; //XOR
                  3'b101:
                        if(alt)
                        begin
                              result=$signed(vj)>>>vk[4:0]; //SRA
                        end
                        else
                        begin
                              result=vj>>vk[4:0]; //SRL
                        end
                  3'b110: result=vj|vk; //OR
                  3'b111: result=vj&vk; //AND
                  default: result = ZERO;
            endcase
      end

end

endmodule
