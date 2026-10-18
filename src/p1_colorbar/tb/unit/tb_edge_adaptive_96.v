// tb_edge_adaptive_96 —— 96bit 并行版（v5：5×5 均值 + 分段 FLOOR，暗区地板下调）与 Python 黄金模型逐像素对比
// ============================================================================
// 验证方法：并行版输出 par_out.txt（带像素编号）；黄金模型在仓库顶层 tools\gen_golden_v4.py
//   （与 RTL 同锚点/同屏蔽/同迟滞顺序）生成 golden_out.txt；
//   src\p1_colorbar\tools\run_tb_96.ps1 逐像素比对，0 误差 = PASS。
// 同 tb 内的 edge_adaptive_pixel（逐像素 RTL 第二形态）只做编译/仿真烟雾，不参与判定。
//
// 本档参数：W=128、H=12、THR_FLOOR=11'd96（分段地板基准）、I_k=2'd2、I_mode=2'd2。
//   v5 起四档偏移量由模块默认参数给（48/36/20/0 → 地板 144/132/116/96），本 tb 不覆盖，
//   与 tools/gen_golden_v4.py 的 section_floor 保持一致。
// 图案：棋盘 + 低对比锯齿 + 中段高亮 + 每像素 ±3 确定性噪声（noisy = 灰度 + ((坐标函数)&7) - 3，
//   即 -3..+4，与黄金模型逐字同式；坑 40 教训）。
// 高度 H=12：6 级下沉行缓存冷启动，row_ok = (y_d2 >= 8) 才出判决 → 可比行只有 y=8..11（4 行）。
// 比对区：行 8..11 × 列 12..115 = 416 个像素（run_tb_96.ps1 第 4 步 okf 的判据）。
`timescale 1ns/1ps
module tb_edge_adaptive_96;

    parameter W    = 128;
    parameter H    = 12;
    parameter GRP  = W / 4;

    reg clk   = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;          // 100MHz

    // ---------------- 图案生成：确定性噪声（坐标函数，两阶段同像素同值）----
    function [7:0] noisy;
        input [7:0] v;
        input [10:0] x;
        input [10:0] y;
        integer s;
        begin
            s = v + ((x[3:0]*13 + (x[7:0]^y[7:0])*31 + y[7:0]*7) & 8'h7) - 3;
            noisy = (s < 0) ? 8'd0 : ((s > 255) ? 8'd255 : s);
        end
    endfunction

    function [23:0] pat_rgb;
        input [10:0] x;
        input [10:0] y;
        reg [7:0] v;
        begin
            if ((x[4] == 1'b0))
                v = 8'd120 + {5'b00000, x[2:0]};   // x[4]=0 亮区锯齿（行向恒定，与 golden v4 图案一致）
            else
                v = 8'd40;
            if (x[6:5] == 2'b10)
                v = 8'd200;
            pat_rgb = {noisy(v,x,y), noisy(v,x,y), noisy(v,x,y)};
        end
    endfunction

    function [7:0] gray_of;
        input [23:0] rgb;
        begin
            gray_of = {2'b00, rgb[23:18]} + {1'b0, rgb[15:9]} + {2'b00, rgb[7:2]};
        end
    endfunction

    // ---------------- 并行版激励与响应 ----------------
    reg         p_valid, p_user, p_last;
    reg  [95:0] p_data;
    wire        p_ready;
    wire        p_o_valid, p_o_last, p_o_user;
    wire [95:0] p_o_data;

    // ---------------- 逐像素版（仅烟雾） ----------------
    reg         s_valid, s_sync;
    reg  [7:0]  s_gray;
    wire        s_o_valid, s_o_edge;
    wire [12:0] s_o_mag;

    edge_adaptive_96 #(
        .IMG_WIDTH  (W),
        .IMG_HEIGHT (H),
        .THR_FLOOR  (11'd96)      // 分段地板基准（v5 四档偏移量走模块默认 48/36/20/0）
    ) u_par (
        .I_clk   (clk),   .I_rst_n (rst_n),
        .I_mode  (2'd2),
        .I_k     (2'd2),
        .I_tlast (p_last), .I_tuser (p_user), .I_tdata (p_data),
        .I_tvalid(p_valid), .I_tready(p_ready),
        .O_tlast (p_o_last), .O_tuser(p_o_user), .O_tdata(p_o_data),
        .O_tvalid(p_o_valid), .O_tready(1'b1)
    );

    edge_adaptive_pixel #(
        .IMG_WIDTH (W)
    ) u_seq (
        .I_clk   (clk),   .I_rst_n (rst_n),
        .I_valid (s_valid), .I_sync(s_sync), .I_gray(s_gray), .I_k(2'd2),
        .O_valid (s_o_valid), .O_edge(s_o_edge), .O_mag(s_o_mag)
    );

    // ---------------- 输出：像素编号 + 判决 ----------------
    integer fpar, fseq;
    integer par_cnt = 0, seq_cnt = 0;
    integer par_pix = 0, seq_pix = 0;

    always @(posedge clk) begin
        if (p_o_valid) begin
            $fwrite(fpar, "%0d %0d %0d %0d %0d\n", par_pix,
                    (p_o_data[95:72] == 24'hFFFFFF),
                    (p_o_data[71:48] == 24'hFFFFFF),
                    (p_o_data[47:24] == 24'hFFFFFF),
                    (p_o_data[23:0]  == 24'hFFFFFF));
            par_pix = par_pix + 4;
            par_cnt = par_cnt + 1;
        end
        if (s_o_valid) begin
            $fwrite(fseq, "%0d %0d\n", seq_pix, s_o_edge);
            seq_pix = seq_pix + 1;
            seq_cnt = seq_cnt + 1;
        end
    end

    // ---------------- 主激励 ----------------
    integer gx, py, m;
    reg [23:0] px [0:3];

    initial begin
        fpar = $fopen("par_out.txt", "w");
        fseq = $fopen("seq_out.txt", "w");
        p_valid = 0; p_user = 0; p_last = 0; p_data = 0;
        s_valid = 0; s_sync = 0; s_gray = 0;

        repeat (10) @(posedge clk);
        rst_n = 1;
        repeat (5) @(posedge clk);

        // ---------- 阶段 1：并行流（4 像素/拍，连续无间隔）----------
        @(posedge clk);
        p_valid <= 1'b1;
        @(posedge clk);
        for (py = 0; py < H; py = py + 1) begin
            for (gx = 0; gx < GRP; gx = gx + 1) begin
                for (m = 0; m < 4; m = m + 1)
                    px[m] = pat_rgb(4*gx + m, py);
                p_data  <= {px[0], px[1], px[2], px[3]};
                p_user  <= (py == 0) && (gx == 0);
                p_last  <= (gx == GRP-1);
                p_valid <= 1'b1;
                @(posedge clk);
            end
        end
        p_valid <= 1'b0; p_user <= 1'b0; p_last <= 1'b0;
        repeat (40) @(posedge clk);

        // ---------- 阶段 2：逐像素流（1 像素/拍，仅烟雾）----------
        @(posedge clk);
        s_valid <= 1'b1;
        @(posedge clk);
        for (py = 0; py < H; py = py + 1) begin
            for (gx = 0; gx < W; gx = gx + 1) begin
                s_gray  <= gray_of(pat_rgb(gx, py));
                s_sync  <= (gx == 0);
                s_valid <= 1'b1;
                @(posedge clk);
            end
        end
        s_valid <= 1'b0; s_sync <= 1'b0;
        repeat (40) @(posedge clk);

        $fclose(fpar);
        $fclose(fseq);
        $display("---- TB DONE ----");
        $display("并行版输出拍数 : %0d", par_cnt);
        $display("逐像素版输出拍数: %0d", seq_cnt);
        $finish;
    end

endmodule