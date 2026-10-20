`timescale 1ns/1ps
module tb_rgb;
reg clk=0;always #5 clk=~clk;
reg rst=0,v=0,s=0,l=0;reg [95:0] d=0;
wire ov;wire [95:0] od;integer n=0;
image_modes4 #(.WIDTH(8)) dut(.I_clk(clk),.I_rst_n(rst),.I_mode(2'd1),
.I_tlast(l),.I_tuser(s),.I_tdata(d),.I_tvalid(v),.I_tready(),.O_tready(1'b1),
.O_tlast(),.O_tuser(),.O_tdata(od),.O_tvalid(ov));
always @(negedge clk) if(ov) begin
 if(n==0 && od!==96'h4d4d4d9595951d1d1dffffff)$fatal(1,"RGB primary weights %h",od);
 if(n==1 && od!==96'h000000010101fefefeffffff)$fatal(1,"RGB full range %h",od);
 n=n+1;
end
initial begin
 repeat(5)@(posedge clk);#1;rst=1;
 @(posedge clk);#1;v=1;s=1;d=96'hff000000ff000000ffffffff;
 @(posedge clk);#1;s=0;l=1;d=96'h000000010101fefefeffffff;
 @(posedge clk);#1;v=0;l=0;
 repeat(30)@(posedge clk);
 if(n!=2)$fatal(1,"Wrong RGB count");
 $display("PASS RGB channel weights and full-range black/white endpoints");$finish;
end
endmodule
