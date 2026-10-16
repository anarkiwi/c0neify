-- Toolchain smoke test: a counter and an EAB-inferred RAM on any ACEX 1K.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity smoke is
	port (
		clk  : in  std_logic;
		we   : in  std_logic;
		din  : in  std_logic_vector(7 downto 0);
		dout : out std_logic_vector(7 downto 0);
		cnt  : out std_logic_vector(15 downto 0)
	);
end entity;

architecture rtl of smoke is
	type ram_t is array (0 to 255) of std_logic_vector(7 downto 0);
	signal ram : ram_t;
	signal c   : unsigned(15 downto 0) := (others => '0');
begin
	process (clk)
	begin
		if rising_edge(clk) then
			c <= c + 1;
			if we = '1' then
				ram(to_integer(c(7 downto 0))) <= din;
			end if;
			dout <= ram(to_integer(c(7 downto 0)));
		end if;
	end process;
	cnt  <= std_logic_vector(c);
end architecture;
