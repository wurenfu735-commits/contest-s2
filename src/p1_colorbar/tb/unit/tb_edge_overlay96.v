// tb_edge_overlay96 —— mode 4「边缘叠加原图」的对齐与叠加验证
// ============================================================================
// 图案：左半 x<64 用 20+x[5:0]（20..83，每列唯一），右半 x>=64 用 180+x[5:0]（180..243），
//   x=63→64 处 Δ≈97 强竖直边缘（mag≈970，远超阈值）。
//   每列颜色唯一 → 任何「原色延迟链错位一拍」都会立刻暴露（输出颜色与期望列不符）。
//
// mode 4 行为：边缘处输出纯白 24'hFFFFFF，非边缘处输出原彩色（pix_d2，2 拍延迟）。
//   冷启动区（row<8）、行首/行尾屏蔽区输出也是原色（pick=0 → 原色），故全图可查对齐。
//
// 验证判据：
//   1. 白像素只能出现在边缘带 col 56..72 内，且数量 > 0（叠加生效）
//   2. 边缘带之外（col<56 或 col>72）每个像素必须精确等于输入原色（对齐正确）
`timescale 1ns/1ps
module tb_edge_overlay96;

    parameter W    = 128;
    parameter H    = 12;
    parameter GRP  = W / 4;

    reg clk   = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;          // 100MHz

    reg         p_valid, p_user, p_last;
    reg  [95:0] p_data;
    wire        p_ready;
    wire        p_o_valid, p_o_last, p_o_user;
    wire [95:0] p_o_data;

    edge_adaptive_96 #(
        .IMG_WIDTH  (W),
        .IMG_HEIGHT (H),
        .THR_FLOOR  (11'd96)      // v5 默认（四档 144/132/116/96）
    ) u_par (
        .I_clk   (clk),   .I_rst_n (rst_n),
        .I_mode  (3'd4),                          // mode 4：边缘叠加原图
        .I_k     (2'd2),
        .I_tlast (p_last), .I_tuser (p_user), .I_tdata (p_data),
        .I_tvalid(p_valid), .I_tready(p_ready),
        .O_tlast (p_o_last), .O_tuser(p_o_user), .O_tdata(p_o_data),
        .O_tvalid(p_o_valid), .O_tready(1'b1)
    );

    // 图案：每列唯一颜色 + 中间强边缘
    function [23:0] pat;
        input [10:0] x;
        input [10:0] y;
        reg [7:0] v;
        begin
            if (x < 64)
                v = 8'd20 + x[5:0];      // 20..83
            else
                v = 8'd180 + x[5:0];     // 180..243
            pat = {v, v, v};             // 灰色
        end
    endfunction

    integer pix       = 0;     // 输出像素编号
    integer err       = 0;     // 对齐/越界错误数
    integer white_cnt = 0;     // 边缘带内白像素数
    integer total     = 0;     // 检查总像素数

    // 逐像素检查（在输出有效拍解析 4 个像素）
    reg [23:0] d0, d1, d2, d3;
    always @(posedge clk) begin
        if (p_o_valid) begin
            d0 = p_o_data[95:72];
            d1 = p_o_data[71:48];
            d2 = p_o_data[47:24];
            d3 = p_o_data[23:0];
            check_px(pix+0, d0);
            check_px(pix+1, d1);
            check_px(pix+2, d2);
            check_px(pix+3, d3);
            pix = pix + 4;
        end
    end

    task check_px;
        input integer x;
        input [23:0] out;
        reg [10:0] col, row;
        reg [23:0] expect;
        begin
            col = x % W;
            row = x / W;
            if (row >= H) begin
                // row 12 尾巴（补 3 拍的产物），跳过不检查
            end else begin
                expect = pat(col, row);
                total = total + 1;
                if (out == 24'hFFFFFF) begin
                    // 白像素只能在边缘带内
                    if (col >= 56 && col <= 72)
                        white_cnt = white_cnt + 1;
                    else begin
                        if (err < 10) $display("ERROR: white at (col=%0d,row=%0d) outside edge band", col, row);
                        err = err + 1;
                    end
                end else begin
                    // 非白像素：边缘带之外必须精确等于原色（对齐判据）
                    if (col < 56 || col > 72) begin
                        if (out != expect) begin
                            if (err < 10) $display("ERROR: misalign at (col=%0d,row=%0d): out=%h expect=%h", col, row, out, expect);
                            err = err + 1;
                        end
                    end
                end
            end
        end
    endtask

    // 主激励（negedge 驱动 + 阻塞赋值：valid 精确 384 拍，避免多一拍尾巴像素）
    integer gx, py, m;
    reg [23:0] px [0:3];

    initial begin
        p_valid = 0; p_user = 0; p_last = 0; p_data = 0;
        repeat (10) @(posedge clk);
        rst_n = 1;
        repeat (5) @(posedge clk);

        for (py = 0; py < H; py = py + 1) begin
            for (gx = 0; gx < GRP; gx = gx + 1) begin
                @(negedge clk);
                for (m = 0; m < 4; m = m + 1)
                    px[m] = pat(4*gx + m, py);
                p_data  = {px[0], px[1], px[2], px[3]};
                p_user  = (py == 0) && (gx == 0);
                p_last  = (gx == GRP-1);
                p_valid = 1'b1;
            end
        end
        // 补 3 拍 valid，让 pix_d3 把最后 3 组数据完整推出（否则尾 8 像素错位；
        // 这 3 拍输出对应 row 12 尾巴，check_px 里跳过不检查）
        repeat (3) @(posedge clk);
        @(negedge clk);
        p_valid = 1'b0; p_user = 1'b0; p_last = 1'b0;
        repeat (40) @(posedge clk);

        $display("---- TB DONE ----");
        $display("总检查像素 : %0d", total);
        $display("边缘带白像素: %0d（必须 > 0）", white_cnt);
        $display("错误数      : %0d", err);
        if (err == 0 && white_cnt > 0)
            $display("ALL PASSED");
        else
            $display("FAILED");
        $finish;
    end

endmodule
