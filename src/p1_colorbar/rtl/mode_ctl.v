// 按键模式控制器（运行在 HDMI 像素时钟域 74.25MHz）
//
// 职责：
//   1. 4 路按键消抖（复用 debounce_btn：低有效、两级同步 + 1kHz 采样 + 20ms 稳定）
//   2. KEY1 循环切换显示模式 O_mode（0→1→2→3→4→0，共 5 态）
//      0 原图 / 1 官方判决 / 2 我们的判决 / 3 左右分屏 / 4 边缘叠加原图（P1 新增）
//   3. KEY2 循环切换灵敏度档 O_k（0→1→2→3→0）
//   4. KEY3 一键复位模式到默认 2（我们的判决）；KEY4 一键复位灵敏度到默认 2
//
// 为什么放在 74.25MHz 域：
//   - PLL 派生时钟，频率精确稳定、不依赖摄像头（摄像头未就绪按键也能工作）
//   - OSD 也在本域，模式号可直接送 OSD 显示，无跨域
//   - 跨域只发生在「模式值 → 算法域」，由 cdc_mode_sync 用独热码 + 帧锁存处理
//
// 资源：4 个消抖 ≈ 200 LUT / 250 FF；模式寄存器几个 FF。0 DSP / 0 ERAM。
module mode_ctl #(
    parameter CLK_FREQ   = 74_250_000,
    parameter STABLE_CNT = 20
)(
    input  wire        I_clk,
    input  wire        I_rst_n,
    input  wire [3:0]  I_btn,     // 板载 KEY1~4，按下为低电平
    output reg  [2:0]  O_mode,    // 5 态：0 原图 / 1 官方 / 2 我们 / 3 分屏 / 4 边缘叠加
    output reg  [1:0]  O_k        // 灵敏度档 0..3
);

    wire [3:0] press;

    // 4 路消抖，各输出一拍按下脉冲（高有效）；参数透传便于 tb 用小值快速仿真
    debounce_btn #(.CLK_FREQ(CLK_FREQ), .STABLE_CNT(STABLE_CNT)) u_db_key1 (.I_clk(I_clk), .I_rst_n(I_rst_n), .I_btn(I_btn[0]), .O_press(press[0]));
    debounce_btn #(.CLK_FREQ(CLK_FREQ), .STABLE_CNT(STABLE_CNT)) u_db_key2 (.I_clk(I_clk), .I_rst_n(I_rst_n), .I_btn(I_btn[1]), .O_press(press[1]));
    debounce_btn #(.CLK_FREQ(CLK_FREQ), .STABLE_CNT(STABLE_CNT)) u_db_key3 (.I_clk(I_clk), .I_rst_n(I_rst_n), .I_btn(I_btn[2]), .O_press(press[2]));
    debounce_btn #(.CLK_FREQ(CLK_FREQ), .STABLE_CNT(STABLE_CNT)) u_db_key4 (.I_clk(I_clk), .I_rst_n(I_rst_n), .I_btn(I_btn[3]), .O_press(press[3]));

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            O_mode <= 3'd2;   // 默认「我们的判决」，与历史行为一致
            O_k    <= 2'd2;
        end else begin
            // KEY1 循环切模式（0→1→2→3→4→0）；KEY3 兜底复位到默认
            if (press[0])      O_mode <= (O_mode == 3'd4) ? 3'd0 : O_mode + 3'd1;
            else if (press[2]) O_mode <= 3'd2;
            // KEY2 循环切灵敏度；KEY4 兜底复位到默认
            if (press[1])      O_k <= (O_k == 2'd3) ? 2'd0 : O_k + 1'd1;
            else if (press[3]) O_k <= 2'd2;
        end
    end

endmodule
