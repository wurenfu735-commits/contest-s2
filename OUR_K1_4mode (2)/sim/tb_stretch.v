`timescale 1ns/1ps
// 验证 stretch() 对比度拉伸：暗区 1~6 应被拉到 ~28~60
module tb_stretch;
  reg [7:0] v;
  function [7:0] stretch;
    input [7:0] vv;
    reg [7:0] base; reg [7:0] delta; reg [11:0] interp;
    begin
      case(vv[7:4])
        4'h0: begin base=8'd0;   delta=8'd37; end
        4'h1: begin base=8'd37;  delta=8'd26; end
        4'h2: begin base=8'd63;  delta=8'd19; end
        4'h3: begin base=8'd82;  delta=8'd15; end
        4'h4: begin base=8'd97;  delta=8'd13; end
        4'h5: begin base=8'd110; delta=8'd12; end
        4'h6: begin base=8'd122; delta=8'd11; end
        4'h7: begin base=8'd133; delta=8'd10; end
        4'h8: begin base=8'd143; delta=8'd10; end
        4'h9: begin base=8'd153; delta=8'd9;  end
        4'ha: begin base=8'd162; delta=8'd9;  end
        4'hb: begin base=8'd171; delta=8'd8;  end
        4'hc: begin base=8'd179; delta=8'd8;  end
        4'hd: begin base=8'd187; delta=8'd8;  end
        4'he: begin base=8'd195; delta=8'd8;  end
        default: begin base=8'd203; delta=8'd52; end
      endcase
      interp = delta * vv[3:0] + 8;
      stretch = (vv==8'hff) ? 8'hff : base + (interp>>4);
    end
  endfunction
  integer i;
  initial begin
    $display("=== stretch 验证（暗区 1~6 应拉到 28~60）===");
    for(i=1;i<=10;i=i+1) begin
      v=i; #1; $display("gray %0d -> %0d", i, stretch(v));
    end
    for(i=16;i<=80;i=i+16) begin
      v=i; #1; $display("gray %0d -> %0d", i, stretch(v));
    end
    v=255; #1; $display("gray 255 -> %0d", stretch(v));
    $finish;
  end
endmodule
