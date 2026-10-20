cd {E:/fpga/OUR_K1_4mode/OUR_project/hdmi_base_src/td_project/OUR_K1_4mode_Runs/phy_1}
if {[catch {source {E:/fpga/doc/scripts/DefaultFlow.tcl}} err]} {puts stderr $err; exit 1}
puts {FLOW_OK}
exit 0
