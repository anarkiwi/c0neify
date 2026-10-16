# C-One FPGA Extender timing constraints
create_clock -name "clk28" -period 35.242ns [get_ports {clk28}]
create_clock -name "clk14" -period 69.841ns [get_ports {clk14}]

# Host PLL: hostclocks (clk14 -> c0 = 100 MHz vid-bus/SDRAM, c1 = 50 MHz
# controller, c2 = 27 MHz guest CLOCK_27)
set hostclk {clocks|pll|auto_generated|pll1|clk[1]}
set supportclk {clocks|pll|auto_generated|pll1|clk[0]}

create_generated_clock -name spiclk -source [get_pins ${hostclk}] -divide_by 4 [get_registers {substitute_mcu:controller|spi_controller:spi|sck}]
create_generated_clock -name spiclkfast -source [get_pins ${supportclk}] -divide_by 4 [get_registers {substitute_mcu:controller|spi_controller:spi|sck}]

derive_pll_clocks -create_base_clocks
derive_clock_uncertainty

# Pin groups for DeMiSTify's downstream constraints
set RAM_CLK ram_clk
set RAM_OUT {ram_data* ram_addr* ram_ba* ram_ras_n ram_cas_n ram_we_n ram_*dqm}
set RAM_IN {ram_data*}

set VGA_OUT {red* grn* blu* hsync_oc vsync_oc}

set FALSE_OUT {sigma_l sigma_r vid_spare_out}
set FALSE_IN {mdb* vid_spare_in*}

set_false_path -to [get_ports {ram_clk}]

# vid-bus link to the 1k30 (cone_mm_link). IOclk is clk_100 / 2 from the
# register cone_mm_link|ioclk and is the only clock of the 1k30's link
# logic (acex.vhd:84-86), so the board-side delays are given against the
# vid_ioclk pin. They are not known (BLOCKED.md #3): 0.5 ns placeholders as
# in DeMiSTify's chameleon64 constraints, so the reported slack is the
# budget left for wires and the 1k30.
set ioclk_reg {*cone_mm_link:*|ioclk}
create_generated_clock -name ioclk -source [get_pins ${supportclk}] -divide_by 2 [get_registers $ioclk_reg]
create_generated_clock -name vid_ioclk -source [get_registers $ioclk_reg] [get_ports {vid_ioclk}]

# Extender -> 1k30: launched on the clk_100 falling edge while IOclk is
# high (cfide.vhd:517-520), captured on the next IOclk rise (acex.vhd:86-87)
# 1.5 clk_100 periods later; the IOclk rise 0.5 periods before the launch
# bounds the hold. -start moves the launch back to the enabled falling edge.
set_output_delay -clock vid_ioclk 0.5 [get_ports {vid_ide_out[*] vid_ser_out}]
set_multicycle_path -setup -start 2 -from [get_clocks ${supportclk}] -to [get_clocks vid_ioclk]
set_multicycle_path -hold -start 1 -from [get_clocks ${supportclk}] -to [get_clocks vid_ioclk]

# 1k30 -> extender: launched on IOclk rise k (acex.vhd:89,174), sampled on
# the clk_100 edge that raises IOclk k+1 (cfide.vhd:527-531,
# cyclone.vhd:133-134), two clk_100 periods later; the launch on that same
# IOclk rise bounds the hold.
set_input_delay -clock vid_ioclk 0.5 [get_ports {vid_ide_in[*] vid_ser_in}]
set_multicycle_path -setup -end 2 -from [get_clocks vid_ioclk] -to [get_clocks ${supportclk}]
set_multicycle_path -hold -end 1 -from [get_clocks vid_ioclk] -to [get_clocks ${supportclk}]

# The guest's SPI_SCK is substitute_mcu's sck register, which the
# divide-by-4 spiclk above stands in for. The selects and conf_data0 are
# written by the controller CPU only while the SPI is idle (busy low), at
# least one controller clock after the last SCK edge and before the next
# trigger, so they are static with respect to spiclk; guests use them as
# asynchronous resets of their SPI logic.
set_false_path -from [get_registers {substitute_mcu:controller|spi_ss* substitute_mcu:controller|conf_data0}] -to [get_clocks {spiclk spiclkfast}]

# spi_controller changes MOSI with the falling SCK step; with SPI_FASTBIT 0
# the next (rising) step comes two controller cycles later at the earliest
# (substitute_mcu.vhd:377-383).
set_multicycle_path -setup -start 2 -from [get_registers {substitute_mcu:controller|spi_controller:spi|mosi}] -to [get_clocks {spiclk spiclkfast}]
set_multicycle_path -hold -start 1 -from [get_registers {substitute_mcu:controller|spi_controller:spi|mosi}] -to [get_clocks {spiclk spiclkfast}]

# JTAG (debug interface, if enabled)
set_input_delay -clock altera_reserved_tck -clock_fall 3 altera_reserved_tdi
set_input_delay -clock altera_reserved_tck -clock_fall 3 altera_reserved_tms
set_output_delay -clock altera_reserved_tck 3 altera_reserved_tdo

set topmodule guest|
