# C-One FPGA Extender timing constraints
create_clock -name "clk28" -period 35.242ns [get_ports {clk28}]
create_clock -name "clk14" -period 69.841ns [get_ports {clk14}]

# Host PLL: hostclocks (clk14 -> c0 = 100 MHz vid-bus/SDRAM, c1 = 50 MHz
# controller, c2 = 27 MHz guest CLOCK_27)
set hostclk {clocks|altpll_component|auto_generated|pll1|clk[1]}
set supportclk {clocks|altpll_component|auto_generated|pll1|clk[0]}

create_generated_clock -name spiclk -source [get_pins ${hostclk}] -divide_by 4 [get_registers {substitute_mcu:controller|spi_controller:spi|sck}]
create_generated_clock -name spiclkfast -source [get_pins ${supportclk}] -divide_by 4 [get_registers {substitute_mcu:controller|spi_controller:spi|sck}]

derive_pll_clocks -create_base_clocks
derive_clock_uncertainty

# Pin groups for DeMiSTify's downstream constraints
set RAM_CLK ram_clk
set RAM_OUT {ram_data* ram_addr* ram_ba* ram_ras_n ram_cas_n ram_we_n ram_*dqm}
set RAM_IN {ram_data*}

set VGA_OUT {red* grn* blu* hsync_oc vsync_oc}

set FALSE_OUT {sigma_l sigma_r mdb*}
set FALSE_IN {mdb*}

set_false_path -to [get_ports {ram_clk}]

# vid-bus link to the 1k30 (clocked by the extender over vid[14])
set_input_delay  0.5 -clock [get_clocks ${supportclk}] [get_ports {vid[*]}]
set_output_delay 0.5 -clock [get_clocks ${supportclk}] [get_ports {vid[*]}]

# JTAG (debug interface, if enabled)
set_input_delay -clock altera_reserved_tck -clock_fall 3 altera_reserved_tdi
set_input_delay -clock altera_reserved_tck -clock_fall 3 altera_reserved_tms
set_output_delay -clock altera_reserved_tck 3 altera_reserved_tdo

set topmodule guest|
