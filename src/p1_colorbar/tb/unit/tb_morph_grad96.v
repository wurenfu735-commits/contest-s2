// tb_morph_grad96.v —— 形态学梯度 RTL 时序验证
// 用小图（32宽×16高）跑真实行缓存时序，验证 3×3 max-min 计算正确
// 激励：列 0..15 = 灰度 50，列 16..31 = 灰度 90（竖直线阶跃在列 15/16）
// 期望：跨阶跃的像素 3×3 含 50 和 90 → mag = 40；平坦区 mag = 0
// ModelSim SE-64 10.5 兼容（仅 Verilog-2001）
`timescale 1ns / 1ps

module tb_morph_grad96;

    localparam integer SIM_W = 32;      // 32 列 = 8 组
    localparam integer SIM_H = 16;
    localparam integer GRP   = SIM_W / 4;   // 8 组/行

    reg         I_clk;
    reg         I_rst_n;
    reg  [2:0]  I_mode;
    reg  [1:0]  I_k;
    reg         I_tlast;
    reg         I_tuser;
    reg  [95:0] I_tdata;
    reg         I_tvalid;
    wire        I_tready;
    wire        O_tlast;
    wire        O_tuser;
    wire [95:0] O_tdata;
    wire [31:0] O_mag;
    wire        O_tvalid;
    reg         O_tready;

    integer i, j;
    integer beat;
    integer err_cnt;
    integer saw_step;      // 是否看到 mag=40（阶跃）
    integer saw_flat;      // 是否看到 mag=0（平坦）

    // 小图例化（参数化，避免 1280×720 全帧仿真）
    morph_grad_96 #(
        .IMG_WIDTH  (SIM_W),
        .IMG_HEIGHT (SIM_H),
        .MORPH_THR  (8'd20)
    ) dut (
        .I_clk      (I_clk),
        .I_rst_n    (I_rst_n),
        .I_mode     (I_mode),
        .I_k        (I_k),
        .I_tlast    (I_tlast),
        .I_tuser    (I_tuser),
        .I_tdata    (I_tdata),
        .I_tvalid   (I_tvalid),
        .I_tready   (I_tready),
        .O_tlast    (O_tlast),
        .O_tuser    (O_tuser),
        .O_tdata    (O_tdata),
        .O_mag      (O_mag),
        .O_tvalid   (O_tvalid),
        .O_tready   (O_tready)
    );

    initial I_clk = 1'b0;
    always #5 I_clk = ~I_clk;

    // 构造 96bit：4 像素，每像素 R=G=B=gray（灰度化后 ≈ gray）
    function [95:0] mk4;
        input [7:0] v0, v1, v2, v3;
        begin
            mk4 = {v0, v0, v0, v1, v1, v1, v2, v2, v2, v3, v3, v3};
        end
    endfunction

    initial begin
        err_cnt  = 0;
        saw_step = 0;
        saw_flat = 0;
        beat     = 0;
        I_rst_n  = 1'b0;
        I_tvalid = 1'b0;
        I_tuser  = 1'b0;
        I_tlast  = 1'b0;
        I_mode   = 3'd2;
        I_k      = 2'd0;
        I_tdata  = 96'd0;
        O_tready = 1'b1;

        #20 I_rst_n = 1'b1;
        #10;

        // ---- 送 SIM_H 行 × GRP 组 ----
        for (j = 0; j < SIM_H; j = j + 1) begin
            for (i = 0; i < GRP; i = i + 1) begin
                @(negedge I_clk);
                I_tvalid = 1'b1;
                I_tuser  = (j == 0 && i == 0) ? 1'b1 : 1'b0;
                I_tlast  = (i == GRP - 1) ? 1'b1 : 1'b0;
                // 列 = i*4 + k；<16 为 50，>=16 为 90
                I_tdata = mk4(
                    (i*4 + 0 < 16) ? 8'd50 : 8'd90,
                    (i*4 + 1 < 16) ? 8'd50 : 8'd90,
                    (i*4 + 2 < 16) ? 8'd50 : 8'd90,
                    (i*4 + 3 < 16) ? 8'd50 : 8'd90
                );
            end
        end
        @(negedge I_clk);
        I_tvalid = 1'b0;
        I_tuser  = 1'b0;
        I_tlast  = 1'b0;

        #500;
        $display("---- 统计 ----");
        $display("saw_step(mag>=40)=%0d  saw_flat(mag==0)=%0d", saw_step, saw_flat);
        if (saw_step > 0 && saw_flat > 0)
            $display("==== tb_morph_grad96 PASS: 阶跃与平坦区都符合形态学梯度预期 ====");
        else
            $display("==== tb_morph_grad96 FAIL: 未同时观察到阶跃(40)与平坦(0) ====");
        $finish;
    end

    // ---- 监测输出：统计 mag 模式 ----
    always @(posedge I_clk) begin
        if (O_tvalid && I_rst_n) begin
            // O_mag = {mg3, mg2, mg1, mg0}
            if (O_mag[7:0]   >= 8'd39 && O_mag[7:0]   <= 8'd41) saw_step = saw_step + 1;
            if (O_mag[15:8]  >= 8'd39 && O_mag[15:8]  <= 8'd41) saw_step = saw_step + 1;
            if (O_mag[23:16] >= 8'd39 && O_mag[23:16] <= 8'd41) saw_step = saw_step + 1;
            if (O_mag[31:24] >= 8'd39 && O_mag[31:24] <= 8'd41) saw_step = saw_step + 1;
            if (O_mag[7:0]   == 8'd0) saw_flat = saw_flat + 1;
            if (O_mag[15:8]  == 8'd0) saw_flat = saw_flat + 1;
            if (O_mag[23:16] == 8'd0) saw_flat = saw_flat + 1;
            if (O_mag[31:24] == 8'd0) saw_flat = saw_flat + 1;
        end
    end

    // 打印前若干个有效输出的 mag（便于人工核对）
    integer print_cnt;
    initial print_cnt = 0;
    always @(posedge I_clk) begin
        if (O_tvalid && I_rst_n && print_cnt < 24) begin
            $display("mag: %0d %0d %0d %0d", O_mag[31:24], O_mag[23:16], O_mag[15:8], O_mag[7:0]);
            print_cnt = print_cnt + 1;
        end
    end

    initial begin
        #200000;
        $display("FAIL: timeout");
        $finish;
    end

endmodule
