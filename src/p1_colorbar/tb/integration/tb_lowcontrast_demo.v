// 端到端自检：TPG 低对比度图案 -> edge_rgb_adapter 四态
//
// 验证目标（这是上板演示的核心场景）：
//   低对比度图案 4（中灰 26/38，Sobel 幅值 48）下
//     - mode1 官方固定阈值(80)：48 < 80 -> 应【全部漏检】，边缘数 = 0
//     - mode2 我们的自适应阈值   ：48 >= thr(~18) -> 应【全部检出】，边缘数 > 0
//   这证明分屏对比时左右两边视觉上确实不同（否则演示无意义）
`timescale 1ns/1ps
module tb_lowcontrast_demo;

    parameter W  = 128;             // 需跨过 lc_phase(lx[6]) 的翻转点，图案才有边界
    parameter H  = 8;
    parameter H0 = 260;             // 有效区起始 hcnt
    parameter V0 = 25;              // 有效区起始 vcnt
    parameter PAT = 3'd4;           // 低对比度·中灰

    reg         clk = 1'b0;
    reg         rst_n = 1'b0;
    reg         t_de = 1'b0;
    reg  [11:0] t_hcnt = 12'd0;
    reg  [11:0] t_vcnt = 12'd0;
    reg  [2:0]  t_pat = PAT;
    reg         t_lock = 1'b1;
    wire [23:0] t_rgb;

    reg  [1:0]  a_mode = 2'd0;
    wire        a_de, a_vs;
    wire [23:0] a_rgb;

    test_pattern_gen u_tpg (
        .I_clk         ( clk    ),
        .I_rst_n       ( rst_n  ),
        .I_de          ( t_de   ),
        .I_hcnt        ( t_hcnt ),
        .I_vcnt        ( t_vcnt ),
        .I_pattern_sel ( t_pat  ),
        .I_pll_lock    ( t_lock ),
        .O_rgb         ( t_rgb  )
    );

    edge_rgb_adapter #(.IMG_WIDTH(W)) u_adapter (
        .I_clk   ( clk    ),
        .I_rst_n ( rst_n  ),
        .I_de    ( t_de   ),
        .I_vs    ( 1'b0   ),
        .I_hcnt  ( t_hcnt ),
        .I_rgb   ( t_rgb  ),
        .I_mode  ( a_mode ),
        .I_k     ( 2'd2   ),
        .O_de    ( a_de   ),
        .O_vs    ( a_vs   ),
        .O_rgb   ( a_rgb  )
    );

    always #6.734 clk = ~clk;

    // 诊断：打印送入算法的前若干像素
    integer g_n = 0;
    always @(posedge clk) begin
        if (t_de && g_n < 16) begin
            $display("  in: hcnt=%0d lx=%0d tpg_rgb=%h gray=%0d", t_hcnt, u_tpg.lx, t_rgb, u_adapter.S_gray);
            g_n = g_n + 1;
        end
    end

    // 统计
    integer e_cnt, m1_e, m2_e, m0_gray_kept;
    integer dbg_row = 0, dbg_col = 0, dbg_n = 0;
    integer dbg_mag_min = 9999, dbg_mag_max = 0, dbg_mag_sum = 0, dbg_mag_cnt = 0;
    always @(posedge clk) begin
        if (a_de) begin
            if (a_rgb === 24'hFFFFFF) begin
                e_cnt = e_cnt + 1;
                if (dbg_n < 20) begin
                    $display("  edge at out_row=%0d out_col=%0d mode=%0d mag=%0d", dbg_row, dbg_col, a_mode, u_adapter.S_mag);
                    dbg_n = dbg_n + 1;
                end
            end
            if (a_mode == 2'd0 && a_rgb !== 24'hFFFFFF && a_rgb !== 24'h000000)
                m0_gray_kept = m0_gray_kept + 1;
            // 记录 mag 范围（诊断用）
            if (u_adapter.S_mag < dbg_mag_min) dbg_mag_min = u_adapter.S_mag;
            if (u_adapter.S_mag > dbg_mag_max) dbg_mag_max = u_adapter.S_mag;
            dbg_mag_sum = dbg_mag_sum + u_adapter.S_mag;
            dbg_mag_cnt = dbg_mag_cnt + 1;

            dbg_col = dbg_col + 1;
            if (dbg_col >= W) begin
                dbg_col = 0;
                dbg_row = dbg_row + 1;
                if (dbg_row >= H) dbg_row = 0;
            end
        end
    end

    integer r, c;
    task send_frame(input [1:0] mode);
        begin
            a_mode = mode;
            e_cnt = 0;
            for (r = 0; r < H; r = r + 1) begin
                for (c = 0; c < (H0 + W + 4); c = c + 1) begin
                    @(posedge clk);
                    t_hcnt <= c[11:0];
                    t_vcnt <= (V0 + r);
                    t_de   <= (c >= H0 && c < H0 + W);
                end
            end
            @(posedge clk);
            t_de <= 1'b0;
            repeat (20) @(posedge clk);
        end
    endtask

    initial begin
        repeat (10) @(posedge clk);
        rst_n = 1'b1;
        repeat (5) @(posedge clk);

        m0_gray_kept = 0;
        send_frame(2'd0);
        $display("mode0 (raw)     : gray pixels kept = %0d  (expect > 0)", m0_gray_kept);

        send_frame(2'd1);
        m1_e = e_cnt;
        $display("mag range in mode1: min=%0d max=%0d avg=%0d (samples=%0d)",
                 dbg_mag_min, dbg_mag_max, dbg_mag_sum / (dbg_mag_cnt > 0 ? dbg_mag_cnt : 1), dbg_mag_cnt);

        send_frame(2'd2);
        m2_e = e_cnt;

        $display("---- TB RESULT (pattern=%0d, low contrast) ----", PAT);
        $display("mode1 (official thr=80) : edges = %0d  (expect 0)", m1_e);
        $display("mode2 (ours adaptive)   : edges = %0d  (expect > 0)", m2_e);

        if (m1_e == 0 && m2_e > 0)
            $display("VERDICT: PASS  (分屏对比能看出差异)");
        else
            $display("VERDICT: FAIL");
        $finish;
    end

endmodule
