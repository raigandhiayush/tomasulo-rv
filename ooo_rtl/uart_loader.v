`timescale 1ns/1ps
// uart_loader.v - UART boot loader: writes a new program (code and data) into instruction
// and data memory, so the program can change without a new bitstream.
//
// top_fpga_ooo enables it (active = 1) when BTNC is held while CPU_RESET is released.
// The core stays in reset; this module owns the UART and the memory write ports until a
// whole program has arrived and its checksum matches, then raises loaded and the core
// starts at pc 0. A bad frame is answered with ERR and the core stays held, so a broken
// transfer never runs; send the frame again.
//
// Frame (host -> board), all multi-byte fields little-endian:
//   "TRV1"           magic; bytes before it are ignored
//   NI               2 bytes, code words, 1..1024
//   ND               2 bytes, data words, 0..1024
//   code[0..NI-1]    4 bytes each, written to imem[0..NI-1]
//   data[0..ND-1]    4 bytes each, written to dmem[0..ND-1] (address 0x1000 + 4*i for C,
//                    data_mem decodes address bits [11:2])
//   checksum         4 bytes, (NI + ND + every code and data word) mod 2^32
// Then imem[NI..1023] and dmem[ND..1023] are set to 0, so both memories match the image
// exactly (a C program's .bss starts at zero).
// Replies (board -> host): "BOOT\r\n" on entry, then "OK\r\n" or "ERR\r\n".
// tools/boot_frame.py builds frames; tb_uart_loader checks this module through the pins.
module uart_loader (
    input  wire        clk,
    input  wire        reset_n,     // active low, asynchronous
    input  wire        active,      // 1: loader owns the UART and the memory write ports
    // UART receive FIFO (rx_data is the oldest byte while rx_valid = 1)
    input  wire        rx_valid,
    input  wire [ 7:0] rx_data,
    output wire        rx_pop,
    // UART transmit FIFO
    input  wire        tx_ready,
    output wire        tx_push,
    output wire [ 7:0] tx_data,
    // instruction memory write port
    output reg         imem_we,
    output reg  [ 9:0] imem_waddr,
    output reg  [31:0] imem_wdata,
    // data memory write port (whole words)
    output reg         dmem_we,
    output reg  [ 9:0] dmem_waddr,
    output reg  [31:0] dmem_wdata,
    output wire        loaded       // program written and checked: start the core
);
    localparam [3:0] S_IDLE = 4'd0, S_TX = 4'd1, S_MAGIC = 4'd2, S_LEN = 4'd3,
                     S_CODE = 4'd4, S_DATA = 4'd5, S_SUM = 4'd6, S_ZERO = 4'd7,
                     S_DONE = 4'd8;
    // message ROM: BOOT\r\n at 0..5, OK\r\n at 6..9, ERR\r\n at 10..14
    localparam [3:0] M_BOOT = 4'd0, M_BOOT_END = 4'd6, M_OK = 4'd6, M_OK_END = 4'd10,
                     M_ERR = 4'd10, M_ERR_END = 4'd15;

    function [7:0] msg_char(input [3:0] i);
        case (i)
            4'd0:  msg_char = "B";  4'd1:  msg_char = "O";  4'd2:  msg_char = "O";
            4'd3:  msg_char = "T";  4'd4:  msg_char = 8'h0D; 4'd5:  msg_char = 8'h0A;
            4'd6:  msg_char = "O";  4'd7:  msg_char = "K";  4'd8:  msg_char = 8'h0D;
            4'd9:  msg_char = 8'h0A;
            4'd10: msg_char = "E";  4'd11: msg_char = "R";  4'd12: msg_char = "R";
            4'd13: msg_char = 8'h0D; 4'd14: msg_char = 8'h0A;
            default: msg_char = 8'h00;
        endcase
    endfunction

    function [7:0] magic_char(input [1:0] i);
        case (i)
            2'd0: magic_char = "T"; 2'd1: magic_char = "R";
            2'd2: magic_char = "V"; default: magic_char = "1";
        endcase
    endfunction

    reg [3:0]  state, tx_next;
    reg [3:0]  ptr, ptr_end;        // message being sent
    reg [1:0]  midx;                // magic bytes matched so far
    reg [1:0]  bcnt;                // bytes of the current field
    reg [10:0] ncode, ndata;        // NI 1..1024, ND 0..1024
    reg [10:0] addr;                // next word to write / zero, 0..1024
    reg [31:0] wbuf;                // little-endian assembly: new byte enters at the top
    reg [31:0] sum;

    wire rx_state = (state == S_MAGIC) || (state == S_LEN) || (state == S_CODE) ||
                    (state == S_DATA)  || (state == S_SUM);
    wire take     = active && rx_state && rx_valid;     // consume rx_data this cycle
    wire [7:0]  b    = rx_data;
    wire [31:0] word = {b, wbuf[31:8]};                 // the full field when bcnt == 3
    // in S_LEN, word = {ND_hi, ND_lo, NI_hi, NI_lo} when bcnt == 3
    wire [15:0] ni16 = word[15:0], nd16 = word[31:16];
    wire        len_ok = (ni16 != 16'd0) && (ni16 <= 16'd1024) && (nd16 <= 16'd1024);

    assign rx_pop  = take;
    assign tx_push = active && (state == S_TX) && tx_ready;
    assign tx_data = msg_char(ptr);
    assign loaded  = active && (state == S_DONE);

    task send_msg(input [3:0] first, input [3:0] last_plus1, input [3:0] then_state);
        begin
            ptr <= first; ptr_end <= last_plus1; tx_next <= then_state; state <= S_TX;
        end
    endtask

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state <= S_IDLE; tx_next <= S_IDLE; ptr <= 4'd0; ptr_end <= 4'd0;
            midx <= 2'd0; bcnt <= 2'd0; ncode <= 11'd0; ndata <= 11'd0; addr <= 11'd0;
            wbuf <= 32'd0; sum <= 32'd0;
            imem_we <= 1'b0; imem_waddr <= 10'd0; imem_wdata <= 32'd0;
            dmem_we <= 1'b0; dmem_waddr <= 10'd0; dmem_wdata <= 32'd0;
        end else begin
            imem_we <= 1'b0;
            dmem_we <= 1'b0;
            if (active) case (state)
                S_IDLE: send_msg(M_BOOT, M_BOOT_END, S_MAGIC);

                S_TX: if (tx_ready) begin
                    if (ptr + 4'd1 == ptr_end) state <= tx_next;
                    ptr <= ptr + 4'd1;
                end

                S_MAGIC: if (take) begin
                    if (b == magic_char(midx)) begin
                        midx <= midx + 2'd1;
                        if (midx == 2'd3) begin state <= S_LEN; bcnt <= 2'd0; end
                    end else
                        midx <= (b == magic_char(2'd0)) ? 2'd1 : 2'd0;
                end

                S_LEN: if (take) begin
                    wbuf <= word; bcnt <= bcnt + 2'd1;
                    if (bcnt == 2'd3) begin
                        if (len_ok) begin
                            ncode <= ni16[10:0]; ndata <= nd16[10:0];
                            sum <= {16'd0, ni16} + {16'd0, nd16}; addr <= 11'd0;
                            state <= S_CODE;
                        end else begin
                            midx <= 2'd0; send_msg(M_ERR, M_ERR_END, S_MAGIC);
                        end
                    end
                end

                S_CODE: if (take) begin
                    wbuf <= word; bcnt <= bcnt + 2'd1;
                    if (bcnt == 2'd3) begin
                        imem_we <= 1'b1; imem_waddr <= addr[9:0]; imem_wdata <= word;
                        sum <= sum + word;
                        if (addr + 11'd1 == ncode) begin
                            addr <= 11'd0;
                            state <= (ndata == 11'd0) ? S_SUM : S_DATA;
                        end else
                            addr <= addr + 11'd1;
                    end
                end

                S_DATA: if (take) begin
                    wbuf <= word; bcnt <= bcnt + 2'd1;
                    if (bcnt == 2'd3) begin
                        dmem_we <= 1'b1; dmem_waddr <= addr[9:0]; dmem_wdata <= word;
                        sum <= sum + word;
                        if (addr + 11'd1 == ndata) state <= S_SUM;
                        addr <= addr + 11'd1;
                    end
                end

                S_SUM: if (take) begin
                    wbuf <= word; bcnt <= bcnt + 2'd1;
                    if (bcnt == 2'd3) begin
                        midx <= 2'd0; addr <= 11'd0;
                        if (word == sum) state <= S_ZERO;
                        else send_msg(M_ERR, M_ERR_END, S_MAGIC);
                    end
                end

                // one pass over 0..1023: zero imem above the code and dmem above the data
                S_ZERO: if (addr == 11'd1024) send_msg(M_OK, M_OK_END, S_DONE);
                    else begin
                        imem_we <= (addr >= ncode); imem_waddr <= addr[9:0]; imem_wdata <= 32'd0;
                        dmem_we <= (addr >= ndata); dmem_waddr <= addr[9:0]; dmem_wdata <= 32'd0;
                        addr <= addr + 11'd1;
                    end

                S_DONE: ;   // stays until the next reset
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
