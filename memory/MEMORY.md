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
  - 改名前的 `.al`/`.sdc` 备份在 `D:\dsh-home\tmp\rename_backup\`；改名脚本留档 `src\p1_colorbar\archive\oneoff_scripts\rename_project.ps1`
  - 官方原包（`HX1P35A_Contest_202606\...\lab_ex1_mipi_hdmi`）保持只读，仍是官方基线
- **文档地图（2026-10-14 建立，2026-10-16 更新）**：总索引 = `docs\00_阅读指南.md`；活文档 = 01 赛题解读 / 02 文件存放规划 / 03 编译烧写速查 / 04 官方例程清单 / 05 开源调研 / 06 情报与呈现方案 / 07 执行路线图 / 08 算法规格_P2 / 09 问题总结_按键无响应 / 10 协作规范 / **11 复用与自研清单（答辩用）**；历史文档 = `docs\archive\`；原始备份 = `contest_s2\_backup_docs_20261014_2230\`
- **src 目录规约（2026-10-14 建立，2026-10-16 重构）**：**`src\p1_colorbar\README.md` = 工程文件地图（唯一权威）**，含 30 秒速览 / 目录职责 / 最新版本判断依据 / 可随时删清单 / 旧版本三步处理；`bitbank\` 只留里程碑 bit，**现行版本看 `bitbank\位流台账.md` 的「★ 现行版本」行**（不看文件名）；tb 分 `unit\`（模块级）/ `integration\`（集成级）/ `gen\`（脚本自动生成，可删）三类，对照表在 `tb\README.md`

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

**2026-10-15（P2 算法 RTL 验证）新增：**

15. **流水线的数据与地址必须同步打拍**：行缓存下沉写入 `lb2[addr] <= p1` 时，`p1` 是「上一拍读出的值」，写地址也必须用「上一拍的地址」（`addr_d1`）。否则行首拍会把上一行末列的数据写进本行首列 → 整行数据错位一列。做法：把「访问地址」单独打成 `addr_d1/addr_d2`，与数据成对使用。
16. **多条并行数据链的相位必须显式对齐**（本次最隐蔽的一个）：3×3 窗口用三条链（当前行 c / 上一行 r / 上上行 q），而行缓存输出 `p1/p2` 本身带一拍读延迟 → 三条链错开一拍，Sobel 实际跨了 4 列求和（实测 `gx=63`，正确值 `252`）。修法：给「当前行」的链输入也插一拍延迟（`in_d1`），三条链才对齐同一组列。
17. **链式窗口的行首处理**：行首清链能切断上一行的 X/越行数据，但清空用的 `0` 会被当成「黑色」参与运算（实测算出 `mag=1012` 的假边缘）→ `win_valid` 门限必须等链**真正填满**（3 级链 + 1 拍输入延迟 = 第 4 拍）才放行（`ram_addr >= 4`）。
18. **计数器位宽（再提醒）**：`row_cnt` 用 5 位装 360 行 → 溢出回绕，第 32 行之后 `win_valid` 判断全乱。凡计数器一律按「最大值 + 余量」取位宽（行/列相关统一 ≥10 位）。
19. **黄金模型必须与 RTL 严格同序**：RTL 是因果流式（不用未来行），模型侧若用「以当前像素为中心」的对称窗口（`np.pad` 底部补 0），最后一行会把下方当全黑 → 产生 560 个假边缘。做法：模型窗口垂直顺序改为 `{y-2, y-1, y}`（顶部补 2 行），边界屏蔽规则与 RTL 的 `win_valid` 逐字对齐。
20. **测试图必须覆盖多方向**：彩条是垂直条纹（`gy≡0`），会掩盖所有垂直方向 bug——P2 的 RTL 在彩条图上 0 误差，换棋盘/渐变图才暴露链相位问题。**验证集合固定为：彩条 + 棋盘 + 渐变 + 灰阶**。
21. **对比实验要排除边界 padding 效应**：统计「官方 vs 我们」误检时若算整幅图，最上 2 行/最左最右列因 `np.pad` 补 0 会产生约 1996 个假边缘（与算法无关）→ 只统计内部区域 `[4:-4, 4:-4]`。
22. **TD 命令行：强制重综合的命令是 `reset_runs`（复数）**（2026-10-15 踩坑）：写成 `reset_run`（单数）会返回 `invalid command name "reset_run"`——**若脚本里用 `catch` 包住，错误被吞掉后 `launch_runs` 会报 `PRJ-8805 ERROR: Runs xxx need to be reset first`，但 `wait_run` 仍会"成功"等到旧 run 的完成状态**，最终表现为：**编译日志一切正常、bit 文件时间戳不变、资源数字与上一版一模一样**（本次 reg 1409 / eram 5 / lut6 941 与 v3 基线完全相同才发现）。判别方法：编译后核对 bit 时间戳与资源数字是否变化；TD 可用命令用 `foreach c [info commands] {...}` 探测（含 reset 的只有 `reset_runs`）。
23. **`.al` 工程文件可以直接改**（2026-10-15 验证）：在 `<Verilog>` 段内按现有条目格式追加即可，`CompileOrder` 顺延；改前备份。格式：`<File Path="../../../rtl/xxx.v">` + `<FileInfo>` 内 4 个 `<Attr>`（UsedInSyn / UsedInP&R / BelongTo=design_1 / CompileOrder）。改后编译日志里应出现 `HDL-1007 : analyze verilog file .../xxx.v` 即生效。
24. **`wait_run` 会真卡死（修正之前的判断）**（2026-10-15 实测）：之前记录"`wait_run` 卡在 `Waiting for run xxx to finish` 但不影响执行"**不准确**——本次实测 syn_1 已完成（日志出了 `PRJ-1410 : Run syn_1 success.`）但 `wait_run` 仍无限等待，导致其后的 `launch_runs phy_1` **永不执行**，日志停在同一行、phy_1 目录始终为空。**可行替代**：用 TCL 标准命令 `after <毫秒>` 定时等待（`launch_runs syn_1` → `after 900000` → `launch_runs phy_1` → `after 300000` → `exit`），或**直接把编译交给 TD GUI 跑**（命令行方案仅适合脚本化/无人值守场景）。用 `after` 时注意 run 的实际耗时（本项目 syn≈10 分钟、phy≈1 分钟）。
25. **命令行编译的完整可用命令集（TD 6.2.168116 实测）**：`open_project` / `reset_runs <run> -f` / `launch_runs <run>` / `wait_run <run>`（勿用，见 24）/ `flow_status` / `exit`。用 `foreach c [info commands] { if {[string match "*reset*" $c]} { puts $c } }` 可探测真实命令名。
26. **数据源必须与 valid 严格同拍**（2026-10-15，A2 阶段踩坑）：`test_pattern_gen` 原用寄存器输出 `O_rgb`，比 `I_de` 晚一拍——直连 HDMI 时只表现为整体平移 1 列（肉眼看不出来，P1 阶段一直没发现），但**接到对边界敏感的算法后**，每行第 0 列会送入消隐期的 0（黑），与相邻灰度 25 形成 **mag=100 的假边缘**（实测每行都有，且两种判决都会检出，掩盖了真实差异）。改为组合输出（`always @(*)`）后与 de 同拍，假边缘消失、mag 正确显示为 48。**通用规则**：valid / 数据 / 地址三者必须同拍；跨模块拼接前先确认上游数据源是组合输出还是寄存器输出（寄存器输出需把 valid 一起打拍）。
27. **时序约束必须与实际设计层次一致**（2026-10-16 检查）：工程 `.sdc` 沿用官方 lab_ex1，其中 MIPI/DDR 相关约束（`create_clock {mipi_rx_ck_pad}`、`rename_clock {MIPI_RX_BYTE_CLK}`、`set_clock_groups` 里的 DDR 组）在"无摄像头版本"里**指向不存在的 net**——TD **静默忽略、不报错**，容易让人误以为约束完整。真正的缺口是：**按键/复位等异步输入没有约束，且 `debounce_btn` 没有同步器**（异步信号直接进比较逻辑，有亚稳态风险）。修法：①异步输入先过两级触发器同步器；②`.sdc` 加 `set_false_path -from [get_ports {I_button[*]}]` 与 `-from [get_ports {I_rst_n}]`；③清理指向不存在对象的约束。**改 `.sdc` 与改 RTL 一样，必须 `reset_runs` 才生效。**
28. **看时序不能只看全设计最差 WNS**：TD 报告顶部的 `Setup WNS` 是**全设计最差路径**（本项目 v3 的 14071ps 极可能落在 50M 域，周期 20ns），**不代表算法所在的 HDMI_PIXEL_CLK(74.25M，周期 13.468ns) 域**。必须分别看各时钟域的 WNS。**补充（2026-10-16，切摄像头版实测）**：综合阶段的 `gate.qor` WNS 是**布局前悲观估计**——本次 `gate.qor` 显示 `Setup WNS -231 / 45 违例`，但 `gate.timing` 已是 +1.116ns，P&R 后 `final_timing.rpt`（`Confidence: Routed`）= **SWNS +0.464 / HWNS +0.020 / 0 违例**。**判序言的最终标准永远是 P&R 后的 `final_timing.rpt`，综合阶段负 WNS 先别慌**。
29. **验证脚本绝不能吞掉编译错误**（2026-10-16 踩坑，最危险的一个）：`verify_all.ps1` 原用 `& vlog ... | Out-Null`，**编译失败时脚本毫无察觉，vsim 沿用了上一次成功编译的旧模块** → 打出"4 图全 0 误差 PASS"，而实际跑的是旧代码（当时 `eb_d1/eb_d2` 被误声明为 wire，编译 4 个 Error）。**修法**：捕获 vlog 输出，`Select-String "Error"` 命中就记"编译失败（未跑仿真）"并 `continue`。**通则：任何"全 PASS"都必须以"编译成功 + 仿真成功"为前提**，自动化验证脚本要显式检查每一环的失败。
30. **仿真模型的参数/端口必须与真原语逐字对齐**：给 TD 原语写 ModelSim 行为模型时，vopt 会校验例化处传的参数是否存在，**少一个就报 `Module parameter 'xxx' not found for override` 并导致加载失败**（本次漏了 `ECC_ENCODE`/`ECC_DECODE`）。做法：把真原语的 parameter 列表**整段抄过来**（含 `SSROVERCE`/`ASYNC_RESET_RELEASE_A`/`CLKMODE`/`DEBUGGABLE`/`PACKABLE`/`FORCE_KEEP`/`IMPLEMENT` 等看似无关的）。
31. **算法模块的输出会被 TD 判成"可常量传播"而整片删除 —— 必须加 `(* keep = "true" *)`**（2026-10-16，排查耗时最长的一个坑）：
    **现象**：`edge_adaptive_pixel` 综合后只有 **49 LUT / 0 ripple / 37 seq / 0 eram**（按代码应有 ~250 LUT / ~139 seq / 3 eram），算法完全没进网表。而文件确实在工程里（`.al` 注册 + `analyze` + `elaborate` 三重确认），数据通路也通（TPG → adapter → `hdmi_tx.I_video_in_data` → HDMI 核，逐段核对过）。
    **干扰项**：换了三种行缓存实现（reg 数组 / 裸例化 `PH1P_LOGIC_ERAM` / 工程内已注册的块 RAM IP）**结果逐字相同**，说明问题不在"用什么 RAM"。
    **根因**：TD 认为算法的输出可常量传播，于是从行缓存输出开始，把窗口链、Sobel 加法器、阈值计算一路删光（`ripple = 0` 就是"没有进位链"的铁证）。
    **解法**：给关键中间信号加保留约束（9 处，用官方 `design_top_wrapper.v` 里的 `(* keep = "true" *)` 语法）：
    ```verilog
    (* keep = "true" *) wire [31:0] S_lb1_dout;          // 块 RAM 输出
    (* keep = "true" *) wire [7:0]  p1 = S_lb1_dout[7:0];
    (* keep = "true" *) wire [11:0] mag = gx_abs + gy_abs;  // Sobel 结果
    (* keep = "true" *) wire [11:0] sum9 = ...;             // 阈值用
    (* keep = "true" *) wire        win_valid = ...;
    ```
    **效果**：`u_edge` 49→**356 LUT**、ripple 0→**39**、seq 37→**161**、eram 0→**3**；顶层 `#eram` 5→**8**、`#luts` 1169→**1522**、`#registers` 1384→**1519**、`#syn_keep` 81→**219**；时序仍 0 违规（R-Freq **152.788MHz**，算法域只需 74.25MHz）。
    **通则**：TD 里若"某模块资源异常小 **且 ripple = 0**"，就是被优化掉了 —— 加 `keep` 即可验证并解决。
32. **TD 里块 RAM 只有两条可用路径**（2026-10-16 实测）：
    ① **工程 `.al` 的 `<IP_FILE>` 段用 `.xml` 注册过的 IP**（如官方 `blk_mem_gen_zhenghe`：32 位 × 2048、`ADDR_WIDTH=11`、`REGMODE_A/B="NOREG"`、`WRITEMODE_B="READBEFOREWRITE"`、`IMPLEMENT("20K(FAST)")`）—— 在 HDL 里**裸例化它的模块名即可**（官方 `zhenghe.v` L167 就是这么用的，我们实测同样有效，`#eram` +3）；
    ② 用 TD 的 IP 生成器自己生成。
    **裸例化 arch 库的 `PH1P_LOGIC_ERAM` 原语无效**：该原语在 `ph1p_macro.v` 里是**纯空壳**（0 个 assign/always/reg），TD 只在 IP 流程里才把它映射成物理块 RAM。裸例化时 `elaborate` 能找到模块、参数也照官方 IP 对齐过，但**不产生任何资源**。第一次尝试用 reg 数组也不行 —— 会被推断成 `LOGIC_RAMFIFO` 且地址位宽推成 10 位（1024 深，实际需要 1280）。
    **仿真**：ModelSim 不认识该原语，用 `sim\golden\ph1p_eram_sim_model.v` 替代（参数列表必须与真原语**逐字对齐**，少一个就报 `Module parameter 'xxx' not found for override` 并加载失败）。
33. **多像素并行流水线的行缓存地址不能凭直觉，必须逐拍推演**（2026-10-16，`edge_adaptive_96` 调试，耗时最长的一轮）：
    **症状**：并行版（4 像素/拍）与已验证的逐像素版逐像素对比，误差长期停在 140/560，且"多余边缘随行号累积"。
    **排查铁律**（照 R2 清单 F 段执行，确实有效）：
    ① **先做能切开假设空间的一次实验**——把迟滞临时关掉（`e = s`）只留强边缘判定，误差立刻从 140 → **0**。一步就把范围锁死在"迟滞"，不用再猜窗口/阈值；
    ② **窗口完整性探针**：图案三行相同时，`BOT/MID/TOP` 必须逐值相等。这一条直接暴露了"MID 落后 1 组、TOP 落后 2 组"，比对着波形数拍快得多；
    ③ **不凭直觉给地址**：块 RAM 同步读有 1 拍延迟，`rd = x_grp` 时"读出的组号"会比"窗口需要的组号"少 1（line1）/少 2（line2）。正确做法是**从"窗口需要哪一组"倒推"地址该在哪一拍给"**，实测校准为 `rd_gray = x_grp + 1`（两块共用），第 31 组回绕到 0（不回绕会读到从未写过的地址 32 得到 `x`，污染下一行开头）；
    ④ **行缓存冷启动**：`line2` 在第 0 行期间写入的是 `line1` 的**未初始化读出（X）**，要到第 2 行才被完全覆盖 → **前 3 行必须屏蔽**（`row_ok = y_d2 >= 3`，与官方 `row_cnt >= 3` 一致）。只屏蔽 2 行会让第 2 行 `mag` 变成 254（应为 12），误判后经迟滞逐行放大；
    ⑤ **边界屏蔽粒度要与参照版一致**：官方 `win_valid` 里的 `ram_addr >= 4` 屏蔽的是**整整一个组（4 列）**，不是只屏蔽列 0。只屏蔽列 0 会让列 3 被上一行残留 `up` 点亮，再经 `left_in` 传给列 4 并逐行累积。
34. **Verilog 拼接的最左项是 MSB**（2026-10-16，同一轮踩到）：`upleft = {e_s1[3], up[0], up[1], up[2]}` 实际是 `upleft[3]=e_s1[3]`，**整个向量是反的**，正确写法 `{up[2], up[1], up[0], e_s1[3]}`。这类错误在"六列窗口/四像素判决"的向量里特别隐蔽——值看着都合理，只是**错位**。**判据**：拿一个已知的真边缘，手算该像素的"左上邻居"列号，与探针打印的向量逐位对。
35. **两个不同节奏的模块比对，必须用"像素编号"而不是"序列下标 + 猜偏移"**（2026-10-16，验证方法本身的坑）：并行版 4 像素/拍、逐像素版 1 像素/拍，按"输出序列下标"对齐时只能靠扫描偏移，而偏移量会随"两者输出起点定义不同"漂移（本次漂到 9，设计的延迟只有 3），越猜越乱。**改法**：tb 输出时带上本拍的**像素编号**，外部脚本按编号查表比对 —— 对齐歧义彻底消失。
36. **参照模块自身也可能带"管线标注延迟"，比对前要先量化它**：`edge_adaptive_pixel` 的输出标注比真实列号多 **+4**（它 3 级流水 + 输出寄存）。这不是 bug，是它自己的时间基准；正式比对时换算掉即可（`par[c]` 对 `seq[c+4]`）。
37. **行首前 2 拍的 `x_d2` 仍停在上一行的 30/31**：此时 bot 行是本行、mid/top 是上一行，窗口是跨行混合的无效值。虽然加了 `beat_bad = (x_grp <= 1)` 屏蔽，但**实测该屏蔽对本例无影响**（真正的病因是 33 的 ④⑤）—— 记录在此以免下次误判为根因。
38. **TD GUI 打开工程期间持有 `.al` 锁，外部改 .al 会被它用内存旧态回滚**（2026-10-16，切摄像头版踩坑）：TD 打开工程后把 `.al` 加载进内存，外部脚本/编辑改磁盘 `.al` 的**瞬间**，TD 会（在它下一次写盘或定时保存时）把它内存里的旧 `.al` 整体覆盖回去——现象是"patch 脚本报成功，但 3 秒后再读又变回 colorbar_top、design_top_wrapper 计数=0"。判定信号：`td_project\.lock.f` 锁文件存在 + `tasklist | grep td.exe` 有进程。
    **正确顺序**：① TD 里关工程（最好直接退出 td.exe）→ ② 确认 `.lock.f` 消失、td.exe 退出 → ③ 再外部改 `.al` → ④ 改完**等几秒复查（grep design_top_wrapper 计数）确认留存** → ⑤ 重启 TD 打开工程（此时读的才是磁盘上的新 .al）。
    **同源坑家族**：与"`check_build.ps1` 读不到 TD GUI 日志"同属"TD GUI 与外部工具互斥"——TD 的工程文件和运行日志都不是给外部进程实时读/写的。
39. **改 .al 的 patch 脚本必须幂等且自包含全部动作**：本次"删 colorbar_top.v"当初是手动 edit 做的、没写进 `patch_al_camera.py`，结果被 TD 回滚后重跑 patch 就漏删了 colorbar_top。教训：**一次性工程配置改动要么全写进一个幂等脚本，要么重跑前先核对"脚本覆盖的动作集合"是否等于"期望的最终状态"**。
40. **仿真的测试图案必须带噪声/低对比度，否则算法对真实传感器过敏感这一关永远测不出来**（2026-10-17，A3 上板实测）：`tb_edge_adaptive_96` 的图案是"干净"的（棋盘+锯齿），仿真 0 误差、但上板烧 `THR_FLOOR=16, I_k=2` 的画面是**灰度雪花**——真实暗部传感器噪声的 Sobel 幅值轻松超过自适应阈值 18，弱边缘判据把噪声全点亮，再被迟滞连成片。**修路径**：① 上板前用 `I_mode=0`（原图直通旁路）二分切出"通路 vs 算法"——本次由此确认通路 100% 正常（彩色实时画面）；② 调参 `THR_FLOOR 16→48`、`I_k 2→0`；③ 若仍不行再上 3×3 前置平滑。**通则**：算法 tb 的测试图案要含 ① 强边缘 ② 弱边缘 ③ **叠加高斯/椒盐噪声的平坦区** ④ 低对比度纹理，四类都要有。
41. **"留一个旁路"是最便宜的调试资产**：`I_mode` 的态 0（原图直通 mux，`S_disp_*` 选 awb 原始 96bit）当初只是为"四态演示"设计的，结果在上板排查时成了**一键二分工具**（绕过算法看通路）。同理：任何插进通路的算法模块，给它留一个"直通旁路"（一个 mux/一个参数位），上板后能省一次硬件返工。

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
5. **★ 阶段性任务完成后必做文件整理**（2026-10-17 用户明确）：每个阶段收尾时按 `docs\02_文件存放规划.md` 的要求整理：临时文件清出根目录（调研脚本/下载源码归入 `docs\research\` 的 Rn 目录或归档）、过时产物版本化归档（不散落不覆盖）、`memory\` 台账与 `bitbank\` 同步、验证产物（sim 输出/视频抽帧）按 `assets\` 归置。**整理本身也是任务的一部分，不算额外工作**。
4. **★ 调研边界铁律（2026-10-17 用户明确，优先级最高）**：**被官方框死的一定遵守（接口/插点/通路），可自主掌握的范围一定深度调研**；调研时间可以花得长且仔细，**目的是减少实施中各种不必要的错误**。具体执行标准：
   - 主题泛化：不只搜"本项目形态"，还搜"同一算子的常见实现范式"（行缓存轮转 / box filter 增量更新 / 多像素并行窗口 / 自适应阈值组织方式…）；
   - **至少深挖 2 个完整开源仓库**（读完核心 RTL，不是只看 README/搜索结果摘要——2026-10-16 那次调研一行源码都没读到，导致 v2 的列和加法器用最笨的重复求和实现）；
   - **先发散后收敛**：检索阶段禁止预设结论，列出 ≥3 个候选架构（资源/时序/实现难度对比表）再选型；"借鉴点摘抄"式的事后贴标签无效（教训：6 列窗口是我们自然推出来的，调研只贴了张标签）；
   - **只借鉴思路、绝不照搬源码**（2026-10-17 用户强调）：借鉴的粒度是**架构模式与工程技巧**（"separable 分离两趟 1D""running sum 增量滑窗怎么组织""环形行缓存免下沉搬运"这类方法论），落地代码一律结合我们的接口（96bit、4 像素/拍）和约束自己写——不复制任何开源 RTL 片段。这与赛题红线（算法不能与官方例程相同）和 `docs\11_复用与自研清单.md` 的口径一致；
   - 情报优先级：读官方例程源码 > GitHub 深度通读 > 论文 > 搜索引擎摘要。
- 已执行：P1 v1 的 4 个 RTL + tb 全部按此重写（功能未变）。以后每次交付代码前自查这几条。
- **补充：流水线设计规范**（2026-10-15 P2 踩坑后固化）：
  1. **数据与控制成对打拍**：像素数据、`valid`/`last`/`user`、以及**访问地址**必须同拍推进，不能一个延迟一个不延迟；
  2. **多链相位显式对齐**：同一窗口的多条数据链（当前行/上一行/上上行）必须对齐到同一组列，行缓存读出的一拍延迟要在链输入端补回来；
  3. **链式窗口的行首**：要么「清链 + 延后放行（等链填满）」，要么加有效性标志，不能在半填满状态下参与运算；
  4. **验证向量四件套**：每张测试图同时导出 `gray/edge/mag/thr`，先对 `mag`（纯组合）再对 `edge`（含迟滞），可把问题范围逐层收窄。

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