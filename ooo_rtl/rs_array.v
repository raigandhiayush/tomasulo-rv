`timescale 1ns/1ps
`include "ooo_defs.vh"
module rs_array #(
      parameter N=3
      )
      (
      input  clk,
      input  reset_n,
      input rs_al_valid,
      input [`OP_W-1:0] rs_al_op,
      input [`ROB_W-1:0] rs_al_tag,
      input rs_al_qj_valid,
      input [`ROB_W-1:0] rs_al_qj,
      input [`XLEN-1:0] rs_al_vj,
      input rs_al_qk_valid,
      input [`ROB_W-1:0] rs_al_qk,
      input [`XLEN-1:0] rs_al_vk,
      input [`XLEN-1:0] rs_al_a,
      output  rs_full,
      input [`NCDB-1:0] cdb_valid,
      input [`NCDB*`ROB_W-1:0] cdb_tag,
      input [`XLEN*`NCDB-1:0] cdb_value,
      output iss_valid,
      output [`OP_W-1:0] iss_op,
      output [`ROB_W-1:0] iss_tag,
      output [`XLEN-1:0] iss_vj,
      output [`XLEN-1:0] iss_vk,
      output [`XLEN-1:0] iss_a,
      input iss_accept
);
      localparam AW = (N > 1) ? $clog2(N) : 1;   // age / entry-index width
      reg [N-1:0] busy;
      wire [N-1:0] ready;
      reg [`OP_W-1:0] e_op [0:N-1];
      reg [`ROB_W-1:0] e_tag [0:N-1];
      reg [N-1:0] qj_valid;
      reg [`ROB_W-1:0] qj [0:N-1];
      reg [`XLEN-1:0] vj [0:N-1];
      reg [N-1:0] qk_valid;
      reg [`ROB_W-1:0] qk [0:N-1];
      reg [`XLEN-1:0] vk [0:N-1];
      reg [`XLEN-1:0] e_a [0:N-1];
      reg [AW-1:0] age [0:N-1];
      assign rs_full=&busy;
      assign ready=busy&(~qj_valid)&(~qk_valid);
      assign iss_valid=|ready;
      integer i, j, k, m;
      reg [AW-1:0] sel;
      reg [AW-1:0] free_rs;
      reg found;
      always @(*)
      begin
            sel=0;
            found=1'b0;
            for(m=0; m<N; m=m+1)
            begin
                  if(ready[m] && (!found || age[m]>age[sel]))
                  begin
                        sel=m;
                        found=1'b1;
                  end 
            end
      end
      always @(*)
      begin
            free_rs={AW{1'b0}};
            for(j=N-1; j>=0; j=j-1)
            begin
                  if(!busy[j])
                  begin
                        free_rs=j;
                  end
            end
      end
      assign iss_op=e_op[sel];
      assign iss_tag=e_tag[sel];
      assign iss_vj=vj[sel];
      assign iss_vk=vk[sel];
      assign iss_a=e_a[sel];
      always @(posedge clk or negedge reset_n)
      begin
            if(!reset_n)
            begin
                  busy<={N{1'b0}};
                  qj_valid<={N{1'b0}};
                  qk_valid<={N{1'b0}};
                  for(i=0; i<N; i=i+1)
                  begin
                        age[i]<={AW{1'b0}};
                  end
            end
            else
            begin
                  for(i=0; i<N; i=i+1)
                  begin
                        for(k=0; k<`NCDB; k=k+1)
                        begin
                              if(busy[i]&&(qj_valid[i])&&cdb_valid[k]&&(qj[i]==cdb_tag[k*`ROB_W+:`ROB_W]))
                              begin
                                    vj[i]<=cdb_value[k*`XLEN+:`XLEN];
                                    qj_valid[i]<=1'b0;
                              end
                              if(busy[i]&&(qk_valid[i])&&cdb_valid[k]&&(qk[i]==cdb_tag[k*`ROB_W+:`ROB_W]))
                              begin
                                    vk[i]<=cdb_value[k*`XLEN+:`XLEN];
                                    qk_valid[i]<=1'b0;
                              end
                        end
                  end
                  for(i=0; i<N; i=i+1)
                  begin
                        if(busy[i] && !(iss_valid && iss_accept && sel==i))
                        begin
                              age[i]<=age[i]+((rs_al_valid&&!rs_full)? 1'b1:1'b0)-((iss_valid&&iss_accept&&(age[i]>age[sel]))? 1'b1:1'b0);      
                        end
                  end
                  if(rs_al_valid & ~rs_full)
                  begin
                        busy[free_rs]<=1'b1;
                        qj_valid[free_rs]<=rs_al_qj_valid;
                        qj[free_rs]<=rs_al_qj;
                        vj[free_rs]<=rs_al_vj;
                        qk_valid[free_rs]<=rs_al_qk_valid;
                        qk[free_rs]<=rs_al_qk;
                        vk[free_rs]<=rs_al_vk;
                        e_a[free_rs]<=rs_al_a;
                        e_op[free_rs]<=rs_al_op;
                        e_tag[free_rs]<=rs_al_tag;
                        age[free_rs]<={AW{1'b0}};
                  end
                  if(iss_valid && iss_accept)
                  begin
                        busy[sel]<=1'b0;
                  end
            end
      end
endmodule
