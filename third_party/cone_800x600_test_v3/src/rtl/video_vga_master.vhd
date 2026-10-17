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
-- VGA Video sync and timing generator
--
-- -----------------------------------------------------------------------
--
-- The module contains a fractional counter to scale the pixels. The speed
-- is set with 'pixelSpeed'. This can result in unequal pixel widths and
-- TFT sync problems depending on the clk speed. The system can also run on
-- full clock speed by setting 'fullSpeed' to 1. Then the fractional counter
-- is bypassed.
--
-- -----------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.all;

-- -----------------------------------------------------------------------

entity video_vga_master is
	port (
-- System
		clk : in std_logic;

-- Sync outputs
		hSync : out std_logic;
		vSync : out std_logic;

-- Control outputs
		endOfPixel : out std_logic;
		endOfLine : out std_logic;
		endOfFrame : out std_logic;
		currentX : out unsigned(11 downto 0);
		currentY : out unsigned(11 downto 0);

-- Configuration
		pixelSpeed : in unsigned(9 downto 0);
		fullSpeed : in std_logic := '0';
		xSize : in unsigned(11 downto 0);
		ySize : in unsigned(11 downto 0);
		xSyncFr : in unsigned(11 downto 0);
		xSyncTo : in unsigned(11 downto 0);
		ySyncFr : in unsigned(11 downto 0);
		ySyncTo : in unsigned(11 downto 0)
	);
end entity;

-- -----------------------------------------------------------------------

architecture rtl of video_vga_master is
	signal xPrescale : unsigned(9 downto 0) := (others => '0');
	signal newPixel : std_logic := '0';
	signal newLine : std_logic := '0';
	signal xCounter : unsigned(11 downto 0) := (others => '0');
	signal yCounter : unsigned(11 downto 0) := (others => '0');
begin
-- -----------------------------------------------------------------------
-- Copy of local signals as outputs (for vga-slaves)
	currentX <= xCounter;
	currentY <= yCounter;
	endOfPixel <= newPixel;
	endOfLine <= newLine;

-- -----------------------------------------------------------------------
-- X & Y counters
	process(clk)
	begin
		if rising_edge(clk) then
			newLine <= '0';
			endOfFrame <= '0';
		
			if newPixel = '1' then
				xCounter <= xCounter + 1;
			end if;
			if xCounter = xSize then
				newLine <= '1';
				xCounter <= (others => '0');
				
				yCounter <= yCounter + 1;
				if yCounter = ySize then
					endOfFrame <= '1';
					yCounter <= (others => '0');
				end if;
			end if;
		end if;
	end process;

-- -----------------------------------------------------------------------
-- x scale (pixelspeed)
	process(clk)
		variable tmpScale : unsigned(10 downto 0);
	begin
		if rising_edge(clk) then
			tmpScale := ("0" & xPrescale) + pixelSpeed;
			if newLine = '1' then
				tmpScale := (others => '0');
			end if;

			xPrescale <= tmpScale(9 downto 0);
			newPixel <= tmpScale(10) or fullSpeed;
		end if;
	end process;

-- -----------------------------------------------------------------------
-- hSync
	process(clk)
	begin
		if rising_edge(clk) then
			hSync <= '0';
			if xCounter >= xSyncFr
			and xCounter < xSyncTo then
				hSync <= '1';
			end if;
		end if;
	end process;

-- -----------------------------------------------------------------------
-- vSync
	process(clk)
	begin
		if rising_edge(clk) then
			vSync <= '0';
			if yCounter >= ySyncFr
			and yCounter < ySyncTo then
				vSync <= '1';
			end if;
		end if;
	end process;
end architecture;


