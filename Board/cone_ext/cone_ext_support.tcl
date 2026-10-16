set_global_assignment -name SDC_FILE ${boardpath}/cone_ext/constraints.sdc
set_global_assignment -name VHDL_FILE ${boardpath}/cone_ext/cone_io.vhd
set_global_assignment -name VHDL_FILE ${boardpath}/cone_ext/cone_mergeinputs.vhd
set_global_assignment -name VHDL_FILE ${boardpath}/cone_ext/gen_reset.vhd
set_global_assignment -name QIP_FILE ${boardpath}/cone_ext/hostclocks.qip

# 16 MB SDRAM on the extender: 128 Mbit x16, 12 row / 9 column bits.
# The fitted part is a Samsung K4S281632-UC60 (C1_extender_schem.pdf). The
# timing values below are generic placeholders from the draft, not yet
# checked against that part's datasheet (BLOCKED.md).
set_global_assignment -name VERILOG_MACRO "SDRAM_WINBOND=0"
set_global_assignment -name VERILOG_MACRO "SDRAM_ROWBITS=12"
set_global_assignment -name VERILOG_MACRO "SDRAM_COLBITS=9"
set_global_assignment -name VERILOG_MACRO "SDRAM_CL=3"
set_global_assignment -name VERILOG_MACRO "SDRAM_tCKminCL2=10000"
set_global_assignment -name VERILOG_MACRO "SDRAM_tRC=66000"
set_global_assignment -name VERILOG_MACRO "SDRAM_tWR=2"
set_global_assignment -name VERILOG_MACRO "SDRAM_tRP=15000"

# Keyboard reaches the extender as PS/2 tunnelled over the vid bus.
set_global_assignment -name VERILOG_MACRO "DEMISTIFY_PS2_KEYBOARD=1"
