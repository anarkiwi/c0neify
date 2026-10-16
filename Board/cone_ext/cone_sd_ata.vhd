-- -----------------------------------------------------------------------
-- cone_sd_ata.vhd
--
-- SD-card-in-SPI-mode front end for an ATA/CF device, so DeMiSTify's
-- unchanged firmware (firmware/spi_sd.c) reaches the C-One's CF slot
-- through cone_mm_link's IDE tunnel. Copyright (c) 2026 Josh Bailey.
--
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- SPI: mode 0 slave on substitute_mcu's raw SD port. spi_controller
-- raises SCK and samples MISO on the same controller clock edge, so MISO
-- (tx(7)) moves only after a rising SCK has been seen here, and the next
-- byte is loaded on the eighth rising edge. SCK, MOSI and CS come from
-- registers clocked by a PLL output related to clk; no synchroniser.
--
-- SD commands, encoded as spi_sd.c:36-45 sends them; responses start in
-- the second byte after the CRC byte, and R1 waits there (0xFF) until the
-- ATA side is idle (spi_sd.c:118-125 polls up to 40000 bytes):
--   CMD0   R1 0x01, enter idle
--   CMD8   R1 + 00 00 0v aa (echo of arg[11:0]; spi_sd.c:208-209)
--   CMD55  R1
--   CMD41  R1 0x00, leave idle (sent after CMD55, spi_sd.c:149-152)
--   CMD58  R1 + OCR C0 FF 80 00 (power-up done, CCS; spi_sd.c:232-238)
--   CMD9   ATA IDENTIFY, then FE + 16-byte CSD v2 + FF FF (spi_sd.c:417-420
--          reads only byte 0 and C_SIZE in bytes 7-9)
--   CMD16  R1
--   CMD17  ATA READ SECTORS, FF while it runs, FE + 512 bytes + FF FF, or
--          the data error token 01 if the device reports ERR
--   CMD24  R1, then FE + 512 bytes + 2 CRC bytes from the host; data
--          response 05, 00 until the ATA write completes, then FF
--   other  R1 0x04 (illegal command)
-- R1 carries the idle bit (bit 0) for every supported command.
--
-- ATA: PIO, LBA28, device 0 on CS0, one sector per command, in the order
-- of Minimig's _MMC_Read/_MMC_Write (Armreplacement/start.asm:113-268):
-- wait BSY=0 and DRDY=1, sector count 1, LBA 3-5, device E0|LBA[27:24],
-- command; wait BSY=0 and DRQ=1 (or ERR); 256 data words, low byte first;
-- after a write, wait BSY=0. Registers: Gayle.v:59-66 (0 data, 2 count,
-- 3-5 LBA, 6 device/head, 7 status/command); status bits Gayle.v:88-91
-- (7 BSY, 6 DRDY, 3 DRQ, 0 ERR); commands start.asm:16-19 (20 read,
-- 30 write, EC identify). IDENTIFY words 60-61 hold the LBA28 sector
-- count (DeMiSTify firmware/ide.c:145-146); the CSD reports
-- C_SIZE = sectors / 1024 - 1, which spi_sd.c:419-420 turns back into
-- (C_SIZE + 1) * 1024 sectors.
-- -----------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity cone_sd_ata is
	port (
		clk : in std_logic;
		reset : in std_logic;

		spi_cs_n : in std_logic;
		spi_sck : in std_logic;
		spi_mosi : in std_logic;
		spi_miso : out std_logic;

		-- cone_mm_link IDE port (CS0)
		ide_req : out std_logic;
		ide_wr : out std_logic;
		ide_reg : out std_logic_vector(2 downto 0);
		ide_wdata : out std_logic_vector(15 downto 0);
		ide_rdata : in std_logic_vector(15 downto 0);
		ide_ack : in std_logic
	);
end entity;

architecture rtl of cone_sd_ata is
	constant BSY : natural := 7;
	constant DRDY : natural := 6;
	constant DRQ : natural := 3;
	constant ERR : natural := 0;

	-- sd: what the byte now being clocked belongs to
	--   s_cmd    idle, FF out, waiting for a command byte
	--   s_arg    argument and CRC bytes in
	--   s_ncr    FF out until the ATA side is idle, then R1 is loaded
	--   s_tail   R1 out, then the four R7/OCR bytes
	--   s_rdwait FF out until the ATA read/identify completes
	--   s_data   token out, then the data block
	--   s_wrtok  FF out, waiting for the host's FE token
	--   s_wrdata data block and CRC in
	--   s_wrbusy data response out, then busy until the ATA write completes
	type sd_state_t is (s_cmd, s_arg, s_ncr, s_tail, s_rdwait, s_data, s_wrtok, s_wrdata, s_wrbusy);
	signal sd : sd_state_t := s_cmd;
	signal sck_d : std_logic := '1';
	signal bitn : unsigned(2 downto 0) := (others => '0');
	signal rx : std_logic_vector(6 downto 0) := (others => '1');
	signal tx : std_logic_vector(7 downto 0) := (others => '1');
	signal cmd : natural range 0 to 63 := 0;
	signal arg : std_logic_vector(31 downto 0) := (others => '0');
	signal n : unsigned(9 downto 0) := (others => '0');
	signal idle : std_logic := '1';
	signal even : std_logic_vector(7 downto 0) := (others => '0');

	-- ATA side: step 0 idle, 1 wait ready, 2-7 write registers 2-7,
	-- 8 wait DRQ, 9 data words, 10 wait write completion
	type op_t is (op_identify, op_read, op_write);
	signal op : op_t := op_read;
	signal go : std_logic := '0';
	signal failed : std_logic := '0';
	signal step : natural range 0 to 10 := 0;
	signal w : unsigned(7 downto 0) := (others => '0');
	signal lba : std_logic_vector(27 downto 0) := (others => '0');
	signal sectors : unsigned(27 downto 0) := (others => '0');
	signal ata_idle : boolean;
	signal cmd_byte : std_logic_vector(7 downto 0);

	type ram_t is array (0 to 255) of std_logic_vector(15 downto 0);
	signal ram : ram_t;
	signal ram_we : std_logic := '0';
	signal ram_wa, ram_ra : unsigned(7 downto 0) := (others => '0');
	signal ram_wd, ram_q : std_logic_vector(15 downto 0) := (others => '0');

	function r1_of(c : natural; idl : std_logic) return std_logic_vector is
	begin
		case c is
			when 0 => return x"01";
			when 41 => return x"00";
			when 8 | 9 | 16 | 17 | 24 | 55 | 58 => return "0000000" & idl;
			when others => return "00000" & "10" & idl;
		end case;
	end function;

	function tail_of(c : natural; a : std_logic_vector(31 downto 0); k : unsigned(1 downto 0))
		return std_logic_vector is
		variable r : std_logic_vector(31 downto 0) := x"00000" & a(11 downto 0);
	begin
		if c = 58 then
			r := x"C0FF8000";
		end if;
		case k is
			when "00" => return r(31 downto 24);
			when "01" => return r(23 downto 16);
			when "10" => return r(15 downto 8);
			when others => return r(7 downto 0);
		end case;
	end function;

	function csd_of(k : unsigned(3 downto 0); csize : unsigned(21 downto 0)) return std_logic_vector is
	begin
		case to_integer(k) is
			when 0 => return x"40";
			when 7 => return "00" & std_logic_vector(csize(21 downto 16));
			when 8 => return std_logic_vector(csize(15 downto 8));
			when 9 => return std_logic_vector(csize(7 downto 0));
			when others => return x"00";
		end case;
	end function;
begin
	spi_miso <= tx(7);
	ata_idle <= step = 0 and go = '0';
	ram_ra <= w when step /= 0 else n(8 downto 1);

	ide_req <= '0' when step = 0 else '1';
	ide_reg <= "000" when step = 9 else
		std_logic_vector(to_unsigned(step, 3)) when step >= 2 and step <= 7 else "111";
	ide_wr <= '1' when (step >= 2 and step <= 7) or (step = 9 and op = op_write) else '0';
	with op select cmd_byte <=
		x"EC" when op_identify,
		x"20" when op_read,
		x"30" when op_write;
	with step select ide_wdata <=
		x"0001" when 2,
		x"00" & lba(7 downto 0) when 3,
		x"00" & lba(15 downto 8) when 4,
		x"00" & lba(23 downto 16) when 5,
		x"00E" & lba(27 downto 24) when 6,
		x"00" & cmd_byte when 7,
		ram_q when others;

	process(clk)
	begin
		if rising_edge(clk) then
			if ram_we = '1' then
				ram(to_integer(ram_wa)) <= ram_wd;
			end if;
			ram_q <= ram(to_integer(ram_ra));
		end if;
	end process;

	process(clk)
		variable b : std_logic_vector(7 downto 0);
	begin
		if rising_edge(clk) then
			ram_we <= '0';

			-- ATA sequencer
			if step = 0 and go = '1' then
				step <= 1;
				go <= '0';
				failed <= '0';
			elsif ide_ack = '1' then
				case step is
					when 1 =>
						if ide_rdata(BSY) = '0' and ide_rdata(DRDY) = '1' then
							step <= 2;
						end if;
					when 8 =>
						if ide_rdata(BSY) = '0' then
							if ide_rdata(ERR) = '1' then
								failed <= '1';
								step <= 0;
							elsif ide_rdata(DRQ) = '1' then
								w <= (others => '0');
								step <= 9;
							end if;
						end if;
					when 9 =>
						w <= w + 1;
						if op /= op_write then
							ram_we <= '1';
							ram_wa <= w;
							ram_wd <= ide_rdata;
						end if;
						if op = op_identify and w = 60 then
							sectors(15 downto 0) <= unsigned(ide_rdata);
						end if;
						if op = op_identify and w = 61 then
							sectors(27 downto 16) <= unsigned(ide_rdata(11 downto 0));
						end if;
						if w = 255 and op = op_write then
							step <= 10;
						elsif w = 255 then
							step <= 0;
						end if;
					when 10 =>
						if ide_rdata(BSY) = '0' then
							failed <= ide_rdata(ERR);
							step <= 0;
						end if;
					when others =>
						step <= step + 1;
				end case;
			end if;

			-- SPI slave
			sck_d <= spi_sck;
			if spi_cs_n = '1' then
				bitn <= (others => '0');
				tx <= (others => '1');
				sd <= s_cmd;
			elsif sck_d = '0' and spi_sck = '1' then
				rx <= rx(5 downto 0) & spi_mosi;
				bitn <= bitn + 1;
				tx <= tx(6 downto 0) & '1';
				if bitn = 7 then
					b := rx & spi_mosi;
					tx <= x"FF";
					case sd is
						when s_cmd =>
							if b(7 downto 6) = "01" then
								cmd <= to_integer(unsigned(b(5 downto 0)));
								n <= (others => '0');
								sd <= s_arg;
							end if;
						when s_arg =>
							n <= n + 1;
							if n = 4 then
								sd <= s_ncr;
							else
								arg <= arg(23 downto 0) & b;
							end if;
						when s_ncr =>
							if ata_idle then
								tx <= r1_of(cmd, idle);
								n <= (others => '0');
								sd <= s_cmd;
								case cmd is
									when 0 => idle <= '1';
									when 41 => idle <= '0';
									when 8 | 58 => sd <= s_tail;
									when 9 | 17 =>
										op <= op_read;
										if cmd = 9 then
											op <= op_identify;
										end if;
										lba <= arg(27 downto 0);
										go <= '1';
										sd <= s_rdwait;
									when 24 => sd <= s_wrtok;
									when others => null;
								end case;
							end if;
						when s_tail =>
							n <= n + 1;
							if n = 4 then
								sd <= s_cmd;
							else
								tx <= tail_of(cmd, arg, n(1 downto 0));
							end if;
						when s_rdwait =>
							if ata_idle then
								n <= (others => '0');
								if failed = '1' then
									tx <= x"01";
									sd <= s_cmd;
								else
									tx <= x"FE";
									sd <= s_data;
								end if;
							end if;
						when s_data =>
							n <= n + 1;
							if (op = op_identify and n = 16) or n = 512 then
								sd <= s_cmd;
							elsif op = op_identify then
								tx <= csd_of(n(3 downto 0), resize(sectors(27 downto 10) - 1, 22));
							elsif n(0) = '0' then
								tx <= ram_q(7 downto 0);
							else
								tx <= ram_q(15 downto 8);
							end if;
						when s_wrtok =>
							if b = x"FE" then
								n <= (others => '0');
								sd <= s_wrdata;
							end if;
						when s_wrdata =>
							n <= n + 1;
							if n(0) = '0' then
								even <= b;
							elsif n < 512 then
								ram_we <= '1';
								ram_wa <= n(8 downto 1);
								ram_wd <= b & even;
							end if;
							if n = 513 then
								tx <= x"05";
								op <= op_write;
								lba <= arg(27 downto 0);
								go <= '1';
								sd <= s_wrbusy;
							end if;
						when s_wrbusy =>
							if ata_idle then
								sd <= s_cmd;
							else
								tx <= x"00";
							end if;
					end case;
				end if;
			end if;

			if reset = '1' then
				step <= 0;
				go <= '0';
				idle <= '1';
				sd <= s_cmd;
			end if;
		end if;
	end process;
end architecture;
