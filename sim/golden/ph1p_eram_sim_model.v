// PH1P_LOGIC_ERAM 的行为模型 —— 仅供 ModelSim 仿真使用
//
// 综合时由 TD 的 arch 库（E:\app\Software\work\td\arch\ph1p_macro.v）提供真原语，
// 仿真时用本模型替代（verify_all.ps1 / run_tb.ps1 会把它一起编译）。
//
// 参数列表必须与真原语【逐字对齐】——vopt 会校验例化时传的参数是否存在，
// 少一个就报 "Module parameter 'xxx' not found for override" 并导致加载失败。
//
// 行为要点与真原语一致：
//   - 读是同步的（地址打一拍，数据下一拍出）
//   - WRITEMODE_B = "READBEFOREWRITE" 时，同地址同拍读写先输出旧值再写入
//   - REGMODE = "NOREG" 时输出不额外打拍
//   - 存储内容不初始化（与块 RAM 综合后行为一致）
module PH1P_LOGIC_ERAM (
    dia,
    addra, cea, ocea, clka, wea, rsta, bea,
    dib,
    addrb, ceb, oceb, clkb, web, rstb, beb,
    ecc_sbiterrinj, ecc_dbiterrinj,
    doa,
    dob,
    ecc_sbiterr,
    ecc_dbiterr
);
    parameter DATA_WIDTH_A = 20;
    parameter DATA_WIDTH_B = DATA_WIDTH_A;
    parameter ADDR_WIDTH_A = 10;
    parameter ADDR_WIDTH_B = ADDR_WIDTH_A;
    parameter DATA_DEPTH_A = 2 ** ADDR_WIDTH_A;
    parameter DATA_DEPTH_B = 2 ** ADDR_WIDTH_B;
    parameter BYTE_ENABLE  = 0;
    parameter BYTE_A = (BYTE_ENABLE == 0) ? 1 : (DATA_WIDTH_A / BYTE_ENABLE);
    parameter BYTE_B = (BYTE_ENABLE == 0) ? 1 : (DATA_WIDTH_B / BYTE_ENABLE);
    parameter MODE         = "DP";             // "DP", "SP", "PDPW", "FIFO"
    parameter REGMODE_A    = "NOREG";          // "NOREG", "OUTREG"
    parameter REGMODE_B    = "NOREG";
    parameter WRITEMODE_A  = "NORMAL";         // "NORMAL", "READBEFOREWRITE", "WRITETHROUGH"
    parameter WRITEMODE_B  = "NORMAL";
    parameter RESETMODE_A  = "ASYNC";          // "SYNC", "ASYNC"
    parameter RESETMODE_B  = "ASYNC";
    parameter OREGSET_A    = "SET";            // "SET", "RESET"
    parameter OREGSET_B    = "SET";
    parameter SSROVERCE    = "ENABLE";         // "DISABLE", "ENABLE"
    parameter ECC_DECODE   = "DISABLE";        // "DISABLE", "ENABLE"
    parameter ECC_ENCODE   = "DISABLE";
    parameter ASYNC_RESET_RELEASE_A = "SYNC";
    parameter ASYNC_RESET_RELEASE_B = "SYNC";
    parameter CLKMODE      = "ASYNC";          // "ASYNC", "SYNC"
    parameter DEBUGGABLE   = "NO";
    parameter PACKABLE     = "NO";
    parameter FORCE_KEEP   = "OFF";
    parameter INIT_FILE    = "NONE";
    parameter FILL_ALL     = "NONE";
    parameter IMPLEMENT    = "20K";            // "20K", "20K(FAST)"

    output  ecc_sbiterr;
    output  ecc_dbiterr;
    output  [DATA_WIDTH_A-1:0] doa;
    output  [DATA_WIDTH_B-1:0] dob;
    input   [DATA_WIDTH_A-1:0] dia;
    input   [DATA_WIDTH_B-1:0] dib;
    input   ecc_sbiterrinj, ecc_dbiterrinj;
    input   cea;
    input   ocea;
    input   clka;
    input   wea;
    input   rsta;
    input   ceb;
    input   oceb;
    input   clkb;
    input   web;
    input   rstb;
    input   [BYTE_A-1:0] bea;
    input   [BYTE_B-1:0] beb;
    input   [ADDR_WIDTH_A-1:0] addra;
    input   [ADDR_WIDTH_B-1:0] addrb;

    reg [DATA_WIDTH_A-1:0] mem [0:DATA_DEPTH_A-1];
    reg [DATA_WIDTH_A-1:0] doa_r;
    reg [DATA_WIDTH_B-1:0] dob_r;

    // A 口
    always @(posedge clka) begin
        if (cea) begin
            if (wea) mem[addra] <= dia;
            doa_r <= mem[addra];          // 同步读（旧值）
        end
    end

    // B 口
    always @(posedge clkb) begin
        if (ceb) begin
            dob_r <= mem[addrb];          // 先读：NORMAL / READBEFOREWRITE 均输出旧值
            if (web) mem[addrb] <= dib;   // 后写
        end
    end

    assign doa = doa_r;
    assign dob = dob_r;
    assign ecc_sbiterr = 1'b0;
    assign ecc_dbiterr = 1'b0;

endmodule
