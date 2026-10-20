# 构建与验证结果

日期：2026-10-19。状态：**已生成可供上板验证的位流；尚未进行本版本的硬件实测。**

## 交付文件

- 位流：`bitbank/OUR_K1_4mode.bit`，1,789,539 字节。
- SHA256：`77eb5aed937120ce5825b20662aade9d0a9484eb19bb79964bd517ec642e29e3`
- 工程：`OUR_project/hdmi_base_src/td_project/OUR_K1_4mode.al`
- 工具：Tang Dynasty 6.2.168116；器件 PH1P35MDG324，速度等级 -3。
- 原工作目录未修改；原 `OUR_b4osd_v5_darkfloor.bit` MD5 仍为 `8c1a75f720d2885fa22e4b6d10bab15a`。
- 完整源码/IP 文件哈希与位流 MD5 见 `MANIFEST.json`。
- 最终交付审计通过：180 个源码/IP 文件哈希、工程全部路径、位流 SHA256、布线报告与四组测试日志已核对，见 `sim/delivery_check.log`。
- TD 已实际打开交付 `.al` 并返回 `PROJECT_OK`，见 `sim/project_check.log`。

## 功能

上电原图；板载 KEY1/D5 单次按下依次选择原图、灰度、3×3 灰度中值、去噪后自适应阈值 Sobel。20 ms 消抖，长按不重复，松开重新使能。四种模式使用相同延迟，帧边界切换。原安路 Logo、OSD 计数、SC520 配置、DDR 和 HDMI 核保留。

## 验证证据

| 测试 | 结果 | 日志 |
|---|---|---|
| 4 个模式，各 1280×720；Python 独立黄金模型与 RTL 对照 | 921,600 组、3,686,400 像素全部一致 | `sim/eram_full/verification.log` |
| 有效信号间断、行边界、连续帧、帧内模式请求 | 包含于上述全帧测试，通过 | 同上 |
| 真实 50 MHz / 20 ms 按键，含抖动、长按、松开、四次循环 | 通过 | `sim/key_verification.log` |
| RGB 三原色权重与 0/1/254/255 端点 | 通过 | `sim/rgb_verification.log` |
| 模拟 AWB 提前 SOF、真实 ISP 适配连接、96→128 字节封包 | 1,920 个输出字全部一致；DDR 复位提前量检查通过 | `sim/adapter_verification.log` |
| TD 综合、布局布线、bitgen | 两阶段均 `FLOW_OK` | `sim/build_syn_1.log`、`sim/build_phy_1.log` |

仿真中的 ERAM 使用项目原有行为模型，不是器件后仿。接口测试通过隔离 AWB 输出验证适配器，不代表已模拟完整加密 MIPI、DDR、HDMI PHY。生成的海量输入/期望数据已删除，可通过 `tools/verify.ps1 -Full` 重建。

## 最终布线时序

来源：`OUR_project/hdmi_base_src/td_project/OUR_K1_4mode_Runs/phy_1/OUR_K1_4mode_pr.timing`，**Confidence: Routed**，Slow/Fast 两个角均检查。

| 指标 | 结果 |
|---|---:|
| Setup WNS / TNS | +0.112 ns / 0.000 ns |
| Hold WNS / TNS | +0.020 ns / 0.000 ns |
| STA coverage | 95.30% |
| MIPI 算法域，103.520 MHz | Setup +0.126 ns，Hold +0.020 ns |
| HDMI 像素域，75.002 MHz | Setup +0.112 ns，Hold +0.020 ns |
| DDR 用户域，66.667 MHz | Setup +2.091 ns，Hold +0.020 ns |

以上结论针对工具已约束和分析的路径，不把 STA coverage 描述为 100%。恢复了 SC520 官方 MIPI 输入时钟及派生字节时钟约束、时钟组关系。命令行构建通过 `settings.cfg` 加载本 SDC；交付 `.al` 也已登记同一 SDC，并启用默认综合流程，供 GUI 使用。

## 最终资源

来源：`.../OUR_K1_4mode_Runs/phy_1/OUR_K1_4mode_phy.area`。

| 资源 | 占用 |
|---|---:|
| Slice | 17,367 / 21,216（81.86%） |
| LUT6 | 15,457 / 21,216（72.86%） |
| Slice 寄存器 | 16,848 / 42,432（39.71%） |
| ERAM20K | 51 / 108（47.22%） |
| DSP | 21 / 40（52.50%） |

新窗口明确实例化安路 ERAM，两个窗口合计 6 个 512×32 行 RAM 宏。完整设计还包含官方 ISP、DDR、HDMI、OSD 的资源。

## 上板待确认

1. 四态顺序和 K1 单次触发；原图颜色与灰度中性；Logo/OSD 在四态持续显示。
2. 相同光照与场景下，中值和边缘模式的暗部雪花改善程度，以及弱边缘是否保留。
3. 30 分钟连续运行、明暗切换时有无闪黑、撕裂、缓存异常。

新边缘阈值为初始参数，没有真实摄像头采样数据足以证明所有场景雪花已消除。HDMI 加密核的 AVI 量化声明未暴露，实际显示器黑白电平仍需对照；内部 RGB888 和灰度按全范围 0–255 处理，详见 README。
