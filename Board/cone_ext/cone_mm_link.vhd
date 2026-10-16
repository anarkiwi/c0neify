-- -----------------------------------------------------------------------
-- cone_mm_link.vhd
--
-- Extender side of the Minimig V2.01 C-One vid-bus link, so the prebuilt
-- Minimig 1k30 image (support.bin, built from 1k30/acex.vhd) serves this
-- core unchanged: IDE/CF register access, PS/2 keyboard and mouse, RS232
-- TxD, both joysticks and the 1k30's serial audio DAC.
--
-- The link protocol, its cycle counts and slot order are Tobias Gubener's
-- (Minimig C-One port, Copyright (c) 2008-2009 Tobias Gubener, GPL-3 or
-- later). Citations are to C1minimigV201_source.zip: cfide.vhd (IDE
-- tunnel), cyclone.vhd (serial slots, audio, joysticks), 1k30/acex.vhd
-- (the 1k30 end). Copyright (c) 2026 Josh Bailey.
--
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- Clocking (cfide.vhd:515-531): IOclk = clk / 2, toggled on rising clk
-- edges. Everything below runs on the rising clk edge that raises IOclk
-- ("tick"), where the inputs are sampled; the outputs computed there are
-- re-registered on the following falling clk edge, so they
-- change half a clk period after IOclk rises and the 1k30 samples them at
-- the next IOclk rise (acex.vhd:86-87). Data the 1k30 launches at IOclk
-- rise k is sampled at tick k+1, so the round trip (IOclk out to vid in)
-- must stay below one IOclk period; all cycle counts assume that.
--
-- IDE port: hold ide_req high with the access fields stable; they are
-- latched when the access starts. ide_ack pulses for one clk with
-- ide_rdata valid (cfide.vhd:377, micro_state = setwaitend). cs0/cs1 are
-- active high here and inverted onto the 1k30's ide1cs/ide2cs.
--
-- Joysticks (cyclone.vhd:206-222), active low:
-- (5) fire2 (4) fire1 (3) right (2) left (1) down (0) up. The CPLD
-- stream carries no second fire button, so fire2 is always '1'.
-- -----------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity cone_mm_link is
	port (
		clk : in std_logic;
		reset : in std_logic;

		-- vid bus (cone_ext_pins.tcl)
		vid_ioclk : out std_logic;                      -- vid[15]
		vid_ser_out : out std_logic;                    -- vid[14]
		vid_ser_in : in std_logic;                      -- vid[13]
		vid_ide_out : out std_logic_vector(5 downto 0); -- vid[9:4]
		vid_ide_in : in std_logic_vector(3 downto 0);   -- vid[3:0]

		-- IDE register access through the 1k30
		ide_req : in std_logic;
		ide_wr : in std_logic;
		ide_cs0 : in std_logic;
		ide_cs1 : in std_logic;
		ide_reg : in std_logic_vector(2 downto 0);
		ide_wdata : in std_logic_vector(15 downto 0);
		ide_rdata : out std_logic_vector(15 downto 0);
		ide_ack : out std_logic;

		-- PS/2: *_out '0' pulls the 1k30's open-drain line low
		ps2k_clk_out : in std_logic;
		ps2k_dat_out : in std_logic;
		ps2m_clk_out : in std_logic;
		ps2m_dat_out : in std_logic;
		ps2k_clk_in : out std_logic;
		ps2k_dat_in : out std_logic;
		ps2m_clk_in : out std_logic;
		ps2m_dat_in : out std_logic;

		txd : in std_logic;
		rxd : out std_logic;
		sync_ok : out std_logic;

		joy_a : out unsigned(5 downto 0);
		joy_b : out unsigned(5 downto 0);

		-- 16-bit samples for the 1k30's serial DAC
		audio_l : in std_logic_vector(15 downto 0);
		audio_r : in std_logic_vector(15 downto 0)
	);
end entity;

architecture rtl of cone_mm_link is
	-- cfide.vhd:552,563 (close), :571 (first nibble), :595 (end gap)
	constant WAIT_CLOSE : unsigned(3 downto 0) := to_unsigned(10, 4);
	constant WAIT_READ : unsigned(3 downto 0) := to_unsigned(5, 4);
	constant WAIT_END : unsigned(3 downto 0) := to_unsigned(5, 4);

	type ide_state_t is (idle, ide1, set_addr, set_data1, set_data2, set_data3,
		waitclose, read1, read2, read3, read4, setwaitend, waitend);
	signal st : ide_state_t := idle;
	signal ioclk : std_logic := '0';
	signal wait_cnt : unsigned(3 downto 0) := (others => '0');
	signal ide_next : std_logic_vector(5 downto 0) := (others => '1');
	signal ide_in_q : std_logic_vector(3 downto 0) := (others => '1');
	signal rdata : std_logic_vector(15 downto 0) := (others => '1');
	signal acc_wr : std_logic := '0';
	signal acc_sel : std_logic_vector(5 downto 0) := (others => '1');
	signal acc_data : std_logic_vector(15 downto 0) := (others => '1');

	signal ide_o : std_logic_vector(5 downto 0) := (others => '1');
	signal ser_next, ser_o : std_logic := '1';
	signal kmshift : std_logic_vector(8 downto 0) := (others => '1');
	signal km_cnt : unsigned(3 downto 0) := (others => '0');
	signal insync : unsigned(3 downto 0) := (others => '0');
	signal locked : std_logic := '0';
	signal c2mhz, c2mhz_d : std_logic := '0';
	signal ioshift : std_logic := '1';
	signal kb_clk, kb_dat, ms_clk, ms_dat, rx : std_logic := '1';

	signal lrclk : std_logic := '0';
	signal count : unsigned(4 downto 0) := (others => '0');
	signal shift : std_logic_vector(16 downto 0) := (others => '0');
	signal jshift : std_logic_vector(15 downto 0) := (others => '1');
	signal ja, jb : unsigned(5 downto 0) := (others => '1');
begin
	vid_ioclk <= ioclk;
	vid_ide_out <= ide_o;
	vid_ser_out <= ser_o;
	ide_rdata <= rdata;
	sync_ok <= locked;
	ps2k_clk_in <= kb_clk;
	ps2k_dat_in <= kb_dat;
	ps2m_clk_in <= ms_clk;
	ps2m_dat_in <= ms_dat;
	rxd <= rx;
	joy_a <= ja;
	joy_b <= jb;

	-- cfide.vhd:517-520, cyclone.vhd:99-102 load these on the falling edge
	-- while IOclk is high; ide_next and ser_next change only on ticks, so
	-- loading on every falling edge is the same and needs no IOclk enable.
	process(clk)
	begin
		if falling_edge(clk) then
			ide_o <= ide_next;
			ser_o <= ser_next;
		end if;
	end process;

	process(clk)
	begin
		if rising_edge(clk) then
			ioclk <= not ioclk;
			ide_ack <= '0';
			if ioclk = '0' then
				-- IDE tunnel, cfide.vhd:527-603
				wait_cnt <= wait_cnt - 1;
				st <= idle;
				ide_next <= (others => '1');
				ide_in_q <= vid_ide_in;
				case st is
					when idle =>
						if ide_req = '1' then
							acc_wr <= ide_wr;
							acc_sel <= not ide_cs1 & not ide_cs0 & '0' & ide_reg;
							acc_data <= ide_wdata;
							st <= ide1;
						end if;
					when ide1 =>
						ide_next <= acc_wr & not acc_wr & "0000";
						st <= set_addr;
					when set_addr =>
						ide_next <= acc_sel;
						if acc_wr = '1' then
							st <= set_data1;
						else
							st <= waitclose;
							wait_cnt <= WAIT_CLOSE;
						end if;
					when set_data1 =>
						ide_next <= acc_data(5 downto 0);
						st <= set_data2;
					when set_data2 =>
						ide_next <= acc_data(11 downto 6);
						st <= set_data3;
					when set_data3 =>
						ide_next(3 downto 0) <= acc_data(15 downto 12);
						st <= waitclose;
						wait_cnt <= WAIT_CLOSE;
					when waitclose =>
						if wait_cnt = 0 then
							ide_next <= (others => '0');
							if acc_wr = '1' then
								st <= setwaitend;
							else
								st <= read1;
								wait_cnt <= WAIT_READ;
							end if;
						else
							st <= waitclose;
						end if;
					when read1 =>
						if wait_cnt = 0 then
							st <= read2;
						else
							st <= read1;
						end if;
						rdata(3 downto 0) <= ide_in_q;
					when read2 =>
						rdata(7 downto 4) <= ide_in_q;
						st <= read3;
					when read3 =>
						rdata(11 downto 8) <= ide_in_q;
						st <= read4;
					when read4 =>
						rdata(15 downto 12) <= ide_in_q;
						st <= setwaitend;
					when setwaitend =>
						ide_ack <= '1';
						wait_cnt <= WAIT_END;
						st <= waitend;
					when waitend =>
						if wait_cnt /= 0 then
							st <= waitend;
						end if;
				end case;

				-- serial slots, cyclone.vhd:106-166
				ser_next <= '1';
				kmshift <= kmshift(7 downto 0) & vid_ser_in;
				km_cnt <= km_cnt + 1;
				if locked = '1' then
					case to_integer(km_cnt(2 downto 0)) is
						when 0 => ser_next <= km_cnt(3);
						when 1 => ser_next <= ps2k_dat_out;
						when 2 => ser_next <= ps2k_clk_out;
						when 3 => ser_next <= ps2m_dat_out;
						when 4 => ser_next <= ps2m_clk_out;
						when 5 => ser_next <= txd;
						when 6 => ser_next <= lrclk;
						when others => ser_next <= shift(16);
					end case;
					case to_integer(km_cnt(2 downto 0)) is
						when 0 => c2mhz <= kmshift(0);
						when 1 => ioshift <= kmshift(0);
						when 3 => kb_dat <= kmshift(0);
						when 4 => kb_clk <= kmshift(0);
						when 5 => ms_dat <= kmshift(0);
						when 6 => ms_clk <= kmshift(0);
						when 7 => rx <= kmshift(0);
						when others => null;
					end case;
				end if;
				if km_cnt(2 downto 0) = "010" then
					if kmshift(8) = kmshift(0) then
						km_cnt(2 downto 0) <= "010";
						insync <= (others => '0');
						locked <= '0';
					elsif insync = 15 then
						locked <= '1';
					else
						insync <= insync + 1;
						km_cnt(3) <= kmshift(0);
					end if;
				end if;
			end if;

			-- audio shifter and joystick rebuild on the relayed C2MHz,
			-- cyclone.vhd:171-222
			c2mhz_d <= c2mhz;
			if c2mhz_d = '1' and c2mhz = '0' then
				if count = 0 then
					count <= to_unsigned(23, 5);
					lrclk <= not lrclk;
					if lrclk = '1' then
						shift <= '0' & audio_l;
					else
						shift <= '0' & audio_r;
					end if;
				else
					count <= count - 1;
					if count < 17 then
						shift <= shift(15 downto 0) & '0';
					end if;
				end if;
			end if;
			if c2mhz_d = '0' and c2mhz = '1' then
				if jshift(15) = '0' then
					jshift <= (15 downto 1 => '1') & ioshift;
					ja <= '1' & jshift(8) & jshift(11) & jshift(10) & jshift(9) & jshift(7);
					jb <= '1' & jshift(5) & jshift(2) & jshift(3) & jshift(4) & jshift(6);
				else
					jshift <= jshift(14 downto 0) & ioshift;
				end if;
			end if;

			if reset = '1' then
				st <= idle;
				locked <= '0';
				insync <= (others => '0');
				kb_clk <= '1';
				kb_dat <= '1';
				ms_clk <= '1';
				ms_dat <= '1';
				rx <= '1';
				ja <= (others => '1');
				jb <= (others => '1');
			end if;
		end if;
	end process;
end architecture;
