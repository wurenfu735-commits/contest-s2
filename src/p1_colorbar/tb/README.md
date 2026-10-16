# 测试台（tb）对照表

> 分三类：`unit\` 模块级、`integration\` 集成级、`gen\` 脚本自动生成（**不要手改，可随时删**）。
> 一键跑法：`pwsh -File ..\tools\run_tb.ps1 -Tb <tb名>`（run_tb.ps1 在本目录上一层 `src\p1_colorbar\tools\`）。

## unit\ —— 模块级单测

| tb | 测什么 | 判据 | 备注 |
|---|---|---|---|
| `tb_edge_adaptive_96.v` | **96bit 并行版主验证入口（v4）**：RTL vs Python 黄金模型逐像素比对 | **PASS = 0 误差** | 由 `tools\run_tb_96.ps1` 一键驱动（内部自动调 `tools\gen_golden_v4.py`）；图案 W=128、H=12、**±3 确定性噪声**、THR_FLOOR=96、I_k=2、I_mode=2 |
| `tb_edge_adaptive_pixel.v` | 逐像素版：与 Python 黄金模型逐像素比对 | edge 与 mag 均 **0 误差**（v2/v3 时代成绩） | **开发期参照（v2 形态：逐像素、3×3 均值），不与 v4 常量比对；现行主验证用 96 版** |
| `tb_debounce_real.v` | 按键消抖（**真实 74.25MHz 参数**） | idle=0 / pressed=1 / released=1 / again=2 | 关键：用真实参数，否则会掩盖位宽 bug |
| `tb_debounce.v` | 同上（1kHz 快仿参数） | 同上 | ⚠️ 参数简化，**不能作为位宽依据** |
| `tb_ptn.v` | 测试图案发生器（坐标 → 颜色 → 状态带） | 各图案在指定坐标的颜色正确 | |

## integration\ —— 集成级

| tb | 测什么 | 判据 |
|---|---|---|
| `tb_lowcontrast_demo.v` | **端到端**：TPG 低对比度图案 → 四态适配器 | mag max=48；官方判决 **0** 边缘、我们 **>0** |
| `tb_edge_rgb_adapter.v` | 四态切换（原图 / 官方 / 我们 / 分屏） | mode1=0 边缘 / mode2>0 / mode3 左0右>0 |

> 上述两条集成 tb 覆盖的是 **A2 TPG 通路**（例化逐像素参照版）；A2 位流已过时（内含 v1 算法），待用 v4 算法重新综合。

## gen\ —— 脚本自动生成（不要手改）

`tb_run*.v` 由 v2/v3 时代的 `sim\golden\verify_all.ps1`（**已停止使用**）从 `unit\tb_edge_adaptive_pixel.v` 复制替换参数生成。
现行验证流程（`run_tb_96.ps1`）**不再重建 `gen\`**；这批文件是历史遗留，**可随时删除**。

## 验证体系入口（现行）

| 脚本 | 用途 | 用法 |
|---|---|---|
| `..\..\..\tools\gen_golden_v4.py` | **现行黄金模型（v4 分段 FLOOR）**，与 RTL 同锚点/同屏蔽/同迟滞顺序；附带场景A噪声指标、场景B低对比指标 | 由 run_tb_96.ps1 自动调用，也可单独 `python gen_golden_v4.py` |
| `..\tools\run_tb_96.ps1` | **一键**：编译 → 仿真 → 生成 golden → 逐像素比对（含"编译/加载失败即中止"检查） | 在仓根执行：`pwsh -File src\p1_colorbar\tools\run_tb_96.ps1` |

> 旧体系（`sim\golden\` 下的 `verify_all.ps1`、`edge_adaptive.py` 等，v2/v3 时代 · 3×3 Sobel）**已停止使用，仅留档**；
> 其中 `ph1p_eram_sim_model.v` 仍被现行 run_tb_96.ps1 复用（行缓存 ERAM 的仿真模型）。v2/v3 黄金模型归档于 `tools\archived\`。

## 跑算法验证的完整步骤

```powershell
# 在仓库根 E:\fpga\contest_s2 下，一条命令跑完：
pwsh -File src\p1_colorbar\tools\run_tb_96.ps1
# 输出最后一行：结果：PASS（并行版与黄金模型逐像素完全一致）= 0 误差
```

> ⚠️ **判据**：PASS = 比对区（行 8..11、列 12..115）**0 误差**；任何一步编译失败/加载失败脚本都会中止，不会出"假 PASS"。