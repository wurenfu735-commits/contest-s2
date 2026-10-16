open_project OUR_p1_colorbar.al
if {[catch {reset_runs syn_1 -f} e]} { puts "reset syn_1 -f err: $e"; if {[catch {reset_runs syn_1} e2]} { puts "reset syn_1 err: $e2" } }
if {[catch {reset_runs phy_1 -f} e]} { puts "reset phy_1 -f err: $e"; if {[catch {reset_runs phy_1} e2]} { puts "reset phy_1 err: $e2" } }
launch_runs syn_1
wait_run syn_1
launch_runs phy_1
wait_run phy_1
exit
