open_project OUR_p1_colorbar.al
reset_runs syn_1 -f
reset_runs phy_1 -f
launch_runs syn_1
after 480000
launch_runs phy_1
after 480000
exit
