-- -----------------------------------------------------------------------
--
-- Syntiac VHDL support files.
--
-- -----------------------------------------------------------------------
-- Copyright 2005-2009 by Peter Wendrich (pwsoft@syntiac.com)
-- Copyright 2004-2005 Tobias Gubener
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
-- Based on example code by Tobias Gubener
--
-- -----------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.ALL;

-- -----------------------------------------------------------------------

entity cone_reconfig1k30 is
	generic (
		byteCount : integer := 60000 -- 59215
	);
	port (
		clk : in std_logic;
		dma : in std_logic;
		
		busy : out std_logic;
		pclk : out std_logic;
		cselect : out unsigned(3 downto 0);

		a : out unsigned(16 downto 0);
		d : in unsigned(7 downto 0);
		q : out unsigned(7 downto 0);
		qEna : out std_logic;
		nWr : out std_logic;
		nCs : out std_logic
	);
end;

-- -----------------------------------------------------------------------

architecture rtl of cone_reconfig1k30 is
	type ReconfigState is (
		state_waitDma,
		state_clrA16,
		state_clrFPGA,
		state_wait40us,
		state_readByteW,
		state_readByte,
		state_readByte2,
		state_readByte3,
		state_storeByteW,
		state_storeByte,
		state_finc,
		state_fidle,
		state_fshift,
		state_fready,
		
		state_done
	);
	signal state : ReconfigState := state_waitDma;
	signal busyReg : std_logic := '0';
	signal enable : std_logic := '0';
		
	signal enaCnt : unsigned(6 downto 0) := (others => '0');
	signal timer : integer range 0 to 40 := 0;
	
	signal c_inc : unsigned(4 downto 0);
	
	signal dmaReg : unsigned(3 downto 0) := (others => '0');
	signal aLoc : unsigned(16 downto 0);
	signal aIncr : unsigned(16 downto 0);
	signal qEnaReg : std_logic := '0';
begin
	a <= aLoc;
	busy <= busyReg;
	qEna <= qEnaReg;

-- -----------------------------------------------------------------------
-- Clk divider
	process(clk)
	begin
		if rising_edge(clk) then
			enable <= '0';
			enaCnt <= enaCnt + 1;
			pclk <= enaCnt(3);

			if enaCnt = 101 then
				enaCnt <= (others => '0');
				enable <= '1';
			end if;
		end if;
	end process;

	process(clk)
	begin
		if rising_edge(clk) then
			aIncr <= aLoc + 1;
		end if;
	end process;

-- -----------------------------------------------------------------------
-- State machine
	process(clk)
	begin
		if rising_edge(clk) then
			if enable = '1' then
				timer <= timer + 1;
				if timer = 40 then
					timer <= 0;
				end if;

				cselect <= "1111";
				qEnaReg <= '0';
				nCs <= '1';
				nWr <= '1';

				case state is
				when state_waitDma =>
					busyReg <= '0';
					c_inc <= (others => '0');
					if dma = '1' then
						state <= state_clrA16;
						timer <= 0;
					end if;
				when state_clrA16 =>
					-- Flash addr clear
					busyReg <= '1';
					--aLoc(3 downto 0) <= "0000";
					aLoc <= (others => '0');
					cselect <= "0110";
					if timer = 8 then
						timer <= 0;
						state <= state_clrFPGA;
					end if;
-- -----------------------------------------------------------------------
-- Clear FPGA and prepare for reconfiguration
				when state_clrFPGA =>
					-- clear nConfig
					q <= "11111010"; 
					qEnaReg <= '1';
					cselect <= "1000";
					nWr <= '0';
					if timer = 20 then
						-- Set nConfig
						q <= "11111011"; 
						timer <= 0;
						state <= state_wait40us;
					end if;
				when state_wait40us =>
					if timer = 40 then
						--aLoc <= (others => '0');
						state <= state_readByte;
					end if;
-- -----------------------------------------------------------------------
-- Config loop
				when state_readByteW =>
					-- Extra state to let WR go up and hold data

					-- Increment address for next read
					aLoc <= aIncr;
					qEnaReg <= '1';
					state <= state_readByte;
					if aLoc /= byteCount then
						state <= state_readByte;
					else
						state <= state_finc;
					end if;
				when state_readByte =>
					nCs <= '0';
					state <= state_readByte2;
				when state_readByte2 =>
					nCs <= '0';
					q <= d;
					state <= state_readByte3;
				when state_readByte3 =>
					qEnaReg <= '1';
					state <= state_storeByte;
				when state_storeByte =>
					qEnaReg <= '1';
					nWr <= '0';
					state <= state_readByteW;
-- -----------------------------------------------------------------------
-- Flash A16 to high (CONF_DONE)
				when state_finc =>
					aLoc(3 downto 0) <= "1000"; -- Flash++
					cselect <= "0110";
					state <= state_fidle;
				when state_fidle =>
					aLoc(3 downto 0) <= "1000"; -- Flash++
					state <= state_fshift;
				when state_fshift =>
					aLoc(3 downto 0) <= "0110"; -- Flash shift left
					cselect <= "0110";
					state <= state_fready;
				when state_fready =>
					aLoc(3 downto 0) <= "0110"; -- Flash shift left
					if c_inc = 16 then
						busyReg <= '0';
						state <= state_done;
					else
						c_inc <= c_inc + 1;
						state <= state_finc;
					end if;
				when state_done =>
					busyReg <= '0';
				when others =>
					null;
				end case;
			end if;
		end if;
	end process;
end architecture;




