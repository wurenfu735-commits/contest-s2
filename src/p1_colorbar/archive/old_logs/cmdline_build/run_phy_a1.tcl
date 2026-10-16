open_project OUR_p1_colorbar.al
if {[catch {reset_runs phy_1 -f} e]} { puts "reset phy_1 err: $e" }
launch_runs phy_1
after 300000
exit
