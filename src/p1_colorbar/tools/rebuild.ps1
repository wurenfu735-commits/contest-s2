# rebuild.ps1 —— 一条命令重建：syn_1 → phy_1 → 结果判读
#
# 用法：
#   pwsh -File src\p1_colorbar\tools\rebuild.ps1
#   pwsh -File src\p1_colorbar\tools\rebuild.ps1 -BitName OUR_b5_mixerlite_logo2c   # 顺便归档到 bitbank
#   pwsh -File src\p1_colorbar\tools\rebuild.ps1 -Tag v5_darkfloor                  # 等价于 -BitName OUR_v5_darkfloor
#
# 前置（脚本会自己检查，不满足就退出）：
#   1. TD GUI（td.exe）必须已关闭 —— 否则它持有工程锁，且会用内存旧态覆盖外部改动
#   2. td_project 下不能有 .lock.f
#   3. TD 安装路径可用环境变量 TD_BIN 覆盖（默认下面那个）
#
# 脚本会自己做的事（别手改）：
#   - 确保 rtl/mixer_lite.v 已登记进 Runs\{syn_1,phy_1}/OUR_p1_colorbar.prj（流程读 .prj 不读 .al）
#   - 归档时拒绝覆盖已存在的位流（位流大小恒定，覆盖后无法凭大小区分版本）
#
# 实测耗时：syn ≈ 2m20s，phy ≈ 2m30s。

param(
    [string]$Tag = "",
    [string]$BitName = "",
    [switch]$SkipCheck
)

$ErrorActionPreference = 'Stop'

$repo  = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
$runs  = "$repo\src\p1_colorbar\OUR_project\hdmi_base_src\td_project\OUR_p1_colorbar_Runs"
$tdbin = if ($env:TD_BIN) { $env:TD_BIN } else { "C:\anlogic\TD_6.2.1_Engineer_6.2.168.116\bin" }
$exe   = Join-Path $tdbin "td_commands_prompt.exe"
$bit   = "$runs\phy_1\OUR_p1_colorbar.bit"

function Fail($msg) {
    Write-Output ""
    Write-Output "!! $msg"
    exit 1
}

Write-Output "================ TD 重建 ================"
Write-Output "仓库: $repo"
Write-Output "TD  : $exe"

# ---------- 0) 前置检查 ----------
if (-not (Test-Path $exe)) {
    Fail "找不到 td_commands_prompt.exe：$exe`n   请设置 `$env:TD_BIN 指向 TD 的 bin 目录"
}

$tdProc = Get-Process td -ErrorAction SilentlyContinue
if ($tdProc) {
    Fail ("TD GUI 正在运行（td.exe PID " + ($tdProc.Id -join ",") + "）。`n" +
          "   请先完全退出 TD（不是最小化），确认进程消失后再跑本脚本。`n" +
          "   原因：TD 打开工程期间会持有锁，并用内存旧态回滚外部改动（docs/03 铁律）。")
}

$locks = Get-ChildItem -Path "$repo\src\p1_colorbar\OUR_project\hdmi_base_src\td_project" -Filter ".lock.f" -Recurse -Force -ErrorAction SilentlyContinue
if ($locks) {
    Fail ("存在残留锁文件，TD 可能未干净退出：`n   " + (($locks | ForEach-Object { $_.FullName }) -join "`n   "))
}

if (-not (Test-Path "$runs\syn_1\run_syn.tcl") -or -not (Test-Path "$runs\phy_1\run_phy.tcl")) {
    Fail "缺少 run_syn.tcl / run_phy.tcl（settings.cfg 流程包装）"
}

Write-Output "前置检查：OK（TD 未运行、无锁、流程脚本齐备）"

# ---------- 0.5) 自愈：确保 mixer_lite.v 已登记进两个 .prj ----------
# 踩过的坑（2026-10-19）：DefaultFlow.tcl 实际读的是
#   OUR_p1_colorbar_Runs\{syn_1,phy_1}\OUR_p1_colorbar.prj（绝对路径），**不是 .al**。
# 所以只往 OUR_p1_colorbar.al 里加文件是没用的 —— 综合会直接报
#   HDL-8007 ERROR: mixer_lite is a black box in design_top_wrapper.v(890)
# 换电脑 / TD 重新生成工程 / 换分支后 .prj 可能变回旧版，这里自动补回来。
$mixerSrc = "$repo\src\p1_colorbar\rtl\mixer_lite.v"
if (-not (Test-Path $mixerSrc)) {
    Fail "找不到 $mixerSrc —— 请先确认 mixer_lite.v 在仓库里（git status 看是否漏提交）"
}

$repoFwd = $repo -replace '\\', '/'
$entryLines = @(
    ('            <File Path="{0}/src/p1_colorbar/rtl/mixer_lite.v">' -f $repoFwd),
    '                <FileInfo>',
    '                    <Attr Name="UsedInSyn" Val="true"/>',
    '                    <Attr Name="UsedInP&R" Val="true"/>',
    '                    <Attr Name="BelongTo" Val="design_1"/>',
    '                    <Attr Name="CompileOrder" Val="66"/>',
    '                </FileInfo>',
    '            </File>'
)
$entry = ($entryLines -join "`n")   # 原 .prj 是纯 LF 换行（实测 CR=0），用 CRLF 会混入 8 个 CR

foreach ($stage in @('syn_1', 'phy_1')) {
    $prjPath = "$runs\$stage\OUR_p1_colorbar.prj"
    if (-not (Test-Path $prjPath)) { Fail "找不到 $prjPath" }
    $txt = Get-Content -LiteralPath $prjPath -Raw
    if ($txt -match 'mixer_lite\.v') {
        Write-Output "   $stage\OUR_p1_colorbar.prj：mixer_lite.v 已在（OK）"
        continue
    }
    # 插在 osd_overlay.v 条目之后；找不到就插在最后一个 </File> 之后
    $pat = '(?s)(<File\s+Path="[^"]*osd_overlay\.v">.*?</File>)(\r?\n)'
    if ($txt -match $pat) {
        $txt = [regex]::Replace($txt, $pat, ('$1$2' + $entry + "`n"), 1)
    } else {
        $lastClose = $txt.LastIndexOf('</File>')
        if ($lastClose -lt 0) { Fail "$prjPath 里找不到 </File>，文件结构异常" }
        $insertAt = $lastClose + '</File>'.Length
        $txt = $txt.Substring(0, $insertAt) + "`n" + $entry + $txt.Substring($insertAt)
    }
    # 备份一次，方便回滚
    Copy-Item -LiteralPath $prjPath -Destination "$prjPath.bak_before_mixer" -Force
    # 必须无 BOM：原 .prj 是 <?xml ...?> 开头且无 BOM，
    # PS 5.1 的 Set-Content -Encoding UTF8 会加 BOM，TD 的 XML 解析器不认。
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($prjPath, $txt, $utf8NoBom)
    Write-Output "   $stage\OUR_p1_colorbar.prj：已补入 mixer_lite.v（原文件备份为 .bak_before_mixer）"
}

# ---------- 1) 综合 ----------
Write-Output ""
Write-Output "---- [1/2] syn_1：read_design → opt_rtl → opt_gate ----"
$t0 = Get-Date
Push-Location "$runs\syn_1"
$logSyn = cmd /c "`"$exe`" run_syn.tcl < nul 2>&1"
Pop-Location
$logSyn | Tee-Object -FilePath "$repo\sim\build_syn.log" | Select-Object -Last 25
if (-not ($logSyn -match "FLOW_RESULT rc=0")) {
    Fail "综合失败（见上面输出与 sim\build_syn.log）"
}
Write-Output ("   综合完成，用时 {0:N1} 分钟" -f ((Get-Date) - $t0).TotalMinutes)

# ---------- 2) 布局布线 + bitgen ----------
Write-Output ""
Write-Output "---- [2/2] phy_1：opt_place → opt_route → bitgen ----"
$t1 = Get-Date
Push-Location "$runs\phy_1"
$logPhy = cmd /c "`"$exe`" run_phy.tcl < nul 2>&1"
Pop-Location
$logPhy | Tee-Object -FilePath "$repo\sim\build_phy.log" | Select-Object -Last 25
if (-not ($logPhy -match "FLOW_RESULT rc=0")) {
    Fail "布局布线/bitgen 失败（见上面输出与 sim\build_phy.log）"
}
Write-Output ("   布线完成，用时 {0:N1} 分钟" -f ((Get-Date) - $t1).TotalMinutes)

if (-not (Test-Path $bit)) { Fail "流程成功但没找到 bit：$bit" }

# ---------- 3) 归档 ----------
if ($Tag -or $BitName) {
    if ($BitName) { $final = $BitName } else { $final = "OUR_$Tag" }
    if ($final -notmatch '\.bit$') { $final = "$final.bit" }
    $dst = "$repo\src\p1_colorbar\bitbank\$final"
    if (Test-Path $dst) {
        Fail ("目标位流已存在，拒绝覆盖：$dst`n" +
              "   位流大小恒为 1,789,539 B，覆盖掉旧版后无法凭大小区分。换个 -BitName，或先手工确认旧版可以删。")
    }
    Copy-Item -LiteralPath $bit -Destination $dst
    $h = (Get-FileHash -LiteralPath $dst -Algorithm SHA256).Hash.ToLower()
    $m = (Get-FileHash -LiteralPath $dst -Algorithm MD5).Hash.ToLower()
    Write-Output ""
    Write-Output "已归档位流：$dst"
    Write-Output "   SHA256 = $h"
    Write-Output "   MD5    = $m"
    Write-Output "   ⚠️ 记得在 src\p1_colorbar\bitbank\位流台账.md 里登记并标上「★ 现行版本」"
}

# ---------- 4) 判读 ----------
if (-not $SkipCheck) {
    Write-Output ""
    & "$PSScriptRoot\check_build.ps1"
}

Write-Output ""
Write-Output "================ 完成 ================"
Write-Output "bit: $bit"
Write-Output "下一步：TD → Tools → Download Center → BitWriter → Add 该 bit → 选 PROGRAM_SRAM → Run（绿三角）"
