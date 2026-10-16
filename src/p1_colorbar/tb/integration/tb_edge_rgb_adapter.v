// edge_rgb_adapter 四态自检 testbench
//
// 测试图：低对比度竖直条纹（灰度 20 / 35 交替，每 8 列一个边界，共 W=64 列）
//   - 边界处 Sobel |Gx| = 4*15 = 60
//   - 官方固定阈值 80  -> 60 < 80，理应【全部漏检】
//   - 我们自适应阈值    -> mag=60 >= thr(~17)，理应【全部检出】
//   => 该图能一眼分辨两种判决机制，正好用来验证四态切换是否生效
//
// 判据：
//   mode0 原图   : 输出应为输入原样（出现灰度 20/35，不是纯黑白）
//   mode1 官方   : 边缘数 = 0（全漏检）
//   mode2 我们   : 边缘数 > 0
//   mode3 分屏   : 左半屏边缘数 = 0（官方），右半屏边缘数 > 0（我们）
`timescale 1ns/1ps
module tb_edge_rgb_adapter;

    parameter W  = 64;
    parameter H  = 8;
    parameter H0 = 260;             // 有效区起始 hcnt

    reg         clk = 1'b0;
    reg         rst_n = 1'b0;
    reg         i_de = 1'b0;
    reg         i_vs = 1'b0;
    reg  [11:0] i_hcnt = 12'd0;
    reg  [23:0] i_rgb = 24'd0;
    reg  [1:0]  i_mode = 2'd0;
    reg  [1:0]  i_k = 2'd2;
    wire        o_de, o_vs;
    wire [23:0] o_rgb;

    edge_rgb_adapter #(.IMG_WIDTH(W)) dut (
        .I_clk   ( clk    ),
        .I_rst_n ( rst_n  ),
        .I_de    ( i_de   ),
        .I_vs    ( i_vs   ),
        .I_hcnt  ( i_hcnt ),
        .I_rgb   ( i_rgb  ),
        .I_mode  ( i_mode ),
        .I_k     ( i_k    ),
        .O_de    ( o_de   ),
        .O_vs    ( o_vs   ),
        .O_rgb   ( o_rgb  )
    );

    always #6.734 clk = ~clk;       // 74.25MHz

    // 低对比度条纹：每 8 列交替 20 / 35（灰度三通道相同）
    function [23:0] test_rgb(input integer col);
        begin
            if (((col / 8) % 2) == 0) test_rgb = {8'd20, 8'd20, 8'd20};
            else                      test_rgb = {8'd35, 8'd35, 8'd35};
        end
    endfunction

    // ---- 统计 ----
    integer e_cnt, el_cnt, er_cnt, col_cnt, nonbw_cnt;
    integer m1_e, m2_e, m3_l, m3_r, m0_nonbw;

    always @(posedge clk) begin
        if (o_de) begin
            if (o_rgb === 24'hFFFFFF) begin
                e_cnt = e_cnt + 1;
                if (col_cnt < (W / 2)) el_cnt = el_cnt + 1;
                else                   er_cnt = er_cnt + 1;
            end
            if (o_rgb !== 24'h000000 && o_rgb !== 24'hFFFFFF) nonbw_cnt = nonbw_cnt + 1;
            col_cnt = col_cnt + 1;
            if (col_cnt >= W) col_cnt = 0;
        end
    end

    // ---- 送一帧（指定模式）----
    task send_frame(input [1:0] mode);
        integer r, c;
        begin
            i_mode  = mode;
            e_cnt   = 0;
            el_cnt  = 0;
            er_cnt  = 0;
            col_cnt = 0;
            nonbw_cnt = 0;
            for (r = 0; r < H; r = r + 1) begin
                for (c = 0; c < (H0 + W + 4); c = c + 1) begin
                    @(posedge clk);
                    i_hcnt <= c[11:0];
                    i_de   <= (c >= H0 && c < H0 + W);
                    i_rgb  <= (c >= H0 && c < H0 + W) ? test_rgb(c - H0) : 24'h000000;
                    i_vs   <= (r == 0 && c == 0);
                end
            end
            @(posedge clk);
            i_de <= 1'b0;
            i_vs <= 1'b0;
            repeat (20) @(posedge clk);
        end
    endtask

    initial begin
        repeat (10) @(posedge clk);
        rst_n = 1'b1;
        repeat (5) @(posedge clk);

        send_frame(2'd0);
        m0_nonbw = nonbw_cnt;

        send_frame(2'd1);
        m1_e = e_cnt;

        send_frame(2'd2);
        m2_e = e_cnt;

        send_frame(2'd3);
        m3_l = el_cnt;
        m3_r = er_cnt;

        $display("---- TB RESULT ----");
        $display("mode0 (raw)     : non-BW pixels = %0d   (expect > 0: raw keeps gray levels)", m0_nonbw);
        $display("mode1 (official): edges = %0d   (expect 0: thr 80 > mag 60, all missed)", m1_e);
        $display("mode2 (ours)    : edges = %0d   (expect > 0: adaptive thr detects)", m2_e);
        $display("mode3 (split)   : left(official) = %0d, right(ours) = %0d   (expect 0 and > 0)", m3_l, m3_r);

        if (m0_nonbw > 0 && m1_e == 0 && m2_e > 0 && m3_l == 0 && m3_r > 0)
            $display("VERDICT: PASS");
        else
            $display("VERDICT: FAIL");
        $finish;
    end

endmodule
