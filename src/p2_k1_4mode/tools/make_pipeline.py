from pathlib import Path
root=Path(__file__).resolve().parents[1]
v='''// RGB888 [95:72] is the first pixel; gray lanes use [7:0] first.
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
'''
for s in range(9):
    src='windows' if s==0 else f'sorted[{s-1}]'
    v+=f'   sorted[{s}]<={src};\n'
    for p in range(4):
        for k in range(s%2,8,2):
            a=p*72+k*8;b=a+8
            v+=f'''   if({src}[{a}+:8]>{src}[{b}+:8]) begin
    sorted[{s}][{a}+:8]<={src}[{b}+:8];sorted[{s}][{b}+:8]<={src}[{a}+:8];
   end
'''
v+='''  end
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
    // Stronger rejection in dark areas; all thresholds in full-range luma.
    threshold[i]<=(ew[i*72+32+:8]<64)?8'd112:
                   (ew[i*72+32+:8]<128)?8'd88:8'd64;
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
'''
(root/'rtl/image_modes4.v').write_text(v,encoding='utf-8')
