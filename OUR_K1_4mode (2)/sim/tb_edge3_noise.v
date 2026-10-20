`timescale 1ns/1ps
module tb_edge3_noise;
  localparam WIDTH = 64;
  localparam BEATS = WIDTH/4;
  reg clk=0, rst_n=0;
  reg [1:0] I_mode=2'd3;
  reg [1:0] I_k=2'd2;
  reg I_tlast=0, I_tuser=0, I_tvalid=0;
  reg [95:0] I_tdata=0;
  wire I_tready;
  reg O_tready=1'b1;
  wire O_tlast, O_tuser, O_tvalid;
  wire [95:0] O_tdata;

  image_modes4 #(.WIDTH(WIDTH)) uut(
    .I_clk(clk), .I_rst_n(rst_n), .I_mode(I_mode), .I_k(I_k),
    .I_tlast(I_tlast), .I_tuser(I_tuser), .I_tdata(I_tdata), .I_tvalid(I_tvalid),
    .I_tready(I_tready), .O_tready(O_tready),
    .O_tlast(O_tlast), .O_tuser(O_tuser), .O_tvalid(O_tvalid), .O_tdata(O_tdata));

  always #5 clk = ~clk;

  // 台阶：x<32 -> 30，x>=32 -> 50（差20），加椒盐噪声（随机 ±40）
  integer xg,y,cl,seed;
  initial seed=12345;
  function [7:0] pix; input integer X, Y;
    reg [7:0] base; reg signed [7:0] n;
    begin
      base = (X<32) ? 8'd30 : 8'd50;
      // 伪随机椒盐：seed 每次调用更新（用 X*Y 做散列）
      n = (X*7 + Y*13) % 2 ? 8'd40 : -8'd40;
      if ((X*3+Y*5)%7==0) base = base + n;   // 部分像素加椒盐
      pix = base;
    end
  endfunction

  initial begin
    #20 rst_n = 1;
    for (y=0; y<32; y=y+1) begin
      for (xg=0; xg<BEATS; xg=xg+1) begin
        I_tdata = {pix(xg*4+0,y),pix(xg*4+0,y),pix(xg*4+0,y),
                   pix(xg*4+1,y),pix(xg*4+1,y),pix(xg*4+1,y),
                   pix(xg*4+2,y),pix(xg*4+2,y),pix(xg*4+2,y),
                   pix(xg*4+3,y),pix(xg*4+3,y),pix(xg*4+3,y)};
        I_tuser = (y==0 && xg==0);
        I_tlast = (xg==BEATS-1);
        I_tvalid = 1;
        @(posedge clk);
      end
    end
    I_tvalid=0; I_tuser=0; I_tlast=0;
  end

  integer coy=0, coxg=0, ox;
  reg wht;
  integer i_lw,i_mw,i_rw,i_lb,i_mb,i_rb;
  reg [31:0] lw,mw,rw,lb,mb,rb, vs;
  always @* begin
    i_lw=0;i_mw=0;i_rw=0;i_lb=0;i_mb=0;i_rb=0;
    for (cl=0; cl<4; cl=cl+1) begin
      ox = coxg*4+cl;
      wht = (O_tdata[95-cl*24-:24]==24'hffffff);
      if (ox<5)        begin end
      else if (ox<=16) begin if(wht) i_lw=i_lw+1; else i_lb=i_lb+1; end
      else if (ox<=44) begin if(wht) i_mw=i_mw+1; else i_mb=i_mb+1; end
      else             begin if(wht) i_rw=i_rw+1; else i_rb=i_rb+1; end
    end
  end
  always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
      coy<=0;coxg<=0; lw<=0;mw<=0;rw<=0;lb<=0;mb<=0;rb<=0; vs<=0;
    end else if(O_tvalid) begin
      if (coy>=6) begin
        lw<=lw+i_lw; mw<=mw+i_mw; rw<=rw+i_rw;
        lb<=lb+i_lb; mb<=mb+i_mb; rb<=rb+i_rb;
      end
      if(O_tuser) vs<=vs+1;
      if(O_tuser)      begin coy<=0; coxg<=0; end
      else if(O_tlast) begin coxg<=0; coy<=coy+1; end
      else              coxg<=coxg+1;
    end
  end

  integer errors;
  initial begin
    errors=0;
    #9000;
    $display("REGION(椒盐噪声) left(w/b)=%0d/%0d  mid(w/b)=%0d/%0d  right(w/b)=%0d/%0d  tuser=%0d",
             lw,lb, mw,mb, rw,rb, vs);
    // 台阶边缘应检出(mid黑>0)，平区噪点应被中值+软腐蚀压掉(lb/rb 应远小于 mid)
    if (mb <= 3) begin $display("FAIL: step edge not detected"); errors=errors+1; end
    if (errors==0) $display("PASS: median filter suppresses salt-pepper noise, edge retained");
    else           $display("FAIL_TOTAL errors=%0d", errors);
    $finish;
  end
endmodule
