param([switch]$Full)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$iv='E:/fpga/_tools/iverilog/bin/iverilog.exe'
$vvp='E:/fpga/_tools/iverilog/bin/vvp.exe'
if($Full){$env:TEST_HEIGHT='720';$env:SIM_TAG='eram_full'}
else{$env:TEST_HEIGHT='16';$env:SIM_TAG='quick'}
python "$PSScriptRoot/verify.py"
if($LASTEXITCODE -ne 0){throw 'Pixel verification failed'}
& $iv -g2012 -s tb_rgb -o "$root/sim/rgb.vvp" "$root/sim/tb_rgb.v" "$root/sim/ph1p_eram_sim_model.v" "$root/rtl/image_modes4.v" "$root/rtl/window4.v"
if($LASTEXITCODE -ne 0){throw 'RGB compilation failed'}
& $vvp "$root/sim/rgb.vvp" | Tee-Object "$root/sim/rgb_verification.log"
if($LASTEXITCODE -ne 0){throw 'RGB verification failed'}
& $iv -g2012 -s tb_key -o "$root/sim/key.vvp" "$root/sim/tb_key.v" "$root/rtl/k1_mode.v"
if($LASTEXITCODE -ne 0){throw 'Key compilation failed'}
& $vvp "$root/sim/key.vvp" | Tee-Object "$root/sim/key_verification.log"
if($LASTEXITCODE -ne 0){throw 'Key verification failed'}
$hdl="$root/OUR_project/hdmi_base_src/user_source/hdl_source"
# -i leaves the upstream sensor/ISP modules unresolved; this test forces AWB
# outputs and tests only the real adapter, image pipeline, and word packer.
& $iv -g2012 -i -s tb_isp_adapter -o "$root/sim/adapter.vvp" "$root/sim/tb_isp_adapter.v" "$root/sim/ph1p_eram_sim_model.v" "$root/rtl/image_modes4.v" "$root/rtl/window4.v" "$hdl/isp/isp_top.v" "$hdl/data_96bit_to_128bit.v"
if($LASTEXITCODE -ne 0){throw 'Adapter compilation failed'}
& $vvp "$root/sim/adapter.vvp" | Tee-Object "$root/sim/adapter_verification.log"
if($LASTEXITCODE -ne 0){throw 'Adapter verification failed'}
