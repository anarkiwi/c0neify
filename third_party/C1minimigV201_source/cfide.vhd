------------------------------------------------------------------------------
------------------------------------------------------------------------------
--                                                                          --
-- Copyright (c) 2008-2009 Tobias Gubener                                   -- 
-- Subdesign fAMpIGA by TobiFlex                                            --
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

 
entity cfide is
   port ( 
	addin: in std_logic_vector(4 downto 0);		
	acexclk: in std_logic;	
	sysclk: in std_logic;	
	n_reset: in std_logic;	
	cpuena_in: in std_logic;			
	memdata_in: in std_logic_vector(15 downto 0);		
	addr: in std_logic_vector(23 downto 0);		
	cpudata_in: in std_logic_vector(15 downto 0);	
	state: in std_logic_vector(1 downto 0);		
	lds: in std_logic;			
	uds: in std_logic;			
	mdb: in std_logic_vector(7 downto 0);--for C-One		
	sd_di		: in std_logic;
		
	addout: out std_logic_vector(6 downto 0);		
--	idea: out std_logic_vector(2 downto 0);		
--	ide_wr: out std_logic;			
--	ide_rd: out std_logic;			
--	ide_csp0: out std_logic;			
--	ide_css0: out std_logic;			
--	ide_csp1: buffer std_logic;	
			
	memce: out std_logic;			
	cpudata: out std_logic_vector(15 downto 0);		
	cpuena: buffer std_logic;			
	TxD: out std_logic;			
	sd_cs 		: out std_logic_vector(7 downto 0);
	sd_clk 		: out std_logic;
	sd_do		: out std_logic;
	locked: in std_logic;--for C-One
	
	A_addr: in std_logic_vector(23 downto 0);		
	A_cpudata_in: in std_logic_vector(15 downto 0);	
	A_rw: in std_logic;
	A_selide: in std_logic;
	A_cpudata: buffer std_logic_vector(15 downto 0);		
	A_iderdy: buffer std_logic;
	ideirq: out std_logic;
	support_run: buffer std_logic;
	sd_dimm		: in std_logic;		--for sdcard
	enaWRreg    : in std_logic:='1';
	IOclk    : buffer std_logic;
	syncOK: in std_logic
   );

end cfide;


architecture wire of cfide is

	COMPONENT startram
    PORT 
	(
		address		: IN STD_LOGIC_VECTOR (10 DOWNTO 0);
		byteena		: IN STD_LOGIC_VECTOR (1 DOWNTO 0);
		clock		: IN STD_LOGIC ;
		data		: IN STD_LOGIC_VECTOR (15 DOWNTO 0);
		wren		: IN STD_LOGIC ;
		q		: OUT STD_LOGIC_VECTOR (15 DOWNTO 0)
    );
	END COMPONENT;




signal partshift: std_logic_vector(39 downto 0); --for C-One
signal mdbd: std_logic;--for C-One
signal mdcdd: std_logic;--for C-One
signal mdcd: std_logic;--for C-One
signal shift: std_logic_vector(9 downto 0);
signal clkgen: std_logic_vector(9 downto 0);
signal shiftout: std_logic;
signal txbusy: std_logic;
signal ld: std_logic;
signal rs232_select: std_logic;
signal KEY_select: std_logic;
signal PART_select: std_logic;
signal SPI_select: std_logic;
signal ROM_select: std_logic;
signal ide_select: std_logic;
signal RAM_write: std_logic;
signal rs232data: std_logic_vector(15 downto 0);
signal part_in: std_logic_vector(15 downto 0);
signal IOdata: std_logic_vector(15 downto 0);
signal IDErd_data: std_logic_vector(15 downto 0);
signal IOcpuena: std_logic;

type micro_states is (idle, io_aktion, ide1, set_addr, set_data1, set_data2, set_data3, read1, read2, read3, read4, waitclose, setwaitend, waitend);
signal micro_state		: micro_states;
signal next_micro_state		: micro_states;

type support_states is (idle, io_aktion);
signal support_state		: support_states;
signal next_support_state		: support_states;

signal sd_out	: std_logic_vector(15 downto 0);
signal sd_in	: std_logic_vector(15 downto 0);
signal sd_di_in	: std_logic;
signal spi_word	: std_logic;
signal shiftcnt	: std_logic_vector(4 downto 0);
signal sck		: std_logic;
signal scs		: std_logic_vector(7 downto 0);
signal SD_busy		: std_logic;
signal spi_div: std_logic_vector(7 downto 0);
signal spi_speed: std_logic_vector(7 downto 0);
signal rom_data: std_logic_vector(15 downto 0);

signal idesel		: std_logic;
signal Z_iderdy		: std_logic;
signal addr1d		: std_logic;

signal IDEwait			 : std_logic_vector(6 downto 0);
signal ide_data	 		 : std_logic_vector(15 downto 0);	--$00	; r/w
signal ide_error	     : std_logic_vector(7 downto 0);	--$04	; r
signal ide_features		 : std_logic_vector(7 downto 0);	--$04	; w
signal ide_scount		 : std_logic_vector(7 downto 0);	--$08	; r/w
signal ide_lba0	    	 : std_logic_vector(7 downto 0);	--$0c	; r/w
signal ide_lba1	   	 	 : std_logic_vector(7 downto 0);	--$10	; r/w
signal ide_lba2	    	 : std_logic_vector(7 downto 0);	--$14	; r/w
signal ide_lba3	   	     : std_logic_vector(7 downto 0);	--$18	; r/w
signal ide_status	     : std_logic_vector(7 downto 0);	--$1c	; r
signal ide_command		 : std_logic_vector(7 downto 0);	--$1c	; w
signal testirq		 	 : std_logic;
signal testirqd		 	 : std_logic;
signal A_selide_now 	 : std_logic;
signal ide_direkt	 	 : std_logic;
--signal support_run	 	 : std_logic;
signal multiblock: std_logic_vector(16 downto 0);
signal blocksize: std_logic_vector(7 downto 0);
signal blockcnt: std_logic_vector(9 downto 0);
signal singleblock: std_logic_vector(9 downto 0);
signal timecnt: std_logic_vector(15 downto 0);
signal timeprecnt: std_logic_vector(15 downto 0);
--signal set_irq2		 	 : std_logic;
signal support_start	 	 : std_logic;
signal support_cycle	 	 : std_logic;
signal no_multiple	 	 : std_logic;
signal delayena	 	 : std_logic;

--type out_states is (idle, set_addr, set_data1, set_data2, read1, read2, read3, read4, read5, write1);
--signal out_state: out_states;
signal addind: std_logic_vector(4 downto 0);
--signal startIO	 	 : std_logic;
--signal iorun	 	 : std_logic;
--signal startIOd	 	 : std_logic;
--signal iorund	 	 : std_logic;
--signal IOclk	 	 : std_logic;
signal addonout: std_logic_vector(6 downto 0);
signal idedata: std_logic_vector(15 downto 0);

begin

process(sysclk, shift, IDErd_data, A_addr, support_run, A_rw)
begin
	ide_direkt <= '0';
--	IF A_selide='1' AND A_addr(0)='0' THEN
		A_cpudata(15 downto 8) <= IDErd_data(7 downto 0);
		A_cpudata(7 downto 0) <= IDErd_data(15 downto 8);
		CASE A_addr(4 downto 2) IS
			WHEN "000" => 	--IF ide_command=X"EC" THEN 		--IDENTIFY
							--A_cpudata(15 downto 0) <= ide_data;
--							ELSE
								ide_direkt <= '1';
--							END IF;	
			WHEN "001" => --A_cpudata(15 downto 8) <= ide_error;
--							IF A_rw='1' AND A_addr(0)='0' THEN
								ide_direkt <= '1';
--							END IF;		
			WHEN "010" => 	--A_cpudata(15 downto 8) <= ide_scount;
								ide_direkt <= '1';
			WHEN "011" =>   --A_cpudata(15 downto 8) <= ide_lba0;
								ide_direkt <= '1';
			WHEN "100" =>   --A_cpudata(15 downto 8) <= ide_lba1;
								ide_direkt <= '1';
			WHEN "101" =>   --A_cpudata(15 downto 8) <= ide_lba2;
								ide_direkt <= '1';
			WHEN "110" =>   --A_cpudata(15 downto 8) <= ide_lba3;
								ide_direkt <= '1';
			WHEN "111" => --A_cpudata(15 downto 8) <= ide_status;
--							IF A_selide='1' AND A_rw='0' AND A_addr(0)='0' THEN
--							IF A_rw='0' AND A_addr(0)='0' THEN
--							IF support_run='0' AND A_rw='1' THEN	--direkt lesen
--								ide_direkt <= '1';
--							ELSE
--								A_cpudata(15 downto 8) <= X"D0";	--busy/not ready
--							END IF;		

							IF support_run='0' OR A_rw='0' THEN	--direkt schreiben
								ide_direkt <= '1';
							ELSE
								A_cpudata(15 downto 8) <= X"D0";	--busy/not ready
							END IF;		
			WHEN OTHERS => null;
		END CASE;
--	END IF;		

	IF n_reset ='0' THEN 
		blocksize <= "00000001";
   	ELSIF sysclk'event AND sysclk = '1' THEN
	IF enaWRreg='1' THEN
		testirq <= '0';
		testirqd <= '0';
--		IF PART_select='1' AND state="11" THEN
--			ideirq <= cpudata_in(15);
--			support_run <= cpudata_in(14);
--		END IF;
--		IF support_cycle='1' AND micro_state=ide5 AND IDErd_data(7)='0' THEN
--			ideirq <= '1';
			support_run <= '0';
--		END IF;
--if amiga read the ide status reset the irq2		
		IF A_selide='1' AND A_rw='1' AND A_addr(4 downto 2)="111" THEN
--		IF A_selide='1' AND A_addr(0)='0' AND A_addr(4 downto 2)="111" THEN
			ideirq <='0';
		END IF;
--		IF micro_state=ide5 AND idesel='1' AND A_addr(4 downto 2)="000" THEN
--			multiblock <= multiblock+1;
--			testirq <= '1';
--		END IF;
		IF testirq='1' AND multiblock(7 downto 0)=X"00" THEN	--micro_state=ide6
			IF multiblock(15 downto 8)=singleblock(7 downto 0) OR
			   multiblock(15 downto 8)=blockcnt(7 downto 0)THEN
				testirqd <= testirq;
				multiblock(15 downto 8) <= (OTHERS => '0');
				blockcnt <= blockcnt-singleblock;
--				IF singleblock<blockcnt THEN
--					ideirq <='1';
--				END IF;
			END IF;
		END IF;
		IF testirqd='1' THEN	--micro_state=ide7
			IF (blockcnt(9)='0' AND blockcnt/=0) OR ide_command=X"C5" OR ide_command=X"30" OR ide_command=X"31" THEN
--				ideirq <='1';
				support_run <= '1';
			END IF;
		END IF;
		IF A_selide='1' AND A_rw='0' AND A_addr(0)='0' THEN
			CASE A_addr(4 downto 2) IS
				WHEN "000" => ide_data 		<= A_cpudata_in(15 downto 0);
				WHEN "001" => ide_features 	<= A_cpudata_in(15 downto 8);
				WHEN "010" => ide_scount 	<= A_cpudata_in(15 downto 8);
				WHEN "011" => ide_lba0 		<= A_cpudata_in(15 downto 8);
				WHEN "100" => ide_lba1 		<= A_cpudata_in(15 downto 8);
				WHEN "101" => ide_lba2 		<= A_cpudata_in(15 downto 8);
				WHEN "110" => ide_lba3 		<= A_cpudata_in(15 downto 8);
				WHEN "111" => 	ide_command <= A_cpudata_in(15 downto 8);
								support_run <='1';
								multiblock <= (OTHERS => '0');
								IF A_cpudata_in(15 downto 8)=X"C6" THEN	--SET MULTIPLE MODE
									blocksize <= ide_scount;
								END IF;
								IF A_cpudata_in(15 downto 8)=X"C4" OR A_cpudata_in(15 downto 8)=X"C5" THEN	--READ MULTIPLE & WRITE MULTIPLE
									blockcnt <= "00"&ide_scount;
									IF ide_scount=0 THEN
										blockcnt(8) <= '1';
									END IF;
									singleblock <= "00"&blocksize;
									IF blocksize=0 THEN
										singleblock(8) <= '1';
									END IF;
--								ELSE	
--									blockcnt <= "00000001";
								END IF;
								IF A_cpudata_in(15 downto 8)=X"20" OR A_cpudata_in(15 downto 8)=X"21" 	--READ SECTOR 
									OR A_cpudata_in(15 downto 8)=X"30" OR A_cpudata_in(15 downto 8)=X"31" --WRITE SECTOR
									OR A_cpudata_in(15 downto 8)=X"40" OR A_cpudata_in(15 downto 8)=X"41" THEN --VERIFY SECTOR
									blockcnt <= "00"&ide_scount;
									IF ide_scount=0 THEN
										blockcnt(8) <= '1';
									END IF;
									singleblock <= "0000000001";
								END IF;
				WHEN OTHERS => null;
			END CASE;
		END IF;		
	END IF;		
	END IF;		
END PROCESS;

srom: startram
	PORT MAP 
	(
		address => addr(11 downto 1),	--: IN STD_LOGIC_VECTOR (11 DOWNTO 0);
		byteena(0)	=> not lds,			--	: IN STD_LOGIC_VECTOR (1 DOWNTO 0),
		byteena(1)	=> not uds,			--	: IN STD_LOGIC_VECTOR (1 DOWNTO 0),
		clock   => sysclk,								--: IN STD_LOGIC ;
		data	=> cpudata_in,		--	: IN STD_LOGIC_VECTOR (15 DOWNTO 0),
		wren	=> RAM_write AND enaWRreg,		-- 	: IN STD_LOGIC ,
		q		=> rom_data									--: OUT STD_LOGIC_VECTOR (15 DOWNTO 0)
    );




memce <= '0' WHEN ROM_select='0' AND addr(23)='0' ELSE '1';
cpudata <=  rom_data WHEN ROM_select='1' ELSE 
			IOdata WHEN IOcpuena='1' ELSE
			part_in WHEN PART_select='1' ELSE 
			memdata_in;
part_in <= 
			partshift(39 downto 24) WHEN addr(4 downto 1)="0000" ELSE	--DEE000 --for C-One		
			partshift(23 downto 8) WHEN addr(4 downto 1)="0001" ELSE	--DEE002 --for C-One		
			partshift(7 downto 0)&multiblock(15 downto 8) WHEN addr(4 downto 1)="0010" ELSE--DEE004 --for C-One
--			ide_data WHEN addr(4 downto 1)="0011" ELSE		--DEE006
			support_run&"XXXXXXX"&ide_command(7 downto 0) WHEN addr(4 downto 1)="0100" ELSE--DEE008
			ide_features&ide_scount WHEN addr(4 downto 1)="0101" ELSE	--DEE00A
			ide_lba3&ide_lba2 WHEN addr(4 downto 1)="0110" ELSE	--DEE00C
			ide_lba1&ide_lba0 WHEN addr(4 downto 1)="0111" ELSE	--DEE00E
			timecnt WHEN addr(4 downto 1)="1000" ELSE	--DEE010
			"XXXXXXXX"&syncOK&"0000001";-- WHEN addr(4 downto 1)="1001" ELSE	--DEE012
			
			
IOdata <=   --rs232data WHEN rs232_select='1' ELSE 
			sd_in WHEN SPI_select='1' ELSE
			IDErd_data(7 downto 0)&IDErd_data(15 downto 8);
cpuena <= '1' WHEN ROM_select='1' OR PART_select='1' ELSE
		  IOcpuena WHEN rs232_select='1' OR ide_select='1' OR SPI_select='1' ELSE 
		  cpuena_in; 

rs232data <= X"FFFF" WHEN txbusy='1' ELSE X"0000";

RAM_write <= '1' when ROM_select='1' AND state="11" ELSE '0';
ROM_select <= '1' when addr(23 downto 12)=X"000" ELSE '0';
rs232_select <= '1' when addr(23 downto 12)=X"DA8" ELSE '0';
ide_select <= '1' when addr(23 downto 14)="1101101000" ELSE '0';
KEY_select <= '1' when addr(23 downto 12)=X"DE0" ELSE '0';
PART_select <= '1' when addr(23 downto 12)=X"DEE" ELSE '0';
SPI_select <= '1' when addr(23 downto 12)=X"DA4" ELSE '0';

idedata <= cpudata_in(7 downto 0)&cpudata_in(15 downto 8) WHEN idesel='0' ELSE A_cpudata_in(7 downto 0)&A_cpudata_in(15 downto 8);
--idea <= "111" WHEN support_cycle='1' ELSE addr(4 downto 2) WHEN idesel='0' ELSE  A_addr(4 downto 2);

-----------------------------------------------------------------
-- Support States
-----------------------------------------------------------------
process(sysclk, shift)
begin
   	IF sysclk'event AND sysclk = '1' THEN
	IF enaWRreg='1' THEN
		support_state <= idle;
		ld <= '0';
		IOcpuena <= '0';
		delayena <= '0';
		CASE support_state IS
			WHEN idle => 
--				IF ide_select='1' AND (addr(12)='0' OR addr(13)='0') THEN
				IF ide_select='1' THEN
					IF (micro_state=setwaitend AND support_cycle='0' AND idesel='0') OR delayena='1' THEN
						support_state <= io_aktion;
						IOcpuena <= '1';
					END IF;	
				ELSIF rs232_select='1' AND state="11" THEN
					IF txbusy='0' THEN
						ld <= '1';
						support_state <= io_aktion;
						IOcpuena <= '1';
					END IF;	
				ELSIF SPI_select='1' THEN		
					IF SD_busy='0' THEN
						support_state <= io_aktion;
						IOcpuena <= '1';
					END IF;
--				ELSIF addr(23)='1' AND state(1)='1' THEN
--					support_state <= io_aktion;
--					IOcpuena <= '1';
				END IF;
					
			WHEN io_aktion => 
--				IF enaWRreg='1' THEN
					support_state <= idle;
--				ELSE
--					support_state <= io_aktion;
--					IOcpuena <= '1';
--				END IF;
				
			WHEN OTHERS => 
				support_state <= idle;
		END CASE;
	ELSIF support_state=idle AND micro_state=setwaitend AND support_cycle='0' AND idesel='0' THEN
		delayena <= '1';
	END IF;	
	END IF;	
end process; 

-----------------------------------------------------------------
-- main States
-----------------------------------------------------------------
A_selide_now <= '1' WHEN A_selide='1' AND ide_direkt='1' ELSE '0';	

process(sysclk, shift, Z_iderdy, addr1d, A_addr, ide_direkt)
begin
	IF (Z_iderdy='1' AND addr1d=A_addr(1)) OR ide_direkt='0' THEN
		A_iderdy <= '1';
	ELSE
		A_iderdy <= '0';
	END IF;
   	IF sysclk'event AND sysclk = '1' THEN
		IF A_selide_now='0' OR addr1d/=A_addr(1) THEN
			Z_iderdy <= '0';
		END IF;	
--		IF A_selide_now='1' AND A_iderdy='0' THEN
		IF A_selide_now='1' THEN
--			IF micro_state=ide6 AND support_cycle='0' AND idesel='1' THEN
				Z_iderdy <= '1';
--			END IF;	
		END IF;
	END IF;	
end process; 



-------------------------------------------------------------------
---- IO States
-------------------------------------------------------------------
--PROCESS(acexclk)
--BEGIN
--	IF acexclk'event AND acexclk='1' THEN
----		startIOd <= startIO;
--		addind <= addin;
--		out_state <= idle;
--		CASE out_state IS
--			WHEN idle => 
--					IF startIOd='1' AND syncOK='1' THEN
----						iorun <='1';
--						IF state="11" THEN
--							addout(1) <= '0';
--						END IF;	
--						IF state="10" THEN
--							addout(0) <= '0';
--						END IF;	
--						out_state <= set_addr;
--					END IF;
--			WHEN set_addr => 
--					addout(2 downto 0) <= addr(4 downto 2); 
----					IF addr(13 downto 12)="01" THEN
--						addout(6) <= '0';
--						addout(4) <= '0';
----					END IF;
--					IF state="11" THEN
--						out_state <= set_data1;
--					ELSE
--						out_state <= read1;
--					END IF;
--			WHEN set_data1 => 
--					out_state <= set_data2;
--					addout <= cpudata_in(15 downto 8);		--Byte swap
--			WHEN set_data2 =>
--					out_state <= write1;
--					addout <= cpudata_in(7 downto 0);		--Byte swap
--			WHEN write1 =>
--					IF addind(3 downto 0)="1110" THEN
--						out_state <= read5;
--					ELSE
--						out_state <= write1;
--					END IF;
--			WHEN read1 =>
--					IF addind(3 downto 0)="1110" THEN
--						out_state <= read2;
--						IDErd_data(0) <= addind(4);
--					ELSE
--						out_state <= read1;
--					END IF;
--			WHEN read2 =>
--					out_state <= read3;
--					IDErd_data(5 downto 1) <= addind(4 downto 0);
--			WHEN read3 =>
--					out_state <= read4;
--					IDErd_data(10 downto 6) <= addind(4 downto 0);
--			WHEN read4 =>
--					out_state <= read5;
--					IDErd_data(15 downto 11) <= addind(4 downto 0);
--			WHEN read5 =>
----					IF startIOd='0' THEN
----						iorun <='0';
----					ELSE
----						out_state <= read5;
----					END IF;
--			WHEN OTHERS => null;
--		END CASE;
--	END IF;
--END PROCESS; 

-----------------------------------------------------------------
-- IDE States
-----------------------------------------------------------------
process(sysclk, shift)
begin
   	IF sysclk'event AND sysclk = '0' THEN
		IF IOclk='1' THEN
			addout <= addonout;
		END IF;
	END IF;
	
   	IF sysclk'event AND sysclk = '1' THEN
		IOclk <= NOT IOclk;
		no_multiple <= '0';
					
		IF IOclk='0' THEN
			IDEwait <= IDEwait-1;
			micro_state <= idle;
			addonout <= "1111111";
			addind <= addin;
			CASE micro_state IS
				WHEN ide1 =>
						IF state="11" THEN
							addonout(4) <= '0';
						END IF;	
						IF state="10" THEN
							addonout(5) <= '0';
						END IF;
						addonout(3 downto 0) <= "0000";
						micro_state <= set_addr;
				WHEN set_addr => 
						addonout(3 downto 0) <= addr(5 downto 2); 
	--					IF addr(13 downto 12)="01" THEN
							addonout(4) <= addr(12);		--CSP0
							addonout(5) <= addr(13);		--CSS0
	--					END IF;
						IF state="11" THEN
							micro_state <= set_data1;
						ELSE
							micro_state <= waitclose;
							IDEwait <= "0001010";	--56MHz
						END IF;
				WHEN set_data1 => 
						micro_state <= set_data2;
						addonout(5 downto 0) <= idedata(5 downto 0);
				WHEN set_data2 => 
						micro_state <= set_data3;
						addonout(5 downto 0) <= idedata(11 downto 6);
				WHEN set_data3 =>
						micro_state <= waitclose;
						addonout(3 downto 0) <= idedata(15 downto 12);
						IDEwait <= "0001010";	--56MHz
				WHEN waitclose =>
						IF IDEwait="0000000" THEN
							addonout(5 downto 0) <= "000000";	--close IDE
							IF state="11" THEN
								micro_state <= setwaitend;
							ELSE
								micro_state <= read1;
								IDEwait <= "0000101";
							END IF;
						ELSE
							micro_state <= waitclose;
						END IF;
						
						
				WHEN read1 =>
						IF IDEwait="0000000" THEN
							micro_state <= read2;
						ELSE
							micro_state <= read1;
						END IF;
						IDErd_data(3 downto 0) <= addind(3 downto 0);
				WHEN read2 =>
						micro_state <= read3;
						IDErd_data(7 downto 4) <= addind(3 downto 0);
				WHEN read3 =>
						micro_state <= read4;
						IDErd_data(11 downto 8) <= addind(3 downto 0);
				WHEN read4 =>
						micro_state <= setwaitend;
						IDErd_data(15 downto 12) <= addind(3 downto 0);
				WHEN setwaitend =>
						IDEwait <= "0000101";	--56MHz
						micro_state <= waitend;
				WHEN waitend =>
						IF IDEwait/="0000000" THEN
							micro_state <= waitend;
						END IF;
				WHEN OTHERS => null;
			END CASE;
		END IF;	
		
		IF micro_state= idle AND enaWRreg='1' THEN
			idesel <= '0';
			support_cycle <= '0';
			support_start <= support_run and not support_cycle;
--				IF ide_select='1' AND (addr(12)='0' OR addr(13)='0') THEN
			IF ide_select='1' THEN
				micro_state <= ide1;
--				ELSIF A_selide_now='1' AND A_iderdy='0' THEN
--					idesel <= '1';
--					micro_state <= ide1;
----					IDEwait <= "0010000";	--56MHz
--					IDEwait <= "0000110";	--14MHz
--					ide_csp0 <= A_addr(12);
----					ide_csp1 <= A_addr(13);
--					ide_wr <= A_rw;
--					ide_rd <= NOT A_rw;
--					addr1d <= A_addr(1);
--				ELSIF support_start='1' THEN	--read ide busy ?
--					support_start <= '0';
--					support_cycle <= '1';
--					micro_state <= ide1;
----					IDEwait <= "0010000";	--56MHz
--					IDEwait <= "0000110";	--14MHz
--					ide_csp0 <= '0';
--					ide_rd <= '0';
			END IF;
		END IF;
	END IF;	
end process; 


-----------------------------------------------------------------
-- SPI-Interface
-----------------------------------------------------------------	
	sd_cs <= NOT scs;
	sd_clk <= NOT sck;
	sd_do <= sd_out(15);
	SD_busy <= shiftcnt(4);
	
	PROCESS (sysclk, n_reset, scs, sd_di, sd_dimm) BEGIN
--		IF (sysclk'event AND sysclk='0') THEN
			IF scs(1)='1' THEN
				sd_di_in <= sd_di;
			ELSE	
				sd_di_in <= sd_dimm;
			END IF;
--		END IF;
		IF n_reset ='0' THEN 
			shiftcnt <= (OTHERS => '0');
			spi_div <= (OTHERS => '0');
			scs <= (OTHERS => '0');
			sck <= '0';
			spi_speed <= "00000000";
		ELSIF (sysclk'event AND sysclk='1') THEN
		IF enaWRreg='1' THEN
			IF SPI_select='1' AND state="11" AND SD_busy='0' THEN	 --SD write
				IF addr(3)='1' THEN				--DA4008
					spi_speed <= cpudata_in(7 downto 0);
				ELSIF addr(2)='1' THEN				--DA4004
					scs(0) <= not cpudata_in(0);
					IF cpudata_in(7)='1' THEN
						scs(7) <= not cpudata_in(0);
					END IF;
					IF cpudata_in(6)='1' THEN
						scs(6) <= not cpudata_in(0);
					END IF;
					IF cpudata_in(5)='1' THEN
						scs(5) <= not cpudata_in(0);
					END IF;
					IF cpudata_in(4)='1' THEN
						scs(4) <= not cpudata_in(0);
					END IF;
					IF cpudata_in(3)='1' THEN
						scs(3) <= not cpudata_in(0);
					END IF;
					IF cpudata_in(2)='1' THEN
						scs(2) <= not cpudata_in(0);
					END IF;
					IF cpudata_in(1)='1' THEN
						scs(1) <= not cpudata_in(0);
					END IF;
				ELSE							--DA4000
					spi_div <= spi_speed;
					sd_out <= cpudata_in(15 downto 0);
					IF uds='0' AND lds='0' THEN
						shiftcnt <= "11111";
						spi_word <= '1';
					ELSE
						shiftcnt <= "10111";
						spi_word <= '0';
					END IF;
--					IF uds='1' THEN
--						sd_out(15 downto 8) <= cpudata_in(7 downto 0);
--					END IF;	
					sck <= '1';
				END IF;
			ELSE
				IF spi_div="00000000" THEN
					spi_div <= spi_speed;
					IF SD_busy='1' THEN
						IF sck='0' THEN
							IF shiftcnt(3 downto 0)/="0000" THEN
								sck <='1';
							END IF;
							shiftcnt <= shiftcnt-1;
							sd_out <= sd_out(14 downto 0)&'1';
						ELSE	
							sck <='0';
							sd_in <= sd_in(14 downto 0)&sd_di_in;
							IF spi_word='0' THEN
								sd_in(8) <= sd_di_in;
							END IF;
						END IF;
					END IF;
				ELSE
					spi_div <= spi_div-1;
				END IF;
			END IF;		
		END IF;		
		END IF;		
	END PROCESS;

-----------------------------------------------------------------
-- Simple UART only TxD
-----------------------------------------------------------------
TxD <= not shiftout;
process(n_reset, sysclk, shift)
begin
	if shift="0000000000" then
		txbusy <= '0';
	else
		txbusy <= '1';
	end if;

	if n_reset='0' then
		shiftout <= '0';
		shift <= "0000000000"; 
	elsif sysclk'event and sysclk = '1' then
	IF enaWRreg='1' THEN
		if ld = '1' then
			shift <=  '1' & cpudata_in(15 downto 8) & '0';			--STOP,MSB...LSB, START
		end if;
		if clkgen/=0 then
			clkgen <= clkgen-1;
		else	
--			clkgen <= "1110101001";--937;		--108MHz/115200
--			clkgen <= "0011101010";--234;		--27MHz/115200
--			clkgen <= "0011111000";--249-1;		--28,7MHz/115200
--			clkgen <= "0011110101";--246-1;		--28,7MHz/115200
			clkgen <= "0001111100";--249-1;		--14,3MHz/115200
			shiftout <= not shift(0) and txbusy;
		   	shift <=  '0' & shift(9 downto 1);
		end if;
	END IF;		
	end if;
end process; 


-----------------------------------------------------------------
-- timer
-----------------------------------------------------------------
process(sysclk)
begin
   	IF sysclk'event AND sysclk = '1' THEN
	IF enaWRreg='1' THEN
		IF timeprecnt=0 THEN
			timeprecnt <= X"3808";
			timecnt <= timecnt+1;
		ELSE
			timeprecnt <= timeprecnt-1;
		END IF;
	END IF;
	end if;
end process; 

-----------------------------------------------------------------
-- store Start position (Cluster and Device) for C-One
-----------------------------------------------------------------
process(sysclk, locked)
begin
	if locked='0' then
		partshift <= (others=>'0');
		mdcdd <= '0';
		mdcd <= '0';
	elsif sysclk'event and sysclk = '1' then
		mdbd <= mdb(4);
		mdcd <= mdb(0);
		mdcdd <= not mdcd;
		if mdcdd='1' and mdcd='1' and partshift(0)='0' then
			partshift <= mdbd&partshift(39 downto 1);
		end if;
	end if;
end process; 

end;  
