-- -----------------------------------------------------------------------
-- Toplevel template for the C-One FPGA Extender (DeMiSTify target "cone_ext")
--
-- Derived from templates/chameleon64/chameleon64_top.vhd. The Chameleon's
-- CPLD mux is replaced by cone_io, which tunnels the same signal set over
-- the 16 "vid" lines to the C-One's ACEX 1K30.
-- -----------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.ALL;

library work;
use work.demistify_config_pkg.all;

entity cone_ext_top is
generic (
	resetCycles: integer := 131071
);
port (
-- Clocks (extender crystals)
	clk14 : in std_logic;
	clk28 : in std_logic;

-- vid bus to/from the 1k30. vid[3:0] and vid[13:11] are input-only.
	vid : inout std_logic_vector(15 downto 0);

-- mdb - board-wide data bus, left tri-stated
	mdb : inout std_logic_vector(7 downto 0);

-- SDRAM (16 MB, 12 row bits; nCS and CKE hardwired)
	ram_clk : out std_logic;
	ram_data : inout std_logic_vector(15 downto 0);
	ram_addr : out std_logic_vector(11 downto 0);
	ram_we_n : out std_logic;
	ram_ras_n : out std_logic;
	ram_cas_n : out std_logic;
	ram_ba_0 : out std_logic;
	ram_ba_1 : out std_logic;
	ram_ldqm : out std_logic;
	ram_udqm : out std_logic;

-- Video - direct VGA, 5/6/5
	red : out unsigned(4 downto 0);
	grn : out unsigned(5 downto 0);
	blu : out unsigned(4 downto 0);
	hsync_oc : out std_logic;   -- drive '1' to pull nHSync low
	vsync_oc : out std_logic;   -- drive '1' to pull nVSync low

-- Audio - extender DAC pins (fill in from C1_extender.pin)
	sigma_l : out std_logic;
	sigma_r : out std_logic
);
end entity;

architecture rtl of cone_ext_top is
	constant reset_cycles : integer := 131071;

-- System clocks
	signal clk_100 : std_logic;
	signal clk_50 : std_logic;
	signal clk_27 : std_logic;
	signal pll_locked : std_logic;

-- Global signals
	signal reset_14 : std_logic;
	signal reset_100 : std_logic;
	signal reset : std_logic;
	signal reset_n : std_logic;

-- vid-bus mux
	signal mux_clk : std_logic;
	signal mux_sel : unsigned(3 downto 0);
	signal mux_d : unsigned(3 downto 0);
	signal mux_q : unsigned(3 downto 0);

-- LEDs
	signal led_green : std_logic;
	signal led_red : std_logic;

-- PS/2
	signal ps2_keyboard_clk_in, ps2_keyboard_dat_in : std_logic;
	signal ps2_keyboard_clk_out, ps2_keyboard_dat_out : std_logic;
	signal ps2_mouse_clk_in, ps2_mouse_dat_in : std_logic;
	signal ps2_mouse_clk_out, ps2_mouse_dat_out : std_logic;
	signal intercept : std_logic;

-- SD card (raw SPI tunnelled through the 1k30)
	signal spi_mosi : std_logic;
	signal spi_miso : std_logic;
	signal mmc_cs : std_logic;
	signal spi_clk : std_logic;
	signal spi_ack : std_logic;
	signal spi_req : std_logic;

-- internal SPI signals (controller <-> guest)
	signal spi_do : std_logic;
	signal spi_toguest : std_logic;
	signal spi_fromguest : std_logic;
	signal spi_ss2, spi_ss3, spi_ss4 : std_logic;
	signal conf_data0 : std_logic;
	signal spi_clk_int : std_logic;

-- RS232 serial (unconnected on the extender)
	signal rs232_rxd : std_logic := '1';
	signal rs232_txd : std_logic;

-- IO
	signal button_reset_n : std_logic;
	signal menu_button_n : std_logic;
	signal c64_joy1 : unsigned(5 downto 0);
	signal c64_joy2 : unsigned(5 downto 0);
	signal joy1 : std_logic_vector(demistify_joybits-1 downto 0);
	signal joy2 : std_logic_vector(demistify_joybits-1 downto 0);

-- SDRAM address from guest (13 bits; the extender wires A[11:0])
	signal sdram_a : std_logic_vector(12 downto 0);

-- Video from guest
	signal vga_hsync, vga_vsync : std_logic;
	signal vga_red, vga_green, vga_blue : std_logic_vector(7 downto 0);

begin
-- -----------------------------------------------------------------------
-- Clocks and reset
-- -----------------------------------------------------------------------
	clocks : entity work.hostclocks
	port map (
		inclk0 => clk14,
		c0 => clk_100,
		c1 => clk_50,
		c2 => clk_27,
		locked => pll_locked
	);

	myReset : entity work.gen_reset
	generic map ( resetCycles => reset_cycles )
	port map (
		clk => clk14,
		enable => '1',
		button => not (pll_locked and button_reset_n),
		reset => reset_14
	);

	process(clk_100)
	begin
		if rising_edge(clk_100) then
			reset_100 <= reset_14;
			reset <= reset_100;
		end if;
	end process;

-- -----------------------------------------------------------------------
-- vid-bus pin mapping (see cone_io.vhd header for the budget)
-- -----------------------------------------------------------------------
	vid(14) <= mux_clk;
	vid(7 downto 4) <= std_logic_vector(mux_d);
	vid(10 downto 8) <= std_logic_vector(mux_sel(2 downto 0));
	vid(15) <= mux_sel(3);
	vid(3 downto 0) <= (others => 'Z');     -- input-only pins anyway
	vid(13 downto 11) <= (others => 'Z');   -- input-only; spare status inputs
	mux_q <= unsigned(vid(3 downto 0));

	mdb <= (others => 'Z');

	myIO : entity work.cone_io
	port map (
		clk_mux => clk_100,
		reset => reset,
		mux_clk => mux_clk,
		mux_sel => mux_sel,
		mux_d => mux_d,
		mux_q => mux_q,

		spi_cs_n => mmc_cs,
		spi_raw_clk => spi_clk,
		spi_raw_mosi => spi_mosi,
		spi_raw_req => spi_req,
		spi_raw_ack => spi_ack,
		spi_miso => spi_miso,
		mmc_cd_n => open,
		mmc_wp => open,

		ps2_keyboard_clk_out => ps2_keyboard_clk_out,
		ps2_keyboard_dat_out => ps2_keyboard_dat_out,
		ps2_keyboard_clk_in => ps2_keyboard_clk_in,
		ps2_keyboard_dat_in => ps2_keyboard_dat_in,
		ps2_mouse_clk_out => ps2_mouse_clk_out,
		ps2_mouse_dat_out => ps2_mouse_dat_out,
		ps2_mouse_clk_in => ps2_mouse_clk_in,
		ps2_mouse_dat_in => ps2_mouse_dat_in,

		joystick1 => c64_joy1,
		joystick2 => c64_joy2,

		led_green => led_green,
		led_red => led_red,
		button_reset_n => button_reset_n,
		button_menu_n => menu_button_n
	);

	-- C-One ports -> substitute_mcu joystick words (active low, buttons at
	-- the core's demistify_button1/2 positions).
	mergeinputs : entity work.cone_mergeinputs
	generic map (
		joybits => demistify_joybits,
		button1 => demistify_button1,
		button2 => demistify_button2
	)
	port map (
		clk => clk_100,
		joy_a => c64_joy1,
		joy_b => c64_joy2,
		joy1_out => joy1,
		joy2_out => joy2
	);

-- -----------------------------------------------------------------------
-- Guest core
-- -----------------------------------------------------------------------
	spi_do <= spi_miso when spi_ss4 = '0' else 'Z';
	spi_fromguest <= spi_do;

	guest : component guest
	port map (
		CLOCK_27 => clk_27,            -- or clk_27&clk_27 for cores with a 2-bit CLOCK_27
--		RESET_N => reset_n,
		LED => led_red,
		-- SDRAM. Guest cores drive 13 address bits; A[12] has no pin.
		SDRAM_DQ => ram_data,
		SDRAM_A => sdram_a,
		SDRAM_DQML => ram_ldqm,
		SDRAM_DQMH => ram_udqm,
		SDRAM_nWE => ram_we_n,
		SDRAM_nCAS => ram_cas_n,
		SDRAM_nRAS => ram_ras_n,
--		SDRAM_nCS => open,             -- hardwired on the extender
		SDRAM_BA(0) => ram_ba_0,
		SDRAM_BA(1) => ram_ba_1,
		SDRAM_CLK => ram_clk,
--		SDRAM_CKE => open,             -- hardwired on the extender
		-- SPI interface to control module
		SPI_DO => spi_do,
		SPI_DI => spi_toguest,
		SPI_SCK => spi_clk_int,
		SPI_SS2 => spi_ss2,
		SPI_SS3 => spi_ss3,
		SPI_SS4 => spi_ss4,
		CONF_DATA0 => conf_data0,
		-- Video output
		VGA_HS => vga_hsync,
		VGA_VS => vga_vsync,
		VGA_R => vga_red(7 downto 2),
		VGA_G => vga_green(7 downto 2),
		VGA_B => vga_blue(7 downto 2),
		-- Audio output (sigma-delta from the guest)
		AUDIO_L => sigma_l,
		AUDIO_R => sigma_r
	);

	ram_addr <= sdram_a(11 downto 0);

	-- VGA: extender has 5/6/5 bits and open-collector sync drivers.
	red <= unsigned(vga_red(7 downto 3));
	grn <= unsigned(vga_green(7 downto 2));
	blu <= unsigned(vga_blue(7 downto 3));
	hsync_oc <= not vga_hsync;   -- MiST cores output active-low sync;
	vsync_oc <= not vga_vsync;   -- '1' here pulls the shared line low.

-- -----------------------------------------------------------------------
-- Control module (replaces the MiST ARM)
-- -----------------------------------------------------------------------
	spi_clk <= spi_clk_int;

	controller : entity work.substitute_mcu
	generic map (
		joybits => demistify_joybits,
		sysclk_frequency => 500,
		debug => false,
		jtag_uart => false,
		SPI_FASTBIT => 0,
		SPI_EXTERNALCLK => true     -- SPI is paced by cone_io's req/ack
	)
	port map (
		clk => clk_50,
		reset_in => not reset,
		reset_out => reset_n,
		-- SPI
		spi_miso => spi_miso,
		spi_mosi => spi_mosi,
		spi_clk => spi_clk_int,
		spi_cs => mmc_cs,
		spi_fromguest => spi_fromguest,
		spi_toguest => spi_toguest,
		spi_ss2 => spi_ss2,
		spi_ss3 => spi_ss3,
		spi_ss4 => spi_ss4,
		conf_data0 => conf_data0,
		spi_req => spi_req,
		spi_ack => spi_ack,
		-- PS/2
		ps2k_clk_in => ps2_keyboard_clk_in,
		ps2k_dat_in => ps2_keyboard_dat_in,
		ps2k_clk_out => ps2_keyboard_clk_out,
		ps2k_dat_out => ps2_keyboard_dat_out,
		ps2m_clk_in => ps2_mouse_clk_in,
		ps2m_dat_in => ps2_mouse_dat_in,
		ps2m_clk_out => ps2_mouse_clk_out,
		ps2m_dat_out => ps2_mouse_dat_out,
		-- Joysticks
		joy1 => joy1,
		joy2 => joy2,
		buttons => (0 => menu_button_n, others => '0'),
		-- UART
		rxd => rs232_rxd,
		txd => rs232_txd,
		intercept => intercept
	);

	led_green <= not spi_ss4;

end architecture;
