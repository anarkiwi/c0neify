-- -----------------------------------------------------------------------
-- cone_io.vhd
--
-- Extender-side half of the "vid bus" link between the C-One FPGA
-- Extender (Cyclone III) and the ACEX 1K30 on the C-One main board.
--
-- The Extender has no I/O of its own. After NewBoot loads extender.rbf,
-- the 16 vid[] lines that carried RGB in bypass mode become free, and
-- they are the only channel to the keyboard, mouse, joysticks, SD/CF and
-- CPLD-attached I/O. This module time-multiplexes everything over them,
-- in the same spirit as chameleon_io.vhd does over the Chameleon's 4-bit
-- CPLD mux, so a DeMiSTify toplevel sees the same signals it would on a
-- Chameleon: PS/2 in/out, raw SPI with req/ack, joysticks, buttons, LEDs.
--
-- Line budget (extender view; input-only lines per the Wendrich manual,
-- section 13, see cone_ext_pins.tcl):
--   vid[3:0]   IN only  (CLK4..7 pins)   q    4 bits, 1k30 -> extender
--   vid[7:4]   out                       d    4 bits, extender -> 1k30
--   vid[10:8]  out                       sel[2:0]
--   vid[15]    out                       sel[3]
--   vid[14]    out                       mux_clk
--   vid[13:11] IN only  unused (vid_spare at the toplevel)
--
-- Protocol (one slot per mux_clk period, MUX_DIV clk_mux cycles per half
-- period):
--   * The extender launches sel and d on the clk_mux edge that drives
--     mux_clk LOW, giving the slave half a period of setup and hold.
--   * The 1k30 slave, on the RISING edge of mux_clk, latches d into the
--     output register selected by sel and drives q from the input register
--     selected by sel. q holds until the next rising edge.
--   * The extender samples q Q_LAT clk_mux cycles after the edge that drove
--     mux_clk HIGH. q is valid at the extender from (rise + round trip) for
--     one mux_clk period, so Q_LAT places the sample inside that window for
--     the board's round-trip delay; Q_LAT = MUX_DIV samples on the falling
--     edge.
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
-- Sequence: SPI, 1, SPI, 2, SPI, 3, SPI, 4, SPI, 5, SPI, 6 (12 slots).
--
-- SPI (substitute_mcu with SPI_EXTERNALCLK = true): every change of
-- spi_raw_req asks for the current spi_raw_clk/spi_raw_mosi to reach the
-- card, and spi_raw_ack := spi_raw_req tells the controller it has. The
-- controller samples MISO when it raises SCK, so:
--   * SCK high (rising edge, or the no-op request at the start of a byte)
--     is acknowledged as soon as it is launched;
--   * SCK low is acknowledged only after MISO_VISITS further SPI slots,
--     launched after the falling edge, have returned q, so spi_miso
--     reflects the card's response to that edge;
--   * a spi_cs_n change is launched in an SPI slot of its own, after a
--     pending rising edge and before a pending falling edge, so CS never
--     changes in the same slot as SCK.
-- -----------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.ALL;

entity cone_io is
	generic (
		MUX_DIV : positive := 1;
		Q_LAT : positive := 1;
		MISO_VISITS : positive := 1
	);
	port (
		clk_mux : in std_logic;              -- 100 MHz
		reset : in std_logic;

		-- vid bus (top-level ports, see cone_ext_pins.tcl)
		mux_clk : out std_logic;                 -- vid[14]
		mux_sel : out unsigned(3 downto 0);      -- vid[15], vid[10:8]
		mux_d : out unsigned(3 downto 0);        -- vid[7:4]
		mux_q : in unsigned(3 downto 0);         -- vid[3:0], input-only

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
	constant SEL_SPI : unsigned(3 downto 0) := X"0";
	constant SEL_PS2 : unsigned(3 downto 0) := X"1";
	constant SEL_MISC : unsigned(3 downto 0) := X"6";
	constant SLOTS : natural := 12;

	-- One q sample request per mux_clk rising edge, delayed Q_LAT + 1
	-- clk_mux cycles (Q_LAT to the sample instant, one for the input
	-- register). after_fall marks SPI slots launched after a falling edge.
	type tag_t is record
		valid : std_logic;
		sel : unsigned(3 downto 0);
		after_fall : std_logic;
	end record;
	constant TAG_NONE : tag_t := ('0', X"F", '0');
	type pipe_t is array (1 to Q_LAT + 1) of tag_t;

	signal ph : natural range 0 to 2 * MUX_DIV - 1 := 0;
	signal slot : natural range 0 to SLOTS - 1 := 0;
	signal pipe : pipe_t := (others => TAG_NONE);
	signal launch_after_fall : std_logic := '0';

	signal mux_clk_r : std_logic := '0';
	signal sel_r : unsigned(3 downto 0) := X"F";
	signal d_r : unsigned(3 downto 0) := X"F";
	signal q_in : unsigned(3 downto 0) := X"F";
	attribute useioff : boolean;
	attribute useioff of mux_clk_r, sel_r, d_r, q_in : signal is true;

	-- SPI state as launched on the bus
	signal sck_p, mosi_p, cs_p : std_logic := '1';
	signal ack_r : std_logic := '0';
	signal fall_pending : std_logic := '0';
	signal fall_req : std_logic := '0';
	signal miso_cnt : natural range 0 to MISO_VISITS := 0;

	-- led_green/led_red come from the guest's clock domain
	signal led_meta, led_sync : std_logic_vector(1 downto 0) := "00";

	-- Registered inputs
	signal miso_reg : std_logic := '1';
	signal cd_n_reg : std_logic := '1';
	signal wp_reg : std_logic := '0';
	signal kclk_in_reg, kdat_in_reg, mclk_in_reg, mdat_in_reg : std_logic := '1';
	signal joy1_reg, joy2_reg : unsigned(5 downto 0) := (others => '1');
	signal reset_n_reg : std_logic := '1';
	signal menu_n_reg : std_logic := '1';
begin
	mux_clk <= mux_clk_r;
	mux_sel <= sel_r;
	mux_d <= d_r;

	spi_raw_ack <= ack_r;
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

	process(clk_mux)
		variable t : tag_t;
		variable ack, fall : std_logic;
		variable cnt : natural range 0 to MISO_VISITS;
		variable req : std_logic;
		variable pending : boolean;
		variable sck, mosi, cs : std_logic;
	begin
		if rising_edge(clk_mux) then
			q_in <= mux_q;
			led_meta <= led_red & led_green;
			led_sync <= led_meta;
			ack := ack_r;
			fall := fall_pending;
			cnt := miso_cnt;

			-- Consume the q sample for the slot whose request reached the
			-- end of the pipeline.
			t := pipe(Q_LAT + 1);
			if t.valid = '1' then
				case t.sel is
					when SEL_SPI =>
						miso_reg <= q_in(0);
						wp_reg <= q_in(1);
						cd_n_reg <= q_in(2);
						if t.after_fall = '1' and fall = '1' then
							if cnt = 1 then
								ack := fall_req;
								fall := '0';
							else
								cnt := cnt - 1;
							end if;
						end if;
					when SEL_PS2 =>
						kclk_in_reg <= q_in(0);
						kdat_in_reg <= q_in(1);
						mclk_in_reg <= q_in(2);
						mdat_in_reg <= q_in(3);
					when X"2" => joy1_reg(3 downto 0) <= q_in;
					when X"3" => joy1_reg(5 downto 4) <= q_in(1 downto 0);
					when X"4" => joy2_reg(3 downto 0) <= q_in;
					when X"5" => joy2_reg(5 downto 4) <= q_in(1 downto 0);
					when SEL_MISC =>
						reset_n_reg <= q_in(0);
						menu_n_reg <= q_in(1);
					when others => null;
				end case;
			end if;

			pipe(2 to Q_LAT + 1) <= pipe(1 to Q_LAT);
			pipe(1) <= TAG_NONE;

			if ph = MUX_DIV - 1 then
				-- mux_clk rises on this edge: the slave captures sel/d.
				mux_clk_r <= '1';
				pipe(1) <= ('1', sel_r, launch_after_fall);
			end if;

			if ph = 2 * MUX_DIV - 1 then
				-- mux_clk falls on this edge: launch the next slot.
				ph <= 0;
				mux_clk_r <= '0';
				slot <= (slot + 1) mod SLOTS;
				launch_after_fall <= '0';
				if slot mod 2 = 0 then
					sck := sck_p;
					mosi := mosi_p;
					cs := cs_p;
					req := to_x01(spi_raw_req);
					pending := req /= 'X' and req /= ack and fall = '0';
					launch_after_fall <= fall;
					if pending and spi_raw_clk = '1' then
						sck := '1';
						mosi := spi_raw_mosi;
						ack := req;
					elsif cs /= spi_cs_n then
						cs := spi_cs_n;
					elsif pending then
						sck := '0';
						mosi := spi_raw_mosi;
						fall := '1';
						fall_req <= req;
						cnt := MISO_VISITS;
					end if;
					sck_p <= sck;
					mosi_p <= mosi;
					cs_p <= cs;
					sel_r <= SEL_SPI;
					d_r <= '1' & cs & mosi & sck;
				else
					case slot / 2 is
						when 0 =>
							sel_r <= SEL_PS2;
							d_r <= ps2_mouse_dat_out & ps2_mouse_clk_out
								& ps2_keyboard_dat_out & ps2_keyboard_clk_out;
						when 5 =>
							sel_r <= SEL_MISC;
							d_r <= "11" & unsigned(led_sync);
						when others =>
							sel_r <= to_unsigned(slot / 2 + 1, 4);
							d_r <= X"F";
					end case;
				end if;
			else
				ph <= ph + 1;
			end if;

			ack_r <= ack;
			fall_pending <= fall;
			miso_cnt <= cnt;

			if reset = '1' then
				fall_pending <= '0';
				pipe <= (others => TAG_NONE);
			end if;
		end if;
	end process;
end architecture;
