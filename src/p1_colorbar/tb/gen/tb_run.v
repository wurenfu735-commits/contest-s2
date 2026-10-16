// ????????? ? ?????? testbench
// ??????????(gray_*.txt) -> ???? DUT -> ??????(rtl_edge_checker.txt)
//       -> ? Python ?? align_compare.py ???????????
//
// ?????????????????????? + ?????
//       ???????????????????????
`timescale 1ns/1ps
module tb_edge_adaptive_pixel;

    parameter IMG_W     = 640;
    parameter IMG_H     = 360;
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

    initial fout = $fopen("rtl_edge_checker.txt", "w");
    always @(posedge clk) begin
        if (o_valid) begin
            $fwrite(fout, "%0d %0d %0d\n", o_edge, mag_d1, thr_d1);
            out_cnt = out_cnt + 1;

            if (o_edge !== 1'b0 && o_edge !== 1'b1) begin
                $display("!! X at out[%0d] t=%0t | row_cnt=%0d wr_ptr=%0d", out_cnt - 1, $time, dut.row_cnt, dut.wr_ptr);
            end
        end
    end

    integer r, c;
    // ???????????? 2 ??? / ?????????? win_valid ????
    integer out_dbg = 0;
    always @(posedge clk) begin
        if (o_valid) begin
            out_dbg = out_dbg + 1;
            if ((out_dbg >= 1281 && out_dbg <= 1290) || (out_dbg >= 229761 && out_dbg <= 229770)) begin
                $display("OUT#%0d edge=%b | ram=%0d row=%0d win=%b mag=%0d o_prev=%b eb_d1=%b eb_d2=%b",
                         out_dbg, o_edge, dut.ram_addr, dut.row_cnt, dut.win_valid,
                         dut.mag, dut.O_edge, dut.eb_d1, dut.eb_d2);
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

        // ---- ????????????????? ----
        $display("lb1[0..7] = %h %h %h %h %h %h %h %h",
                 dut.lb1[0], dut.lb1[1], dut.lb1[2], dut.lb1[3],
                 dut.lb1[4], dut.lb1[5], dut.lb1[6], dut.lb1[7]);
        $display("lb2[0..7] = %h %h %h %h %h %h %h %h",
                 dut.lb2[0], dut.lb2[1], dut.lb2[2], dut.lb2[3],
                 dut.lb2[4], dut.lb2[5], dut.lb2[6], dut.lb2[7]);
        $display("lb2[636..639] = %h %h %h %h",
                 dut.lb2[636], dut.lb2[637], dut.lb2[638], dut.lb2[639]);
        $display("eb[0..7]  = %b %b %b %b %b %b %b %b",
                 dut.eb[0], dut.eb[1], dut.eb[2], dut.eb[3],
                 dut.eb[4], dut.eb[5], dut.eb[6], dut.eb[7]);
        $display("row_cnt=%0d  final wr_ptr=%0d", dut.row_cnt, dut.wr_ptr);

        $fclose(fout);
        $display("---- TB DONE ----");
        $display("pixels fed : %0d", TOTAL);
        $display("pixels out : %0d", out_cnt);
        $display("output file: rtl_edge_checker.txt");
        $finish;
    end

endmodule

