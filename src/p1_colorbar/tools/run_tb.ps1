# 一键编译+仿真指定 tb（省去手敲 vlog/vsim 命令）
# 用法: pwsh -File run_tb.ps1 -Tb tb_lowcontrast_demo
#
# 说明：
#   - tb 会在 tb\ 下递归查找（unit\ / integration\ / gen\ 都可以）
#   - 依赖的 RTL 按 tb 名自动推断（见下表）；未列出的则编译 rtl\ 下全部
#   - 需要向量文件的 tb（tb_edge_adaptive_pixel）请用 sim\golden\verify_all.ps1 跑，
#     因为它同时负责生成向量并做逐像素比对
param(
    [Parameter(Mandatory = $true)][string]$Tb,
    [string]$Root = "E:\fpga\contest_s2\src\p1_colorbar",
    [string]$Work = "E:\fpga\contest_s2\sim\work_tb"
)
$ErrorActionPreference = "Continue"
$ms     = "E:\app\Software\work\modelsim\win64"
$rtlDir = Join-Path $Root "rtl"
$tbDir  = Join-Path $Root "tb"

# ---- 找 tb ----
$tbFile = Get-ChildItem -LiteralPath $tbDir -Recurse -Filter "$Tb.v" -File -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $tbFile) {
    Write-Output "找不到测试台: $Tb"
    Write-Output "现有 tb："
    Get-ChildItem -LiteralPath $tbDir -Recurse -Filter "*.v" -File | ForEach-Object { Write-Output ("  " + $_.FullName.Replace("$tbDir\", "")) }
    exit 1
}
Write-Output ("tb  = " + $tbFile.FullName.Replace("$Root\", ""))

# ---- 推断依赖 RTL ----
$rtlMap = @{
    "tb_edge_adaptive_pixel" = @("edge_adaptive_pixel.v")
    "tb_edge_rgb_adapter"    = @("edge_adaptive_pixel.v", "edge_rgb_adapter.v")
    "tb_lowcontrast_demo"    = @("edge_adaptive_pixel.v", "edge_rgb_adapter.v", "test_pattern_gen.v")
    "tb_ptn"                 = @("vtc_720p.v", "test_pattern_gen.v")
    "tb_debounce"            = @("debounce_btn.v")
    "tb_debounce_real"       = @("debounce_btn.v")
}
# ERAM 原语在仿真时的行为模型（综合时由 TD arch 库提供真原语）
# 仿真需一起编译：块 RAM IP 的 RTL + ERAM 原语的行为模型
$ipRtl = "E:\fpga\contest_s2\src\p1_colorbar\OUR_project\hdmi_base_src\user_source\hdl_source\isp\demosaic_4x_2_0\blk_mem_gen_zhenghe"
$eramModel = @(
    "$ipRtl\blk_mem_gen_zhenghe.v",
    "$ipRtl\RTL\ram_d32970204f32.v",
    "E:\fpga\contest_s2\sim\golden\ph1p_eram_sim_model.v"
)
$needEram  = @("tb_edge_adaptive_pixel", "tb_edge_rgb_adapter", "tb_lowcontrast_demo")
$rtlFiles = @()
if ($rtlMap.ContainsKey($Tb)) {
    $rtlFiles = $rtlMap[$Tb] | ForEach-Object { Join-Path $rtlDir $_ }
    Write-Output ("rtl = " + ($rtlMap[$Tb] -join ", "))
} else {
    $rtlFiles = (Get-ChildItem -LiteralPath $rtlDir -Filter *.v | ForEach-Object { $_.FullName })
    Write-Output "rtl = 全部（未在映射表中找到该 tb）"
}

# ---- 编译 + 仿真 ----
if (-not (Test-Path -LiteralPath $ms)) { Write-Output "!! 找不到 ModelSim: $ms"; exit 1 }
New-Item -ItemType Directory -Force -Path $Work | Out-Null
Set-Location -LiteralPath $Work

Write-Output ""
Write-Output "=== 编译 ==="
$compileList = @($rtlFiles)
if ($needEram -contains $Tb) {
    $compileList += $eramModel
    Write-Output ("eram = ph1p_eram_sim_model.v（ERAM 原语仿真模型）")
}
& "$ms\vlog.exe" -work work @compileList $tbFile.FullName 2>&1 |
    Select-String -Pattern "Error|error|\*\* Error|Compiling" | Select-Object -First 12

Write-Output ""
Write-Output "=== 仿真 ==="
& "$ms\vsim.exe" -c -do "run -all; quit -f" "work.$Tb" 2>&1 | Select-Object -Last 30

