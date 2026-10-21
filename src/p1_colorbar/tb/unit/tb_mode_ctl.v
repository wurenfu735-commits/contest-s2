// mode_ctl 独立验证：按键循环切模式（5 态）/灵敏度、复位兜底、抖动过滤
// 用参数化把时钟降到 1kHz、采样周期 1 拍，几百拍即可验证（不必跑真实 74.25MHz）
`timescale 1ns/1ps
module tb_mode_ctl;
    reg         clk   = 1'b0;
    reg         rst_n = 1'b0;
    reg  [3:0]  btn   = 4'b1111;   // 未按下 = 高电平
    wire [2:0]  mode;
    wire [1:0]  k;

    mode_ctl #(
        .CLK_FREQ   (1000),   // 参数化：采样周期 = 1 个时钟
        .STABLE_CNT (20)      // 稳定 20 个采样
    ) dut (
        .I_clk   (clk),
        .I_rst_n (rst_n),
        .I_btn   (btn),
        .O_mode  (mode),
        .O_k     (k)
    );

    always #500 clk = ~clk;   // 1kHz

    integer step = 0;
    integer errs = 0;

    // 按键按下：拉低 hold 拍后松开
    task press_key;
        input [1:0] idx;
        input integer hold;
        begin
            btn[idx] = 1'b0;
            repeat (hold) @(posedge clk);
            btn[idx] = 1'b1;
            repeat (60) @(posedge clk);
        end
    endtask

    task check;
        input integer expect_mode;
        input integer expect_k;
        begin
            if (mode !== expect_mode[2:0] || k !== expect_k[1:0]) begin
                $display("FAIL step %0d: mode=%0d(expect %0d) k=%0d(expect %0d)",
                         step, mode, expect_mode, k, expect_k);
                errs = errs + 1;
            end else begin
                $display("PASS step %0d: mode=%0d k=%0d", step, mode, k);
            end
            step = step + 1;
        end
    endtask

    initial begin
        $timeformat(-9, 0, "ns", 8);
        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (80) @(posedge clk);

        // 1. 复位默认值
        check(2, 2);

        // 2. KEY1 循环切模式（5 态）：2 -> 3 -> 4 -> 0 -> 1 -> 2
        press_key(0, 50);  check(3, 2);
        press_key(0, 50);  check(4, 2);
        press_key(0, 50);  check(0, 2);
        press_key(0, 50);  check(1, 2);
        press_key(0, 50);  check(2, 2);

        // 3. KEY2 循环切灵敏度：2 -> 3 -> 0
        press_key(1, 50);  check(2, 3);
        press_key(1, 50);  check(2, 0);

        // 4. KEY3 复位模式到默认 2
        press_key(0, 50);  check(3, 0);
        press_key(2, 50);  check(2, 0);

        // 5. KEY4 复位灵敏度到默认 2
        press_key(1, 50);  check(2, 1);
        press_key(3, 50);  check(2, 2);

        // 6. 抖动测试：快速抖动 KEY1（每次 2 拍），不应切模式
        begin : JITTER
            integer i;
            for (i = 0; i < 10; i = i + 1) begin
                btn[0] = 1'b0; repeat (2) @(posedge clk);
                btn[0] = 1'b1; repeat (2) @(posedge clk);
            end
        end
        btn[0] = 1'b1;
        repeat (60) @(posedge clk);
        check(2, 2);

        if (errs == 0) $display("ALL PASSED");
        else           $display("FAILED with %0d error(s)", errs);
        $finish;
    end
endmodule
