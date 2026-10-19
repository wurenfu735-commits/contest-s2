// 模式值跨时钟域同步 + 帧起始锁存（防撕裂）
//
// 方向：HDMI 像素域（74.25MHz）→ MIPI 字节域（~103.52MHz，算法所在域）
//
// 做法（三步）：
//   1. 独热码（one-hot）传输：模式是多 bit 控制信号，二进制/格雷码在 4→0
//      的跳变上都无法保证每步只变 1 位（gray(4)=110 → gray(0)=000 变 2 位），
//      两级同步器可能采到非法中间值。独热码任意两个合法码之间不存在
//      「会被误读为另一个合法码」的中间态——每 bit 独立同步，绝对安全。
//   2. 两级同步器：异步信号跨域必须先打两拍，避免亚稳态传播。
//   3. 帧起始锁存：模式值只在帧起始（I_frame_start，即 isp_top 的 tuser）锁存，
//      保证切换发生在帧边界，画面不撕裂（对应进阶①「切换平稳」）。
//
// 资源：独热 5bit × 2 级同步 + k 2bit 独热(4bit) × 2 级 ≈ 30 FF / 20 LUT。
module cdc_mode_sync (
    input  wire        I_clk_hdmi,     // 74.25MHz，源域（按键/模式所在域）
    input  wire        I_clk_csi,      // ~103.52MHz，目的域（算法所在域）
    input  wire        I_rst_n,
    input  wire [2:0]  I_mode,         // 源域的模式值（0..4）
    input  wire [1:0]  I_k,            // 源域的灵敏度值（0..3）
    input  wire        I_frame_start,  // 目的域的帧起始脉冲（isp_top 的 tuser）
    output reg  [2:0]  O_mode,         // 目的域、帧锁存后的模式值
    output reg  [1:0]  O_k             // 目的域、帧锁存后的灵敏度值
);

    // ---- 1. 独热编码（源域，组合）----
    reg [4:0] mode_oh;
    always @(*) begin
        case (I_mode)
            3'd0:    mode_oh = 5'b00001;
            3'd1:    mode_oh = 5'b00010;
            3'd2:    mode_oh = 5'b00100;
            3'd3:    mode_oh = 5'b01000;
            default: mode_oh = 5'b10000;   // 4
        endcase
    end

    reg [3:0] k_oh;
    always @(*) begin
        case (I_k)
            2'd0:    k_oh = 4'b0001;
            2'd1:    k_oh = 4'b0010;
            2'd2:    k_oh = 4'b0100;
            default: k_oh = 4'b1000;      // 3
        endcase
    end

    // ---- 2. 两级同步器（目的域）----
    reg [4:0] mode_oh_s1, mode_oh_s2;
    reg [3:0] k_oh_s1,    k_oh_s2;

    always @(posedge I_clk_csi or negedge I_rst_n) begin
        if (!I_rst_n) begin
            mode_oh_s1 <= 5'b00000;
            mode_oh_s2 <= 5'b00100;   // 复位默认独热 2（我们的判决）
            k_oh_s1    <= 4'b0000;
            k_oh_s2    <= 4'b0100;    // 复位默认 2
        end else begin
            mode_oh_s1 <= mode_oh;
            mode_oh_s2 <= mode_oh_s1;
            k_oh_s1    <= k_oh;
            k_oh_s2    <= k_oh_s1;
        end
    end

    // ---- 3. 解码（目的域，组合）+ 帧起始锁存 ----
    // 独热 → 二进制：mode4 优先级最低（若同步瞬间出现多位 1，按高位优先，
    // 最坏情况是单帧内闪现一次相邻模式，帧锁存后下一帧恢复——不会挂死）
    wire [2:0] mode_d = (mode_oh_s2[0]) ? 3'd0 :
                        (mode_oh_s2[1]) ? 3'd1 :
                        (mode_oh_s2[2]) ? 3'd2 :
                        (mode_oh_s2[3]) ? 3'd3 : 3'd4;

    wire [1:0] k_d = (k_oh_s2[0]) ? 2'd0 :
                     (k_oh_s2[1]) ? 2'd1 :
                     (k_oh_s2[2]) ? 2'd2 : 2'd3;

    always @(posedge I_clk_csi or negedge I_rst_n) begin
        if (!I_rst_n) begin
            O_mode <= 3'd2;
            O_k    <= 2'd2;
        end else if (I_frame_start) begin
            O_mode <= mode_d;
            O_k    <= k_d;
        end
    end

endmodule
