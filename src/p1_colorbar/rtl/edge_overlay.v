// 边缘叠加模块（独立标准模块，借鉴开源 rgb_merger / mask_processor 的设计）
// ============================================================================
// 职责：把「边缘检测结果」叠加到「原图」上。原图延迟链是**本模块的数据通路**
//   （类似 rgb_merger 的 r_reg 打拍），不是旁挂，因此不会被综合器优化删除。
//
// 模式：
//   I_mode == 4（边缘叠加）：mag != 0 处显示梯度灰阶（强边亮/弱边暗），否则透出原图
//   I_mode != 4（官方/我们/分屏）：透传二值图 I_edge（黑底白线，与官方对照）
//
// 延迟对齐（关键，勿改拍数）：
//   - edge 输出的 O_tdata/O_mag 数据延迟 3 拍（判决锚定 x_d2=2 拍 + 输出寄存 1 拍）
//   - 原图 I_orig 用 I_orig_valid（awb 原始 valid）门控延迟 3 拍 → orig_d3 与 I_edge/I_mag 同拍
//   - 输出 O_data/O_valid 各寄存 1 拍，两者相对延迟不变，下游 data96_128 正确打包
//
// 资源：原图 3 级延迟链 288 FF + mux ~100 LUT，0 ERAM / 0 DSP。
module edge_overlay (
    input  wire        I_clk,
    input  wire        I_rst_n,
    // 原图（awb 直通，0 拍）
    input  wire [95:0] I_orig,
    input  wire        I_orig_valid,
    // 边缘二值图 + 梯度灰阶（edge 输出，数据延迟 3 拍）
    input  wire [95:0] I_edge,
    input  wire [31:0] I_mag,     // 4 像素 × 8bit 梯度灰阶，[7:0]=第1像素 … [31:24]=第4像素
    input  wire [2:0]  I_mode,    // 4=边缘叠加，其他=二值图透传
    // edge 输出的控制信号（与 I_edge/I_mag 同拍）
    input  wire        I_edge_valid,
    input  wire        I_edge_last,
    input  wire        I_edge_user,
    // 输出（叠加结果）
    output reg  [95:0] O_data,
    output reg         O_valid,
    output reg         O_last,
    output reg         O_user
);

    // ---- 原图延迟链（I_orig_valid 门控，对齐 edge 数据的 3 拍延迟）----
    (* keep = "true" *) reg [95:0] orig_d1, orig_d2, orig_d3;
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            orig_d1 <= 96'd0;
            orig_d2 <= 96'd0;
            orig_d3 <= 96'd0;
        end else if (I_orig_valid) begin
            orig_d1 <= I_orig;
            orig_d2 <= orig_d1;
            orig_d3 <= orig_d2;
        end
    end

    // ---- 叠加 mux ----
    // mode 4：梯度灰阶 != 0（有边缘）→ 显示梯度灰阶；== 0（非边缘）→ 透出原图
    // 其他 mode：透传二值图
    wire        ov_en   = (I_mode == 3'd4);
    wire [7:0]  mag0    = I_mag[7:0];
    wire [7:0]  mag1    = I_mag[15:8];
    wire [7:0]  mag2    = I_mag[23:16];
    wire [7:0]  mag3    = I_mag[31:24];

    wire [23:0] p0 = ov_en ? (mag0 != 8'd0 ? {mag0, mag0, mag0} : orig_d3[95:72]) : I_edge[95:72];
    wire [23:0] p1 = ov_en ? (mag1 != 8'd0 ? {mag1, mag1, mag1} : orig_d3[71:48]) : I_edge[71:48];
    wire [23:0] p2 = ov_en ? (mag2 != 8'd0 ? {mag2, mag2, mag2} : orig_d3[47:24]) : I_edge[47:24];
    wire [23:0] p3 = ov_en ? (mag3 != 8'd0 ? {mag3, mag3, mag3} : orig_d3[23:0])  : I_edge[23:0];

    // ---- 输出寄存（与输入 valid 同拍对齐，整体 +1 拍）----
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            O_data  <= 96'd0;
            O_valid <= 1'b0;
            O_last  <= 1'b0;
            O_user  <= 1'b0;
        end else begin
            O_data  <= {p0, p1, p2, p3};
            O_valid <= I_edge_valid;
            O_last  <= I_edge_last;
            O_user  <= I_edge_user;
        end
    end

endmodule
