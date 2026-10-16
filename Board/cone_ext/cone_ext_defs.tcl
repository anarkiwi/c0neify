# C-One FPGA Extender - DeMiSTify board definition
set have_sdram 1
# Nominal frequency of the guest's CLOCK_27 input. The template feeds it
# hostclocks c2 (27.09 MHz, derived from clk14), so guest PLLs generated for
# 27 MHz are used unchanged. Set 28 only for a core whose own PLL has been
# regenerated for the 28.37516 MHz crystal (see README "Clocks").
set base_clock 27
set fpga "CycloneIII"
