module isp_top (
    input 			axi4s_video_aclk,
    input 			I_rst_n			,
    input 			I_tlast			,
    input 			I_tuser			,
    input [39:0] 	I_tdata			,
    input 			I_tvalid		,
    input [9:0] 	I_tdest			,
    input 			O_tready		,
    input [2:0] 	I_mode			,   // 0原图 2我们边缘 3分屏(原图|卡通) 4卡通化 5形态学梯度
    input [1:0] 	I_k				,   // 自适应阈值灵敏度档 0..3
    output [127:0] 	O_tdata			,
    output 			O_tlast			,
    output 			O_tuser			,
    output 			O_tvalid		,
    output 			I_tready
);
 
wire         m_aixs_tvalid;  //synthesis keep 
  wire [127:0] m_aixs_tdata;  //synthesis keep 
  wire         m_aixs_tuser;  //synthesis keep 
  wire         m_aixs_tlast;  //synthesis keep 
  wire         m_aixs_tready;  //synthesis keep 
  
  wire [ 95:0] m_aixs_tdata_96;  //synthesis keep 


  wire         awb_O_tlast;  //synthesis keep 
  wire         awb_O_tuser;  //synthesis keep 
  wire [ 95:0] awb_O_tdata;  //synthesis keep 
  wire         awb_O_tvalid;  //synthesis keep 
  wire         awb_O_tready;  //synthesis keep 

  wire         awb_O_tuser_128;  //synthesis keep 
  wire         awb_O_tvalid_128;  //synthesis keep 
  wire [127:0] awb_O_tdata_128;  //synthesis keep 

  // ===== 自研：自适应阈值边缘检测（4 像素/拍，全分辨率，因果双阈值迟滞）=====
  wire         edge_O_tlast;  //synthesis keep
  wire         edge_O_tuser;  //synthesis keep
  wire [ 95:0] edge_O_tdata;  //synthesis keep
  wire [ 31:0] edge_O_mag;    //synthesis keep  梯度灰阶（供边缘叠加）
  wire         edge_O_tvalid; //synthesis keep
  wire         edge_O_tready; //synthesis keep


  assign awb_O_tready = edge_O_tready;
  assign edge_O_tready = O_tready;
  assign O_tdata  = awb_O_tdata_128;
  assign O_tlast  = awb_O_tlast    ;
  assign O_tuser  = awb_O_tuser_128    ;
  assign O_tvalid = awb_O_tvalid_128   ;
  
  //assign m_aixs_tready = O_tready;
  //assign O_tdata  = m_aixs_tdata;
  //assign O_tlast  = m_aixs_tlast    ;
  //assign O_tuser  = m_aixs_tuser    ;
  //assign O_tvalid = m_aixs_tvalid   ;
 
 
demosaic #(
    .IMG_HEIGHT          (720 ),  // 图像高度
    .IMG_WIDTH           (1280),  // 图像宽度
    .data_complete_delay (50  ),
    .BAYER_MODE          ("BGGR")
)
u_demosaic
(
    .I_clk   			(axi4s_video_aclk)	,   // 时钟信号
    .I_rst_n 			(I_rst_n)	,   // 复位信号，低有效
    .axi4s_video_tdata 	(I_tdata)	,  // AXI4-Stream视频数据
    .axi4s_video_tdest 	(I_tdest)	,
    .axi4s_video_tlast 	(I_tlast)	,  // 行结束信号
    .axi4s_video_tvalid	(I_tvalid)	,  // 数据有效信号
    .axi4s_video_tuser 	(I_tuser)	,  // 帧开始信号
    .axi4s_video_tready	(I_tready)	,  // 从模块准备好接受数据
    .O_tlast  			(m_aixs_tlast)	,  // 输出行结束信号
    .O_tuser  			(m_aixs_tuser)	,  // 输出帧开始信号
    .O_tdata  			(m_aixs_tdata)	,  // 输出数据
    .O_tvalid 			(m_aixs_tvalid)	,  // 输出数据有效信号
    .O_tready   		(m_aixs_tready)	   // 输出数据准备好信号
);
 
data128_96 u_data128_96 (
    .I_tdata(m_aixs_tdata),
    .O_tdata(m_aixs_tdata_96)
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

  // 自研算法插在 awb 与 data_96bit_to_128bit 之间（与官方 lab_ex2 的 edge_detect_96 同位置）
  edge_adaptive_96 #(
      .IMG_WIDTH  (1280),
      .IMG_HEIGHT (720),
      .THR_FLOOR  (11'd96)    // v5 分段地板基准：四档 = 144/132/116/96（偏移量走模块默认 48/36/20/0）
  ) u_edge_adaptive_96 (
      .I_clk   (axi4s_video_aclk),
      .I_rst_n (I_rst_n),
      .I_mode  (I_mode),     // 五态（顶层按键驱动，经 cdc_mode_sync 帧锁存后传入）
      .I_k     (I_k),        // 灵敏度档
      .I_tlast (awb_O_tlast),
      .I_tuser (awb_O_tuser),
      .I_tdata (awb_O_tdata),
      .I_tvalid(awb_O_tvalid),
      .I_tready(awb_O_tready),
      .O_tlast (edge_O_tlast),
      .O_tuser (edge_O_tuser),
      .O_tdata (edge_O_tdata),
      .O_mag   (edge_O_mag),
      .O_tvalid(edge_O_tvalid),
      .O_tready(edge_O_tready)
  );

  // ---- 第二算法：形态学梯度（2026-10-19，高阶①多算法切换）----
  //   与 edge_adaptive_96 并行例化（同输入、同 3 拍延迟），mode 5 时选它
  //   注意：.I_tready 悬空 —— 上游 ready 已由 edge_adaptive_96 驱动，避免多驱动
  wire         morph_O_tlast;   //synthesis keep
  wire         morph_O_tuser;   //synthesis keep
  wire [ 95:0] morph_O_tdata;   //synthesis keep
  wire [ 31:0] morph_O_mag;     //synthesis keep
  wire         morph_O_tvalid;  //synthesis keep

  morph_grad_96 #(
      .IMG_WIDTH  (1280),
      .IMG_HEIGHT (720),
      .MORPH_THR  (8'd20)     // 形态学梯度阈值（演示可调：小=边缘更粗）
  ) u_morph_grad_96 (
      .I_clk   (axi4s_video_aclk),
      .I_rst_n (I_rst_n),
      .I_mode  (I_mode),
      .I_k     (I_k),
      .I_tlast (awb_O_tlast),
      .I_tuser (awb_O_tuser),
      .I_tdata (awb_O_tdata),
      .I_tvalid(awb_O_tvalid),
      .I_tready(),                    // 悬空：上游 ready 由 edge_adaptive_96 驱动
      .O_tlast (morph_O_tlast),
      .O_tuser (morph_O_tuser),
      .O_tdata (morph_O_tdata),
      .O_mag   (morph_O_mag),
      .O_tvalid(morph_O_tvalid),
      .O_tready(edge_O_tready)        // 下游 ready（与 edge 同）
  );

  // ---- 算法选择：mode 5 = 形态学梯度，其他 = 平滑梯度（edge_adaptive_96）----
  wire         S_algo_is_morph = (I_mode == 3'd5);                          //synthesis keep
  wire [ 95:0] algo_tdata = S_algo_is_morph ? morph_O_tdata : edge_O_tdata;  //synthesis keep
  wire [ 31:0] algo_mag   = S_algo_is_morph ? morph_O_mag   : edge_O_mag;   //synthesis keep
  wire         algo_valid = S_algo_is_morph ? morph_O_tvalid: edge_O_tvalid; //synthesis keep
  wire         algo_last  = S_algo_is_morph ? morph_O_tlast : edge_O_tlast;  //synthesis keep
  wire         algo_user  = S_algo_is_morph ? morph_O_tuser : edge_O_tuser;  //synthesis keep

  // ---- 卡通化（mode 4 全屏 / mode 3 右半屏）：复用算法边缘，把边缘融进彩色画面 ----
  //   颜色量化 + 边缘压黑，既是更好的视觉呈现，又是赛题扩展①「风格化/视觉增强」。
  wire [ 95:0] cartoon_O_tdata;
  wire         cartoon_O_valid;
  wire         cartoon_O_last;
  wire         cartoon_O_user;
  cartoon_96 u_cartoon (
      .I_clk        (axi4s_video_aclk),
      .I_rst_n      (I_rst_n),
      .I_orig       (awb_O_tdata),
      .I_orig_valid (awb_O_tvalid),
      .I_edge       (algo_tdata),
      .I_valid      (algo_valid),
      .I_last       (algo_last),
      .I_user       (algo_user),
      .O_tdata      (cartoon_O_tdata),
      .O_valid      (cartoon_O_valid),
      .O_last       (cartoon_O_last),
      .O_user       (cartoon_O_user)
  );

  // ---- mode 3 分屏（左原图 / 右卡通）：原图额外延迟 4 拍对齐卡通输出相位 ----
  //   卡通输出相位 = 原图入 3 拍(内部延迟) + 1 拍(输出寄存) = 4 拍；
  //   左半屏原图也延迟 4 拍，使左右同相、列计数一致。
  (* keep = "true" *) reg [95:0] od1, od2, od3, od4;
  always @(posedge axi4s_video_aclk or negedge I_rst_n) begin
      if (!I_rst_n) begin
          od1 <= 96'd0; od2 <= 96'd0; od3 <= 96'd0; od4 <= 96'd0;
      end else if (awb_O_tvalid) begin
          od1 <= awb_O_tdata; od2 <= od1; od3 <= od2; od4 <= od3;
      end
  end

  // 卡通相位下的「行内拍计数」：本通路每拍 = 4 像素 → 1280/4 = 320 拍/行
  //   关键：必须每行末(cartoon_O_last)清零；只在帧首(cartoon_O_user)清零会退化成
  //   "按 4 行一组的上/下色带"（因为 320 拍/行撑不到 1280 才复位）。
  //   split_left 用「拍」比较：640 px / 4 px每拍 = 160 拍。
  reg [9:0] split_col;                       // 0..319（每行 320 拍）
  always @(posedge axi4s_video_aclk or negedge I_rst_n) begin
      if (!I_rst_n)             split_col <= 10'd0;
      else if (cartoon_O_user)  split_col <= 10'd0;
      else if (cartoon_O_last)  split_col <= 10'd0;   // 每行复位（关键修复）
      else if (cartoon_O_valid) split_col <= (split_col == 10'd319) ? 10'd0 : (split_col + 10'd1);
  end
  wire split_left = (split_col < 10'd160);   // 左半屏 = 原图（0..159 拍 = 0..639 px）

  // ---- 显示多路（各分支自带 valid/last/user，相位自洽；帧锁存兜底防撕裂）----
  //   mode 0：原图(awb, 0 拍)
  //   mode 2：我们的边缘二值图(算法, 3 拍)
  //   mode 3：左原图 / 右卡通（卡通相位）
  //   mode 4：卡通化（卡通相位）
  //   mode 5：形态学梯度二值图(算法, 3 拍)
  wire        S_disp_is_orig    = (I_mode == 3'd0);
  wire        S_disp_is_cartoon = (I_mode == 3'd4);
  wire        S_disp_is_split   = (I_mode == 3'd3);
  // mode 2/5 -> 算法二值图（algo_tdata 已按 mode 选 edge/morph）
  // 显示反相：白底黑线。注意 algo_tdata 原值仍直送 cartoon_96 判边（edge=非0），
  //   此处只在「显示」支路反相，切勿改 O_tdata 本身，否则卡通化判边会翻转。
  wire [ 95:0] algo_tdata_disp  = ~algo_tdata;   // 黑<->白 互换（仅显示用）

  wire [ 95:0] S_disp_tdata =
      S_disp_is_orig    ? awb_O_tdata :
      S_disp_is_cartoon ? cartoon_O_tdata :
      S_disp_is_split   ? (split_left ? od4 : cartoon_O_tdata) :
                          algo_tdata_disp;       // mode 2 / 5（白底黑线）

  wire         S_disp_tuser =
      S_disp_is_orig    ? awb_O_tuser :
      S_disp_is_cartoon ? cartoon_O_user :
      S_disp_is_split   ? cartoon_O_user :
                          algo_user;

  wire         S_disp_tvalid =
      S_disp_is_orig    ? awb_O_tvalid :
      S_disp_is_cartoon ? cartoon_O_valid :
      S_disp_is_split   ? cartoon_O_valid :
                          algo_valid;

  wire         S_disp_tlast =
      S_disp_is_orig    ? awb_O_tlast :
      S_disp_is_cartoon ? cartoon_O_last :
      S_disp_is_split   ? cartoon_O_last :
                          algo_last;

    data_96bit_to_128bit u_data_96bit_to_128bit(
        .I_clk              ( axi4s_video_aclk  ),
        .I_rst_n            ( I_rst_n           ),
	
        .I_96b_frame_start  ( S_disp_tuser      ),
        .I_96b_valid        ( S_disp_tvalid     ),
        .I_96b_data         ( S_disp_tdata      ),
	
        .O_128b_frame_start ( awb_O_tuser_128  	),
        .O_128b_valid       ( awb_O_tvalid_128 	),
        .O_128b_data        ( awb_O_tdata_128  	)
    );



//data96_128 u_data96_128 (
//    .I_tdata(awb_O_tdata),
//    .O_tdata(awb_O_tdata_128)
//);
	
endmodule


// Four-pixel RGB888 gamma stage.  The 16-segment curve approximates
// y = 255 * (x / 255)^0.7.  It lifts shadows and mid-tones while preserving
// black and white and adds one registered pipeline cycle.
module axis_gamma_rgb96 (
    input  wire        I_clk,
    input  wire        I_rst_n,
    input  wire        I_tlast,
    input  wire        I_tuser,
    input  wire [95:0] I_tdata,
    input  wire        I_tvalid,
    output reg         O_tlast,
    output reg         O_tuser,
    output reg  [95:0] O_tdata,
    output reg         O_tvalid
);

    function [7:0] gamma07;
        input [7:0] value;
        reg [7:0] base;
        reg [7:0] delta;
        reg [11:0] interpolation;
        begin
            case (value[7:4])
                4'h0: begin base = 8'd0;   delta = 8'd37; end
                4'h1: begin base = 8'd37;  delta = 8'd23; end
                4'h2: begin base = 8'd60;  delta = 8'd19; end
                4'h3: begin base = 8'd79;  delta = 8'd18; end
                4'h4: begin base = 8'd97;  delta = 8'd16; end
                4'h5: begin base = 8'd113; delta = 8'd16; end
                4'h6: begin base = 8'd129; delta = 8'd14; end
                4'h7: begin base = 8'd143; delta = 8'd14; end
                4'h8: begin base = 8'd157; delta = 8'd14; end
                4'h9: begin base = 8'd171; delta = 8'd13; end
                4'ha: begin base = 8'd184; delta = 8'd13; end
                4'hb: begin base = 8'd197; delta = 8'd12; end
                4'hc: begin base = 8'd209; delta = 8'd12; end
                4'hd: begin base = 8'd221; delta = 8'd12; end
                4'he: begin base = 8'd233; delta = 8'd11; end
                default: begin base = 8'd244; delta = 8'd11; end
            endcase

            interpolation = delta * value[3:0] + 8;
            if (value == 8'hff)
                gamma07 = 8'hff;
            else
                gamma07 = base + (interpolation >> 4);
        end
    endfunction

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            O_tlast  <= 1'b0;
            O_tuser  <= 1'b0;
            O_tdata  <= 96'd0;
            O_tvalid <= 1'b0;
        end else begin
            O_tlast  <= I_tlast;
            O_tuser  <= I_tuser;
            O_tvalid <= I_tvalid;
            if (I_tvalid) begin
                O_tdata <= {
                    gamma07(I_tdata[95:88]), gamma07(I_tdata[87:80]), gamma07(I_tdata[79:72]),
                    gamma07(I_tdata[71:64]), gamma07(I_tdata[63:56]), gamma07(I_tdata[55:48]),
                    gamma07(I_tdata[47:40]), gamma07(I_tdata[39:32]), gamma07(I_tdata[31:24]),
                    gamma07(I_tdata[23:16]), gamma07(I_tdata[15:8]),  gamma07(I_tdata[7:0])
                };
            end else begin
                O_tdata <= 96'd0;
            end
        end
    end

endmodule


// Centre crop for the ISP's four-pixel-wide RGB888 stream.  Frame start is
// intentionally forwarded at the original frame boundary so video_in can
// reset its asynchronous FIFO before the first selected row arrives.
module axis_crop_rgb96 #(
    parameter integer IN_WIDTH   = 1792,
    parameter integer IN_HEIGHT  = 1080,
    parameter integer OUT_WIDTH  = 1600,
    parameter integer OUT_HEIGHT = 900,
    parameter integer X_START    = 96,
    parameter integer Y_START    = 90
)(
    input  wire        I_clk,
    input  wire        I_rst_n,
    input  wire        I_tlast,
    input  wire        I_tuser,
    input  wire [95:0] I_tdata,
    input  wire        I_tvalid,
    output wire        O_tlast,
    output wire        O_tuser,
    output wire [95:0] O_tdata,
    output wire        O_tvalid
);

    localparam integer X_START_BEAT = X_START / 4;
    localparam integer OUT_BEATS    = OUT_WIDTH / 4;
    localparam integer X_END_BEAT   = X_START_BEAT + OUT_BEATS;

    reg [9:0]  S_hcnt;
    reg [10:0] S_vcnt;

    wire [9:0]  S_current_h = I_tuser ? 10'd0 : S_hcnt;
    wire [10:0] S_current_v = I_tuser ? 11'd0 : S_vcnt;
    wire S_inside = (S_current_h >= X_START_BEAT) &&
                    (S_current_h < X_END_BEAT) &&
                    (S_current_v >= Y_START) &&
                    (S_current_v < (Y_START + OUT_HEIGHT));

    assign O_tdata  = I_tdata;
    assign O_tvalid = I_tvalid && S_inside;
    assign O_tlast  = O_tvalid && (S_current_h == (X_END_BEAT - 1));
    assign O_tuser  = I_tuser;

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_hcnt <= 10'd0;
            S_vcnt <= 11'd0;
        end
        else if(I_tuser) begin
            S_hcnt <= (I_tvalid && !I_tlast) ? 10'd1 : 10'd0;
            S_vcnt <= (I_tvalid && I_tlast) ? 11'd1 : 11'd0;
        end
        else if(I_tvalid) begin
            if(I_tlast) begin
                S_hcnt <= 10'd0;
                S_vcnt <= (S_vcnt == IN_HEIGHT - 1) ? 11'd0 : S_vcnt + 1'b1;
            end
            else begin
                S_hcnt <= S_hcnt + 1'b1;
            end
        end
    end

endmodule
