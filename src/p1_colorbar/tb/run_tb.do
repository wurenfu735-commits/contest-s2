# P1 tb 运行脚本（GUI 模式，带波形）
# 用法：ModelSim 里先 File -> Change Directory 到本目录(tb)，
#       然后在命令行输入：  do run_tb.do
# 跑完 Transcript 打印 OK/ALL PASSED，波形窗口显示关键信号
vlib work
vlog -work work ../rtl/vtc_720p.v ../rtl/test_pattern_gen.v ./tb_ptn.v
vsim -voptargs="+acc" work.tb_ptn
add wave clk
add wave rst_n
add wave hsync
add wave vsync
add wave de
add wave hcnt
add wave vcnt
add wave psel
add wave rgb
run -all