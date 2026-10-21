// cdc_mode_sync 独立验证：独热码跨域传递 + 帧起始锁存（防撕裂）
// 两个异步时钟（非整数倍关系）模拟 hdmi 像素域 → MIPI 字节域的真实跨域
`timescale 1ns/1ps
module tb_cdc_mode_sync;
    reg         clk_hdmi = 1'b0;
    reg         clk_csi  = 1'b0;
    reg         rst_n    = 1'b0;
    reg  [2:0]  mode_in  = 3'd2;
    reg  [1:0]  k_in     = 2'd2;
    reg         frame    = 1'b0;
    wire [2:0]  mode_out;
    wire [1:0]  k_out;

    cdc_mode_sync dut (
        .I_clk_hdmi    (clk_hdmi),
        .I_clk_csi     (clk_csi),
        .I_rst_n       (rst_n),
        .I_mode        (mode_in),
        .I_k           (k_in),
        .I_frame_start (frame),
        .O_mode        (mode_out),
        .O_k           (k_out)
    );

    always #10 clk_hdmi = ~clk_hdmi;   // 50MHz（周期 20ns）
    always #7  clk_csi  = ~clk_csi;    // ~71.4MHz（周期 14ns），与 hdmi 异步

    integer step = 0;
    integer errs = 0;

    // 在 csi 域发一帧起始脉冲：下降沿拉高，等锁存拍 + O_mode 非阻塞更新拍后清除
    task send_frame;
        begin
            @(negedge clk_csi);
            frame = 1'b1;
            @(posedge clk_csi);   // 锁存拍
            @(posedge clk_csi);   // 非阻塞更新拍
            frame = 1'b0;
        end
    endtask

    // 等待独热码两级同步稳定（>2 个 csi 周期）
    task wait_sync;
        begin
            repeat (5) @(posedge clk_csi);
        end
    endtask

    task check;
        input integer expect_mode;
        input integer expect_k;
        begin
            if (mode_out !== expect_mode[2:0] || k_out !== expect_k[1:0]) begin
                $display("FAIL step %0d: mode=%0d(expect %0d) k=%0d(expect %0d)",
                         step, mode_out, expect_mode, k_out, expect_k);
                errs = errs + 1;
            end else begin
                $display("PASS step %0d: mode=%0d k=%0d", step, mode_out, k_out);
            end
            step = step + 1;
        end
    endtask

    initial begin
        $timeformat(-9, 0, "ns", 8);
        repeat (8) @(posedge clk_csi);
        rst_n = 1'b1;
        repeat (8) @(posedge clk_csi);

        // 1. 复位默认值
        check(2, 2);

        // 2. 改模式但帧锁存未触发 → 输出不变（防撕裂核心）
        mode_in = 3'd0;
        wait_sync;
        check(2, 2);

        // 3. 发帧起始 → 锁存新值
        send_frame;
        check(0, 2);

        // 4. 依次验证全部 5 个模式都能正确传递（覆盖独热码 5 个码字）
        mode_in = 3'd4; wait_sync; send_frame; check(4, 2);
        mode_in = 3'd3; wait_sync; send_frame; check(3, 2);
        mode_in = 3'd1; wait_sync; send_frame; check(1, 2);
        mode_in = 3'd2; wait_sync; send_frame; check(2, 2);

        // 5. 灵敏度 k 的传递（4 档）
        k_in = 2'd1; wait_sync; send_frame; check(2, 1);
        k_in = 2'd3; wait_sync; send_frame; check(2, 3);
        k_in = 2'd0; wait_sync; send_frame; check(2, 0);

        if (errs == 0) $display("ALL PASSED");
        else           $display("FAILED with %0d error(s)", errs);
        $finish;
    end
endmodule
