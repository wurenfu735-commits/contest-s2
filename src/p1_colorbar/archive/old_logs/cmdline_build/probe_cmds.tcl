open_project OUR_p1_colorbar.al
puts "===CMD_RESET==="
foreach c [lsort [info commands]] { if {[string match "*reset*" $c]} { puts "  $c" } }
puts "===CMD_RUN==="
foreach c [lsort [info commands]] { if {[string match "*run*" $c] || [string match "*launch*" $c]} { puts "  $c" } }
puts "===STATUS==="
if {[catch {flow_status} e]} { puts "flow_status err: $e" }
exit
