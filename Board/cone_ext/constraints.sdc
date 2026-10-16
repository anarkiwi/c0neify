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

set FALSE_OUT {sigma_l sigma_r}
set FALSE_IN {mdb* vid_spare*}

set_false_path -to [get_ports {ram_clk}]

# vid-bus link to the 1k30 (clocked by the extender over vid[14])
# Placeholder 0.5 ns delays as in DeMiSTify's chameleon64 constraints; the
# board's real vid-bus delays are not known (BLOCKED.md).
set_input_delay  0.5 -clock [get_clocks ${supportclk}] [get_ports {mux_q[*]}]
set_output_delay 0.5 -clock [get_clocks ${supportclk}] [get_ports {mux_clk mux_sel[*] mux_d[*]}]

# The guest's SPI_SCK is substitute_mcu's sck register, which the
# divide-by-4 spiclk above stands in for. The selects and conf_data0 are
# written by the controller CPU only while the SPI is idle (busy low), at
# least one controller clock after the last SCK edge and before the next
# trigger, so they are static with respect to spiclk; guests use them as
# asynchronous resets of their SPI logic.
set_false_path -from [get_registers {substitute_mcu:controller|spi_ss* substitute_mcu:controller|conf_data0}] -to [get_clocks {spiclk spiclkfast}]

# spi_controller changes MOSI with the falling SCK step; the next rising
# step needs a full req/ack handshake, and with SPI_EXTERNALCLK the ack
# passes two synchroniser flops (substitute_mcu spi_ack_d, spi_ack_r), so
# at least three controller cycles separate them. Two are allowed here.
set_multicycle_path -setup -start 2 -from [get_registers {substitute_mcu:controller|spi_controller:spi|mosi}] -to [get_clocks {spiclk spiclkfast}]
set_multicycle_path -hold -start 1 -from [get_registers {substitute_mcu:controller|spi_controller:spi|mosi}] -to [get_clocks {spiclk spiclkfast}]

# LED levels from the guest clock domain enter cone_io through a two-flop
# synchroniser; only its first stage is unconstrained.
set_false_path -to [get_registers {*cone_io:*|led_meta[*]}]

# JTAG (debug interface, if enabled)
set_input_delay -clock altera_reserved_tck -clock_fall 3 altera_reserved_tdi
set_input_delay -clock altera_reserved_tck -clock_fall 3 altera_reserved_tms
set_output_delay -clock altera_reserved_tck 3 altera_reserved_tdo

set topmodule guest|
