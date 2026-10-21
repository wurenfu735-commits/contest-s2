// ????????? ? ?????? testbench
// ??????????(gray_*.txt) -> ???? DUT -> ??????(rtl_out.txt)
//       -> ? Python ?? align_compare.py ???????????
//
// ?????????????????????? + ?????
//       ???????????????????????
`timescale 1ns/1ps
module tb_edge_adaptive_pixel;

    parameter IMG_W     = 1280;
    parameter IMG_H     = 720;
    parameter TOTAL     = IMG_W * IMG_H;
    parameter K_VAL     = 2;
    parameter FLOOR_VAL = 16;

    reg        clk     = 1'b0;
    reg        rst_n   = 1'b0;
    reg        i_valid = 1'b0;
    reg        i_sync  = 1'b0;
    reg  [7:0] i_gray  = 8'd0;
    reg  [1:0] i_k     = K_VAL;
    wire       o_valid;
    wire       o_edge;

    reg  [7:0] gray_mem [0:TOTAL-1];
    reg        exp_mem  [0:TOTAL-1];

    integer    fout;
    integer    out_cnt = 0;

    edge_adaptive_pixel #(
        .IMG_WIDTH (IMG_W),
        .THR_FLOOR (FLOOR_VAL)
    ) dut (
        .I_clk   (clk),
        .I_rst_n (rst_n),
        .I_valid (i_valid),
        .I_sync  (i_sync),
        .I_gray  (i_gray),
        .I_k     (i_k),
        .O_valid (o_valid),
        .O_edge  (o_edge)
    );

    always #6.734 clk = ~clk;          // 74.25MHz

    // ???????edge + ????(mag/thr????? edge ??)???????
    reg [11:0] mag_d1;
    reg [12:0] thr_d1;
    always @(posedge clk) begin
        mag_d1 <= dut.mag;
        thr_d1 <= dut.thr_high;
    end

    initial fout = $fopen("rtl_out.txt", "w");
    always @(posedge clk) begin
        if (o_valid) begin
            $fwrite(fout, "%0d %0d %0d\n", o_edge, mag_d1, thr_d1);
            out_cnt = out_cnt + 1;

            if (o_edge !== 1'b0 && o_edge !== 1'b1) begin
                $display("!! X at out[%0d] t=%0t | row_cnt=%0d col_cnt=%0d", out_cnt - 1, $time, dut.row_cnt, dut.ram_addr);
            end
        end
    end

    integer r, c;
    // ???? 16 ?? 12 ????????????? 1 ????????
    integer out_dbg = 0;
    always @(posedge clk) begin
        if (o_valid) begin
            out_dbg = out_dbg + 1;
            if (out_dbg >= (16*IMG_W + 1) && out_dbg <= (16*IMG_W + 12)) begin
                $display("OUT#%0d edge=%b | col=%0d row=%0d win=%b mag=%0d thr_h=%0d o_prev=%b eb_c=%b eb_r=%b",
                         out_dbg, o_edge, dut.ram_addr, dut.row_cnt, dut.win_valid,
                         dut.mag, dut.thr_high, dut.O_edge, dut.eb_rd, dut.eb_rd);
            end
        end
    end

    initial begin
        $readmemh("gray_checker.txt", gray_mem);
        $readmemh("edge_checker.txt", exp_mem);
        $display("vectors loaded: %0d x %0d = %0d pixels", IMG_W, IMG_H, TOTAL);

        // ??
        repeat (10) @(posedge clk);
        rst_n = 1'b1;
        repeat (5) @(posedge clk);

        // ?????????? i_sync ???
        for (r = 0; r < IMG_H; r = r + 1) begin
            for (c = 0; c < IMG_W; c = c + 1) begin
                @(posedge clk);
                i_valid <= 1'b1;
                i_sync  <= (c == 0);
                i_gray  <= gray_mem[(r * IMG_W) + c];
            end
        end

        @(posedge clk);
        i_valid <= 1'b0;
        i_sync  <= 1'b0;

        // ????
        repeat (40) @(posedge clk);

        // ?????? TD ? ERAM ??????????????????????
        $display("row_cnt=%0d  final ram_addr=%0d", dut.row_cnt, dut.ram_addr);

        $fclose(fout);
        $display("---- TB DONE ----");
        $display("pixels fed : %0d", TOTAL);
        $display("pixels out : %0d", out_cnt);
        $display("output file: rtl_out.txt");
        $finish;
    end

endmodule





