# B4 更新说明：OSD 叠加（含"安路"Logo）

> ⚠️ **2026-10-17 23:41 更新：已按"官方优先"原则切换为官方实现。**
> 现行交付 = 官方 `hdmi_mixer.v`（内部自带 Logo + 文字 OSD）+ 官方 `anlogic_logo_rom.v` / `osd_char_lib.v`，**原样使用、字节未改**。
> 本文第一～八节记录的是**自研实现**（`osd_overlay.v`）的过程与验证数据，仍然有效——它现在作为**备选分支**保留，定义 `OSD_SELF_DEV` 即可切回。
> 两者对比、为什么切、切换方法与实测差异，见**第九节**。

> 本文只讲一件事：**赛题"基础"第 4 条**——"叠加图形、文字等信息，如 Logo 等（包含'安路'字样或标识）"。
> 扩展/进阶内容（模式切换、按键、参数面板……）本次**一律没动**。
>
> 落盘位置：`E:\xunlei\contest-s2-main`（可直接接回你们原来的工程）。

---

## 一、更新在哪里（改了什么、一行都不多）

### 1. 新增 RTL（2 个文件，全部自研）

| 文件 | 行数 | 作用 |
|---|---|---|
| `src/p1_colorbar/rtl/osd_overlay.v` | 537 | OSD 叠加主模块：坐标计数器、面板/描边、Logo 取数、5×7 字模、优先级、单拍流水 |
| `src/p1_colorbar/rtl/osd_logo_rom.v` | 6408 | "安路"标识的 2bit/像素 ROM（6387 个不透明像素，深蓝/红两色） |

`osd_logo_rom.v` 由生成器自动产出，**不要手改**；改 Logo 只改生成器再重跑。

### 2. 改已有文件（只有 2 个，共 5 处）

#### (1) `OUR_project/hdmi_base_src/user_source/hdl_source/design_top_wrapper.v`（3 处）

| 位置 | 改了什么 |
|---|---|
| 第 **163–167** 行 | 新增 4 根线：`S_osd_vs / S_osd_hs / S_osd_de / S_osd_data` |
| 第 **892–912** 行 | 在 `u_hdmi_mixer` 之后、`u_hdmi_tx` 之前**插入实例** `u_osd_overlay` |
| 第 **923 / 924 / 929** 行 | `hdmi_tx` 的输入改接 OSD 输出：`.I_video_in_vs(S_osd_vs)`、`.I_video_in_de(S_osd_de)`、`.I_video_in_data(S_osd_data)` |

插入点为什么选这里（答辩会说）：

```
SC520 → isp_top(自研边缘算法) → data_96→128 → video_in → DDR → video_out
      → hdmi_mixer → 【osd_overlay 新增】→ hdmi_tx → HDMI
```

- **不能放在 `isp_top` 里**：那里的数据还要过自研边缘检测，Logo 会被"边缘化/卡通化"。
- 放在 `hdmi_mixer` 之后 = 像素域最后一级，逻辑最简单、对上游零影响、只加 1 拍延迟。

#### (2) `OUR_project/hdmi_base_src/td_project/OUR_p1_colorbar.al`（2 处）

| 位置 | 改了什么 |
|---|---|
| 第 **387** 行起 | 新增 `../../../rtl/osd_overlay.v` 条目（`CompileOrder=62`，参与综合/P&R） |
| 第 **395** 行起 | 新增 `../../../rtl/osd_logo_rom.v` 条目（`CompileOrder=63`，参与综合/P&R） |

> 也就是说：**TD 打开工程就能直接编译，不需要你手动 Add Files**。
> 约束一个都不用改（`pin.adc`、`OUR_p1_colorbar.sdc` 均未改动）。
>
> 如果你们真实工程在别的位置（`.al` 里记的 `E:/fpga/contest_s2/...`），那边还没有这两条登记，
> 跑一次补丁脚本即可（幂等、自动备份，已验证与手工改动逐字节一致）：
>
> ```bash
> python tools/patch_al_osd.py <你的>/OUR_p1_colorbar.al
> ```

### 3. 验证与工具（不进综合，只用于自检/复现）

| 文件 | 作用 |
|---|---|
| `tb/unit/tb_osd_overlay.v` | 自检 testbench：产生 720p 时序 + 逐拍断言 + 整帧哈希比对 |
| `tb/unit/osd_tb_expect_1280x720.vh` | 黄金模型期望值（720p），生成器产出 |
| `tb/unit/osd_tb_expect_320x240.vh` | 同上（320×240 小帧，仿真加速用） |
| `tools/gen_osd_assets.py` | 资源生成器 + 黄金模型（ROM / 字模 / 期望值 / 预览图） |
| `tools/osd_overlay.tpl.v` | `osd_overlay.v` 的模板（生成器输入） |
| `tools/raw2png.py` | 把仿真导出的裸 RGB 帧转 PNG |
| `tools/osd_preview.png` | 黄金模型渲染的 720p 预览 |
| `tools/osd_sim_frame.png` | **仿真器算出来的真实 RTL 输出帧**（1280×720） |
| `tools/osd_sim_crop.png` | 上面那张图左上角的 3 倍放大（看清字和 Logo） |
| `tools/patch_al_osd.py`（仓库根目录） | 把两条 OSD 文件登记打进任意 `OUR_p1_colorbar.al`（幂等，自动备份） |

另外同步了两份文档到 `docs/`：`11_复用与自研清单.md`（加了"复用边界怎么判"）、`13_差距分析与后续任务清单.md`（B1–B4/扩展/进阶现状与 11/4 前日程）。

---

## 二、屏幕上看到什么

左上角 `(16,16)` 起，一块 **208×156** 的小面板：

```
┌──────────────────────────────┐  ← 深蓝 #1C2D4E 描边，2px
│   ▲ 安路标识（146×94）        │  ← 深蓝 A + 红色渐变条，2bit/像素
│   ANLOGIC                    │  ← 5×7 点阵，2 倍放大
│   PH1P35 720P                │  ← 同上
└──────────────────────────────┘  ← 底板浅灰 #E0E0E0
```

- 位置/尺寸/描边宽度/文字内容**全部是模块参数**（`PANEL_X/Y/W/H/BW`、`LOGO_X/Y`、`TEXT_X/Y0/Y1`、`CHAR_NUM`），改一行就能挪。
- 为什么要底板+描边：自研边缘图是**黑白线条**，纯白/纯黑背景上只画 Logo 会糊掉；加浅灰底板后两种模式下都清楚。这是和官方例程最直观的区别之一。
- 输出相对输入**固定延迟 1 拍**，`vs/hs/de/data` 同步延迟，720p 时序关系不变。

---

## 三、怎么编译、怎么上板

1. TD 6.2.1 打开 `src/p1_colorbar/OUR_project/hdmi_base_src/td_project/OUR_p1_colorbar.al`；
2. 直接跑 `syn_1` → `phy_1`（新增文件已在文件列表里，不用再加）；
3. 生成 bit 流烧写，接 HDMI 显示器，上电即可看到左上角面板。

> 想看资源/时序：GUI 里跑完 `syn_1` 和 `phy_1` 后，`gate.area` / `phy.area` / `final_timing.rpt` 就是权威数字。

---

## 四、验证做了什么（"能不能跑通、符不符合要求"）

本机没有 ModelSim/Questa，我搭了一条能真正跑起来的验证链，全部在本机跑过：

### 1) 官方工具链编译检查 —— 通过

TD 6.2.1 批处理打开工程（全量解析所有源文件）：

```
PRJ-1401 : Successfully analyzed 97 source files.
```

**97 个源文件（含新增的 2 个 OSD 文件）零错误**通过安路自己的解析器。
单独把 OSD 两个文件拎出来解析，也是 **0 error / 0 warning**。

### 1.5) TD 抓到的两个真实隐患（已修，这就是"必须用真工具链"的原因）

| # | TD 报的东西 | 后果 | 修法 |
|---|---|---|---|
| 1 | 无报错，但 lint 发现 `(S_ly[6:0] << 5)` 在"自决定位宽"上下文里只有 7 bit | 部分工具会按 7bit 截断 → Logo 地址算错 → 上板花屏 | 改成显式 14bit 补零扩位 `{2'b00, S_ly}` 再移位 |
| 2 | `HDL-5007 WARNING: literal value 'h208 truncated to fit in 9 bits`（`'A'` 那一行） | 字模 `case` 的键是 9bit 放不下 `'A'=0x41`，字符码被截断。**这次仿真碰巧同向截断所以没暴露，但属于定时炸弹**：以后加任何低 6 位重复的字符就会串码 | 字符码从 6bit 扩到 7bit，键从 9bit 扩到 10bit |

修完之后 TD 对 OSD 文件的解析告警数 = **0**。这两条也写进了 RTL 注释里，防止以后改回去。

### 2) 独立 Lint（Verilator 5.49，`-Wall`）—— 零告警

```
verilator --lint-only -Wall --top-module osd_overlay rtl/osd_overlay.v rtl/osd_logo_rom.v
→ 0 warning / 0 error
```

### 3) RTL 功能仿真 —— 逐像素比特级一致

用 Verilator 把**真正的 RTL** 编译成可执行仿真，跑 3 帧完整 720p：

```
[OSD-TB] frame #0  1280x720  de pixels=921600
[OSD-TB] border : got 1440    exp 1440
[OSD-TB] plate  : got 23613   exp 23613
[OSD-TB] navy   : got 4830    exp 4830
[OSD-TB] red    : got 2565    exp 2565
[OSD-TB] hash   : got 2196929688  exp 2196929688
[OSD-TB] errors : 0
...  帧 #1、#2 同上
[OSD-TB] RESULT: *** PASS (3 frames) ***
```

检验的 6 件事：

| # | 检查 | 结果 |
|---|---|---|
| 1 | `O_vs/O_hs/O_de` 严格等于输入延迟 1 拍 | 通过（`err=0`） |
| 2 | 面板**之外**的像素一个 bit 都不改（透传） | 通过（92 万点逐点比对） |
| 3 | 面板**之内**只出现 3 种 OSD 颜色 | 通过 |
| 4 | 描边/底板/深蓝/红 四类像素计数 = 黄金模型 | 通过（1440 / 23613 / 4830 / 2565） |
| 5 | **整帧 921600 像素的 32bit 滚动哈希** = 黄金模型 | 通过（`2196929688`） |
| 6 | 连续 3 帧（验证 `vs` 帧对齐跨帧稳定） | 通过 |

> 哈希一致 = 921600 个像素**逐点相同**，这不是"看着像"，是比特级等价。

### 4) 仿真画面（`tools/osd_sim_frame.png`）

上图是把仿真器输出的第 2 帧原样存成 PNG 得到的——是 **RTL 算出来的画面**，不是效果图。背景的彩条是 testbench 的固定测试图样（用来同时检验透传和可读性）。

### 5) 关于门级综合/布线的资源数字

**本机跑不到 `elaborate` 之后**：TD 命令行的 `elaborate` 会抛
`Assertion failed: GlobalDesign.chip() != nullptr (macrolib.cpp:1283)`，
因为我没法在批处理里把器件库正确初始化（`import_device` 的 package 名对不上）。
我用一个 **4bit 计数器**的最小工程复现了同一个断言 —— 证明这跟本项目的代码**无关**，是 TD 命令行模式的限制。

所以资源/时序的权威数字请在 GUI 里点一次 `syn_1`/`phy_1` 就有了。参考量级：

- 官方 `lab_ex3`（带 OSD）相对 `lab_ex1`（无 OSD）：LUT6 **+2667**，ERAM **+1**（39→40）；
- 我们的 OSD：ROM 只有 **12,800 bit**（2bit×6400，官方是 24bit×25600≈614 kbit），
  逻辑只有坐标比较 + 一个 5×7 字模查表 + 一级输出寄存器，**预期远小于官方的 2667 LUT**（量级在几百 LUT 内）。

---

## 五、红线（合规）—— 这块我逐条对过原文

官方原文（`选题指南` P35）：

> **"参赛作品必须为原创，不得抄袭、盗用他人作品，且版权未移交他人。"**

另注：`"所有算法、控制逻辑及数据处理流程应在 FPGA 中自主编程实现"` 这句**只出现在选题一 1.3**，选题二没有这句；但即使按最严口径，我们也完全达标。

### 我们是怎么做的

| 层面 | 做法 | 判定 |
|---|---|---|
| 器件/IP 驱动（PLL、MIPI、DDR、HDMI PHY） | 用厂商 IP | 允许（属于平台能力） |
| 参考架构（`video_in/video_out/hdmi_mixer` 的骨架） | 参考安路参考设计 | 允许（属于参考设计） |
| **OSD 渲染逻辑** | **100% 自写**：坐标计数器、参数化几何、掩膜/描边、自建 5×7 字模、优先级仲裁、旁路流水 | 原创 |
| "安路"标识**位图数据** | 取自官方例程的位图，**重新量化成 2bit/像素并自行重编码为 ROM** | 主办方标识素材，属"呈现内容"，非逻辑 |

关键点：**我们没有把官方的 `hdmi_mixer.v` / `anlogic_logo_rom.v` 搬进工程**——
`OUR_p1_colorbar.al` 的文件列表里没有这两个文件，交付代码里也没有。官方例程只在本地当"对照参考"，用来确认配色和 Logo 图形。

### 和官方 lab_ex3 OSD 的客观差异（可以用来回答"你做了什么"）

| 维度 | 官方 lab_ex3 | 我们 |
|---|---|---|
| 代码组织 | 塞在 `hdmi_mixer.v` 里，和混流逻辑混在一起 | 独立模块 `osd_overlay.v`，接口只有 vs/hs/de/data |
| 版面几何 | 坐标写死 | 位置/尺寸/描边/行距全参数化 |
| 可读性保障 | 整像素硬替换，无底板 | 浅灰底板 + 深蓝描边，黑白边缘图/彩色图上都能读 |
| 内容 | 只有 Logo（+ 计数器字符） | Logo + 自建 5×7 字模两行文案（`ANLOGIC` / `PH1P35 720P`） |
| 数据编码 | 24bit/像素，~614 kbit | 2bit/像素，12.8 kbit，**重采样 + 两色量化** |
| 流水 | 组合直通 | 显式单拍寄存，vs/hs/de/data 同步延迟 |
| 面积 | +2667 LUT / +1 ERAM | 预期远小（ROM 位宽少 ~48 倍） |

---

## 六、答辩口径（3 句话，背下来）

1. "OSD 是我们自己写的一个独立模块，插在 `hdmi_mixer` 和 `hdmi_tx` 之间，只加 1 拍延迟，不动上游任何东西。"
2. "'安路'标识的**图形**取自主办方素材，但**编码和绘制是我们重做的**：24bit 多色重采样成 2bit 两色，ROM 自己生成，字模自己画。"
3. "渲染逻辑——坐标、掩模、描边、优先级、流水——全部自研，官方例程只当对照参考，没有一行移植。"

---

## 七、怎么复现（给队友）

```bash
# 1) 重新生成 OSD 资源（改 Logo/文案后必须跑）
#    需要官方 lab_ex3 里的 anlogic_logo_rom.v 作为位图来源
python src/p1_colorbar/tools/gen_osd_assets.py <官方>/anlogic_logo_rom.v

# 2) 仿真（本机用 Verilator 5.x + 任一 C++ 编译器）
#    小帧快速版：加 -DSMALL_FRAME；跑真帧：去掉它
verilator --cc --exe --main --timing -DSMALL_FRAME \
    -I src/p1_colorbar/tb/unit --top-module tb_osd_overlay \
    src/p1_colorbar/rtl/osd_overlay.v src/p1_colorbar/rtl/osd_logo_rom.v \
    src/p1_colorbar/tb/unit/tb_osd_overlay.v
#  （有 ModelSim 的话直接建工程编这 3 个文件即可，tb 是标准可综合风格写法）

# 3) 导出真实画面
#    加 -DDUMP_FRAME 重新编译，跑完得到 osd_frame.raw
python src/p1_colorbar/tools/raw2png.py osd_frame.raw osd_frame.png 1280 720
```

改了文案/位置以后：**必须先重跑生成器**，否则 `osd_tb_expect_*.vh` 里的期望值还是旧的，仿真会 FAIL——这是设计上的防错，不是 bug。

---

## 八、顺手踩到并已修好的一个坑（跟 OSD 无关，但会挡住出片）

`OUR_project/hdmi_base_src/td_project/OUR_p1_colorbar.al` 里登记了

```
../user_source/ip_source/divider/divider.ipc
```

但 **这个文件在 zip 里不存在**（目录里只有 `divider_gate.v`），而 `awb.v` 第 165 行实例化了 `divider`。综合时报：

```
HDL-8007 ERROR: divider ... is a black box in awb.v
```

**整工程重新综合会因此停下**（导出 zip 时漏了这个 IP 的配置文件）。

### 已解决（2026-10-17）

`divider.ipc` 在官方 `HX1P35A_Contest_202606\7_lab_ex_2026_nosoft\安路比赛文档2026.zip` 的 `lab_ex3_osd` 工程里就有，695 字节。已恢复两份：

```
user_source/ip_source/divider/divider.ipc
user_source/hdl_source/isp/awb/divider/divider.ipc
```

内容为 32 位分母 / 48 位分子、无符号、50 级流水线，`GeneratedFiles → GateVerilog = divider_gate.v`，与目录里现成的 `divider_gate.v` 正好配对。恢复后综合、布局布线、bitgen 全部一次通过，产出 `OUR_p1_colorbar.bit`（1,789,539 B）。

**上板步骤与实测数据见 [`15_上板实测指南.md`](./15_上板实测指南.md)。**

---

## 九、按"官方优先"改为官方实现（2026-10-17 23:41）

> 依据：**"东西都要用官方的，官方有的都要用官方的"**。官方 lab_ex3 本身就是 OSD 例程，所以 B4 改用官方实现作为交付默认。

### 9.1 改了哪几个文件

| 动作 | 文件 | 说明 |
|---|---|---|
| **替换** | `user_source/hdl_source/hdmi_mixer.v` | 6,906 B（纯透传 + debug 图案）→ **41,314 B 官方版**（内部自带 Logo 与文字 OSD），与官方 `lab_ex3_osd` 的 md5 `51158a17…` **字节一致**。原文件备份 `hdmi_mixer.v.bak_before_official_osd` |
| **新增** | `user_source/hdl_source/anlogic_logo_rom.v` | 298,506 B，官方 25bit/像素 Logo ROM，未改动 |
| **新增** | `user_source/hdl_source/osd_char_lib.v` | 38,988 B，官方点阵字库（含"安路"中文），未改动 |
| **改 3 处** | `OUR_p1_colorbar.al` | 登记上面两个新文件，CompileOrder 64 / 65 |
| **改 1 处** | `design_top_wrapper.v` | `u_osd_overlay` 例化改为 `` `ifdef OSD_SELF_DEV `` 分支；**默认不定义** → 走 `assign` 直连（OSD 由官方 mixer 内部完成） |

端口是完全兼容的（`I_video_*` / `I_debug_status` / `O_video_rd_en` / `I_video_rd_data` / `O_hdmi_*` 一字不差），所以是**真正的 drop-in 替换**，顶层其余连线一行都没动。

### 9.2 官方 vs 自研（同工程、同约束实测）

| 指标 | 官方实现（现行） | 自研实现（备选） |
|---|---|---|
| 屏幕上 | 左上 (0,0) 160×160 Logo + (375,120) 黄色 `安路 CNT: 数字` | (16,16) 208×156 面板 + Logo + 两行英文 |
| OSD 本体 | 2,753 LUT + 229 FF + 1 DSP | **593 LUT + 95 FF** |
| 全片 slice | 16,710（**78.76%**） | 14,654（69.07%） |
| Setup WNS | **+0.005 ns** | **+0.787 ns** |
| Hold WNS | +0.020 ns | +0.020 ns |
| bit sha256（前 16） | `1f4258a2185eaf04` | `145bf69c78bd7361` |
| 仿真验证 | 未单独跑（直接用官方代码） | 3 帧 720p 逐像素哈希一致 |

### 9.3 两个必须知道的事实

1. **官方版时序只剩 5 ps。** 根因是官方 `hdmi_mixer.v:619` 用 DSP 乘法器 `S_logo_y * LOGO_W` 组合算 ROM 地址，像素域 13.33 ns 预算里走 15.7 ns。综合阶段是 **-2.475 ns（24 条违例）**，靠布局布线拉到 +0.005。这不是我们改坏的——**官方 lab_ex3 自己综合也是 -1.296 ns，布完 +0.103 ns**，同一套路。正式出片前建议跑 `MultiSeed.tcl`；想把余量拿回来，把那行换成移位即可（行为不变）。
2. **资源涨了 4.6 倍**：官方 OSD 是完整 160×160×25bit 位图 + 中文字库，吃 2,753 LUT，全片从 69% 涨到 78.76%。后面再加扩展功能（模式切换/参数面板）时，这块余量要算进去。

### 9.4 怎么切回自研

在 `design_top_wrapper.v` 里（或工程 Verilog Define 里）加一行：

```verilog
`define OSD_SELF_DEV
```

然后**必须重新综合 + 布局布线**（两者资源差 2,500 slice、时序差 0.78 ns，不能混用旧 bit）。

### 9.5 关于"原创性"的一句提醒

官方 lab_ex3 是**给你照着改的参考例程**，直接用它的 OSD 属于"打底"，评审看的是后面 A2/A3 的算法自研与进阶功能。如果担心"基础部分太像例程"，自研分支（`OSD_SELF_DEV`）随时能切回来——两条路都在仓库里，数据也都留了。
