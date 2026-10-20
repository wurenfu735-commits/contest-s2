`timescale 1ns/1ps
module tb_isp_adapter;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,v=0,s=0,l=0;reg [95:0] data=0;
 wire ov,os;wire [127:0] od;
 integer y,x,k,n=0,frames=0,first=0,cycle=0,reset_cycle=0;
 reg [127:0] expected;
 reg [23:0] pix;
 isp_top dut(.axi4s_video_aclk(clk),.I_rst_n(rst),.I_tlast(1'b0),
 .I_tuser(1'b0),.I_tdata(40'd0),.I_tvalid(1'b0),.I_tdest(10'd0),
 .O_tready(1'b1),.I_mode(2'd0),.I_k(2'd0),.O_tdata(od),.O_tlast(),
 .O_tuser(os),.O_tvalid(ov),.I_tready());
 always @(negedge clk) if(rst) begin
  cycle=cycle+1;
  if(os) begin frames=frames+1;reset_cycle=cycle;end
  if(ov) begin
   if(n==0 && cycle-reset_cycle<40)$fatal(1,"DDR reset lead too short");
   for(k=0;k<16;k=k+1) begin
    pix=(n*16+k)/3;
    case((n*16+k)%3)
     0:expected[127-k*8-:8]=pix[23:16];
     1:expected[127-k*8-:8]=pix[15:8];
     2:expected[127-k*8-:8]=pix[7:0];
    endcase
   end
   if(od!==expected)$fatal(1,"Packed bytes mismatch word %0d got %h expected %h",n,od,expected);
   n=n+1;
  end
 end
 initial begin
  force dut.awb_O_tvalid=v;force dut.awb_O_tuser=s;
  force dut.awb_O_tlast=l;force dut.awb_O_tdata=data;
  repeat(5)@(posedge clk);#1;rst=1;
  @(posedge clk);#1;s=1;
  @(posedge clk);#1;s=0;
  repeat(54)@(posedge clk);
  for(y=0;y<8;y=y+1) begin
   for(x=0;x<320;x=x+1) begin
    @(posedge clk);#1;v=1;l=(x==319);
    data={24'(y*1280+x*4),24'(y*1280+x*4+1),24'(y*1280+x*4+2),24'(y*1280+x*4+3)};
   end
   @(posedge clk);#1;v=0;l=0;
   repeat(50)@(posedge clk);
  end
  repeat(50)@(posedge clk);
  if(n!=1920||frames!=1)$fatal(1,"Wrong totals words %0d frames %0d",n,frames);
  $display("PASS ISP early SOF adapter and 96-to-128 packing: %0d words",n);$finish;
 end
endmodule
