// ERAM 原语最小复现探针
//
// 目的：判定 TD 能否把"在普通 HDL 里裸例化的 PH1P_LOGIC_ERAM"变成真正的块 RAM 资源。
//   - 若综合后 #eram >= 1  -> 裸例化可行，问题在我们的算法代码里
//   - 若综合后 #eram = 0   -> 必须走 TD 的 IP 生成器（blk_mem_gen），不能用裸例化
//
// 用法（独立小工程，几分钟）：
//   1. TD 新建工程，器件选 PH1P35MDG324-3
//   2. 只添加本文件，顶层设为 eram_probe
//   3. 跑综合，看资源报告的 #eram
//   （不需要引脚约束；输出用 (* keep *) 保住，防止被优化掉）
module eram_probe #(
    parameter ADDR_W = 11,       // 11 -> 2048 深
    parameter DEPTH  = 2048
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [7:0]  din,
    output reg  [7:0]  dout
);
    reg  [ADDR_W-1:0] wr_addr;
    reg  [ADDR_W-1:0] rd_addr;
    (* keep = "true" *) wire [7:0] doa;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_addr <= {ADDR_W{1'b0}};
            rd_addr <= {ADDR_W{1'b0}};
            dout    <= 8'd0;
        end else begin
            wr_addr <= wr_addr + 1'b1;
            rd_addr <= wr_addr;            // 读地址落后写地址一拍（读旧值）
            dout    <= doa;                // 打一拍，保证 dout 依赖 doa
        end
    end

    PH1P_LOGIC_ERAM #(
        .DATA_WIDTH_A(8), .DATA_WIDTH_B(8),
        .ADDR_WIDTH_A(ADDR_W), .ADDR_WIDTH_B(ADDR_W),
        .DATA_DEPTH_A(DEPTH), .DATA_DEPTH_B(DEPTH),
        .BYTE_ENABLE(0), .BYTE_A(1), .BYTE_B(1),
        .MODE("DP"),
        .REGMODE_A("NOREG"), .REGMODE_B("NOREG"),
        .WRITEMODE_A("NORMAL"), .WRITEMODE_B("READBEFOREWRITE"),
        .RESETMODE_A("ASYNC"), .RESETMODE_B("ASYNC"),
        .OREGSET_A("RESET"), .OREGSET_B("RESET"),
        .SSROVERCE("DISABLE"),
        .ECC_ENCODE("DISABLE"), .ECC_DECODE("DISABLE"),
        .ASYNC_RESET_RELEASE_A("ASYNC"), .ASYNC_RESET_RELEASE_B("ASYNC"),
        .CLKMODE("ASYNC"), .DEBUGGABLE("NO"), .PACKABLE("NO"), .FORCE_KEEP("OFF"),
        .INIT_FILE("NONE"), .FILL_ALL("NONE"),
        .IMPLEMENT("20K(FAST)")
    ) u_ram (
        .clka(clk), .cea(1'b1), .ocea(1'b0), .addra(rd_addr), .wea(1'b0), .dia(8'd0), .rsta(1'b0), .bea(1'b0),
        .clkb(clk), .ceb(1'b1), .oceb(1'b0), .addrb(wr_addr), .web(1'b1), .dib(din), .rstb(1'b0), .beb(1'b0),
        .doa(doa), .dob(),
        .ecc_sbiterrinj(1'b0), .ecc_dbiterrinj(1'b0), .ecc_sbiterr(), .ecc_dbiterr()
    );

endmodule
