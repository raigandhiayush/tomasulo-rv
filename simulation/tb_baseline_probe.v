`timescale 1ns/1ps
// tb_baseline_probe.v - Self-checking testbench for baseline pipeline execution and cycle timing.
module tb_baseline_probe;

    reg clk = 0, reset = 0;
    always #5 clk = ~clk;

    wire [31:0] imem_rdata, imem_addr, dmem_rdata, dmem_raddr, dmem_waddr, dmem_wdata;
    wire        dmem_re, dmem_we, exception;
    wire [3:0]  dmem_wstrb;

    pipe DUT (
        .clk(clk), .reset(reset), .stall(1'b0), .exception(exception), .pc_out(),
        .inst_mem_is_valid(1'b1), .inst_mem_read_data(imem_rdata), .inst_mem_address(imem_addr),
        .dmem_read_data_temp(dmem_rdata), .dmem_write_valid(1'b1), .dmem_read_valid(1'b1),
        .dmem_read_ready(dmem_re), .dmem_read_address(dmem_raddr),
        .dmem_write_ready(dmem_we), .dmem_write_address(dmem_waddr),
        .dmem_write_data(dmem_wdata), .dmem_write_byte(dmem_wstrb)
    );
    instr_mem IMEM (.clk(clk), .pc(imem_addr), .instr(imem_rdata));
    data_mem  DMEM (.clk(clk), .re(dmem_re), .raddr(dmem_raddr), .rdata(dmem_rdata),
                    .we(dmem_we), .waddr(dmem_waddr), .wdata(dmem_wdata), .wstrb(dmem_wstrb));

    localparam NSTORE = 5;
    reg [31:0] exp_data [0:NSTORE-1];
    integer cyc = 0, n_st = 0, n_pass = 0, n_fail = 0, first_cyc [0:1], exc_pulses = 0;

    always @(posedge clk) if (reset) begin
        cyc <= cyc + 1;
        if (exception) exc_pulses = exc_pulses + 1;
        if (dmem_we) begin
            $display("cycle %4d  store addr=%h data=%h (%0d) strb=%b", cyc, dmem_waddr, dmem_wdata, dmem_wdata, dmem_wstrb);
            if (dmem_wdata === exp_data[n_st % NSTORE]) n_pass = n_pass + 1;
            else begin
                n_fail = n_fail + 1;
                $display("TEST_FAIL baseline_xor store %0d: got %0d expected %0d", n_st, dmem_wdata, exp_data[n_st % NSTORE]);
            end
            if (n_st % NSTORE == 0 && n_st / NSTORE < 2) first_cyc[n_st / NSTORE] = cyc;
            n_st = n_st + 1;
        end
    end

    initial begin
        exp_data[0] = 0; exp_data[1] = 0; exp_data[2] = 10; exp_data[3] = 3; exp_data[4] = 9;
        #100 reset = 1;                      // active-low reset released, as in tb_pipeline
        repeat (200) @(posedge clk);
        #1;
        if (n_st < 2 * NSTORE) begin n_fail = n_fail + 1; $display("TEST_FAIL baseline_xor only %0d stores", n_st); end
        $display("note: baseline exception pulsed %0d times (squashed fetch of 0x00000000 after ret; F10)", exc_pulses);
        $display("stores: %0d in 200 cycles; loop period: %0d cycles for 18 instructions (CPI %0d.%02d)",
                 n_st, first_cyc[1] - first_cyc[0], (first_cyc[1] - first_cyc[0]) / 18,
                 ((first_cyc[1] - first_cyc[0]) * 100 / 18) % 100);
        if (n_fail == 0) $display("TEST_PASS baseline_xor %0d", n_pass);
        else             $display("TEST_FAIL baseline_xor %0d of %0d checks failed", n_fail, n_pass + n_fail);
        $finish;
    end

endmodule