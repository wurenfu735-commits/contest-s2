// 测试图发生器：按画面坐标产生 8 种图案，KEY 切换
//   0 八彩条       每 160 列一种颜色，白黄青绿品红蓝黑（强边缘）
//   1 棋盘格       16x16 像素黑白格（强边缘）
//   2 渐变         红随列、绿随行、蓝取两值异或（几乎无边缘）
//   3 八级灰阶     每 160 列一级（强边缘）
//   4 低对比度·中灰 每 64 列在 26/38 间交替（Δ=12 -> Sobel 48，低于官方固定阈值 80）
//   5 低对比度·暗区 每 64 列在  8/22 间交替（Δ=14 -> Sobel 56）
//   6 低对比度·亮区 每 64 列在 200/214 间交替（Δ=14 -> Sobel 56）
//   7 细条纹       每 8 列高低交替，灰度 0/255（检验分辨率与最小边缘间距）
// 图案 4/5/6 是给"固定阈值 vs 自适应阈值"对比用的：三者对比度都低于固定阈值 80，
// 固定阈值一律漏检，自适应阈值仍能检出，分屏对比时差异一眼可见。
//
// 画面底部 16 行固定为状态带：上 8 行指示当前图案，下 8 行指示 PLL 锁定
// 坐标说明：hcnt/vcnt 是整幅时序计数（含同步/后沿），画面左上角对应
//           hcnt=260、vcnt=25，因此先换算成画面坐标 lx/ly 再算图案；
//           消隐期 lx/ly 无意义，但此时 de=0，输出恒 0，不影响
module test_pattern_gen (
    input  wire        I_clk,
    input  wire        I_rst_n,
    input  wire        I_de,
    input  wire [11:0] I_hcnt,
    input  wire [11:0] I_vcnt,
    input  wire [2:0]  I_pattern_sel,
    input  wire        I_pll_lock,
    output reg  [23:0] O_rgb            // RGB888
);

    // 画面坐标：左列 0..1279，上行 0..719
    wire [10:0] lx = I_hcnt[10:0] - 11'd260;
    wire [11:0] ly = I_vcnt       - 12'd25;

    // 8 分列：每段 160 列，比较链占用少量 LUT
    wire [2:0] col = (lx >= 11'd1120) ? 3'd7 :
                     (lx >= 11'd960)  ? 3'd6 :
                     (lx >= 11'd800)  ? 3'd5 :
                     (lx >= 11'd640)  ? 3'd4 :
                     (lx >= 11'd480)  ? 3'd3 :
                     (lx >= 11'd320)  ? 3'd2 :
                     (lx >= 11'd160)  ? 3'd1 : 3'd0;

    // 渐变分量：红 8 像素一级，绿 4 行一级
    wire [7:0] x8 = lx[10:3];
    wire [7:0] y8 = ly[9:2];

    // 低对比度图案的交替相位：每 64 列翻转
    wire lc_phase = lx[6];

    // 状态带：画面最下 16 行
    wire in_band = I_de && (ly >= 12'd704);
    wire band_hi = (ly < 12'd712);

    reg [23:0] colorbar, checker, gradient, gray, lc_mid, lc_dark, lc_bright, fine, band_color;
    always @(*) begin
        case (col)
            3'd0: colorbar = 24'hFFFFFF;
            3'd1: colorbar = 24'hFFFF00;
            3'd2: colorbar = 24'h00FFFF;
            3'd3: colorbar = 24'h00FF00;
            3'd4: colorbar = 24'hFF00FF;
            3'd5: colorbar = 24'hFF0000;
            3'd6: colorbar = 24'h0000FF;
            default: colorbar = 24'h000000;
        endcase

        checker = (lx[4] ^ ly[4]) ? 24'hFFFFFF : 24'h000000;
        gradient = {x8, y8, (x8 ^ y8)};

        case (col)
            3'd0: gray = 24'h000000;
            3'd1: gray = 24'h242424;
            3'd2: gray = 24'h494949;
            3'd3: gray = 24'h6D6D6D;
            3'd4: gray = 24'h929292;
            3'd5: gray = 24'hB6B6B6;
            3'd6: gray = 24'hDBDBDB;
            default: gray = 24'hFFFFFF;
        endcase

        // 低对比度：Δ=12/14，Sobel 幅值 48/56，均低于官方固定阈值 80
        lc_mid    = lc_phase ? 24'h262626 : 24'h1A1A1A;   // 38 / 26
        lc_dark   = lc_phase ? 24'h161616 : 24'h080808;   // 22 / 8
        lc_bright = lc_phase ? 24'hD6D6D6 : 24'hC8C8C8;   // 214 / 200
        fine      = lx[3] ? 24'hFFFFFF : 24'h000000;      // 每 8 列黑白

        case (I_pattern_sel)
            3'd0: band_color = 24'hFFFFFF;
            3'd1: band_color = 24'hFFFF00;
            3'd2: band_color = 24'h00FFFF;
            3'd3: band_color = 24'h00FF00;
            3'd4: band_color = 24'hFF00FF;
            3'd5: band_color = 24'hFF8000;
            3'd6: band_color = 24'h8080FF;
            default: band_color = 24'hFF0000;
        endcase
    end

    // 组合输出：必须与 I_de 同拍
    // （若用寄存器输出，数据会比 de 晚一拍，消隐期的 0 会被当成图案第 0 列，
    //   在算法侧形成 mag=100 的假边缘）
    always @(*) begin
        if (!I_de) begin
            O_rgb = 24'd0;
        end else if (in_band && band_hi) begin
            O_rgb = band_color;
        end else if (in_band) begin
            O_rgb = I_pll_lock ? 24'h00FF00 : 24'hFF0000;
        end else begin
            case (I_pattern_sel)
                3'd0: O_rgb = colorbar;
                3'd1: O_rgb = checker;
                3'd2: O_rgb = gradient;
                3'd3: O_rgb = gray;
                3'd4: O_rgb = lc_mid;
                3'd5: O_rgb = lc_dark;
                3'd6: O_rgb = lc_bright;
                default: O_rgb = fine;
            endcase
        end
    end

endmodule
