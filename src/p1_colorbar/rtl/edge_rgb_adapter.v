// 测试图 -> 边缘检测 -> 四态显示（原图 / 官方判决 / 我们的判决 / 左右分屏）
//
// 数据流：RGB888 --灰度(R/4+G/2+B/4)--> edge_adaptive_pixel --+--> 我们的判决(自适应阈值+迟滞)
//                                                             |
//                                                             +--> 官方判决(固定阈值, 与 Python 复现一致)
// 两种判决共用同一套 Sobel 前端与 3x3 窗口，保证对比只体现"判决机制"的差异。
//
// 四态（I_mode）：0=原图直通  1=官方判决(固定阈值)  2=我们的判决  3=左右分屏(左官方/右我们)
// 对齐：算法的 O_valid/O_edge/O_mag 同拍输出；分屏判断用"输出流内的列计数"（天然与数据对齐）
module edge_rgb_adapter #(
    parameter IMG_WIDTH = 1280,
    parameter [11:0] OFFICIAL_THR = 12'd80      // 官方例程的固定阈值
)(
    input  wire        I_clk,
    input  wire        I_rst_n,
    input  wire        I_de,          // 数据有效
    input  wire        I_vs,          // 场同步
    input  wire [11:0] I_hcnt,        // 整幅时序列计数（有效区从 260 起）
    input  wire [23:0] I_rgb,         // 输入图案
    input  wire [1:0]  I_mode,        // 显示模式
    input  wire [1:0]  I_k,           // 亮度灵敏度档 0..3
    output wire        O_de,
    output wire        O_vs,
    output wire [23:0] O_rgb
);

    // 灰度化：R/4 + G/2 + B/4（与 Python 黄金模型逐位一致，最大 253）
    // 注意：三个分片先各自零扩展到 8 位再相加——若直接相加，表达式位宽按最大操作数(7 位)取，
    //       253 会被截断成 125
    wire [7:0] S_gray = {2'b00, I_rgb[23:18]} + {1'b0, I_rgb[15:9]} + {2'b00, I_rgb[7:2]};

    // 行首：有效区第一列
    wire S_line_start = I_de && (I_hcnt == 12'd260);

    // 算法：输出我们的判决 + Sobel 幅值（供官方判决复用同一条前端）
    wire        S_edge_valid;
    wire        S_edge_ours;
    wire [11:0] S_mag;
    edge_adaptive_pixel #(
        .IMG_WIDTH (IMG_WIDTH)
    ) u_edge (
        .I_clk   ( I_clk         ),
        .I_rst_n ( I_rst_n       ),
        .I_valid ( I_de          ),
        .I_sync  ( S_line_start  ),
        .I_gray  ( S_gray        ),
        .I_k     ( I_k           ),
        .O_valid ( S_edge_valid  ),
        .O_edge  ( S_edge_ours   ),
        .O_mag   ( S_mag         )
    );

    // 官方判决：固定阈值，无迟滞
    wire S_edge_off = (S_mag >= OFFICIAL_THR);

    // vs 延迟一拍，与算法输出的 O_valid 对齐
    reg S_vs_d1;
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) S_vs_d1 <= 1'b0;
        else          S_vs_d1 <= I_vs;
    end

    // 输出流内的列计数：与数据同拍，用于分屏判断
    // （若改用 I_hcnt 判断，因算法固有 3 列延迟会错位；计数器天然对齐）
    reg [10:0] S_out_col;
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) S_out_col <= 11'd0;
        else if (S_edge_valid)
            S_out_col <= (S_out_col == (IMG_WIDTH - 1)) ? 11'd0 : (S_out_col + 11'd1);
    end

    // 判决选择：分屏时左半屏用官方、右半屏用我们
    wire S_pick_off = (I_mode == 2'd1) || ((I_mode == 2'd3) && (S_out_col < (IMG_WIDTH / 2)));
    wire S_edge_out = S_pick_off ? S_edge_off : S_edge_ours;
    wire S_edge_mode = (I_mode != 2'd0);

    assign O_de  = S_edge_valid;
    assign O_vs  = S_vs_d1;
    assign O_rgb = S_edge_mode ? (S_edge_out ? 24'hFFFFFF : 24'h000000) : I_rgb;

endmodule
