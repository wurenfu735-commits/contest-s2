# TD 编译结果一键判读
# 用法: pwsh -File check_build.ps1
# 判读内容：bit 是否更新 / 资源占用 / 时序 WNS / 是否有错误 / 新文件是否参与编译
$ErrorActionPreference = "Continue"
# 路径按脚本位置推导，不再绑死某台机器
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
$tdp  = "$repo\src\p1_colorbar\OUR_project\hdmi_base_src\td_project"
$base = "$repo\src\p1_colorbar\bitbank\OUR_p1_colorbar_v3_debounce_fix.bit"

Write-Output "================ TD 编译结果判读 ================"

# ---- 1) bit 文件 ----
Write-Output ""
Write-Output "[1] bit 文件"
$bit = "$tdp\OUR_p1_colorbar_Runs\phy_1\OUR_p1_colorbar.bit"
if (Test-Path $bit) {
    $b = Get-Item $bit
    $age = [int]((Get-Date) - $b.LastWriteTime).TotalMinutes
    Write-Output ("   路径: $bit")
    Write-Output ("   时间: " + $b.LastWriteTime + "   (距今 $age 分钟)")
    Write-Output ("   大小: " + [int]($b.Length / 1KB) + " KB")
    if ($age -le 120) { Write-Output "   => OK：是新生成的 bit" }
    else { Write-Output "   => 注意：bit 不是新生成的（可能没真正重跑，检查是否 reset）" }
} else { Write-Output "   !! 未找到 bit 文件" }

# ---- 2) 最新编译日志 ----
Write-Output ""
Write-Output "[2] 最新编译日志"
$logs = Get-ChildItem -LiteralPath $tdp -Filter "td_*.log" | Sort-Object LastWriteTime -Descending
if ($logs.Count -eq 0) { Write-Output "   !! 没找到 td_*.log"; exit }
$log = $logs[0].FullName
Write-Output ("   " + $logs[0].Name + "   (" + $logs[0].LastWriteTime + ")")
$txt = Get-Content -LiteralPath $log

# ---- 3) 新文件是否参与编译 ----
Write-Output ""
Write-Output "[3] 新 RTL 是否参与编译"
foreach ($f in @("edge_adaptive_96.v", "edge_adaptive_pixel.v", "edge_rgb_adapter.v")) {
    $hit = $txt | Select-String -Pattern ([regex]::Escape($f)) -SimpleMatch | Select-Object -First 1
    if ($hit) { Write-Output ("   OK  " + $f) } else { Write-Output ("   ??  " + $f + " 未出现在日志中") }
}

# ---- 4) 资源占用 ----
Write-Output ""
Write-Output "[4] 资源占用"
$keys = @("#lut6", "#reg", "#eram", "#eram20k", "#dsp", "#IO", "#slice reg", "#slice ")
$found = $false
foreach ($k in $keys) {
    $m = $txt | Select-String -Pattern ([regex]::Escape($k)) | Select-Object -Last 1
    if ($m) { Write-Output ("   " + $m.Line.Trim()); $found = $true }
}
if (-not $found) { Write-Output "   !! 日志里没找到资源统计（可能被 GUI 写到别处）" }

# ---- 5) 时序 ----
Write-Output ""
Write-Output "[5] 时序（Setup / Hold）"
$tim = $txt | Select-String -Pattern "Setup\s*:|Hold\s*:" | Select-Object -Last 4
if ($tim) { $tim | ForEach-Object { Write-Output ("   " + $_.Line.Trim()) } }
else { Write-Output "   !! 未找到时序行" }
Write-Output "   注意：这是【全设计最差路径】，多半落在 50M 域（周期 20ns）。"
Write-Output "         算法跑在 HDMI_PIXEL_CLK(74.25M, 周期 13.468ns) 域，必须单独确认该域 WNS。"

# ---- 5b) 各时钟域时序 ----
Write-Output ""
Write-Output "[5b] 各时钟域 WNS"
$tfiles = Get-ChildItem -LiteralPath "$tdp\OUR_p1_colorbar_Runs\phy_1" -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match "timing|summary" } | Sort-Object LastWriteTime -Descending | Select-Object -First 4
if ($tfiles) {
    foreach ($tf in $tfiles) {
        $hit = Get-Content -LiteralPath $tf.FullName -ErrorAction SilentlyContinue |
            Select-String -Pattern "WNS|HDMI_PIXEL|HDMI_SERIAL|sys_clk_50m|Slack" | Select-Object -First 14
        if ($hit) {
            Write-Output ("   --- " + $tf.Name)
            $hit | ForEach-Object { Write-Output ("       " + $_.Line.Trim()) }
        }
    }
} else {
    Write-Output "   未找到 timingsummary/timing 报告"
    Write-Output "   可在 TD GUI: 打开 phy_1 -> Report Timing，分别看 HDMI_PIXEL_CLK 与 sys_clk_50m 域的 WNS"
}

# ---- 6) 错误 ----
Write-Output ""
Write-Output "[6] 错误与关键警告"
$errs = $txt | Select-String -Pattern "ERROR|PRJ-88|PRJ-92|SYN-9|PHY-9" | Select-Object -First 15
if ($errs) { $errs | ForEach-Object { Write-Output ("   " + $_.Line.Trim()) } }
else { Write-Output "   OK：没有 ERROR 行" }

# ---- 7) 与上一版基线对比 ----
Write-Output ""
Write-Output "[7] 与上一版基线对比（官方 OSD + v4：slice 16710 / 78.76%，Setup WNS +0.005ns）"
Write-Output "   v5 只改了阈值常量（换成 4 个 parameter），结构未变 → slice 应基本持平（±50 内）"
Write-Output "   若 slice 或 WNS 与上版差异很大 => 说明改动范围超出预期，先查是不是误改了别处"

Write-Output ""
Write-Output "================ 判读结束 ================"
