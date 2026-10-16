-- Behavioural altpll for GHDL lint and simulation.
--
-- Output k runs at f(inclk0) * clkK_multiply_by / clkK_divide_by with 50 %
-- duty, rising at lock. Its n-th edge is placed at T(inclk0) * n * div / (2 * mul)
-- from a common origin, so related outputs keep exact edge alignment for the
-- whole run, as they do from a real PLL's shared VCO, and only real clock
-- edges are simulated. locked rises after stub_lock_cycles rising edges of
-- inclk(0) and drops on areset. Phase shift and non-50 % duty cycle are not
-- modelled.

library ieee;
use ieee.std_logic_1164.all;

entity altpll is
	generic (
		intended_device_family : string := "Cyclone III";
		lpm_type : string := "altpll";
		lpm_hint : string := "UNUSED";
		operation_mode : string := "NORMAL";
		pll_type : string := "AUTO";
		bandwidth_type : string := "AUTO";
		compensate_clock : string := "CLK0";
		inclk0_input_frequency : natural := 0;
		width_clock : natural := 5;
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
		port_clk0 : string := "PORT_UNUSED";
		port_clk1 : string := "PORT_UNUSED";
		port_clk2 : string := "PORT_UNUSED";
		port_clk3 : string := "PORT_UNUSED";
		port_clk4 : string := "PORT_UNUSED";
		port_locked : string := "PORT_UNUSED";
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
end entity;

architecture behavioural of altpll is
	type nat_array is array (0 to 4) of natural;
	constant mul : nat_array := (clk0_multiply_by, clk1_multiply_by,
		clk2_multiply_by, clk3_multiply_by, clk4_multiply_by);
	constant div : nat_array := (clk0_divide_by, clk1_divide_by,
		clk2_divide_by, clk3_divide_by, clk4_divide_by);

	constant T_IN : time := inclk0_input_frequency * 1 ps;

	signal lock_r : std_logic := '0';
begin
	assert inclk0_input_frequency > 0
		report "altpll stub: inclk0_input_frequency must be set" severity failure;
	assert clk0_phase_shift = "0" and clk1_phase_shift = "0" and clk2_phase_shift = "0"
		and clk3_phase_shift = "0" and clk4_phase_shift = "0"
		report "altpll stub: phase shift is not modelled" severity warning;

	locked <= lock_r;

	lock : process(inclk(0), areset)
		variable n : natural := 0;
	begin
		if areset = '1' then
			n := 0;
			lock_r <= '0';
		elsif rising_edge(inclk(0)) then
			if n < stub_lock_cycles then
				n := n + 1;
			else
				lock_r <= '1';
			end if;
		end if;
	end process;

	outputs : for k in 0 to width_clock - 1 generate
		process
			variable n : natural;
			variable t0 : time;
		begin
			clk(k) <= '0';
			wait until lock_r = '1';
			t0 := now;
			n := 0;
			while lock_r = '1' loop
				clk(k) <= not clk(k);
				n := n + 1;
				wait for t0 + (T_IN * (n * div(k))) / (2 * mul(k)) - now;
			end loop;
		end process;
	end generate;
end architecture;
