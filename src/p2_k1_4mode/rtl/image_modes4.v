// RGB888 [95:72] is the first pixel; gray lanes use [7:0] first.
// One token per clock, no backpressure: matches the camera/DDR capture path.
module image_modes4 #(parameter WIDTH=1280)(
 input I_clk,input I_rst_n,input [1:0] I_mode,input [1:0] I_k,
 input I_tlast,input I_tuser,input [95:0] I_tdata,input I_tvalid,
 output I_tready, input O_tready,
 output reg O_tlast,output reg O_tuser,output reg [95:0] O_tdata,output reg O_tvalid
);
 assign I_tready=1'b1;
 reg [31:0] gray;
 reg [95:0] raw;
 reg gv,gs,gl;
 function [7:0] luma;
  input [23:0] rgb;
  reg [15:0] sum;
  begin
   sum=rgb[23:16]*16'd77+rgb[15:8]*16'd150+rgb[7:0]*16'd29+16'd128;
   luma=sum[15:8];
  end
 endfunction
 // 对比度拉伸：gamma 0.35（y=255*(x/255)^0.35），暗区陡峭增益。
 // 针对暗场景灰度 1~6 的痛点：把 1~6 拉伸到 ~37~69，让车牌/物体边缘与纹理可见。
 // 32 段分段线性（每段 8 灰度，v[7:3] 选段 / v[2:0] 段内偏移），无乘法器。
 function [7:0] stretch;
  input [7:0] v;
  reg [7:0] base;
  reg [8:0] delta;
  reg [13:0] interp;
  begin
   case(v[7:3])
    5'd0:  begin base=8'd0;   delta=9'd76;  end //  0~7   -> 0~76
    5'd1:  begin base=8'd76;  delta=9'd21;  end //  8~15  -> 76~97
    5'd2:  begin base=8'd97;  delta=9'd15;  end // 16~23  -> 97~112
    5'd3:  begin base=8'd112; delta=9'd11;  end // 24~31  -> 112~123
    5'd4:  begin base=8'd123; delta=9'd10;  end // 32~39  -> 123~133
    5'd5:  begin base=8'd133; delta=9'd9;   end // 40~47  -> 133~142
    5'd6:  begin base=8'd142; delta=9'd8;   end // 48~55  -> 142~150
    5'd7:  begin base=8'd150; delta=9'd7;   end // 56~63  -> 150~157
    5'd8:  begin base=8'd157; delta=9'd7;   end // 64~71  -> 157~164
    5'd9:  begin base=8'd164; delta=9'd6;   end // 72~79  -> 164~170
    5'd10: begin base=8'd170; delta=9'd6;   end // 80~87  -> 170~176
    5'd11: begin base=8'd176; delta=9'd5;   end // 88~95  -> 176~181
    5'd12: begin base=8'd181; delta=9'd5;   end // 96~103 -> 181~186
    5'd13: begin base=8'd186; delta=9'd5;   end // 104~111-> 186~191
    5'd14: begin base=8'd191; delta=9'd5;   end // 112~119-> 191~196
    5'd15: begin base=8'd196; delta=9'd4;   end // 120~127-> 196~200
    5'd16: begin base=8'd200; delta=9'd4;   end // 128~135-> 200~204
    5'd17: begin base=8'd204; delta=9'd4;   end // 136~143-> 204~208
    5'd18: begin base=8'd208; delta=9'd4;   end // 144~151-> 208~212
    5'd19: begin base=8'd212; delta=9'd4;   end // 152~159-> 212~216
    5'd20: begin base=8'd216; delta=9'd4;   end // 160~167-> 216~220
    5'd21: begin base=8'd220; delta=9'd4;   end // 168~175-> 220~224
    5'd22: begin base=8'd224; delta=9'd3;   end // 176~183-> 224~227
    5'd23: begin base=8'd227; delta=9'd4;   end // 184~191-> 227~231
    5'd24: begin base=8'd231; delta=9'd3;   end // 192~199-> 231~234
    5'd25: begin base=8'd234; delta=9'd3;   end // 200~207-> 234~237
    5'd26: begin base=8'd237; delta=9'd4;   end // 208~215-> 237~241
    5'd27: begin base=8'd241; delta=9'd3;   end // 216~223-> 241~244
    5'd28: begin base=8'd244; delta=9'd3;   end // 224~231-> 244~247
    5'd29: begin base=8'd247; delta=9'd3;   end // 232~239-> 247~250
    5'd30: begin base=8'd250; delta=9'd2;   end // 240~247-> 250~252
    default:begin base=8'd252; delta=9'd3;   end // 248~255-> 252~255
   endcase
   interp = delta * v[2:0] + 4;
   stretch = (v==8'hff) ? 8'hff : base + (interp>>3);
  end
 endfunction
 integer i;
 // 两级流水拆开 luma 与 stretch，消除 awb 乘法器 -> stretch 乘法器的长组合路径。
 // 第1拍：luma 加权和 -> luma_r；第2拍：stretch 查表 -> gray。
 // raw/valid/sof/eol 与 gray 同拍输出（都在第2拍更新），保持对齐。
 reg [31:0] luma_r;
 reg [95:0] raw_r;
 reg gv_r,gs_r,gl_r;
 always @(posedge I_clk or negedge I_rst_n) begin
  if(!I_rst_n) begin gray<=0;raw<=0;gv<=0;gs<=0;gl<=0;luma_r<=0;raw_r<=0;gv_r<=0;gs_r<=0;gl_r<=0;end
  else begin
   // 第1拍：luma 加权 + 寄存原图/同步信号
   for(i=0;i<4;i=i+1) luma_r[i*8+:8]<=luma(I_tdata[95-i*24-:24]);
   raw_r<=I_tdata; gv_r<=I_tvalid; gs_r<=I_tuser&&I_tvalid; gl_r<=I_tlast&&I_tvalid;
   // 第2拍：stretch 查表 + 输出对齐
   for(i=0;i<4;i=i+1) gray[i*8+:8]<=stretch(luma_r[i*8+:8]);
   raw<=raw_r; gv<=gv_r; gs<=gs_r; gl<=gl_r;
  end
 end
 wire wv,ws,wl;
 wire [287:0] windows;
 wire [3:0] good;
 wire [127:0] side;
 window4 #(.WIDTH(WIDTH),.SIDE(128)) median_window(
  .clk(I_clk),.rst_n(I_rst_n),.valid(gv),.sof(gs),.eol(gl),
  .gray(gray),.side({raw,gray}),.ov(wv),.os(ws),.ol(wl),
  .win(windows),.good(good),.aside(side));
 // Nine alternating compare/exchange stages give the exact median of nine.
 reg [287:0] sorted[0:8];
 reg [127:0] meta[0:8];
 reg [3:0] bounds[0:8];
 reg [8:0] mv,ms,ml;
 integer t;
 always @(posedge I_clk or negedge I_rst_n) begin
  if(!I_rst_n) begin
   mv<=0;ms<=0;ml<=0;
   for(t=0;t<9;t=t+1) begin sorted[t]<=0;meta[t]<=0;bounds[t]<=0;end
  end else begin
   mv<={mv[7:0],wv};ms<={ms[7:0],ws};ml<={ml[7:0],wl};
   meta[0]<=side;bounds[0]<=good;
   for(t=1;t<9;t=t+1) begin meta[t]<=meta[t-1];bounds[t]<=bounds[t-1];end
   sorted[0]<=windows;
   if(windows[0+:8]>windows[8+:8]) begin
    sorted[0][0+:8]<=windows[8+:8];sorted[0][8+:8]<=windows[0+:8];
   end
   if(windows[16+:8]>windows[24+:8]) begin
    sorted[0][16+:8]<=windows[24+:8];sorted[0][24+:8]<=windows[16+:8];
   end
   if(windows[32+:8]>windows[40+:8]) begin
    sorted[0][32+:8]<=windows[40+:8];sorted[0][40+:8]<=windows[32+:8];
   end
   if(windows[48+:8]>windows[56+:8]) begin
    sorted[0][48+:8]<=windows[56+:8];sorted[0][56+:8]<=windows[48+:8];
   end
   if(windows[72+:8]>windows[80+:8]) begin
    sorted[0][72+:8]<=windows[80+:8];sorted[0][80+:8]<=windows[72+:8];
   end
   if(windows[88+:8]>windows[96+:8]) begin
    sorted[0][88+:8]<=windows[96+:8];sorted[0][96+:8]<=windows[88+:8];
   end
   if(windows[104+:8]>windows[112+:8]) begin
    sorted[0][104+:8]<=windows[112+:8];sorted[0][112+:8]<=windows[104+:8];
   end
   if(windows[120+:8]>windows[128+:8]) begin
    sorted[0][120+:8]<=windows[128+:8];sorted[0][128+:8]<=windows[120+:8];
   end
   if(windows[144+:8]>windows[152+:8]) begin
    sorted[0][144+:8]<=windows[152+:8];sorted[0][152+:8]<=windows[144+:8];
   end
   if(windows[160+:8]>windows[168+:8]) begin
    sorted[0][160+:8]<=windows[168+:8];sorted[0][168+:8]<=windows[160+:8];
   end
   if(windows[176+:8]>windows[184+:8]) begin
    sorted[0][176+:8]<=windows[184+:8];sorted[0][184+:8]<=windows[176+:8];
   end
   if(windows[192+:8]>windows[200+:8]) begin
    sorted[0][192+:8]<=windows[200+:8];sorted[0][200+:8]<=windows[192+:8];
   end
   if(windows[216+:8]>windows[224+:8]) begin
    sorted[0][216+:8]<=windows[224+:8];sorted[0][224+:8]<=windows[216+:8];
   end
   if(windows[232+:8]>windows[240+:8]) begin
    sorted[0][232+:8]<=windows[240+:8];sorted[0][240+:8]<=windows[232+:8];
   end
   if(windows[248+:8]>windows[256+:8]) begin
    sorted[0][248+:8]<=windows[256+:8];sorted[0][256+:8]<=windows[248+:8];
   end
   if(windows[264+:8]>windows[272+:8]) begin
    sorted[0][264+:8]<=windows[272+:8];sorted[0][272+:8]<=windows[264+:8];
   end
   sorted[1]<=sorted[0];
   if(sorted[0][8+:8]>sorted[0][16+:8]) begin
    sorted[1][8+:8]<=sorted[0][16+:8];sorted[1][16+:8]<=sorted[0][8+:8];
   end
   if(sorted[0][24+:8]>sorted[0][32+:8]) begin
    sorted[1][24+:8]<=sorted[0][32+:8];sorted[1][32+:8]<=sorted[0][24+:8];
   end
   if(sorted[0][40+:8]>sorted[0][48+:8]) begin
    sorted[1][40+:8]<=sorted[0][48+:8];sorted[1][48+:8]<=sorted[0][40+:8];
   end
   if(sorted[0][56+:8]>sorted[0][64+:8]) begin
    sorted[1][56+:8]<=sorted[0][64+:8];sorted[1][64+:8]<=sorted[0][56+:8];
   end
   if(sorted[0][80+:8]>sorted[0][88+:8]) begin
    sorted[1][80+:8]<=sorted[0][88+:8];sorted[1][88+:8]<=sorted[0][80+:8];
   end
   if(sorted[0][96+:8]>sorted[0][104+:8]) begin
    sorted[1][96+:8]<=sorted[0][104+:8];sorted[1][104+:8]<=sorted[0][96+:8];
   end
   if(sorted[0][112+:8]>sorted[0][120+:8]) begin
    sorted[1][112+:8]<=sorted[0][120+:8];sorted[1][120+:8]<=sorted[0][112+:8];
   end
   if(sorted[0][128+:8]>sorted[0][136+:8]) begin
    sorted[1][128+:8]<=sorted[0][136+:8];sorted[1][136+:8]<=sorted[0][128+:8];
   end
   if(sorted[0][152+:8]>sorted[0][160+:8]) begin
    sorted[1][152+:8]<=sorted[0][160+:8];sorted[1][160+:8]<=sorted[0][152+:8];
   end
   if(sorted[0][168+:8]>sorted[0][176+:8]) begin
    sorted[1][168+:8]<=sorted[0][176+:8];sorted[1][176+:8]<=sorted[0][168+:8];
   end
   if(sorted[0][184+:8]>sorted[0][192+:8]) begin
    sorted[1][184+:8]<=sorted[0][192+:8];sorted[1][192+:8]<=sorted[0][184+:8];
   end
   if(sorted[0][200+:8]>sorted[0][208+:8]) begin
    sorted[1][200+:8]<=sorted[0][208+:8];sorted[1][208+:8]<=sorted[0][200+:8];
   end
   if(sorted[0][224+:8]>sorted[0][232+:8]) begin
    sorted[1][224+:8]<=sorted[0][232+:8];sorted[1][232+:8]<=sorted[0][224+:8];
   end
   if(sorted[0][240+:8]>sorted[0][248+:8]) begin
    sorted[1][240+:8]<=sorted[0][248+:8];sorted[1][248+:8]<=sorted[0][240+:8];
   end
   if(sorted[0][256+:8]>sorted[0][264+:8]) begin
    sorted[1][256+:8]<=sorted[0][264+:8];sorted[1][264+:8]<=sorted[0][256+:8];
   end
   if(sorted[0][272+:8]>sorted[0][280+:8]) begin
    sorted[1][272+:8]<=sorted[0][280+:8];sorted[1][280+:8]<=sorted[0][272+:8];
   end
   sorted[2]<=sorted[1];
   if(sorted[1][0+:8]>sorted[1][8+:8]) begin
    sorted[2][0+:8]<=sorted[1][8+:8];sorted[2][8+:8]<=sorted[1][0+:8];
   end
   if(sorted[1][16+:8]>sorted[1][24+:8]) begin
    sorted[2][16+:8]<=sorted[1][24+:8];sorted[2][24+:8]<=sorted[1][16+:8];
   end
   if(sorted[1][32+:8]>sorted[1][40+:8]) begin
    sorted[2][32+:8]<=sorted[1][40+:8];sorted[2][40+:8]<=sorted[1][32+:8];
   end
   if(sorted[1][48+:8]>sorted[1][56+:8]) begin
    sorted[2][48+:8]<=sorted[1][56+:8];sorted[2][56+:8]<=sorted[1][48+:8];
   end
   if(sorted[1][72+:8]>sorted[1][80+:8]) begin
    sorted[2][72+:8]<=sorted[1][80+:8];sorted[2][80+:8]<=sorted[1][72+:8];
   end
   if(sorted[1][88+:8]>sorted[1][96+:8]) begin
    sorted[2][88+:8]<=sorted[1][96+:8];sorted[2][96+:8]<=sorted[1][88+:8];
   end
   if(sorted[1][104+:8]>sorted[1][112+:8]) begin
    sorted[2][104+:8]<=sorted[1][112+:8];sorted[2][112+:8]<=sorted[1][104+:8];
   end
   if(sorted[1][120+:8]>sorted[1][128+:8]) begin
    sorted[2][120+:8]<=sorted[1][128+:8];sorted[2][128+:8]<=sorted[1][120+:8];
   end
   if(sorted[1][144+:8]>sorted[1][152+:8]) begin
    sorted[2][144+:8]<=sorted[1][152+:8];sorted[2][152+:8]<=sorted[1][144+:8];
   end
   if(sorted[1][160+:8]>sorted[1][168+:8]) begin
    sorted[2][160+:8]<=sorted[1][168+:8];sorted[2][168+:8]<=sorted[1][160+:8];
   end
   if(sorted[1][176+:8]>sorted[1][184+:8]) begin
    sorted[2][176+:8]<=sorted[1][184+:8];sorted[2][184+:8]<=sorted[1][176+:8];
   end
   if(sorted[1][192+:8]>sorted[1][200+:8]) begin
    sorted[2][192+:8]<=sorted[1][200+:8];sorted[2][200+:8]<=sorted[1][192+:8];
   end
   if(sorted[1][216+:8]>sorted[1][224+:8]) begin
    sorted[2][216+:8]<=sorted[1][224+:8];sorted[2][224+:8]<=sorted[1][216+:8];
   end
   if(sorted[1][232+:8]>sorted[1][240+:8]) begin
    sorted[2][232+:8]<=sorted[1][240+:8];sorted[2][240+:8]<=sorted[1][232+:8];
   end
   if(sorted[1][248+:8]>sorted[1][256+:8]) begin
    sorted[2][248+:8]<=sorted[1][256+:8];sorted[2][256+:8]<=sorted[1][248+:8];
   end
   if(sorted[1][264+:8]>sorted[1][272+:8]) begin
    sorted[2][264+:8]<=sorted[1][272+:8];sorted[2][272+:8]<=sorted[1][264+:8];
   end
   sorted[3]<=sorted[2];
   if(sorted[2][8+:8]>sorted[2][16+:8]) begin
    sorted[3][8+:8]<=sorted[2][16+:8];sorted[3][16+:8]<=sorted[2][8+:8];
   end
   if(sorted[2][24+:8]>sorted[2][32+:8]) begin
    sorted[3][24+:8]<=sorted[2][32+:8];sorted[3][32+:8]<=sorted[2][24+:8];
   end
   if(sorted[2][40+:8]>sorted[2][48+:8]) begin
    sorted[3][40+:8]<=sorted[2][48+:8];sorted[3][48+:8]<=sorted[2][40+:8];
   end
   if(sorted[2][56+:8]>sorted[2][64+:8]) begin
    sorted[3][56+:8]<=sorted[2][64+:8];sorted[3][64+:8]<=sorted[2][56+:8];
   end
   if(sorted[2][80+:8]>sorted[2][88+:8]) begin
    sorted[3][80+:8]<=sorted[2][88+:8];sorted[3][88+:8]<=sorted[2][80+:8];
   end
   if(sorted[2][96+:8]>sorted[2][104+:8]) begin
    sorted[3][96+:8]<=sorted[2][104+:8];sorted[3][104+:8]<=sorted[2][96+:8];
   end
   if(sorted[2][112+:8]>sorted[2][120+:8]) begin
    sorted[3][112+:8]<=sorted[2][120+:8];sorted[3][120+:8]<=sorted[2][112+:8];
   end
   if(sorted[2][128+:8]>sorted[2][136+:8]) begin
    sorted[3][128+:8]<=sorted[2][136+:8];sorted[3][136+:8]<=sorted[2][128+:8];
   end
   if(sorted[2][152+:8]>sorted[2][160+:8]) begin
    sorted[3][152+:8]<=sorted[2][160+:8];sorted[3][160+:8]<=sorted[2][152+:8];
   end
   if(sorted[2][168+:8]>sorted[2][176+:8]) begin
    sorted[3][168+:8]<=sorted[2][176+:8];sorted[3][176+:8]<=sorted[2][168+:8];
   end
   if(sorted[2][184+:8]>sorted[2][192+:8]) begin
    sorted[3][184+:8]<=sorted[2][192+:8];sorted[3][192+:8]<=sorted[2][184+:8];
   end
   if(sorted[2][200+:8]>sorted[2][208+:8]) begin
    sorted[3][200+:8]<=sorted[2][208+:8];sorted[3][208+:8]<=sorted[2][200+:8];
   end
   if(sorted[2][224+:8]>sorted[2][232+:8]) begin
    sorted[3][224+:8]<=sorted[2][232+:8];sorted[3][232+:8]<=sorted[2][224+:8];
   end
   if(sorted[2][240+:8]>sorted[2][248+:8]) begin
    sorted[3][240+:8]<=sorted[2][248+:8];sorted[3][248+:8]<=sorted[2][240+:8];
   end
   if(sorted[2][256+:8]>sorted[2][264+:8]) begin
    sorted[3][256+:8]<=sorted[2][264+:8];sorted[3][264+:8]<=sorted[2][256+:8];
   end
   if(sorted[2][272+:8]>sorted[2][280+:8]) begin
    sorted[3][272+:8]<=sorted[2][280+:8];sorted[3][280+:8]<=sorted[2][272+:8];
   end
   sorted[4]<=sorted[3];
   if(sorted[3][0+:8]>sorted[3][8+:8]) begin
    sorted[4][0+:8]<=sorted[3][8+:8];sorted[4][8+:8]<=sorted[3][0+:8];
   end
   if(sorted[3][16+:8]>sorted[3][24+:8]) begin
    sorted[4][16+:8]<=sorted[3][24+:8];sorted[4][24+:8]<=sorted[3][16+:8];
   end
   if(sorted[3][32+:8]>sorted[3][40+:8]) begin
    sorted[4][32+:8]<=sorted[3][40+:8];sorted[4][40+:8]<=sorted[3][32+:8];
   end
   if(sorted[3][48+:8]>sorted[3][56+:8]) begin
    sorted[4][48+:8]<=sorted[3][56+:8];sorted[4][56+:8]<=sorted[3][48+:8];
   end
   if(sorted[3][72+:8]>sorted[3][80+:8]) begin
    sorted[4][72+:8]<=sorted[3][80+:8];sorted[4][80+:8]<=sorted[3][72+:8];
   end
   if(sorted[3][88+:8]>sorted[3][96+:8]) begin
    sorted[4][88+:8]<=sorted[3][96+:8];sorted[4][96+:8]<=sorted[3][88+:8];
   end
   if(sorted[3][104+:8]>sorted[3][112+:8]) begin
    sorted[4][104+:8]<=sorted[3][112+:8];sorted[4][112+:8]<=sorted[3][104+:8];
   end
   if(sorted[3][120+:8]>sorted[3][128+:8]) begin
    sorted[4][120+:8]<=sorted[3][128+:8];sorted[4][128+:8]<=sorted[3][120+:8];
   end
   if(sorted[3][144+:8]>sorted[3][152+:8]) begin
    sorted[4][144+:8]<=sorted[3][152+:8];sorted[4][152+:8]<=sorted[3][144+:8];
   end
   if(sorted[3][160+:8]>sorted[3][168+:8]) begin
    sorted[4][160+:8]<=sorted[3][168+:8];sorted[4][168+:8]<=sorted[3][160+:8];
   end
   if(sorted[3][176+:8]>sorted[3][184+:8]) begin
    sorted[4][176+:8]<=sorted[3][184+:8];sorted[4][184+:8]<=sorted[3][176+:8];
   end
   if(sorted[3][192+:8]>sorted[3][200+:8]) begin
    sorted[4][192+:8]<=sorted[3][200+:8];sorted[4][200+:8]<=sorted[3][192+:8];
   end
   if(sorted[3][216+:8]>sorted[3][224+:8]) begin
    sorted[4][216+:8]<=sorted[3][224+:8];sorted[4][224+:8]<=sorted[3][216+:8];
   end
   if(sorted[3][232+:8]>sorted[3][240+:8]) begin
    sorted[4][232+:8]<=sorted[3][240+:8];sorted[4][240+:8]<=sorted[3][232+:8];
   end
   if(sorted[3][248+:8]>sorted[3][256+:8]) begin
    sorted[4][248+:8]<=sorted[3][256+:8];sorted[4][256+:8]<=sorted[3][248+:8];
   end
   if(sorted[3][264+:8]>sorted[3][272+:8]) begin
    sorted[4][264+:8]<=sorted[3][272+:8];sorted[4][272+:8]<=sorted[3][264+:8];
   end
   sorted[5]<=sorted[4];
   if(sorted[4][8+:8]>sorted[4][16+:8]) begin
    sorted[5][8+:8]<=sorted[4][16+:8];sorted[5][16+:8]<=sorted[4][8+:8];
   end
   if(sorted[4][24+:8]>sorted[4][32+:8]) begin
    sorted[5][24+:8]<=sorted[4][32+:8];sorted[5][32+:8]<=sorted[4][24+:8];
   end
   if(sorted[4][40+:8]>sorted[4][48+:8]) begin
    sorted[5][40+:8]<=sorted[4][48+:8];sorted[5][48+:8]<=sorted[4][40+:8];
   end
   if(sorted[4][56+:8]>sorted[4][64+:8]) begin
    sorted[5][56+:8]<=sorted[4][64+:8];sorted[5][64+:8]<=sorted[4][56+:8];
   end
   if(sorted[4][80+:8]>sorted[4][88+:8]) begin
    sorted[5][80+:8]<=sorted[4][88+:8];sorted[5][88+:8]<=sorted[4][80+:8];
   end
   if(sorted[4][96+:8]>sorted[4][104+:8]) begin
    sorted[5][96+:8]<=sorted[4][104+:8];sorted[5][104+:8]<=sorted[4][96+:8];
   end
   if(sorted[4][112+:8]>sorted[4][120+:8]) begin
    sorted[5][112+:8]<=sorted[4][120+:8];sorted[5][120+:8]<=sorted[4][112+:8];
   end
   if(sorted[4][128+:8]>sorted[4][136+:8]) begin
    sorted[5][128+:8]<=sorted[4][136+:8];sorted[5][136+:8]<=sorted[4][128+:8];
   end
   if(sorted[4][152+:8]>sorted[4][160+:8]) begin
    sorted[5][152+:8]<=sorted[4][160+:8];sorted[5][160+:8]<=sorted[4][152+:8];
   end
   if(sorted[4][168+:8]>sorted[4][176+:8]) begin
    sorted[5][168+:8]<=sorted[4][176+:8];sorted[5][176+:8]<=sorted[4][168+:8];
   end
   if(sorted[4][184+:8]>sorted[4][192+:8]) begin
    sorted[5][184+:8]<=sorted[4][192+:8];sorted[5][192+:8]<=sorted[4][184+:8];
   end
   if(sorted[4][200+:8]>sorted[4][208+:8]) begin
    sorted[5][200+:8]<=sorted[4][208+:8];sorted[5][208+:8]<=sorted[4][200+:8];
   end
   if(sorted[4][224+:8]>sorted[4][232+:8]) begin
    sorted[5][224+:8]<=sorted[4][232+:8];sorted[5][232+:8]<=sorted[4][224+:8];
   end
   if(sorted[4][240+:8]>sorted[4][248+:8]) begin
    sorted[5][240+:8]<=sorted[4][248+:8];sorted[5][248+:8]<=sorted[4][240+:8];
   end
   if(sorted[4][256+:8]>sorted[4][264+:8]) begin
    sorted[5][256+:8]<=sorted[4][264+:8];sorted[5][264+:8]<=sorted[4][256+:8];
   end
   if(sorted[4][272+:8]>sorted[4][280+:8]) begin
    sorted[5][272+:8]<=sorted[4][280+:8];sorted[5][280+:8]<=sorted[4][272+:8];
   end
   sorted[6]<=sorted[5];
   if(sorted[5][0+:8]>sorted[5][8+:8]) begin
    sorted[6][0+:8]<=sorted[5][8+:8];sorted[6][8+:8]<=sorted[5][0+:8];
   end
   if(sorted[5][16+:8]>sorted[5][24+:8]) begin
    sorted[6][16+:8]<=sorted[5][24+:8];sorted[6][24+:8]<=sorted[5][16+:8];
   end
   if(sorted[5][32+:8]>sorted[5][40+:8]) begin
    sorted[6][32+:8]<=sorted[5][40+:8];sorted[6][40+:8]<=sorted[5][32+:8];
   end
   if(sorted[5][48+:8]>sorted[5][56+:8]) begin
    sorted[6][48+:8]<=sorted[5][56+:8];sorted[6][56+:8]<=sorted[5][48+:8];
   end
   if(sorted[5][72+:8]>sorted[5][80+:8]) begin
    sorted[6][72+:8]<=sorted[5][80+:8];sorted[6][80+:8]<=sorted[5][72+:8];
   end
   if(sorted[5][88+:8]>sorted[5][96+:8]) begin
    sorted[6][88+:8]<=sorted[5][96+:8];sorted[6][96+:8]<=sorted[5][88+:8];
   end
   if(sorted[5][104+:8]>sorted[5][112+:8]) begin
    sorted[6][104+:8]<=sorted[5][112+:8];sorted[6][112+:8]<=sorted[5][104+:8];
   end
   if(sorted[5][120+:8]>sorted[5][128+:8]) begin
    sorted[6][120+:8]<=sorted[5][128+:8];sorted[6][128+:8]<=sorted[5][120+:8];
   end
   if(sorted[5][144+:8]>sorted[5][152+:8]) begin
    sorted[6][144+:8]<=sorted[5][152+:8];sorted[6][152+:8]<=sorted[5][144+:8];
   end
   if(sorted[5][160+:8]>sorted[5][168+:8]) begin
    sorted[6][160+:8]<=sorted[5][168+:8];sorted[6][168+:8]<=sorted[5][160+:8];
   end
   if(sorted[5][176+:8]>sorted[5][184+:8]) begin
    sorted[6][176+:8]<=sorted[5][184+:8];sorted[6][184+:8]<=sorted[5][176+:8];
   end
   if(sorted[5][192+:8]>sorted[5][200+:8]) begin
    sorted[6][192+:8]<=sorted[5][200+:8];sorted[6][200+:8]<=sorted[5][192+:8];
   end
   if(sorted[5][216+:8]>sorted[5][224+:8]) begin
    sorted[6][216+:8]<=sorted[5][224+:8];sorted[6][224+:8]<=sorted[5][216+:8];
   end
   if(sorted[5][232+:8]>sorted[5][240+:8]) begin
    sorted[6][232+:8]<=sorted[5][240+:8];sorted[6][240+:8]<=sorted[5][232+:8];
   end
   if(sorted[5][248+:8]>sorted[5][256+:8]) begin
    sorted[6][248+:8]<=sorted[5][256+:8];sorted[6][256+:8]<=sorted[5][248+:8];
   end
   if(sorted[5][264+:8]>sorted[5][272+:8]) begin
    sorted[6][264+:8]<=sorted[5][272+:8];sorted[6][272+:8]<=sorted[5][264+:8];
   end
   sorted[7]<=sorted[6];
   if(sorted[6][8+:8]>sorted[6][16+:8]) begin
    sorted[7][8+:8]<=sorted[6][16+:8];sorted[7][16+:8]<=sorted[6][8+:8];
   end
   if(sorted[6][24+:8]>sorted[6][32+:8]) begin
    sorted[7][24+:8]<=sorted[6][32+:8];sorted[7][32+:8]<=sorted[6][24+:8];
   end
   if(sorted[6][40+:8]>sorted[6][48+:8]) begin
    sorted[7][40+:8]<=sorted[6][48+:8];sorted[7][48+:8]<=sorted[6][40+:8];
   end
   if(sorted[6][56+:8]>sorted[6][64+:8]) begin
    sorted[7][56+:8]<=sorted[6][64+:8];sorted[7][64+:8]<=sorted[6][56+:8];
   end
   if(sorted[6][80+:8]>sorted[6][88+:8]) begin
    sorted[7][80+:8]<=sorted[6][88+:8];sorted[7][88+:8]<=sorted[6][80+:8];
   end
   if(sorted[6][96+:8]>sorted[6][104+:8]) begin
    sorted[7][96+:8]<=sorted[6][104+:8];sorted[7][104+:8]<=sorted[6][96+:8];
   end
   if(sorted[6][112+:8]>sorted[6][120+:8]) begin
    sorted[7][112+:8]<=sorted[6][120+:8];sorted[7][120+:8]<=sorted[6][112+:8];
   end
   if(sorted[6][128+:8]>sorted[6][136+:8]) begin
    sorted[7][128+:8]<=sorted[6][136+:8];sorted[7][136+:8]<=sorted[6][128+:8];
   end
   if(sorted[6][152+:8]>sorted[6][160+:8]) begin
    sorted[7][152+:8]<=sorted[6][160+:8];sorted[7][160+:8]<=sorted[6][152+:8];
   end
   if(sorted[6][168+:8]>sorted[6][176+:8]) begin
    sorted[7][168+:8]<=sorted[6][176+:8];sorted[7][176+:8]<=sorted[6][168+:8];
   end
   if(sorted[6][184+:8]>sorted[6][192+:8]) begin
    sorted[7][184+:8]<=sorted[6][192+:8];sorted[7][192+:8]<=sorted[6][184+:8];
   end
   if(sorted[6][200+:8]>sorted[6][208+:8]) begin
    sorted[7][200+:8]<=sorted[6][208+:8];sorted[7][208+:8]<=sorted[6][200+:8];
   end
   if(sorted[6][224+:8]>sorted[6][232+:8]) begin
    sorted[7][224+:8]<=sorted[6][232+:8];sorted[7][232+:8]<=sorted[6][224+:8];
   end
   if(sorted[6][240+:8]>sorted[6][248+:8]) begin
    sorted[7][240+:8]<=sorted[6][248+:8];sorted[7][248+:8]<=sorted[6][240+:8];
   end
   if(sorted[6][256+:8]>sorted[6][264+:8]) begin
    sorted[7][256+:8]<=sorted[6][264+:8];sorted[7][264+:8]<=sorted[6][256+:8];
   end
   if(sorted[6][272+:8]>sorted[6][280+:8]) begin
    sorted[7][272+:8]<=sorted[6][280+:8];sorted[7][280+:8]<=sorted[6][272+:8];
   end
   sorted[8]<=sorted[7];
   if(sorted[7][0+:8]>sorted[7][8+:8]) begin
    sorted[8][0+:8]<=sorted[7][8+:8];sorted[8][8+:8]<=sorted[7][0+:8];
   end
   if(sorted[7][16+:8]>sorted[7][24+:8]) begin
    sorted[8][16+:8]<=sorted[7][24+:8];sorted[8][24+:8]<=sorted[7][16+:8];
   end
   if(sorted[7][32+:8]>sorted[7][40+:8]) begin
    sorted[8][32+:8]<=sorted[7][40+:8];sorted[8][40+:8]<=sorted[7][32+:8];
   end
   if(sorted[7][48+:8]>sorted[7][56+:8]) begin
    sorted[8][48+:8]<=sorted[7][56+:8];sorted[8][56+:8]<=sorted[7][48+:8];
   end
   if(sorted[7][72+:8]>sorted[7][80+:8]) begin
    sorted[8][72+:8]<=sorted[7][80+:8];sorted[8][80+:8]<=sorted[7][72+:8];
   end
   if(sorted[7][88+:8]>sorted[7][96+:8]) begin
    sorted[8][88+:8]<=sorted[7][96+:8];sorted[8][96+:8]<=sorted[7][88+:8];
   end
   if(sorted[7][104+:8]>sorted[7][112+:8]) begin
    sorted[8][104+:8]<=sorted[7][112+:8];sorted[8][112+:8]<=sorted[7][104+:8];
   end
   if(sorted[7][120+:8]>sorted[7][128+:8]) begin
    sorted[8][120+:8]<=sorted[7][128+:8];sorted[8][128+:8]<=sorted[7][120+:8];
   end
   if(sorted[7][144+:8]>sorted[7][152+:8]) begin
    sorted[8][144+:8]<=sorted[7][152+:8];sorted[8][152+:8]<=sorted[7][144+:8];
   end
   if(sorted[7][160+:8]>sorted[7][168+:8]) begin
    sorted[8][160+:8]<=sorted[7][168+:8];sorted[8][168+:8]<=sorted[7][160+:8];
   end
   if(sorted[7][176+:8]>sorted[7][184+:8]) begin
    sorted[8][176+:8]<=sorted[7][184+:8];sorted[8][184+:8]<=sorted[7][176+:8];
   end
   if(sorted[7][192+:8]>sorted[7][200+:8]) begin
    sorted[8][192+:8]<=sorted[7][200+:8];sorted[8][200+:8]<=sorted[7][192+:8];
   end
   if(sorted[7][216+:8]>sorted[7][224+:8]) begin
    sorted[8][216+:8]<=sorted[7][224+:8];sorted[8][224+:8]<=sorted[7][216+:8];
   end
   if(sorted[7][232+:8]>sorted[7][240+:8]) begin
    sorted[8][232+:8]<=sorted[7][240+:8];sorted[8][240+:8]<=sorted[7][232+:8];
   end
   if(sorted[7][248+:8]>sorted[7][256+:8]) begin
    sorted[8][248+:8]<=sorted[7][256+:8];sorted[8][256+:8]<=sorted[7][248+:8];
   end
   if(sorted[7][264+:8]>sorted[7][272+:8]) begin
    sorted[8][264+:8]<=sorted[7][272+:8];sorted[8][272+:8]<=sorted[7][264+:8];
   end
  end
 end
 wire [31:0] median;
 genvar p;
 generate for(p=0;p<4;p=p+1) begin: med_lane
  assign median[p*8+:8]=bounds[8][p]?sorted[8][p*72+32+:8]:meta[8][p*8+:8];
 end endgenerate
 wire ev,es,el;
 wire [287:0] ew;
 wire [3:0] egood;
 wire [159:0] emeta;
 window4 #(.WIDTH(WIDTH),.SIDE(160)) edge_window(
  .clk(I_clk),.rst_n(I_rst_n),.valid(mv[8]),.sof(ms[8]),.eol(ml[8]),
  .gray(median),.side({meta[8],median}),.ov(ev),.os(es),.ol(el),
    .win(ew),.good(egood),.aside(emeta));

function [11:0] magnitude;
  input [71:0] w;
  reg [10:0] a,b,c,d;
  begin
   a={3'd0,w[16+:8]}+{2'd0,w[40+:8],1'b0}+{3'd0,w[64+:8]};
   b={3'd0,w[0+:8]}+{2'd0,w[24+:8],1'b0}+{3'd0,w[48+:8]};
   c={3'd0,w[48+:8]}+{2'd0,w[56+:8],1'b0}+{3'd0,w[64+:8]};
   d={3'd0,w[0+:8]}+{2'd0,w[8+:8],1'b0}+{3'd0,w[16+:8]};
   magnitude=((a>b)?a-b:b-a)+((c>d)?c-d:d-c);
  end
 endfunction
 reg [11:0] mag[0:3];
 reg [159:0] final_side;
 reg fv,fs,fl;
 reg [3:0] fg;
 reg [1:0] active_mode;
 wire [1:0] select_mode=(fv&&fs)?I_mode:active_mode;
 always @(posedge I_clk or negedge I_rst_n) begin
  if(!I_rst_n) begin
   fv<=0;fs<=0;fl<=0;fg<=0;final_side<=0;active_mode<=0;
   for(i=0;i<4;i=i+1) mag[i]<=0;
  end else begin
   fv<=ev;fs<=es;fl<=el;fg<=egood;final_side<=emeta;
   for(i=0;i<4;i=i+1) mag[i]<=magnitude(ew[i*72+:72]);
   if(fv&&fs) active_mode<=I_mode;
  end
 end

 // 边缘位（组合）：固定阈值（Sobel 梯度是"绝对灰度差"，与绝对灰度无关，不应与中心灰度比较）
 // gamma 拉伸后梯度分布：物体边缘 24~47，人脸/弱边 10~20，噪声被中值压掉后残留 <10。
 // I_k 选档：0=12(敏感) 1=16 2=20 3=24(稳健)。默认 I_k=2 -> 阈值 20。
 wire [7:0] edge_thr = (I_k==2'd0)? 8'd12 : (I_k==2'd1)? 8'd16 : (I_k==2'd2)? 8'd20 : 8'd24;
 wire [3:0] edge_c = { fg[3]&&(mag[3] >= {4'b0, edge_thr}),
                       fg[2]&&(mag[2] >= {4'b0, edge_thr}),
                       fg[1]&&(mag[1] >= {4'b0, edge_thr}),
                       fg[0]&&(mag[0] >= {4'b0, edge_thr}) };

 // 3x3 软腐蚀：去孤立噪点（中值滤波已去大部分椒盐，这里再收尾）
 wire [31:0] ero_gray = {7'b0,edge_c[3], 7'b0,edge_c[2], 7'b0,edge_c[1], 7'b0,edge_c[0]};
 wire        emv,ems,eml;
 wire [287:0] ew_ero;
 wire [3:0]  egood_ero;
 wire [31:0] easide_ero;
 window4 #(.WIDTH(WIDTH),.SIDE(32)) erode_window(
  .clk(I_clk),.rst_n(I_rst_n),.valid(fv),.sof(fs),.eol(fl),
  .gray(ero_gray),.side(32'b0),.ov(emv),.os(ems),.ol(eml),
  .win(ew_ero),.good(egood_ero),.aside(easide_ero));
 reg  [3:0] ero_out;
 reg        ero_v,ero_s,ero_l;
 integer ee;
 always @(posedge I_clk or negedge I_rst_n) begin
  if(!I_rst_n) begin ero_out<=0;ero_v<=0;ero_s<=0;ero_l<=0; end
  else begin
   ero_v<=emv;ero_s<=ems&&emv;ero_l<=eml&&emv;
   for(ee=0;ee<4;ee=ee+1) begin
    // 软腐蚀：3x3 邻域内边缘计数 >=4 才保留（去孤立点，不伤 1px 细边缘）
    if(!egood_ero[ee]) ero_out[ee]<=1'b0;
    else ero_out[ee] <= ( ew_ero[ee*72+32] + ew_ero[ee*72+0] + ew_ero[ee*72+8]
                        + ew_ero[ee*72+16] + ew_ero[ee*72+24] + ew_ero[ee*72+40]
                        + ew_ero[ee*72+48] + ew_ero[ee*72+56] + ew_ero[ee*72+64] ) >= 4;
   end
  end
 end

 // final_side(原图/灰度)与 ero_out 差 2 拍，打 2 拍对齐
 reg [159:0] final_side_d1, final_side_d2;
 reg [47:0] mag_d1, mag_d2;   // mag[0:3] 12bit 打 2 拍对齐输出
 always @(posedge I_clk or negedge I_rst_n) begin
  if(!I_rst_n) begin final_side_d1<=0; final_side_d2<=0; mag_d1<=0; mag_d2<=0; end
  else begin
   final_side_d1<=final_side; final_side_d2<=final_side_d1;
   mag_d1<={mag[3],mag[2],mag[1],mag[0]};
   mag_d2<=mag_d1;
  end
 end

 // 边缘强度灰度图：mag 12bit 缩放 8bit，边缘亮/平区暗（绕开二值化阈值）
 // mag 范围 0~2040(255*8)，>>4 -> 0~127；此处 >>3 -> 0~255，>2040 饱和 255
 function [7:0] mag2gray;
  input [11:0] m;
  begin
   mag2gray = (m > 12'd2040) ? 8'hff : m[11:3];
  end
 endfunction

 // 输出（统一用 ero_* 同步）
 always @(posedge I_clk or negedge I_rst_n) begin
  if(!I_rst_n) begin
   O_tvalid<=0;O_tuser<=0;O_tlast<=0;O_tdata<=0;
  end else begin
   O_tvalid<=ero_v;O_tuser<=ero_s&&ero_v;O_tlast<=ero_l&&ero_v;
   for(i=0;i<4;i=i+1) begin
    case(select_mode)
     0:O_tdata[95-i*24-:24]<=final_side_d2[159-i*24-:24];
     1:O_tdata[95-i*24-:24]<={3{final_side_d2[32+i*8+:8]}};
     2:O_tdata[95-i*24-:24]<={3{mag2gray(mag_d2[i*12+:12])}};    // 边缘强度灰度图
     3:O_tdata[95-i*24-:24]<=ero_out[i]?24'h000000:24'hffffff;   // 边缘(二值黑边白底)
    endcase
   end
  end
 end
endmodule
