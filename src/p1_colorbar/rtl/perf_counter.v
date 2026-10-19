// ============================================================================
// perf_counter.v  ——  运行时性能计数器（帧率 / 总帧数 / MIPI 错误累计）
//
// 为什么有它（对应赛题）：
//   - 2.6 评分第 4 条「系统稳定性」要证据：帧率稳不稳、丢帧多少、错误多少
//   - 高阶挑战③「处理延迟可视化」要 fps 数据
//   - 扩展④「性能优化」要优化前后帧率对比
//   当前 design_top 把 video_in.I_mipi_rx_error 硬接 1'b0（假健康），本模块顺便
//   把 mipi_rx_error 接进来累计，让"0 错误"是真的 0。
//
// 时钟域：HDMI_PIXEL_CLK（74.25MHz），OSD 同域，输出直接给显示用无需再跨域。
//   mipi_rx_error 来自 csi_rx_clk（~103.52MHz）域，内部 2 级 FF 同步 + 上升沿检测。
//
// 资源预估：~120 LUT + ~90 FF · 0 DSP · 0 ERAM（74.25M 域纯计数，无窗口无乘法）
//
// 接入（等 td.exe 退出后做，本轮不动 .al）：
//   1) .al 在 System_Verilog 段加本文件
//   2) design_top 例化本模块：I_vsync 接 S_video_out_vsync（或 S_hdmi_vsync）
//      I_mipi_rx_error 接 mipi_rx_error_detect 的 O_mipi_rx_error（需先例化 detect 模块）
//   3) O_err_flag 接 LED（D10/E10/C6/D6 任一）
//   4) O_frame_cnt / O_fps / O_err_cnt 留给 T3「指标上屏」接 osd_overlay
// ============================================================================
`timescale 1ns / 1ps

module perf_counter #(
    parameter CLK_HZ = 74_250_000   // 本模块工作时钟频率（HDMI_PIXEL_CLK）
)(
    input  wire        I_clk,            // 74.25MHz
    input  wire        I_rst_n,          // 同步复位，低有效
    input  wire        I_vsync,          // 帧脉冲（本域，已同步到 I_clk）
    input  wire        I_mipi_rx_error,  // 异步（来自 csi_rx_clk 域），内部做 CDC

    output wire [31:0]  O_frame_cnt,      // 总帧数（不归零，溢出回绕）
    output wire [7:0]   O_fps,            // 每秒帧数（1 秒滚动窗口锁存）
    output wire [15:0]  O_err_cnt,       // MIPI 错误累计
    output wire        O_err_flag        // 错误发生过（latch，给 LED）
);

    // ---- 1 秒计时器 ----
    reg [26:0] sec_cnt;            // 0..CLK_HZ-1，2^27=134M 够装 74.25M
    wire       sec_tick = (sec_cnt == CLK_HZ - 1);

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n)            sec_cnt <= 27'd0;
        else if (sec_tick)       sec_cnt <= 27'd0;
        else                     sec_cnt <= sec_cnt + 27'd1;
    end

    // ---- vsync 上升沿检测（帧脉冲）----
    reg        vsync_1d;
    wire       vsync_rise = I_vsync & ~vsync_1d;

    // ---- 本秒帧数 + 锁存 fps + 总帧数 ----
    reg [7:0]  fps_cnt;          // 本秒内的帧数
    reg [7:0]  fps_latch;        // 满秒时锁存，给显示
    reg [31:0] frame_cnt;        // 总帧数

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            vsync_1d  <= 1'b0;
            fps_cnt   <= 8'd0;
            fps_latch <= 8'd0;
            frame_cnt <= 32'd0;
        end
        else begin
            vsync_1d <= I_vsync;
            if (sec_tick) begin
                fps_latch <= fps_cnt;     // 锁存上一秒的帧数
                fps_cnt   <= 8'd0;
            end
            else if (vsync_rise) begin
                fps_cnt <= fps_cnt + 8'd1;
            end
            if (vsync_rise)
                frame_cnt <= frame_cnt + 32'd1;
        end
    end

    // ---- mipi_rx_error CDC：2 级 FF 同步 + 上升沿检测 + 累计 ----
    reg        err_sync_1d;
    reg        err_sync_2d;
    reg        err_2d;            // 用于沿检测
    reg [15:0] err_cnt;
    wire       err_rise = err_sync_2d & ~err_2d;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            err_sync_1d <= 1'b0;
            err_sync_2d <= 1'b0;
            err_2d      <= 1'b0;
            err_cnt     <= 16'd0;
        end
        else begin
            err_sync_1d <= I_mipi_rx_error;
            err_sync_2d <= err_sync_1d;
            err_2d      <= err_sync_2d;
            if (err_rise)
                err_cnt <= err_cnt + 16'd1;
        end
    end

    assign O_frame_cnt = frame_cnt;
    assign O_fps       = fps_latch;
    assign O_err_cnt   = err_cnt;
    assign O_err_flag  = (err_cnt != 16'd0);

endmodule
