// ============================================================================
// tb_osd_overlay.v  ——  B4 OSD 自检测试平台
// ----------------------------------------------------------------------------
// 目的：不依赖人工看图，自动证明 osd_overlay 的 5 件事
//   1) 时序：O_vs/O_hs/O_de 严格是 I_vs/I_hs/I_de 延迟 1 拍（不破坏 720p 时序）
//   2) 透传：面板区域之外的像素 **一个 bit 都不改**
//   3) 叠加：面板之内只出现 3 种 OSD 颜色，且描边/底板/Logo/文字的分类计数与
//            Python 黄金模型完全一致（期望值由 tools/gen_osd_assets.py 生成）
//   4) 内容：整帧像素做 32bit 滚动哈希，与黄金模型逐像素一致（最强校验）
//   5) 结构采样点：描边/底板/面板外 的定点位置颜色正确
//
// 写法说明：整份 tb 用“可综合风格”写（计数器产生时序、always 块内做比较），
//   因此既能进 ModelSim/Questa(Vivado) 跑，也能进 yosys sim 跑（本机无商业仿真器）。
//
// 两种帧尺寸：
//   默认 1280x720（真实分辨率，期望值见 osd_tb_expect_1280x720.vh）
//   加 +define+SMALL_FRAME 用 320x240（仿真快 10 倍，面板 224x172 仍完整落在屏内，
//   所有绘制分支都会被走到，坐标运算与 720p 完全同构）
//
// 注：EXP_* 常量由 tools/gen_osd_assets.py 生成，改了 Logo/文案/位置后必须重跑生成器。
// ============================================================================
`timescale 1ns/1ps

module tb_osd_overlay;

`ifdef SMALL_FRAME
    localparam H_ACTIVE = 320;
    localparam V_ACTIVE = 240;
`else
    localparam H_ACTIVE = 1280;
    localparam V_ACTIVE = 720;
`endif

    localparam H_TOTAL = H_ACTIVE + 64;      // 行总周期（含消隐）
    localparam V_TOTAL = V_ACTIVE + 32;      // 帧总行数（含消隐）

    // 与 DUT 内部配色一致
    localparam [23:0] C_NAVY  = 24'h1C2D4E;
    localparam [23:0] C_RED   = 24'hED1C24;
    localparam [23:0] C_PLATE = 24'hE0E0E0;

    // 面板几何（= DUT 默认参数）
    localparam PANEL_X = 16;
    localparam PANEL_Y = 16;
    localparam PANEL_W = 208;
    localparam PANEL_H = 156;

    // 黄金模型期望值
`ifdef SMALL_FRAME
    `include "osd_tb_expect_320x240.vh"
`else
    `include "osd_tb_expect_1280x720.vh"
`endif

    // ------------------------------------------------------------------ 时钟
    reg clk;
`ifndef YOSYS_SIM
    initial clk = 1'b0;
    always #5 clk = ~clk;              // 200MHz 只是仿真节拍，不代表实际像素时钟
`endif

    // ------------------------------------------------------------------ 复位
    // 用计数器产生“上电复位”，不依赖 initial 延时，波形上更直观
    /* verilator lint_off PROCASSINIT */
    /* verilator lint_off SYNCASYNCNET */
    reg [5:0] rst_cnt = 6'd0;
    /* verilator lint_on SYNCASYNCNET */
    /* verilator lint_on PROCASSINIT */
    wire      rst_n   = (rst_cnt == 6'd63);

    always @(posedge clk) begin
        if (rst_cnt != 6'd63) rst_cnt <= rst_cnt + 6'd1;
    end

    // ------------------------------------------------------------------ 视频时序发生
    reg [11:0] hc;      // 行内计数 0..H_TOTAL-1
    reg [11:0] vc;      // 帧内行计数 0..V_TOTAL-1

    always @(posedge clk) begin
        if (!rst_n) begin
            hc <= 12'd0;
            vc <= 12'd0;
        end else if (hc == (H_TOTAL - 1)) begin
            hc <= 12'd0;
            vc <= (vc == (V_TOTAL - 1)) ? 12'd0 : (vc + 12'd1);
        end else begin
            hc <= hc + 12'd1;
        end
    end

    wire        de_i  = (hc < H_ACTIVE) && (vc < V_ACTIVE);
    wire        vs_i  = (vc >= V_ACTIVE) && (vc < (V_ACTIVE + 8));
    wire        hs_i  = (hc >= (H_ACTIVE + 8)) && (hc < (H_ACTIVE + 48));
    // 测试图样：低 12bit=行号，高 12bit=列号（唯一，且不可能撞上 3 种 OSD 颜色）
    wire [23:0] dat_i = {hc, vc};

    // ------------------------------------------------------------------ 待测模块
    wire        vs_o, hs_o, de_o;
    wire [23:0] dat_o;

    osd_overlay #(
        .H_ACTIVE (H_ACTIVE),
        .V_ACTIVE (V_ACTIVE)
    ) u_dut (
        .I_pix_clk (clk),
        .I_rst_n   (rst_n),
        .I_vs      (vs_i),
        .I_hs      (hs_i),
        .I_de      (de_i),
        .I_data    (dat_i),
        .O_vs      (vs_o),
        .O_hs      (hs_o),
        .O_de      (de_o),
        .O_data    (dat_o)
    );

    // ------------------------------------------------------------------ 输出侧对齐（DUT 固定 1 拍延迟）
    reg [11:0] hc_d, vc_d;
    reg [23:0] dat_d;
    reg        de_d, vs_d, hs_d;

    always @(posedge clk) begin
        if (!rst_n) begin
            hc_d  <= 12'd0;      // 复位期间同步清零，避免复位边界上比 de_o/de_d 多出一拍
            vc_d  <= 12'd0;
            dat_d <= 24'd0;
            de_d  <= 1'b0;
            vs_d  <= 1'b0;
            hs_d  <= 1'b0;
        end else begin
            hc_d  <= hc;
            vc_d  <= vc;
            dat_d <= dat_i;
            de_d  <= de_i;
            vs_d  <= vs_i;
            hs_d  <= hs_i;
        end
    end

    // ------------------------------------------------------------------ 位置判定
    wire in_panel_d = (hc_d >= PANEL_X) && (hc_d < (PANEL_X + PANEL_W)) &&
                      (vc_d >= PANEL_Y) && (vc_d < (PANEL_Y + PANEL_H));

    wire on_border_d = (hc_d <  (PANEL_X + 2)) || (hc_d >= (PANEL_X + PANEL_W - 2)) ||
                       (vc_d <  (PANEL_Y + 2)) || (vc_d >= (PANEL_Y + PANEL_H - 2));

    wire is_osd_d = (dat_o == C_NAVY) || (dat_o == C_RED) || (dat_o == C_PLATE);

    // 结构采样点（只依赖几何，不依赖 Logo 具体像素）
    wire spot_border = ((hc_d == 16)  && (vc_d == 16))  ||
                       ((hc_d == 223) && (vc_d == 171)) ||
                       ((hc_d == 222) && (vc_d == 50));
    wire spot_plate  = ((hc_d == 20)  && (vc_d == 20))  ||
                       ((hc_d == 221) && (vc_d == 169)) ||
                       ((hc_d == 100) && (vc_d == 160));
    wire spot_pass   = ((hc_d == 300) && (vc_d == 200)) ||
                       ((hc_d == 240) && (vc_d == 60));

    // ------------------------------------------------------------------ 逐拍错误统计
    reg [5:0] bad;
    always @(*) begin
        bad = 6'd0;
        if (de_o != de_d)                              bad = bad + 6'd1;  // 时序被打乱
        if (vs_o != vs_d)                              bad = bad + 6'd1;  // 场同步被改
        if (hs_o != hs_d)                              bad = bad + 6'd1;  // 行同步被改
        if (de_o && in_panel_d && !is_osd_d)           bad = bad + 6'd1;  // 面板内出现杂色
        if (de_o && !in_panel_d && (dat_o != dat_d))   bad = bad + 6'd1;  // 面板外没透传
        if (de_o && spot_border && (dat_o != C_NAVY))  bad = bad + 6'd1;
        if (de_o && spot_plate  && (dat_o != C_PLATE)) bad = bad + 6'd1;
        if (de_o && spot_pass   && (dat_o != dat_d))   bad = bad + 6'd1;
    end

    // ------------------------------------------------------------------ 帧尾标志 / 帧计数
    localparam NFRAMES = 3;                     // 连续检查 3 帧（验证 vs 帧对齐跨帧稳定）

    reg fin_q;                                  // 帧最后一个行周期之后 1 拍
    always @(posedge clk) begin
        if (!rst_n) fin_q <= 1'b0;
        else        fin_q <= (hc == (H_TOTAL - 1)) && (vc == (V_TOTAL - 1));
    end

    reg [3:0] frm;                              // 已完成帧数
    always @(posedge clk) begin
        if (!rst_n)     frm <= 4'd0;
        else if (fin_q) frm <= frm + 4'd1;
    end

    // ------------------------------------------------------------------ 统计 + 整帧哈希（每帧清零）
    reg [31:0] c_plate, c_border, c_navy, c_red;
    reg [31:0] err, hsh, n_pix;

    always @(posedge clk) begin
        if (!rst_n || fin_q) begin
            c_plate  <= 32'd0;
            c_border <= 32'd0;
            c_navy   <= 32'd0;
            c_red    <= 32'd0;
            err      <= 32'd0;
            hsh      <= 32'd0;
            n_pix    <= 32'd0;
        end else begin
            err <= err + {26'd0, bad};
            if (de_o) begin
                // h = h*33 + rgb，与黄金模型 ((h<<5)+h+rgb) & 0xFFFFFFFF 等价
                hsh   <= (hsh << 5) + hsh + {8'd0, dat_o};
                n_pix <= n_pix + 32'd1;
                if (in_panel_d) begin
                    if (on_border_d)           c_border <= c_border + 32'd1;
                    else if (dat_o == C_PLATE) c_plate  <= c_plate  + 32'd1;
                    else if (dat_o == C_RED)   c_red    <= c_red    + 32'd1;
                    else if (dat_o == C_NAVY)  c_navy   <= c_navy   + 32'd1;
                end
            end
        end
    end

    // ------------------------------------------------------------------ 首次出错现场打印（最多 8 条）
    reg [3:0] dbg_n;
    always @(posedge clk) begin
        if (!rst_n) dbg_n <= 4'd0;
        else if ((bad != 6'd0) && (dbg_n != 4'hF)) begin
            dbg_n <= dbg_n + 4'd1;
            if (dbg_n < 4'd8)
                $display("[OSD-TB] BAD=%0d @(x=%0d,y=%0d) de_o/d=%0d/%0d vs_o/d=%0d/%0d hs_o/d=%0d/%0d dat=%06x/%06x inp=%0d osd=%0d sp=%0d%0d%0d",
                         bad, hc_d, vc_d, de_o, de_d, vs_o, vs_d, hs_o, hs_d,
                         dat_o, dat_d, in_panel_d, is_osd_d, spot_border, spot_plate, spot_pass);
        end
    end

    // ------------------------------------------------------------------ 判据汇总（组合逻辑）
    reg [2:0] nfail_c;
    always @(*) begin
        nfail_c = 3'd0;
        if (n_pix    != (H_ACTIVE * V_ACTIVE)) nfail_c = nfail_c + 3'd1;
        if (c_border != EXP_BORDER)            nfail_c = nfail_c + 3'd1;
        if (c_plate  != EXP_PLATE)             nfail_c = nfail_c + 3'd1;
        if (c_navy   != EXP_NAVY)              nfail_c = nfail_c + 3'd1;
        if (c_red    != EXP_RED)               nfail_c = nfail_c + 3'd1;
        if (hsh      != EXP_HASH)              nfail_c = nfail_c + 3'd1;
        if (err      != 32'd0)                 nfail_c = nfail_c + 3'd1;
    end

    // ------------------------------------------------------------------ 帧尾报告
    reg all_ok;
    always @(posedge clk) begin
        if (!rst_n) all_ok <= 1'b1;
        else if (fin_q && (nfail_c != 3'd0)) all_ok <= 1'b0;
    end

    always @(posedge clk) begin
        if (rst_n && fin_q) begin
            $display("--------------------------------------------------------------");
            $display("[OSD-TB] frame #%0d  %0dx%0d  de pixels=%0d", frm, H_ACTIVE, V_ACTIVE, n_pix);
            $display("[OSD-TB] border : got %0d  exp %0d", c_border, EXP_BORDER);
            $display("[OSD-TB] plate  : got %0d  exp %0d", c_plate,  EXP_PLATE);
            $display("[OSD-TB] navy   : got %0d  exp %0d", c_navy,   EXP_NAVY);
            $display("[OSD-TB] red    : got %0d  exp %0d", c_red,    EXP_RED);
            $display("[OSD-TB] hash   : got %0d  exp %0d", hsh,      EXP_HASH);
            $display("[OSD-TB] errors : %0d", err);
            $display("[OSD-TB] this frame: %0s", (nfail_c == 3'd0) ? "MATCH" : "MISMATCH");

            if (frm == (NFRAMES - 1)) begin
                if (all_ok) $display("[OSD-TB] RESULT: *** PASS (%0d frames) ***", NFRAMES);
                else        $display("[OSD-TB] RESULT: *** FAIL ***");
                $finish;
            end
        end
    end

    // ------------------------------------------------------------------ 可选：导出 RTL 实际输出帧（仿真专用）
    //   +define+DUMP_FRAME 时，把第 2 帧的 de 像素按 RGB888 裸流写进 osd_frame.raw，
    //   再用 tools/raw2png.py 转成 PNG —— 这张图是“仿真器算出来的板子画面”，不是效果图。
`ifdef DUMP_FRAME
    /* verilator lint_off PROCASSINIT */
    integer fd;
    initial fd = $fopen("osd_frame.raw", "wb");
    /* verilator lint_on PROCASSINIT */
    always @(posedge clk) begin
        if (rst_n && de_o && (frm == 4'd1))
            $fwrite(fd, "%c%c%c", dat_o[23:16], dat_o[15:8], dat_o[7:0]);
        if (rst_n && fin_q && (frm == 4'd1)) begin
            $fclose(fd);
            $display("[OSD-TB] frame #1 dumped -> osd_frame.raw");
        end
    end
`endif

    // ------------------------------------------------------------------ 兜底超时
    always @(posedge clk) begin
        if (n_pix > (H_ACTIVE * V_ACTIVE + 16)) begin
            $display("[OSD-TB] RESULT: *** TIMEOUT / 多出像素 ***");
            $finish;
        end
    end

endmodule
