# archive · 旧版本说明

> ⚠️ 这里的内容**全部是旧版本**，仅作参考与追溯，**不要用于编译、不要烧录**。
> 现行版本在上一级目录：`rtl\`（源码）、`bitbank\`（bit）、`logs\`（编译脚本）、`tools\`（工具）。

## old_bit\ —— 旧 bit（**别烧**）

| 文件 | 为什么是旧版 | 被谁取代 |
|---|---|---|
| `OUR_p1_colorbar_v1_20261014.bit` | **按键约束在扩展口 N2/J14**（照抄官方 pin.adc），板载 KEY1/KEY2 根本按不到 → 按键功能等于没有 | v3 |
| `OUR_p1_colorbar_v2_onboard_key.bit` | 按键已改到板载 D5/A9，但 **`debounce_btn.v` 的采样计数器位宽不足**（16 位装不下 74249）→ 采样脉冲永不产生，**按键完全无响应**（综合器还把这段死逻辑优化掉了：reg 仅 1256） | v3 |

**✅ 现行可用版本**：见 `..\bitbank\位流台账.md` 的「★ 现行版本」行（P1 里程碑 = `..\bitbank\OUR_p1_colorbar_verified.bit`）
（2026-10-14 22:19 生成；按键切图案 + LED 指示 + 状态带全部上板验证通过；reg 1409 / LUT 941 / 时序无违规）

## oneoff_scripts\ —— 一次性脚本（已完成使命）

| 文件 | 当时用途 | 现在为什么不用 |
|---|---|---|
| `rename_project.ps1` | 把工程从官方同名 `camera_to_dsi_display` 三层改名为 `OUR_p1_colorbar`（目录 + 工程文件 + `.al` 内容同步） | 改名已完成，工程现名 `OUR_project\hdmi_base_src\td_project\OUR_p1_colorbar.al`，再跑会因找不到源目录而报错退出 |

## old_logs\ —— 失败尝试的编译日志

| 文件 | 那次尝试的问题 |
|---|---|
| `rebuild_v3.tcl`、`rebuild_v3_console.log`、`build_v3_rebuild.log` | **第一次**：TD 认为综合 run 已完成 → `launch_runs` 直接跳过综合 → bit 没更新（时间戳仍是旧的） |
| `rebuild_v3b.tcl`、`rebuild_v3b_console.log` | **第二次**：脚本末尾 `exit` 把**异步**的 run 掐断了（且 `reset_runs` 清空了 phy 产物） |

**✅ 成功的做法**：`..\logs\rebuild_v3c.tcl` —— 用独立进程 + 重定向 stdin 让 TD 一直活着，从外部轮询产物文件判断完成。
完整说明见 [`docs\archive\03_编译烧写速查.md`](../../../docs/archive/03_编译烧写速查.md) 第三节「命令行编译」。

---
*本文件由 AI 于 2026-10-14 整理生成；后续新增旧版本请在此追加一行。*
