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
-- and drop c2. The generic set is the one the MegaWizard emits for a
-- Cyclone III altpll (as in Board/chameleon64/hostclocks.vhd), with the
-- component declared locally and without defaults: the declaration in
-- altera_mf_components carries Stratix-style defaults (clkN_counter "G0"
-- etc.) that stop Quartus from computing the Cyclone III PLL counters.

library ieee;
use ieee.std_logic_1164.all;
library altera_mf;
use altera_mf.all;

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
	component altpll
		generic (
			bandwidth_type : string;
			compensate_clock : string;
			intended_device_family : string;
			lpm_hint : string;
			lpm_type : string;
			operation_mode : string;
			pll_type : string;
			inclk0_input_frequency : natural;
			clk0_multiply_by : natural;
			clk0_divide_by : natural;
			clk0_duty_cycle : natural;
			clk0_phase_shift : string;
			clk1_multiply_by : natural;
			clk1_divide_by : natural;
			clk1_duty_cycle : natural;
			clk1_phase_shift : string;
			clk2_multiply_by : natural;
			clk2_divide_by : natural;
			clk2_duty_cycle : natural;
			clk2_phase_shift : string;
			port_inclk0 : string;
			port_inclk1 : string;
			port_areset : string;
			port_locked : string;
			port_clk0 : string;
			port_clk1 : string;
			port_clk2 : string;
			port_activeclock : string;
			port_clkbad0 : string;
			port_clkbad1 : string;
			port_clkloss : string;
			port_clkswitch : string;
			port_configupdate : string;
			port_fbin : string;
			port_pfdena : string;
			port_phasecounterselect : string;
			port_phasedone : string;
			port_phasestep : string;
			port_phaseupdown : string;
			port_pllena : string;
			port_scanaclr : string;
			port_scanclk : string;
			port_scanclkena : string;
			port_scandata : string;
			port_scandataout : string;
			port_scandone : string;
			port_scanread : string;
			port_scanwrite : string;
			port_clk3 : string;
			port_clk4 : string;
			port_clk5 : string;
			port_clkena0 : string;
			port_clkena1 : string;
			port_clkena2 : string;
			port_clkena3 : string;
			port_clkena4 : string;
			port_clkena5 : string;
			port_extclk0 : string;
			port_extclk1 : string;
			port_extclk2 : string;
			port_extclk3 : string;
			self_reset_on_loss_lock : string;
			width_clock : natural
		);
		port (
			inclk : in std_logic_vector(1 downto 0);
			clk : out std_logic_vector(4 downto 0);
			locked : out std_logic
		);
	end component;

	signal sub_wire : std_logic_vector(4 downto 0);
begin
	c0 <= sub_wire(0);
	c1 <= sub_wire(1);
	c2 <= sub_wire(2);

	pll : altpll
	generic map (
		bandwidth_type => "AUTO",
		compensate_clock => "CLK0",
		intended_device_family => "Cyclone III",
		lpm_hint => "CBX_MODULE_PREFIX=hostclocks",
		lpm_type => "altpll",
		operation_mode => "NORMAL",
		pll_type => "AUTO",
		inclk0_input_frequency => 69841,  -- picoseconds: 1/14.31818 MHz
		clk0_multiply_by => 70, clk0_divide_by => 10, clk0_duty_cycle => 50, clk0_phase_shift => "0",
		clk1_multiply_by => 70, clk1_divide_by => 20, clk1_duty_cycle => 50, clk1_phase_shift => "0",
		clk2_multiply_by => 70, clk2_divide_by => 37, clk2_duty_cycle => 50, clk2_phase_shift => "0",
		port_inclk0 => "PORT_USED",
		port_inclk1 => "PORT_UNUSED",
		port_areset => "PORT_UNUSED",
		port_locked => "PORT_USED",
		port_clk0 => "PORT_USED",
		port_clk1 => "PORT_USED",
		port_clk2 => "PORT_USED",
		port_activeclock => "PORT_UNUSED",
		port_clkbad0 => "PORT_UNUSED",
		port_clkbad1 => "PORT_UNUSED",
		port_clkloss => "PORT_UNUSED",
		port_clkswitch => "PORT_UNUSED",
		port_configupdate => "PORT_UNUSED",
		port_fbin => "PORT_UNUSED",
		port_pfdena => "PORT_UNUSED",
		port_phasecounterselect => "PORT_UNUSED",
		port_phasedone => "PORT_UNUSED",
		port_phasestep => "PORT_UNUSED",
		port_phaseupdown => "PORT_UNUSED",
		port_pllena => "PORT_UNUSED",
		port_scanaclr => "PORT_UNUSED",
		port_scanclk => "PORT_UNUSED",
		port_scanclkena => "PORT_UNUSED",
		port_scandata => "PORT_UNUSED",
		port_scandataout => "PORT_UNUSED",
		port_scandone => "PORT_UNUSED",
		port_scanread => "PORT_UNUSED",
		port_scanwrite => "PORT_UNUSED",
		port_clk3 => "PORT_UNUSED",
		port_clk4 => "PORT_UNUSED",
		port_clk5 => "PORT_UNUSED",
		port_clkena0 => "PORT_UNUSED",
		port_clkena1 => "PORT_UNUSED",
		port_clkena2 => "PORT_UNUSED",
		port_clkena3 => "PORT_UNUSED",
		port_clkena4 => "PORT_UNUSED",
		port_clkena5 => "PORT_UNUSED",
		port_extclk0 => "PORT_UNUSED",
		port_extclk1 => "PORT_UNUSED",
		port_extclk2 => "PORT_UNUSED",
		port_extclk3 => "PORT_UNUSED",
		self_reset_on_loss_lock => "OFF",
		width_clock => 5
	)
	port map (
		inclk(0) => inclk0,
		inclk(1) => '0',
		clk => sub_wire,
		locked => locked
	);
end architecture;
