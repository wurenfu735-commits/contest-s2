// RGB888 [95:72] is the first pixel; gray lanes use [7:0] first.
// One token per clock, no backpressure: matches the camera/DDR capture path.
module image_modes4 #(parameter WIDTH=1280)(
 input I_clk,input I_rst_n,input [1:0] I_mode,
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
 integer i;
 always @(posedge I_clk or negedge I_rst_n) begin
  if(!I_rst_n) begin gray<=0;raw<=0;gv<=0;gs<=0;gl<=0;end
  else begin
   gv<=I_tvalid;gs<=I_tuser&&I_tvalid;gl<=I_tlast&&I_tvalid;raw<=I_tdata;
   for(i=0;i<4;i=i+1) gray[i*8+:8]<=luma(I_tdata[95-i*24-:24]);
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
 reg [7:0] threshold[0:3];
 reg [159:0] final_side;
 reg fv,fs,fl;
 reg [3:0] fg;
 reg [1:0] active_mode;
 wire [1:0] select_mode=(fv&&fs)?I_mode:active_mode;
 reg [7:0] out_gray;
 always @(posedge I_clk or negedge I_rst_n) begin
  if(!I_rst_n) begin
   fv<=0;fs<=0;fl<=0;fg<=0;final_side<=0;active_mode<=0;
   O_tvalid<=0;O_tuser<=0;O_tlast<=0;O_tdata<=0;
   for(i=0;i<4;i=i+1) begin mag[i]<=0;threshold[i]<=0;end
  end else begin
   fv<=ev;fs<=es;fl<=el;fg<=egood;final_side<=emeta;
   for(i=0;i<4;i=i+1) begin
    mag[i]<=magnitude(ew[i*72+:72]);
    // V3: measured mag noise sigma = 2.0..3.6, so thr ~= 8.5*sigma (17..31).
    // thr = 14 + (center>>3).  Old 112/88/64 meant 28/22/16 gray levels = 3..4x
    // too strict, and got LOOSER in bright areas although noise GROWS there.
    threshold[i]<=ew[i*72+39 -: 5] + 8'd14;
   end
   O_tvalid<=fv;O_tuser<=fs&&fv;O_tlast<=fl&&fv;
   if(fv&&fs) active_mode<=I_mode;
   for(i=0;i<4;i=i+1) begin
    case(select_mode)
     0:O_tdata[95-i*24-:24]<=final_side[159-i*24-:24];
     1:O_tdata[95-i*24-:24]<={3{final_side[32+i*8+:8]}};
     2:O_tdata[95-i*24-:24]<={3{final_side[i*8+:8]}};
     3:O_tdata[95-i*24-:24]<=(fg[i]&&mag[i]>=threshold[i])?24'hffffff:24'h000000;
    endcase
   end
  end
 end
endmodule
