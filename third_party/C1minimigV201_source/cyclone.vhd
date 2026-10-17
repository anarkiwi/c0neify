------------------------------------------------------------------------------
------------------------------------------------------------------------------
--                                                                          --
-- Copyright (c) 2009 Tobias Gubener                                        -- 
-- Subdesign FamPiGA by TobiFlex                                            --
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


entity cyclone is
   port ( 
	sysclk: in std_logic;
	IOclk: in std_logic;
	addonin: in std_logic;
	addonout: out std_logic;
	
	TxD: in std_logic;
	kb_clki: in std_logic;
	kb_datai: in std_logic;
	ms_clki: in std_logic;
	ms_datai: in std_logic;
	kb_clk: out std_logic;
	kb_data: out std_logic;
	ms_clk: out std_logic;
	ms_data: out std_logic;
	JoyA: out std_logic_vector(5 downto 0);
	JoyB: out std_logic_vector(5 downto 0);
	left: in std_logic_vector(15 downto 0);
	right: in std_logic_vector(15 downto 0);
	syncOK: buffer std_logic
  );

end cyclone;
 

architecture wire of cyclone is

signal C2MHz: std_logic;
signal C2MHzd: std_logic;
signal lrclk: std_logic;
signal jshift: std_logic_vector(15 downto 0);
signal ioshift: std_logic;
signal addon_out: std_logic;

--	signal idedatad: std_logic_vector(14 downto 0);
--	signal dmuxd: std_logic_vector(14 downto 0);
--	signal dmux: std_logic_vector(15 downto 0);		
signal shift: std_logic_vector(16 downto 0);		
signal count: std_logic_vector(4 downto 0);		
--	signal sync: std_logic;			
--	signal addonout: std_logic_vector(8 downto 0);		
--	signal syncshift: std_logic_vector(6 downto 0);		
--	signal inbuf : std_logic_vector(7 downto 0);


signal kmshiftin: std_logic_vector(8 downto 0);
--signal kmshiftout: std_logic_vector(7 downto 0);
signal km_cnt: std_logic_vector(3 downto 0);
--signal km_cnt: std_logic_vector(3 downto 0);
signal insync: std_logic_vector(3 downto 0);
--signal addonind: std_logic_vector(7 downto 0);
--signal in_id: std_logic_vector(7 downto 0);
--signal in_addr: std_logic_vector(7 downto 0);
--signal in_data: std_logic_vector(15 downto 0);
--signal IDErd_data: std_logic_vector(15 downto 0);
--signal ideout: std_logic_vector(15 downto 0);
--signal ide_wrd : std_logic;
--signal IDEwait			 : std_logic_vector(6 downto 0);

signal RxD : std_logic;
--signal addonind : std_logic;
BEGIN


-------------------------------------------------------------------
--  TRANSMITTER
-------------------------------------------------------------------
PROCESS(sysclk)
BEGIN
   	IF sysclk'event AND sysclk = '0' THEN
		IF IOclk='1' THEN
			addonout <= addon_out;
		END IF;
	END IF;
END PROCESS; 

PROCESS(sysclk)
BEGIN
   	IF sysclk'event AND sysclk = '1' THEN
		IF IOclk='0' THEN
			addon_out <= '1';
			IF syncOK='1' THEN
				CASE km_cnt(2 downto 0) IS
					WHEN "000" => addon_out <= km_cnt(3);
					WHEN "001" => addon_out <= kb_datai;
					WHEN "010" => addon_out <= kb_clki;
					WHEN "011" => addon_out <= ms_datai;
					WHEN "100" => addon_out <= ms_clki;
					WHEN "101" => addon_out <= TxD;
					WHEN "110" => addon_out <= lrclk;
					WHEN "111" => addon_out <= shift(16);
					WHEN OTHERS => null;
				END CASE;	
			END IF;	
		END IF;	
	END IF;
END PROCESS; 

-------------------------------------------------------------------
--  RESEIVER
-------------------------------------------------------------------
PROCESS(sysclk)
BEGIN
   	IF sysclk'event AND sysclk = '1' THEN
		IF IOclk='0' THEN
			kmshiftin <= kmshiftin(7 downto 0) & addonin;
			km_cnt <= km_cnt+1;
			IF syncOK='1' THEN
				CASE km_cnt(2 downto 0) IS
					WHEN "000" => C2MHz <= kmshiftin(0);
					WHEN "001" => ioshift <= kmshiftin(0);
	--				WHEN "010" => km_cnt(3) <= kmshiftin(0);
					WHEN "011" => kb_data <= kmshiftin(0);
					WHEN "100" => kb_clk <= kmshiftin(0);
					WHEN "101" => ms_data <= kmshiftin(0);
					WHEN "110" => ms_clk <= kmshiftin(0);
					WHEN "111" => RxD <= kmshiftin(0);
					WHEN OTHERS => null;
				END CASE;	
			END IF;	
			IF km_cnt(2 downto 0)="010" THEN
				IF kmshiftin(8)=kmshiftin(0) THEN
					km_cnt(2 downto 0) <= "010";
					insync <= "0000";
					syncOK <= '0';
				ELSE
					IF insync="1111" THEN
						syncOK <= '1';
					ELSE
						insync <= insync+1;
						km_cnt(3) <= kmshiftin(0);
					END IF;
				END IF;
			END IF;	
		END IF;	
	END IF;
END PROCESS; 

-------------------------------------------------------------------
--  SOUND Audioshifter
-------------------------------------------------------------------
PROCESS(sysclk)
BEGIN
	IF sysclk'event AND sysclk = '1' THEN
		C2MHzd <= C2MHz;
		IF C2MHzd='1' AND C2MHz='0' THEN
			IF count=0 then	
				count <= "10111";--23
				lrclk <= NOT lrclk;				
--				shift <= ("00111111111111111");			--max output	
				IF lrclk='1' THEN
--					IF target='1' THEN						
						shift <= ('0'&left);
--					ELSE				
--						shift <= ('0'&sleft);				
--					END IF;
				ELSE
--					IF target='1' THEN						
						shift <= ('0'&right);			
--					ELSE				
--						shift <= ('0'&sright);			
--					END IF;
				END IF;
			ELSE
				count <= count-1;
				IF count<17 THEN
					shift <= (shift(15 downto 0)&'0');
				END IF;
			END IF;
		END IF;
	END IF;
END PROCESS; 

-------------------------------------------------------------------
-- Joystick
-------------------------------------------------------------------
PROCESS(sysclk)
BEGIN
	IF sysclk'event AND sysclk = '1' THEN
		IF C2MHzd='0' AND C2MHz='1' THEN
			IF jshift(15)='0' THEN
				jshift <=("111111111111111"&ioshift);
	--				lpt_bsy=NOT jshift(14);
	--				JoyA<=('1'&jshift(8)&jshift(11 downto 9)&jshift(7));
	--				JoyB<=('1'&jshift(5)&jshift(2)&jshift(3)&jshift(4)&jshift(6));
				JoyA<=('1'&jshift(8)&jshift(7)&jshift(9)&jshift(10)&jshift(11));
				JoyB<=('1'&jshift(5)&jshift(6)&jshift(4)&jshift(3)&jshift(2));
			ELSE
				jshift<=(jshift(14 downto 0)&ioshift);
			END IF;
		END IF;
	END IF;
END PROCESS; 

END;  
