# 测试台（tb）对照表

> 分三类：`unit\` 模块级、`integration\` 集成级、`gen\` 脚本自动生成（**不要手改，可随时删**）。
> 一键跑法：`pwsh -File ..\..\..\tools\run_tb.ps1 -Tb <tb名>`

## unit\ —— 模块级单测

| tb | 测什么 | 判据 | 备注 |
|---|---|---|---|
| `tb_edge_adaptive_pixel.v` | **算法核心**：与 Python 黄金模型逐像素比对 | edge 与 mag 均 **0 误差** | 由 `sim\golden\verify_all.ps1` 驱动（需向量文件，见下） |
| `tb_debounce_real.v` | 按键消抖（**真实 74.25MHz 参数**） | idle=0 / pressed=1 / released=1 / again=2 | 关键：用真实参数，否则会掩盖位宽 bug |
| `tb_debounce.v` | 同上（1kHz 快仿参数） | 同上 | ⚠️ 参数简化，**不能作为位宽依据** |
| `tb_ptn.v` | 测试图案发生器（坐标 → 颜色 → 状态带） | 各图案在指定坐标的颜色正确 | |

## integration\ —— 集成级

| tb | 测什么 | 判据 |
|---|---|---|
| `tb_lowcontrast_demo.v` | **端到端**：TPG 低对比度图案 → 四态适配器 | mag max=48；官方判决 **0** 边缘、我们 **>0** |
| `tb_edge_rgb_adapter.v` | 四态切换（原图 / 官方 / 我们 / 分屏） | mode1=0 边缘 / mode2>0 / mode3 左0右>0 | 

## gen\ —— 脚本自动生成（不要手改）

由 `sim\golden\verify_all.ps1` 每次运行时，从 `unit\tb_edge_adaptive_pixel.v` 复制并替换
（`IMG_W`/`IMG_H` 参数 + 向量文件名）而来。**可随时删除**，下次验证会自动重建。

## 验证体系入口（在 `sim\golden\`）

| 脚本 | 用途 | 用法 |
|---|---|---|
| `verify_all.ps1` | **一键四图逐像素验证**（edge + mag 双指标），自动生成 `gen\` 下的 tb | `pwsh -File verify_all.ps1 -W 1280 -H 720` |
| `compare_official.py` | 官方固定阈值 vs 我们自适应 的**效果对比实验** | `python compare_official.py` |
| `edge_adaptive.py` | Python 黄金模型（与 RTL 严格同序，可导出 `gray/edge/mag/thr` 四组向量） | `python edge_adaptive.py --all --w 1280 --h 720` |

## 跑算法验证的完整步骤

```powershell
# 1) 生成向量（写入 sim\golden\out\）
python sim\golden\edge_adaptive.py --all --w 1280 --h 720
# 2) 一键验证（自动生成 tb、编译、仿真、逐像素比对）
pwsh -File sim\golden\verify_all.ps1 -W 1280 -H 720
```

> ⚠️ **判据必须用 1280×720**：小尺寸（如 64×32）下边界效应占比过大，会出现假误差。
