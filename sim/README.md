# sim\ —— 仿真与验证分区导读

## 这个目录是什么

验证的**运行目录与留档区**：黄金模型会把期望结果写到这里、ModelSim 在这里编译仿真、旧时代的验证脚本在这里留档。
**注意**：现行黄金模型脚本不在本目录，而在仓库根的 `tools\gen_golden_v4.py`（生成结果写到 `sim\tb96\`）。

## 有什么

| 路径 | 是什么 | 可再生？ |
|---|---|---|
| `tb96\` | `tb_edge_adaptive_96` 的运行目录：`golden_out.txt`（黄金模型期望）、`par_out.txt`/`seq_out.txt`（RTL 输出）、`work\`（ModelSim 工作库） | ✅ 每次 `run_tb_96.ps1` 重写 |
| `golden\` | **v2/v3 时代**的黄金模型与一键脚本（`edge_adaptive.py`、`verify_all.ps1`、`compare_official.py`、`out\` 对照输出），**已退出现行一键验证链路（留档）**；其中 `ph1p_eram_sim_model.v`（行缓存 ERAM 的仿真模型）仍被现行流程复用 | ❌ 脚本留档勿动（`edge_adaptive.py` 可作参数试跑/图案对照）；`out\` 可删 |
| `eram_probe\` | ERAM 探针小工程（排查行缓存行为用） | 手工维护 |
| `work_tb\` | 旧 tb 的 ModelSim 运行目录 | 残留，可清 |

## 怎么用

1. **现行算法验证只有一条命令**（在仓库根执行）：
   `pwsh -File src\p1_colorbar\tools\run_tb_96.ps1` → 最后一行 `PASS` = RTL 与 v4 黄金模型逐像素 **0 误差**。
2. 黄金模型改 `tools\gen_golden_v4.py`，不要改 `sim\golden\` 下的旧脚本（它们认 v2/v3 的旧算法，与新 RTL 不对标）。
3. 三个目录里的 `work\`、`out\`、`*.txt` 全是运行产物，**可随时再生成或删除**（删除后重跑脚本即重建）。