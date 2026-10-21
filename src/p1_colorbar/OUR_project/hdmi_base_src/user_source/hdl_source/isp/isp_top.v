// ============================================================================
// isp_top.v —— 极简基线版（2026-10-21 重构）
//
// 只保留「原图实时显示」所需的最小通路：
//   demosaic(去马赛克) → data128_96 → awb(白平衡) → data_96bit_to_128bit
//
// 已剔除（不再综合）：
//   · edge_adaptive_96（自适应边缘检测）
//   · morph_grad_96（形态学梯度）
//   · cartoon_96（卡通化）
//   · 所有显示多路（mode 0/2/3/4/5 切换）
//   · I_mode / I_k 端口
//
// OSD 叠加不在这里做（在 design_top_wrapper 的 hdmi 像素域，见 osd_overlay）。
// 恢复算法：从 git 历史取回旧 isp_top.v 即可（本文件只做减法）。
// ============================================================================
module isp_top (
    input           axi4s_video_aclk,
    input           I_rst_n,
    input           I_tlast,
    input           I_tuser,
    input  [39:0]   I_tdata,
    input           I_tvalid,
    input  [9:0]    I_tdest,
    input           O_tready,
    output [127:0]  O_tdata,
    output          O_tlast,
    output          O_tuser,
    output          O_tvalid,
    output          I_tready
);

    wire         m_aixs_tvalid;
    wire [127:0] m_aixs_tdata;
    wire         m_aixs_tuser;
    wire         m_aixs_tlast;
    wire         m_aixs_tready;
    wire [ 95:0] m_aixs_tdata_96;

    wire         awb_O_tlast;
    wire         awb_O_tuser;
    wire [ 95:0] awb_O_tdata;
    wire         awb_O_tvalid;
    wire         awb_O_tready;

    wire         awb_O_tuser_128;
    wire         awb_O_tvalid_128;
    wire [127:0] awb_O_tdata_128;

    // 原图直通：awb 输出直接给 96→128 打包
    assign awb_O_tready = O_tready;
    assign O_tdata      = awb_O_tdata_128;
    assign O_tlast      = awb_O_tlast;
    assign O_tuser      = awb_O_tuser_128;
    assign O_tvalid     = awb_O_tvalid_128;

    demosaic #(
        .IMG_HEIGHT          (720 ),
        .IMG_WIDTH           (1280),
        .data_complete_delay (50  ),
        .BAYER_MODE          ("BGGR")
    ) u_demosaic (
        .I_clk              (axi4s_video_aclk),
        .I_rst_n            (I_rst_n),
        .axi4s_video_tdata  (I_tdata),
        .axi4s_video_tdest  (I_tdest),
        .axi4s_video_tlast  (I_tlast),
        .axi4s_video_tvalid (I_tvalid),
        .axi4s_video_tuser  (I_tuser),
        .axi4s_video_tready (I_tready),
        .O_tlast            (m_aixs_tlast),
        .O_tuser            (m_aixs_tuser),
        .O_tdata            (m_aixs_tdata),
        .O_tvalid           (m_aixs_tvalid),
        .O_tready           (m_aixs_tready)
    );

    data128_96 u_data128_96 (
        .I_tdata (m_aixs_tdata),
        .O_tdata (m_aixs_tdata_96)
    );

    awb #(
        .IMG_HEIGHT(720 ),
        .IMG_WIDTH (1280)
    ) u_awb (
        .I_clk   (axi4s_video_aclk),
        .I_rst_n (I_rst_n),
        .I_tlast (m_aixs_tlast),
        .I_tuser (m_aixs_tuser),
        .I_tdata (m_aixs_tdata_96),
        .I_tvalid(m_aixs_tvalid),
        .I_tready(m_aixs_tready),
        .O_tlast (awb_O_tlast ),
        .O_tuser (awb_O_tuser ),
        .O_tdata (awb_O_tdata ),
        .O_tvalid(awb_O_tvalid),
        .O_tready(awb_O_tready)
    );

    data_96bit_to_128bit u_data_96bit_to_128bit (
        .I_clk              ( axi4s_video_aclk  ),
        .I_rst_n            ( I_rst_n           ),
        .I_96b_frame_start  ( awb_O_tuser       ),
        .I_96b_valid        ( awb_O_tvalid      ),
        .I_96b_data         ( awb_O_tdata       ),
        .O_128b_frame_start ( awb_O_tuser_128   ),
        .O_128b_valid       ( awb_O_tvalid_128  ),
        .O_128b_data        ( awb_O_tdata_128   )
    );

endmodule
