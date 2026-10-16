-- -----------------------------------------------------------------------
-- cone_mergeinputs.vhd
--
-- Maps the two C-One joystick ports into the joystick words expected by
-- DeMiSTify's substitute_mcu (and by MiST guest cores): directions in bits
-- 3..0 in the same up/down/left/right order as the C64 port, fire buttons
-- at the core-specific positions demistify_button1/2 from
-- demistify_config_pkg. Everything is active low on both sides, matching
-- chameleon_mergeinputs and substitute_mcu's '1' defaults.
--
-- Input bit order (both ports): 5 fire2, 4 fire1, 3 right, 2 left, 1 down,
-- 0 up. Plain VHDL-93 so the 1k30 side can share it.
-- -----------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity cone_mergeinputs is
	generic (
		joybits : integer := 8;
		button1 : integer := 4;
		button2 : integer := 5
	);
	port (
		clk : in std_logic;
		joy_a : in unsigned(5 downto 0);
		joy_b : in unsigned(5 downto 0);
		joy1_out : out std_logic_vector(joybits - 1 downto 0);
		joy2_out : out std_logic_vector(joybits - 1 downto 0)
	);
end entity;

architecture rtl of cone_mergeinputs is
	function map_port(j : unsigned(5 downto 0)) return std_logic_vector is
		variable r : std_logic_vector(joybits - 1 downto 0) := (others => '1');
	begin
		r(3 downto 0) := std_logic_vector(j(3 downto 0));
		r(button1) := j(4);
		r(button2) := j(5);
		return r;
	end function;
begin
	assert button1 >= 4 and button1 < joybits and button2 >= 4 and button2 < joybits
		and button1 /= button2
		report "cone_mergeinputs: button positions must be distinct and in 4..joybits-1"
		severity failure;

	process(clk)
	begin
		if rising_edge(clk) then
			joy1_out <= map_port(joy_a);
			joy2_out <= map_port(joy_b);
		end if;
	end process;
end architecture;
