-- tb_mmlink: cone_sd_ata + cone_mm_link on the extender, a 1k30 running
-- either sim/models/k30_mm_model.vhd or Minimig's own 1k30/acex.vhd
-- (K30_REAL, extracted from reference/C1minimigV201_source.zip by
-- scripts/sim.sh), an ATA device on the 1k30's IDE pins, PS/2 devices,
-- and the CPLD joystick stream.
--
-- The SPI master is DeMiSTify's spi_controller with substitute_mcu's SPI
-- timer (substitute_mcu.vhd:367-386, SPI_EXTERNALCLK false, SPI_FASTBIT
-- 0) and its CPU-side SPI()/SPI_READ()/chip-select timing; the sequencer
-- replays firmware/spi_sd.c: sd_init (CMD0, CMD8, CMD55+ACMD41, CMD58,
-- CMD9), then sector reads and writes, an out-of-range read and an
-- illegal command.
--
-- Wires: T_E2K_PS on IOclk, T_E2K_PS + SKEW_PS on the other extender
-- outputs, T_K2E_PS on the 1k30 outputs. Setup and hold at both capture
-- points (1k30 IOclk rise, extender IOclk rise) are measured over the run
-- and must exceed MARGIN_PS. Prints RESULT lines.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.ata_model_pkg.all;

entity tb_mmlink is
	generic (
		K30_REAL : boolean := false;
		T_E2K_PS : natural := 3000;
		SKEW_PS : natural := 0;
		T_K2E_PS : natural := 3000;
		MARGIN_PS : natural := 1000;
		SLOWBIT : natural := 6;
		SPIN_BYTES : positive := 200;
		SECTORS : positive := 30000000;
		PS2_HALF_NS : positive := 30000;
		C2M_NS : positive := 500;
		FULL : boolean := true
	);
end entity;

architecture sim of tb_mmlink is
	constant MARGIN : time := MARGIN_PS * 1 ps;
	type byte_list is array (natural range <>) of std_logic_vector(7 downto 0);
	constant PS2_BYTES : byte_list := (X"1C", X"F0", X"1C", X"5A");
	constant AUDIO_L : std_logic_vector(15 downto 0) := x"A5C3";
	constant AUDIO_R : std_logic_vector(15 downto 0) := x"3C5A";

	function odd_parity(b : std_logic_vector(7 downto 0)) return std_logic is
		variable p : std_logic := '1';
	begin
		for k in b'range loop
			p := p xor b(k);
		end loop;
		return p;
	end function;

	-- byte i of the test pattern written to sector lba
	function wr_byte(lba, i : natural) return std_logic_vector is
	begin
		return std_logic_vector(to_unsigned((i * 7 + lba mod 251 + 3) mod 256, 8));
	end function;

	component acex
		port (
			ide1irq : in std_logic;
			addonin : in std_logic_vector(7 downto 0);
			C2MHz : in std_logic;
			ioshift : in std_logic;
			IOclk : in std_logic;
			kb_clk : inout std_logic;
			kb_data : inout std_logic;
			ms_clk : inout std_logic;
			ms_data : inout std_logic;
			addonout : out std_logic_vector(5 downto 0);
			idedata : inout std_logic_vector(15 downto 0);
			idea : out std_logic_vector(2 downto 0);
			ide_wr : out std_logic;
			ide_rd : out std_logic;
			ide_csp0 : out std_logic;
			ide_css0 : out std_logic;
			TxD : out std_logic;
			lrclk : out std_logic;
			adat : out std_logic
		);
	end component;

	signal clk14 : std_logic := '0';
	signal clk_100, clk_50, clk_27, locked : std_logic;
	signal reset : std_logic := '1';
	signal running : boolean := false;

	-- wires, indexed by vid line
	signal ext_vid, k30_vid : std_logic_vector(15 downto 0);
	signal ext_in, k30_in : std_logic_vector(7 downto 0);

	-- extender
	signal ide_req, ide_wr, ide_ack : std_logic;
	signal ide_reg : std_logic_vector(2 downto 0);
	signal ide_wdata, ide_rdata : std_logic_vector(15 downto 0);
	signal ps2_out : std_logic_vector(3 downto 0) := "1111"; -- kclk kdat mclk mdat
	signal ps2_in : std_logic_vector(3 downto 0);
	signal txd : std_logic := '1';
	signal rxd, sync_ok : std_logic;
	signal joy_a, joy_b : unsigned(5 downto 0);
	signal merged1, merged2 : std_logic_vector(7 downto 0);

	-- substitute_mcu SPI
	signal spi_cs_n : std_logic := '1';
	signal spi_fast : std_logic := '0';
	signal spi_sck, spi_mosi, spi_req, miso, bridge_miso : std_logic;
	signal spi_ack_r : std_logic := '0';
	signal spi_tick : std_logic := '0';
	signal spi_counter : unsigned(8 downto 0) := (others => '0');
	signal trigger, busy : std_logic := '0';
	signal host_to_spi, spi_to_host : std_logic_vector(7 downto 0);

	-- 1k30
	signal addonin : std_logic_vector(7 downto 0);
	signal addonout : std_logic_vector(5 downto 0);
	signal kb_clk, kb_data, ms_clk, ms_data : std_logic;
	signal dev_clk, dev_dat : std_logic_vector(0 to 1) := "ZZ";
	signal idedata : std_logic_vector(15 downto 0);
	signal idea : std_logic_vector(2 downto 0);
	signal dior_n, diow_n, cs0_n, cs1_n, k30_txd, lrclk, adat : std_logic;
	signal c2mhz : std_logic := '0';
	signal ioshift : std_logic := '1';
	signal joy_ta, joy_tb : unsigned(5 downto 0) := (others => '1');

	-- results
	signal sd_done, ps2_done, joy_done, audio_ok, txd_done : boolean := false;
	signal ata_cmds : natural;
	signal dior_min, diow_min, ata_setup_min : time;
	signal t_sync, t_init, t_read, t_write : time := 0 ns;
	signal ext_setup, ext_hold, k30_setup, k30_hold : time := 1 sec;
	signal ps2_rx : integer_vector(0 to 1) := (0, 0);
	signal joy_lat : time := 0 ns;
	signal sd_size : natural := 0;
	signal sck_slow, sck_fast : time := 1 sec;
begin
	clk14 <= not clk14 after 34920 ps when clk14 = '1' else not clk14 after 34921 ps;

	clocks : entity work.hostclocks
	port map (inclk0 => clk14, c0 => clk_100, c1 => clk_50, c2 => clk_27, locked => locked);

	process
	begin
		wait until locked = '1';
		for k in 1 to 20 loop
			wait until rising_edge(clk_100);
		end loop;
		reset <= '0';
		running <= true;
		wait;
	end process;

	-- -------------------------------------------------------------------
	-- Wires
	-- -------------------------------------------------------------------
	k30_vid(15) <= transport ext_vid(15) after T_E2K_PS * 1 ps;
	e2k : for i in 4 to 14 generate
		data : if i <= 10 or i = 14 generate
			k30_vid(i) <= transport ext_vid(i) after (T_E2K_PS + SKEW_PS) * 1 ps;
		end generate;
	end generate;
	k2e : for i in 0 to 13 generate
		data : if i <= 3 or i >= 11 generate
			ext_vid(i) <= transport k30_vid(i) after T_K2E_PS * 1 ps;
		end generate;
	end generate;

	ext_in <= ext_vid(13 downto 11) & '0' & ext_vid(3 downto 0);
	k30_in <= k30_vid(14) & k30_vid(10 downto 4);

	-- -------------------------------------------------------------------
	-- Extender
	-- -------------------------------------------------------------------
	link : entity work.cone_mm_link
	port map (
		clk => clk_100, reset => reset,
		vid_ioclk => ext_vid(15), vid_ser_out => ext_vid(14), vid_ser_in => to_x01(ext_vid(13)),
		vid_ide_out => ext_vid(9 downto 4), vid_ide_in => to_x01(ext_vid(3 downto 0)),
		ide_req => ide_req, ide_wr => ide_wr, ide_cs0 => '1', ide_cs1 => '0',
		ide_reg => ide_reg, ide_wdata => ide_wdata, ide_rdata => ide_rdata, ide_ack => ide_ack,
		ps2k_clk_out => ps2_out(3), ps2k_dat_out => ps2_out(2),
		ps2m_clk_out => ps2_out(1), ps2m_dat_out => ps2_out(0),
		ps2k_clk_in => ps2_in(3), ps2k_dat_in => ps2_in(2),
		ps2m_clk_in => ps2_in(1), ps2m_dat_in => ps2_in(0),
		txd => txd, rxd => rxd, sync_ok => sync_ok,
		joy_a => joy_a, joy_b => joy_b,
		audio_l => AUDIO_L, audio_r => AUDIO_R
	);
	ext_vid(10) <= '1';

	bridge : entity work.cone_sd_ata
	port map (
		clk => clk_100, reset => reset,
		spi_cs_n => spi_cs_n, spi_sck => spi_sck, spi_mosi => spi_mosi, spi_miso => bridge_miso,
		ide_req => ide_req, ide_wr => ide_wr, ide_reg => ide_reg,
		ide_wdata => ide_wdata, ide_rdata => ide_rdata, ide_ack => ide_ack
	);

	merge : entity work.cone_mergeinputs
	generic map (joybits => 8, button1 => 5, button2 => 4)
	port map (clk => clk_100, joy_a => joy_a, joy_b => joy_b, joy1_out => merged1, joy2_out => merged2);

	-- substitute_mcu.vhd:367-386 (SPI_EXTERNALCLK false) and :413
	process(clk_50)
	begin
		if rising_edge(clk_50) then
			spi_counter <= spi_counter + 1;
			spi_tick <= '0';
			if (spi_fast = '1' and spi_counter(0) = '1') or spi_counter(SLOWBIT) = '1' then
				-- spi_controller's spi_req_r has no reset; it powers up '0'
				spi_ack_r <= to_x01(spi_req);
				if is_x(spi_req) then
					spi_ack_r <= '0';
				end if;
				spi_tick <= '1';
				spi_counter <= (others => '0');
			end if;
		end if;
	end process;
	miso <= bridge_miso when spi_cs_n = '0' else '1';

	spi_ctl : entity work.spi_controller
	port map (
		sysclk => clk_50, reset => not reset,
		host_to_spi => host_to_spi, spi_to_host => spi_to_host,
		trigger => trigger, busy => busy,
		spi_req => spi_req, spi_ack => spi_ack_r,
		miso => miso, mosi => spi_mosi, spiclk_out => spi_sck
	);

	-- -------------------------------------------------------------------
	-- 1k30
	-- -------------------------------------------------------------------
	addonin <= k30_in;
	k30_vid(13 downto 11) <= addonout(5 downto 4) & '0';
	k30_vid(3 downto 0) <= addonout(3 downto 0);

	real_k30 : if K30_REAL generate
		k30 : component acex
		port map (
			ide1irq => '1', addonin => addonin, C2MHz => c2mhz, ioshift => ioshift,
			IOclk => k30_vid(15), kb_clk => kb_clk, kb_data => kb_data, ms_clk => ms_clk, ms_data => ms_data,
			addonout => addonout, idedata => idedata, idea => idea, ide_wr => diow_n, ide_rd => dior_n,
			ide_csp0 => cs0_n, ide_css0 => cs1_n, TxD => k30_txd, lrclk => lrclk, adat => adat
		);
	end generate;
	model_k30 : if not K30_REAL generate
		k30 : entity work.k30_mm_model
		port map (
			ide1irq => '1', addonin => addonin, C2MHz => c2mhz, ioshift => ioshift,
			IOclk => k30_vid(15), kb_clk => kb_clk, kb_data => kb_data, ms_clk => ms_clk, ms_data => ms_data,
			addonout => addonout, idedata => idedata, idea => idea, ide_wr => diow_n, ide_rd => dior_n,
			ide_csp0 => cs0_n, ide_css0 => cs1_n, TxD => k30_txd, lrclk => lrclk, adat => adat
		);
	end generate;
	kb_clk <= 'H';
	kb_data <= 'H';
	ms_clk <= 'H';
	ms_data <= 'H';
	idedata <= (others => 'H');

	cf : entity work.ata_device_model
	generic map (SECTORS => SECTORS)
	port map (
		cs0_n => cs0_n, cs1_n => cs1_n, a => idea, dior_n => dior_n, diow_n => diow_n, d => idedata,
		commands => ata_cmds, dior_min => dior_min, diow_min => diow_min, setup_min => ata_setup_min
	);

	-- -------------------------------------------------------------------
	-- Capture windows and bus checks
	-- -------------------------------------------------------------------
	window_k30 : process
		variable t_edge, t_chg : time := 0 ns;
	begin
		wait on k30_vid(15), k30_in;
		if running and now > 2 us then
			if rising_edge(k30_vid(15)) then
				k30_setup <= minimum(k30_setup, now - t_chg);
				t_edge := now;
			end if;
			if k30_in'event then
				k30_hold <= minimum(k30_hold, now - t_edge);
			end if;
		end if;
		if k30_in'event then
			t_chg := now;
		end if;
	end process;

	window_ext : process
		variable t_edge, t_chg : time := 0 ns;
	begin
		wait on ext_vid(15), ext_in;
		if running and now > 2 us then
			if rising_edge(ext_vid(15)) then
				ext_setup <= minimum(ext_setup, now - t_chg);
				t_edge := now;
			end if;
			if ext_in'event then
				ext_hold <= minimum(ext_hold, now - t_edge);
			end if;
		end if;
		if ext_in'event then
			t_chg := now;
		end if;
	end process;

	drive_check : process(idedata, ext_vid, k30_vid)
	begin
		if running then
			assert not is_x(ext_vid) and not is_x(k30_vid) report "vid line undriven or in contention: " & to_string(ext_vid) & " " & to_string(k30_vid)
				severity error;
			for i in idedata'range loop
				assert idedata(i) /= 'X' report "IDE data bus contention" severity error;
			end loop;
		end if;
	end process;

	sync_check : process
	begin
		wait until running;
		wait until sync_ok = '1' for 20 us;
		assert sync_ok = '1' report "link did not lock" severity failure;
		t_sync <= now;
		wait until sync_ok = '0';
		report "link lost sync" severity error;
	end process;

	-- -------------------------------------------------------------------
	-- SD firmware sequence (firmware/spi_sd.c)
	-- -------------------------------------------------------------------
	sd_host : process
		variable r : natural;
		variable v : std_logic_vector(31 downto 0);
		variable buf : byte_list(0 to 511);
		variable t0 : time;
		variable ok : boolean;

		-- substitute_mcu: SPI(x) triggers a transfer once the controller is
		-- idle on an SPI tick; SPI_READ() then waits for it to finish.
		procedure spi(b : std_logic_vector(7 downto 0)) is
		begin
			wait until rising_edge(clk_50) and busy = '0' and spi_tick = '1';
			host_to_spi <= b;
			trigger <= '1';
			wait until rising_edge(clk_50);
			trigger <= '0';
		end procedure;

		procedure spi_read(rd : out natural) is
		begin
			wait until rising_edge(clk_50) and busy = '0' and spi_tick = '1';
			rd := to_integer(unsigned(spi_to_host));
		end procedure;

		procedure xfer(b : natural; rd : out natural) is
		begin
			spi(std_logic_vector(to_unsigned(b, 8)));
			spi_read(rd);
		end procedure;

		procedure set_cs(cs_n, fast : std_logic) is
		begin
			wait until rising_edge(clk_50) and busy = '0' and spi_tick = '1';
			spi_cs_n <= cs_n;
			spi_fast <= fast;
		end procedure;

		procedure spin is
		begin
			for i in 1 to SPIN_BYTES loop
				spi(x"FF");
			end loop;
		end procedure;

		-- spi_sd.c:95-129 (sd_is_sdhc = 1: block addressing)
		procedure cmd_write(cmd : natural; lba : natural; rd : out natural) is
			variable a : std_logic_vector(31 downto 0) := std_logic_vector(to_unsigned(lba, 32));
			variable c : std_logic_vector(23 downto 0) := std_logic_vector(to_unsigned(cmd, 24));
			variable res : natural;
		begin
			spi(c(7 downto 0));
			for k in 3 downto 0 loop
				spi(a(8 * k + 7 downto 8 * k));
			end loop;
			spi(c(23 downto 16));
			spi_read(res);
			for i in 1 to 40000 loop
				exit when res /= 255;
				xfer(255, res);
			end loop;
			rd := res;
		end procedure;

		-- spi_sd.c:354-377
		procedure sd_read(n : natural; good : out boolean) is
			variable res : natural;
		begin
			good := false;
			for i in 1 to 1500000 loop
				xfer(255, res);
				exit when res = 16#FE# or res = 1;
			end loop;
			if res = 16#FE# then
				for i in 0 to n - 1 loop
					xfer(255, res);
					buf(i) := std_logic_vector(to_unsigned(res, 8));
				end loop;
				good := true;
			end if;
			spi(x"FF");
			spi(x"FF");
		end procedure;

		procedure read_sector(lba : natural; expect_ok : boolean) is
			variable res : natural;
			variable good : boolean;
		begin
			spi(x"FF");
			set_cs('0', '1');
			spi(x"FF");
			cmd_write(16#FF0051#, lba, res);
			assert res = 0 report "CMD17 R1 " & integer'image(res) severity error;
			sd_read(512, good);
			set_cs('1', '1');
			assert good = expect_ok report "sector " & integer'image(lba) & " read status wrong" severity error;
		end procedure;

		procedure write_sector(lba : natural) is
			variable res : natural;
		begin
			spi(x"FF");
			set_cs('0', '1');
			spi(x"FF");
			cmd_write(16#FF0058#, lba, res);
			assert res = 0 report "CMD24 R1 " & integer'image(res) severity error;
			spi(x"FF");
			spi(x"FE");
			for i in 0 to 511 loop
				spi(wr_byte(lba, i));
			end loop;
			spi(x"FF");
			spi(x"FF");
			xfer(255, res);
			assert res mod 32 = 5 report "data response " & integer'image(res) severity error;
			for i in 1 to 100000 loop
				xfer(255, res);
				exit when res /= 0;
			end loop;
			assert res = 255 report "write busy ended with " & integer'image(res) severity error;
			spi(x"FF");
			set_cs('1', '1');
		end procedure;

		procedure check_read(lba : natural; written : boolean) is
			variable w : std_logic_vector(15 downto 0);
			variable e : std_logic_vector(7 downto 0);
			variable bad : natural := 0;
		begin
			for i in 0 to 511 loop
				w := ata_word(lba, i / 2);
				e := w(8 * (i mod 2) + 7 downto 8 * (i mod 2));
				if written then
					e := wr_byte(lba, i);
				end if;
				if buf(i) /= e then
					bad := bad + 1;
				end if;
			end loop;
			assert bad = 0 report "sector " & integer'image(lba) & ": " & integer'image(bad)
				& " bytes wrong" severity error;
		end procedure;

		constant LBAS : integer_vector := (16#1234567#, 0, SECTORS - 1);
	begin
		wait until running and sync_ok = '1';
		t0 := now;
		-- sd_init, spi_sd.c:262-303
		for i in 1 to 7 loop
			set_cs('1', '0');
			spin;
			set_cs('0', '0');
			cmd_write(16#950040#, 0, r);
			exit when r = 1;
			assert i < 7 report "CMD0 never answered 1" severity failure;
		end loop;
		-- is_sdhc, spi_sd.c:192-259
		spin;
		cmd_write(16#870048#, 16#1AA#, r);
		assert r = 1 report "CMD8 R1 " & integer'image(r) severity error;
		for k in 0 to 3 loop
			xfer(255, r);
			v := v(23 downto 0) & std_logic_vector(to_unsigned(r, 8));
		end loop;
		assert v(15 downto 0) = x"01AA" report "CMD8 R7 " & to_hstring(v) severity error;
		spi(x"FF");
		spin;
		cmd_write(16#FF0077#, 0, r);
		assert r = 1 report "CMD55 R1 " & integer'image(r) severity error;
		spi(x"FF");
		cmd_write(16#870069#, 16#40000000#, r);
		assert r = 0 report "ACMD41 R1 " & integer'image(r) severity error;
		spi(x"FF");
		cmd_write(16#FF007A#, 0, r);
		assert r = 0 report "CMD58 R1 " & integer'image(r) severity error;
		xfer(255, r);
		assert r / 64 mod 2 = 1 report "OCR CCS clear" severity error;
		for k in 1 to 4 loop
			spi(x"FF");
		end loop;
		spi(x"FF");
		-- sd_get_size, spi_sd.c:404-441
		cmd_write(16#FF0049#, 0, r);
		assert r = 0 report "CMD9 R1 " & integer'image(r) severity error;
		sd_read(18, ok);
		assert ok and unsigned(buf(0)(7 downto 6)) = 1 report "CSD not v2" severity error;
		sd_size <= (to_integer(unsigned(std_logic_vector'(buf(7)(5 downto 0) & buf(8) & buf(9)))) + 1) * 1024;
		set_cs('1', '0');
		spi(x"FF");
		t_init <= now - t0;

		for k in LBAS'range loop
			t0 := now;
			read_sector(LBAS(k), true);
			t_read <= now - t0;
			check_read(LBAS(k), false);
			exit when not FULL;
		end loop;
		t0 := now;
		write_sector(LBAS(0));
		t_write <= now - t0;
		read_sector(LBAS(1), true);
		check_read(LBAS(1), false);
		read_sector(LBAS(0), true);
		check_read(LBAS(0), true);
		if FULL then
			read_sector(SECTORS, false);
			set_cs('0', '1');
			cmd_write(16#FF004D#, 0, r);
			assert r = 4 report "illegal command R1 " & integer'image(r) severity error;
			set_cs('1', '1');
			write_sector(LBAS(2));
			read_sector(LBAS(2), true);
			check_read(LBAS(2), true);
		end if;
		sd_done <= true;
		wait;
	end process;

	-- -------------------------------------------------------------------
	-- PS/2: keyboard (k = 0) and mouse (k = 1) devices on the 1k30 pins,
	-- frames decoded from the extender's ps2*_in; the keyboard device first
	-- checks that the extender can inhibit it.
	-- -------------------------------------------------------------------
	kb_clk <= dev_clk(0);
	kb_data <= dev_dat(0);
	ms_clk <= dev_clk(1);
	ms_data <= dev_dat(1);

	-- the extender inhibits the keyboard before the devices start sending
	ps2_inhibit : process
	begin
		wait until running and sync_ok = '1';
		ps2_out(3) <= '0';
		wait until to_x01(kb_clk) = '0' for 10 us;
		assert to_x01(kb_clk) = '0' report "PS/2 inhibit did not reach the 1k30" severity error;
		ps2_out(3) <= '1';
		wait;
	end process;

	ps2_dev : for k in 0 to 1 generate
		signal armed : boolean := false;
	begin
		device : process
			constant H : time := PS2_HALF_NS * 1 ns;
			variable frame : std_logic_vector(10 downto 0);
		begin
			wait until running and sync_ok = '1';
			wait for 20 us;
			armed <= true;
			for b in PS2_BYTES'range loop
				frame := '1' & odd_parity(PS2_BYTES(b)) & PS2_BYTES(b) & '0';
				for j in 0 to 10 loop
					dev_dat(k) <= 'Z';
					if frame(j) = '0' then
						dev_dat(k) <= '0';
					end if;
					wait for H / 2;
					dev_clk(k) <= '0';
					wait for H;
					dev_clk(k) <= 'Z';
					wait for H / 2;
				end loop;
				wait for 4 * H;
			end loop;
			wait;
		end process;

		host : process
			variable frame : std_logic_vector(10 downto 0);
			variable nbit, nbyte : natural := 0;
		begin
			wait until falling_edge(ps2_in(3 - 2 * k)) and armed;
			frame := ps2_in(2 - 2 * k) & frame(10 downto 1);
			nbit := nbit + 1;
			if nbit = 11 then
				assert frame(0) = '0' and frame(10) = '1' and frame(9) = odd_parity(frame(8 downto 1))
					and nbyte <= PS2_BYTES'high and frame(8 downto 1) = PS2_BYTES(nbyte)
					report "PS/2 " & integer'image(k) & " frame " & integer'image(nbyte) & " wrong: "
					& to_hstring(frame) severity error;
				nbyte := nbyte + 1;
				ps2_rx(k) <= nbyte;
				nbit := 0;
			end if;
		end process;
	end generate;

	ps2_done <= ps2_rx(0) = PS2_BYTES'length and ps2_rx(1) = PS2_BYTES'length;

	-- -------------------------------------------------------------------
	-- Joysticks: the CPLD's 16-bit ioshift stream (Cone_core_development
	-- section 7.3: bit 0 sync '0', bit 1 lpt busy, 2-8 port A, 9-15 port B),
	-- re-timed to C2MHz rising edges as the 1k30's gdemux does.
	-- -------------------------------------------------------------------
	c2mhz <= not c2mhz after C2M_NS * 1 ns / 2;

	joy_stream : process
		variable s : std_logic_vector(0 to 15);
	begin
		-- port A: 2,3 pot, 4 right, 5 left, 6 down, 7 fire, 8 up
		-- port B: 9 up, 10 fire, 11 down, 12 left, 13 right, 14,15 pot
		s := "01" & "11" & joy_ta(3) & joy_ta(2) & joy_ta(1) & joy_ta(4) & joy_ta(0)
			& joy_tb(0) & joy_tb(4) & joy_tb(1) & joy_tb(2) & joy_tb(3) & "11";
		for i in s'range loop
			ioshift <= s(i) after 20 ns;
			wait until rising_edge(c2mhz);
		end loop;
	end process;

	joy_check : process
		constant BOUND : time := 3 * 16 * C2M_NS * 1 ns;
		variable a, b : unsigned(5 downto 0);
		variable t0, lmax : time := 0 ns;
		variable ok : boolean;
	begin
		-- sticks released while the frame locks onto the sync bit
		-- (cyclone.vhd:209 would also take a pressed button's '0')
		wait until running and sync_ok = '1';
		wait for 3 * 16 * C2M_NS * 1 ns;
		for k in 0 to 11 loop
			a := '1' & to_unsigned((k * 13 + 5) mod 32, 5);
			b := '1' & to_unsigned((k * 7 + 17) mod 32, 5);
			joy_ta <= a;
			joy_tb <= b;
			t0 := now;
			loop
				wait until rising_edge(clk_100);
				ok := joy_a = a and joy_b = b
					and merged1 = "11" & std_logic(a(4)) & std_logic(a(5)) & std_logic_vector(a(3 downto 0))
					and merged2 = "11" & std_logic(b(4)) & std_logic(b(5)) & std_logic_vector(b(3 downto 0));
				exit when ok or now - t0 > BOUND;
			end loop;
			assert ok report "joystick step " & integer'image(k) & ": " & to_string(joy_a) & " " & to_string(joy_b) & " expected " & to_string(a) & " " & to_string(b) & " not delivered within "
				& time'image(BOUND) severity error;
			lmax := maximum(lmax, now - t0);
		end loop;
		joy_lat <= lmax;
		joy_done <= true;
		wait;
	end process;

	-- -------------------------------------------------------------------
	-- Audio: the 1k30's lrclk/adat (re-timed to C2MHz falling). Each
	-- channel is 24 C2MHz periods; MSB first from the 8th period after the
	-- lrclk change; lrclk low carries the left sample (cyclone.vhd:171-201).
	-- -------------------------------------------------------------------
	audio_check : process
		variable k : natural := 0;
		variable last : std_logic := 'U';
		variable word : std_logic_vector(15 downto 0);
		variable good : natural := 0;
	begin
		wait until rising_edge(c2mhz);
		if running and sync_ok = '1' then
			if lrclk /= last then
				k := 0;
			else
				k := k + 1;
			end if;
			last := lrclk;
			if k >= 8 and k <= 23 then
				word(23 - k) := adat;
			end if;
			if k = 23 then
				assert (lrclk = '0' and word = AUDIO_L) or (lrclk = '1' and word = AUDIO_R)
					report "audio channel " & std_logic'image(lrclk) & " got " & to_hstring(word) severity error;
				good := good + 1;
				audio_ok <= good >= 4;
			end if;
		end if;
	end process;

	txd_check : process
	begin
		wait until running and sync_ok = '1';
		for k in 0 to 3 loop
			txd <= not txd;
			wait until k30_txd = txd for 1 us;
			assert k30_txd = txd report "TxD not relayed" severity error;
		end loop;
		txd_done <= true;
		wait;
	end process;

	sck_period : process
		variable t : time := 0 ns;
	begin
		wait until rising_edge(spi_sck);
		if spi_cs_n = '0' and spi_fast = '1' then
			sck_fast <= minimum(sck_fast, now - t);
		elsif spi_cs_n = '0' then
			sck_slow <= minimum(sck_slow, now - t);
		end if;
		t := now;
	end process;

	-- -------------------------------------------------------------------
	-- Summary
	-- -------------------------------------------------------------------
	finish_proc : process
	begin
		wait until sd_done and ps2_done and joy_done and audio_ok and txd_done for 200 ms;
		assert sd_done and ps2_done and joy_done and audio_ok and txd_done
			report "timeout: sd " & boolean'image(sd_done) & " ps2 " & boolean'image(ps2_done)
			& " joy " & boolean'image(joy_done) & " audio " & boolean'image(audio_ok)
			& " txd " & boolean'image(txd_done) severity failure;
		report "RESULT ext_setup_ps=" & integer'image(ext_setup / 1 ps);
		report "RESULT ext_hold_ps=" & integer'image(ext_hold / 1 ps);
		report "RESULT k30_setup_ps=" & integer'image(k30_setup / 1 ps);
		report "RESULT k30_hold_ps=" & integer'image(k30_hold / 1 ps);
		report "RESULT sync_ns=" & integer'image(t_sync / 1 ns);
		report "RESULT sck_slow_ns=" & integer'image(sck_slow / 1 ns);
		report "RESULT sck_fast_ns=" & integer'image(sck_fast / 1 ns);
		report "RESULT sd_init_us=" & integer'image(t_init / 1 us);
		report "RESULT read_us=" & integer'image(t_read / 1 us);
		report "RESULT write_us=" & integer'image(t_write / 1 us);
		report "RESULT sd_size=" & integer'image(sd_size);
		report "RESULT ata_cmds=" & integer'image(ata_cmds);
		report "RESULT dior_ns=" & integer'image(dior_min / 1 ns);
		report "RESULT diow_ns=" & integer'image(diow_min / 1 ns);
		report "RESULT ata_setup_ns=" & integer'image(ata_setup_min / 1 ns);
		report "RESULT joy_lat_ns=" & integer'image(joy_lat / 1 ns);
		assert sd_size = SECTORS / 1024 * 1024 report "CSD size " & integer'image(sd_size) severity error;
		assert ext_setup >= MARGIN and ext_hold > MARGIN report "extender capture window violated"
			severity error;
		assert k30_setup >= MARGIN and k30_hold > MARGIN report "1k30 capture window violated"
			severity error;
		report "RESULT PASS";
		finish;
	end process;
end architecture;
