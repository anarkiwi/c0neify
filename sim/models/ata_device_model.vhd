-- ata_device_model: ATA PIO device (the CF card on the 1k30's IDE pins)
-- for the testbench. Device 0, LBA28, task file on CS0:
-- 0 data, 1 error, 2 sector count, 3-5 LBA, 6 device, 7 status/command.
-- Commands EC (IDENTIFY, words 60-61 = SECTORS), 20 (READ SECTORS) and
-- 30 (WRITE SECTORS), one sector each; anything else aborts. Reads of a
-- sector never written return ata_word(lba, i); writes are kept in a few
-- slots. BSY lasts T_BUSY after a command (T_WRITE after the last data
-- word of a write), and the device is busy for T_BUSY after power-up.
-- Register access rules are asserted (no task-file writes while BSY or
-- DRQ, CS1 never used, LBA mode device 0, sector count 1) and the strobe
-- timing is measured.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package ata_model_pkg is
	type word_array is array (natural range <>) of std_logic_vector(15 downto 0);
	function ata_word(lba : natural; i : natural) return std_logic_vector;
end package;

package body ata_model_pkg is
	function ata_word(lba : natural; i : natural) return std_logic_vector is
	begin
		return std_logic_vector(to_unsigned(((lba mod 65536) * 251 + (lba / 65536) * 13
			+ i * 2654 + 12345) mod 65536, 16));
	end function;
end package body;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.ata_model_pkg.all;

entity ata_device_model is
	generic (
		SECTORS : natural;
		T_ACC : time := 30 ns;
		T_BUSY : time := 3 us;
		T_WRITE : time := 5 us
	);
	port (
		cs0_n : in std_logic;
		cs1_n : in std_logic;
		a : in std_logic_vector(2 downto 0);
		dior_n : in std_logic;
		diow_n : in std_logic;
		d : inout std_logic_vector(15 downto 0);
		commands : out natural := 0;
		dior_min : out time := 1 sec;
		diow_min : out time := 1 sec;
		setup_min : out time := 1 sec
	);
end entity;

architecture behav of ata_device_model is
begin
	process
		constant BSY : natural := 7;
		constant DRDY : natural := 6;
		constant DRQ : natural := 3;
		constant ERR : natural := 0;
		type slot_t is record
			lba : integer;
			data : word_array(0 to 255);
		end record;
		type store_t is array (0 to 3) of slot_t;
		variable store : store_t := (others => (-1, (others => (others => '0'))));
		type regs_t is array (1 to 6) of std_logic_vector(7 downto 0);
		variable regs : regs_t := (others => (others => '0'));
		variable status : std_logic_vector(7 downto 0) := (BSY => '1', others => '0');
		variable buf : word_array(0 to 255);
		variable idx : natural := 0;
		variable writing : boolean := false;
		variable lba : natural := 0;
		type phase_t is (ready, data, commit);
		variable phase : phase_t := ready;
		variable done_at : time := T_BUSY;
		variable t_fall, t_addr : time := 0 ns;
		variable n : natural := 0;

		impure function slot_of(l : natural) return integer is
		begin
			for s in store'range loop
				if store(s).lba = l then
					return s;
				end if;
			end loop;
			return -1;
		end function;

		procedure fail(code : std_logic_vector(7 downto 0)) is
		begin
			regs(1) := code;
			status := (DRDY => '1', ERR => '1', others => '0');
			done_at := 0 ns;
		end procedure;
	begin
		d <= (others => 'Z');
		loop
			if done_at > now then
				wait on dior_n, diow_n, a, cs0_n for done_at - now;
			else
				wait on dior_n, diow_n, a, cs0_n;
			end if;

			if done_at /= 0 ns and now >= done_at then
				done_at := 0 ns;
				status := (DRDY => '1', others => '0');
				if phase = commit then
					if slot_of(lba) < 0 then
						store(n mod 4).lba := lba;
						n := n + 1;
					end if;
					store(slot_of(lba)).data := buf;
					writing := false;
				elsif phase = data then
					status(DRQ) := '1';
				end if;
				phase := ready;
			end if;

			if a'event or cs0_n'event then
				t_addr := now;
			end if;
			assert to_x01(cs1_n) /= '0' report "ATA: CS1 asserted" severity error;

			if to_x01(cs0_n) = '0' and falling_edge(dior_n) then
				t_fall := now;
				setup_min <= minimum(setup_min, now - t_addr);
				case to_integer(unsigned(a)) is
					when 0 => d <= buf(idx mod 256) after T_ACC;
					when 7 => d <= x"00" & status after T_ACC;
					when others => d <= x"00" & regs(to_integer(unsigned(a))) after T_ACC;
				end case;
			elsif to_x01(cs0_n) = '0' and rising_edge(dior_n) then
				dior_min <= minimum(dior_min, now - t_fall);
				d <= (others => 'Z');
				if unsigned(a) = 0 and status(DRQ) = '1' and not writing then
					idx := idx + 1;
					if idx = 256 then
						status(DRQ) := '0';
					end if;
				end if;
			elsif to_x01(cs0_n) = '0' and falling_edge(diow_n) then
				t_fall := now;
				setup_min <= minimum(setup_min, now - t_addr);
			elsif to_x01(cs0_n) = '0' and rising_edge(diow_n) then
				diow_min <= minimum(diow_min, now - t_fall);
				if unsigned(a) = 0 then
					assert status(DRQ) = '1' and writing report "ATA: data write without DRQ" severity error;
					buf(idx) := d;
					idx := idx + 1;
					if idx = 256 then
						status := (BSY => '1', others => '0');
						phase := commit;
						done_at := now + T_WRITE;
					end if;
				else
					assert status(BSY) = '0' and status(DRQ) = '0'
						report "ATA: task file write while BSY or DRQ" severity error;
					if unsigned(a) /= 7 then
						regs(to_integer(unsigned(a))) := d(7 downto 0);
					else
						commands <= commands + 1;
						assert regs(2) = x"01" report "ATA: sector count not 1" severity error;
						assert regs(6)(7 downto 4) = x"E" report "ATA: device register not LBA device 0"
							severity error;
						lba := to_integer(unsigned(std_logic_vector'(regs(6)(3 downto 0) & regs(5) & regs(4) & regs(3))));
						idx := 0;
						writing := false;
						status := (BSY => '1', others => '0');
						phase := data;
						done_at := now + T_BUSY;
						case d(7 downto 0) is
							when x"EC" =>
								buf := (others => (others => '0'));
								buf(49) := x"0200";
								buf(60) := std_logic_vector(to_unsigned(SECTORS mod 65536, 16));
								buf(61) := std_logic_vector(to_unsigned(SECTORS / 65536, 16));
							when x"20" | x"30" =>
								if lba >= SECTORS then
									fail(x"10");
								elsif d(7 downto 0) = x"30" then
									writing := true;
								elsif slot_of(lba) >= 0 then
									buf := store(slot_of(lba)).data;
								else
									for i in buf'range loop
										buf(i) := ata_word(lba, i);
									end loop;
								end if;
							when others =>
								fail(x"04");
						end case;
					end if;
				end if;
			end if;
		end loop;
	end process;
end architecture;
