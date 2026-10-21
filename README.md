# 基于安路 PH1P35 的实时图像显示（极简基线）

> 全国大学生嵌入式芯片与系统设计竞赛 '2026 · FPGA 创新设计赛道 · 选题二
> 平台：**安路 HX1P35A**（PH1P35MDG324-3）· 摄像头 SC520（MIPI 2-Lane RAW10）· 显示 HDMI 1280×720@60
>
> **2026-10-21 重构为极简基线**：只保留「原图实时显示 + 自研 OSD」，剔除全部图像算法与按键切换。

## 一句话

摄像头 → FPGA（官方 ISP 去马赛克+白平衡 + **自研 OSD 叠加安路 Logo**）→ HDMI 实时输出。

## 一、当前能实现什么

| 项 | 状态 |
|---|---|
| **原图实时显示**（SC520 → MIPI → ISP → DDR → HDMI 720p60 彩色画面） | ✅ 已编译验证 |
| **自研 OSD 叠加**（左上 208×156 面板 + 146×94 安路双色 Logo + `ANLOGIC`/`PH1P35 720P` 两行文字） | ✅ 已编译验证 |
| 边缘检测 / 形态学梯度 / 卡通化 / 按键多模式切换 | ❌ **已剔除**（恢复见第五节） |

## 二、实测数据（2026-10-21 编译）

| 资源（P&R） | 值 |
|---|---|
| Slice | **12,943 / 21,216 = 61.01%** |
| LUT6 | 10,624（50.08%） |
| Slice reg | 13,368（31.50%） |
| ERAM | 39 / 108（36.11%） |
| DSP | 8 / 40（20.00%） |
| **Setup WNS** | **+0.593 ns** |
| **Hold WNS** | **+0.020 ns** |
| 违例 | **0** |

> 对比含算法的旧版（slice 74.40%）：极简版省 **13.4 个百分点 slice**，时序余量更健康。

## 三、关键文件

```
src/p1_colorbar/
├── rtl/                         自研 RTL（只剩 3 个）
│   ├── mixer_lite.v             轻量像素混合器（替代官方 hdmi_mixer，省 ~2,100 slice）
│   ├── osd_overlay.v            自研 OSD 叠加（面板 + Logo + 文字）
│   └── osd_logo_rom.v           安路 Logo 位图 ROM（146×94，2bit/像素，官方素材重编码）
├── OUR_project/hdmi_base_src/
│   ├── td_project/
│   │   ├── OUR_p1_colorbar.al   TD 工程文件
│   │   └── OUR_p1_colorbar.sdc  主时序约束
│   └── user_source/             官方源码（ISP/MIPI/DDR/HDMI/摄像头配置）
├── bitbank/
│   ├── 位流台账.md              ★ 现行位流（看这个）
│   └── OUR_baseline_orig_osd.bit  现行位流
└── tb/unit/tb_osd_overlay.v     OSD 仿真 tb（唯一保留的 tb）
```

## 四、编译方式（本机实测有效）

TD 6.2.1（6.2.168116）。**命令行 `launch_runs` 在本机不可靠（会假成功），用 `DefaultFlow.tcl`**：

```bash
# 1) 综合：在 syn_1 目录跑
cd src/p1_colorbar/OUR_project/hdmi_base_src/td_project/OUR_p1_colorbar_Runs/syn_1
td_commands_prompt.exe <TD安装>/doc/scripts/DefaultFlow.tcl

# 2) 布局布线 + bitgen：在 phy_1 目录跑
cd ../phy_1
td_commands_prompt.exe <TD安装>/doc/scripts/DefaultFlow.tcl
```

**三个坑**（实测）：
1. `launch_runs` 报 `PRJ-1410 Run success` 但 `run.exe` 没跑（假成功）→ 用 `DefaultFlow.tcl` 同步流程。
2. `open_project` 生成的 `settings.cfg` 里 `device_name`/`package_name` 为空 → 手动补 `ph1_35p.db` / `PH1P35MDG324`。
3. `phy_1` 目录需要从 `syn_1` 复制 `.prj`，否则 `open_project -noanalyze` 失败。

> 首次编译前若 `OUR_p1_colorbar_Runs/` 不存在，先用 `open_project OUR_p1_colorbar.al` 生成工程分析（`.prj` + `settings.cfg`）。

## 五、如何加回算法（从历史恢复）

本仓库的 git 历史包含完整多算法版：
- `edge_adaptive_96.v`（自适应阈值边缘检测）
- `morph_grad_96.v`（形态学梯度）
- `cartoon_96.v`（卡通化）
- `mode_ctl.v` + `cdc_mode_sync.v`（按键五态切换）
- `perf_counter.v`（帧率/延迟）

恢复方式：从 git 历史取回对应 RTL + 旧版 `isp_top.v`/`design_top_wrapper.v`，并在 `.al` 重新加入 File 块。

## 六、文档

| 文件 | 内容 |
|---|---|
| [`memory/MEMORY.md`](memory/MEMORY.md) | 不变事实 + 踩坑清单（TD/仿真/环境） |
| [`memory/PROGRESS.md`](memory/PROGRESS.md) | 各阶段实测数据 |
| [`需求文档.md`](需求文档.md) | 硬件边界（资源/引脚/时钟域） |
| [`docs/操作手册.md`](docs/操作手册.md) | 编译/烧写/上板/排错 |
| [`docs/答辩与合规.md`](docs/答辩与合规.md) | 自研 vs 复用边界、合规自检 |
| [`docs/01_赛题解读.md`](docs/01_赛题解读.md) | 赛题要求与评分 |
| [`src/p1_colorbar/bitbank/位流台账.md`](src/p1_colorbar/bitbank/位流台账.md) | **现行位流** |

> `docs/` 下还有 `PLAN.md`、`算法规格.md`、`research/`（旧算法规划与调研），保留仅作历史参考。

## 七、红线（赛题规则）

- 官方例程的**算法**禁止照抄；本极简版不含自研算法，仅原图直通 + 自研 OSD
- 外扩电路板不得含非安路 FPGA
- 必须使用 TD 6.2.1
