# 基于安路 PH1P35 的实时数字图像处理系统

> 全国大学生嵌入式芯片与系统设计竞赛 '2026 · FPGA 创新设计赛道 · 选题二  
> 平台：**安路 HX1P35A**（PH1P35MDG324-3）· 摄像头 SC520（MIPI）· 显示 1280×720@60

## 一句话

摄像头 → FPGA（**我们自己写的图像处理算法** + **Logo/动态信息 OSD 叠加**）→ HDMI 实时输出到显示器，全程不卡顿。

## 现在到哪了

| 阶段 | 内容 | 状态 |
|---|---|---|
| **P0** | SC520 官方通路基线：编译 / 烧写 / 出实时画面 | ✅ **已完成**（10-14） |
| **P1** | 自研 720p 时序 + 测试图 + 按键/LED（显示地基） | ✅ **已完成并上板验证**（10-14） |
| **P2** | 自研自适应阈值边缘检测算法（96bit 并行，现为 **v4**） | ✅ **已完成**：仿真 0 误差（run_tb_96.ps1）、摄像头通路出轮廓（A3） |
| **A2** | 四态演示版（原图 / 官方判决 / 我们判决 / 左右分屏） | ❌ 位流过时（**内含 v1 旧算法**），待用 v4 算法重新综合 |
| **A3** | 算法接入 SC520 摄像头通路 + 噪声鲁棒性迭代 v1→v4 | ⏸ **v4 暂停点**：基本功能实现、雪花显著减少但仍有残留；现行位流 [`OUR_a3_camera_v4_pending.bit`](src/p1_colorbar/bitbank/位流台账.md)（台账 ★ 现行版本） |
| **B4** | 赛题「基础」第 4 条：OSD 叠加安路 Logo | ✅ **已完成并上板验证**（10-17 深夜）：官方 `hdmi_mixer` + `anlogic_logo_rom` + `osd_char_lib` **原样**入工程，Logo + 动态信息正常显示，见 [`docs/14`](docs/14_B4_OSD更新说明.md) · [`docs/15`](docs/15_上板实测指南.md) |
| **P4** | OSD 自研版（备选分支） | 🧩 **已实现、可切换**：`rtl/osd_overlay.v` + `rtl/osd_logo_rom.v`，定义 `OSD_SELF_DEV` 即切回。比官方版省 **2,533 slice**（78.76% → 69.07%），见 [`docs/17`](docs/17_优化点与官方边界.md) |

> 完整进度、每阶段实测数据与决策记录：**[`memory/PROGRESS.md`](memory/PROGRESS.md)**
> 阶段总结与上板验收单：**[`docs/12_阶段总结_摄像头版接入与上板验收.md`](docs/12_阶段总结_摄像头版接入与上板验收.md)**

### 关键实测数据

| 项目 | 数据 |
|---|---|
| v4 算法验证 | `run_tb_96.ps1` 一键：RTL 与 v4 黄金模型逐像素比对 **0 误差**（PASS；±3 确定性噪声图案） |
| 算法综合 | `u_edge_adaptive_96`（摄像头版接入时 **v1 形态**实测）LUT **1134** / ripple **148** / ERAM 11 / **DSP 0**；**v4 形态（2026-10-16 18:58 综合）LUT 12187 / reg 14384 / slices 4832（22.78%）/ RAMs 63 / DSP 8** |
| 全设计 · 无 OSD（v4） | slice **14,177（66.82%，P&R）** / RAMs 60 / DSP 8 / **Setup WNS +0.376 ns** / 0 违规 |
| 全设计 · 官方 OSD（B4，现行） | slice **16,710（78.76%）** / `u_hdmi_mixer` 层 **2,753 LUT + 229 reg + 1 DSP** / **Setup WNS +0.005 ns** / 0 违规 |
| 全设计 · 自研 OSD（备选） | slice **14,654（69.07%）** / `u_osd_overlay` 层仅 **593 LUT** / **Setup WNS +0.787 ns** |
| 资源总账（syn.log 实测） | Slice 16,454/21,216（**77.55%**）· ERAM **63/108**（58.33%）· **DSP 9/40（22.50%，剩 31 个）** · Slice Reg 14,454/42,432（34.06%） |
| P0 官方基线 | Slice 58.40% / DSP 20% / SWNS +1.242 ns / 0 违规 |

`ripple > 0` 是关键证据：证明均值求和 / 梯度差 / 阈值比较这套加法逻辑**确实进了网表**，没被综合器优化掉。

> ⚠️ **资源判断的坑**：我们缺的是 **Slice**（77.55%），**不缺 DSP**（只用 22.5%）。所以网上 Sobel 工程那套"kernel 全展开成移位加法、做到 0 DSP"的经验，对我们**是负优化**——省下的 DSP 换来更多 LUT 和进位链。详见 [`docs/17`](docs/17_优化点与官方边界.md) 第二节推论 2。

### 诚实结论（答辩时要讲）

- ✅ 摄像头 → ISP → DDR → HDMI 通路正常，自研算法输出替代官方边缘检测，**物体轮廓清晰、画面实时**
- ⚠️ 平面上**仍有残留雪花**：原图本身有传感器暗场噪声（经 awb 增益放大），边缘检测把它显性化了。
  v4 的分段阈值已显著减少但未根治，**当前暂停完善**，候选方案见 PROGRESS.md
- ⚠️ A2 位流：内含 **v1 旧算法**，已被 v4 取代，等用 v4 算法重新综合后废弃旧版
  （早期"行缓存被综合成 1024 深 LOGIC_RAMFIFO、算法没进网表"的问题当时已用 keep 约束解决，见 PROGRESS.md）
- ℹ️ **上板看到黑白画面是设计行为，不是故障**：两套 OSD 都工作在边缘模式，`edge_rgb_adapter.v:79` 二值输出（纯黑/纯白），所以 Logo 是彩色叠加、画面本身是随景物实时变化的黑白边缘图。这与 `docs/12` 的验收标准一致。若要看彩色原图，把 `design_top_wrapper.v` 的 `I_mode` 改为 `2'd0`（原图直通）。

## 给协作者：从哪开始读

| 想了解 | 读这个 |
|---|---|
| **进度 / 实测数据 / 决策记录**（最该先看） | [`memory/PROGRESS.md`](memory/PROGRESS.md) |
| 文档全貌与推荐阅读顺序 | [`docs/00_阅读指南.md`](docs/00_阅读指南.md) |
| 题目到底要什么、评委看什么 | [`docs/01_赛题解读.md`](docs/01_赛题解读.md) |
| **文件放在哪、什么不进版本库** | [`docs/02_文件存放规划.md`](docs/02_文件存放规划.md) |
| 怎么编译、怎么烧写（**每次上板前**） | [`docs/03_编译烧写速查.md`](docs/03_编译烧写速查.md) |
| 位流清单：哪个是现行的 / 该看到什么现象 | [`src/p1_colorbar/bitbank/位流台账.md`](src/p1_colorbar/bitbank/位流台账.md) |
| **哪些是自研、哪些复用官方**（答辩必用） | [`docs/11_复用与自研清单.md`](docs/11_复用与自研清单.md) |
| **最新阶段总结与上板验收单** | [`docs/12_阶段总结_摄像头版接入与上板验收.md`](docs/12_阶段总结_摄像头版接入与上板验收.md) |
| **B4 OSD 做了什么、屏幕该看到什么** | [`docs/14_B4_OSD更新说明.md`](docs/14_B4_OSD更新说明.md) |
| **第一次上板 / 板子不出画面 / 报错看不懂** | [`docs/15_上板实测指南.md`](docs/15_上板实测指南.md) |
| **基础跑通了，下一步做什么**（应用路线） | [`docs/16_应用方向与开源参考.md`](docs/16_应用方向与开源参考.md) |
| **哪行能改、哪行不能改；资源不够怎么省** | [`docs/17_优化点与官方边界.md`](docs/17_优化点与官方边界.md) |
| **多人/多机怎么改不打架** | [`docs/10_协作规范.md`](docs/10_协作规范.md) |
| 算法怎么改（规格 + 调研） | [`docs/08_算法规格_P2.md`](docs/08_算法规格_P2.md)（v4 规格） · [`docs/research/README.md`](docs/research/README.md) · [`docs/research/R1_自适应阈值边缘检测.md`](docs/research/R1_自适应阈值边缘检测.md) |
| 执行路线图、分工 | [`docs/07_执行路线图.md`](docs/07_执行路线图.md) |
| 借鉴了哪些开源、差异在哪（**答辩要用**） | [`docs/05_开源调研.md`](docs/05_开源调研.md) |
| 踩过的坑 | [`docs/09_问题总结_按键无响应.md`](docs/09_问题总结_按键无响应.md) · [`memory/MEMORY.md`](memory/MEMORY.md) |
| 做什么功能、演示怎么讲 | [`docs/06_情报与呈现方案.md`](docs/06_情报与呈现方案.md) |

## 目录结构

```
docs/       文档（00 阅读指南 → 17 优化点与官方边界）+ research/ 算法调研（含 R3 参考源码，只借思路不照搬）+ archive/ 历史
memory/     进度与记忆：PROGRESS.md（阶段实测数据）、MEMORY.md（不变事实与坑）
src/        自研 RTL 工程 —— src/p1_colorbar/
sim/        仿真对照与 tb 运行目录（tb96\、work_tb\、eram_probe\；v2/v3 时代黄金模型留档在 sim\golden\）
assets/     手册截图、赛题文档图、上板录像抽帧、参考资料
tools/      辅助脚本：现行黄金模型 gen_golden_v4.py、patch_al_camera.py、check_jtag.bat（驱动/链路一键体检）、archived\（作废脚本）
```

`src/p1_colorbar/` 下：`rtl/`（9 个自研 RTL）· `tb/`（`unit/` `integration/` `gen/`）· `constraints/` · `tools/`（一键跑仿真）· `bitbank/`（**位流台账 + 里程碑位流，位流不进 git**）· `logs/` · `OUR_project/`（TD 工程，含安路官方源码）

## ⚠️ 三条重要约定

**1. 工作区约 481 MB，其中只有 97 MB 进了版本库。**

大块头都在 `.gitignore` 之外（不需要也不该进仓库）：

| 内容 | 体积 | 进仓库？ |
|---|---|---|
| `assets/ref_docs/`（赛题文档、开发板手册、第三方参考资料） | 237 MB | 部分（第三方副本排除） |
| `assets/ref_videos/` + `video_frames*/`（参考视频、上板录像抽帧） | 54 MB | ❌ |
| `src/p1_colorbar/OUR_project/`（TD 工程与综合产物） | 109 MB | 仅源码，产物排除 |
| `sim/golden/out/`（仿真对照输出，可重新生成） | 60 MB | 目前进了仓库（可优化，见下） |
| `sim/`、`docs/`、`memory/`、`tools/` | 小 | ✅ |

**历史上的教训**：曾有单个 `tb/vsim.wlf` 仿真波形长到 **26 GB**（被残留 `vsimk.exe` 占着删不掉），当时工作区 27.7 GB。`.gitignore` 就是为此设的。

**不要为了让某个产物进仓库而删 `.gitignore` 规则**——仓库会瞬间膨胀，push 必然失败。被忽略的类别：
`*.wlf` `wlft*`、`work/`、`*_Runs/`、`db/`、`incremental_db/`、`output_files/`、`simulation/`、
`*.qdb/qpg/qtl/qor/timing/timingsummary`、仿真波形、日志、**`*.bit` 等位流**。

> 💡 可优化项：`sim/golden/out/` 里 60 MB 是 v2/v3 时代 `verify_all.ps1`（已停止使用）运行写出的中间输出
> （`rtl_out.txt` 7 MB、`thr_*`/`mag_*.txt` 各 3.5 MB）。它们不是源码，加 `.gitignore` 可以瘦身——
> 但对比图 `cmp_*.png`（才 0.02 MB）值得保留。需要时再处理。

**2. 位流走 GitHub Releases，不进 git。**

`src/p1_colorbar/bitbank/` 里的 `.bit` 是"发布产物"而非源码，每个约 1.7 MB。
**判断哪个是现行版看 [`位流台账.md`](src/p1_colorbar/bitbank/位流台账.md) 的「★ 现行版本」，不要看文件名**
——同阶段的位流字节数几乎完全相同，极易搞混。

已发布 2 个 Release（含 7 个位流附件）：
[v0.1-p1-colorbar](https://github.com/wurenfu735-commits/contest-s2/releases/tag/v0.1-p1-colorbar) ·
[v0.2-a3-camera](https://github.com/wurenfu735-commits/contest-s2/releases/tag/v0.2-a3-camera)

**3. 第三方参考资料不随本仓库分发。**

`assets/ref_docs/guoyi_repo*` 是他人 2025 年国一作品的开源副本，有独立来源与许可；按 [`docs/05_开源调研.md`](docs/05_开源调研.md) 里给的 GitHub 地址自行获取即可。参考视频/音频同理。

## 红线（来自赛题规则）

- 官方例程的**算法**禁止照抄，**必须自研**（见 [`docs/07_执行路线图.md`](docs/07_执行路线图.md)）
- 外扩电路板不得含非安路 FPGA

## 协作方式

```bash
git clone https://github.com/wurenfu735-commits/contest-s2.git   # 私有库，需有权限的账号
cd contest_s2
```

**动手改之前先拉，改完立刻推** —— 这个工程同时有多台机器、多个会话在改，Git 不会自动同步：

```bash
git pull --rebase
# ...改代码、写文档...
git add -A && git commit -m "说明" && git push
```

完整规范（含 Windows 上 TLS 报错的处理、行尾约定、位流发版流程）见
**[`docs/10_协作规范.md`](docs/10_协作规范.md)**。

进度更新直接改 `memory/PROGRESS.md`（按阶段追加实测数据，注明日期）。这样任何人都能靠 `git log` 和 `PROGRESS.md` 看出「做到哪、下一步、卡在哪」。
