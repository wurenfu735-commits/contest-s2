# 项目进度 — PROGRESS.md

> 每个阶段完成时的实测数据与决策记录。权威数据以 TD 报告文件为准。

## P0 · SC520 基线（2026-10-14 达成 ✅）

### 里程碑
- SC520 版 `lab_ex1_mipi_hdmi_SC520` 编译成功（TD 6.2.1，器件 PH1P35MDG324-3，2026-10-14 15:51 日志 + 15:56 时序报告）
- 烧写成功，HDMI 出实时画面（用户实测：实时跟随、无撕裂/闪烁/花屏）
- 数据来源（实测文件）：
  - 资源：`td_project\camera_to_dsi_display_Runs\phy_1\camera_to_dsi_display_phy.area`
  - 时序：`td_project\camera_to_dsi_display_Runs\phy_1\final_timing.rpt` / `route.qor`

### 基线资源占用（★后续自研的对比基准）

| 资源 | 使用 | 总量 | 占比 |
|---|---|---|---|
| LUT6 | 10,002 | 21,216 | 47.14% |
| Slice | 12,390 | 21,216 | **58.40%** |
| Slice reg (DFF) | 13,396 | 42,432 | 31.57% |
| ERAM20K | 39 | 108 | 36.11% |
| DSP | 8 | 40 | 20.00% |
| PLL | 3 | 6 | 50% |
| GCLK | 9 | 32 | 28% |
| MIPI RX | 1 | 2 | 50% |
| DDR byte | 6 | 12 | 50% |
| IO | 58 | 160 | 36% |

**留给自研算法的预算**：slice 余 ≈41.6%、ERAM 余 ≈63.9%、DSP 余 80%。

### 时序（无违规 ✅）
- SWNS = +1.242ns，STNS = 0；HWNS = +0.020ns，HTNS = 0；违反端点 0。
- 关键时钟：MIPI_RX_BYTE_CLK=103.52MHz（=828Mbps/8，与 SC520 寄存器注释一致）、HDMI_PIXEL_CLK=75MHz、HDMI_SERIAL_CLK=375MHz、DDR usr_clk=66.67MHz、pll_clk_24m=23.81MHz。

### 层次资源（决定自研算法该插哪、有多狠）
| 模块 | logic LUT | ripple(加法器链) | FF | ERAM | DSP |
|---|---|---|---|---|---|
| u_isp_top（ISP 总） | 2,531 | 2,626 | 7,492 | 22 | 8 |
| ├ u_awb（白平衡） | 1,642 | 2,292 | 6,059 | 10 | 8 |
| │  └ 2 个 32bit divider IP | 736+730 | 1084+1084 | 2781+2720 | 0 | 0 |
| u_ph1p35_324_ddr_wrapper（DDR 控制器） | 2,576 | 111 | 3,454 | 0(dram296) | 0 |
| u_hdmi_tx | 611 | 28 | 1,227 | 5 | 0 |
| uicfgcs520（SC520 配置） | 205 | 17 | 136 | 0 | 0 |
| u_video_in/out | 278 | 80 | 331 | 8 | 0 |

### 关键洞察（答辩素材）
1. **例程的 8 个 DSP 全在 AWB 的除法器里**，且两个 32-bit divider 吃掉 1084×2 个加法器链——除法的 FPGA 成本极高。我们自研边缘检测用**移位近似均值（不用除法）**，天然形成"资源优化"对比。
2. 算法插入点（例程 2 结构）：`isp_top` 内 `awb` 与 `data_96bit_to_128bit` 之间，96bit 流接口。
3. SC520 例程时钟架构与 SC500 版不同：SC520 版走 MIPI_RX_BYTE_CLK=103.52M（SC500 版是 112.5M），DDR usr_clk=66.67M（SC500 版 132.8M）。

## "像素不高"结论
- 例程输出 = 1280×720@60（720p），这是赛题基础分辨率，**符合提交要求**，不是缺陷。
- 观感模糊的原因：便携显示器多半是 1080p 及以上屏，**720p 信号被屏幕放大** → 颗粒感。换 1080p 模式或大屏更明显。
- 提升路径（可选，属扩展/进阶加分）：
  a. 例程带现成更高模式 .bit：`best_result\camera_to_dsi_display_1792x1080_normal.bit`、`..._1600x900_30fps.bit`；
  b. SC520 满分辨率寄存器表 `uics520reg_full_2560x1920_30.v`（2560×1920@30，需配套 HDMI 时序）；
  c. 上"自动曝光/白平衡/均衡"ISP 优化（官方进阶加分项(5)）。

## P0 收尾状态
- [x] 编译烧写出画面；[x] 画面实时、无花屏；[x] 资源/时序基线入库
- [ ] （可选）连续 10 分钟以上静置观察 → 补一条稳定性记录

---

## 插曲：lab_ex2（SC520 边缘检测例程）两 bit 无摄像头烧录现象分析（2026-10-14）

- 用户烧的：`lab_ex2_edge_SC520\lab_ex2_edge\td_project\camera_to_dsi_display_Runs\best_result\` 下两个 bit：
  - `camera_to_dsi_display.bit`（完整码流）→ 实测"白屏 + 黑颗粒"
  - `camera_to_dsi_display_compress.bit`（压缩码流）→ 实测"纯白屏"
- 日志证据：`readMe.txt`＝"The implemented result of phy_1 is saved as best result"；最新 `td_2026-10-14_16-10-54.log` 内 `RUN-1002 start command "save_best_bits"`。
- **成因（已读 `isp/edge_detect_96.v` 源码确认）**：lab_ex2 = 边缘检测，输出极性 **edge=0xFFFFFF(白)/非edge=0x000000(黑)**，阈值 `EDGE_TH=80`。无摄像头时 MIPI 无有效帧 → ISP 输出噪声/平场数据 → Sobel 对强噪声处处 |Gx|+|Gy|≥80 → 整屏判"边缘=白"、低噪声处黑 → 白底黑颗粒；输入为平场时 → 纯黑或纯白平场。
- 结论：**两个现象都不是故障，是"边缘检测 + 无有效输入"的预期表现**。插上 SC520 摄像头重烧 `camera_to_dsi_display.bit` 应看到黑底白线的实时边缘图。
- `edge_detect_96.v` 关键参数（P2 自研算法"必须不同"的对照基准）：
  - 灰度近似 `R/4+G/2+B/4`（无乘法器，max=253）；4 像素合成 2 个 pair → 水平 640 样本
  - 2 行 block RAM 行缓存（320×16bit）；Sobel＝|Gx|+|Gy|；固定阈值 80；多数表决
  - 掩首 2 行 + 行首 group（window_valid）；tvalid/tlast/tuser 原位打拍
- 方法论教训（再次验证方案里的一句话）：**"画面能动"≠"功能正确"**——lab_ex2 无输入时画面照样"动"（颗粒），所以自研算法必须用已知彩条输入做逐像素比对验证。

---

## 官方例程全跑通清单（执行进度，2026-10-14）

| # | 例程/bit | 摄像头 | 预期 | 状态 |
|---|---|---|---|---|
| 0 | lab_ex1 `camera_to_dsi_display_1280x720_60fps.bit` | 插 | 彩色实时画面 720p60 | ✅ 已跑通（P0） |
| 1 | lab_ex1 `..._1280x720_75M_HDMI_COLORBAR_TEST.bit` | 不插 | 720p 八彩条 | ✅ 已跑通（用户照片确认：竖条彩带，颜色正常、画面稳） |
| 2 | lab_ex1 `1792x1080_normal.bit` | 插 | 高分辨率画面（对比像素观感） | ⚠️ 已试：显示器报"输入不支持"（本地屏支持列表缺少此非标准分辨率），**非链路故障** |
| 3 | lab_ex2 `camera_to_dsi_display.bit` | 插 | 黑底白线实时边缘图 | ✅ 已跑通（用户视频确认：白线实时跟随物体转动，即 Sobel 边缘检测正常） |
| 4 | lab_ex3 `camera_to_dsi_display.bit` | 插 | 实时画面+安路Logo+计数器 | ✅ 已跑通（照片证实：左上角安路Logo+文字"安路 CNT:00 1245"计数器在跑，背景实时画面） |

- **第 1 步意义（重要）**：不插摄像头也能出彩条 = **显示半条链（VTC 时序 + DDR 帧缓存 + HDMI 发送）独立验证通过**。这就是 P1"无摄像头地基"的能力证明，官方连测试 bit 都做好了——P1 自研时我们用 `colorbar_top` 复刻这一能力并加"通链自检显示"。
- **1792×1080 "输入不支持"结论**：1792×1080 是非标准分辨率（不在常见 EDID 支持列表），用户显示器（障碍约 1280×800 档便携屏）拒绝该时序；FPGA 输出本身没有问题。后续高分辨率验证建议换标准分辨率（`1600x900_30fps.bit`，VESA 标准，scaler 屏通常认）。比赛主线仍是 720p60。
- 待 P1 自研时确认：这个 COLORBAR_TEST bit 的彩条源在链路哪一层（HDMI-core TPG 直出 vs 视频通路注入）。

---

## P1 动工记录（2026-10-14 晚）

### 彩条源定位结论（已读源码实锤）
- 官方 `hdmi_1_4b_transmitter_core_wrapper.enc` 参数 **`VIDEO_TPG = "Disable"`**——官方 COLORBAR/TPG 各 bit = 把该参数设为 Enable（图案与 720p 时序在**加密 IP 核内**）。另有注释掉的 1080p `video_source_test` 例化（HDMI IP 前注入）。
- `hdmi_tx.v` 端口实锤：支持 **RGB 时序接口**（`I_video_rgb_enable=1`，de/vs/data 直连，user/valid/last 可接 0）+ AXI-Stream 接口；`O_screen_pwm=1'b1`；UI 音 DDC/音频为 0/悬空。
- 720p 官方参数（wrapper 内）：HTOTAL=1650/HSA=40/HFP=110/HBP=220/HACTIVE=1280；VTOTAL=750/VSA=5/VFP=5/VBP=20/VACTIVE=720；pixel clk=74.25M、serial=371.25M。
- PLL 例化端口：refclk/reset/clk0_out(100M)/clk1_out(24M)/clk4_out(74.25M)/clk5_out(371.25M)/lock。

### P1 v1 交付（全落 `E:\fpga\contest_s2\src\p1_colorbar\`）
- rtl：`colorbar_top.v`（顶层）/`vtc_720p.v`/`test_pattern_gen.v`（四图案+状态带）/`debounce_btn.v`
- constraints：`colorbar_top.adc`（照官方 pin.adc 相关行）；tb：`tb_ptn.v`（自检五要素：总量/规律/边界/状态带/负向，ModelSim 可直跑）
- doc：`docs\archive\P1_工程搭建与烧写步骤.md`（复制官方工程建 TD 副本 + 增删 + 编译烧写；**现行速查见 `docs\03_编译烧写速查.md`**）
- 修过的 bug：test_pattern_gen 初版 col=I_hcnt[10:8]（256 宽分列）是错的，已改 `(I_hcnt>=1120)?7:I_hcnt[10:7]`（160 宽 8 分列）。
- v2 待办：走 DDR 帧缓存（TPG→video_in→video_out→hdmi_tx），状态带加 DDR ready/帧计数。

### 自检三查（P1 v1 交付时）
1. 目标查：对应 B1/B3 的"显示链独立可验证"地基 + 上板自检可视化（自主创意）✅
2. 红线查：VTC/TPG 纯自写，非例程算法；复用 hdmi_tx 属官方基础通路（不涉算法红线）；TD 6.2.1 ✅
3. 路线查：文件在 contest_s2 结构内；GitHub 借鉴已声明（07 文档）；时间在预算内 ✅

### tb 仿真排错三连（教训，写 tb 必看）
1. **SV 语法**：longint/数字位选/块内声明赋初值/%0s 在 ModelSim 10.5 vlog 全报错（MEMORY 第五节 11 条）。
2. **坐标两类**：hcnt/vcnt 是整幅时序计数，图案分列要先减 260/25 换算画面坐标；彩条 160 列/段用比较链，hcnt[10:7](128/段) 是错的（MEMORY 第五节 12 条）。
3. **并行块竞争**：多个 initial 块共享 psel 时，棋盘块切图案会把并行的彩条块采样拍成棋盘色（现象：同一坐标既 ERROR 又 OK）。→ tb 统一改为**单 initial 顺序执行 + 图案显式切换 + 先对齐行再对齐列**，probe 用"当前行内对齐列 + 4 拍窗口找期望值"。

### P1 v1 TD 编译资源实测（2026-10-14，Report Model = colorbar_top ✅）
数据来源：`OUR_project\hdmi_base_src\td_project\OUR_p1_colorbar_Runs\phy_1\camera_to_dsi_display_phy.area` + `route.qor`

| 资源 | P1 v1 实测 | 占器件 | 官方 lab_ex1 基线 | 对比 |
|---|---|---|---|---|
| Slice | **967** | **4.56%** | 12390（58.40%） | 约 1/12.8 |
| LUT6 | 751 | 3.54% | 10002（47.14%） | 约 1/13.3 |
| DFF（slice reg） | 1258 | 2.96% | 13396（31.57%） | 约 1/10.6 |
| ERAM20K | 5 | 4.63% | 39（36.11%） | 约 1/7.8 |
| **DSP** | **0** | **0%** | 8（20%） | 零 DSP |
| PLL / GCLK | 1 / 3 | 16.7% / 9.4% | 3 / 9 | — |
| IO | 9 | 5.62% | 58 | 无摄像头/MIPI/DDR 脚 |
| 布线长度 | 235,296 | — | 2,771,104 | 约 1/11.8 |

**时序（route.qor，无违规 ✅）**：Setup WNS = **14.11ns**（余量极大）、Setup TNS 0、Hold WNS 26ps、违反端点 0。

**正确口径（答辩用，勿夸大）**：v1 只含"显示链地基"（自研 VTC+TPG+消抖 + 复用官方 hdmi_tx/PLL），**不含 MIPI/DDR/ISP 与算法**，因此与官方全链路基线不可直接等价对比。可讲的结论是：**自研显示地基只占 4.56% 资源、零 DSP、时序余量 14.11ns → 为 P2 算法留出了 >95% 的资源空间**。

**里程碑状态**：P1 v1 bit 已生成并归档为 `src\p1_colorbar\bitbank\OUR_p1_colorbar_v1_20261014.bit`（1,789,533 字节，2026-10-14 19:18）。

### ✅ P1 v1 上板验证通过（2026-10-14 20:xx，用户录像 + AI 抽帧判读）
- 用户录了 6.46s/1280×720/30fps 上板视频；本机 ffmpeg（winget 装的 Gyan.FFmpeg 9.0.2）抽帧到 `assets\video_frames\`，AI 用读图能力直接判读画面。
- **实测结果**：屏幕显示**八色竖彩条**，顺序 白→黄→青→绿→品红→红→蓝→黑，与 `test_pattern_gen.v` 设计**完全一致**；**画面最底部一条绿色横带** = 状态带下半段（PLL 已锁定，绿）✅。
- 结论：**自研 VTC(720p) + 四图案测试图 + 状态带 全链路在真实硬件上工作**；无摄像头出图能力 = 显示半条链独立验证完成（对应 B1/B3 地基 + 自主创意"上板自检可视化"）。
- ⚠️ **发现的易用性问题（v2 修）**：`I_button` 约束在**扩展口 N2/J14**（照抄官方 pin.adc），板载 KEY1~4（D5/A9/B9/C7）**按不到** → 录像里没能演示按键切图案。v2 应把按键改到**板载 KEY1/KEY2（D5/A9）**，这样手指直接按板子即可切换。
- 待现场确认的小项：状态带**上半段**（图案指示色，应随图案变白/黄/青/品）在视频里不明显，可能是便携屏 overscan 裁切或相机曝光，现场肉眼再看一次即知。

### 🔧 新增能力：AI 可自主"看视频"
本机装好 ffmpeg 后，AI 可自行 `ffmpeg 抽帧 → read_image 看画面`，用于分析上板录像/示波器截图等（无需人工转述）。
另探测到 DSH 本地 QWEN key 可用：文本 `qwen-plus`/`qwen-max` OK，视觉 `qwen3-vl-plus` OK（`qwen-vl-max`/`qwen-vl-plus` 404/403 不可用）。

### 插件与 AI 能力线收尾（2026-10-14 晚）
- 环境：ffmpeg 9.0.2（winget Gyan.FFmpeg）；Python 依赖 faster-whisper 1.2.1 / opencv / PyAV 19 / xxhash / pandas / yt-dlp 全部就位。
- **视觉判读（qwen3-vl-plus，5 帧）**：8 条等宽竖彩带（白·黄·青·绿·紫·红·蓝·深灰）+ 画面最底部一条浅绿横带；无撕裂/闪烁/噪点/缺色；帧间无可见变化。
- **插件引擎（AVIS）**：运动矢量提取 ✅、场景分类（scene=64，0 切换点）✅、对象跟踪 12 个 ✅、AVIS 清单 ✅；ASR 输出 0 段（音频 RMS=0.0015 近乎静音 → 正常，非故障）。
- **结论**：「AI 能看懂上板录像」目标达成，两条路径（抽帧读图 / VLM）均可复用；插件线收尾，不再投入。

---

## 参考情报分析（2026-10-14 晚，为"重新对齐"服务）

**三个情报源**（产物在 `assets\ref_videos\`、`assets\ref_docs\`）：
1. 高云赛道国一演示视频（BV15rKP6pEwi，3分22秒）→ 抽帧 20 张 + ASR 79 段。**内容实为多功能仪器类作品**（频率计/信号源/调制/示波器/频谱/逻辑分析仪），与图像处理无关，但**呈现公式可借用**：功能切片 + 大字幕标题 + 实拍手操作 + 全程报指标 + 专业仪器背书。
2. **安路赛道国一选手经验分享 PPT**（13 页，`FPGA_Competition.pptx`）→ 最有价值情报：基础与扩展做满才能进线下；展示视频占晋级 70%（评委原话）；多展示数值指标；视觉效果强的算法优先（热力图/Sobel）；工作量也是分数（他们做 15 种算法）；三人分工（队长 infra / A 算法尽量多 / B 刷题+idea）；时间线 9.22 开赛→11.7 提交→11.28 国赛（含 Verilog 上机测评 + 现场答辩会被拷打）。
3. 2025 赛题解析 PPT（23 页）→ 确认**2025 安路赛题二是"以太网数据传输系统"（HX4S20C/EG4S20BG256）**，与 2026 我们的"实时数字图像处理系统（HX1P35A）"是两代不同的题 → 其架构不可照搬。

**据此产出**：`docs\06_情报与呈现方案.md`（功能清单三档 + 呈现方案 + 能力边界）、`docs\07_执行路线图.md`（流水线类比 + 4 周路线 + 三人分工 + 扩展调研模板）。

## P1 v2 启动（2026-10-14 晚）

**目标**：①按键从扩展口改到**板载 KEY1(D5)/KEY2(A9)**（v1 按键约束在 N2/J14，手指按不到）②TPG 接 DDR 帧缓存（为算法提供标准挂载点）

**已完成（AI）**：
- 约束 `constraints\colorbar_top.adc`：`I_button[0]` N2 → **D5**、`I_button[1]` J14 → **A9**
- 顶层注释同步更新（`colorbar_top.v`）
- 待用户验证：TD 重新编译 + 上板，按**板载 KEY1** 应能切换图案

**待做**：TPG → video_in(DDR) → video_out → hdmi_tx 通路（算法挂载点）

### 按键"没反应"排查（2026-10-14 晚，已定位根因）

**现象**：烧 v2（按键已改板载 D5/A9）后，按板子**左边缘**完全无反应（用户录像证实画面始终彩条）。

**排查链（四步排除法）**：
1. 消抖逻辑独立仿真（`tb\tb_debounce.v`）：静置 0 脉冲、按下 1 个、松开不误触、抖动 10 次被滤除 → **ALL PASSED**
2. 编译日志与资源报告：`run.log` 显示 `I_button[0] LOCATION = D5`、`[1] = A9`；`phy.area` IO 明细确认 D5/A9 已进 bit → **约束生效**
3. 手册第 22–23 页原文："板载 4 个金属弹片型独立按键 (KEY1~KEY4)，按下为低电平"；引脚分配 KEY1=D5 / KEY2=A9 / KEY3=B9 / KEY4=C7 → **与我们的约束和极性假设完全一致**
4. 手册第 4 页板卡布局图（实物标注）→ **按键物理位置**在**板子下边缘偏左**（TF 座上方、SPI FLASH 左侧，4 个并排轻触按键，丝印 K1~K4）

**根因**：**按错位置**——板子左边缘是 GPIO 扩展口 J1 排针区，没有按键。

**硬件验证**：烧官方现成 bit `2_Example\2_key_led\key_led_Runs\phy_1\key_led.bit`（无需编译），按 4 键流水灯效果与文档完全一致 → **按键硬件、引脚、极性全部正常**。

**产物**：标注图 `assets\manual_imgs\board_KEY_location_marked.png`；手册布局图 `assets\manual_imgs\p04_0.jpg`；手册按键章节图 `p22_1.jpg / p23_1.jpg`。

**待办**：烧回 `bitbank\OUR_p1_colorbar_v2_onboard_key.bit`，按**正确位置**的 KEY1 验证切图案。
**备用**：v3（LED 指示：LED1/2 = KEY1/KEY2 按下脉冲、LED3/4 = 图案编号）代码与约束已改好但**尚未编译**。