# BIT 文件台账（防混淆）

> 用途：自研 bit 与官方预制 bit 混在同一工程目录，按本文档区分，**烧写前认准名字**。
> **现行版本只有一个**：`bitbank\OUR_p1_colorbar_v3_debounce_fix.bit`

## ✅ 一、现行自研 bit（要烧的就是它）

| 归档位置 | 文件名 | 内容 | 上板现象（验收依据） |
|---|---|---|---|
| `bitbank\` | **`OUR_p1_colorbar_v3_debounce_fix.bit`** | P1 v3：自研 720p 时序 + 四图案 + 状态带 + **板载按键** + LED 指示 + **消抖位宽修复**（2026-10-14 22:19） | 八彩条 + 底部状态带（下半绿=PLL 锁）；按 **KEY1** 切图案（棋盘→渐变→灰阶→彩条循环），**LED1 闪 0.2s**、LED3/4 显示图案编号；按 **KEY2** 立即回彩条 |

- 资源：reg 1409 / LUT6 941 / IO 13；时序 Setup WNS 14.071ns、Hold WNS 23ps、0 违规
- 工程内产物位置（重新编译后在这里）：
  `OUR_project\hdmi_base_src\td_project\OUR_p1_colorbar_Runs\phy_1\OUR_p1_colorbar.bit`

## 📜 二、历史版本（已移入 `archive\old_bit\`，**别烧**）

| 文件 | 问题 |
|---|---|
| `OUR_p1_colorbar_v1_20261014.bit` | 按键约束在**扩展口 N2/J14**（照抄官方 pin.adc）→ 板载 KEY 按不到 |
| `OUR_p1_colorbar_v2_onboard_key.bit` | 按键已改板载，但**消抖计数器位宽不足**（16 位装不下 74249）→ 按键完全无响应 |

详见 [`archive\README_旧版说明.md`](../README_旧版说明.md)（含问题原因与取舍记录）。

## ⚠️ 三、官方预制 bit（复制工程时带过来的，勿混淆）

位于工程内 `...\OUR_p1_colorbar_Runs\phy_1\` 与 `best_result\`，文件名都带 `camera_to_dsi_display` 前缀（官方遗留命名）：

| 文件名前缀 | 效果 |
|---|---|
| `camera_to_dsi_display_1280x720_60fps` | 官方 720p60 摄像头实时显示 |
| `camera_to_dsi_display_1280x720_75M_HDMI_COLORBAR_TEST` | 官方 720p 八彩条（HDMI IP 内置 TPG） |
| `camera_to_dsi_display_1080p_colorbar_test` | 官方 1080p 彩条 |
| `camera_to_dsi_display_hdmi_core_tpg` / `_vic0_75m` | 官方 HDMI 核 TPG 测试图 |
| `camera_to_dsi_display_1792x1080_normal` | 官方 1792×1080（非标，普通屏不支持） |
| `camera_to_dsi_display_1600x900_30fps` | 官方 1600×900@30 |
| `camera_to_dsi_display_compress` | 官方压缩码流（与主 bit 同功能） |

## 📌 四、防混淆规则（持续执行）

1. **新 bit 生成后立即归档**：复制到 `bitbank\`，命名 `OUR_<阶段>_<版本>_<日期>.bit`
2. **旧 bit 立即移入** `archive\old_bit\`，并在 `archive\README_旧版说明.md` 追加一行（为什么旧 / 被谁取代）——**`bitbank\` 里永远只留最新可用版**
3. 烧写时认准 **`OUR_` 前缀**；工程目录里同名的 `camera_to_dsi_display_*` 一律是官方遗留，别烧
4. 官方原包（`E:\fpga\HX1P35A_Contest_202606\`）只读；实验全部在 `contest_s2` 侧进行
5. 归档用命令行（原 `.bat` 脚本已移除）：

```powershell
# 取最新的非 compress 版归档（改个版本名即可）
$src = "E:\fpga\contest_s2\src\p1_colorbar\OUR_project\hdmi_base_src\td_project\OUR_p1_colorbar_Runs\phy_1\OUR_p1_colorbar.bit"
$dst = "E:\fpga\contest_s2\src\p1_colorbar\bitbank\OUR_p1_colorbar_v4_<改动说明>.bit"
Copy-Item -LiteralPath $src -Destination $dst -Force
```

> ⚠️ 别归档 `*_compress.bit`（压缩码流变体，烧写工具默认选正式版即可）。
