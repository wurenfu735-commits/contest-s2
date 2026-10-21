// ============================================================================
// morph_grad_96.v  ——  形态学梯度（3×3 膨胀-腐蚀）：max(3×3) - min(3×3)
//
// 为什么有它（高阶①"多算法切换"）：
//   现有 edge_adaptive_96 是"5×5 盒式平滑 + 基线 2 中心差分"的等效 5×7 平滑梯度；
//   本模块是结构完全不同的第二类算子（形态学），凑出真正的多算法切换，
//   且形态学梯度对脉冲噪声天然不敏感（max/min 不被单个脉冲拉偏），与平滑梯度互补。
//
// 算法：morph = max(3×3) - min(3×3)
//   max/min 可分离：3×3 max = max(3行各行3元max)，min 同理 → 8 比较器/像素（非全排序）
//
// 窗口结构：完全复用 edge_adaptive_96（6 块行缓存 + 3 级延迟链，10 列窗口）
//   - 锚像素 i 在窗口索引 3+i；其 3×3 = 行(r2,r3,r4) × 窗口索引(2+i, 3+i, 4+i)
//   - 左右邻由延迟链提供（s1/s2/s3），已验证可提供完整 3×3
//   - 与 edge_adaptive_96 延迟一致（3 拍），isp_top 里 mux 切换不会错位
//
// 阈值：固定 MORPH_THR（参数化）。形态学梯度在均匀区接近 0，无需复杂自适应。
//
// 资源预估：+6 ERAM（行缓存）+ ~300 LUT（max/min 比较器）· DSP 0
// ============================================================================
`timescale 1ns / 1ps

module morph_grad_96 #(
    parameter IMG_WIDTH  = 1280,
    parameter IMG_HEIGHT = 720,
    parameter [7:0] MORPH_THR = 8'd20     // 形态学梯度阈值（演示可调：小=边缘更粗）
)(
    input  wire        I_clk,
    input  wire        I_rst_n,
    input  wire [2:0]  I_mode,       // 保留接口兼容（isp_top mux 选模块，本模块单判决）
    input  wire [1:0]  I_k,          // 保留接口兼容
    input  wire        I_tlast,
    input  wire        I_tuser,
    input  wire [95:0] I_tdata,      // 4 像素 RGB888：[95:72]=第1个 … [23:0]=第4个
    input  wire        I_tvalid,
    output wire        I_tready,
    output reg         O_tlast,
    output reg         O_tuser,
    output reg  [95:0] O_tdata,      // 二值边缘图（黑底白线）
    output reg  [31:0] O_mag,        // 梯度灰阶（4×8bit，供叠加显示）
    output reg         O_tvalid,
    input  wire        O_tready
);

    localparam LAST_GRP = (IMG_WIDTH >> 2) - 1;
    localparam LAST_ROW = IMG_HEIGHT - 1;
    localparam TOTAL_DLY = 3;

    assign I_tready = O_tready;

    // ---------------- 1) 拆像素 + 灰度化（与 edge_adaptive_96 完全一致）----------------
    wire [23:0] pix0 = I_tdata[95:72];
    wire [23:0] pix1 = I_tdata[71:48];
    wire [23:0] pix2 = I_tdata[47:24];
    wire [23:0] pix3 = I_tdata[23:0];

    (* keep = "true" *) wire [7:0] g0 = {2'b00,pix0[23:18]} + {1'b0,pix0[15:9]} + {2'b00,pix0[7:2]};
    (* keep = "true" *) wire [7:0] g1 = {2'b00,pix1[23:18]} + {1'b0,pix1[15:9]} + {2'b00,pix1[7:2]};
    (* keep = "true" *) wire [7:0] g2 = {2'b00,pix2[23:18]} + {1'b0,pix2[15:9]} + {2'b00,pix2[7:2]};
    (* keep = "true" *) wire [7:0] g3 = {2'b00,pix3[23:18]} + {1'b0,pix3[15:9]} + {2'b00,pix3[7:2]};

    // ---------------- 2) 行列计数（沿用 v1/v2）----------------
    reg [9:0] x_grp;
    reg [9:0] y_pos;
    reg [9:0] y_d1, y_d2;
    reg [9:0] x_d1, x_d2;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            x_grp <= 10'd0;
            y_pos <= 10'd0;
        end else if (I_tvalid) begin
            if (I_tuser) begin
                x_grp <= 10'd1;
                y_pos <= 10'd0;
            end else if (x_grp == LAST_GRP[9:0]) begin
                x_grp <= 10'd0;
                y_pos <= (y_pos == LAST_ROW[9:0]) ? 10'd0 : (y_pos + 10'd1);
            end else begin
                x_grp <= x_grp + 10'd1;
            end
        end
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n)          begin y_d1 <= 10'd0; y_d2 <= 10'd0; x_d1 <= 10'd0; x_d2 <= 10'd0; end
        else if (I_tvalid)     begin y_d1 <= y_pos; y_d2 <= y_d1;   x_d1 <= x_grp; x_d2 <= x_d1;  end
    end

    // ---------------- 3) 行缓存：6 块灰度（结构同 edge_adaptive_96）----------------
    (* keep = "true" *) wire [10:0] rd_gray = (x_grp == LAST_GRP[9:0]) ? 11'd0 : ({1'b0, x_grp} + 11'd1);
    (* keep = "true" *) wire [10:0] wr_gray = {1'b0, x_grp};
    (* keep = "true" *) wire [31:0] S_gray_in_w = {g3, g2, g1, g0};
    (* keep = "true" *) wire [31:0] d1, d2, d3, d4, d5, d6;

    blk_mem_gen_zhenghe u_line1 (.clka(I_clk), .wea(1'b0), .addra(rd_gray), .dia(32'd0), .clkb(I_clk), .web(I_tvalid), .addrb(wr_gray), .dib(S_gray_in_w), .doa(d1), .dob());
    blk_mem_gen_zhenghe u_line2 (.clka(I_clk), .wea(1'b0), .addra(rd_gray), .dia(32'd0), .clkb(I_clk), .web(I_tvalid), .addrb(wr_gray), .dib(d1),        .doa(d2), .dob());
    blk_mem_gen_zhenghe u_line3 (.clka(I_clk), .wea(1'b0), .addra(rd_gray), .dia(32'd0), .clkb(I_clk), .web(I_tvalid), .addrb(wr_gray), .dib(d2),        .doa(d3), .dob());
    blk_mem_gen_zhenghe u_line4 (.clka(I_clk), .wea(1'b0), .addra(rd_gray), .dia(32'd0), .clkb(I_clk), .web(I_tvalid), .addrb(wr_gray), .dib(d3),        .doa(d4), .dob());
    blk_mem_gen_zhenghe u_line5 (.clka(I_clk), .wea(1'b0), .addra(rd_gray), .dia(32'd0), .clkb(I_clk), .web(I_tvalid), .addrb(wr_gray), .dib(d4),        .doa(d5), .dob());
    blk_mem_gen_zhenghe u_line6 (.clka(I_clk), .wea(1'b0), .addra(rd_gray), .dia(32'd0), .clkb(I_clk), .web(I_tvalid), .addrb(wr_gray), .dib(d5),        .doa(d6), .dob());

    // ---------------- 4) 延迟链 + 10 列窗口（与 edge_adaptive_96 同构）----------------
    reg [7:0] r0_s1_0,r0_s1_1,r0_s1_2,r0_s1_3, r0_s2_0,r0_s2_1,r0_s2_2,r0_s2_3, r0_s3_1,r0_s3_2,r0_s3_3;
    reg [7:0] r1_s1_0,r1_s1_1,r1_s1_2,r1_s1_3, r1_s2_0,r1_s2_1,r1_s2_2,r1_s2_3, r1_s3_1,r1_s3_2,r1_s3_3;
    reg [7:0] r2_s1_0,r2_s1_1,r2_s1_2,r2_s1_3, r2_s2_0,r2_s2_1,r2_s2_2,r2_s2_3, r2_s3_1,r2_s3_2,r2_s3_3;
    reg [7:0] r3_s1_0,r3_s1_1,r3_s1_2,r3_s1_3, r3_s2_0,r3_s2_1,r3_s2_2,r3_s2_3, r3_s3_1,r3_s3_2,r3_s3_3;
    reg [7:0] r4_s1_0,r4_s1_1,r4_s1_2,r4_s1_3, r4_s2_0,r4_s2_1,r4_s2_2,r4_s2_3, r4_s3_1,r4_s3_2,r4_s3_3;
    reg [7:0] r5_s1_0,r5_s1_1,r5_s1_2,r5_s1_3, r5_s2_0,r5_s2_1,r5_s2_2,r5_s2_3, r5_s3_1,r5_s3_2,r5_s3_3;
    reg [7:0] r6_s1_0,r6_s1_1,r6_s1_2,r6_s1_3, r6_s2_0,r6_s2_1,r6_s2_2,r6_s2_3, r6_s3_1,r6_s3_2,r6_s3_3;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            r0_s1_0<=8'd0; r0_s1_1<=8'd0; r0_s1_2<=8'd0; r0_s1_3<=8'd0; r0_s2_0<=8'd0; r0_s2_1<=8'd0; r0_s2_2<=8'd0; r0_s2_3<=8'd0; r0_s3_1<=8'd0; r0_s3_2<=8'd0; r0_s3_3<=8'd0;
            r1_s1_0<=8'd0; r1_s1_1<=8'd0; r1_s1_2<=8'd0; r1_s1_3<=8'd0; r1_s2_0<=8'd0; r1_s2_1<=8'd0; r1_s2_2<=8'd0; r1_s2_3<=8'd0; r1_s3_1<=8'd0; r1_s3_2<=8'd0; r1_s3_3<=8'd0;
            r2_s1_0<=8'd0; r2_s1_1<=8'd0; r2_s1_2<=8'd0; r2_s1_3<=8'd0; r2_s2_0<=8'd0; r2_s2_1<=8'd0; r2_s2_2<=8'd0; r2_s2_3<=8'd0; r2_s3_1<=8'd0; r2_s3_2<=8'd0; r2_s3_3<=8'd0;
            r3_s1_0<=8'd0; r3_s1_1<=8'd0; r3_s1_2<=8'd0; r3_s1_3<=8'd0; r3_s2_0<=8'd0; r3_s2_1<=8'd0; r3_s2_2<=8'd0; r3_s2_3<=8'd0; r3_s3_1<=8'd0; r3_s3_2<=8'd0; r3_s3_3<=8'd0;
            r4_s1_0<=8'd0; r4_s1_1<=8'd0; r4_s1_2<=8'd0; r4_s1_3<=8'd0; r4_s2_0<=8'd0; r4_s2_1<=8'd0; r4_s2_2<=8'd0; r4_s2_3<=8'd0; r4_s3_1<=8'd0; r4_s3_2<=8'd0; r4_s3_3<=8'd0;
            r5_s1_0<=8'd0; r5_s1_1<=8'd0; r5_s1_2<=8'd0; r5_s1_3<=8'd0; r5_s2_0<=8'd0; r5_s2_1<=8'd0; r5_s2_2<=8'd0; r5_s2_3<=8'd0; r5_s3_1<=8'd0; r5_s3_2<=8'd0; r5_s3_3<=8'd0;
            r6_s1_0<=8'd0; r6_s1_1<=8'd0; r6_s1_2<=8'd0; r6_s1_3<=8'd0; r6_s2_0<=8'd0; r6_s2_1<=8'd0; r6_s2_2<=8'd0; r6_s2_3<=8'd0; r6_s3_1<=8'd0; r6_s3_2<=8'd0; r6_s3_3<=8'd0;
        end else if (I_tvalid) begin
            r0_s1_0<=g0; r0_s1_1<=g1; r0_s1_2<=g2; r0_s1_3<=g3;
            r0_s2_0<=r0_s1_0; r0_s2_1<=r0_s1_1; r0_s2_2<=r0_s1_2; r0_s2_3<=r0_s1_3;
            r0_s3_1<=r0_s2_1; r0_s3_2<=r0_s2_2; r0_s3_3<=r0_s2_3;

            r1_s1_0<=d1[7:0]; r1_s1_1<=d1[15:8]; r1_s1_2<=d1[23:16]; r1_s1_3<=d1[31:24];
            r1_s2_0<=r1_s1_0; r1_s2_1<=r1_s1_1; r1_s2_2<=r1_s1_2; r1_s2_3<=r1_s1_3;
            r1_s3_1<=r1_s2_1; r1_s3_2<=r1_s2_2; r1_s3_3<=r1_s2_3;

            r2_s1_0<=d2[7:0]; r2_s1_1<=d2[15:8]; r2_s1_2<=d2[23:16]; r2_s1_3<=d2[31:24];
            r2_s2_0<=r2_s1_0; r2_s2_1<=r2_s1_1; r2_s2_2<=r2_s1_2; r2_s2_3<=r2_s1_3;
            r2_s3_1<=r2_s2_1; r2_s3_2<=r2_s2_2; r2_s3_3<=r2_s2_3;

            r3_s1_0<=d3[7:0]; r3_s1_1<=d3[15:8]; r3_s1_2<=d3[23:16]; r3_s1_3<=d3[31:24];
            r3_s2_0<=r3_s1_0; r3_s2_1<=r3_s1_1; r3_s2_2<=r3_s1_2; r3_s2_3<=r3_s1_3;
            r3_s3_1<=r3_s2_1; r3_s3_2<=r3_s2_2; r3_s3_3<=r3_s2_3;

            r4_s1_0<=d4[7:0]; r4_s1_1<=d4[15:8]; r4_s1_2<=d4[23:16]; r4_s1_3<=d4[31:24];
            r4_s2_0<=r4_s1_0; r4_s2_1<=r4_s1_1; r4_s2_2<=r4_s1_2; r4_s2_3<=r4_s1_3;
            r4_s3_1<=r4_s2_1; r4_s3_2<=r4_s2_2; r4_s3_3<=r4_s2_3;

            r5_s1_0<=d5[7:0]; r5_s1_1<=d5[15:8]; r5_s1_2<=d5[23:16]; r5_s1_3<=d5[31:24];
            r5_s2_0<=r5_s1_0; r5_s2_1<=r5_s1_1; r5_s2_2<=r5_s1_2; r5_s2_3<=r5_s1_3;
            r5_s3_1<=r5_s2_1; r5_s3_2<=r5_s2_2; r5_s3_3<=r5_s2_3;

            r6_s1_0<=d6[7:0]; r6_s1_1<=d6[15:8]; r6_s1_2<=d6[23:16]; r6_s1_3<=d6[31:24];
            r6_s2_0<=r6_s1_0; r6_s2_1<=r6_s1_1; r6_s2_2<=r6_s1_2; r6_s2_3<=r6_s1_3;
            r6_s3_1<=r6_s2_1; r6_s3_2<=r6_s2_2; r6_s3_3<=r6_s2_3;
        end
    end

    // 10 列窗口（与 edge_adaptive_96 同构；锚像素 i 在索引 3+i）
    (* keep = "true" *) wire [7:0] w2_0=r2_s3_1, w2_1=r2_s3_2, w2_2=r2_s3_3, w2_3=r2_s2_0, w2_4=r2_s2_1, w2_5=r2_s2_2, w2_6=r2_s2_3, w2_7=r2_s1_0, w2_8=r2_s1_1, w2_9=r2_s1_2;
    (* keep = "true" *) wire [7:0] w3_0=r3_s3_1, w3_1=r3_s3_2, w3_2=r3_s3_3, w3_3=r3_s2_0, w3_4=r3_s2_1, w3_5=r3_s2_2, w3_6=r3_s2_3, w3_7=r3_s1_0, w3_8=r3_s1_1, w3_9=r3_s1_2;
    (* keep = "true" *) wire [7:0] w4_0=r4_s3_1, w4_1=r4_s3_2, w4_2=r4_s3_3, w4_3=r4_s2_0, w4_4=r4_s2_1, w4_5=r4_s2_2, w4_6=r4_s2_3, w4_7=r4_s1_0, w4_8=r4_s1_1, w4_9=r4_s1_2;

    // ---------------- 5) 形态学梯度：3×3 max - min（可分离）----------------
    function [7:0] max3;
        input [7:0] a,b,c;
        reg [7:0] m;
        begin
            m = (a >= b) ? a : b;
            max3 = (m >= c) ? m : c;
        end
    endfunction

    function [7:0] min3;
        input [7:0] a,b,c;
        reg [7:0] m;
        begin
            m = (a <= b) ? a : b;
            min3 = (m <= c) ? m : c;
        end
    endfunction

    // 3×3 max = max(三行各自的 3 元 max)
    function [7:0] max33;
        input [7:0] r0a,r0b,r0c, r1a,r1b,r1c, r2a,r2b,r2c;
        begin
            max33 = max3( max3(r0a,r0b,r0c), max3(r1a,r1b,r1c), max3(r2a,r2b,r2c) );
        end
    endfunction

    function [7:0] min33;
        input [7:0] r0a,r0b,r0c, r1a,r1b,r1c, r2a,r2b,r2c;
        begin
            min33 = min3( min3(r0a,r0b,r0c), min3(r1a,r1b,r1c), min3(r2a,r2b,r2c) );
        end
    endfunction

    // 像素 i 的 3×3：行 w2/w3/w4，窗口索引 (2+i, 3+i, 4+i)
    (* keep = "true" *) wire [7:0] mx0 = max33(w2_2,w2_3,w2_4, w3_2,w3_3,w3_4, w4_2,w4_3,w4_4);
    (* keep = "true" *) wire [7:0] mn0 = min33(w2_2,w2_3,w2_4, w3_2,w3_3,w3_4, w4_2,w4_3,w4_4);
    (* keep = "true" *) wire [7:0] mx1 = max33(w2_3,w2_4,w2_5, w3_3,w3_4,w3_5, w4_3,w4_4,w4_5);
    (* keep = "true" *) wire [7:0] mn1 = min33(w2_3,w2_4,w2_5, w3_3,w3_4,w3_5, w4_3,w4_4,w4_5);
    (* keep = "true" *) wire [7:0] mx2 = max33(w2_4,w2_5,w2_6, w3_4,w3_5,w3_6, w4_4,w4_5,w4_6);
    (* keep = "true" *) wire [7:0] mn2 = min33(w2_4,w2_5,w2_6, w3_4,w3_5,w3_6, w4_4,w4_5,w4_6);
    (* keep = "true" *) wire [7:0] mx3 = max33(w2_5,w2_6,w2_7, w3_5,w3_6,w3_7, w4_5,w4_6,w4_7);
    (* keep = "true" *) wire [7:0] mn3 = min33(w2_5,w2_6,w2_7, w3_5,w3_6,w3_7, w4_5,w4_6,w4_7);

    (* keep = "true" *) wire [7:0] mg0 = mx0 - mn0;
    (* keep = "true" *) wire [7:0] mg1 = mx1 - mn1;
    (* keep = "true" *) wire [7:0] mg2 = mx2 - mn2;
    (* keep = "true" *) wire [7:0] mg3 = mx3 - mn3;

    // ---------------- 6) 阈值判决 + 边界屏蔽（与 edge_adaptive_96 屏蔽口径一致）----------------
    (* keep = "true" *) wire row_ok   = (y_d2 >= 10'd8);
    (* keep = "true" *) wire grp0_bad = (x_d2 == 10'd0);
    (* keep = "true" *) wire last_bad = (x_d2 == LAST_GRP[9:0]);
    (* keep = "true" *) wire beat_bad = (x_grp <= 10'd1);

    (* keep = "true" *) wire s0 = (mg0 >= MORPH_THR);
    (* keep = "true" *) wire s1 = (mg1 >= MORPH_THR);
    (* keep = "true" *) wire s2 = (mg2 >= MORPH_THR);
    (* keep = "true" *) wire s3 = (mg3 >= MORPH_THR);

    (* keep = "true" *) wire e0 = row_ok & ~grp0_bad & ~beat_bad & s0;
    (* keep = "true" *) wire e1 = row_ok & ~grp0_bad & ~beat_bad & s1;
    (* keep = "true" *) wire e2 = row_ok & ~grp0_bad & ~last_bad & ~beat_bad & s2;
    (* keep = "true" *) wire e3 = row_ok & ~last_bad & ~beat_bad & s3;

    // ---------------- 7) 输出 ----------------
    wire [23:0] p0_out = e0 ? 24'hFFFFFF : 24'h000000;
    wire [23:0] p1_out = e1 ? 24'hFFFFFF : 24'h000000;
    wire [23:0] p2_out = e2 ? 24'hFFFFFF : 24'h000000;
    wire [23:0] p3_out = e3 ? 24'hFFFFFF : 24'h000000;

    // ---------------- 8) 控制信号同步延迟（总延迟 3 拍，与 edge_adaptive_96 一致）----------------
    reg [TOTAL_DLY-1:0] vld_d, lst_d, usr_d;
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            vld_d <= {TOTAL_DLY{1'b0}};
            lst_d <= {TOTAL_DLY{1'b0}};
            usr_d <= {TOTAL_DLY{1'b0}};
        end else begin
            vld_d <= {vld_d[TOTAL_DLY-2:0], I_tvalid};
            lst_d <= {lst_d[TOTAL_DLY-2:0], I_tlast};
            usr_d <= {usr_d[TOTAL_DLY-2:0], I_tuser};
        end
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            O_tdata  <= 96'd0;
            O_mag    <= 32'd0;
            O_tvalid <= 1'b0;
            O_tlast  <= 1'b0;
            O_tuser  <= 1'b0;
        end else begin
            O_tdata  <= {p0_out, p1_out, p2_out, p3_out};
            O_mag    <= {mg3, mg2, mg1, mg0};
            O_tvalid <= vld_d[TOTAL_DLY-1];
            O_tlast  <= lst_d[TOTAL_DLY-1];
            O_tuser  <= usr_d[TOTAL_DLY-1];
        end
    end

endmodule
