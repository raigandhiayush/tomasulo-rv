`timescale 1ns/1ps
`include "ooo_defs.vh"

module mem_wait #(
    parameter WAIT   = `MEM_WAIT,
    parameter WBUF_N = `MEM_WBUF_N
) (
    input  wire              clk,
    input  wire              reset_n,
    // core side
    input  wire              re,
    input  wire [`XLEN-1:0]  raddr,
    input  wire              we,
    input  wire [`XLEN-1:0]  waddr,
    input  wire [`XLEN-1:0]  wdata,
    input  wire [3:0]        wstrb,
    output wire              read_valid,
    output wire              write_valid,
    // data_mem side
    output wire              ram_re,
    output wire [`XLEN-1:0]  ram_raddr,
    output wire              ram_we,
    output wire [`XLEN-1:0]  ram_waddr,
    output wire [`XLEN-1:0]  ram_wdata,
    output wire [3:0]        ram_wstrb
);
    generate
    if (WAIT == 0) begin : g_pass
        assign read_valid  = 1'b1;
        assign write_valid = 1'b1;
        assign ram_re      = re;
        assign ram_raddr   = raddr;
        assign ram_we      = we;
        assign ram_waddr   = waddr;
        assign ram_wdata   = wdata;
        assign ram_wstrb   = wstrb;
    end else begin : g_wait
        localparam PW = (WBUF_N > 1) ? $clog2(WBUF_N) : 1;
        localparam TW = $clog2(WAIT + 1);

        reg [`XLEN-1:0]  w_addr [0:WBUF_N-1];
        reg [`XLEN-1:0]  w_data [0:WBUF_N-1];
        reg [3:0]        w_strb [0:WBUF_N-1];
        reg [PW-1:0]     w_head, w_tail;
        reg [PW:0]       w_cnt;
        reg              rd_pend;
        reg [`XLEN-1:0]  rd_addr;
        reg [TW-1:0]     timer;
        reg              paid;              // the op at the front has paid its WAIT
        reg              last_valid;
        reg [9:0]        last_word;

        wire             has_w  = (w_cnt != 0);
        wire             has_r  = rd_pend | re;
        wire [`XLEN-1:0] r_addr = rd_pend ? rd_addr : raddr;
        wire [`XLEN-1:0] op_addr = has_w ? w_addr[w_head] : r_addr;
        wire             seq    = last_valid && op_addr[11:2] == last_word + 10'd1;
        wire             go     = (has_w | has_r) && timer == 0 && (paid || seq);
        wire             fire_w = go & has_w;
        wire             fire_r = go & ~has_w;

        assign read_valid  = ~rd_pend;
        assign write_valid = (w_cnt != WBUF_N);
        assign ram_re      = fire_r;
        assign ram_raddr   = r_addr;
        assign ram_we      = fire_w;
        assign ram_waddr   = w_addr[w_head];
        assign ram_wdata   = w_data[w_head];
        assign ram_wstrb   = w_strb[w_head];

        always @(posedge clk or negedge reset_n) begin
            if (!reset_n) begin
                w_head <= 0; w_tail <= 0; w_cnt <= 0;
                rd_pend <= 1'b0; rd_addr <= 0;
                timer <= 0; paid <= 1'b0;
                last_valid <= 1'b0; last_word <= 10'd0;
            end else begin
                if (we) begin
                    w_addr[w_tail] <= waddr;
                    w_data[w_tail] <= wdata;
                    w_strb[w_tail] <= wstrb;
                    w_tail <= (w_tail == WBUF_N-1) ? 0 : w_tail + 1'b1;
                end
                if (fire_w) w_head <= (w_head == WBUF_N-1) ? 0 : w_head + 1'b1;
                if (we && !fire_w)      w_cnt <= w_cnt + 1'b1;
                else if (!we && fire_w) w_cnt <= w_cnt - 1'b1;

                if (re && !fire_r) begin rd_pend <= 1'b1; rd_addr <= raddr; end
                else if (fire_r)   rd_pend <= 1'b0;

                if (go) begin
                    paid       <= 1'b0;
                    last_valid <= 1'b1;
                    last_word  <= op_addr[11:2];
                end else if (timer != 0) begin
                    timer <= timer - 1'b1;
                    if (timer == 1) paid <= 1'b1;
                end else if ((has_w | has_r) && !paid) begin
                    timer <= WAIT - 1;
                    if (WAIT == 1) paid <= 1'b1;
                end
            end
        end

        // synthesis translate_off
        always @(posedge clk) begin
            if (reset_n && re && rd_pend)
                $display("TEST_FAIL mem_wait protocol: read sent while read_valid = 0 (t=%0t)", $time);
            if (reset_n && we && w_cnt == WBUF_N)
                $display("TEST_FAIL mem_wait protocol: write sent to a full buffer (t=%0t)", $time);
        end
        // synthesis translate_on
    end
    endgenerate
endmodule
