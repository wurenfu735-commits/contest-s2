# 把我们的工程改名，与官方 lab_ex1 彻底区分（三层改名 + .al 内容同步）
# 用法：先完全关闭 TD，再执行本脚本（双击或在 pwsh 里运行）
# 备份落在 D:\dsh-home\tmp\rename_backup\，可随时回滚

$ErrorActionPreference = "Stop"
$old = "E:\fpga\contest_s2\src\p1_colorbar\hdmi_base"
$new = "E:\fpga\contest_s2\src\p1_colorbar\OUR_project"

if (Get-Process -Name td -ErrorAction SilentlyContinue) {
    Write-Host "TD 正在运行，请先完全关闭 TD 再执行本脚本。" -ForegroundColor Yellow
    exit 1
}
if (-not (Test-Path -LiteralPath $old)) {
    if (Test-Path -LiteralPath $new) { Write-Host "看起来已经改过名了（OUR_project 已存在）。" -ForegroundColor Yellow; exit 0 }
    Write-Host "找不到源目录：$old" -ForegroundColor Red; exit 1
}

# [0] 备份
New-Item -ItemType Directory -Force -Path "D:\dsh-home\tmp\rename_backup" | Out-Null
Copy-Item -LiteralPath "$old\lab_ex1_mipi_hdmi\td_project\camera_to_dsi_display.al"  -Destination "D:\dsh-home\tmp\rename_backup\camera_to_dsi_display.al.bak" -Force
Copy-Item -LiteralPath "$old\lab_ex1_mipi_hdmi\td_project\camera_to_dsi_display.sdc" -Destination "D:\dsh-home\tmp\rename_backup\camera_to_dsi_display.sdc.bak" -Force
Write-Host "[0] 备份完成 -> D:\dsh-home\tmp\rename_backup\"

# [1] 目录改名（外层 + 内层）
Rename-Item -LiteralPath "$old\lab_ex1_mipi_hdmi" -NewName "hdmi_base_src"
Rename-Item -LiteralPath $old -NewName "OUR_project"
$tdp = "$new\hdmi_base_src\td_project"

# [2] 与工程同名的文件/目录改名
Rename-Item -LiteralPath "$tdp\camera_to_dsi_display_Runs" -NewName "OUR_p1_colorbar_Runs"
Rename-Item -LiteralPath "$tdp\camera_to_dsi_display.sdc"  -NewName "OUR_p1_colorbar.sdc"
Write-Host "[2] 目录/文件改名完成"

# [3] .al 内容同步（工程名 + Path），写成无 BOM UTF-8
$alOld = "$tdp\camera_to_dsi_display.al"
$c = [System.IO.File]::ReadAllText($alOld)
$c = $c.Replace('<Name>camera_to_dsi_display</Name>', '<Name>OUR_p1_colorbar</Name>')
$c = $c.Replace('E:/fpga/contest_s2/src/p1_colorbar/hdmi_base/lab_ex1_mipi_hdmi/td_project',
                'E:/fpga/contest_s2/src/p1_colorbar/OUR_project/hdmi_base_src/td_project')
$utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($alOld, $c, $utf8)
Rename-Item -LiteralPath $alOld -NewName "OUR_p1_colorbar.al"
Write-Host "[3] .al 内容更新 + 改名完成"

# [4] 核对
Write-Host "`n=== 新工程目录 ===" -ForegroundColor Cyan
Get-ChildItem -LiteralPath $tdp -Force | Select-Object Mode, Name | Format-Table -AutoSize
$alNew = "$tdp\OUR_p1_colorbar.al"
Write-Host "=== 关键字段 ===" -ForegroundColor Cyan
Select-String -LiteralPath $alNew -Pattern "<Name>|TOP_MODULE|<LABEL>|<MODULE>|colorbar_top.adc" |
    ForEach-Object { "   L{0}: {1}" -f $_.LineNumber, $_.Line.Trim() }
$residual = (Select-String -LiteralPath $alNew -Pattern "camera_to_dsi_display" | Measure-Object).Count
Write-Host ("=== 残留旧工程名引用数: " + $residual)
Write-Host "`n改完请用 TD 打开：$alNew" -ForegroundColor Green
