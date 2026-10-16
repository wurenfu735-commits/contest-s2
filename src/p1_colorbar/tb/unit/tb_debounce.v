// 按键消抖模块的独立验证：按下一次应输出 1 个脉冲
// 用参数化把时钟降到 1kHz，仿真几百拍即可验证逻辑（不必跑真实 74.25MHz）
`timescale 1ns/1ps
module tb_debounce;
    reg  clk   = 1'b0;
    reg  rst_n = 1'b0;
    reg  btn   = 1'b1;          // 未按下 = 高电平
    wire press;

    integer press_cnt = 0;

    debounce_btn #(
        .CLK_FREQ   (1000),     // 参数化：1kHz
        .STABLE_CNT (20)        // 20 个采样 = 20ms 等效
    ) dut (
        .I_clk   (clk),
        .I_rst_n (rst_n),
        .I_btn   (btn),
        .O_press (press)
    );

    always #500 clk = ~clk;     // 1kHz

    always @(posedge clk)
        if (press) press_cnt <= press_cnt + 1;

    initial begin
        $timeformat(-9, 0, "ns", 8);
        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (100) @(posedge clk);         // 静置：不应有脉冲
        $display("after idle: press_cnt = %0d (expect 0)", press_cnt);
        if (press_cnt != 0) $display("FAIL: idle generated pulse");

        // 第一次按下：拉低 50 拍
        btn = 1'b0;
        repeat (50) @(posedge clk);
        $display("after press1: press_cnt = %0d (expect 1)", press_cnt);

        // 松开：拉高 50 拍
        btn = 1'b1;
        repeat (50) @(posedge clk);
        $display("after release: press_cnt = %0d (expect 1)", press_cnt);

        // 第二次按下
        btn = 1'b0;
        repeat (50) @(posedge clk);
        $display("after press2: press_cnt = %0d (expect 2)", press_cnt);

        // 抖动测试：快速抖动 10 次（每次 3 拍），不应产生脉冲
        btn = 1'b1; repeat (30) @(posedge clk);
        begin : JITTER
            integer i;
            for (i = 0; i < 10; i = i + 1) begin
                btn = 1'b0; repeat (3) @(posedge clk);
                btn = 1'b1; repeat (3) @(posedge clk);
            end
        end
        btn = 1'b1;
        repeat (60) @(posedge clk);
        $display("after jitter: press_cnt = %0d (expect 2, jitter must be filtered)", press_cnt);

        if (press_cnt == 2) $display("ALL PASSED");
        else                $display("FAILED (press_cnt=%0d expect 2)", press_cnt);
        $finish;
    end
endmodule
