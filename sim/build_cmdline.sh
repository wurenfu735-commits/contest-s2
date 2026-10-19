#!/bin/bash
# 命令行编译：syn_1 → phy_1 → bitgen（用 TD DefaultFlow.tcl，同步执行不卡死）
TD="E:/app/Software/work/td/bin/td_commands_prompt.exe"
FLOW="E:/app/Software/work/td/doc/scripts/DefaultFlow.tcl"
RUNS="E:/fpga/contest_s2/src/p1_colorbar/OUR_project/hdmi_base_src/td_project/OUR_p1_colorbar_Runs"
LOG="E:/fpga/contest_s2/sim/build_cmdline.log"

echo "======== $(date) 开始编译 ========" | tee "$LOG"

echo "---- [1/2] syn_1 ----" | tee -a "$LOG"
cd "$RUNS/syn_1"
"$TD" "$FLOW" >> "$LOG" 2>&1
echo "syn 退出码: $?" | tee -a "$LOG"
grep -E "FLOW_RESULT|ERROR|PRJ-1401" "$LOG" | tail -5 | tee -a "$LOG"

echo "---- [2/2] phy_1 ----" | tee -a "$LOG"
cd "$RUNS/phy_1"
"$TD" "$FLOW" >> "$LOG" 2>&1
echo "phy 退出码: $?" | tee -a "$LOG"
grep -E "FLOW_RESULT|ERROR" "$LOG" | tail -5 | tee -a "$LOG"

echo "---- bit 检查 ----" | tee -a "$LOG"
ls -la "$RUNS/phy_1/OUR_p1_colorbar.bit" 2>&1 | tee -a "$LOG"
echo "======== $(date) 编译结束 ========" | tee -a "$LOG"
