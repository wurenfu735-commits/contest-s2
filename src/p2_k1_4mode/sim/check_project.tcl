cd {E:/fpga/OUR_K1_4mode/OUR_project/hdmi_base_src/td_project}
import_device ph1_35p.db -package PH1P35MDG324 -speed 3
if {[catch {open_project OUR_K1_4mode.al -noanalyze} err]} {puts stderr $err; exit 1}
puts {PROJECT_OK}
exit 0
