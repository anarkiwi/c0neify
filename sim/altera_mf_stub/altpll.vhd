-- Behavioural altpll for GHDL lint and simulation.
--
-- Output k runs at f(inclk0) * clkK_multiply_by / clkK_divide_by with 50 %
-- duty. All outputs are derived by counting one common tick of period
-- T(inclk0) / (2 * lcm(multipliers)), so related outputs keep exact edge
-- alignment for the whole run, as they do from a real PLL's shared VCO.
-- locked rises after stub_lock_cycles rising edges of inclk(0) and drops on
-- areset. Phase shift and non-50 % duty cycle are not modelled.

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

	function gcd(a, b : natural) return natural is
		variable x : natural := a;
		variable y : natural := b;
		variable t : natural;
	begin
		while y /= 0 loop
			t := x mod y;
			x := y;
			y := t;
		end loop;
		return x;
	end function;

	function lcm_all return natural is
		variable l : natural := 1;
	begin
		for k in mul'range loop
			l := l / gcd(l, mul(k)) * mul(k);
		end loop;
		return l;
	end function;

	constant lcm_mul : natural := lcm_all;
	constant tick : time := (inclk0_input_frequency * 1000 / (2 * lcm_mul)) * 1 fs;

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

	outputs : process
		type cnt_array is array (0 to 4) of natural;
		variable cnt : cnt_array := (others => 0);
		variable lvl : std_logic_vector(4 downto 0) := (others => '0');
	begin
		clk <= (others => '0');
		wait until lock_r = '1';
		while lock_r = '1' loop
			for k in 0 to width_clock - 1 loop
				if cnt(k) = 0 then
					lvl(k) := not lvl(k);
					cnt(k) := div(k) * lcm_mul / mul(k);
				end if;
				cnt(k) := cnt(k) - 1;
			end loop;
			clk <= lvl(width_clock - 1 downto 0);
			wait for tick;
		end loop;
	end process;
end architecture;
