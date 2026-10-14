// 按键消抖（低有效按键）
// 74.25MHz 分频到 1kHz 采样，连续 20 次采样电平一致才确认状态，
// 稳定性从高变低（按下）时输出一拍 O_press 脉冲
// 不用乘除法，仅计数器与比较，资源几个 LUT + 寄存器
module debounce_btn #(
    parameter CLK_FREQ  = 74_250_000,
    parameter STABLE_CNT = 20          // 20ms @ 1kHz
)(
    input  wire I_clk,
    input  wire I_rst_n,
    input  wire I_btn,
    output reg  O_press
);
    localparam SAMPLE_MAX = CLK_FREQ / 1000;   // 一个采样周期内的时钟数

    // 位宽必须装得下 SAMPLE_MAX-1：74.25MHz 时为 74250（16 位装不下 65535 以上，
    // 会导致 sample_tick 永不产生、按键完全无反应）。24 位最大 16777215，
    // 覆盖本板所有时钟（50M / 74.25M / 148.5M）并留足余量。
    reg [23:0] sample_div;
    reg        sample_tick;
    reg [4:0]  cnt;
    reg        stable;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            sample_div  <= 16'd0;
            sample_tick <= 1'b0;
        end else if (sample_div == SAMPLE_MAX - 1) begin
            sample_div  <= 16'd0;
            sample_tick <= 1'b1;
        end else begin
            sample_div  <= sample_div + 1'd1;
            sample_tick <= 1'b0;
        end
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            cnt     <= 5'd0;
            stable  <= 1'b1;    // 上电视为未按下
            O_press <= 1'b0;
        end else begin
            O_press <= 1'b0;
            if (sample_tick) begin
                if (I_btn != stable) begin
                    if (cnt == STABLE_CNT - 1) begin
                        stable <= I_btn;
                        cnt    <= 5'd0;
                        // 稳定之后确认按下
                        if (I_btn == 1'b0)
                            O_press <= 1'b1;
                    end else begin
                        cnt <= cnt + 1'd1;
                    end
                end else begin
                    cnt <= 5'd0;
                end
            end
        end
    end
endmodule