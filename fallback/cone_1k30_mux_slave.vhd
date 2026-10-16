-- -----------------------------------------------------------------------
-- cone_1k30_mux_slave.vhd
--
-- 1k30-side slave for the vid-bus mux driven by cone_io on the Extender.
-- Target: ACEX EP1K30QC208-3 (1728 LEs) - keep it tiny, VHDL-93.
-- Protocol and slot map: see the header of Board/cone_ext/cone_io.vhd.
--
-- Pin numbers (1K30 column of the C-One manual, section 13):
--   vid[15..0]  170,172,173,174,175,176,177,179,180,186,187,189,190,191,192,193
--               (vid[15] first). Extender drives vid[4..10],[14],[15];
--               1k30 drives vid[0..3]; vid[11..13] are left undriven.
--   keyb_clk 203, keyb_dat 202, mouse_clk 200, mouse_dat 199
--   gb[7..0]    36,37,38,39,40,41,44,45  (to the 1k100: joystick + SPI relay)
--
-- Joysticks are NOT reachable from the 1k30 (ioshift is a 1k100-only pin),
-- so the 1k100 support core reads the 7064 CPLD shift stream and presents
-- the 12 joystick bits plus the SD card's MISO on gb[]; this slave merely
-- forwards them. SPI SCK/MOSI/CS go the other way across gb[].
--
-- Everything is clocked by mux_clk (vid[14]). Asynchronous inputs (PS/2,
-- joysticks, buttons, card detect) pass a two-flop synchroniser. spi_miso
-- is sampled directly: it answers the SCK this slave drove at least one SPI
-- slot earlier.
-- -----------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.ALL;

entity cone_1k30_mux_slave is
	port (
		vid : inout std_logic_vector(15 downto 0);

		-- Real PS/2 pins (open drain)
		ps2k_clk : inout std_logic;
		ps2k_dat : inout std_logic;
		ps2m_clk : inout std_logic;
		ps2m_dat : inout std_logic;

		-- From/to the 1k100 over gb[]
		joy_a : in unsigned(5 downto 0);     -- active low, fire2 fire1 right left down up
		joy_b : in unsigned(5 downto 0);
		spi_miso : in std_logic;
		spi_sck : out std_logic;
		spi_mosi : out std_logic;
		spi_cs_n : out std_logic;
		mmc_cd_n : in std_logic := '0';
		mmc_wp : in std_logic := '0';
		button_reset_n : in std_logic := '1';
		button_menu_n : in std_logic := '1';
		led_green : out std_logic;
		led_red : out std_logic
	);
end entity;

architecture rtl of cone_1k30_mux_slave is
	signal mux_clk : std_logic;
	signal mux_sel : unsigned(3 downto 0);
	signal mux_d : unsigned(3 downto 0);

	-- Asynchronous inputs, in the order they are synchronised:
	-- 22 ps2m_dat 21 ps2m_clk 20 ps2k_dat 19 ps2k_clk 18 menu_n 17 reset_n
	-- 16 cd_n 15 wp 14..9 joy_b 8..3 joy_a
	signal async_in : std_logic_vector(22 downto 3);
	signal sync1, sync2 : std_logic_vector(22 downto 3) := (others => '1');

	signal kclk_o, kdat_o, mclk_o, mdat_o : std_logic := '1';
	signal sck_r, mosi_r, cs_r : std_logic := '1';
	signal ledg_r, ledr_r : std_logic := '0';
	signal q_r : unsigned(3 downto 0) := X"F";
begin
	mux_clk <= vid(14);
	mux_sel <= unsigned(vid(15) & vid(10 downto 8));
	mux_d <= unsigned(vid(7 downto 4));
	vid(3 downto 0) <= std_logic_vector(q_r);
	vid(15 downto 4) <= (others => 'Z');

	-- Open-drain PS/2 drivers
	ps2k_clk <= '0' when kclk_o = '0' else 'Z';
	ps2k_dat <= '0' when kdat_o = '0' else 'Z';
	ps2m_clk <= '0' when mclk_o = '0' else 'Z';
	ps2m_dat <= '0' when mdat_o = '0' else 'Z';

	spi_sck <= sck_r;
	spi_mosi <= mosi_r;
	spi_cs_n <= cs_r;
	led_green <= ledg_r;
	led_red <= ledr_r;

	async_in <= to_x01(ps2m_dat & ps2m_clk & ps2k_dat & ps2k_clk
		& button_menu_n & button_reset_n & mmc_cd_n & mmc_wp
		& std_logic_vector(joy_b) & std_logic_vector(joy_a));

	-- Latch d into the selected output register and present the selected
	-- input nibble, both on the rising edge of mux_clk.
	process(mux_clk)
	begin
		if rising_edge(mux_clk) then
			sync1 <= async_in;
			sync2 <= sync1;
			q_r <= X"F";
			case mux_sel is
				when X"0" =>
					sck_r <= mux_d(0);
					mosi_r <= mux_d(1);
					cs_r <= mux_d(2);
					q_r <= '1' & sync2(16) & sync2(15) & to_x01(spi_miso);
				when X"1" =>
					kclk_o <= mux_d(0);
					kdat_o <= mux_d(1);
					mclk_o <= mux_d(2);
					mdat_o <= mux_d(3);
					q_r <= unsigned(sync2(22 downto 19));
				when X"2" => q_r <= unsigned(sync2(6 downto 3));
				when X"3" => q_r <= unsigned("11" & sync2(8 downto 7));
				when X"4" => q_r <= unsigned(sync2(12 downto 9));
				when X"5" => q_r <= unsigned("11" & sync2(14 downto 13));
				when X"6" =>
					ledg_r <= mux_d(0);
					ledr_r <= mux_d(1);
					q_r <= unsigned("11" & sync2(18 downto 17));
				when others => null;
			end case;
		end if;
	end process;
end architecture;
