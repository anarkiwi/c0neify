------------------------------------------------------------------------------
------------------------------------------------------------------------------
--                                                                          --
-- Copyright (c) 2009 Tobias Gubener <tobiflex@opencores.org>               --
--                                                                          --
-- This source file is free software: you can redistribute it and/or modify --
-- it under the terms of the GNU General Public License as published        --
-- by the Free Software Foundation, either version 3 of the License, or     --
-- (at your option) any later version.                                      --
--                                                                          --
-- This source file is distributed in the hope that it will be useful,      --
-- but WITHOUT ANY WARRANTY; without even the implied warranty of           --
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the            --
-- GNU General Public License for more details.                             --
--                                                                          --
-- You should have received a copy of the GNU General Public License        --
-- along with this program.  If not, see <http://www.gnu.org/licenses/>.    --
--                                                                          --
------------------------------------------------------------------------------
------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.STD_LOGIC_UNSIGNED.all;


entity acex is
port ( 
	ide1irq		: in std_logic;
	addonin		: in std_logic_vector(7 downto 0);
	C2MHz		: in std_logic;
	ioshift		: in std_logic;
	IOclk		: in std_logic;
	kb_clk		: inout std_logic;
	kb_data		: inout std_logic;
	ms_clk		: inout std_logic;
	ms_data		: inout std_logic;
	addonout	: out std_logic_vector(5 downto 0);
	idedata		: inout std_logic_vector(15 downto 0);
	idea		: out std_logic_vector(2 downto 0);
	ide_wr		: out std_logic;
	ide_rd		: out std_logic;
	ide_csp0	: out std_logic;
	ide_css0	: out std_logic;
	TxD			: out std_logic;
	lrclk		: out std_logic;
	adat		: out std_logic
);
end acex;


architecture wire of acex is

signal kb_clki : std_logic;
signal kb_datai : std_logic;
signal ms_clki : std_logic;
signal ms_datai : std_logic;

signal addonind: std_logic_vector(5 downto 0);
signal IDErd_data: std_logic_vector(15 downto 0);
signal ideout: std_logic_vector(15 downto 0);
signal ide_wrd : std_logic;

signal RxD : std_logic;
signal sync : std_logic;
signal lrclkd : std_logic;
signal adatd : std_logic;
signal KMline : std_logic;
signal inaction : std_logic;
signal IDEread : std_logic;

type in_states is (idle, get_addr, get_data1, get_data2, get_data3, waitread, close, send1, send2, send3, send4);
signal in_state: in_states;

type km_states is (km0, km1, km2, km3, km4, km5, km6, km7);
signal km_state: km_states;

BEGIN
-----------------------------------------------------------------
-- IO States
-----------------------------------------------------------------
idedata <= ideout WHEN ide_wrd='0' ELSE "ZZZZZZZZZZZZZZZZ";

PROCESS(IOclk)
BEGIN
	IF IOclk'event AND IOclk='1' THEN
		addonind <= addonin(5 downto 0);
		in_state <= idle;
		addonout(4 downto 0) <= "11111";
		CASE in_state IS
			WHEN idle => 
					IF inaction='0' THEN
						ide_rd <= '1';
						ide_wr <= '1';
						ide_wrd <='1';
						ide_csp0 <= '1';
						ide_css0 <= '1';
						IDEread <= '0';
					END IF;
					IF addonind="010000" THEN	--read
						in_state <= get_addr;
						inaction <= '1';
						IDEread <= '1';
					END IF;
					IF addonind="100000" THEN	--write
						in_state <= get_addr;
						inaction <= '1';
					END IF;
					IF addonind="000000" THEN	--end
						in_state <= close;
						inaction <= '0';
					END IF;
			WHEN get_addr =>
					idea <= addonind(2 downto 0);
					ide_csp0 <= addonind(4);
					ide_css0 <= addonind(5);
					IF IDEread='1' THEN --Read
						in_state <= waitread;
					ELSE				--Write
						in_state <= get_data1;
					END IF;
			WHEN waitread =>
					ide_rd <= '0';
					
			WHEN get_data1 => 
					ide_wr <= '0';
					in_state <= get_data2;
					ideout(5 downto 0) <= addonind(5 downto 0);
			WHEN get_data2 => 
					in_state <= get_data3;
					ideout(11 downto 6) <= addonind(5 downto 0);
			WHEN get_data3 =>
					ideout(15 downto 12) <= addonind(3 downto 0);
					ide_wrd <='0';
					
			WHEN close =>
					ide_wr <= '1';
					ide_rd <= '1';
					IDErd_data <= idedata;
					IF IDEread='1' THEN
						in_state <= send1;
					END IF;
					
			WHEN send1 =>
					ide_wrd <='1';
					ide_csp0 <= '1';
					ide_css0 <= '1';
					in_state <= send2;
					addonout(3 downto 0) <= IDErd_data(3 downto 0);
			WHEN send2 =>
					in_state <= send3;
					addonout(3 downto 0) <= IDErd_data(7 downto 4);
			WHEN send3 =>
					in_state <= send4;
					addonout(3 downto 0) <= IDErd_data(11 downto 8);
			WHEN send4 =>
					addonout(3 downto 0) <= IDErd_data(15 downto 12);
			WHEN OTHERS => null;
		END CASE;
	END IF;
END PROCESS; 

-------------------------------------------------------------------
--  TRANSMITTER
-------------------------------------------------------------------
kb_clk <= '0' WHEN kb_clki='0' ELSE 'Z'; 
kb_data <= '0' WHEN kb_datai='0' ELSE 'Z'; 
ms_clk <= '0' WHEN ms_clki='0' ELSE 'Z'; 
ms_data <= '0' WHEN ms_datai='0' ELSE 'Z'; 

PROCESS(IOclk)
BEGIN
	IF IOclk'event AND IOclk='1' THEN
		addonout(5) <= '1';
		CASE km_state IS
			WHEN km0 => addonout(5) <= sync;		--toggle flag for sync
						km_state <=km1;
			WHEN km1 => addonout(5) <= kb_data;
						km_state <=km2;
			WHEN km2 => addonout(5) <= kb_clk;
						km_state <=km3;
			WHEN km3 => addonout(5) <= ms_data;
						km_state <=km4;
			WHEN km4 => addonout(5) <= ms_clk;
						km_state <=km5;
			WHEN km5 => addonout(5) <= RxD;
						km_state <=km6;
			WHEN km6 => addonout(5) <= C2MHz;
						km_state <=km7;
			WHEN km7 => addonout(5) <= ioshift;
						sync <= NOT sync;
						km_state <=km0;
			WHEN OTHERS => 
						km_state <=km0;
		END CASE;	
	END IF;
END PROCESS; 

-------------------------------------------------------------------
--  RESEIVER
-------------------------------------------------------------------
PROCESS(C2MHz)
BEGIN
	IF C2MHz'event AND C2MHz='0' THEN
		adat <= adatd;
		lrclk <= lrclkd;
	END IF;
END PROCESS; 

PROCESS(IOclk)
BEGIN
	IF IOclk'event AND IOclk='1' THEN
	KMline <= addonin(7);
		CASE km_state IS
			WHEN km0 => lrclkd <= KMline;
			WHEN km1 => adatd <= KMline;
--			WHEN km2 =>  <= KMline;
			WHEN km3 => kb_datai <= KMline;
			WHEN km4 => kb_clki <= KMline;
			WHEN km5 => ms_datai <= KMline;
			WHEN km6 => ms_clki <= KMline;
			WHEN km7 => TxD <= KMline;
			WHEN OTHERS => null;
		END CASE;
	END IF;
END PROCESS; 

END;  
