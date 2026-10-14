// 消抖模块「真实参数」验证：专门抓计数器位宽不足这类 bug
// 教训：之前用 1kHz 小参数做仿真，SAMPLE_MAX=1 掩盖了 16 位计数器装不下 74250 的缺陷，
//       上板后表现为"按键完全无反应"。所以必须有真实时钟参数的用例。
`timescale 1ns/1ps
module tb_debounce_real;
    // 真实像素时钟 74.25MHz（周期 ≈ 13.468ns）
    reg  clk   = 1'b1;
    reg  rst_n = 1'b0;
    reg  btn   = 1'b1;
    wire press;

    integer press_cnt = 0;
    integer i;

    debounce_btn #(
        .CLK_FREQ   (74_250_000),
        .STABLE_CNT (20)
    ) dut (
        .I_clk   (clk),
        .I_rst_n (rst_n),
        .I_btn   (btn),
        .O_press (press)
    );

    always #6.734 clk = ~clk;      // 74.25MHz

    always @(posedge clk)
        if (press) press_cnt <= press_cnt + 1;

    initial begin
        $timeformat(-9, 0, "ns", 8);

        // 复位
        repeat (10) @(posedge clk);
        rst_n = 1'b1;

        // 静置 30ms：真实参数下应当完全无脉冲
        // （30ms × 74.25MHz ≈ 222.75 万拍；若计数器位宽不足，此处也不会有脉冲，
        //   所以关键看后面按下时能否出脉冲）
        repeat (2_227_500) @(posedge clk);
        $display("[%0t] idle 30ms done: press_cnt = %0d (expect 0)", $time, press_cnt);
        if (press_cnt != 0) $display("FAIL: idle generated pulse");

        // 按下并保持 30ms（> 20ms 消抖时间）：应当产生 1 个脉冲
        btn = 1'b0;
        repeat (2_227_500) @(posedge clk);
        $display("[%0t] pressed 30ms: press_cnt = %0d (expect 1)", $time, press_cnt);

        // 松开 30ms
        btn = 1'b1;
        repeat (2_227_500) @(posedge clk);
        $display("[%0t] released 30ms: press_cnt = %0d (expect 1)", $time, press_cnt);

        // 再按一次
        btn = 1'b0;
        repeat (2_227_500) @(posedge clk);
        $display("[%0t] pressed again: press_cnt = %0d (expect 2)", $time, press_cnt);

        if (press_cnt == 2) $display("REAL-PARAM ALL PASSED");
        else                $display("REAL-PARAM FAILED (press_cnt=%0d expect 2) —— 检查计数器位宽是否够装 SAMPLE_MAX-1", press_cnt);
        $finish;
    end
endmodule
