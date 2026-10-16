// 边缘检测 · 逐像素参考实现 v2（与 edge_adaptive_96 v2 同算法，供逐像素对比验证）
// ============================================================================
// 用途：算法正确性验证基准。与 96bit 并行版跑同一测试图案，按像素编号逐像素比对。
//
// 【v2 变更：3×3 均值去噪 + 均值梯度（与并行版同构）】
//   窗口从 3 行 3 列扩到 4 行 5 列；sobel 替换为相邻 3×3 和之差；
//   判决锚定像素 (col-2)，所以窗口五列全部来自当前与历史数据，无需未来列。
//
//   S1 = sum9(x+1,t..b)=q3_2+r3_2+c3_2，S2 = sum9(x-1)=q3_0+r3_0+c3_0，
//   S3 = sum9(x)=q3_1+r3_1+c3_1（兼作阈值输入），S4 = sum9(上行)=z3_1+q3_1+r3_1
//   mag = |S1-S2| + |S3-S4|
//
// 【行缓存】4 块 blk_mem_gen_zhenghe（lb1/lb2/lb3 灰度 + eb 判定位）
//   lb1 写 I_gray@ram_addr（读旧值=上一行同列）
//   lb2 写 p1@addr_d1（再下沉一行）；lb3 写 p2@addr_d2（第三历史行）
module edge_adaptive_pixel #(
    parameter IMG_WIDTH = 1280,
    parameter [10:0] THR_FLOOR = 11'd16
)(
    input  wire        I_clk,
    input  wire        I_rst_n,
    input  wire        I_valid,      // 像素有效
    input  wire        I_sync,       // 行首（每行第一拍拉高）
    input  wire [7:0]  I_gray,       // 灰度，外部已做 R/4+G/2+B/4
    input  wire [1:0]  I_k,          // 亮度灵敏度档 0..3
    output reg         O_valid,
    output reg         O_edge,       // 1=边缘(白) 0=非边缘(黑)
    output reg  [12:0] O_mag         // 梯度幅值（与 O_edge 同拍输出）
);

    // ---------------- 行缓存地址生成 ----------------
    reg  [10:0] wr_ptr;
    reg  [10:0] addr_d1, addr_d2;
    reg  [9:0]  row_cnt;

    wire [10:0] ram_addr = I_sync ? 11'd0 : wr_ptr;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            wr_ptr  <= 11'd0;
            addr_d1 <= 11'd0;
            addr_d2 <= 11'd0;
            row_cnt <= 10'd0;
        end else if (I_valid) begin
            wr_ptr  <= ram_addr + 11'd1;
            addr_d1 <= ram_addr;
            addr_d2 <= addr_d1;
            row_cnt <= I_sync ? (row_cnt + 10'd1) : row_cnt;
        end
    end

    // ---------------- 行缓存：4 块块 RAM ----------------
    (* keep = "true" *) wire [31:0] S_lb1_dout;
    (* keep = "true" *) wire [31:0] S_lb2_dout;
    (* keep = "true" *) wire [31:0] S_lb3_dout;
    (* keep = "true" *) wire [31:0] S_eb_dout;

    (* keep = "true" *) wire [7:0]  p1    = S_lb1_dout[7:0];   // 上一行同列
    (* keep = "true" *) wire [7:0]  p2    = S_lb2_dout[7:0];   // 上上行同列
    (* keep = "true" *) wire [7:0]  p3    = S_lb3_dout[7:0];   // 上上上行同列
    (* keep = "true" *) wire        eb_rd = S_eb_dout[0];
    reg         eb_d1, eb_d2;

    blk_mem_gen_zhenghe u_lb1 (
        .clka(I_clk), .wea(1'b0),    .addra(ram_addr), .dia(32'd0),
        .clkb(I_clk), .web(I_valid), .addrb(ram_addr), .dib({24'd0, I_gray}),
        .doa(S_lb1_dout), .dob()
    );

    blk_mem_gen_zhenghe u_lb2 (
        .clka(I_clk), .wea(1'b0),    .addra(ram_addr), .dia(32'd0),
        .clkb(I_clk), .web(I_valid), .addrb(ram_addr),  .dib({24'd0, p1}),
        .doa(S_lb2_dout), .dob()
    );

    blk_mem_gen_zhenghe u_lb3 (
        .clka(I_clk), .wea(1'b0),    .addra(ram_addr), .dia(32'd0),
        .clkb(I_clk), .web(I_valid), .addrb(ram_addr),  .dib({24'd0, p2}),
        .doa(S_lb3_dout), .dob()
    );

    blk_mem_gen_zhenghe u_eb (
        .clka(I_clk), .wea(1'b0),    .addra(ram_addr), .dia(32'd0),
        .clkb(I_clk), .web(I_valid), .addrb(addr_d2),  .dib({31'd0, O_edge}),
        .doa(S_eb_dout), .dob()
    );

    // ---------------- 4 行 × 5 列窗口（每行 5 级移位链，c0 最新） ----------------
    reg [7:0] c0, c1, c2, c3, c4;    // 当前行：col / col-1 / col-2 / col-3 / col-4
    reg [7:0] r0, r1, r2, r3, r4;    // 上一行
    reg [7:0] q0, q1, q2, q3, q4;    // 上上行
    reg [7:0] z0, z1, z2, z3, z4;    // 上上上行
    reg [7:0] in_d1;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            c0<=8'd0; c1<=8'd0; c2<=8'd0; c3<=8'd0; c4<=8'd0;
            r0<=8'd0; r1<=8'd0; r2<=8'd0; r3<=8'd0; r4<=8'd0;
            q0<=8'd0; q1<=8'd0; q2<=8'd0; q3<=8'd0; q4<=8'd0;
            z0<=8'd0; z1<=8'd0; z2<=8'd0; z3<=8'd0; z4<=8'd0;
            in_d1  <= 8'd0;
            eb_d1  <= 1'b0;
            eb_d2  <= 1'b0;
        end else if (I_valid) begin
            in_d1 <= I_gray;
            if (I_sync) begin
                // 行首清链：5 级链要 5 拍才填满，否则上一行末尾数据搬进本行开头
                {c4,c3,c2,c1,c0} <= 40'd0;
                {r4,r3,r2,r1,r0} <= 40'd0;
                {q4,q3,q2,q1,q0} <= 40'd0;
                {z4,z3,z2,z1,z0} <= 40'd0;
            end else begin
                {c4,c3,c2,c1,c0} <= {c3,c2,c1,c0, in_d1};
                {r4,r3,r2,r1,r0} <= {r3,r2,r1,r0, p1};
                {q4,q3,q2,q1,q0} <= {q3,q2,q1,q0, p2};
                {z4,z3,z2,z1,z0} <= {z3,z2,z1,z0, p3};
            end
            eb_d1 <= eb_rd;
            eb_d2 <= eb_d1;
        end
    end

    // ---------------- 每行 3 列滑动和 + 4 个 3×3 和 ----------------
    (* keep = "true" *) wire [10:0] c3_0 = {2'b00,c4}+{2'b00,c3}+{2'b00,c2}, c3_1 = {2'b00,c3}+{2'b00,c2}+{2'b00,c1}, c3_2 = {2'b00,c2}+{2'b00,c1}+{2'b00,c0};
    (* keep = "true" *) wire [10:0] r3_0 = {2'b00,r4}+{2'b00,r3}+{2'b00,r2}, r3_1 = {2'b00,r3}+{2'b00,r2}+{2'b00,r1}, r3_2 = {2'b00,r2}+{2'b00,r1}+{2'b00,r0};
    (* keep = "true" *) wire [10:0] q3_0 = {2'b00,q4}+{2'b00,q3}+{2'b00,q2}, q3_1 = {2'b00,q3}+{2'b00,q2}+{2'b00,q1}, q3_2 = {2'b00,q2}+{2'b00,q1}+{2'b00,q0};
    (* keep = "true" *) wire [10:0] z3_0 = {2'b00,z4}+{2'b00,z3}+{2'b00,z2}, z3_1 = {2'b00,z3}+{2'b00,z2}+{2'b00,z1}, z3_2 = {2'b00,z2}+{2'b00,z1}+{2'b00,z0};

    (* keep = "true" *) wire [12:0] s1 = {2'b00,q3_2}+{2'b00,r3_2}+{2'b00,c3_2};
    (* keep = "true" *) wire [12:0] s2 = {2'b00,q3_0}+{2'b00,r3_0}+{2'b00,c3_0};
    (* keep = "true" *) wire [12:0] s3 = {2'b00,q3_1}+{2'b00,r3_1}+{2'b00,c3_1};
    (* keep = "true" *) wire [12:0] s4 = {2'b00,z3_1}+{2'b00,q3_1}+{2'b00,r3_1};

    wire [12:0] a1 = (s1 >= s2) ? (s1 - s2) : (s2 - s1);
    wire [12:0] a2 = (s3 >= s4) ? (s3 - s4) : (s4 - s3);
    (* keep = "true" *) wire [12:0] mag = a1 + a2;               // <= 4554

    // ---------------- 自适应阈值：thr = FLOOR + ((mean9 * K) >> 5) ----------------
    wire [11:0] mean9 = s3 >> 3;

    wire [12:0] mk = (I_k == 2'd0) ? 13'd0              :
                     (I_k == 2'd1) ? {1'b0, mean9}      :
                     (I_k == 2'd2) ? {mean9, 1'b0}      :
                                     ({mean9, 1'b0} + {1'b0, mean9});

    wire [12:0] thr_high = {2'b00, THR_FLOOR} + (mk >> 5);
    wire [12:0] thr_low  = thr_high >> 1;

    // ---------------- 因果双阈值迟滞 ----------------
    wire is_strong = (mag >= thr_high);
    wire is_weak   = (mag >= thr_low);
    wire neighbor  = O_edge | eb_d1 | eb_d2;

    // 窗口有效：4 行缓存冷启动需 4 行 + 5 级链需 5 拍 + 判决锚 col-2
    (* keep = "true" *) wire win_valid = (row_cnt >= 10'd6) && (ram_addr >= 11'd6);

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            O_edge  <= 1'b0;
            O_valid <= 1'b0;
            O_mag   <= 13'd0;
        end else begin
            O_valid <= I_valid;
            O_edge  <= win_valid & (is_strong | (is_weak & neighbor));
            O_mag   <= win_valid ? mag : 13'd0;
        end
    end

endmodule