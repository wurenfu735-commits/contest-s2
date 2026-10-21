// 顶层：测试图 + 边缘检测四态显示 + HDMI 输出
// 时钟：板载 50M(C4) -> PLL 输出 74.25M(像素)、371.25M(串行)
// 数据流：vtc_720p 行场时序 -> test_pattern_gen 图案 -> edge_rgb_adapter（灰度+边缘检测）-> hdmi_tx -> TMDS
//
// 按键：KEY1(D5) 切图案（彩条/棋盘/渐变/灰阶）；KEY2(A9) 循环切显示模式
//       模式：0=原图直通  1=官方判决(固定阈值80)  2=我们的判决(自适应阈值+迟滞)  3=左右分屏(左官方/右我们)
// LED ：LED1/LED2 = KEY1/KEY2 按下指示（亮 0.2s）；LED3/LED4 = 当前显示模式编号
// hdmi_tx 来自官方例程，音频/EDID 均不使用接 0
module colorbar_top (
    input  wire       I_sys_clk,
    input  wire       I_rst_n,
    input  wire [1:0] I_button,
    output wire [3:0] O_led,
    output wire       O_screen_pwm,
    output wire       O_tmds_ch0_p,
    output wire       O_tmds_ch1_p,
    output wire       O_tmds_ch2_p,
    output wire       O_tmds_clk_p
);

    wire        S_pll_lock;
    wire        S_hdmi_pixel_clk;
    wire        S_hdmi_serial_clk;
    wire        S_hsync, S_vsync, S_de;
    wire [11:0] S_hcnt, S_vcnt;
    wire [23:0] S_rgb_tpg;
    wire [23:0] S_rgb_out;
    wire        S_out_de, S_out_vs;
    wire        S_btn0_press, S_btn1_press;
    reg  [2:0]  S_pattern_sel;        // 3 位：8 种图案
    reg  [1:0]  S_disp_mode;          // 0=原图 1=官方判决 2=我们的判决 3=左右分屏
    wire [1:0]  S_k_level;

    assign O_screen_pwm = 1'b1;
    assign S_k_level    = 2'd2;       // 灵敏度档暂固定为 2，后续接按键在线调参

    // PLL：IP 生成件，50M 进，clk4=74.25M、clk5=371.25M；clk0/clk1 本设计不用
    PLL u_PLL(
        .refclk   ( I_sys_clk         ),
        .reset    ( ~I_rst_n          ),
        .clk0_out (                   ),
        .clk1_out (                   ),
        .clk4_out ( S_hdmi_pixel_clk  ),
        .clk5_out ( S_hdmi_serial_clk ),
        .lock     ( S_pll_lock        )
    );

    debounce_btn u_dbtn0(
        .I_clk   ( S_hdmi_pixel_clk ),
        .I_rst_n ( I_rst_n          ),
        .I_btn   ( I_button[0]      ),
        .O_press ( S_btn0_press     )
    );
    debounce_btn u_dbtn1(
        .I_clk   ( S_hdmi_pixel_clk ),
        .I_rst_n ( I_rst_n          ),
        .I_btn   ( I_button[1]      ),
        .O_press ( S_btn1_press     )
    );

    // KEY1 循环切图案（8 种，3 位自然回绕）
    always @(posedge S_hdmi_pixel_clk or negedge I_rst_n) begin
        if (!I_rst_n)
            S_pattern_sel <= 3'd0;
        else if (S_btn0_press)
            S_pattern_sel <= S_pattern_sel + 1'd1;
    end

    // KEY2 循环切显示模式
    always @(posedge S_hdmi_pixel_clk or negedge I_rst_n) begin
        if (!I_rst_n)
            S_disp_mode <= 2'd0;              // 上电默认显示原图
        else if (S_btn1_press)
            S_disp_mode <= S_disp_mode + 1'd1;
    end

    // 按键指示：按下时对应 LED 亮 0.2s
    localparam LED_HOLD = 24'd14_850_000;      // 0.2s @ 74.25MHz
    reg [23:0] S_led0_cnt;
    reg [23:0] S_led1_cnt;

    always @(posedge S_hdmi_pixel_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            S_led0_cnt <= 24'd0;
            S_led1_cnt <= 24'd0;
        end else begin
            if (S_btn0_press)         S_led0_cnt <= LED_HOLD;
            else if (S_led0_cnt != 0) S_led0_cnt <= S_led0_cnt - 1'd1;

            if (S_btn1_press)         S_led1_cnt <= LED_HOLD;
            else if (S_led1_cnt != 0) S_led1_cnt <= S_led1_cnt - 1'd1;
        end
    end

    assign O_led[0] = (S_led0_cnt != 24'd0);
    assign O_led[1] = (S_led1_cnt != 24'd0);
    assign O_led[2] = S_disp_mode[1];          // 显示模式编号（00原图/01官方/10我们/11分屏）
    assign O_led[3] = S_disp_mode[0];

    vtc_720p u_vtc(
        .I_clk    ( S_hdmi_pixel_clk ),
        .I_rst_n  ( I_rst_n          ),
        .O_hsync  ( S_hsync          ),
        .O_vsync  ( S_vsync          ),
        .O_de     ( S_de             ),
        .O_hcnt   ( S_hcnt           ),
        .O_vcnt   ( S_vcnt           )
    );

    test_pattern_gen u_tpg(
        .I_clk         ( S_hdmi_pixel_clk ),
        .I_rst_n       ( I_rst_n          ),
        .I_de          ( S_de             ),
        .I_hcnt        ( S_hcnt           ),
        .I_vcnt        ( S_vcnt           ),
        .I_pattern_sel ( S_pattern_sel    ),
        .I_pll_lock    ( S_pll_lock       ),
        .O_rgb         ( S_rgb_tpg        )
    );

    edge_rgb_adapter #(
        .IMG_WIDTH (1280)
    ) u_edge_adapter (
        .I_clk   ( S_hdmi_pixel_clk ),
        .I_rst_n ( I_rst_n          ),
        .I_de    ( S_de             ),
        .I_vs    ( S_vsync          ),
        .I_hcnt  ( S_hcnt           ),
        .I_rgb   ( S_rgb_tpg        ),
        .I_mode  ( S_disp_mode      ),
        .I_k     ( S_k_level        ),
        .O_de    ( S_out_de         ),
        .O_vs    ( S_out_vs         ),
        .O_rgb   ( S_rgb_out        )
    );

    hdmi_tx u_hdmi_tx(
        .I_pixel_clk        ( S_hdmi_pixel_clk  ),
        .I_serial_clk       ( S_hdmi_serial_clk ),
        .I_rst              ( ~I_rst_n          ),
        .I_key_in           ( 1'b0              ),
        .I_edid_read_trig   ( 1'b0              ),
        .O_edid_read_valid  (                   ),
        .O_edid_read_data   (                   ),
        .I_video_rgb_enable ( 1'b1              ),
        .I_video_in_vs      ( S_out_vs          ),
        .I_video_in_de      ( S_out_de          ),
        .I_video_in_user    ( 1'b0              ),
        .I_video_in_valid   ( 1'b0              ),
        .I_video_in_last    ( 1'b0              ),
        .O_video_in_ready   (                   ),
        .I_video_in_data    ( S_rgb_out         ),
        .I_audio_valid      ( 1'b0              ),
        .I_audio_left_data  ( 24'd0             ),
        .I_audio_right_data ( 24'd0             ),
        .I_i2s_BCLK         ( 1'b0              ),
        .I_i2s_LRCK         ( 1'b0              ),
        .I_i2s_DOUT         ( 1'b0              ),
        .O_ddc_scl          (                   ),
        .O_hdmi_clk_p       (                   ),
        .O_hdmi_tx_p        (                   ),
        .O_tmds_ch0_p       ( O_tmds_ch0_p      ),
        .O_tmds_ch1_p       ( O_tmds_ch1_p      ),
        .O_tmds_ch2_p       ( O_tmds_ch2_p      ),
        .O_tmds_clk_p       ( O_tmds_clk_p      )
    );

endmodule
