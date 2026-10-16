# Device settings - same silicon as MiST and Chameleon V1
set_global_assignment -name FAMILY "Cyclone III"
set_global_assignment -name DEVICE EP3C25E144C8
set_global_assignment -name DEVICE_FILTER_PACKAGE TQFP
set_global_assignment -name DEVICE_FILTER_PIN_COUNT 144
set_global_assignment -name DEVICE_FILTER_SPEED_GRADE 8
set_global_assignment -name LAST_QUARTUS_VERSION 13.1

set_global_assignment -name MIN_CORE_JUNCTION_TEMP 0
set_global_assignment -name MAX_CORE_JUNCTION_TEMP 85

# The 1k30 configures the extender in passive serial from extender.rbf,
# so no configuration device, and reclaim the config pins as I/O.
set_global_assignment -name USE_CONFIGURATION_DEVICE OFF
set_global_assignment -name CYCLONEII_RESERVE_NCEO_AFTER_CONFIGURATION "USE AS REGULAR IO"
set_global_assignment -name RESERVE_DATA0_AFTER_CONFIGURATION "USE AS REGULAR IO"
set_global_assignment -name RESERVE_DATA1_AFTER_CONFIGURATION "USE AS REGULAR IO"
set_global_assignment -name RESERVE_FLASH_NCE_AFTER_CONFIGURATION "USE AS REGULAR IO"
set_global_assignment -name RESERVE_DCLK_AFTER_CONFIGURATION "USE AS REGULAR IO"
set_global_assignment -name ON_CHIP_BITSTREAM_DECOMPRESSION ON
set_global_assignment -name GENERATE_RBF_FILE ON
set_global_assignment -name PROJECT_OUTPUT_DIRECTORY output_files

set_global_assignment -name SMART_RECOMPILE ON
set_global_assignment -name OPTIMIZE_HOLD_TIMING "ALL PATHS"
set_global_assignment -name OPTIMIZE_MULTI_CORNER_TIMING ON
set_global_assignment -name FITTER_EFFORT "STANDARD FIT"
set_global_assignment -name ENABLE_CLOCK_LATENCY ON
set_global_assignment -name PHYSICAL_SYNTHESIS_EFFORT NORMAL

if {[info exists optimizeforspeed] && ($optimizeforspeed==1)} {
	set_global_assignment -name CYCLONEII_OPTIMIZATION_TECHNIQUE SPEED
} else {
	set_global_assignment -name CYCLONEII_OPTIMIZATION_TECHNIQUE BALANCED
}

set_global_assignment -name PARTITION_NETLIST_TYPE SOURCE -section_id Top
set_global_assignment -name PARTITION_FITTER_PRESERVATION_LEVEL PLACEMENT_AND_ROUTING -section_id Top
set_global_assignment -name PARTITION_COLOR 16764057 -section_id Top
set_instance_assignment -name PARTITION_HIERARCHY root_partition -to | -section_id Top
