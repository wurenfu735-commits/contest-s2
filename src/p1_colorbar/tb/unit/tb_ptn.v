// P1 v1 仿真：验证 vtc_720p 与 test_pattern_gen 两个模块
// （hdmi_tx 依赖 TD IP 生成件，不进本仿真）
// 像素时钟按 74.25MHz（周期 13.468ns），跑 3 帧
// 检查项：
//   - 帧结构：hsync 宽度 40 拍、de 有效像素总数 1280*720*3、末个有效像素 de=1
//   - 图案：色彩条 6 段颜色抽查、棋盘格 1 格、状态带上/下带颜色
// 与前版差异：全部检查放在同一个 initial 里按顺序执行，
// 图案切换由该块显式控制，避免多个并行块争用 psel 造成误判
// ModelSim 控制台按 ANSI 显示，打印文本一律英文
//
// 运行（命令行模式，只打印）：
//   vlib work
//   vlog -work work ../rtl/vtc_720p.v ../rtl/test_pattern_gen.v ./tb_ptn.v
//   vsim -c -do "run -all; quit -f" work.tb_ptn
// 或（GUI 模式，带波形）：do run_tb.do
`timescale 1ns/1ps
module tb_ptn;
    reg         clk      = 1'b0;
    reg         rst_n    = 1'b0;
    reg         pll_lock = 1'b0;
    reg  [1:0]  psel     = 2'd0;

    wire        hsync, vsync, de;
    wire [11:0] hcnt, vcnt;
    wire [23:0] rgb;

    vtc_720p dut_vtc(
        .I_clk(clk), .I_rst_n(rst_n),
        .O_hsync(hsync), .O_vsync(vsync), .O_de(de),
        .O_hcnt(hcnt), .O_vcnt(vcnt)
    );

    test_pattern_gen dut_tpg(
        .I_clk(clk), .I_rst_n(rst_n),
        .I_de(de), .I_hcnt(hcnt), .I_vcnt(vcnt),
        .I_pattern_sel(psel), .I_pll_lock(pll_lock),
        .O_rgb(rgb)
    );

    always #6.734 clk = ~clk;

    integer err_cnt = 0;
    integer de_cnt  = 0;   // 最大 1280*720*3，integer(32位)足够

    // 主检查流程：单一 initial 顺序执行
    initial begin
        $timeformat(-9, 0, "ns", 8);

        // 复位 5 拍后释放，PLL 置锁
        rst_n    = 1'b0;
        pll_lock = 1'b0;
        repeat(5) @(posedge clk);
        rst_n    = 1'b1;
        pll_lock = 1'b1;

        // ---- 1) hsync 宽度：在一行里数高电平拍数 ----
        wait (vcnt == 12'd0 && hcnt == 12'd0);
        hsync_width_chk;

        // ---- 2) 彩条图案（psel=0）：v=100 行，列取每段中央 ----
        wait (vcnt == 12'd100);
        probe_at(300,  24'hFFFFFF, "colorbar col0 white");
        probe_at(480,  24'hFFFF00, "colorbar col1 yellow");
        probe_at(640,  24'h00FFFF, "colorbar col2 cyan");
        probe_at(960,  24'hFF00FF, "colorbar col4 magenta");
        probe_at(1280, 24'h0000FF, "colorbar col6 blue");
        probe_at(1440, 24'h000000, "colorbar col7 black");

        // ---- 3) 状态带（psel=0）：画面行 704..719 即 vcnt 729..744 ----
        wait (vcnt == 12'd732);
        probe_at(300, 24'hFFFFFF, "band top = pattern white");
        wait (vcnt == 12'd740);
        probe_at(300, 24'h00FF00, "band bottom = PLL green");

        // ---- 4) 棋盘（psel=1）采样一帧后切回 ----
        wait (vcnt == 12'd0 && hcnt == 12'd0);
        psel = 2'd1;
        wait (vcnt == 12'd48);
        // h=264 -> 画面列 4（lx[4]=0）；v=48 -> 画面行 23（ly[4]=1），异或=1，白
        probe_at(264, 24'hFFFFFF, "checker sample");
        psel = 2'd0;

        // ---- 5) 末个有效像素 ----
        wait (vcnt == 12'd744 && hcnt == 12'd1539);
        @(posedge clk);
        if (de != 1'b1) begin
            $display("ERROR: de=0 at last active pixel");
            err_cnt = err_cnt + 1;
        end else begin
            $display("OK: de=1 at last active pixel");
        end

        // ---- 6) 总量：跑满 3 帧同期统计 de 拍数 ----
        repeat (1650 * 750 * 3) begin
            @(posedge clk);
            if (de) de_cnt = de_cnt + 1;
        end
        $display("TOTAL de beats = %0d (expect %0d)", de_cnt, 1280*720*3);
        if (de_cnt != 1280*720*3) begin
            $display("ERROR: total de count mismatch");
            err_cnt = err_cnt + 1;
        end else begin
            $display("OK: total de count");
        end

        finish_report;
    end

    // 数从当前拍起 1650 拍里 hsync 高电平拍数，应为 40
    task hsync_width_chk;
        integer h_high;
        integer i;
        begin
            h_high = 0;
            for (i = 0; i < 1650; i = i + 1) begin
                @(posedge clk);
                if (hsync) h_high = h_high + 1;
            end
            if (h_high != 40) begin
                $display("ERROR: hsync width = %0d expect 40", h_high);
                err_cnt = err_cnt + 1;
            end else begin
                $display("OK: hsync width 40");
            end
        end
    endtask

    // 当前行内对齐到列 x，其后 4 拍窗口里 rgb 出现 expect 即通过
    // （rgb 相对行列计数有一拍寄存延迟，看窗口不赌单拍）
    task probe_at(input [11:0] x, input [23:0] expect,
                  input [8*24-1:0] name);
        reg found;
        integer k;
        begin
            while (hcnt != x) @(posedge clk);
            found = 1'b0;
            begin : WIN
                for (k = 0; k < 4; k = k + 1) begin
                    @(posedge clk);
                    if (rgb === expect) begin
                        found = 1'b1;
                        disable WIN;
                    end
                end
            end
            if (found) begin
                $display("OK: %s", name);
            end else begin
                $display("ERROR: %s @(x=%0d,y=%0d) never got %h",
                         name, x, vcnt, expect);
                err_cnt = err_cnt + 1;
            end
        end
    endtask

    task finish_report;
        begin
            if (err_cnt == 0)
                $display("ALL PASSED");
            else
                $display("FAILED with %0d error(s)", err_cnt);
        end
    endtask

endmodule