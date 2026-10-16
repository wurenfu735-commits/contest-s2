# 逐图运行 RTL 仿真并与黄金模型向量比对（支持指定分辨率）
# 用法: pwsh -File verify_all.ps1 -W 1280 -H 720
param(
    [int]$W = 640,
    [int]$H = 360
)
$ErrorActionPreference = "Continue"
$ms   = "E:\app\Software\work\modelsim\win64"
$rtl  = "E:\fpga\contest_s2\src\p1_colorbar\rtl\edge_adaptive_pixel.v"
$tbT  = "E:\fpga\contest_s2\src\p1_colorbar\tb\unit\tb_edge_adaptive_pixel.v"
$tbG  = "E:\fpga\contest_s2\src\p1_colorbar\tb\gen"
# 仿真需一起编译：块 RAM IP 的 RTL + ERAM 原语的行为模型
$ipRtl = "E:\fpga\contest_s2\src\p1_colorbar\OUR_project\hdmi_base_src\user_source\hdl_source\isp\demosaic_4x_2_0\blk_mem_gen_zhenghe"
$eramModel = @(
    "$ipRtl\blk_mem_gen_zhenghe.v",
    "$ipRtl\RTL\ram_d32970204f32.v",
    "E:\fpga\contest_s2\sim\golden\ph1p_eram_sim_model.v"
)
$out  = "E:\fpga\contest_s2\sim\golden\out"
$py   = "E:\app\Software\daily\python\python.exe"
$env:PYTHONIOENCODING = "utf-8"
$env:PYTHONUTF8 = "1"

Write-Output "===== 分辨率 ${W}x${H} ====="

# tb 模板：统一输出文件名 + 设定分辨率
$tmpl = (Get-Content -LiteralPath $tbT -Raw) -replace 'rtl_edge_out\.txt', 'rtl_out.txt'
$tmpl = $tmpl -replace 'parameter IMG_W\s*=\s*\d+', "parameter IMG_W     = $W"
$tmpl = $tmpl -replace 'parameter IMG_H\s*=\s*\d+', "parameter IMG_H     = $H"

Set-Location -LiteralPath $out
$summary = @()
$allPass = $true

foreach ($pat in @("colorbar", "checker", "gradient", "gray8")) {
    $tbRun = "$tbG\tb_run_$pat.v"
    $tbSrc = $tmpl `
        -replace 'gray_(colorbar|checker|gradient|gray8)\.txt', "gray_$pat.txt" `
        -replace 'edge_(colorbar|checker|gradient|gray8)\.txt', "edge_$pat.txt"
    Set-Content -LiteralPath $tbRun -Value $tbSrc -Encoding ASCII

    Remove-Item -LiteralPath "$out\rtl_out.txt" -Force -ErrorAction SilentlyContinue
    # 一起编译 ERAM 原语的仿真行为模型（综合时由 TD arch 库提供真原语）
    # 注意：编译错误必须显式中止——否则 vsim 会沿用上一次编译的旧模块，产生"假 PASS"
    $vlogOut = & "$ms\vlog.exe" -work work $rtl $eramModel $tbRun 2>&1
    $vlogErr = $vlogOut | Select-String -Pattern "\bError\b" | Select-Object -First 4
    if ($vlogErr) {
        $summary += "[$pat] 编译失败（未跑仿真）"
        $vlogErr | ForEach-Object { $summary += ("      " + $_.Line.Trim()) }
        $allPass = $false
        continue
    }
    & "$ms\vsim.exe" -c -do "run -all; quit -f" work.tb_edge_adaptive_pixel 2>&1 | Out-Null

    if (-not (Test-Path -LiteralPath "$out\rtl_out.txt")) {
        $summary += "[$pat] 仿真未产生输出文件"; $allPass = $false; continue
    }

    $res = & $py -c @"
import sys
sys.stdout.reconfigure(encoding='utf-8', errors='replace')
def _i(s):
    return 0 if s.lower() in ('x','z') else int(s)
def loadh(p):
    return [0 if l.strip().lower() in ('x','z') else int(l.strip(),16)
            for l in open(p, encoding='ascii', errors='replace') if l.strip()]
def load1(p):
    return [_i(l.strip()) for l in open(p, encoding='ascii', errors='replace') if l.strip()]
def load3(p):
    v=[]
    for l in open(p, encoding='ascii', errors='replace'):
        q=l.split()
        if len(q)>=3: v.append((_i(q[0]), _i(q[1]), _i(q[2])))
    return v
OUT=r'$out'
pat='$pat'
W,H,off=$W,$H,3
rtl=load3(OUT+r'\rtl_out.txt')
exp=load1(OUT+r'\edge_'+pat+'.txt')
mag=loadh(OUT+r'\mag_'+pat+'.txt')
ee=me=mm=0; first=None
for row in range(H):
    for j in range(off, W):
        k=row*W+j; idx=row*W+j-off
        if k>=len(rtl) or idx>=len(exp): continue
        mm+=1
        if rtl[k][0]!=exp[idx]:
            ee+=1
            if first is None: first=(row, idx%W, rtl[k][0], exp[idx])
        if rtl[k][1]!=mag[idx]: me+=1
print(f'{ee}|{me}|{mm}|{first}')
"@ 2>&1
    $f = $res -split '\|'
    $tag = if ($f[0] -eq "0" -and $f[1] -eq "0") { "PASS" } else { "DIFF"; $allPass = $false }
    $summary += ("[{0,-9}] edge误差={1,-6} mag误差={2,-6} 比对={3,-8} 首错={4}  {5}" -f $pat, $f[0], $f[1], $f[2], $f[3], $tag)
}

Write-Output "===== 汇总（行内偏移 3） ====="
$summary | ForEach-Object { Write-Output $_ }
Write-Output $(if ($allPass) { "*** 全部通过 ***" } else { "*** 存在差异 ***" })

