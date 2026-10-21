// tb_cartoon_96.v —— 卡通化 RTL 验证（对齐 tools/gen_golden_cartoon.py）
//
// 验证重点：「量化」+「边缘压黑」两个功能。用**恒定输入分阶段**验证：
//   流水填满后输出与具体延迟无关，彻底避开 tb 内部参考流水与 DUT 读 I_edge 的同拍竞争。
//   阶段：
//     A) 原图非边缘 + I_edge=0        → 输出 = 量化原图（验证量化）
//     B) 原图边缘像素 + I_edge=全1    → 输出 = 黑（验证压黑）
//     C) 原图非边缘 + I_edge=全1      → 输出 = 黑（验证 I_edge 确实控制压黑）
//     D) 原图边缘像素 + I_edge=0      → 输出 = 量化原图（验证 orig 确实参与）
//
// ModelSim SE-64 10.5 兼容（仅 Verilog-2001）
`timescale 1ns / 1ps

module tb_cartoon_96;

    reg         I_clk;
    reg         I_rst_n;
    reg  [95:0] I_orig;
    reg         I_orig_valid;
    reg  [95:0] I_edge;
    reg         I_valid;
    reg         I_last;
    reg         I_user;
    wire [95:0] O_tdata;
    wire        O_valid;
    wire        O_last;
    wire        O_user;

    integer errors;

    cartoon_96 #(.QBITS(3)) dut (
        .I_clk   (I_clk),
        .I_rst_n (I_rst_n),
        .I_orig  (I_orig),
        .I_orig_valid (I_orig_valid),
        .I_edge  (I_edge),
        .I_valid (I_valid),
        .I_last  (I_last),
        .I_user  (I_user),
        .O_tdata (O_tdata),
        .O_valid (O_valid),
        .O_last  (O_last),
        .O_user  (O_user)
    );

    initial I_clk = 1'b0;
    always #5 I_clk = ~I_clk;

    // ---- 参考模型（与黄金模型同构）----
    function [23:0] qpix;
        input [23:0] p;
        begin
            qpix = { p[23:21], 5'b0, p[15:13], 5'b0, p[7:5], 5'b0 };
        end
    endfunction
    function [95:0] q4;
        input [95:0] p;
        begin
            q4 = {qpix(p[95:72]), qpix(p[71:48]), qpix(p[47:24]), qpix(p[23:0])};
        end
    endfunction

    function [95:0] mk4;
        input [23:0] a, b, c, d;
        begin
            mk4 = {a, b, c, d};
        end
    endfunction
    function [95:0] allof;
        input [23:0] p;
        begin
            allof = {p, p, p, p};
        end
    endfunction

    reg [95:0] P0, P1;   // P0 非边缘，P1 边缘像素（R=0xFF）
    reg [95:0] QP0, QP1; // 量化后
    reg [95:0] BLACK;

    // 单拍驱动：在 negedge 设输入，便于 DUT 在 posedge 稳定采样
    task drive;
        input [95:0] o_in;
        input [95:0] e_in;
        begin
            @(negedge I_clk);
            I_orig = o_in;
            I_edge = e_in;
        end
    endtask

    // 跑 N 拍，最后 3 拍比对 expect
    task run_phase;
        input [95:0] o_in;
        input [95:0] e_in;
        input [95:0] expect;
        input [7:0]  n;
        input [8*32:1] name;
        integer i;
        begin
            for (i = 0; i < n; i = i + 1) begin
                drive(o_in, e_in);
                @(posedge I_clk); #1;
                if (i >= n - 3) begin   // 最后 3 拍比对（流水已填满）
                    if (O_tdata !== expect) begin
                        $display("FAIL %0s beat=%0d got=%h exp=%h", name, i, O_tdata, expect);
                        errors = errors + 1;
                    end else begin
                        $display("PASS %0s beat=%0d", name, i);
                    end
                end
            end
        end
    endtask

    initial begin
        errors = 0;
        P0 = mk4(24'hB2357A, 24'hB2357A, 24'hB2357A, 24'hB2357A); // 非边缘
        P1 = mk4(24'hFF0000, 24'hFF0000, 24'hFF0000, 24'hFF0000); // 边缘（R=FF）
        QP0 = q4(P0);
        QP1 = q4(P1);
        BLACK = 96'd0;

        I_rst_n = 1'b0;
        I_valid = 1'b0;
        I_orig_valid = 1'b0;
        I_last  = 1'b0;
        I_user  = 1'b0;
        I_orig  = 96'd0;
        I_edge  = 96'd0;

        #20 I_rst_n = 1'b1;
        #10;
        I_valid = 1'b1;
        I_orig_valid = 1'b1;

        // A) 非边缘 + I_edge=0 → 量化原图
        run_phase(P0, 96'd0, QP0, 8, "A_quant");
        // B) 边缘像素 + I_edge=全1 → 黑
        run_phase(P1, 96'hFFFFFFFFFFFFFFFFFFFFFFFF, BLACK, 8, "B_black");
        // C) 非边缘 + I_edge=全1 → 黑（I_edge 控制压黑）
        run_phase(P0, 96'hFFFFFFFFFFFFFFFFFFFFFFFF, BLACK, 8, "C_edge_ctrl");
        // D) 边缘像素 + I_edge=0 → 量化（orig 参与）
        run_phase(P1, 96'd0, QP1, 8, "D_orig_used");

        #20;
        if (errors == 0)
            $display("==== tb_cartoon_96 ALL PASS (quant + blacken, 4 phases) ====");
        else
            $display("==== tb_cartoon_96 FAIL count=%0d ====", errors);
        $finish;
    end

    initial begin
        #200000;
        $display("FAIL: timeout");
        $finish;
    end

endmodule
