// 1280x720@60 显示时序发生器，像素时钟 74.25MHz
// 行：1650 = 同步40 + 后沿220 + 有效1280 + 前沿110
// 场：750  = 同步5  + 后沿20  + 有效720  + 前沿5
// 各参数与官方 uivtc 的取值一致，这里独立实现，便于以后按分辨率调整
module vtc_720p #(
    parameter H_TOTAL  = 1650, parameter H_SYNC  = 40,
    parameter H_BACK   = 220,  parameter H_ACTIVE = 1280,
    parameter H_FRONT  = 110,
    parameter V_TOTAL  = 750,  parameter V_SYNC  = 5,
    parameter V_BACK   = 20,   parameter V_ACTIVE = 720,
    parameter V_FRONT  = 5
)(
    input  wire        I_clk,
    input  wire        I_rst_n,
    output reg         O_hsync,
    output reg         O_vsync,
    output reg         O_de,           // 有效像素区
    output reg  [11:0] O_hcnt,         // 列计数 0..1649
    output reg  [11:0] O_vcnt          // 行计数 0..749
);
    // 有效区范围：同步+后沿 之后 1280x720 像素
    localparam H_DE_START = H_SYNC + H_BACK;         // 260
    localparam H_DE_END   = H_DE_START + H_ACTIVE;   // 1540
    localparam V_DE_START = V_SYNC + V_BACK;         // 25
    localparam V_DE_END   = V_DE_START + V_ACTIVE;   // 745

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            O_hcnt <= 12'd0;
            O_vcnt <= 12'd0;
            O_hsync <= 1'b0;
            O_vsync <= 1'b0;
            O_de    <= 1'b0;
        end else begin
            if (O_hcnt == H_TOTAL - 1) begin
                O_hcnt <= 12'd0;
                O_vcnt <= (O_vcnt == V_TOTAL - 1) ? 12'd0 : O_vcnt + 1'd1;
            end else begin
                O_hcnt <= O_hcnt + 1'd1;
            end

            O_hsync <= (O_hcnt < H_SYNC);
            O_vsync <= (O_vcnt < V_SYNC);

            O_de <= (O_hcnt >= H_DE_START) && (O_hcnt < H_DE_END) &&
                    (O_vcnt >= V_DE_START) && (O_vcnt < V_DE_END);
        end
    end
endmodule