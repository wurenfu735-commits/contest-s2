`timescale 1ns/1ps
module tb;
reg clk=0;always #5 clk=~clk;
reg rst=0;reg [111:0] token=0;
wire ov,os,ol;wire [95:0] od;
reg [111:0] ins[0:1114559];reg [103:0] exp[0:921599];
integer i,n=0,errors=0;
image_modes4 dut(.I_clk(clk),.I_rst_n(rst),.I_mode(token[97:96]),
.I_tvalid(token[108]),.I_tuser(token[104]),.I_tlast(token[100]),.I_tdata(token[95:0]),
.I_tready(),.O_tready(1'b1),.O_tvalid(ov),.O_tuser(os),.O_tlast(ol),.O_tdata(od));
always @(negedge clk) if(rst&&ov) begin
 if(n>=921600) $fatal(1,"Too many outputs");
 if({os,ol,od} !== {exp[n][100],exp[n][96],exp[n][95:0]}) begin
  if(errors<8)$display("Mismatch %0d got=%h expected=%h",n,od,exp[n][95:0]);
  errors=errors+1;
 end
 n=n+1;
end
initial begin
 $readmemh("input.hex",ins);$readmemh("expected.hex",exp);
 repeat(5)@(posedge clk);#1;rst=1;
 for(i=0;i<1114560;i=i+1) begin @(posedge clk);#1;token=ins[i];end
 @(posedge clk);#1;token=0;
 repeat(40)@(posedge clk);
 if(errors||n!=921600)$fatal(1,"FAIL errors=%0d tokens=%0d",errors,n);
 $display("PASS four modes: %0d groups / %0d pixels",n,n*4);$finish;
end
endmodule
