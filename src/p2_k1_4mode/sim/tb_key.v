`timescale 1ns/1ps
module tb_key;
 reg clk=0;always #10 clk=~clk;
 reg rst=0,key=1;
 wire [1:0] mode;
 k1_mode dut(.clk(clk),.rst_n(rst),.key_n(key),.mode_gray(mode));
 task cycles;input integer n;integer j;begin for(j=0;j<n;j=j+1)@(negedge clk);end endtask
 task check;input [1:0] want;begin if(mode!==want)$fatal(1,"key mode got %d want %d",mode,want);end endtask
 task press;input [1:0] want;
 begin
  key=0;cycles(5000);key=1;cycles(5000);key=0;cycles(5000);key=1;cycles(5000);
  key=0;cycles(1000010);check(want);
  cycles(1100000);check(want);
  key=1;cycles(5000);key=0;cycles(5000);key=1;cycles(1000010);check(want);
 end endtask
 initial begin
  cycles(5);rst=1;cycles(1000010);check(0);
  press(1);press(3);press(2);press(0);
  $display("PASS KEY1 actual 50 MHz / 20 ms: bounce, hold, release, four presses");$finish;
 end
endmodule
