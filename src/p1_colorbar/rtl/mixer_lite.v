// ============================================================================
// mixer_lite.v  ——  轻量像素混合器（替代官方 hdmi_mixer 的"非 OSD"部分）
//
// 为什么需要它（2026-10-19 完整跑 syn+phy 实测）：
//   官方 hdmi_mixer.v（909 行）内部无条件例化 anlogic_logo_rom（6,387 条 × 25bit 的
//   组合 ROM），实测这一个位图就占 2,340 LUT / 2,325 slice / 1 DSP / 0.554ns Setup 余量
//   —— 是全片的 10.96%。它把"最缺的 LUT 用来存位图，最富余的 ERAM 空着"。
//
//   而官方 hdmi_mixer 去掉 OSD 逻辑后只剩三件事：
//     1) O_video_rd_en = I_video_de            （官方原文就这一行）
//     2) vsync/hsync/de/data 各打 3 拍          （官方 1d/2d/输出 三级）
//     3) 把 OSD 叠上去                          （← 这一件交给 rtl/osd_overlay.v）
//   本模块只做 1) 2)，第 3 件由 osd_overlay.v 完成（Logo 用 2bit/像素的品牌双色 ROM）。
//
// 合规性：
//   * 不修改、不删除任何官方文件；官方 hdmi_mixer.v / anlogic_logo_rom.v 原样留在工程里
//   * 本模块是自研代码，顶层"不再例化"官方 hdmi_mixer，属于顶层连线范围
//   * Logo 位图数据仍来自官方 anlogic_logo_rom.v 的同一份素材（重新量化为品牌两色）
//   * 官方加密 IP（hdmi_1_4b_transmitter_core_wrapper.enc.v、mipi_dphy_rx/*.enc.*）未动
//
// 时序契约（必须与官方一致，否则 osd_overlay 的坐标会错）：
//   官方 mixer 对 vs/hs/de/data 的输出延迟都是 3 个 I_clk（1d → 2d → 输出寄存器），
//   本模块逐拍照抄，保证 osd_overlay 收到的信号相对关系与原来完全相同。
// ============================================================================
`timescale 1ns / 1ps

module mixer_lite (
    input  wire        I_clk,
    input  wire        I_rst_n,

    // 来自 vtc 的视频时序
    input  wire        I_video_vsync,
    input  wire        I_video_hsync,
    input  wire        I_video_de,
    input  wire        I_video_user,      // 保留端口，本模块不使用（官方 mixer 只用于 OSD 坐标复位）
    input  wire        I_video_last,      // 同上

    // 从 DDR 读回的像素
    output wire        O_video_rd_en,
    input  wire [23:0] I_video_rd_data,

    // 送 hdmi_tx（后面再接 osd_overlay）
    output reg         O_hdmi_vsync,
    output reg         O_hdmi_hsync,
    output reg         O_hdmi_de,
    output reg  [23:0] O_hdmi_data
);

    // ---- 1) 读使能：与官方完全一致（组合直通，不打拍）----
    assign O_video_rd_en = I_video_de;

    // ---- 2) 三级延迟，逐拍对齐官方 ----
    reg        S_vs_1d, S_vs_2d;
    reg        S_hs_1d, S_hs_2d;
    reg        S_de_1d, S_de_2d;
    reg [23:0] S_dt_1d, S_dt_2d;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            S_vs_1d <= 1'b0;  S_vs_2d <= 1'b0;  O_hdmi_vsync <= 1'b0;
            S_hs_1d <= 1'b0;  S_hs_2d <= 1'b0;  O_hdmi_hsync <= 1'b0;
            S_de_1d <= 1'b0;  S_de_2d <= 1'b0;  O_hdmi_de    <= 1'b0;
            S_dt_1d <= 24'd0; S_dt_2d <= 24'd0; O_hdmi_data  <= 24'd0;
        end
        else begin
            S_vs_1d <= I_video_vsync;
            S_vs_2d <= S_vs_1d;
            O_hdmi_vsync <= S_vs_2d;

            S_hs_1d <= I_video_hsync;
            S_hs_2d <= S_hs_1d;
            O_hdmi_hsync <= S_hs_2d;

            S_de_1d <= I_video_de;
            S_de_2d <= S_de_1d;
            O_hdmi_de <= S_de_2d;

            S_dt_1d <= I_video_rd_data;
            S_dt_2d <= S_dt_1d;
            O_hdmi_data <= S_dt_2d;
        end
    end

    // 未用端口：显式引用一次，避免"未使用"告警干扰日志判读
    wire S_unused = I_video_user ^ I_video_last;

endmodule
