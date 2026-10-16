// 算法模块独立综合探针
//
// 目的：判定 edge_adaptive_pixel 单独综合时，能否产生 Sobel 的加法器。
//   工程里它只报告 49 LUT / 0 ripple（ripple = 进位链，0 表示没有加法器），
//   而按代码应有 ~250 LUT。本探针把它的输出经 keep 保住后引到端口，
//   排除"输出未被使用导致整片被优化"的可能。
//
// 用法（独立小工程，约 3 分钟）：
//   1. TD 新建工程，器件 PH1P35MDG324-3
//   2. 添加这些文件：
//        sim\eram_probe\algo_probe.v                                    （本文件）
//        src\p1_colorbar\rtl\edge_adaptive_pixel.v
//        OUR_project\hdmi_base_src\user_source\hdl_source\isp\demosaic_4x_2_0\
//            blk_mem_gen_zhenghe\blk_mem_gen_zhenghe.v
//        ...\blk_mem_gen_zhenghe\RTL\ram_d32970204f32.v
//   3. 顶层设为 algo_probe，跑综合
//   4. 看资源报告：
//        #lut6 明显增加（几百）+ 有进位链  -> 算法代码本身没问题，是集成层的问题
//        #lut6 仍很小、无进位链            -> 算法代码本身被综合器判为无效，需改写法
module algo_probe (
    input  wire       clk,
    input  wire       rst_n,
    output wire [7:0] led
);
    // 造一个 1280×N 的扫描时序 + 棋盘状灰度（保证 Sobel 有非零输出）
    reg [10:0] col;
    reg [9:0]  row;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            col <= 11'd0;
            row <= 10'd0;
        end else begin
            col <= (col == 11'd1279) ? 11'd0 : (col + 11'd1);
            if (col == 11'd1279) row <= row + 10'd1;
        end
    end

    wire        sync = (col == 11'd0);
    (* keep = "true" *) wire [7:0] gray = col[7:0] ^ row[7:0];

    wire o_valid;
    wire o_edge;
    (* keep = "true" *) wire [11:0] o_mag;

    edge_adaptive_pixel #(
        .IMG_WIDTH (1280)
    ) u_edge (
        .I_clk   ( clk      ),
        .I_rst_n ( rst_n    ),
        .I_valid ( 1'b1     ),
        .I_sync  ( sync     ),
        .I_gray  ( gray     ),
        .I_k     ( 2'd2     ),
        .O_valid ( o_valid  ),
        .O_edge  ( o_edge   ),
        .O_mag   ( o_mag    )
    );

    // keep 保住输出，防止"未使用"被优化
    assign led = o_mag[7:0] ^ {7'd0, o_edge};

endmodule
