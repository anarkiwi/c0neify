-- hostclocks.vhd - host PLL for the C-One FPGA Extender
--
-- Input: clk14 = 14.31818 MHz crystal on the extender (pin 55).
-- VCO = 14.31818 * 70 = 1002.27 MHz (Cyclone III VCO range 600..1300 MHz)
--   c0 = VCO / 10 = 100.23 MHz   vid-bus mux clock, SDRAM
--   c1 = VCO / 20 =  50.11 MHz   substitute_mcu (EightThirtyTwo) clock
--   c2 = VCO / 37 =  27.09 MHz   feed to the guest's CLOCK_27 (+0.33 %)
--
-- If +0.33 % on the guest clock matters for a given core, regenerate the
-- guest's own PLL for a 28.37516 MHz input instead (set base_clock 28)
-- and drop c2. Equivalent to the MegaWizard altpll; regenerate there if
-- you prefer a .qip-managed instance.

library ieee;
use ieee.std_logic_1164.all;
library altera_mf;
use altera_mf.altera_mf_components.all;

entity hostclocks is
	port (
		inclk0 : in std_logic;
		c0 : out std_logic;
		c1 : out std_logic;
		c2 : out std_logic;
		locked : out std_logic
	);
end entity;

architecture rtl of hostclocks is
	signal sub_wire : std_logic_vector(4 downto 0);
begin
	c0 <= sub_wire(0);
	c1 <= sub_wire(1);
	c2 <= sub_wire(2);

	pll : altpll
	generic map (
		intended_device_family => "Cyclone III",
		lpm_type => "altpll",
		operation_mode => "NORMAL",
		pll_type => "AUTO",
		inclk0_input_frequency => 69841,  -- picoseconds: 1/14.31818 MHz
		clk0_multiply_by => 70, clk0_divide_by => 10, clk0_duty_cycle => 50, clk0_phase_shift => "0",
		clk1_multiply_by => 70, clk1_divide_by => 20, clk1_duty_cycle => 50, clk1_phase_shift => "0",
		clk2_multiply_by => 70, clk2_divide_by => 37, clk2_duty_cycle => 50, clk2_phase_shift => "0",
		port_clk0 => "PORT_USED",
		port_clk1 => "PORT_USED",
		port_clk2 => "PORT_USED",
		port_clk3 => "PORT_UNUSED",
		port_clk4 => "PORT_UNUSED",
		port_locked => "PORT_USED",
		port_inclk0 => "PORT_USED",
		port_inclk1 => "PORT_UNUSED",
		port_areset => "PORT_UNUSED",
		self_reset_on_loss_lock => "OFF"
	)
	port map (
		inclk(0) => inclk0,
		inclk(1) => '0',
		clk => sub_wire,
		locked => locked
	);
end architecture;
