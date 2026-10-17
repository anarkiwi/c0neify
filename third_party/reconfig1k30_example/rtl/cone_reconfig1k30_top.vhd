-- -----------------------------------------------------------------------
--
-- Syntiac VHDL support files.
--
-- -----------------------------------------------------------------------
-- Copyright 2005-2009 by Peter Wendrich (pwsoft@syntiac.com)
-- http://www.syntiac.com
--
-- This source file is free software: you can redistribute it and/or modify
-- it under the terms of the GNU Lesser General Public License as published
-- by the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- This source file is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with this program. If not, see <http://www.gnu.org/licenses/>.
--
-- -----------------------------------------------------------------------
--
-- Reconfiguration of 1K30 FPGA from the 1K100 FPGA.
-- Example toplevel file.
--
-- -----------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.ALL;

-- -----------------------------------------------------------------------

entity cone_reconfig1k30_top is
	port (
		sysclk : in std_logic;
		nReset : in std_logic;
		
		pclk : out std_logic;
		gb : inout unsigned(7 downto 0);
		cselect : inout unsigned(3 downto 0);
		
		ioShift : in std_logic;
		
		ramcs : out std_logic;
		wr : inout std_logic;
		a : inout unsigned(16 downto 0);
		mdb : inout unsigned(7 downto 0)
	);
end entity;

-- -----------------------------------------------------------------------

architecture rtl of cone_reconfig1k30_top is
	signal clk : std_logic;
	signal reset : std_logic;
	signal reconfigBusy : std_logic;
	signal reconfigBusyPrev : std_logic;
	
	signal reconfigPClk : std_logic;
	signal reconfigCSelect : unsigned(3 downto 0);
	signal reconfigA : unsigned(16 downto 0);
	signal reconfigQ : unsigned(7 downto 0);
	signal reconfigQEna : std_logic;
	signal reconfigWr : std_logic;
	signal reconfigCs : std_logic;

	signal clkdiv : unsigned(5 downto 0);
	signal running : std_logic := '0';
	
	signal ioShiftReg : std_logic;
begin
	reset <= not nReset;
	clk <= not (gb(7));
	gb <= (others => 'Z');

	process(gb)
	begin
		if rising_edge(clk) then
			ioShiftReg <= ioShift;
		end if;
	end process;

	process(sysclk)
	begin
		if rising_edge(sysclk) then
			clkdiv <= clkdiv + 1;
			reconfigBusyPrev <= reconfigBusy;
			if reconfigBusyPrev = '1' and reconfigBusy = '0' then
				running <= '1';
			end if;
		end if;
	end process;
	
	myReconfig1k30 : entity work.cone_reconfig1k30
		port map (
			clk => clkdiv(1), --sysclk, --clkdiv(1),
			dma => '1',

			busy => reconfigBusy,
			pclk => reconfigPClk,
			cselect => reconfigCSelect,
			
			a => reconfigA,
			d => mdb,
			q => reconfigQ,
			qEna => reconfigQEna,
			
			nWr => reconfigWr,
			nCs => reconfigCs
		);
	
	gb(0) <= ioShiftReg when running = '1' else 'Z';
	pclk <= reconfigPClk when reconfigBusy = '1' else clk;
	cselect <= reconfigCSelect when reconfigBusy = '1' else (others => 'Z');
	a <= reconfigA when reconfigBusy = '1' else (others => 'Z');
	mdb <= reconfigQ when ((reconfigBusy = '1') and (reconfigQEna = '1')) else (others => 'Z');
	wr <= reconfigWr when reconfigBusy = '1' else 'Z';
	ramcs <= reconfigCs when reconfigBusy = '1' else 'Z';
end architecture;