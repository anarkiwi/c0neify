set_global_assignment -name SDC_FILE ${boardpath}/cone_ext/constraints.sdc
set_global_assignment -name VHDL_FILE ${boardpath}/cone_ext/cone_mm_link.vhd
set_global_assignment -name VHDL_FILE ${boardpath}/cone_ext/cone_sd_ata.vhd
set_global_assignment -name VHDL_FILE ${boardpath}/cone_ext/cone_mergeinputs.vhd
set_global_assignment -name VHDL_FILE ${boardpath}/cone_ext/gen_reset.vhd
set_global_assignment -name QIP_FILE ${boardpath}/cone_ext/hostclocks.qip

# 16 MB SDRAM on the extender: Samsung K4S281632-UC60 (C1_extender_schem.pdf),
# 8M x 16, 12 row / 9 column bits. Timings from the K4S281632F datasheet
# (reference/K4S280432F-UC.PDF, "SDRAM 128Mb F-die (x4, x8, x16)" Rev 1.2,
# -60 column): tRC 60 ns, tRP 18 ns, tRDL 2 CLK, CL3 at tCK >= 6 ns.
# The -60 grade has no CL2 rating, so SDRAM_tCKminCL2 is left undefined.
set_global_assignment -name VERILOG_MACRO "SDRAM_WINBOND=0"
set_global_assignment -name VERILOG_MACRO "SDRAM_ROWBITS=12"
set_global_assignment -name VERILOG_MACRO "SDRAM_COLBITS=9"
set_global_assignment -name VERILOG_MACRO "SDRAM_CL=3"
set_global_assignment -name VERILOG_MACRO "SDRAM_tRC=60000"
set_global_assignment -name VERILOG_MACRO "SDRAM_tWR=2"
set_global_assignment -name VERILOG_MACRO "SDRAM_tRP=18000"

# Keyboard reaches the extender as PS/2 tunnelled over the vid bus.
set_global_assignment -name VERILOG_MACRO "DEMISTIFY_PS2_KEYBOARD=1"
