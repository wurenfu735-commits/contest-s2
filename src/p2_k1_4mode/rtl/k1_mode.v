module k1_mode #(parameter CLK_HZ=50000000, parameter DEBOUNCE_MS=20)(
 input clk, input rst_n, input key_n, output reg [1:0] mode_gray
);
 localparam LIMIT=CLK_HZ/1000*DEBOUNCE_MS;
 (* async_reg="true" *) reg key_meta,key_sync;
 reg stable;
 reg [31:0] count;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   key_meta<=1; key_sync<=1; stable<=1; count<=0; mode_gray<=0;
  end else begin
   key_meta<=key_n; key_sync<=key_meta;
   if(key_sync==stable) count<=0;
   else if(count==LIMIT-1) begin
    count<=0; stable<=key_sync;
    if(!key_sync) case(mode_gray)
     0:mode_gray<=1; 1:mode_gray<=3; 3:mode_gray<=2; 2:mode_gray<=0;
    endcase
   end else count<=count+1'b1;
  end
 end
endmodule
