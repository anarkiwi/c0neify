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
-- 800x600 video test with color dither for C-One plus extender board.
--
-- -----------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.ALL;

-- -----------------------------------------------------------------------

entity cone_800x600_test is
	generic (
		resetCycles: integer := 4095
	);
	port (
		clk14 : in std_logic;
		clk28 : in std_logic;

-- Video
		red : out unsigned(4 downto 0);
		grn : out unsigned(5 downto 0);
		blu : out unsigned(4 downto 0);
		nHSync : out std_logic;
		nVSync : out std_logic
	);
end entity;

-- -----------------------------------------------------------------------

architecture rtl of cone_800x600_test is
	signal sysclk : std_logic;

-- Video signals
	signal hsync : std_logic;
	signal vsync : std_logic;
	signal endOfLine : std_logic;
	signal endOfFrame : std_logic;
	signal currentX : unsigned(11 downto 0);
	signal currentY : unsigned(11 downto 0);
	signal colorBarY : unsigned(7 downto 0);
	signal dither : unsigned(3 downto 0);

	signal r : unsigned(7 downto 0);
	signal g : unsigned(7 downto 0);
	signal b : unsigned(7 downto 0);
	signal rReg : unsigned(7 downto 0);
	signal gReg : unsigned(7 downto 0);
	signal bReg : unsigned(7 downto 0);
begin
-- -----------------------------------------------------------------------
-- Signal connections
-- -----------------------------------------------------------------------
	nHSync <= not hSync;
	nVSync <= not vSync;

-- -----------------------------------------------------------------------
-- Clocks and PLL
-- -----------------------------------------------------------------------
	pllInstance : entity work.pll28
		port map (
			inclk0 => clk28,
			c0 => sysclk,
			locked => open
		);

-- -----------------------------------------------------------------------
-- RGB dither
-- -----------------------------------------------------------------------
	myDither : entity work.video_dither_888to565
		port map (
			clk => sysclk,
			dither => dither,
			
			dR => rReg,
			dG => gReg,
			dB => bReg,
			qR => red,
			qG => grn,
			qB => blu
		);
	dither <= currentX(0) & currentY(0) & currentX(1) & currentY(1);

-- -----------------------------------------------------------------------
-- VGA generator
-- -----------------------------------------------------------------------
	vgaMasterInstance : entity work.video_vga_master
		port map (
			clk => sysclk,
			
			hSync => hSync,
			vSync => vSync,
			endOfLine => endOfLine,
			endOfFrame => endOfFrame,
			currentX => currentX,
			currentY => currentY,
			
			pixelSpeed => "1000000000",
			fullSpeed => '0',
			xSize => to_unsigned(1040, 12),
			ySize => to_unsigned(666, 12),
			-- What is written in manuals, but it's a little off center
--			xSyncFr => to_unsigned(856, 12),
--			xSyncTo => to_unsigned(976, 12),
--			ySyncFr => to_unsigned(637, 12),
--			ySyncTo => to_unsigned(643, 12)
			-- These settings result in centered picture on my monitor
			-- Your experiences might be different.
			xSyncFr => to_unsigned(816, 12),
			xSyncTo => to_unsigned(936, 12),
			ySyncFr => to_unsigned(625, 12),
			ySyncTo => to_unsigned(631, 12)
		);

	process(sysclk)
		variable t : unsigned(15 downto 0);
	begin
		if rising_edge(sysclk) then
			r <= (others => '0');
			g <= (others => '0');
			b <= (others => '0');

			colorBarY <= to_unsigned((to_integer(currentY) - 172), 8);

			if currentX < 800 and currentY < 600 then
				if currentX = 0 or currentX = 799 or currentY = 0 or currentY = 599 then
					r <= (others => '1');
					g <= (others => '1');
					b <= (others => '1');
				end if;
				if currentY >= 172 and currentY < 428 then
					if currentX >= 272 and currentX < 528 then
						r <= to_unsigned((to_integer(currentX) - 272), 8);
						g <= colorBarY;
						b <= (others => '0');
					end if;

					-- Black to color
					if currentX >= 32 and currentX < 64 then
						r <= colorBarY;
						g <= (others => '0');
						b <= (others => '0');
					end if;
					if currentX >= 96 and currentX < 128 then
						r <= (others => '0');
						g <= colorBarY;
						b <= (others => '0');
					end if;
					if currentX >= 160 and currentX < 192 then
						r <= (others => '0');
						g <= (others => '0');
						b <= colorBarY;
					end if;

					-- Grayscale without dither
					if currentX >= 224 and currentX < 256 then
						r <= colorBarY(7 downto 3) & "000";
						g <= colorBarY(7 downto 3) & "000";
						b <= colorBarY(7 downto 3) & "000";
					end if;

					-- White to color
					if currentX >= 736 and currentX < 768 then
						r <= colorBarY;
						g <= (others => '1');
						b <= (others => '1');
					end if;
					if currentX >= 672 and currentX < 704 then
						r <= (others => '1');
						g <= colorBarY;
						b <= (others => '1');
					end if;
					if currentX >= 608 and currentX < 640 then
						r <= (others => '1');
						g <= (others => '1');
						b <= colorBarY;
					end if;
					-- B/W
					if currentX >= 544 and currentX < 576 then
						r <= colorBarY;
						g <= colorBarY;
						b <= colorBarY;
					end if;
				end if;
			end if;
			rReg <= r;
			gReg <= g;
			bReg <= b;
		end if;
	end process;
end architecture;