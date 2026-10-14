# 项目记忆 — 赛题二 HX1P35A（DSH 会话 · 独立维护）

> 本目录是「错误与关键点」记忆，独立于官方资料包。
> 历史记忆快照（workbuddy 时代，已读取并继承）在：
> `E:\fpga\HX1P35A_Contest_202606\.workbuddy\memory\`
> ⚠️ 其中关于 **SC500** 的一切结论，已被下方 **SC520 纠错** 取代。

---

## 一、关键事实（本轮已核实，勿再翻旧文档）

- 赛题二 = **MIPI 摄像头采集 → FPGA 自研算法实时处理 → HDMI 输出处理后的视频 + OSD 叠加"安路"Logo**。
- 基础 4 条（必做）：①采集+实时显示 ②FPGA 端 ≥1 种图像算法 ③画面稳定连续 ④OSD 且必须含"安路"Logo。
- 红线：⚠️ ①提交的算法**不得与官方例程雷同** ②必须用 **TD 6.2.1** ③外扩电路板不得含非安路 FPGA 器件。
- 平台：PH1P35MDG324，1280×720@60，HDMI 像素时钟 74.25MHz，摄像头 = **SC520**。

## 二、⚠️ 重要纠错：摄像头是 SC520，不是 SC500

- 用户明确：实物摄像头是 **SC520**（不是题目手册写 SC500CS/SC500）。
- 资料包 `7_lab_ex_2026_nosoft\` 下实际有**两套例程**：
  - 旧 `SC500_720P` 版：`lab_ex1_mipi_hdmi_SC500_720P` / `lab_ex2_edge_SC500_720P` / `lab_ex3_osd_SC500_720P`
  - 新 `SC520` 版：`lab_ex1_mipi_hdmi_SC520`（已解压，双层嵌套）、`lab_ex2_edge_SC520.zip`、`lab_ex3_osd_SC520.zip`
- SC520 版 lab_ex1 源码里**同时存在** `uics500_cfg\` 与 `uics520_cfg\` 两个目录；`uics520_cfg\uics520regAE.v` 是 SC520 专属寄存器配置。
- **结论：P0 基线必须用 SC520 版例程**（`lab_ex1_mipi_hdmi_SC520`），不要用 SC500_720P 版，否则 SC520 摄像头寄存器可能不匹配。
- **SC520 例程关键确认（已读源码）**：
  - 寄存器表 `uics520_cfg\uics520reg_720p60.v` 头部注释：**SC520CS 原厂 HD 模式 = 1280×720@60fps，24MHz MCLK，2-Lane RAW10，Lane 速率 828Mbps，Sensor 内部启用 VBIN+HSUB 直接输出真实 720p；REG_SIZE=165**。
  - 满分辨率表 `uics520reg_full_2560x1920_30.v` 存在（500 万像素全分辨率 2560×1920@30）。
  - 顶层 `design_top_wrapper.v`（916 行）带**传感器 ID 校验**：`S_cam_sensor_id / S_cam_sensor_id_ok / S_cam_i2c_error`（keep 信号）→ 摄像头型号不是 SC520 会配置失败，可作排错依据。
  - 引脚约束与 SC500 版一致：I_sys_clk=C4 / I_rst_n=R10 / cam_scl=K3 / cam_sda=J3 / cam_24m=L3 / cam_rst=L2 / button=N2,J14 / tmds=G16,F17,H14,C17。
  - 资源：LUT 38184 / DFF 42432 / ERAM 2160Kbit / DSP 40 / PLL 6。

## 三、团队与目标（本轮对齐）

- 团队：3 人，大三。1 人有 Verilog + 简单 FPGA 上板经验；2 人接触较少，但 AI 使用与学习能力强。
- 时间：约 4 周（冲刺）。目标：**稳基础 + 1~2 个扩展项**。
- 既定打法：
  - 主算法 = **自适应阈值边缘检测**（区别于例程的「固定阈值 Sobel」，天然满足"不雷同"红线）。
  - 扩展优先级 = ①卡通化（视觉冲击强、演示好）②颜色/形状目标检测 + OSD 框（可选，规则级无需 NPU）。
  - 交付路线 = P0 基线 → P1 彩条地基 → P2 算法仿真 → P3 算法上板 → P4 OSD → P5 交互 → P6 扩展 → P7 交付。

## 四、文件布局（E 盘，新）

- 项目根（我们的产物）：`E:\fpga\contest_s2\`（docs / src / sim / assets / delivery / memory）
- 官方资料（只读不动）：`E:\fpga\HX1P35A_Contest_202606\`
- 历史文档快照（不迁移，仅参考）：`E:\workbuddy\fpga\`
- 自建 TD 工程历史：`E:\fpga\anlu_project\`
- **P1 自研 TD 工程（2026-10-14 已改名，与官方彻底区分）**：
  `E:\fpga\contest_s2\src\p1_colorbar\OUR_project\hdmi_base_src\td_project\OUR_p1_colorbar.al`
  （外层 `OUR_project` / 内层 `hdmi_base_src` / 工程名及 Runs、sdc 均为 `OUR_p1_colorbar*`；原 `hdmi_base\lab_ex1_mipi_hdmi` + `camera_to_dsi_display.*` 已不存在）
  - 顶层 = `colorbar_top`；自研 rtl 在 `src\p1_colorbar\rtl\`（工程内相对路径 `../../../rtl/`）；约束 `../../../constraints/colorbar_top.adc`
  - 改名前的 `.al`/`.sdc` 备份在 `D:\dsh-home\tmp\rename_backup\`；改名脚本留档 `src\p1_colorbar\tools\rename_project.ps1`
  - 官方原包（`HX1P35A_Contest_202606\...\lab_ex1_mipi_hdmi`）保持只读，仍是官方基线
- **文档地图（2026-10-14 已按主题重构）**：总索引 = `docs\00_阅读指南.md`；活文档 = 01 赛题解读 / 02 文件存放规划 / 03 编译烧写速查 / 04 官方例程清单 / 05 开源调研 / 06 情报与呈现方案 / 07 执行路线图 / 08 算法规格_P2 / 09 问题总结_按键无响应；历史文档 = `docs\archive\`（P0 两份手册、旧全程纪要、TD 分步教程、旧版 01）；原始备份 = `contest_s2\_backup_docs_20261014_2230\`
- **src 目录规约（2026-10-14 建立）**：`src\p1_colorbar\README.md` = 各目录职责 + "什么算最新版本"判断依据 + 旧版本三步处理 + 可随时删的仿真产物清单；旧版本集中在 `src\p1_colorbar\archive\`（`old_bit\` / `oneoff_scripts\` / `old_logs\`，配 `README_旧版说明.md`）；**`bitbank\` 永远只留最新可用 bit**（现行 = `OUR_p1_colorbar_v3_debounce_fix.bit`）

## 五、已踩坑速查（继承自历史，避免重犯）

1. **BIT-8123**：未加引脚约束会直接报 `Bitgen is prohibited`——每个顶层端口都必须有 LOCATION 约束。
2. **ModelSim 控制台是 ANSI 编码**：tb 里 `$display` 中文乱码 → 输出用英文、中文只放注释；`%0t` 要配 `$timeformat(-9,0,"ns",8)`；integer 变量必须初始化。
3. **TD 支持仿真**（曾误判"不支持"）：`Tools → Simulation Libraries Compiler` 编器件库 + `Tools → Project Simulation` 四阶段仿真；tb 走 `Source → New Source → Verilog Test Bench` 或 `Project Simulation → Add existing testbench`，不进 Design Files。
4. **TD 生成的 behav_sim do 末尾固定 `run 1us`**——图像模块必须改 `run -all`。
5. **本板仿真模型在 `sim_release\ph1p\`**（不是 ph1）；纯 RTL 不需器件库，用安路原语/后仿才需编译。
6. **TB 必须有"总量校验"**：否则设计完全不动也误报 PASSED（自检形同虚设）。
7. 器件 PH1P35MDG324-3；约束语法 `set_pin_assignment {端口}{LOCATION=...;IOSTANDARD=LVCMOS33;...}`，总线写 `端口[0]`。
8. 板载：KEY1~4=D5/A9/B9/C7(低有效)、LED1~4=D10/E10/C6/D6(高有效)、时钟 C4、HDMI TMDS=G16/F17/H14/C17(仅 _p 端 TMDS33)。
9. **TD 6.2.1 锁死不可升**；`E:\app\Software\work\td\`，ModelSim 在 `E:\app\Software\work\modelsim\win64\`。
10. **文档矛盾优先级：例程 pin.adc > 原理图 > 引脚汇总文档**；JTAG TCK=P15（手册 R13 是笔误）。
11. **本机 ModelSim SE-64 10.5 的 vlog 只支持 Verilog-2001**，以下 SystemVerilog 写法都会编译报错（2026-10-14 踩坑，tb 因 3 处 SV 语法编译失败）：①`longint` 数据类型 → 用 `integer`；②块内变量声明时赋初值（`integer h=0;` 在 begin 块内）→ 声明与赋值分开；③对数字常量取位选（如 `264[4]`）→ 先算好写成常数或声明变量；④`$display` 的 `%0s` → 用 `%s`（`%0d` 合法）。以后 ModelSim 编译报 `near"="`/`unexpected '['` 先查这四条。
12. **视频通路坐标两类，不要混**（2026-10-14 P1 仿真抓出的真 bug）：`hcnt/vcnt` 是**整幅时序计数**（含同步+后沿，720p 有效区从 hcnt=260、vcnt=25 开始），产生图案/比较画面中某个 (x,y) 时必须先换成**画面坐标** lx=hcnt-260、ly=vcnt-25；彩条 8 分列 = 每 160 列，用比较链（>=1120/960/800/...），用 `hcnt[10:7]`（128 列一段）是错的（现象：探针 @280 得到青色 00ffff）。另外 tb 里 wait 到 (x,y) 当拍后，**下一个 posedge** rgb 寄存的即该坐标颜色（多等一拍会拿到 x+1）。
13. **约束属性要与端口方向匹配**（2026-10-14 TD 报 `USR-8409 ERROR: DRIVESTRENGTH is not supported by HDIO.LVCMOS33 in INPUT direction`）：顶层声明为 `input` 的脚约束里**不能带 `DRIVESTRENGTH`**（官方 pin.adc 的 I_button 带它是因为官方顶层用的 `inout`）。我们 top 的 I_button= input → 约束只留 LOCATION/IOSTANDARD/PULLTYPE。已修 colorbar_top.adc。
14. TD 日志里这些是无害的，别当错误：`IO_ddc_sda remains unconnected`（inout 悬空）、`S_pll_lock does not have a driver`（hdmi_tx 内部警告）、加密 IP 的 `**` 符号、官网 demosaic 的 `/* inside a comment`。

## 六、待办（P0 优先级，下一步）

- [x] 肉眼看摄像头丝印，确认 SC520（用户已确认是 SC520）
- [x] 读 SC520 例程源码（寄存器表/顶层/约束），差异已记录上方
- [x] **P0 里程碑达成**：SC520 版 lab_ex1 在 TD 6.2.1 编译 + 烧写成功，HDMI 出实时画面（用户照片确认，画面为摄像头实拍场景）→ 证明工具链+MIPI+DDR+HDMI+SC520 全链路完好
- [ ] **P0 收尾待办**：①确认画面质量（挥动手看是否实时跟随、无撕裂/花屏、连续 ≥10 分钟）②记录综合报告资源占用（LUT/DFF/ERAM/DSP + Fmax）作基线 → 记 `memory\PROGRESS.md`
- [ ] 解压 `lab_ex2_edge_SC520.zip`、`lab_ex3_osd_SC520.zip`
- 下一步阶段：P1 无摄像头彩条地基（复用 32 号例程 HDMI 链 + 自研彩条源 + 通链自检显示）

## 七、环境问题（✅ 已解决：切换沙箱档位，2026-10-14 19:18）

- **现象**：DSH 的 pwsh 工具 spawn 任何 `pwsh.exe` 都报 `0xC0000142`（STATUS_DLL_INIT_FAILED），无任何输出；而同一台机器手动运行 PowerShell/pwsh 正常、无第三方杀软；更新 / 重启 / 卸载重装 DSH 均无效；**同机 workbuddy、Cursor 能正常执行命令**（关键对照证据）。
- **根因（源码级）**：DSH 在 Windows 上用**低完整性令牌（write-restricted Low-integrity token）**实现文件沙箱；在 `workspace-write` 档位下，pwsh 于受限令牌中启动即 DLL 初始化失败。证据：`_sbx\sandbox-policy.js`（`SANDBOX_MODES = ["read-only","workspace-write","danger-full-access"]`，支持每会话覆盖、有 UI 控件）+ 历史会话结论原文 "the confined sandbox itself is what breaks `pwsh` (it works under full access)"。
- **解法**：把会话文件策略从「工作区内修改」切到「**完全访问 / danger-full-access**」。**实测通过**（首次成功执行 `Copy-Item` 归档 bit）。
- **代价与约定**：完全访问下没有文件沙箱保护（AI 可写任意路径），需要时可随时切回；**这档位就是执行能力的总开关**——以后若通道再报 0xC0000142，第一个查它。
- 教训：先后误判为"缺 pwsh / 杀软 / 版本旧 / 组件损坏"，最终靠"同机其它工具正常"的对照 + 源码证据才定位到沙箱令牌。

## 八、代码编写规范（用户 2026-10-14 明确，长期强制）

1. **资源与效果优先，避免复杂化**：设计先从资源占用和呈现场景出发，能简单绝不绕。
2. **注释去 AI 化**：只写"这段在做什么、为什么这么写、参数哪来的"这类工程实话；不用"自检要素""团队规范""自研件 X/Y""与官方的差异"等组织性/汇报性措辞；**注释必须与代码一致**（教训：tb 头部写"负向校验"但实现里没有，被用户指出）。
3. **贴合实际硬件与时序**：时钟（50M/74.25M/371.25M）、TMDS 引脚、PLL 端口等按实际连线写。
- 已执行：P1 v1 的 4 个 RTL + tb 全部按此重写（功能未变）。以后每次交付代码前自查这三条。

## 九、AI 本机能力与工具链（2026-10-14 打通，可复用）

- **执行通道**：沙箱档位切 `danger-full-access` 后 pwsh 恢复（详见第七节）；档位即总开关。
- **看视频**：本机已装 **ffmpeg 9.0.2**（winget `Gyan.FFmpeg`，路径 `C:\Users\Administrator\AppData\Local\Microsoft\WinGet\Packages\Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe\ffmpeg-9.0.2-full_build\bin`）。抽帧：`ffmpeg -i in.mp4 -vf "fps=2,scale=640:-1" frame_%03d.png` → AI 用读图能力直接判读（无需人工转述）。范例帧存 `assets\video_frames\`。
- **视觉大模型**：DSH 本地 QWEN key（凭据 `D:\dsh-home\.credentials.yaml` → `refs.QWEN_TOKEN_PLAN_CN_API_KEY`，明文，长 115）可用：文本 `qwen-plus` / `qwen-max`；视觉 **`qwen3-vl-plus`**（`qwen-vl-max` 403、`qwen-vl-plus` 404 不可用）。端点 `https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions`。复用脚本：`src\p1_colorbar\tools\vlm_frames_probe.py`。
- **视频理解插件** `dsh-video-understand 0.5.2`（pnpm 裸装于 `D:\dsh-home\profiles\desktop\node_modules\`，未按 D:\Plugins 规范）：引擎 `engine\understand_video.py`；前置 ffmpeg + faster-whisper + opencv（已装）；**Windows 必须设 `PYTHONIOENCODING=utf-8`**（否则 emoji 触发 GBK `UnicodeEncodeError` 崩溃）；缺的包按其 `engine\requirements.txt` 补（已知缺 xxhash）。
- **控制台编码通用坑**：本机 Python/ModelSim 输出中文/emoji 都会撞 GBK → 统一 `PYTHONIOENCODING=utf-8` + `[Console]::OutputEncoding=UTF8`。

## 十、路线调整（2026-10-14 重新对齐，长期有效）

情报来源：国一选手参赛经验 PPT（2025 安路赛题二国一，见 `assets\ref_docs\`）+ 高云国一演示视频（BV15rKP6pEwi）。据此对原计划做 4 处修正：

1. **扩展项必须做满**——国一原话："基础与扩展做满方能进入线下"；扩展不是选做，是决赛门票。
2. **算法数量本身就是分数**（国一做了 15 种图像处理模块）：算法做成**可插拔模块**，目标 6~10 种效果（边缘/卡通/浮雕/马赛克/素描/热力图/运动检测…）。
3. **展示视频权重最高**——评委原话："一个优质的展示视频基本占晋级概率 **70%**"：素材随做随录、每个功能前加字幕标题、全程报数值指标（资源/帧率/延时）。
4. **每个扩展项动工前先做可行性调研**（用户要求）：按 `docs\07_执行路线图.md` 第四部分模板产出 1 页 `docs\research\Rn_<项目名>.md`，全队看过再动手。

**能力边界（已写入 `docs\12`）**：像素级 / 邻域级 / 规则级算法全都能实时做（FPGA 主场）；需要 CNN/NPU 的目标识别做不了（本芯片无 NPU，38K LUT 不够）。
- **插件引擎端到端可用**（2026-10-14）：`python engine\avis.py encode <视频> -o <目录> --obj-tracks --asr-model tiny --skip-mv` 能产出 AVIS 语义层（运动矢量 / 场景分类 / 对象跟踪）；未跑通的是可选件：OCR（缺 PaddleOCR）、YOLO（缺 ultralytics）。
- **两个下载/兼容坑**：① HF 模型下载 401 → `HF_HUB_DISABLE_XET=1`（配 `HF_ENDPOINT=https://hf-mirror.com`）；② faster-whisper 1.2.1 与 **PyAV 19** 冲突（`av.open(..., metadata_errors=)` 参数已被移除），降级 `av<15` 在 Py3.13 无预编译 wheel、源码编译失败 → **绕法**：`ffmpeg -i v.mp4 -vn -ac 1 -ar 16000 a.wav` 抽音频，再用标准库 `wave` 读成 int16 数组 /32768 后传给 `WhisperModel.transcribe(数组, language='zh')`，跳过出错的 `decode_audio`。附：`time_info`/`billing` 无关。
- **抽帧看视频是本机最快的视频分析路径**：`ffmpeg -vf "fps=2,scale=640:-1" frame_%03d.png` → AI 读图；比装整套 ASR/VLM 管线快得多，且不依赖任何云服务。