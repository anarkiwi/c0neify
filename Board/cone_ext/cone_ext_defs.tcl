# C-One FPGA Extender - DeMiSTify board definition
set have_sdram 1
# Base clock fed to the guest's CLOCK_27 port and to the host PLL.
# The extender has 14.31818 and 28.37516 MHz crystals; we use clk28.
set base_clock 28
set fpga "CycloneIII"
