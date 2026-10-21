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
    parameter LOGO_W   = 146,
    parameter LOGO_H   = 94,
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

    // 5x7 点阵字模（自建，bit4 = 最左列）。case 键 = {字符码[6:0], 行号[2:0]} = 10bit。
    // 注意：字符码必须按 7bit 传（'A'=0x41 已经超过 6bit），否则键会被截断、字模串码。
    function [4:0] F_glyph;
        input [6:0] I_ch;
        input [2:0] I_row;
        begin
            case ({I_ch, I_row})
                10'h100: F_glyph = 5'b00000;  // 'SP' row0
                10'h101: F_glyph = 5'b00000;  // 'SP' row1
                10'h102: F_glyph = 5'b00000;  // 'SP' row2
                10'h103: F_glyph = 5'b00000;  // 'SP' row3
                10'h104: F_glyph = 5'b00000;  // 'SP' row4
                10'h105: F_glyph = 5'b00000;  // 'SP' row5
                10'h106: F_glyph = 5'b00000;  // 'SP' row6
                10'h168: F_glyph = 5'b00000;  // '-' row0
                10'h169: F_glyph = 5'b00000;  // '-' row1
                10'h16A: F_glyph = 5'b00000;  // '-' row2
                10'h16B: F_glyph = 5'b11111;  // '-' row3
                10'h16C: F_glyph = 5'b00000;  // '-' row4
                10'h16D: F_glyph = 5'b00000;  // '-' row5
                10'h16E: F_glyph = 5'b00000;  // '-' row6
                10'h170: F_glyph = 5'b00000;  // '.' row0
                10'h171: F_glyph = 5'b00000;  // '.' row1
                10'h172: F_glyph = 5'b00000;  // '.' row2
                10'h173: F_glyph = 5'b00000;  // '.' row3
                10'h174: F_glyph = 5'b00000;  // '.' row4
                10'h175: F_glyph = 5'b00110;  // '.' row5
                10'h176: F_glyph = 5'b00110;  // '.' row6
                10'h180: F_glyph = 5'b01110;  // '0' row0
                10'h181: F_glyph = 5'b10001;  // '0' row1
                10'h182: F_glyph = 5'b10011;  // '0' row2
                10'h183: F_glyph = 5'b10101;  // '0' row3
                10'h184: F_glyph = 5'b11001;  // '0' row4
                10'h185: F_glyph = 5'b10001;  // '0' row5
                10'h186: F_glyph = 5'b01110;  // '0' row6
                10'h188: F_glyph = 5'b00100;  // '1' row0
                10'h189: F_glyph = 5'b01100;  // '1' row1
                10'h18A: F_glyph = 5'b00100;  // '1' row2
                10'h18B: F_glyph = 5'b00100;  // '1' row3
                10'h18C: F_glyph = 5'b00100;  // '1' row4
                10'h18D: F_glyph = 5'b00100;  // '1' row5
                10'h18E: F_glyph = 5'b01110;  // '1' row6
                10'h190: F_glyph = 5'b01110;  // '2' row0
                10'h191: F_glyph = 5'b10001;  // '2' row1
                10'h192: F_glyph = 5'b00001;  // '2' row2
                10'h193: F_glyph = 5'b00010;  // '2' row3
                10'h194: F_glyph = 5'b00100;  // '2' row4
                10'h195: F_glyph = 5'b01000;  // '2' row5
                10'h196: F_glyph = 5'b11111;  // '2' row6
                10'h198: F_glyph = 5'b11110;  // '3' row0
                10'h199: F_glyph = 5'b00001;  // '3' row1
                10'h19A: F_glyph = 5'b00001;  // '3' row2
                10'h19B: F_glyph = 5'b01110;  // '3' row3
                10'h19C: F_glyph = 5'b00001;  // '3' row4
                10'h19D: F_glyph = 5'b00001;  // '3' row5
                10'h19E: F_glyph = 5'b11110;  // '3' row6
                10'h1A0: F_glyph = 5'b00010;  // '4' row0
                10'h1A1: F_glyph = 5'b00110;  // '4' row1
                10'h1A2: F_glyph = 5'b01010;  // '4' row2
                10'h1A3: F_glyph = 5'b10010;  // '4' row3
                10'h1A4: F_glyph = 5'b11111;  // '4' row4
                10'h1A5: F_glyph = 5'b00010;  // '4' row5
                10'h1A6: F_glyph = 5'b00010;  // '4' row6
                10'h1A8: F_glyph = 5'b11111;  // '5' row0
                10'h1A9: F_glyph = 5'b10000;  // '5' row1
                10'h1AA: F_glyph = 5'b11110;  // '5' row2
                10'h1AB: F_glyph = 5'b00001;  // '5' row3
                10'h1AC: F_glyph = 5'b00001;  // '5' row4
                10'h1AD: F_glyph = 5'b10001;  // '5' row5
                10'h1AE: F_glyph = 5'b01110;  // '5' row6
                10'h1B0: F_glyph = 5'b00110;  // '6' row0
                10'h1B1: F_glyph = 5'b01000;  // '6' row1
                10'h1B2: F_glyph = 5'b10000;  // '6' row2
                10'h1B3: F_glyph = 5'b11110;  // '6' row3
                10'h1B4: F_glyph = 5'b10001;  // '6' row4
                10'h1B5: F_glyph = 5'b10001;  // '6' row5
                10'h1B6: F_glyph = 5'b01110;  // '6' row6
                10'h1B8: F_glyph = 5'b11111;  // '7' row0
                10'h1B9: F_glyph = 5'b00001;  // '7' row1
                10'h1BA: F_glyph = 5'b00010;  // '7' row2
                10'h1BB: F_glyph = 5'b00100;  // '7' row3
                10'h1BC: F_glyph = 5'b01000;  // '7' row4
                10'h1BD: F_glyph = 5'b01000;  // '7' row5
                10'h1BE: F_glyph = 5'b01000;  // '7' row6
                10'h1C0: F_glyph = 5'b01110;  // '8' row0
                10'h1C1: F_glyph = 5'b10001;  // '8' row1
                10'h1C2: F_glyph = 5'b10001;  // '8' row2
                10'h1C3: F_glyph = 5'b01110;  // '8' row3
                10'h1C4: F_glyph = 5'b10001;  // '8' row4
                10'h1C5: F_glyph = 5'b10001;  // '8' row5
                10'h1C6: F_glyph = 5'b01110;  // '8' row6
                10'h1C8: F_glyph = 5'b01110;  // '9' row0
                10'h1C9: F_glyph = 5'b10001;  // '9' row1
                10'h1CA: F_glyph = 5'b10001;  // '9' row2
                10'h1CB: F_glyph = 5'b01111;  // '9' row3
                10'h1CC: F_glyph = 5'b00001;  // '9' row4
                10'h1CD: F_glyph = 5'b00010;  // '9' row5
                10'h1CE: F_glyph = 5'b01100;  // '9' row6
                10'h1D0: F_glyph = 5'b00000;  // ':' row0
                10'h1D1: F_glyph = 5'b00100;  // ':' row1
                10'h1D2: F_glyph = 5'b00100;  // ':' row2
                10'h1D3: F_glyph = 5'b00000;  // ':' row3
                10'h1D4: F_glyph = 5'b00100;  // ':' row4
                10'h1D5: F_glyph = 5'b00100;  // ':' row5
                10'h1D6: F_glyph = 5'b00000;  // ':' row6
                10'h208: F_glyph = 5'b01110;  // 'A' row0
                10'h209: F_glyph = 5'b10001;  // 'A' row1
                10'h20A: F_glyph = 5'b10001;  // 'A' row2
                10'h20B: F_glyph = 5'b11111;  // 'A' row3
                10'h20C: F_glyph = 5'b10001;  // 'A' row4
                10'h20D: F_glyph = 5'b10001;  // 'A' row5
                10'h20E: F_glyph = 5'b10001;  // 'A' row6
                10'h210: F_glyph = 5'b11110;  // 'B' row0
                10'h211: F_glyph = 5'b10001;  // 'B' row1
                10'h212: F_glyph = 5'b10001;  // 'B' row2
                10'h213: F_glyph = 5'b11110;  // 'B' row3
                10'h214: F_glyph = 5'b10001;  // 'B' row4
                10'h215: F_glyph = 5'b10001;  // 'B' row5
                10'h216: F_glyph = 5'b11110;  // 'B' row6
                10'h218: F_glyph = 5'b01110;  // 'C' row0
                10'h219: F_glyph = 5'b10001;  // 'C' row1
                10'h21A: F_glyph = 5'b10000;  // 'C' row2
                10'h21B: F_glyph = 5'b10000;  // 'C' row3
                10'h21C: F_glyph = 5'b10000;  // 'C' row4
                10'h21D: F_glyph = 5'b10001;  // 'C' row5
                10'h21E: F_glyph = 5'b01110;  // 'C' row6
                10'h220: F_glyph = 5'b11110;  // 'D' row0
                10'h221: F_glyph = 5'b10001;  // 'D' row1
                10'h222: F_glyph = 5'b10001;  // 'D' row2
                10'h223: F_glyph = 5'b10001;  // 'D' row3
                10'h224: F_glyph = 5'b10001;  // 'D' row4
                10'h225: F_glyph = 5'b10001;  // 'D' row5
                10'h226: F_glyph = 5'b11110;  // 'D' row6
                10'h228: F_glyph = 5'b11111;  // 'E' row0
                10'h229: F_glyph = 5'b10000;  // 'E' row1
                10'h22A: F_glyph = 5'b10000;  // 'E' row2
                10'h22B: F_glyph = 5'b11110;  // 'E' row3
                10'h22C: F_glyph = 5'b10000;  // 'E' row4
                10'h22D: F_glyph = 5'b10000;  // 'E' row5
                10'h22E: F_glyph = 5'b11111;  // 'E' row6
                10'h230: F_glyph = 5'b11111;  // 'F' row0
                10'h231: F_glyph = 5'b10000;  // 'F' row1
                10'h232: F_glyph = 5'b10000;  // 'F' row2
                10'h233: F_glyph = 5'b11110;  // 'F' row3
                10'h234: F_glyph = 5'b10000;  // 'F' row4
                10'h235: F_glyph = 5'b10000;  // 'F' row5
                10'h236: F_glyph = 5'b10000;  // 'F' row6
                10'h238: F_glyph = 5'b01110;  // 'G' row0
                10'h239: F_glyph = 5'b10001;  // 'G' row1
                10'h23A: F_glyph = 5'b10000;  // 'G' row2
                10'h23B: F_glyph = 5'b10111;  // 'G' row3
                10'h23C: F_glyph = 5'b10001;  // 'G' row4
                10'h23D: F_glyph = 5'b10001;  // 'G' row5
                10'h23E: F_glyph = 5'b01111;  // 'G' row6
                10'h240: F_glyph = 5'b10001;  // 'H' row0
                10'h241: F_glyph = 5'b10001;  // 'H' row1
                10'h242: F_glyph = 5'b10001;  // 'H' row2
                10'h243: F_glyph = 5'b11111;  // 'H' row3
                10'h244: F_glyph = 5'b10001;  // 'H' row4
                10'h245: F_glyph = 5'b10001;  // 'H' row5
                10'h246: F_glyph = 5'b10001;  // 'H' row6
                10'h248: F_glyph = 5'b01110;  // 'I' row0
                10'h249: F_glyph = 5'b00100;  // 'I' row1
                10'h24A: F_glyph = 5'b00100;  // 'I' row2
                10'h24B: F_glyph = 5'b00100;  // 'I' row3
                10'h24C: F_glyph = 5'b00100;  // 'I' row4
                10'h24D: F_glyph = 5'b00100;  // 'I' row5
                10'h24E: F_glyph = 5'b01110;  // 'I' row6
                10'h250: F_glyph = 5'b00111;  // 'J' row0
                10'h251: F_glyph = 5'b00010;  // 'J' row1
                10'h252: F_glyph = 5'b00010;  // 'J' row2
                10'h253: F_glyph = 5'b00010;  // 'J' row3
                10'h254: F_glyph = 5'b00010;  // 'J' row4
                10'h255: F_glyph = 5'b10010;  // 'J' row5
                10'h256: F_glyph = 5'b01100;  // 'J' row6
                10'h258: F_glyph = 5'b10001;  // 'K' row0
                10'h259: F_glyph = 5'b10010;  // 'K' row1
                10'h25A: F_glyph = 5'b10100;  // 'K' row2
                10'h25B: F_glyph = 5'b11000;  // 'K' row3
                10'h25C: F_glyph = 5'b10100;  // 'K' row4
                10'h25D: F_glyph = 5'b10010;  // 'K' row5
                10'h25E: F_glyph = 5'b10001;  // 'K' row6
                10'h260: F_glyph = 5'b10000;  // 'L' row0
                10'h261: F_glyph = 5'b10000;  // 'L' row1
                10'h262: F_glyph = 5'b10000;  // 'L' row2
                10'h263: F_glyph = 5'b10000;  // 'L' row3
                10'h264: F_glyph = 5'b10000;  // 'L' row4
                10'h265: F_glyph = 5'b10000;  // 'L' row5
                10'h266: F_glyph = 5'b11111;  // 'L' row6
                10'h268: F_glyph = 5'b10001;  // 'M' row0
                10'h269: F_glyph = 5'b11011;  // 'M' row1
                10'h26A: F_glyph = 5'b10101;  // 'M' row2
                10'h26B: F_glyph = 5'b10101;  // 'M' row3
                10'h26C: F_glyph = 5'b10001;  // 'M' row4
                10'h26D: F_glyph = 5'b10001;  // 'M' row5
                10'h26E: F_glyph = 5'b10001;  // 'M' row6
                10'h270: F_glyph = 5'b10001;  // 'N' row0
                10'h271: F_glyph = 5'b11001;  // 'N' row1
                10'h272: F_glyph = 5'b10101;  // 'N' row2
                10'h273: F_glyph = 5'b10011;  // 'N' row3
                10'h274: F_glyph = 5'b10001;  // 'N' row4
                10'h275: F_glyph = 5'b10001;  // 'N' row5
                10'h276: F_glyph = 5'b10001;  // 'N' row6
                10'h278: F_glyph = 5'b01110;  // 'O' row0
                10'h279: F_glyph = 5'b10001;  // 'O' row1
                10'h27A: F_glyph = 5'b10001;  // 'O' row2
                10'h27B: F_glyph = 5'b10001;  // 'O' row3
                10'h27C: F_glyph = 5'b10001;  // 'O' row4
                10'h27D: F_glyph = 5'b10001;  // 'O' row5
                10'h27E: F_glyph = 5'b01110;  // 'O' row6
                10'h280: F_glyph = 5'b11110;  // 'P' row0
                10'h281: F_glyph = 5'b10001;  // 'P' row1
                10'h282: F_glyph = 5'b10001;  // 'P' row2
                10'h283: F_glyph = 5'b11110;  // 'P' row3
                10'h284: F_glyph = 5'b10000;  // 'P' row4
                10'h285: F_glyph = 5'b10000;  // 'P' row5
                10'h286: F_glyph = 5'b10000;  // 'P' row6
                10'h288: F_glyph = 5'b01110;  // 'Q' row0
                10'h289: F_glyph = 5'b10001;  // 'Q' row1
                10'h28A: F_glyph = 5'b10001;  // 'Q' row2
                10'h28B: F_glyph = 5'b10001;  // 'Q' row3
                10'h28C: F_glyph = 5'b10101;  // 'Q' row4
                10'h28D: F_glyph = 5'b10010;  // 'Q' row5
                10'h28E: F_glyph = 5'b01101;  // 'Q' row6
                10'h290: F_glyph = 5'b11110;  // 'R' row0
                10'h291: F_glyph = 5'b10001;  // 'R' row1
                10'h292: F_glyph = 5'b10001;  // 'R' row2
                10'h293: F_glyph = 5'b11110;  // 'R' row3
                10'h294: F_glyph = 5'b10100;  // 'R' row4
                10'h295: F_glyph = 5'b10010;  // 'R' row5
                10'h296: F_glyph = 5'b10001;  // 'R' row6
                10'h298: F_glyph = 5'b01111;  // 'S' row0
                10'h299: F_glyph = 5'b10000;  // 'S' row1
                10'h29A: F_glyph = 5'b10000;  // 'S' row2
                10'h29B: F_glyph = 5'b01110;  // 'S' row3
                10'h29C: F_glyph = 5'b00001;  // 'S' row4
                10'h29D: F_glyph = 5'b00001;  // 'S' row5
                10'h29E: F_glyph = 5'b11110;  // 'S' row6
                10'h2A0: F_glyph = 5'b11111;  // 'T' row0
                10'h2A1: F_glyph = 5'b00100;  // 'T' row1
                10'h2A2: F_glyph = 5'b00100;  // 'T' row2
                10'h2A3: F_glyph = 5'b00100;  // 'T' row3
                10'h2A4: F_glyph = 5'b00100;  // 'T' row4
                10'h2A5: F_glyph = 5'b00100;  // 'T' row5
                10'h2A6: F_glyph = 5'b00100;  // 'T' row6
                10'h2A8: F_glyph = 5'b10001;  // 'U' row0
                10'h2A9: F_glyph = 5'b10001;  // 'U' row1
                10'h2AA: F_glyph = 5'b10001;  // 'U' row2
                10'h2AB: F_glyph = 5'b10001;  // 'U' row3
                10'h2AC: F_glyph = 5'b10001;  // 'U' row4
                10'h2AD: F_glyph = 5'b10001;  // 'U' row5
                10'h2AE: F_glyph = 5'b01110;  // 'U' row6
                10'h2B0: F_glyph = 5'b10001;  // 'V' row0
                10'h2B1: F_glyph = 5'b10001;  // 'V' row1
                10'h2B2: F_glyph = 5'b10001;  // 'V' row2
                10'h2B3: F_glyph = 5'b10001;  // 'V' row3
                10'h2B4: F_glyph = 5'b10001;  // 'V' row4
                10'h2B5: F_glyph = 5'b01010;  // 'V' row5
                10'h2B6: F_glyph = 5'b00100;  // 'V' row6
                10'h2B8: F_glyph = 5'b10001;  // 'W' row0
                10'h2B9: F_glyph = 5'b10001;  // 'W' row1
                10'h2BA: F_glyph = 5'b10001;  // 'W' row2
                10'h2BB: F_glyph = 5'b10101;  // 'W' row3
                10'h2BC: F_glyph = 5'b10101;  // 'W' row4
                10'h2BD: F_glyph = 5'b11011;  // 'W' row5
                10'h2BE: F_glyph = 5'b10001;  // 'W' row6
                10'h2C0: F_glyph = 5'b10001;  // 'X' row0
                10'h2C1: F_glyph = 5'b10001;  // 'X' row1
                10'h2C2: F_glyph = 5'b01010;  // 'X' row2
                10'h2C3: F_glyph = 5'b00100;  // 'X' row3
                10'h2C4: F_glyph = 5'b01010;  // 'X' row4
                10'h2C5: F_glyph = 5'b10001;  // 'X' row5
                10'h2C6: F_glyph = 5'b10001;  // 'X' row6
                10'h2C8: F_glyph = 5'b10001;  // 'Y' row0
                10'h2C9: F_glyph = 5'b10001;  // 'Y' row1
                10'h2CA: F_glyph = 5'b01010;  // 'Y' row2
                10'h2CB: F_glyph = 5'b00100;  // 'Y' row3
                10'h2CC: F_glyph = 5'b00100;  // 'Y' row4
                10'h2CD: F_glyph = 5'b00100;  // 'Y' row5
                10'h2CE: F_glyph = 5'b00100;  // 'Y' row6
                10'h2D0: F_glyph = 5'b11111;  // 'Z' row0
                10'h2D1: F_glyph = 5'b00001;  // 'Z' row1
                10'h2D2: F_glyph = 5'b00010;  // 'Z' row2
                10'h2D3: F_glyph = 5'b00100;  // 'Z' row3
                10'h2D4: F_glyph = 5'b01000;  // 'Z' row4
                10'h2D5: F_glyph = 5'b10000;  // 'Z' row5
                10'h2D6: F_glyph = 5'b11111;  // 'Z' row6
                default: F_glyph = 5'b00000;
            endcase
        end
    endfunction

    // 两行文案（改字只改这里；不足 12 字符用空格补齐，避免残留旧字）
    //   line0 = "ANLOGIC     "
    //   line1 = "PH1P35 720P "
    function [6:0] F_char;
        input [0:0] I_line;
        input [3:0] I_idx;
        begin
            case ({I_line, I_idx})
                5'h00: F_char = 7'h41;  // 'A'
                5'h01: F_char = 7'h4E;  // 'N'
                5'h02: F_char = 7'h4C;  // 'L'
                5'h03: F_char = 7'h4F;  // 'O'
                5'h04: F_char = 7'h47;  // 'G'
                5'h05: F_char = 7'h49;  // 'I'
                5'h06: F_char = 7'h43;  // 'C'
                5'h07: F_char = 7'h20;  // 'SP'
                5'h08: F_char = 7'h20;  // 'SP'
                5'h09: F_char = 7'h20;  // 'SP'
                5'h0A: F_char = 7'h20;  // 'SP'
                5'h0B: F_char = 7'h20;  // 'SP'
                5'h10: F_char = 7'h50;  // 'P'
                5'h11: F_char = 7'h48;  // 'H'
                5'h12: F_char = 7'h31;  // '1'
                5'h13: F_char = 7'h50;  // 'P'
                5'h14: F_char = 7'h33;  // '3'
                5'h15: F_char = 7'h35;  // '5'
                5'h16: F_char = 7'h20;  // 'SP'
                5'h17: F_char = 7'h37;  // '7'
                5'h18: F_char = 7'h32;  // '2'
                5'h19: F_char = 7'h30;  // '0'
                5'h1A: F_char = 7'h50;  // 'P'
                5'h1B: F_char = 7'h20;  // 'SP'
                default: F_char = 7'h20;  // 空格
            endcase
        end
    endfunction

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
