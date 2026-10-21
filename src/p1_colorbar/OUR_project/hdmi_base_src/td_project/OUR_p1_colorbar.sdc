    # 时序约束（摄像头版 · 2026-10-18 更正注释）
    # 设计：50M 主时钟 -> PLL（74.25M 像素 / 371.25M 串行）+ MIPI RX + DDR2 帧缓存
    #       -> ISP(awb) -> 自研边缘检测 -> HDMI
    #
    # 注意：本文件来自官方 lab_ex1 的裁剪版，只约束了 sys_clk_50m 与 PLL 派生时钟。
    #   DDR2 的 usr_clk / ctl_clk / ddr_clk 等由 ph1p35 DDR IP 自带约束产生，
    #   MIPI 恢复时钟由 mipi_dphy_rx 原语产生，均不在本文件里重复定义。
    #   因此 STA coverage 约 43%（TD 报告口径），时序结论只对已约束部分成立 —— 详见 docs/20 第六节。
    # 改动本文件任何一行都必须重新综合+布线，否则现有位流与约束不再对应。

create_clock -name {sys_clk_50m} -period 20.000 -waveform {0.000 10.000} [get_ports {I_sys_clk}]

derive_clocks

rename_clock -name {pll_clk_100m}    [get_clocks {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[0]}]
rename_clock -name {pll_clk_24m}     [get_clocks {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[1]}]
rename_clock -name {HDMI_PIXEL_CLK}  [get_clocks {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[4]}]
rename_clock -name {HDMI_SERIAL_CLK} [get_clocks {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[5]}]

# PLL 输出与 50M 同源，组内需做时序分析；本设计没有其它独立时钟域
set_clock_groups -asynchronous \
    -group [get_clocks {sys_clk_50m pll_clk_100m pll_clk_24m HDMI_PIXEL_CLK HDMI_SERIAL_CLK}]

# 按键与复位是异步输入，不做时序分析（debounce_btn 内部已有两级同步器）
set_false_path -from [get_ports {I_button[*]}]
set_false_path -from [get_ports {I_rst_n}]
