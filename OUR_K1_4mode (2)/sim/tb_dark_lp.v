`timescale 1ns/1ps
// 真实暗场景：车牌字符(灰度6) vs 背景(灰度1)，加椒盐噪声
// 验证 gamma 拉伸后，字符边缘能被检出、噪点被压掉
module tb_dark_lp;
  localparam WIDTH = 64;
  localparam BEATS = WIDTH/4;
  reg clk=0, rst_n=0;
  reg [1:0] I_mode=2'd3;
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
  // 背景灰度1，车牌字符(竖条)灰度6，加椒盐(单像素跳变)
  function [7:0] pix; input integer X,Y;
    reg [7:0] base;
    begin
      base = 8'd1;   // 背景
      if (X>=28 && X<=36) base = 8'd6;  // 车牌字符竖条
      if ((X*3+Y*5)%11==0) base = 8'd6; // 椒盐(单像素跳变)
      pix = base;
    end
  endfunction
  initial begin
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
  integer coy=0,coxg=0,ox,cl2;
  reg wht;
  integer i_edge,i_bg;
  reg [31:0] edge_black, bg_black, edge_tot, bg_tot;
  always @* begin
    i_edge=0;i_bg=0;
    for(cl2=0;cl2<4;cl2=cl2+1) begin
      ox=coxg*4+cl2;
      wht=(O_tdata[95-cl2*24-:24]==24'hffffff);
      if(ox>=26 && ox<=38) begin if(!wht) i_edge=i_edge+1; else ; end
      else begin if(!wht) i_bg=i_bg+1; end
    end
  end
  always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin coy<=0;coxg<=0;edge_black<=0;bg_black<=0;edge_tot<=0;bg_tot<=0;end
    else if(O_tvalid) begin
      if(coy>=6) begin
        edge_black<=edge_black+i_edge; bg_black<=bg_black+i_bg;
        if(coxg*4>=26 && coxg*4<=38) edge_tot<=edge_tot+4; else bg_tot<=bg_tot+4;
      end
      if(O_tuser) begin coy<=0;coxg<=0;end
      else if(O_tlast) begin coxg<=0;coy<=coy+1;end
      else coxg<=coxg+1;
    end
  end
  integer errors;
  initial begin errors=0; #9000;
    $display("暗场景车牌: 字符区黑=%0d/%0d  背景区黑=%0d/%0d", edge_black,edge_tot,bg_black,bg_tot);
    if(edge_black <= 3) begin $display("FAIL: 车牌字符边缘未检出"); errors=errors+1; end
    if(bg_black > bg_tot/2) begin $display("FAIL: 背景噪点过多"); errors=errors+1; end
    if(errors==0) $display("PASS: 车牌字符检出, 背景噪点被压");
    else $display("FAIL_TOTAL errors=%0d", errors);
    $finish;
  end
endmodule
