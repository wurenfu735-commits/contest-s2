# p1_colorbar · 目录规约（文件存放规划）

> P1 阶段自研产物的存放规则。核心原则：**本目录只保留最新有效版本，旧版本一律进 `archive\`**。

## 一、目录职责

| 目录 / 文件          | 放什么                                                                                                          | 更新规则                                                      |
| ---------------- | ------------------------------------------------------------------------------------------------------------ | --------------------------------------------------------- |
| `rtl\`           | 4 个自研 Verilog：`colorbar_top.v`（顶层）、`vtc_720p.v`（720p 时序）、`test_pattern_gen.v`（图案+状态带）、`debounce_btn.v`（按键消抖） | **只留当前有效版**，改版直接覆盖                                        |
| `tb\`            | 测试平台源码：`tb_ptn.v`（图案自检）、`tb_debounce.v`（消抖逻辑）、`tb_debounce_real.v`（真实参数）、`run_tb.do`                         | 同上；**绝不放仿真产物**                                            |
| `constraints\`   | `colorbar_top.adc`（引脚约束，含按键/LED/HDMI/时钟）                                                                     | 同上                                                        |
| `bitbank\`       | **只放最新可用的 bit** + [`BIT文件台账_防混淆.md`](BIT文件台账_防混淆.md)                                                         | 新 bit 归档后，旧 bit 移入 archive                                |
| `logs\`          | 可复用的编译脚本与关键日志（`rebuild_v3c.tcl` = 命令行编译脚本；`*_console.log` = 编译证据）                                            | 失败尝试的日志进 archive                                          |
| `tools\`         | 可复用的小工具：`vlm_frames_probe.py`（抽帧喂视觉模型）、`extract_pptx.py`（PPT 文本+图提取）                                         | 一次性脚本用完进 archive                                          |
| `OUR_project\`   | TD 工程本体（活工程，内含 td_project + user_source）                                                                     | **不改名、不移动**                                               |
| `archive\`       | **旧版本集中存放**：`old_bit\`、`oneoff_scripts\`、`old_logs\`                                                         | 只进不出，配 [`archive\README_旧版说明.md`](archive/README_旧版说明.md) |
| `BIT文件台账_防混淆.md` | 版本对照表（防烧错文件）                                                                                                 | 每次生成新 bit 必须更新                                            |

## 二、什么算"最新版本"（判断依据）

1. **rtl / tb / constraints**：内容 = 当前 TD 工程实际编译的那一份（文件时间戳应 ≥ 最后一次编译时间）
2. **bitbank 里的 bit**：与当前源码一致、**且上板验证通过**的那一版
3. 交叉核对：`logs\` 里有对应的编译记录 + `BIT文件台账` 里有登记

> 现状（2026-10-14）：现行 bit = `OUR_p1_colorbar_v3_debounce_fix.bit`；现行 RTL = `debounce_btn.v`(24 位计数器修复版) + `colorbar_top.v`(含 O_led 指示)。

## 三、旧版本处理（三步走）

1. 移入 `archive\` 对应子目录（`old_bit\` / `oneoff_scripts\` / `old_logs\`）
2. 在 `archive\README_旧版说明.md` 登记一行：**文件名 / 为什么旧 / 被谁取代**
3. **src 主目录不留旧版本**（避免烧错 bit、改错代码）

## 四、不进版本管理的东西（可随时删）

| 类别            | 具体                                                             | 说明                     |
| ------------- | -------------------------------------------------------------- | ---------------------- |
| ModelSim 仿真产物 | `vsim.wlf`、`wlft*`、`work\`、`transcript`、`vish_stacktrace.vstf` | **可再生的垃圾**，见下方教训       |
| TD 中间产物       | `OUR_p1_colorbar_Runs\` 内部（TD 自己管理）                            | 别手动删，工程要用              |
| 下载的参考资料       | 官方包、第三方仓库、参考视频                                                 | 放 `assets\`，**不放 src** |

> ⚠️ **真实教训（2026-10-14）**：`tb\vsim.wlf` 单个文件涨到 **26 GB**，而且被一个从 18:14 残留到 22:39 的 `vsimk.exe` 占用，普通删除直接失败（报 "being used by another process"）。  
> **处理办法**：先 `Get-Process vsimk | Stop-Process -Force` 结束残留内核，再删文件。  
> **预防**：跑完波形仿真立刻清 `vsim.wlf`，或把波形输出路径指到项目外。

## 五、给团队的一句话

> 拿到这个目录时，**先看 `rtl\` + `constraints\` + `bitbank\` 这三处的最新版**，`archive\` 里的东西一律当"历史证据"看，不参与编译、不用于烧录。
