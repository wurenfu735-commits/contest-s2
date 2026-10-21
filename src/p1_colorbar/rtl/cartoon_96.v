// ============================================================================
// cartoon_96.v  ——  卡通化（风格化/视觉增强，赛题扩展①）
//
// 为什么有它：
//   原 mode 4「边缘叠加」效果差（叠加不明显/疑似 bug）。改为卡通化——
//   把边缘**融进**彩色画面（而不是叠一层），既是更好的视觉呈现，又是扩展①得分项。
//
// 算法（成熟做法，两步）：
//   1) 颜色量化：RGB 每通道取高 QBITS 位（默认 3 → 8 级/通道 = 512 色），低位清零
//      → 色块平滑，去掉噪点与渐变，得到"动画风"平涂色块
//   2) 边缘压黑：边缘像素输出纯黑 → 卡通描边效果
//   复用已有边缘（algo_tdata 二值图），不新开窗口/ERAM
//
// 成本：~50-100 LUT（纯位操作 + mux）· 0 ERAM · 0 DSP
//
// 延迟对齐（关键，勿改拍数 —— 照搬 edge_overlay 的做法）：
//   - 算法（edge/morph）输出的 O_tdata/O_valid 数据延迟 3 拍（寄存器级）
//   - 原图 I_orig 用 I_orig_valid 门控延迟 3 拍 → orig_d3 与 I_edge/I_valid 同拍
//   - 输出 O_tdata/O_valid 各寄存 1 拍，整体 +1 拍；下游 data96_128 正确打包
// ============================================================================
`timescale 1ns / 1ps

module cartoon_96 #(
    parameter QBITS = 3            // 量化位数：3 = 每通道 8 级（512 色）
)(
    input  wire        I_clk,
    input  wire        I_rst_n,

    input  wire [95:0] I_orig,      // 原图：4 像素 RGB888（[95:72]=第1个 … [23:0]=第4个）
    input  wire        I_orig_valid,// 原图侧 valid（awb_O_tvalid），用于推进原图延迟链
    input  wire [95:0] I_edge,      // 边缘二值图（算法输出，数据已延迟 3 拍）：边缘=全 1，非边=全 0
    input  wire        I_valid,     // 边缘侧 valid（算法 valid，已延迟 3 拍），用于输出门控
    input  wire        I_last,
    input  wire        I_user,

    output reg  [95:0] O_tdata,
    output reg         O_valid,
    output reg         O_last,
    output reg         O_user
);

    // ---- 原图延迟链（I_orig_valid 门控，对齐算法输出的 3 拍延迟）----
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

    // ---- 单像素卡通化：量化 + 边缘压黑 ----
    function [23:0] cartoon_pix;
        input [23:0] orig;
        input [23:0] edge_px;
        reg [7:0] rq, gq, bq;
        begin
            // 量化：取高 QBITS 位，低位清零（QBITS=3 → {R[7:5], 5'b0}）
            rq = {orig[23:(24-QBITS)], {(8-QBITS){1'b0}}};
            gq = {orig[15:(16-QBITS)], {(8-QBITS){1'b0}}};
            bq = {orig[ 7:( 8-QBITS)], {(8-QBITS){1'b0}}};
            // 边缘压黑（二值图非 0 即边缘）
            if (edge_px != 24'd0)
                cartoon_pix = 24'h000000;
            else
                cartoon_pix = {rq, gq, bq};
        end
    endfunction

    // 用对齐后的 orig_d3（与 I_edge 同拍）做卡通化
    wire [23:0] pix0 = orig_d3[95:72];
    wire [23:0] pix1 = orig_d3[71:48];
    wire [23:0] pix2 = orig_d3[47:24];
    wire [23:0] pix3 = orig_d3[23:0];

    wire [23:0] edge0 = I_edge[95:72];
    wire [23:0] edge1 = I_edge[71:48];
    wire [23:0] edge2 = I_edge[47:24];
    wire [23:0] edge3 = I_edge[23:0];

    (* keep = "true" *) wire [23:0] c0 = cartoon_pix(pix0, edge0);
    (* keep = "true" *) wire [23:0] c1 = cartoon_pix(pix1, edge1);
    (* keep = "true" *) wire [23:0] c2 = cartoon_pix(pix2, edge2);
    (* keep = "true" *) wire [23:0] c3 = cartoon_pix(pix3, edge3);

    // ---- 输出寄存（与输入 valid 同拍对齐，整体 +1 拍）----
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            O_tdata <= 96'd0;
            O_valid <= 1'b0;
            O_last  <= 1'b0;
            O_user  <= 1'b0;
        end else begin
            O_tdata <= {c0, c1, c2, c3};
            O_valid <= I_valid;
            O_last  <= I_last;
            O_user  <= I_user;
        end
    end

endmodule
