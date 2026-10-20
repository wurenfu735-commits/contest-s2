$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$tdbin=if($env:TD_BIN){$env:TD_BIN}else{'E:\fpga\bin'}
$exe=Join-Path $tdbin 'td_commands_prompt.exe'
$flow=Join-Path (Split-Path $tdbin -Parent) 'doc/scripts/DefaultFlow.tcl'
python "$PSScriptRoot/generate_runs.py"
if($LASTEXITCODE -ne 0){throw 'Run generation failed'}
foreach($stage in @('syn_1','phy_1')) {
 $dir=Join-Path $root "OUR_project/hdmi_base_src/td_project/OUR_K1_4mode_Runs/$stage"
 $tcl=Join-Path $root "sim/build_$stage.tcl"
 "cd {$($dir.Replace('\','/'))}`nif {[catch {source {$($flow.Replace('\','/'))}} err]} {puts stderr `$err; exit 1}`nputs {FLOW_OK}`nexit 0" | Set-Content $tcl
 & $exe ($tcl.Replace('\','/')) *> "$root/sim/build_$stage.log"
 if($LASTEXITCODE -ne 0){throw "TD $stage failed, see sim/build_$stage.log"}
 if(!(Select-String -LiteralPath "$root/sim/build_$stage.log" -SimpleMatch 'FLOW_OK' -Quiet)){throw "TD $stage did not finish"}
}
$bit=Join-Path $root 'OUR_project/hdmi_base_src/td_project/OUR_K1_4mode_Runs/phy_1/OUR_K1_4mode.bit'
if(!(Test-Path $bit)){throw 'No bitstream generated'}
Copy-Item -LiteralPath $bit -Destination "$root/bitbank/OUR_K1_4mode.bit" -Force
Get-FileHash "$root/bitbank/OUR_K1_4mode.bit"
