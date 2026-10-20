// Behavioral stub for Anlogic PH1P_LOGIC_ERAM (dual-port RAM) used by window4.v.
// Implements synchronous write on port A and synchronous read on port B so the
// 1-cycle read latency matches what window4 expects. Parameters are accepted
// (to satisfy instance overrides) but ignored in the behavioral model.
module PH1P_LOGIC_ERAM
 #(parameter DATA_WIDTH_A=32, parameter DATA_WIDTH_B=32,
   parameter ADDR_WIDTH_A=9,  parameter ADDR_WIDTH_B=9,
   parameter DATA_DEPTH_A=512, parameter DATA_DEPTH_B=512,
   parameter MODE="DP", parameter REGMODE_A="NOREG", parameter REGMODE_B="NOREG",
   parameter WRITEMODE_A="NORMAL", parameter WRITEMODE_B="NORMAL",
   parameter IMPLEMENT="20K(FAST)", parameter CLKMODE="SYNC",
   parameter RESETMODE_A="ASYNC", parameter RESETMODE_B="ASYNC",
   parameter INIT_FILE="NONE", parameter FILL_ALL="NONE")
 ( input [31:0] dia, input [31:0] dib,
  input [8:0] addra, input [8:0] addrb,
  input cea, input ceb, input ocea, input oceb,
  input clka, input clkb, input wea, input web,
  input bea, input beb, input rsta, input rstb,
  output [31:0] doa, output [31:0] dob,
  output ecc_sbiterr, output ecc_dbiterr,
  input ecc_sbiterrinj, input ecc_dbiterrinj
);
  reg [31:0] mem [0:511];
  reg [31:0] doa_r, dob_r;
  integer mi;
  initial begin
    for (mi=0; mi<512; mi=mi+1) mem[mi]=32'b0;
    doa_r=32'b0; dob_r=32'b0;
  end
  always @(posedge clka) if(cea) begin
    if(wea) mem[addra] <= dia;
    if(~ocea) doa_r <= mem[addra];
  end
  always @(posedge clkb) if(ceb) begin
    if(web) mem[addrb] <= dib;
    if(~oceb) dob_r <= mem[addrb];
  end
  assign doa = doa_r;
  assign dob = dob_r;
  assign ecc_sbiterr = 1'b0;
  assign ecc_dbiterr = 1'b0;
endmodule
