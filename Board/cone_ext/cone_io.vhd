-- -----------------------------------------------------------------------
-- cone_io.vhd
--
-- Extender-side half of the "vid bus" link between the C-One FPGA
-- Extender (Cyclone III) and the ACEX 1K30 on the C-One main board.
--
-- The Extender has no I/O of its own. After NewBoot loads extender.rbf,
-- the 16 vid[] lines that carried RGB in bypass mode become free, and
-- they are the only channel to the keyboard, mouse, joysticks, CF card
-- and CPLD-attached I/O. This module time-multiplexes everything over
-- them, in the same spirit as chameleon_io.vhd does over the Chameleon's
-- 4-bit CPLD mux - so a DeMiSTify toplevel sees the same signals it
-- would on a Chameleon: PS/2 in/out, raw SPI with req/ack, joysticks,
-- buttons, LEDs.
--
-- Line budget (extender view):
--   vid[3:0]   IN only  (CLK4..7 pins)   -> mux_q   4 bits, 1k30 -> extender
--   vid[7:4]   out      (mux_d)                     4 bits, extender -> 1k30
--   vid[10:8]  out      (mux sel[2:0])
--   vid[15]    out      (mux sel[3])
--   vid[14]    out      (mux_clk)
--   vid[13:11] IN only  spare inputs (e.g. 1k30 "ready", CF card detect)
--
-- Protocol (mirror of the Chameleon CPLD mux):
--   * mux_clk toggles at clk_mux/2.
--   * While mux_clk is LOW the extender drives sel and d.
--   * On the RISING edge of mux_clk the 1k30 slave latches d into its
--     output register selected by sel, and drives q from its input
--     register selected by sel.
--   * On the next FALLING edge the extender samples q.
--
-- Slot map (sel):
--   0  SPI       d = {-, spi_cs_n, spi_mosi, spi_clk}   q = {-, cd_n, wp, miso}
--   1  PS/2      d = {mdat_o, mclk_o, kdat_o, kclk_o}   q = {mdat_i, mclk_i, kdat_i, kclk_i}
--   2  JOY A lo  d = -                                   q = {right, left, down, up}       (active low)
--   3  JOY A hi  d = -                                   q = {-, -, fire2, fire1}          (active low)
--   4  JOY B lo  d = -                                   q = {right, left, down, up}
--   5  JOY B hi  d = -                                   q = {-, -, fire2, fire1}
--   6  MISC      d = {-, -, led_red, led_green}          q = {-, -, menu_n, reset_n}
--   7..15 reserved (IEC, SID writes, CPLD printer port, ...)
--
-- The SPI slot is visited every other state so the SD/CF path gets half
-- the link bandwidth: at clk_mux = 100 MHz each state is 20 ns, the SPI
-- slot recurs every 40 ns, giving a usable SCK of ~5-6 MHz. That is in
-- the same range as the Chameleon V1 (SPI_EXTERNALCLK = true).
--
-- The 1k30 side is a small slave (see cone_1k30_mux_slave.vhd) that owns
-- the real PS/2 pins, the serial joystick stream from the 7064 CPLD, and
-- either a real SPI SD socket wired to spare 1k30 pins or an SPI-flavoured
-- shim over the CF/IDE registers.
--
-- GPL-3 compatible, written for use with DeMiSTify.
-- -----------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.ALL;

entity cone_io is
	port (
		clk_mux : in std_logic;              -- 100 MHz
		reset : in std_logic;

		-- vid bus pins
		mux_clk : out std_logic;             -- vid[14]
		mux_sel : out unsigned(3 downto 0);  -- vid[10:8] & vid[15]
		mux_d : out unsigned(3 downto 0);    -- vid[7:4]
		mux_q : in unsigned(3 downto 0);     -- vid[3:0]

		-- Raw SPI from substitute_mcu (SPI_EXTERNALCLK = true)
		spi_cs_n : in std_logic;
		spi_raw_clk : in std_logic;
		spi_raw_mosi : in std_logic;
		spi_raw_req : in std_logic;
		spi_raw_ack : out std_logic;
		spi_miso : out std_logic;
		mmc_cd_n : out std_logic;
		mmc_wp : out std_logic;

		-- PS/2
		ps2_keyboard_clk_out : in std_logic;
		ps2_keyboard_dat_out : in std_logic;
		ps2_keyboard_clk_in : out std_logic;
		ps2_keyboard_dat_in : out std_logic;
		ps2_mouse_clk_out : in std_logic;
		ps2_mouse_dat_out : in std_logic;
		ps2_mouse_clk_in : out std_logic;
		ps2_mouse_dat_in : out std_logic;

		-- Joysticks, active low: (5)fire2 (4)fire1 (3)right (2)left (1)down (0)up
		joystick1 : out unsigned(5 downto 0);
		joystick2 : out unsigned(5 downto 0);

		-- Misc
		led_green : in std_logic;
		led_red : in std_logic;
		button_reset_n : out std_logic;
		button_menu_n : out std_logic
	);
end entity;

architecture rtl of cone_io is
	type state_t is (
		S_SPI0, S_PS2,
		S_SPI1, S_JOYA_L,
		S_SPI2, S_JOYA_H,
		S_SPI3, S_JOYB_L,
		S_SPI4, S_JOYB_H,
		S_SPI5, S_MISC
	);
	signal state : state_t := S_SPI0;

	signal mux_clk_reg : std_logic := '0';
	signal sel_reg : unsigned(3 downto 0) := X"F";
	signal d_reg : unsigned(3 downto 0) := X"F";

	-- Registered inputs
	signal miso_reg : std_logic := '1';
	signal cd_n_reg : std_logic := '1';
	signal wp_reg : std_logic := '0';
	signal kclk_in_reg, kdat_in_reg, mclk_in_reg, mdat_in_reg : std_logic := '1';
	signal joy1_reg, joy2_reg : unsigned(5 downto 0) := (others => '1');
	signal reset_n_reg : std_logic := '1';
	signal menu_n_reg : std_logic := '1';

	signal spi_ack_reg : std_logic := '0';
begin
	mux_clk <= mux_clk_reg;
	mux_sel <= sel_reg;
	mux_d <= d_reg;

	spi_raw_ack <= spi_ack_reg;
	spi_miso <= miso_reg;
	mmc_cd_n <= cd_n_reg;
	mmc_wp <= wp_reg;
	ps2_keyboard_clk_in <= kclk_in_reg;
	ps2_keyboard_dat_in <= kdat_in_reg;
	ps2_mouse_clk_in <= mclk_in_reg;
	ps2_mouse_dat_in <= mdat_in_reg;
	joystick1 <= joy1_reg;
	joystick2 <= joy2_reg;
	button_reset_n <= reset_n_reg;
	button_menu_n <= menu_n_reg;

	-- Half-rate mux clock
	process(clk_mux)
	begin
		if rising_edge(clk_mux) then
			mux_clk_reg <= not mux_clk_reg;
		end if;
	end process;

	-- Drive phase: set up sel/d while mux_clk is low; advance state while high
	process(clk_mux)
	begin
		if rising_edge(clk_mux) then
			if mux_clk_reg = '1' then
				-- mux_clk is about to fall: sample q for the slot just completed,
				-- then move on and present the next slot.
				case sel_reg is
					when X"0" =>
						miso_reg <= mux_q(0);
						wp_reg <= mux_q(1);
						cd_n_reg <= mux_q(2);
					when X"1" =>
						kclk_in_reg <= mux_q(0);
						kdat_in_reg <= mux_q(1);
						mclk_in_reg <= mux_q(2);
						mdat_in_reg <= mux_q(3);
					when X"2" => joy1_reg(3 downto 0) <= mux_q;
					when X"3" => joy1_reg(5 downto 4) <= mux_q(1 downto 0);
					when X"4" => joy2_reg(3 downto 0) <= mux_q;
					when X"5" => joy2_reg(5 downto 4) <= mux_q(1 downto 0);
					when X"6" =>
						reset_n_reg <= mux_q(0);
						menu_n_reg <= mux_q(1);
					when others => null;
				end case;

				case state is
					when S_SPI0 => state <= S_PS2;
					when S_PS2 => state <= S_SPI1;
					when S_SPI1 => state <= S_JOYA_L;
					when S_JOYA_L => state <= S_SPI2;
					when S_SPI2 => state <= S_JOYA_H;
					when S_JOYA_H => state <= S_SPI3;
					when S_SPI3 => state <= S_JOYB_L;
					when S_JOYB_L => state <= S_SPI4;
					when S_SPI4 => state <= S_JOYB_H;
					when S_JOYB_H => state <= S_SPI5;
					when S_SPI5 => state <= S_MISC;
					when S_MISC => state <= S_SPI0;
				end case;
			else
				-- mux_clk is low: present sel/d for the current state.
				d_reg <= X"F";
				case state is
					when S_SPI0 | S_SPI1 | S_SPI2 | S_SPI3 | S_SPI4 | S_SPI5 =>
						sel_reg <= X"0";
						d_reg(0) <= spi_raw_clk;
						d_reg(1) <= spi_raw_mosi;
						d_reg(2) <= spi_cs_n;
						-- Acknowledge the controller once its clock edge has
						-- been placed on the bus (same scheme as chameleon_io).
						spi_ack_reg <= spi_raw_req;
					when S_PS2 =>
						sel_reg <= X"1";
						d_reg(0) <= ps2_keyboard_clk_out;
						d_reg(1) <= ps2_keyboard_dat_out;
						d_reg(2) <= ps2_mouse_clk_out;
						d_reg(3) <= ps2_mouse_dat_out;
					when S_JOYA_L => sel_reg <= X"2";
					when S_JOYA_H => sel_reg <= X"3";
					when S_JOYB_L => sel_reg <= X"4";
					when S_JOYB_H => sel_reg <= X"5";
					when S_MISC =>
						sel_reg <= X"6";
						d_reg(0) <= led_green;
						d_reg(1) <= led_red;
				end case;
			end if;

			if reset = '1' then
				state <= S_SPI0;
				spi_ack_reg <= '0';
			end if;
		end if;
	end process;
end architecture;
