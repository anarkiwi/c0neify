-- Minimal stand-in for Altera's altera_mf_components package, compiled into
-- a library named altera_mf so RTL that instantiates altpll can be analysed,
-- elaborated and simulated with GHDL without a Quartus install.
--
-- Only altpll is provided. Generics a MegaWizard Cyclone III altpll normally
-- sets are accepted; those the model does not implement are ignored.

library ieee;
use ieee.std_logic_1164.all;

package altera_mf_components is
	component altpll
		generic (
			intended_device_family : string := "NONE";
			lpm_type : string := "altpll";
			lpm_hint : string := "UNUSED";
			operation_mode : string := "NORMAL";
			pll_type : string := "AUTO";
			bandwidth_type : string := "AUTO";
			compensate_clock : string := "CLK0";
			inclk0_input_frequency : natural;
			width_clock : natural := 6;
			clk0_multiply_by : natural := 1; clk0_divide_by : natural := 1;
			clk0_duty_cycle : natural := 50; clk0_phase_shift : string := "0";
			clk1_multiply_by : natural := 1; clk1_divide_by : natural := 1;
			clk1_duty_cycle : natural := 50; clk1_phase_shift : string := "0";
			clk2_multiply_by : natural := 1; clk2_divide_by : natural := 1;
			clk2_duty_cycle : natural := 50; clk2_phase_shift : string := "0";
			clk3_multiply_by : natural := 1; clk3_divide_by : natural := 1;
			clk3_duty_cycle : natural := 50; clk3_phase_shift : string := "0";
			clk4_multiply_by : natural := 1; clk4_divide_by : natural := 1;
			clk4_duty_cycle : natural := 50; clk4_phase_shift : string := "0";
			clk5_multiply_by : natural := 1; clk5_divide_by : natural := 1;
			clk5_duty_cycle : natural := 50; clk5_phase_shift : string := "0";
			port_clk0 : string := "PORT_UNUSED";
			port_clk1 : string := "PORT_UNUSED";
			port_clk2 : string := "PORT_UNUSED";
			port_clk3 : string := "PORT_UNUSED";
			port_clk4 : string := "PORT_UNUSED";
			port_clk5 : string := "PORT_UNUSED";
			port_locked : string := "PORT_UNUSED";
			port_activeclock : string := "PORT_UNUSED";
			port_clkbad0 : string := "PORT_UNUSED";
			port_clkbad1 : string := "PORT_UNUSED";
			port_clkloss : string := "PORT_UNUSED";
			port_clkswitch : string := "PORT_UNUSED";
			port_configupdate : string := "PORT_UNUSED";
			port_fbin : string := "PORT_UNUSED";
			port_pfdena : string := "PORT_UNUSED";
			port_phasecounterselect : string := "PORT_UNUSED";
			port_phasedone : string := "PORT_UNUSED";
			port_phasestep : string := "PORT_UNUSED";
			port_phaseupdown : string := "PORT_UNUSED";
			port_pllena : string := "PORT_UNUSED";
			port_scanaclr : string := "PORT_UNUSED";
			port_scanclk : string := "PORT_UNUSED";
			port_scanclkena : string := "PORT_UNUSED";
			port_scandata : string := "PORT_UNUSED";
			port_scandataout : string := "PORT_UNUSED";
			port_scandone : string := "PORT_UNUSED";
			port_scanread : string := "PORT_UNUSED";
			port_scanwrite : string := "PORT_UNUSED";
			port_clkena0 : string := "PORT_UNUSED";
			port_clkena1 : string := "PORT_UNUSED";
			port_clkena2 : string := "PORT_UNUSED";
			port_clkena3 : string := "PORT_UNUSED";
			port_clkena4 : string := "PORT_UNUSED";
			port_clkena5 : string := "PORT_UNUSED";
			port_extclk0 : string := "PORT_UNUSED";
			port_extclk1 : string := "PORT_UNUSED";
			port_extclk2 : string := "PORT_UNUSED";
			port_extclk3 : string := "PORT_UNUSED";
			port_inclk0 : string := "PORT_USED";
			port_inclk1 : string := "PORT_UNUSED";
			port_areset : string := "PORT_UNUSED";
			self_reset_on_loss_lock : string := "OFF";
			width_phasecounterselect : natural := 3;
			stub_lock_cycles : positive := 16
		);
		port (
			inclk : in std_logic_vector(1 downto 0) := (others => '0');
			areset : in std_logic := '0';
			pfdena : in std_logic := '1';
			clk : out std_logic_vector(width_clock - 1 downto 0);
			locked : out std_logic
		);
	end component;
end package;
