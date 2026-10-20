// Four pixels/clock. Causal 3x3 window ends at (x,y).
// Three rotating synchronous RAM banks avoid read/write collision dependence.
// Top two rows and left two columns are marked invalid; RAM needs no reset.
module window4 #(parameter WIDTH=1280, parameter SIDE=128)(
 input clk,input rst_n,input valid,input sof,input eol,
 input [31:0] gray,input [SIDE-1:0] side,
 output reg ov,output reg os,output reg ol,
 output reg [287:0] win,output reg [3:0] good,
 output reg [SIDE-1:0] aside
);
 localparam GROUPS=WIDTH/4;
 wire [31:0] q0,q1,q2;
 reg [31:0] cur;
 reg [10:0] x,y;
 reg [1:0] bank,rd_bank;
 wire [10:0] ax=sof?11'd0:x;
 wire [10:0] ay=sof?11'd0:y;
 wire [1:0] ab=sof?2'd0:bank;
 reg v1,s1,l1,left1,rows1;
 reg [SIDE-1:0] side1;
 reg [15:0] tail0,tail1,tail2;
 wire [31:0] prev1=(rd_bank==0)?q2:(rd_bank==1)?q0:q1;
 wire [31:0] prev2=(rd_bank==0)?q1:(rd_bank==1)?q2:q0;
 wire [47:0] r0={prev2,left1?16'd0:tail0};
 wire [47:0] r1={prev1,left1?16'd0:tail1};
 wire [47:0] r2={cur,left1?16'd0:tail2};
 integer p,k;
 // Explicit Anlogic ERAM: 512 x 32 per bank, synchronous read.
 // The bank being written is never used as either previous-row source.
 line_ram4 bank0(.clk(clk),.address(ax[8:0]),.we(valid&&ab==0),.data(gray),.q(q0));
 line_ram4 bank1(.clk(clk),.address(ax[8:0]),.we(valid&&ab==1),.data(gray),.q(q1));
 line_ram4 bank2(.clk(clk),.address(ax[8:0]),.we(valid&&ab==2),.data(gray),.q(q2));
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   x<=0;y<=0;bank<=0;rd_bank<=0;cur<=0;
   v1<=0;s1<=0;l1<=0;left1<=0;rows1<=0;side1<=0;
   ov<=0;os<=0;ol<=0;win<=0;good<=0;aside<=0;
   tail0<=0;tail1<=0;tail2<=0;
  end else begin
   v1<=valid;s1<=sof&&valid;l1<=eol&&valid;
   ov<=v1;os<=s1;ol<=l1;aside<=side1;
   if(valid) begin
    cur<=gray;rd_bank<=ab;side1<=side;left1<=ax==0;rows1<=ay>=2;
    if(eol) begin x<=0;y<=ay+1'b1;bank<=(ab==2)?0:ab+1'b1;end
    else begin x<=ax+1'b1;y<=ay;bank<=ab;end
   end
   if(v1) begin
    tail0<=prev2[31:16];tail1<=prev1[31:16];tail2<=cur[31:16];
    for(p=0;p<4;p=p+1) begin
     good[p]<=rows1&&(!left1||p>=2);
     for(k=0;k<3;k=k+1) begin
      win[p*72+k*8+:8]<=r0[(p+k)*8+:8];
      win[p*72+24+k*8+:8]<=r1[(p+k)*8+:8];
      win[p*72+48+k*8+:8]<=r2[(p+k)*8+:8];
     end
    end
   end
  end
 end
endmodule

module line_ram4(input clk,input [8:0] address,input we,input [31:0] data,output [31:0] q);
 PH1P_LOGIC_ERAM #(
  .DATA_WIDTH_A(32),.DATA_WIDTH_B(32),.ADDR_WIDTH_A(9),.ADDR_WIDTH_B(9),
  .DATA_DEPTH_A(512),.DATA_DEPTH_B(512),.MODE("DP"),
  .REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
  .WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),
  .IMPLEMENT("20K(FAST)"),.CLKMODE("SYNC"),
  .RESETMODE_A("ASYNC"),.RESETMODE_B("ASYNC"),
  .INIT_FILE("NONE"),.FILL_ALL("NONE")
 ) mem(
  .dia(data),.dib(32'd0),.addra(address),.addrb(address),
  .cea(1'b1),.ceb(1'b1),.ocea(1'b0),.oceb(1'b0),
  .clka(clk),.clkb(clk),.wea(we),.web(1'b0),
  .bea(1'b0),.beb(1'b0),.rsta(1'b0),.rstb(1'b0),
  .doa(),.dob(q),.ecc_sbiterr(),.ecc_dbiterr(),
  .ecc_sbiterrinj(1'b0),.ecc_dbiterrinj(1'b0));
endmodule
