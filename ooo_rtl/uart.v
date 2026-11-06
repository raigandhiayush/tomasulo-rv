`timescale 1ns/1ps
// uart.v - UART for terminal input and output (8 data bits, no parity, 1 stop bit)
//
// CLK_DIV = clock cycles per bit: 50 MHz / 115200 = 434 (0.006 % fast).
// Receive: a two-flip-flop synchronizer, then a falling edge starts a frame. The
// line is checked again half a bit later (a shorter glitch is ignored), each data
// bit is sampled in its middle, and a frame with a low stop bit is dropped.
// Good bytes go into a FIFO; if it is full the byte is lost and rx_overflow stays
// set until reset. Transmit: a FIFO in front of a shifter. Bytes pushed while
// tx_ready = 0 are lost, so software checks tx_ready first.
//
// rx_data is the oldest byte while rx_valid = 1; rx_pop removes it.
// reset_n: active low, asynchronous.
`include "ooo_defs.vh"

module uart #(
    parameter CLK_DIV = `UART_DIV,
    parameter FIFO_N  = `UART_FIFO_N
) (
    input  wire         clk,
    input  wire         reset_n,
    input  wire         rx,
    output reg          tx,
    output wire         rx_valid,
    output wire [7:0]   rx_data,
    input  wire         rx_pop,
    output reg          rx_overflow,
    output wire         tx_ready,
    input  wire         tx_push,
    input  wire [7:0]   tx_data,
    output wire         tx_idle                 // nothing queued or being sent
);
    localparam PW = $clog2(FIFO_N);
    localparam DW = $clog2(CLK_DIV + 1);
    localparam [DW-1:0] DIV_C = CLK_DIV;

    // ---- receive ------------------------------------------------------------------
    reg              rx_m, rx_s;
    reg              r_busy, r_start;
    reg  [3:0]       r_bit;
    reg  [DW-1:0]    r_cnt;
    reg  [7:0]       r_shift;
    reg  [7:0]       r_mem [0:FIFO_N-1];
    reg  [PW-1:0]    r_head, r_tail;
    reg  [PW:0]      r_count;

    assign rx_valid = (r_count != 0);
    assign rx_data  = r_mem[r_head];

    wire r_done = r_busy && !r_start && r_cnt == 0 && r_bit == 8;   // stop bit sample
    wire r_good = r_done && rx_s;
    wire r_full = (r_count == FIFO_N);
    wire r_push = r_good && !r_full;
    wire r_pop  = rx_pop && rx_valid;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            rx_m <= 1'b1; rx_s <= 1'b1;
            r_busy <= 1'b0; r_start <= 1'b0; r_bit <= 4'd0; r_cnt <= 0; r_shift <= 8'd0;
            r_head <= 0; r_tail <= 0; r_count <= 0;
            rx_overflow <= 1'b0;
        end else begin
            rx_m <= rx;
            rx_s <= rx_m;
            if (!r_busy) begin
                if (!rx_s) begin
                    r_busy <= 1'b1; r_start <= 1'b1; r_bit <= 4'd0;
                    r_cnt <= DIV_C / 2 - 1;
                end
            end else if (r_cnt != 0)
                r_cnt <= r_cnt - 1'b1;
            else if (r_start) begin
                if (rx_s) r_busy <= 1'b0;               // glitch: not a start bit
                r_start <= 1'b0;
                r_cnt   <= DIV_C - 1;
            end else if (r_bit == 8)
                r_busy <= 1'b0;
            else begin
                r_shift <= {rx_s, r_shift[7:1]};
                r_bit   <= r_bit + 1'b1;
                r_cnt   <= DIV_C - 1;
            end

            if (r_push) begin
                r_mem[r_tail] <= r_shift;
                r_tail <= r_tail + 1'b1;
            end
            if (r_good && r_full) rx_overflow <= 1'b1;
            if (r_pop) r_head <= r_head + 1'b1;
            if (r_push && !r_pop)      r_count <= r_count + 1'b1;
            else if (!r_push && r_pop) r_count <= r_count - 1'b1;
        end
    end

    // ---- transmit -----------------------------------------------------------------
    reg  [7:0]       t_mem [0:FIFO_N-1];
    reg  [PW-1:0]    t_head, t_tail;
    reg  [PW:0]      t_count;
    reg              t_busy;
    reg  [3:0]       t_left;                    // bits left to send after this one
    reg  [DW-1:0]    t_cnt;
    reg  [8:0]       t_shift;

    assign tx_ready = (t_count != FIFO_N);
    assign tx_idle  = (t_count == 0) && !t_busy;

    wire t_push = tx_push && tx_ready;
    wire t_load = !t_busy && t_count != 0;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            tx <= 1'b1;
            t_head <= 0; t_tail <= 0; t_count <= 0;
            t_busy <= 1'b0; t_left <= 4'd0; t_cnt <= 0; t_shift <= 9'h1FF;
        end else begin
            if (t_push) begin
                t_mem[t_tail] <= tx_data;
                t_tail <= t_tail + 1'b1;
            end
            if (t_load) t_head <= t_head + 1'b1;
            if (t_push && !t_load)      t_count <= t_count + 1'b1;
            else if (!t_push && t_load) t_count <= t_count - 1'b1;

            if (t_load) begin
                t_busy  <= 1'b1;
                tx      <= 1'b0;                    // start bit
                t_shift <= {1'b1, t_mem[t_head]};   // stop bit above the data
                t_left  <= 4'd9;
                t_cnt   <= DIV_C - 1;
            end else if (t_busy) begin
                if (t_cnt != 0)
                    t_cnt <= t_cnt - 1'b1;
                else if (t_left != 0) begin
                    tx      <= t_shift[0];
                    t_shift <= {1'b1, t_shift[8:1]};
                    t_left  <= t_left - 1'b1;
                    t_cnt   <= DIV_C - 1;
                end else
                    t_busy <= 1'b0;
            end
        end
    end
endmodule
