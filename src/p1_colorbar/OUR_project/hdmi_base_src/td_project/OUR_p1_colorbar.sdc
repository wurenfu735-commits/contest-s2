# 时序约束（无摄像头版本）
# 本工程设计：50M 主时钟 -> PLL（74.25M 像素 / 371.25M 串行）-> 测试图 -> 边缘检测 -> HDMI
# 原文件为官方 lab_ex1 的裁剪版，含 MIPI/DDR 相关约束，但本设计未例化这些模块
# （.al 里保留了官方源文件但顶层不引用，综合时会被优化掉），故一并清理

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
