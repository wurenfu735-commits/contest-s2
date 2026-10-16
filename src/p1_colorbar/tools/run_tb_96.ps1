# run_tb_96.ps1 —— v2 一键验证：edge_adaptive_96（并行版）vs Python 黄金模型
#
# 用法：pwsh -File src\p1_colorbar\tools\run_tb_96.ps1
#
# 判据：并行版输出 par_out.txt 与黄金模型 golden_out.txt（gen_golden_v2.py，与
#       RTL 同锚点/同屏蔽/同迟滞顺序）逐像素一致 = PASS。
# 附带：参照版 edge_adaptive_pixel（RTL 第二形态）同 tb 仿真，仅作参考。
$ErrorActionPreference = 'Stop'
$MS   = "E:\app\Software\work\modelsim\win64"
$ROOT = "E:\fpga\contest_s2"
$RTL  = "$ROOT\src\p1_colorbar\rtl"
$TB   = "$ROOT\src\p1_colorbar\tb\unit\tb_edge_adaptive_96.v"
$IP   = "$ROOT\src\p1_colorbar\OUR_project\hdmi_base_src\user_source\hdl_source\isp\demosaic_4x_2_0\blk_mem_gen_zhenghe"
$MOD  = "$ROOT\sim\golden\ph1p_eram_sim_model.v"
$WORK = "$ROOT\sim\tb96"
$PY   = "E:\app\Software\daily\python\python.exe"

New-Item -ItemType Directory -Force -Path $WORK | Out-Null
Set-Location -LiteralPath $WORK
Remove-Item -LiteralPath "$WORK\par_out.txt", "$WORK\seq_out.txt", "$WORK\golden_out.txt" -Force -ErrorAction SilentlyContinue

Write-Output "=== 1) 编译 ==="
$vlog = & "$MS\vlog.exe" -work work `
    "$RTL\edge_adaptive_96.v" "$RTL\edge_adaptive_pixel.v" `
    "$IP\blk_mem_gen_zhenghe.v" "$IP\RTL\ram_d32970204f32.v" `
    $MOD $TB 2>&1
$vlog | Select-String -Pattern "Error" | Select-Object -First 10
if ($vlog -match "Errors: [1-9]") { Write-Output "!! 编译失败，中止"; exit 1 }
Write-Output "  编译通过"

Write-Output "=== 2) 仿真 ==="
$vsim = & "$MS\vsim.exe" -c -do "run -all; quit -f" work.tb_edge_adaptive_96 2>&1
$vsim | Select-String -Pattern "TB DONE|Failed to find" | Select-Object -First 5
if ($vsim -match "Failed to find|Error loading") { Write-Output "!! 仿真加载失败，中止"; exit 1 }
if (-not (Test-Path "$WORK\par_out.txt")) { Write-Output "!! 未产生输出文件，中止"; exit 1 }

Write-Output "=== 3) 生成黄金模型期望（v4：分段 FLOOR 阈值）==="
$env:PYTHONIOENCODING = "utf-8"; $env:PYTHONUTF8 = "1"
& $PY "$ROOT\tools\gen_golden_v4.py"
if (-not (Test-Path "$WORK\golden_out.txt")) { Write-Output "!! golden 未生成，中止"; exit 1 }

Write-Output "=== 4) 逐像素比对（并行版 vs 黄金模型）==="
& $PY -c @"
import sys
sys.stdout.reconfigure(encoding='utf-8', errors='replace')
W, H = 128, 12
d = r'$WORK'
par = {}
for l in open(d+r'\par_out.txt'):
    q = l.split()
    if len(q) < 5 or q[0].lower() in ('x','z'): continue
    b = int(q[0])
    for k in range(4): par[b+k] = 0 if q[1+k].lower() in ('x','z') else int(q[1+k])
gol = {}
for l in open(d+r'\golden_out.txt'):
    q = l.split()
    if len(q) < 5 or q[0].lower() in ('x','z'): continue
    b = int(q[0])
    for k in range(4): gol[b+k] = 0 if q[1+k].lower() in ('x','z') else int(q[1+k])
def okf(p):
    r, c = divmod(p, W)
    return (8 <= r <= H-1) and (12 <= c <= 115)
common = [p for p in sorted(par) if p in gol and okf(p)]
err = sum(1 for p in common if par[p] != gol[p])
print('  比对 %d 个像素（第 8 行起，含 ±3 传感器噪声图案（与黄金模型逐字同式））' % len(common))
print('  误差 %d 个（%.2f%% 正确）' % (err, 100.0*(len(common)-err)/max(1,len(common))))
sys.exit(0 if err == 0 else 1)
"@
if ($LASTEXITCODE -eq 0) { Write-Output "`n结果：PASS（并行版与黄金模型逐像素完全一致）" } else { Write-Output "`n结果：FAIL" }

