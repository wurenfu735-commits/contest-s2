# 基于安路 PH1P35 的实时数字图像处理系统

> 全国大学生嵌入式芯片与系统设计竞赛 '2026 · FPGA 创新设计赛道 · 选题二
> 平台：**安路 HX1P35A**（PH1P35MDG324-3）· 摄像头 SC520（MIPI）· 显示 1280×720@60

## 一句话

摄像头 → FPGA（**我们自己写的图像处理算法**）→ 叠加「安路」Logo → HDMI 实时输出到显示器，全程不卡顿。

## 现在到哪了

| 阶段 | 内容 | 状态 |
|---|---|---|
| **P0** | SC520 官方通路基线：编译 / 烧写 / 出实时画面 | ✅ **已完成**（见 [memory/PROGRESS.md](memory/PROGRESS.md)） |
| **P1** | colorbar 自研通路验证 | 进行中 |
| **P2** | 自研自适应阈值边缘检测算法 | 🔜 下一步 |
| **P3** | 处理后视频稳定输出 | 🔜 |
| **P4** | OSD + 「安路」Logo 叠加 | 🔜 |

**P0 基线实测数据**（后续自研的资源对比基准）：

- 资源：Slice 58.40%（余 41.6%）、ERAM20K 36.11%、DSP 20.00%
- 时序：**无违规**（SWNS = +1.242 ns，HWNS = +0.020 ns，违反端点 0）
- 关键时钟：MIPI_RX_BYTE_CLK 103.52 MHz、HDMI_PIXEL_CLK 75 MHz、HDMI_SERIAL_CLK 375 MHz

## 给协作者：从哪开始读

| 想了解 | 读这个 |
|---|---|
| **进度 / 实测数据 / 决策记录**（最该先看） | [`memory/PROGRESS.md`](memory/PROGRESS.md) |
| 题目到底要什么、评委看什么 | [`docs/01_赛题解读.md`](docs/01_赛题解读.md) |
| 整体阅读顺序 | [`docs/00_阅读指南.md`](docs/00_阅读指南.md) |
| 怎么编译、怎么烧写 | [`docs/03_编译烧写速查.md`](docs/03_编译烧写速查.md) |
| 做什么功能、怎么讲 | [`docs/06_情报与呈现方案.md`](docs/06_情报与呈现方案.md) |
| 执行路线图 | [`docs/07_执行路线图.md`](docs/07_执行路线图.md) |
| 算法规格 | [`docs/08_算法规格_P2.md`](docs/08_算法规格_P2.md) |
| 踩过的坑 | [`docs/09_问题总结_按键无响应.md`](docs/09_问题总结_按键无响应.md) |
| 借鉴了哪些开源、差异在哪（**答辩要用**） | [`docs/05_开源调研.md`](docs/05_开源调研.md) |

## 目录结构

```
docs/      文档：赛题解读 / 路线图 / 算法规格 / 速查手册 / 开源调研
memory/    进度与记忆：PROGRESS.md（阶段实测数据）、MEMORY.md
src/       RTL 源码、约束、测试平台、工程脚本
sim/       黄金参考模型（Python）与仿真输出
assets/    手册截图、参考资料图
```

`src/p1_colorbar/` 下：`rtl/` 设计源码 · `tb/` 测试平台 · `constraints/` 约束 · `OUR_project/` TD 工程 · `bitbank/` 历史位流（**不进 git**）· `doc/` · `logs/` · `tools/`

## ⚠️ 两条重要约定

**1. 这个目录约 27.7 GB，但只有约 9 MB 该进版本库。**

绝大部分是仿真/综合产物——单是 `src/p1_colorbar/tb/vsim.wlf` 就有 **26.7 GB**。`.gitignore` 已经挡掉这些。**不要为了让某个产物进仓库而删 `.gitignore` 规则**：仓库会瞬间膨胀到几十 GB，push 必然失败。

被忽略的类别：`*.wlf` `wlft*`、`work/`、`*_Runs/`、`db/`、`incremental_db/`、`output_files/`、`simulation/`、`*.qdb/qpg/qtl/qor/timing/timingsummary`、仿真波形、日志，以及 **`*.bit` 等位流**（见下条）。

**2. 位流走 GitHub Releases，不进 git。**

`src/p1_colorbar/bitbank/` 里的 `.bit` 是"发布产物"而非源码，每个约 1.7 MB。需要发给队友时用 **Releases 附件**配 tag，不要 commit。

**3. 第三方参考资料不随本仓库分发。**

`assets/ref_docs/guoyi_repo*` 是他人 2025 年国一作品的开源副本，有独立来源与许可；按 [`docs/05_开源调研.md`](docs/05_开源调研.md) 里给的 GitHub 地址自行获取即可。参考视频/音频同理。

## 红线（来自赛题规则）

- 官方例程的**算法**禁止照抄，**必须自研**（见 [`docs/07_执行路线图.md`](docs/07_执行路线图.md)）
- 外扩电路板不得含非安路 FPGA

## 协作方式

```bash
git clone <本仓库地址>
cd contest_s2
```

改动走分支 + Pull Request，进度更新直接改 `memory/PROGRESS.md`（按阶段追加实测数据，注明日期）。这样任何人都能靠 `git log` 和 `PROGRESS.md` 看出「做到哪、下一步、卡在哪」。
