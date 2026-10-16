-- k30_mm_model: behavioural model of the 1k30 end of the Minimig V2.01
-- C-One vid-bus link, written from the protocol description in
-- docs/minimig_link.md. Same ports as 1k30/acex.vhd so the testbench can
-- swap in the real file. Stricter than the hardware: it reports any link
-- word the extender should never send at that point.
--
-- Every action happens on a rising IOclk edge. The link inputs are
-- registered, so a decision at edge n uses the extender's word from edge
-- n-1 ("seen" below).
--   IDE: seen = 010000 (read) / 100000 (write) at edge s; edge s+1
--        latches register and chip selects; a read drops DIOR- at s+2; a
--        write drops DIOW- at s+2 and takes data bits 5..0, 11..6, 15..12
--        at s+2..s+4, driving the bus from s+4. seen = 000000 at edge c
--        releases the strobe at c+1 (a read latches the bus there) and
--        returns the read word on vid[3:0] as nibbles, low first, at
--        c+2..c+5; chip selects and the bus are released at c+2.
--   Serial: slot j = 0..7 free-running; the 1k30 sends sync (toggling
--        each frame), kb_data, kb_clk, ms_data, ms_clk, RxD ('1'), C2MHz,
--        ioshift; the extender's bit seen in slot j is lrclk (0), audio
--        data (1), kb_data (3), kb_clk (4), ms_data (5), ms_clk (6),
--        TxD (7). PS/2 lines are open drain. lrclk/adat are re-timed to
--        the falling edge of C2MHz.

library ieee;
use ieee.std_logic_1164.all;

entity k30_mm_model is
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
end entity;

architecture behav of k30_mm_model is
	signal nibble : std_logic_vector(3 downto 0) := "1111";
	signal ps2 : std_logic_vector(3 downto 0) := "1111"; -- kb_data kb_clk ms_data ms_clk
	signal lr_d, ad_d : std_logic := '0';
begin
	addonout(4) <= '1';
	addonout(3 downto 0) <= nibble;
	kb_data <= '0' when ps2(3) = '0' else 'Z';
	kb_clk <= '0' when ps2(2) = '0' else 'Z';
	ms_data <= '0' when ps2(1) = '0' else 'Z';
	ms_clk <= '0' when ps2(0) = '0' else 'Z';

	ide : process
		variable cur, seen : std_logic_vector(5 downto 0) := "111111";
		variable wdata, rdata : std_logic_vector(15 downto 0);
		variable rd : boolean;

		procedure edge is
		begin
			wait until rising_edge(IOclk);
			seen := cur;
			cur := to_x01(addonin(5 downto 0));
		end procedure;
	begin
		idea <= "000";
		ide_rd <= '1';
		ide_wr <= '1';
		ide_csp0 <= '1';
		ide_css0 <= '1';
		idedata <= (others => 'Z');
		loop
			edge;
			nibble <= "1111";
			next when seen = "111111";
			assert seen = "010000" or seen = "100000"
				report "k30 model: link word " & to_string(seen) & " while idle" severity error;
			next when seen /= "010000" and seen /= "100000";
			rd := seen = "010000";
			edge;
			idea <= seen(2 downto 0);
			ide_csp0 <= seen(4);
			ide_css0 <= seen(5);
			edge;
			if rd then
				ide_rd <= '0';
			else
				ide_wr <= '0';
				wdata(5 downto 0) := seen;
				edge;
				wdata(11 downto 6) := seen;
				edge;
				wdata(15 downto 12) := seen(3 downto 0);
				idedata <= wdata;
			end if;
			loop
				edge;
				exit when seen = "000000";
				assert seen = "111111"
					report "k30 model: link word " & to_string(seen) & " before close" severity error;
			end loop;
			edge;
			rdata := to_x01(idedata);
			ide_rd <= '1';
			ide_wr <= '1';
			edge;
			ide_csp0 <= '1';
			ide_css0 <= '1';
			idedata <= (others => 'Z');
			if rd then
				for k in 0 to 3 loop
					nibble <= rdata(4 * k + 3 downto 4 * k);
					if k < 3 then
						edge;
					end if;
				end loop;
			end if;
		end loop;
	end process;

	serial : process
		variable slot : natural range 0 to 7 := 0;
		variable sync : std_logic := '0';
		variable line : std_logic := '1';
		variable pins : std_logic_vector(3 downto 0);
	begin
		wait until rising_edge(IOclk);
		pins := to_x01(kb_data & kb_clk & ms_data & ms_clk);
		case slot is
			when 0 => addonout(5) <= sync; lr_d <= line;
			when 1 => addonout(5) <= pins(3); ad_d <= line;
			when 2 => addonout(5) <= pins(2);
			when 3 => addonout(5) <= pins(1); ps2(3) <= line;
			when 4 => addonout(5) <= pins(0); ps2(2) <= line;
			when 5 => addonout(5) <= '1'; ps2(1) <= line;
			when 6 => addonout(5) <= C2MHz; ps2(0) <= line;
			when 7 => addonout(5) <= ioshift; TxD <= line; sync := not sync;
		end case;
		slot := (slot + 1) mod 8;
		line := to_x01(addonin(7));
	end process;

	process(C2MHz)
	begin
		if falling_edge(C2MHz) then
			lrclk <= lr_d;
			adat <= ad_d;
		end if;
	end process;
end architecture;
