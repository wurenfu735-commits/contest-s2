// 边缘检测 · 96bit 并行版 v4（4 像素/拍，全分辨率，5×5 均值去噪 + 分段 FLOOR）
// ============================================================================
// 用途：插入官方摄像头通路 isp_top（awb 输出 → 本模块 → data_96bit_to_128bit）
//
// 【v4 变更（2026-10-17）：单一 FLOOR → 分段 FLOOR】
//   v3 的阈值是一条直线：thr = FLOOR + ((mean25*K)>>5)。一个地板要同时伺候暗区和亮区，
//   结果两头都不对：暗部残余雪花压不住，亮部弱纹理又被抬高后的阈值抹掉。
//   v4 把地板按 mean25 分四段（散粒噪声随亮度上升、信噪比随之改善 → 地板随亮度单调下降）：
//     thr = FLOOR_基准 + {96, 64, 32, 0} + ((mean25*K)>>5)
//       mean25 <  64（画面灰度 <41）   →  +96   暗区：压噪优先
//       64  ≤ mean25 < 128（灰度 41-82）→  +64
//       128 ≤ mean25 < 192（灰度 82-123）→ +32
//       mean25 ≥ 192（灰度 ≥123）      →   +0   亮区：保细节
//   基准 FLOOR 由例化处传入：isp_top 与 tb 均传 96（与本档 tb、黄金模型一致）；
//   模块默认值自 v4 起同步为 96，不传参也不会退回过低地板（v3 及以前默认 16）。
//   代价：阈值函数多 3 个比较器 + 3 个加法器，纯组合，流水级数不变。
//   分段点与段落值和黄金模型 tools/gen_golden_v4.py 的 section_floor 逐条对齐。
//
// 【v3 历史变更（2026-10-17）：3×3 均值 → 5×5 均值】
//   v2 上板实测：3×3 均值后平坦区仍有可见雪花 —— 噪声梯度幅度仍超阈值（4.2σ ≈ 63~84）。
//   v3 把均值核扩到 5×5：噪声梯度幅度降到 7.07σ×(和差系数) ≈ 仍 106 量级但
//   真实台阶边界的梯度幅度从 ~783 升到 ~2175，**信噪比翻倍**，FLOOR 可以抬高到
//   160 直接把残雪挡住、边缘仍有 13 倍余量。弱纹理（台阶 3）在这档阈值下会丢，
//   这是"干净 > 细腻"的取舍（用户：综合效果最好）。
//
// 【结构代价】行缓存 3→6 块(灰度)+1 块(判决)，窗口 8 列 4 行 → 10 列 7 行。
//
// 【设计说明（只借思路不借代码的产物）】：
//   5 列滑动和 = separable 第一步（调研 R3：与开源 Sobel 分离思路一致）；
//   6 块行缓存 = 下沉链直扩（块 RAM 同址读写读旧值，数据本就不搬移，
//   环形轮转在本结构下无收益 —— R3 调研结论）。
//
// 【与官方 edge_detect_96 的差异（赛题红线）】
//   官方：降采样 640 + 固定阈值 80 + 无后处理
//   我们：全 1280 + 5×5 均值去噪 + 分段 FLOOR 自适应阈值 + 因果迟滞 + 四态可切
//
// 【资源预估（v3 综合后对账；v4 阈值只多几个比较器/加法器，量级不变）】
//   LUT ~3200  FF ~650  ERAM ~30（6×4+edge）  DSP 0
//
// 【实现约定（沿用 v1/v2 教训）】keep 全加；块 RAM 用已注册 IP、不复位；
//   读出位序 [7:0]=组内第 1 个；拼接最左是 MSB；读地址 rd_gray = x_grp+1（回绕），
//   下沉块写地址 = wr_gray（v2 实测校准）。
//
// 【时序（v2 已验证结构直扩）】窗口材料每行同构：s1=当拍 4 个(1 级)、s2=前拍 4 个(2 级)，
//   s3=前两拍末 3 个(3 级)。10 列窗口（列 4n-3 … 4n+6）：
//     w[0..2] = s3_1..s3_3   w[3..6] = s2_0..s2_3   w[7..9] = s1_0..s1_2
//   行：r0=当拍行 y，r1..r6 = line1..line6（y-1..y-6）。判决锚像素 (4n+i, y-3)。
//   → 总延迟 3 拍不变。
//
// 【梯度与阈值】每像素 4 个 5×5 和：
//   S1=sum25(x+1,r0..r4) S2=sum25(x-1,r0..r4) S3=sum25(x,r0..r4) S4=sum25(x,r2..r6)
//   mag=|S1-S2|+|S3-S4|（≤ 2×12750）；mean25 = S3>>4（≈/16）
//   thr = FLOOR_分段(mean25) + ((mean25*K)>>5)   —— 分段表见上方 v4 变更
//   —— /16 是有意的工程近似：mean25 只做"亮度坡度"项，绝对地板靠 FLOOR 分段。
// ============================================================================
module edge_adaptive_96 #(
    parameter IMG_WIDTH  = 1280,
    parameter IMG_HEIGHT = 720,
    parameter [10:0] THR_FLOOR    = 11'd96,   // v4 基准地板 96（分段 +{96,64,32,0} → 192/160/128/96）；例化处可覆盖，isp_top/tb 均传 96
    parameter [11:0] OFFICIAL_THR = 12'd80
)(
    input  wire        I_clk,
    input  wire        I_rst_n,
    input  wire [1:0]  I_mode,       // 1=官方判决 2=我们的判决 3=左右分屏（0=原图在 isp_top 层做）
    input  wire [1:0]  I_k,          // 亮度灵敏度档 0..3
    input  wire        I_tlast,
    input  wire        I_tuser,
    input  wire [95:0] I_tdata,      // 4 像素 RGB888：[95:72]=第1个 … [23:0]=第4个
    input  wire        I_tvalid,
    output wire        I_tready,
    output reg         O_tlast,
    output reg         O_tuser,
    output reg  [95:0] O_tdata,
    output reg         O_tvalid,
    input  wire        O_tready
);

    localparam LAST_GRP = (IMG_WIDTH >> 2) - 1;
    localparam LAST_ROW = IMG_HEIGHT - 1;
    localparam TOTAL_DLY = 3;

    assign I_tready = O_tready;

    // ---------------- 1) 拆像素 + 灰度化 ----------------
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

    // ---------------- 3) 行缓存：6 块灰度 + 1 块判决 ----------------
    (* keep = "true" *) wire [10:0] rd_gray = (x_grp == LAST_GRP[9:0]) ? 11'd0 : ({1'b0, x_grp} + 11'd1);
    (* keep = "true" *) wire [10:0] rd_edge = {1'b0, x_d1};
    (* keep = "true" *) wire [10:0] wr_gray = {1'b0, x_grp};
    (* keep = "true" *) wire [10:0] wr_edge = {1'b0, x_d2};

    (* keep = "true" *) wire [3:0]  S_edge_out_w;
    (* keep = "true" *) wire [31:0] S_gray_in_w  = {g3, g2, g1, g0};
    (* keep = "true" *) wire [31:0] S_edge_in_w  = {28'd0, S_edge_out_w};

    (* keep = "true" *) wire [31:0] d1, d2, d3, d4, d5, d6;   // line1..line6 读出
    (* keep = "true" *) wire [31:0] S_edge_doa;

    // 6 块灰度：line1 写当前行；line2..6 写"上一块当拍读出"，写地址全部 wr_gray（v2 实测校准）
    blk_mem_gen_zhenghe u_line1 (.clka(I_clk), .wea(1'b0), .addra(rd_gray), .dia(32'd0), .clkb(I_clk), .web(I_tvalid), .addrb(wr_gray), .dib(S_gray_in_w), .doa(d1), .dob());
    blk_mem_gen_zhenghe u_line2 (.clka(I_clk), .wea(1'b0), .addra(rd_gray), .dia(32'd0), .clkb(I_clk), .web(I_tvalid), .addrb(wr_gray), .dib(d1),        .doa(d2), .dob());
    blk_mem_gen_zhenghe u_line3 (.clka(I_clk), .wea(1'b0), .addra(rd_gray), .dia(32'd0), .clkb(I_clk), .web(I_tvalid), .addrb(wr_gray), .dib(d2),        .doa(d3), .dob());
    blk_mem_gen_zhenghe u_line4 (.clka(I_clk), .wea(1'b0), .addra(rd_gray), .dia(32'd0), .clkb(I_clk), .web(I_tvalid), .addrb(wr_gray), .dib(d3),        .doa(d4), .dob());
    blk_mem_gen_zhenghe u_line5 (.clka(I_clk), .wea(1'b0), .addra(rd_gray), .dia(32'd0), .clkb(I_clk), .web(I_tvalid), .addrb(wr_gray), .dib(d4),        .doa(d5), .dob());
    blk_mem_gen_zhenghe u_line6 (.clka(I_clk), .wea(1'b0), .addra(rd_gray), .dia(32'd0), .clkb(I_clk), .web(I_tvalid), .addrb(wr_gray), .dib(d5),        .doa(d6), .dob());

    blk_mem_gen_zhenghe u_line_edge (.clka(I_clk), .wea(1'b0), .addra(rd_edge), .dia(32'd0), .clkb(I_clk), .web(I_tvalid), .addrb(wr_edge), .dib(S_edge_in_w), .doa(S_edge_doa), .dob());

    // ---------------- 4) 延迟链：7 行同构，各凑 10 列窗口 ----------------
    // 窗口（列 4n-3..4n+6，n=x_d2）：w[0..2]=3级 w[3..6]=2级 w[7..9]=1级
    reg [7:0] r0_s1_0,r0_s1_1,r0_s1_2,r0_s1_3, r0_s2_0,r0_s2_1,r0_s2_2,r0_s2_3, r0_s3_1,r0_s3_2,r0_s3_3;
    reg [7:0] r1_s1_0,r1_s1_1,r1_s1_2,r1_s1_3, r1_s2_0,r1_s2_1,r1_s2_2,r1_s2_3, r1_s3_1,r1_s3_2,r1_s3_3;
    reg [7:0] r2_s1_0,r2_s1_1,r2_s1_2,r2_s1_3, r2_s2_0,r2_s2_1,r2_s2_2,r2_s2_3, r2_s3_1,r2_s3_2,r2_s3_3;
    reg [7:0] r3_s1_0,r3_s1_1,r3_s1_2,r3_s1_3, r3_s2_0,r3_s2_1,r3_s2_2,r3_s2_3, r3_s3_1,r3_s3_2,r3_s3_3;
    reg [7:0] r4_s1_0,r4_s1_1,r4_s1_2,r4_s1_3, r4_s2_0,r4_s2_1,r4_s2_2,r4_s2_3, r4_s3_1,r4_s3_2,r4_s3_3;
    reg [7:0] r5_s1_0,r5_s1_1,r5_s1_2,r5_s1_3, r5_s2_0,r5_s2_1,r5_s2_2,r5_s2_3, r5_s3_1,r5_s3_2,r5_s3_3;
    reg [7:0] r6_s1_0,r6_s1_1,r6_s1_2,r6_s1_3, r6_s2_0,r6_s2_1,r6_s2_2,r6_s2_3, r6_s3_1,r6_s3_2,r6_s3_3;
    reg [3:0] e_s1;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            r0_s1_0<=8'd0; r0_s1_1<=8'd0; r0_s1_2<=8'd0; r0_s1_3<=8'd0;
            r0_s2_0<=8'd0; r0_s2_1<=8'd0; r0_s2_2<=8'd0; r0_s2_3<=8'd0; r0_s3_1<=8'd0; r0_s3_2<=8'd0; r0_s3_3<=8'd0;
            r1_s1_0<=8'd0; r1_s1_1<=8'd0; r1_s1_2<=8'd0; r1_s1_3<=8'd0;
            r1_s2_0<=8'd0; r1_s2_1<=8'd0; r1_s2_2<=8'd0; r1_s2_3<=8'd0; r1_s3_1<=8'd0; r1_s3_2<=8'd0; r1_s3_3<=8'd0;
            r2_s1_0<=8'd0; r2_s1_1<=8'd0; r2_s1_2<=8'd0; r2_s1_3<=8'd0;
            r2_s2_0<=8'd0; r2_s2_1<=8'd0; r2_s2_2<=8'd0; r2_s2_3<=8'd0; r2_s3_1<=8'd0; r2_s3_2<=8'd0; r2_s3_3<=8'd0;
            r3_s1_0<=8'd0; r3_s1_1<=8'd0; r3_s1_2<=8'd0; r3_s1_3<=8'd0;
            r3_s2_0<=8'd0; r3_s2_1<=8'd0; r3_s2_2<=8'd0; r3_s2_3<=8'd0; r3_s3_1<=8'd0; r3_s3_2<=8'd0; r3_s3_3<=8'd0;
            r4_s1_0<=8'd0; r4_s1_1<=8'd0; r4_s1_2<=8'd0; r4_s1_3<=8'd0;
            r4_s2_0<=8'd0; r4_s2_1<=8'd0; r4_s2_2<=8'd0; r4_s2_3<=8'd0; r4_s3_1<=8'd0; r4_s3_2<=8'd0; r4_s3_3<=8'd0;
            r5_s1_0<=8'd0; r5_s1_1<=8'd0; r5_s1_2<=8'd0; r5_s1_3<=8'd0;
            r5_s2_0<=8'd0; r5_s2_1<=8'd0; r5_s2_2<=8'd0; r5_s2_3<=8'd0; r5_s3_1<=8'd0; r5_s3_2<=8'd0; r5_s3_3<=8'd0;
            r6_s1_0<=8'd0; r6_s1_1<=8'd0; r6_s1_2<=8'd0; r6_s1_3<=8'd0;
            r6_s2_0<=8'd0; r6_s2_1<=8'd0; r6_s2_2<=8'd0; r6_s2_3<=8'd0; r6_s3_1<=8'd0; r6_s3_2<=8'd0; r6_s3_3<=8'd0;
            e_s1<=4'd0;
        end else if (I_tvalid) begin
            // r0 = 当拍灰度
            r0_s1_0<=g0; r0_s1_1<=g1; r0_s1_2<=g2; r0_s1_3<=g3;
            r0_s2_0<=r0_s1_0; r0_s2_1<=r0_s1_1; r0_s2_2<=r0_s1_2; r0_s2_3<=r0_s1_3;
            r0_s3_1<=r0_s2_1; r0_s3_2<=r0_s2_2; r0_s3_3<=r0_s2_3;
            // r1..r6 = line1..line6 读出（位序 [7:0]=组内第 1 个）
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
            // 判定位
            e_s1<=S_edge_doa;
        end
    end

    // 10 列窗口（列 4n-3..4n+6）
    (* keep = "true" *) wire [7:0] w0_0=r0_s3_1, w0_1=r0_s3_2, w0_2=r0_s3_3, w0_3=r0_s2_0, w0_4=r0_s2_1, w0_5=r0_s2_2, w0_6=r0_s2_3, w0_7=r0_s1_0, w0_8=r0_s1_1, w0_9=r0_s1_2;
    (* keep = "true" *) wire [7:0] w1_0=r1_s3_1, w1_1=r1_s3_2, w1_2=r1_s3_3, w1_3=r1_s2_0, w1_4=r1_s2_1, w1_5=r1_s2_2, w1_6=r1_s2_3, w1_7=r1_s1_0, w1_8=r1_s1_1, w1_9=r1_s1_2;
    (* keep = "true" *) wire [7:0] w2_0=r2_s3_1, w2_1=r2_s3_2, w2_2=r2_s3_3, w2_3=r2_s2_0, w2_4=r2_s2_1, w2_5=r2_s2_2, w2_6=r2_s2_3, w2_7=r2_s1_0, w2_8=r2_s1_1, w2_9=r2_s1_2;
    (* keep = "true" *) wire [7:0] w3_0=r3_s3_1, w3_1=r3_s3_2, w3_2=r3_s3_3, w3_3=r3_s2_0, w3_4=r3_s2_1, w3_5=r3_s2_2, w3_6=r3_s2_3, w3_7=r3_s1_0, w3_8=r3_s1_1, w3_9=r3_s1_2;
    (* keep = "true" *) wire [7:0] w4_0=r4_s3_1, w4_1=r4_s3_2, w4_2=r4_s3_3, w4_3=r4_s2_0, w4_4=r4_s2_1, w4_5=r4_s2_2, w4_6=r4_s2_3, w4_7=r4_s1_0, w4_8=r4_s1_1, w4_9=r4_s1_2;
    (* keep = "true" *) wire [7:0] w5_0=r5_s3_1, w5_1=r5_s3_2, w5_2=r5_s3_3, w5_3=r5_s2_0, w5_4=r5_s2_1, w5_5=r5_s2_2, w5_6=r5_s2_3, w5_7=r5_s1_0, w5_8=r5_s1_1, w5_9=r5_s1_2;
    (* keep = "true" *) wire [7:0] w6_0=r6_s3_1, w6_1=r6_s3_2, w6_2=r6_s3_3, w6_3=r6_s2_0, w6_4=r6_s2_1, w6_5=r6_s2_2, w6_6=r6_s2_3, w6_7=r6_s1_0, w6_8=r6_s1_1, w6_9=r6_s1_2;

    // 判定位窗口
    (* keep = "true" *) wire [3:0] up     = S_edge_doa;
    (* keep = "true" *) wire [3:0] upleft = {up[2], up[1], up[0], e_s1[3]};

    // ---------------- 5) 5 列滑动和 ×7 行 + 5×5 和 ----------------
    function [11:0] col5;
        input [7:0] a,b,c,dd,ee;
        begin
            col5 = {4'b0000,a} + {4'b0000,b} + {4'b0000,c} + {4'b0000,dd} + {4'b0000,ee};
        end
    endfunction

    function [14:0] s25_of;
        input [11:0] c1,c2,c3,c4,c5;
        begin
            s25_of = {3'b000,c1} + {3'b000,c2} + {3'b000,c3} + {3'b000,c4} + {3'b000,c5};
        end
    endfunction

    // 每行 6 个列和（起点 0..5）
    (* keep = "true" *) wire [11:0] r0c0=col5(w0_0,w0_1,w0_2,w0_3,w0_4), r0c1=col5(w0_1,w0_2,w0_3,w0_4,w0_5);
    (* keep = "true" *) wire [11:0] r0c2=col5(w0_2,w0_3,w0_4,w0_5,w0_6), r0c3=col5(w0_3,w0_4,w0_5,w0_6,w0_7);
    (* keep = "true" *) wire [11:0] r0c4=col5(w0_4,w0_5,w0_6,w0_7,w0_8), r0c5=col5(w0_5,w0_6,w0_7,w0_8,w0_9);
    (* keep = "true" *) wire [11:0] r1c0=col5(w1_0,w1_1,w1_2,w1_3,w1_4), r1c1=col5(w1_1,w1_2,w1_3,w1_4,w1_5);
    (* keep = "true" *) wire [11:0] r1c2=col5(w1_2,w1_3,w1_4,w1_5,w1_6), r1c3=col5(w1_3,w1_4,w1_5,w1_6,w1_7);
    (* keep = "true" *) wire [11:0] r1c4=col5(w1_4,w1_5,w1_6,w1_7,w1_8), r1c5=col5(w1_5,w1_6,w1_7,w1_8,w1_9);
    (* keep = "true" *) wire [11:0] r2c0=col5(w2_0,w2_1,w2_2,w2_3,w2_4), r2c1=col5(w2_1,w2_2,w2_3,w2_4,w2_5);
    (* keep = "true" *) wire [11:0] r2c2=col5(w2_2,w2_3,w2_4,w2_5,w2_6), r2c3=col5(w2_3,w2_4,w2_5,w2_6,w2_7);
    (* keep = "true" *) wire [11:0] r2c4=col5(w2_4,w2_5,w2_6,w2_7,w2_8), r2c5=col5(w2_5,w2_6,w2_7,w2_8,w2_9);
    (* keep = "true" *) wire [11:0] r3c0=col5(w3_0,w3_1,w3_2,w3_3,w3_4), r3c1=col5(w3_1,w3_2,w3_3,w3_4,w3_5);
    (* keep = "true" *) wire [11:0] r3c2=col5(w3_2,w3_3,w3_4,w3_5,w3_6), r3c3=col5(w3_3,w3_4,w3_5,w3_6,w3_7);
    (* keep = "true" *) wire [11:0] r3c4=col5(w3_4,w3_5,w3_6,w3_7,w3_8), r3c5=col5(w3_5,w3_6,w3_7,w3_8,w3_9);
    (* keep = "true" *) wire [11:0] r4c0=col5(w4_0,w4_1,w4_2,w4_3,w4_4), r4c1=col5(w4_1,w4_2,w4_3,w4_4,w4_5);
    (* keep = "true" *) wire [11:0] r4c2=col5(w4_2,w4_3,w4_4,w4_5,w4_6), r4c3=col5(w4_3,w4_4,w4_5,w4_6,w4_7);
    (* keep = "true" *) wire [11:0] r4c4=col5(w4_4,w4_5,w4_6,w4_7,w4_8), r4c5=col5(w4_5,w4_6,w4_7,w4_8,w4_9);
    (* keep = "true" *) wire [11:0] r5c0=col5(w5_0,w5_1,w5_2,w5_3,w5_4), r5c1=col5(w5_1,w5_2,w5_3,w5_4,w5_5);
    (* keep = "true" *) wire [11:0] r5c2=col5(w5_2,w5_3,w5_4,w5_5,w5_6), r5c3=col5(w5_3,w5_4,w5_5,w5_6,w5_7);
    (* keep = "true" *) wire [11:0] r5c4=col5(w5_4,w5_5,w5_6,w5_7,w5_8), r5c5=col5(w5_5,w5_6,w5_7,w5_8,w5_9);
    (* keep = "true" *) wire [11:0] r6c0=col5(w6_0,w6_1,w6_2,w6_3,w6_4), r6c1=col5(w6_1,w6_2,w6_3,w6_4,w6_5);
    (* keep = "true" *) wire [11:0] r6c2=col5(w6_2,w6_3,w6_4,w6_5,w6_6), r6c3=col5(w6_3,w6_4,w6_5,w6_6,w6_7);
    (* keep = "true" *) wire [11:0] r6c4=col5(w6_4,w6_5,w6_6,w6_7,w6_8), r6c5=col5(w6_5,w6_6,w6_7,w6_8,w6_9);

    // 像素 0..3 的 S1..S4
    (* keep = "true" *) wire [14:0] s1_0 = s25_of(r0c2,r1c2,r2c2,r3c2,r4c2), s2_0 = s25_of(r0c0,r1c0,r2c0,r3c0,r4c0), s3_0 = s25_of(r0c1,r1c1,r2c1,r3c1,r4c1), s4_0 = s25_of(r2c1,r3c1,r4c1,r5c1,r6c1);
    (* keep = "true" *) wire [14:0] s1_1 = s25_of(r0c3,r1c3,r2c3,r3c3,r4c3), s2_1 = s25_of(r0c1,r1c1,r2c1,r3c1,r4c1), s3_1 = s25_of(r0c2,r1c2,r2c2,r3c2,r4c2), s4_1 = s25_of(r2c2,r3c2,r4c2,r5c2,r6c2);
    (* keep = "true" *) wire [14:0] s1_2 = s25_of(r0c4,r1c4,r2c4,r3c4,r4c4), s2_2 = s25_of(r0c2,r1c2,r2c2,r3c2,r4c2), s3_2 = s25_of(r0c3,r1c3,r2c3,r3c3,r4c3), s4_2 = s25_of(r2c3,r3c3,r4c3,r5c3,r6c3);
    (* keep = "true" *) wire [14:0] s1_3 = s25_of(r0c5,r1c5,r2c5,r3c5,r4c5), s2_3 = s25_of(r0c3,r1c3,r2c3,r3c3,r4c3), s3_3 = s25_of(r0c4,r1c4,r2c4,r3c4,r4c4), s4_3 = s25_of(r2c4,r3c4,r4c4,r5c4,r6c4);

    function [15:0] mag_f;
        input [14:0] sp, sn, up9, dn9;
        reg [14:0] a1, a2;
        begin
            a1 = (sp >= sn) ? (sp - sn) : (sn - sp);
            a2 = (up9 >= dn9) ? (up9 - dn9) : (dn9 - up9);
            mag_f = {1'b0, a1} + {1'b0, a2};
        end
    endfunction

    (* keep = "true" *) wire [15:0] mag0 = mag_f(s1_0, s2_0, s3_0, s4_0);
    (* keep = "true" *) wire [15:0] mag1 = mag_f(s1_1, s2_1, s3_1, s4_1);
    (* keep = "true" *) wire [15:0] mag2 = mag_f(s1_2, s2_2, s3_2, s4_2);
    (* keep = "true" *) wire [15:0] mag3 = mag_f(s1_3, s2_3, s3_3, s4_3);

    // ---------------- 6) 自适应阈值 v4：thr = FLOOR_section(mean25) + ((mean25 * K) >> 5) ----------------
    // 分段地板：噪声随亮度增大而减小（散粒噪声信噪比随亮度改善），段落值与黄金模型
    // gen_golden_v4.py 的 section_floor 一致：基准 THR_FLOOR + {96, 64, 32, 0}
    function [15:0] thr_calc;
        input [14:0] s25;
        input [1:0]  k;
        reg [10:0] m25;
        reg [10:0] floor_sel;
        reg [15:0] mk;
        begin
            m25 = s25[14:4];                    // s25 >> 4（≈ /16，注释见文件头）
            if (m25 < 11'd64)        floor_sel = THR_FLOOR + 11'd96;   // 暗区：压噪优先
            else if (m25 < 11'd128)  floor_sel = THR_FLOOR + 11'd64;
            else if (m25 < 11'd192)  floor_sel = THR_FLOOR + 11'd32;
            else                     floor_sel = THR_FLOOR;            // 亮区：保细节
            case (k)
                2'd0:    mk = 16'd0;
                2'd1:    mk = {5'b00000, m25};
                2'd2:    mk = {4'b0000, m25, 1'b0};
                default: mk = {4'b0000, m25, 1'b0} + {5'b00000, m25};
            endcase
            thr_calc = {5'b00000, floor_sel} + (mk >> 5);
        end
    endfunction

    (* keep = "true" *) wire [15:0] thr0 = thr_calc(s3_0, I_k);
    (* keep = "true" *) wire [15:0] thr1 = thr_calc(s3_1, I_k);
    (* keep = "true" *) wire [15:0] thr2 = thr_calc(s3_2, I_k);
    (* keep = "true" *) wire [15:0] thr3 = thr_calc(s3_3, I_k);

    // ---------------- 7) 因果双阈值迟滞（沿用 v2）----------------
    reg left_in;
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n)          left_in <= 1'b0;
        else if (I_tvalid)     left_in <= S_edge_out_w[3];
    end

    (* keep = "true" *) wire s0 = (mag0 >= thr0);  (* keep = "true" *) wire w0 = (mag0 >= (thr0 >> 1));
    (* keep = "true" *) wire s1 = (mag1 >= thr1);  (* keep = "true" *) wire w1 = (mag1 >= (thr1 >> 1));
    (* keep = "true" *) wire s2 = (mag2 >= thr2);  (* keep = "true" *) wire w2 = (mag2 >= (thr2 >> 1));
    (* keep = "true" *) wire s3 = (mag3 >= thr3);  (* keep = "true" *) wire w3 = (mag3 >= (thr3 >> 1));

    // 边界屏蔽（v3 窗口 10 列，像素 i 需列 4n+i-3 .. 4n+i+3）：
    //   首组（n=0）屏蔽 e0/e1/e2（用到负列）；末组屏蔽 e2/e3（用到 ≥1280 列，e1 顶到 1279 可用）
    //   行有效：窗口需 r6=行 y-6 有效 + 6 级下沉冷启动 → row_ok = y_d2 >= 8
    (* keep = "true" *) wire row_ok   = (y_d2 >= 10'd8);
    (* keep = "true" *) wire grp0_bad = (x_d2 == 10'd0);
    (* keep = "true" *) wire last_bad = (x_d2 == LAST_GRP[9:0]);
    (* keep = "true" *) wire beat_bad = (x_grp <= 10'd1);

    (* keep = "true" *) wire e0 = row_ok & ~grp0_bad & ~beat_bad & (s0 | (w0 & (left_in | up[0] | upleft[0])));
    (* keep = "true" *) wire e1 = row_ok & ~grp0_bad & ~beat_bad & (s1 | (w1 & (e0 | up[1] | upleft[1])));
    (* keep = "true" *) wire e2 = row_ok & ~grp0_bad & ~last_bad & ~beat_bad & (s2 | (w2 & (e1 | up[2] | upleft[2])));
    (* keep = "true" *) wire e3 = row_ok & ~last_bad & ~beat_bad &           (s3 | (w3 & (e2 | up[3] | upleft[3])));

    assign S_edge_out_w = {e3, e2, e1, e0};

    // ---------------- 8) 四态输出 ----------------
    reg [10:0] out_col;
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n)                     out_col <= 11'd0;
        else if (O_tvalid)                out_col <= (out_col >= (IMG_WIDTH - 1)) ? 11'd0 : (out_col + 11'd1);
    end

    (* keep = "true" *) wire [3:0] off_bits = { (mag3 >= OFFICIAL_THR), (mag2 >= OFFICIAL_THR),
                                               (mag1 >= OFFICIAL_THR), (mag0 >= OFFICIAL_THR) };

    (* keep = "true" *) wire split_left = (out_col < (IMG_WIDTH / 2));
    (* keep = "true" *) wire [3:0] pick = (I_mode == 2'd3) ? (split_left ? off_bits : S_edge_out_w) :
                                          (I_mode == 2'd1) ? off_bits : S_edge_out_w;

    wire [23:0] p0_out = pick[0] ? 24'hFFFFFF : 24'h000000;
    wire [23:0] p1_out = pick[1] ? 24'hFFFFFF : 24'h000000;
    wire [23:0] p2_out = pick[2] ? 24'hFFFFFF : 24'h000000;
    wire [23:0] p3_out = pick[3] ? 24'hFFFFFF : 24'h000000;

    // ---------------- 9) 控制信号同步延迟（总延迟 3 拍）----------------
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
            O_tvalid <= 1'b0;
            O_tlast  <= 1'b0;
            O_tuser  <= 1'b0;
        end else begin
            O_tdata  <= {p0_out, p1_out, p2_out, p3_out};
            O_tvalid <= vld_d[TOTAL_DLY-1];
            O_tlast  <= lst_d[TOTAL_DLY-1];
            O_tuser  <= usr_d[TOTAL_DLY-1];
        end
    end

endmodule