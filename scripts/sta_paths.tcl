# Worst setup and hold paths between two node patterns of a compiled
# project, slow 85C corner:
#   quartus_sta -t scripts/sta_paths.tcl DIR REVISION FROM TO [NPATHS]
# FROM/TO match keepers (ports or registers), e.g. {vid_ide_in[*]} {*}.
lassign $quartus(args) dir rev from to npaths
if {$npaths eq ""} {
	set npaths 5
}
cd $dir
project_open $rev
create_timing_netlist
read_sdc
update_timing_netlist
foreach analysis {setup hold} {
	report_timing -$analysis -from [get_keepers $from] -to [get_keepers $to] \
		-npaths $npaths -detail summary -stdout
}
delete_timing_netlist
project_close
