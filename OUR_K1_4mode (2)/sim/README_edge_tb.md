# 边缘检测测试台（2026-10-20 新增）

配合 `../rtl/image_modes4.v` 的边缘检测链路仿真验证。链路：
`灰度化 luma → stretch(gamma0.35) → 中值 → Sobel → 固定阈值 → 软腐蚀 → 输出`。

## 测试台清单

| 文件 | 验证内容 | 状态 |
|------|---------|------|
| `tb_edge3_noise.v` | 椒盐噪声：中值+软腐蚀压噪、边缘保留 | ✅ PASS |
| `tb_edge4_adaptive.v` | 暗光弱边：固定阈值检出弱边、平区干净 | ✅ PASS |
| `tb_mode2.v` | mode2 边缘强度灰度图输出 | ✅ PASS |
| `tb_dark_lp.v` | **真实暗场景**：灰度1背景+6字符+椒盐，字符边缘检出、噪点压住 | ✅ PASS（最接近实际）|
| `tb_stretch.v` | stretch() 对比度拉伸函数映射验证 | ✅ PASS |
| `ph1p_stub.v` | PH1P_LOGIC_ERAM 行为级桩件（ModelSim 用，含 initial 复位）| 仿真依赖 |

## 批量仿真命令（ModelSim）

```bash
export PATH="/e/app/Software/work/modelsim/win64:$PATH"
vlib work
vlog -work work ../rtl/window4.v ph1p_stub.v ../rtl/image_modes4.v tb_dark_lp.v
vsim -c -do "run -all; quit -f" work.tb_dark_lp
```

> 注：`tb_image_modes4.v`（旧 LPR 时代）引用已删除信号，勿用。当前有效 tb 以上表为准。
