-- tb_vidbus: cone_io (extender) and cone_1k30_mux_slave (1k30) back to
-- back over the 16 vid wires.
--
-- Wires carry transport delays: T_E2K_PS on mux_clk, T_E2K_PS + SKEW_PS on
-- sel/d, T_K2E_PS on q. vid[3:0] and vid[13:11] are inputs at the extender
-- (separate input ports); any 1k30 drive on an extender-driven line, or on
-- the pulled-up vid[13:11], shows up as 'X' or a strong level. Setup/hold windows of MARGIN_PS are checked at
-- both capture points (slave mux_clk rise, extender q sample).
--
-- Stimulus, all concurrent:
--   (a) SPI: spi_controller (DeMiSTify's, or the model) clocked at 50 MHz
--       with substitute_mcu's SPI_EXTERNALCLK ack synchroniser, sending
--       bursts under CS to an SPI slave that answers a known byte stream;
--       the slave sees its response MISO_DELAY_PS after each falling SCK.
--   (b) PS/2 keyboard on the 1k30 pins sending make/break codes at the
--       fastest PS/2 clock, after the extender inhibits and releases the
--       clock line (host -> device path).
--   (c) joystick and button changes, through cone_mergeinputs as well.
--   (d) LED writes.
-- Prints RESULT lines with the SCK rate, throughput and latencies.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_vidbus is
	generic (
		MUX_DIV : positive := 1;
		Q_LAT : positive := 1;
		MISO_VISITS : positive := 1;
		T_E2K_PS : natural := 0;
		SKEW_PS : natural := 0;
		T_K2E_PS : natural := 0;
		MISO_DELAY_PS : natural := 0;
		MARGIN_PS : natural := 1000;
		CHECK_TIMING : boolean := true;
		N_BURSTS : positive := 4;
		BURST_LEN : positive := 16;
		PS2_HALF_NS : positive := 30000
	);
end entity;

architecture sim of tb_vidbus is
	constant MARGIN : time := MARGIN_PS * 1 ps;
	constant T_E2K : time := T_E2K_PS * 1 ps;
	constant T_DATA : time := (T_E2K_PS + SKEW_PS) * 1 ps;
	constant T_K2E : time := T_K2E_PS * 1 ps;
	constant N_BYTES : positive := N_BURSTS * BURST_LEN;
	type byte_list is array (natural range <>) of std_logic_vector(7 downto 0);
	constant PS2_BYTES : byte_list := (X"1C", X"F0", X"1C", X"5A", X"F0", X"5A");

	function master_byte(i : natural) return std_logic_vector is
	begin
		case i is
			when 1 => return X"FF";
			when 2 => return X"00";
			when others => return std_logic_vector(to_unsigned((i * 37 + 11) mod 256, 8));
		end case;
	end function;

	function slave_byte(i : natural) return std_logic_vector is
	begin
		case i is
			when 1 => return X"00";
			when 2 => return X"FF";
			when others => return std_logic_vector(to_unsigned((i * 91 + 90) mod 256, 8));
		end case;
	end function;

	function odd_parity(b : std_logic_vector(7 downto 0)) return std_logic is
		variable p : std_logic := '1';
	begin
		for k in b'range loop
			p := p xor b(k);
		end loop;
		return p;
	end function;

	signal clk14 : std_logic := '0';
	signal clk_100, clk_50, clk_27, locked : std_logic;
	signal clk_ps : integer_vector(0 to 2) := (0, 0, 0);
	signal reset, reset_n : std_logic := '1';
	signal running : boolean := false;

	signal ext_vid, k30_vid : std_logic_vector(15 downto 0);
	signal mux_clk : std_logic;
	signal mux_sel, mux_d, mux_q : unsigned(3 downto 0);
	-- slave-captured lines and extender-captured lines as whole signals
	signal k30_seld : std_logic_vector(7 downto 0);
	signal ext_q : std_logic_vector(3 downto 0);

	-- extender side
	signal spi_cs_n : std_logic := '1';
	signal spi_sck, spi_mosi, spi_req, spi_ack, spi_ack_d, spi_ack_r : std_logic;
	signal spi_miso, mmc_cd_n, mmc_wp : std_logic;
	signal trigger : std_logic := '0';
	signal busy : std_logic;
	signal host_to_spi, spi_to_host : std_logic_vector(7 downto 0);
	signal kclk_out, kdat_out : std_logic := '1';
	signal kclk_in, kdat_in, mclk_in, mdat_in : std_logic;
	signal joystick1, joystick2 : unsigned(5 downto 0);
	signal merged1, merged2 : std_logic_vector(7 downto 0);
	signal led_green, led_red : std_logic := '0';
	signal button_reset_n_e, button_menu_n_e : std_logic;

	-- 1k30 side
	signal ps2k_clk, ps2k_dat, ps2m_clk, ps2m_dat : std_logic;
	signal joy_a, joy_b : unsigned(5 downto 0) := (others => '1');
	signal c_sck, c_mosi, c_cs_n : std_logic;
	signal c_miso : std_logic := '1';
	signal card_bit : std_logic := '1';
	signal cd_n, wp : std_logic := '1';
	signal button_reset_n, button_menu_n : std_logic := '1';
	signal led_green_k, led_red_k : std_logic;

	-- results
	signal spi_done, ps2_done, io_done, ps2_armed : boolean := false;
	signal sck_periods : natural := 0;
	signal sck_sum, sck_min : time := 0 ns;
	signal spi_t0, spi_t1 : time := 0 ns;
	signal ps2_lat_max, ps2_lat_min, ps2_lat_sum : time := 0 ns;
	signal ps2_edges, ps2_rx_bytes : natural := 0;
	signal inhibit_lat, io_lat_max : time := 0 ns;
begin
	clk14 <= not clk14 after 34920 ps when clk14 = '1' else not clk14 after 34921 ps;

	clocks : entity work.hostclocks
	port map (inclk0 => clk14, c0 => clk_100, c1 => clk_50, c2 => clk_27, locked => locked);

	-- hostclocks: 14.31818 MHz * 70 / (10, 20, 37), outputs rising together
	clock_check : for k in 0 to 2 generate
		signal c : std_logic;
	begin
		c <= clk_100 when k = 0 else clk_50 when k = 1 else clk_27;
		process
			variable t : time;
		begin
			wait until running;
			wait until rising_edge(c);
			t := now;
			wait until rising_edge(c);
			clk_ps(k) <= (now - t) / 1 ps;
			if k = 1 then
				assert clk_100 = '1' and clk_100'last_event = 0 ns
					report "clk_50 not aligned to clk_100" severity error;
			end if;
			wait;
		end process;
	end generate;

	process
	begin
		wait until locked = '1';
		for k in 1 to 20 loop
			wait until rising_edge(clk_50);
		end loop;
		reset <= '0';
		reset_n <= '1';
		running <= true;
		wait;
	end process;
	reset_n <= not reset;

	-- -------------------------------------------------------------------
	-- Wires
	-- -------------------------------------------------------------------
	k30_vid(14) <= transport ext_vid(14) after T_E2K;
	e2k : for i in 4 to 15 generate
		data : if i /= 14 and (i < 11 or i > 13) generate
			k30_vid(i) <= transport ext_vid(i) after T_DATA;
		end generate;
	end generate;
	k2e : for i in 0 to 3 generate
		ext_vid(i) <= transport k30_vid(i) after T_K2E;
	end generate;
	ext_vid(13 downto 11) <= "HHH";
	k30_vid(13 downto 11) <= "HHH";

	-- -------------------------------------------------------------------
	-- Extender: cone_io + DeMiSTify SPI controller
	-- -------------------------------------------------------------------
	-- extender pins onto the vid wires (cone_ext_pins.tcl)
	ext_vid(14) <= mux_clk;
	ext_vid(15) <= mux_sel(3);
	ext_vid(10 downto 8) <= std_logic_vector(mux_sel(2 downto 0));
	ext_vid(7 downto 4) <= std_logic_vector(mux_d);
	mux_q <= unsigned(to_x01(ext_vid(3 downto 0)));

	dut_ext : entity work.cone_io
	generic map (MUX_DIV => MUX_DIV, Q_LAT => Q_LAT, MISO_VISITS => MISO_VISITS)
	port map (
		clk_mux => clk_100, reset => reset,
		mux_clk => mux_clk, mux_sel => mux_sel, mux_d => mux_d, mux_q => mux_q,
		spi_cs_n => spi_cs_n, spi_raw_clk => spi_sck, spi_raw_mosi => spi_mosi,
		spi_raw_req => spi_req, spi_raw_ack => spi_ack, spi_miso => spi_miso,
		mmc_cd_n => mmc_cd_n, mmc_wp => mmc_wp,
		ps2_keyboard_clk_out => kclk_out, ps2_keyboard_dat_out => kdat_out,
		ps2_keyboard_clk_in => kclk_in, ps2_keyboard_dat_in => kdat_in,
		ps2_mouse_clk_out => '1', ps2_mouse_dat_out => '1',
		ps2_mouse_clk_in => mclk_in, ps2_mouse_dat_in => mdat_in,
		joystick1 => joystick1, joystick2 => joystick2,
		led_green => led_green, led_red => led_red,
		button_reset_n => button_reset_n_e, button_menu_n => button_menu_n_e
	);

	-- substitute_mcu, SPI_EXTERNALCLK = true with spi_fast_sd set
	process(clk_50)
	begin
		if rising_edge(clk_50) then
			spi_ack_d <= spi_ack;
			spi_ack_r <= spi_ack_d;
		end if;
	end process;

	spi : entity work.spi_controller
	port map (
		sysclk => clk_50, reset => reset_n,
		host_to_spi => host_to_spi, spi_to_host => spi_to_host,
		trigger => trigger, busy => busy,
		spi_req => spi_req, spi_ack => spi_ack_r,
		miso => spi_miso, mosi => spi_mosi, spiclk_out => spi_sck
	);

	merge : entity work.cone_mergeinputs
	generic map (joybits => 8, button1 => 5, button2 => 4)
	port map (clk => clk_100, joy_a => joystick1, joy_b => joystick2,
		joy1_out => merged1, joy2_out => merged2);

	-- -------------------------------------------------------------------
	-- 1k30
	-- -------------------------------------------------------------------
	dut_k30 : entity work.cone_1k30_mux_slave
	port map (
		vid => k30_vid,
		ps2k_clk => ps2k_clk, ps2k_dat => ps2k_dat,
		ps2m_clk => ps2m_clk, ps2m_dat => ps2m_dat,
		joy_a => joy_a, joy_b => joy_b,
		spi_miso => c_miso, spi_sck => c_sck, spi_mosi => c_mosi, spi_cs_n => c_cs_n,
		mmc_cd_n => cd_n, mmc_wp => wp,
		button_reset_n => button_reset_n, button_menu_n => button_menu_n,
		led_green => led_green_k, led_red => led_red_k
	);
	ps2k_clk <= 'H';
	ps2k_dat <= 'H';
	ps2m_clk <= 'H';
	ps2m_dat <= 'H';

	-- -------------------------------------------------------------------
	-- Bus checks
	-- -------------------------------------------------------------------
	k30_seld <= k30_vid(15) & k30_vid(10 downto 4);
	ext_q <= ext_vid(3 downto 0);

	drive_check : process(ext_vid, k30_vid)
	begin
		if running then
			for i in 0 to 15 loop
				assert ext_vid(i) /= 'X' and k30_vid(i) /= 'X'
					report "vid(" & integer'image(i) & ") contention" severity error;
			end loop;
			assert ext_vid(13 downto 11) = "HHH" and k30_vid(13 downto 11) = "HHH"
				report "vid(13:11) driven" severity error;
		end if;
	end process;

	slave_capture : process
	begin
		wait until rising_edge(k30_vid(14)) and running and CHECK_TIMING;
		assert k30_seld'last_event >= MARGIN
			report "slave setup violation" severity error;
		wait for MARGIN;
		assert k30_seld'last_event > MARGIN
			report "slave hold violation" severity error;
	end process;

	ext_capture : process
	begin
		wait until rising_edge(ext_vid(14)) and running and CHECK_TIMING;
		for k in 1 to Q_LAT loop
			wait until rising_edge(clk_100);
		end loop;
		assert ext_q'last_event >= MARGIN
			report "extender q setup violation" severity error;
		wait for MARGIN;
		assert ext_q'last_event > MARGIN
			report "extender q hold violation" severity error;
	end process;

	-- -------------------------------------------------------------------
	-- (a) SPI
	-- -------------------------------------------------------------------
	spi_host : process
		variable n : natural := 0;
	begin
		wait until running;
		spi_t0 <= now;
		for b in 1 to N_BURSTS loop
			wait until rising_edge(clk_50);
			spi_cs_n <= '0';
			for i in 1 to BURST_LEN loop
				wait until rising_edge(clk_50);
				host_to_spi <= master_byte(n);
				trigger <= '1';
				wait until rising_edge(clk_50);
				trigger <= '0';
				wait until rising_edge(clk_50) and busy = '0';
				assert spi_to_host = slave_byte(n)
					report "SPI byte " & integer'image(n) & ": master got "
					& to_hstring(spi_to_host) & " expected " & to_hstring(slave_byte(n))
					severity error;
				n := n + 1;
			end loop;
			spi_cs_n <= '1';
			for k in 1 to 50 loop
				wait until rising_edge(clk_50);
			end loop;
		end loop;
		spi_t1 <= now;
		spi_done <= true;
		wait;
	end process;

	-- Acknowledging a falling edge promises that spi_miso already answers it.
	ack_check : process
	begin
		wait on spi_ack until running and spi_sck = '0';
		assert spi_miso = card_bit
			report "falling-edge ack before MISO arrived" severity error;
	end process;

	spi_card : process
		variable rx, tx : std_logic_vector(7 downto 0);
		variable nbit : natural := 0;
		variable idx : natural := 0;
		variable t_fall : time := 0 ns;
		variable pmin : time := 1 sec;
	begin
		wait on c_sck, c_cs_n until running;
		if c_cs_n'event then
			assert c_sck = '1' and c_sck'last_event > 0 ns
				report "CS changed together with SCK" severity error;
			nbit := 0;
		elsif c_cs_n = '0' and c_sck = '0' then
			if nbit = 0 then
				tx := slave_byte(idx);
			else
				pmin := minimum(pmin, now - t_fall);
				sck_periods <= sck_periods + 1;
				sck_sum <= sck_sum + (now - t_fall);
				sck_min <= pmin;
			end if;
			t_fall := now;
			card_bit <= tx(7 - nbit);
			c_miso <= transport tx(7 - nbit) after MISO_DELAY_PS * 1 ps;
		elsif c_cs_n = '0' and c_sck = '1' then
			rx := rx(6 downto 0) & c_mosi;
			nbit := nbit + 1;
			if nbit = 8 then
				assert rx = master_byte(idx)
					report "SPI byte " & integer'image(idx) & ": card got "
					& to_hstring(rx) & " expected " & to_hstring(master_byte(idx))
					severity error;
				idx := idx + 1;
				nbit := 0;
			end if;
		end if;
	end process;

	-- -------------------------------------------------------------------
	-- (b) PS/2
	-- -------------------------------------------------------------------
	ps2_device : process
		constant H : time := PS2_HALF_NS * 1 ns;
		variable frame : std_logic_vector(10 downto 0);
	begin
		ps2k_clk <= 'Z';
		ps2k_dat <= 'Z';
		wait until running;
		wait for 2 us;
		-- host inhibit: extender pulls the keyboard clock low
		kclk_out <= '0';
		wait until to_x01(ps2k_clk) = '0' for 10 us;
		assert to_x01(ps2k_clk) = '0' report "PS/2 inhibit did not reach the 1k30" severity error;
		inhibit_lat <= kclk_out'last_event;
		wait for 100 us;
		kclk_out <= '1';
		wait until to_x01(ps2k_clk) = '1' for 10 us;
		wait for 50 us;
		ps2_armed <= true;
		for b in PS2_BYTES'range loop
			frame := '1' & odd_parity(PS2_BYTES(b)) & PS2_BYTES(b) & '0';
			for k in 0 to 10 loop
				if frame(k) = '0' then ps2k_dat <= '0'; else ps2k_dat <= 'Z'; end if;
				wait for H / 2;
				ps2k_clk <= '0';
				wait for H;
				ps2k_clk <= 'Z';
				wait for H / 2;
			end loop;
			wait for 4 * H;
		end loop;
		wait for 20 us;
		ps2_done <= true;
		wait;
	end process;

	ps2_host : process
		variable frame : std_logic_vector(10 downto 0);
		variable nbit, nbyte : natural := 0;
	begin
		wait until falling_edge(kclk_in) and ps2_armed;
		frame := kdat_in & frame(10 downto 1);
		nbit := nbit + 1;
		if nbit = 11 then
			assert frame(0) = '0' and frame(10) = '1'
				and frame(9) = odd_parity(frame(8 downto 1))
				and nbyte <= PS2_BYTES'high and frame(8 downto 1) = PS2_BYTES(nbyte)
				report "PS/2 frame " & integer'image(nbyte) & " wrong: " & to_hstring(frame)
				severity error;
			nbyte := nbyte + 1;
			ps2_rx_bytes <= nbyte;
			nbit := 0;
		end if;
	end process;

	ps2_latency : process
		variable v : std_logic;
		variable t0, lat, lmax, lsum : time := 0 ns;
		variable lmin : time := 1 sec;
		variable n : natural := 0;
	begin
		wait on ps2k_clk, ps2k_dat;
		if running and kclk_out = '1' then
			-- the device changes one line at a time
			if ps2k_clk'event then
				v := to_x01(ps2k_clk);
				t0 := now;
				if kclk_in /= v then wait until kclk_in = v for 20 us; end if;
				assert kclk_in = v report "PS/2 clock edge lost" severity error;
				assert ps2k_clk'last_event >= now - t0 report "PS/2 clock edge overtaken" severity error;
			else
				v := to_x01(ps2k_dat);
				t0 := now;
				if kdat_in /= v then wait until kdat_in = v for 20 us; end if;
				assert kdat_in = v report "PS/2 data edge lost" severity error;
			end if;
			lat := now - t0;
			n := n + 1;
			lmax := maximum(lmax, lat);
			lmin := minimum(lmin, lat);
			lsum := lsum + lat;
			ps2_edges <= n;
			ps2_lat_max <= lmax;
			ps2_lat_min <= lmin;
			ps2_lat_sum <= lsum;
		end if;
	end process;

	-- -------------------------------------------------------------------
	-- (c) joysticks and buttons, (d) LEDs
	-- -------------------------------------------------------------------
	io_seq : process
		constant BOUND : time := 20 * 2 * MUX_DIV * 10 ns;
		variable t0, lmax : time := 0 ns;
		variable a, b : unsigned(5 downto 0);
		variable ok : boolean;
	begin
		wait until running;
		wait for 1 us;
		for k in 0 to 39 loop
			a := to_unsigned((k * 29 + 5) mod 64, 6);
			b := to_unsigned((k * 43 + 17) mod 64, 6);
			joy_a <= a;
			joy_b <= b;
			button_reset_n <= to_unsigned(k mod 8, 3)(0);
			button_menu_n <= to_unsigned(k mod 8, 3)(1);
			led_green <= to_unsigned(k mod 8, 3)(1);
			led_red <= to_unsigned(k mod 8, 3)(2);
			t0 := now;
			loop
				wait until rising_edge(clk_100);
				ok := joystick1 = a and joystick2 = b
					and merged1 = "11" & std_logic(a(4)) & std_logic(a(5)) & std_logic_vector(a(3 downto 0))
					and merged2 = "11" & std_logic(b(4)) & std_logic(b(5)) & std_logic_vector(b(3 downto 0))
					and button_reset_n_e = button_reset_n and button_menu_n_e = button_menu_n
					and led_green_k = led_green and led_red_k = led_red;
				exit when ok or now - t0 > BOUND;
			end loop;
			assert ok report "joystick/button/LED step " & integer'image(k)
				& " not delivered within " & time'image(BOUND) severity error;
			lmax := maximum(lmax, now - t0);
			wait for 300 ns;
		end loop;
		io_lat_max <= lmax;
		io_done <= true;
		wait;
	end process;

	-- -------------------------------------------------------------------
	-- Summary
	-- -------------------------------------------------------------------
	finish_proc : process
		constant T_SLOT : time := 2 * MUX_DIV * 10 ns;
		variable mean : time;
	begin
		wait until spi_done and ps2_done and io_done for 50 ms;
		assert spi_done and ps2_done and io_done report "timeout" severity failure;
		assert ps2_rx_bytes = PS2_BYTES'length
			report "PS/2: " & integer'image(ps2_rx_bytes) & " frames received" severity error;
		assert mclk_in = '1' and mdat_in = '1' and mmc_cd_n = '1' and mmc_wp = '1'
			report "idle inputs wrong" severity error;
		mean := sck_sum / sck_periods;
		assert abs (clk_ps(0) - 69841 * 10 / 70) <= 1 and abs (clk_ps(1) - 69841 * 20 / 70) <= 1
			and abs (clk_ps(2) - 69841 * 37 / 70) <= 1
			report "hostclocks periods " & integer'image(clk_ps(0)) & " " & integer'image(clk_ps(1))
			& " " & integer'image(clk_ps(2)) & " ps" severity error;
		report "RESULT clk_ps=" & integer'image(clk_ps(0));
		report "RESULT slot_ns=" & integer'image(T_SLOT / 1 ns);
		report "RESULT spi_bytes=" & integer'image(N_BYTES);
		report "RESULT sck_mean_khz=" & integer'image(1 ms / mean);
		report "RESULT sck_max_khz=" & integer'image(1 ms / sck_min);
		report "RESULT spi_kbyte_s=" & integer'image(integer(real(N_BYTES) * 1.0e9
			/ real((spi_t1 - spi_t0) / 1 ps)));
		report "RESULT ps2_edges=" & integer'image(ps2_edges);
		report "RESULT ps2_lat_min_ns=" & integer'image(ps2_lat_min / 1 ns);
		report "RESULT ps2_lat_mean_ns=" & integer'image(ps2_lat_sum / ps2_edges / 1 ns);
		report "RESULT ps2_lat_max_ns=" & integer'image(ps2_lat_max / 1 ns);
		report "RESULT ps2_inhibit_lat_ns=" & integer'image(inhibit_lat / 1 ns);
		report "RESULT io_lat_max_ns=" & integer'image(io_lat_max / 1 ns);
		report "RESULT PASS";
		finish;
	end process;
end architecture;
