// tb_perf_counter.v —— perf_counter 帧率/错误计数逻辑仿真
// ModelSim SE-64 10.5 兼容（仅 Verilog-2001）：不用 $error/$info，用 $display + $finish
// 加速：CLK_HZ 设小值（600），1 秒 = 600 拍，整跑约 1.1 秒模型时间
`timescale 1ns / 1ps

module tb_perf_counter;

    // 加速参数：1 秒 = 600 拍，60 fps = 每 10 拍一帧
    localparam integer SIM_CLK_HZ = 600;
    localparam integer FRAMES_PER_SEC = 60;
    localparam integer TICKS_PER_FRAME = SIM_CLK_HZ / FRAMES_PER_SEC;  // 10

    reg         I_clk;
    reg         I_rst_n;
    reg         I_vsync;
    reg         I_mipi_rx_error;

    wire [31:0] O_frame_cnt;
    wire [7:0]  O_fps;
    wire [15:0] O_err_cnt;
    wire        O_err_flag;

    integer i;
    integer errors;

    perf_counter #(
        .CLK_HZ(SIM_CLK_HZ)
    ) dut (
        .I_clk           (I_clk),
        .I_rst_n         (I_rst_n),
        .I_vsync         (I_vsync),
        .I_mipi_rx_error (I_mipi_rx_error),
        .O_frame_cnt     (O_frame_cnt),
        .O_fps           (O_fps),
        .O_err_cnt       (O_err_cnt),
        .O_err_flag      (O_err_flag)
    );

    // 100MHz 时钟（周期 10ns）
    initial I_clk = 1'b0;
    always #5 I_clk = ~I_clk;

    // 复位 + 激励
    initial begin
        errors = 0;
        I_rst_n = 1'b0;
        I_vsync = 1'b0;
        I_mipi_rx_error = 1'b0;

        // 复位 20ns
        #20 I_rst_n = 1'b1;
        #10;

        // ---- 第一秒：给 60 个 vsync 脉冲，周期 90ns（低80+高10）
        //      60×90=5400ns < 1秒(6000ns)，确保全部落在第一秒内被计数 ----
        for (i = 0; i < FRAMES_PER_SEC; i = i + 1) begin
            #80;
            I_vsync = 1'b1;
            #10;
            I_vsync = 1'b0;
        end

        // 第一秒结束（sec_cnt 在拍 603 ≈ 6030ns 满时锁存 fps_latch，等越过边界）
        #800;

        // 检查点 1：fps_latch 应 = 60
        if (O_fps !== 8'd60) begin
            $display("FAIL: O_fps=%0d, expected 60", O_fps);
            errors = errors + 1;
        end else begin
            $display("PASS: O_fps=%0d (第一秒锁存)", O_fps);
        end

        // 检查点 2：frame_cnt 应 = 60（总帧数）
        if (O_frame_cnt !== 32'd60) begin
            $display("FAIL: O_frame_cnt=%0d, expected 60", O_frame_cnt);
            errors = errors + 1;
        end else begin
            $display("PASS: O_frame_cnt=%0d", O_frame_cnt);
        end

        // ---- 注入 3 个 mipi_rx_error 脉冲（异步，长一点确保被采样）----
        // 每个脉冲高 25ns（约 2.5 拍），间隔 100ns
        for (i = 0; i < 3; i = i + 1) begin
            #50;
            I_mipi_rx_error = 1'b1;
            #25;
            I_mipi_rx_error = 1'b0;
            #50;
        end
        #50;   // 等 CDC 同步链稳定

        // 检查点 3：err_cnt 应 = 3
        if (O_err_cnt !== 16'd3) begin
            $display("FAIL: O_err_cnt=%0d, expected 3", O_err_cnt);
            errors = errors + 1;
        end else begin
            $display("PASS: O_err_cnt=%0d", O_err_cnt);
        end

        // 检查点 4：err_flag 应 = 1（错误发生过）
        if (O_err_flag !== 1'b1) begin
            $display("FAIL: O_err_flag=%0d, expected 1", O_err_flag);
            errors = errors + 1;
        end else begin
            $display("PASS: O_err_flag=%0d", O_err_flag);
        end

        // ---- 错误信号恢复 0 后，err_cnt 不应归零（累计，不自动清）----
        #200;
        if (O_err_cnt !== 16'd3) begin
            $display("FAIL: err_cnt 回落到 %0d（应为累计保持 3）", O_err_cnt);
            errors = errors + 1;
        end else begin
            $display("PASS: err_cnt 累计保持 %0d", O_err_cnt);
        end

        // ---- 总结 ----
        if (errors == 0)
            $display("==== tb_perf_counter ALL PASS ====");
        else
            $display("==== tb_perf_counter FAIL count=%0d ====", errors);
        $finish;
    end

    // 超时保护：跑太久自动停
    initial begin
        #1000000;
        $display("FAIL: timeout");
        $finish;
    end

endmodule
