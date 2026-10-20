`timescale 1ns/1ps
module tb_mode2;
  localparam WIDTH = 64;
  localparam BEATS = WIDTH/4;
  reg clk=0, rst_n=0;
  reg [1:0] I_mode=2'd2;
  reg [1:0] I_k=2'd2;
  reg I_tlast=0, I_tuser=0, I_tvalid=0;
  reg [95:0] I_tdata=0;
  wire I_tready; reg O_tready=1'b1;
  wire O_tlast,O_tuser,O_tvalid; wire [95:0] O_tdata;
  image_modes4 #(.WIDTH(WIDTH)) uut(
    .I_clk(clk),.I_rst_n(rst_n),.I_mode(I_mode),.I_k(I_k),
    .I_tlast(I_tlast),.I_tuser(I_tuser),.I_tdata(I_tdata),.I_tvalid(I_tvalid),
    .I_tready(I_tready),.O_tready(O_tready),
    .O_tlast(O_tlast),.O_tuser(O_tuser),.O_tvalid(O_tvalid),.O_tdata(O_tdata));
  always #5 clk=~clk;
  integer xg,y,cl;
  function [7:0] pix; input integer X,Y;
    begin pix = (X<32)?8'd20:8'd45; end
  endfunction
  integer maxv, minv, cnt;
  initial begin
    maxv=0; minv=255; cnt=0;
    #20 rst_n=1;
    for(y=0;y<32;y=y+1) for(xg=0;xg<BEATS;xg=xg+1) begin
      I_tdata={pix(xg*4+0,y),pix(xg*4+0,y),pix(xg*4+0,y),
               pix(xg*4+1,y),pix(xg*4+1,y),pix(xg*4+1,y),
               pix(xg*4+2,y),pix(xg*4+2,y),pix(xg*4+2,y),
               pix(xg*4+3,y),pix(xg*4+3,y),pix(xg*4+3,y)};
      I_tuser=(y==0&&xg==0); I_tlast=(xg==BEATS-1); I_tvalid=1;
      @(posedge clk);
    end
    I_tvalid=0;I_tuser=0;I_tlast=0;
  end
  always @(posedge clk) begin
    if(O_tvalid) for(cl=0;cl<4;cl=cl+1) begin
      if(O_tdata[95-cl*24-:24] > maxv) maxv=O_tdata[95-cl*24-:24];
      if(O_tdata[95-cl*24-:24] < minv) minv=O_tdata[95-cl*24-:24];
      cnt=cnt+1;
    end
  end
  initial begin #9000;
    $display("MODE2 边缘强度灰度图: max=%0d min=%0d cnt=%0d (应 max>0 边缘亮, min>=0 平区暗)", maxv,minv,cnt);
    if(maxv>0 && minv<maxv) $display("PASS: mode2 outputs grayscale gradient map");
    else $display("FAIL: mode2 output not as expected");
    $finish;
  end
endmodule
