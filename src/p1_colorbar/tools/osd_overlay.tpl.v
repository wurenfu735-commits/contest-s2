// ============================================================================
// osd_overlay.v  ——  自研 OSD 叠加（B4：叠加图形/文字信息，含“安路”标识 Logo）
// ----------------------------------------------------------------------------
// 插入位置：hdmi_mixer 之后、hdmi_tx 之前（像素域，74.25MHz）。
//   禁止插进 isp_top：那里的数据还要过自研算法，Logo 会被边缘化/卡通化。
//
// 功能（只做赛题基础要求第 4 条，不含模式切换等扩展）：
//   1) 左上角一块浅灰底 + 深蓝描边的小面板（保证黑白边缘图、彩色原图上都看得清）
//   2) 面板内绘制“安路”标识 Logo（146x94，数据取自官方例程位图，重编码为 2bit/像素）
//   3) 面板内两行 5x7 点阵文字：line0 = "ANLOGIC"，line1 = "PH1P35 720P"
//
// 与官方 lab_ex3 OSD 的差异（答辩用）：
//   官方：整像素硬替换、位置写死、无底板、只有计数器；混在 hdmi_mixer 里（2300+ LUT）
//   我们：独立模块、坐标/尺寸全参数化、自建 2bit Logo ROM + 自建 5x7 字模 +
//         底板/描边保证任意背景下可读、单周期流水（约 1/5 资源）
//
// 时序：所有输出相对输入延迟 1 拍（vs/hs/de/data 同步延迟，时序关系不变）。
// ============================================================================

module osd_overlay #(
    parameter H_ACTIVE = 1280,      // 有效行像素（必须与 hdmi_mixer 的 IMG_WIDTH 一致）
    parameter V_ACTIVE = 720,       // 有效行数
    parameter PANEL_X  = 16,        // 面板左上角
    parameter PANEL_Y  = 16,
    parameter PANEL_W  = 208,       // 面板宽（含描边）
    parameter PANEL_H  = 156,       // 面板高（含描边）
    parameter PANEL_BW = 2,         // 描边宽度
    parameter LOGO_X   = 24,        // Logo 在屏幕上的位置与尺寸
    parameter LOGO_Y   = 24,
    parameter LOGO_W   = @@LOGO_W@@,
    parameter LOGO_H   = @@LOGO_H@@,
    parameter TEXT_X   = 24,        // 文字左上角
    parameter TEXT_Y0  = 126,       // 第 1 行
    parameter TEXT_Y1  = 146,       // 第 2 行
    parameter CHAR_ADV = 16,        // 字符步进（2 倍放大：字模 5x7 -> 10x14，留 6px 间距）
    parameter CHAR_NUM = 12         // 每行字符数
) (
    input  wire        I_pix_clk,
    input  wire        I_rst_n,

    input  wire        I_vs,
    input  wire        I_hs,
    input  wire        I_de,
    input  wire [23:0] I_data,

    output reg         O_vs,
    output reg         O_hs,
    output reg         O_de,
    output reg  [23:0] O_data
);

    // ------------------------------------------------------------------
    // 配色（品牌两色 + 面板底色）
    // ------------------------------------------------------------------
    localparam [23:0] C_NAVY  = 24'h1C2D4E;   // 安路深蓝
    localparam [23:0] C_RED   = 24'hED1C24;   // 安路红
    localparam [23:0] C_PLATE = 24'hE0E0E0;   // 面板浅灰（不用纯白，避免刺眼）

    // 文字局部坐标用的 8bit 常量（文字块在 x<256 / y<256 内，低 8 位足够，
    // 这样差值不会在“自决定位宽”下被截断，也不会因高位闲置触发 lint 误报）
    localparam [7:0] LP_TEXT_X8 = TEXT_X[7:0];
    localparam [7:0] LP_TEXT_Y0 = TEXT_Y0[7:0];
    localparam [7:0] LP_TEXT_Y1 = TEXT_Y1[7:0];

//@@FONT@@

//@@CHARS@@

    // ------------------------------------------------------------------
    // 1. 行列坐标（de 计数；vs 上升沿帧对齐）
    // ------------------------------------------------------------------
    reg  [11:0] S_x;
    reg  [11:0] S_y;
    reg         S_de_d;
    reg         S_vs_d;

    wire S_vs_rise = I_vs & ~S_vs_d;
    wire S_de_fall = S_de_d & ~I_de;

    always @(posedge I_pix_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            S_de_d <= 1'b0;
            S_vs_d <= 1'b0;
        end else begin
            S_de_d <= I_de;
            S_vs_d <= I_vs;
        end
    end

    always @(posedge I_pix_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            S_x <= 12'd0;
            S_y <= 12'd0;
        end else if (S_vs_rise) begin
            S_x <= 12'd0;
            S_y <= 12'd0;
        end else if (I_de) begin
            if (S_x == (H_ACTIVE - 1)) S_x <= 12'd0;
            else                       S_x <= S_x + 12'd1;
        end else if (S_de_fall) begin
            S_x <= 12'd0;
            if (S_y == (V_ACTIVE - 1)) S_y <= 12'd0;
            else                       S_y <= S_y + 12'd1;
        end
    end

    // ------------------------------------------------------------------
    // 2. 面板 / 描边
    // ------------------------------------------------------------------
    wire S_in_panel = (S_x >= PANEL_X) && (S_x < (PANEL_X + PANEL_W)) &&
                      (S_y >= PANEL_Y) && (S_y < (PANEL_Y + PANEL_H));

    wire S_on_border = S_in_panel &&
                       ((S_x <  (PANEL_X + PANEL_BW)) ||
                        (S_x >= (PANEL_X + PANEL_W - PANEL_BW)) ||
                        (S_y <  (PANEL_Y + PANEL_BW)) ||
                        (S_y >= (PANEL_Y + PANEL_H - PANEL_BW)));

    // ------------------------------------------------------------------
    // 3. Logo：地址 = ly*160 + lx（160 = 128 + 32，纯移位加法，不用乘法器）
    //    位宽注意：所有中间量都显式写成 14bit。若写成 (S_ly[6:0] << 5)，
    //    它处于“自决定位宽”上下文，部分工具会按 7bit 截断 -> 地址错。必须补零扩位。
    // ------------------------------------------------------------------
    wire [11:0] S_lx = S_x - LOGO_X;
    wire [11:0] S_ly = S_y - LOGO_Y;

    wire S_in_logo = (S_x >= LOGO_X) && (S_x < (LOGO_X + LOGO_W)) &&
                     (S_y >= LOGO_Y) && (S_y < (LOGO_Y + LOGO_H));

    wire [13:0] S_ly14 = {2'b00, S_ly};                        // 12bit -> 14bit
    wire [13:0] S_lx14 = {2'b00, S_lx};
    wire [13:0] S_logo_y = (S_ly14 << 7) + (S_ly14 << 5);      // ly * 128 + ly * 32
    wire [13:0] S_logo_addr = S_logo_y + S_lx14;               // ly * 160 + lx

    wire [1:0] S_logo_px;
    osd_logo_rom u_osd_logo_rom (
        .I_addr (S_logo_addr),
        .O_px   (S_logo_px)
    );

    // ------------------------------------------------------------------
    // 4. 文字：char 索引 = tx[7:4]（步进 16），列 = tx[3:0]/2，行 = ty/2
    //    文字块整体落在 x<256 / y<256 内，故局部坐标用低 8 位算即可（无截断风险）
    //    注：坐标差值的高位本来就闲置，lint 工具会报 UNUSEDSIGNAL，这里局部关闭
    // ------------------------------------------------------------------
    /* verilator lint_off UNUSEDSIGNAL */
    wire [7:0] S_tx  = S_x[7:0] - LP_TEXT_X8;
    wire [3:0] S_ci  = S_tx[7:4];
    wire [3:0] S_cx  = S_tx[3:0];
    wire       S_col_ok = (S_cx < 4'd10);          // 5 列字模 x2 后占 10px

    wire S_in_t0 = (S_x >= TEXT_X) && (S_x < (TEXT_X + CHAR_NUM * CHAR_ADV)) &&
                   (S_y >= TEXT_Y0) && (S_y < (TEXT_Y0 + 14));
    wire S_in_t1 = (S_x >= TEXT_X) && (S_x < (TEXT_X + CHAR_NUM * CHAR_ADV)) &&
                   (S_y >= TEXT_Y1) && (S_y < (TEXT_Y1 + 14));

    wire [7:0] S_dy0 = S_y[7:0] - LP_TEXT_Y0;      // 行内偏移（0..13）
    wire [7:0] S_dy1 = S_y[7:0] - LP_TEXT_Y1;
    /* verilator lint_on UNUSEDSIGNAL */
    wire [2:0] S_cy0 = S_dy0[3:1];                 // /2 -> 字模行号 0..6
    wire [2:0] S_cy1 = S_dy1[3:1];

    wire [6:0] S_ch0 = F_char(1'b0, S_ci);
    wire [6:0] S_ch1 = F_char(1'b1, S_ci);
    wire [4:0] S_gl0 = F_glyph(S_ch0, S_cy0);
    wire [4:0] S_gl1 = F_glyph(S_ch1, S_cy1);

    // 取字模第 (4 - cx/2) 位：cx 每 2 列跨一列字模（2 倍放大）。直接位选取，无位宽隐患
    wire       S_px0 = S_col_ok & S_gl0[3'd4 - S_cx[3:1]];
    wire       S_px1 = S_col_ok & S_gl1[3'd4 - S_cx[3:1]];

    // ------------------------------------------------------------------
    // 5. 叠加优先级：描边 > Logo > 文字 > 底板
    // ------------------------------------------------------------------
    reg        S_ov_hit;
    reg [23:0] S_ov_color;

    always @(*) begin
        S_ov_hit   = 1'b0;
        S_ov_color = 24'd0;
        if (S_in_panel) begin
            S_ov_hit   = 1'b1;
            S_ov_color = C_PLATE;
            if (S_on_border) begin
                S_ov_color = C_NAVY;
            end else if (S_in_logo && (S_logo_px != 2'd0)) begin
                S_ov_color = S_logo_px[1] ? C_RED : C_NAVY;
            end else if (S_in_t0 && S_px0) begin
                S_ov_color = C_NAVY;
            end else if (S_in_t1 && S_px1) begin
                S_ov_color = C_NAVY;
            end
        end
    end

    // ------------------------------------------------------------------
    // 6. 输出打一拍（vs/hs/de/data 同步延迟，保持时序关系）
    // ------------------------------------------------------------------
    always @(posedge I_pix_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            O_vs   <= 1'b0;
            O_hs   <= 1'b0;
            O_de   <= 1'b0;
            O_data <= 24'd0;
        end else begin
            O_vs   <= I_vs;
            O_hs   <= I_hs;
            O_de   <= I_de;
            O_data <= (I_de && S_ov_hit) ? S_ov_color : I_data;
        end
    end

endmodule
