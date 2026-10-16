-- Behavioural model of DeMiSTify controller/spi_controller.vhd with the same
-- entity interface, so simulations can run with or without the DeMiSTify
-- submodule (sim.sh substitutes the upstream file when it is present).
--
-- Byte transfer, MSB first, SCK idling high. trigger loads host_to_spi and
-- issues a request with SCK unchanged. Each time spi_ack equals spi_req the
-- next half-cycle is issued together with a new request (spi_req := not
-- spi_ack): SCK low with the next MOSI bit, then SCK high while shifting in
-- MISO as it stands at that moment. busy drops after the eighth rising edge.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity spi_controller is
	port (
		sysclk : in std_logic;
		reset : in std_logic;
		host_to_spi : in std_logic_vector(7 downto 0);
		spi_to_host : out std_logic_vector(7 downto 0);
		trigger : in std_logic;
		busy : buffer std_logic;
		spi_req : out std_logic;
		spi_ack : in std_logic;
		miso : in std_logic;
		mosi : out std_logic;
		spiclk_out : out std_logic
	);
end entity;

architecture model of spi_controller is
	signal req : std_logic := '0';
	signal sck : std_logic := '1';
	signal shift : std_logic_vector(7 downto 0) := (others => '1');
	signal bits : natural range 0 to 8 := 0;
begin
	spi_req <= req;
	spiclk_out <= sck;
	spi_to_host <= shift;
	busy <= '1' when bits /= 0 or trigger = '1' else '0';

	process(sysclk, reset)
	begin
		if reset = '0' then
			bits <= 0;
			sck <= '1';
			mosi <= '1';
			shift <= (others => '1');
		elsif rising_edge(sysclk) then
			if trigger = '1' then
				bits <= 8;
				shift <= host_to_spi;
				sck <= '1';
				req <= not spi_ack;
			elsif req = spi_ack and bits /= 0 then
				if sck = '1' then
					mosi <= shift(7);
					sck <= '0';
				else
					shift <= shift(6 downto 0) & miso;
					bits <= bits - 1;
					sck <= '1';
				end if;
				req <= not spi_ack;
			end if;
		end if;
	end process;
end architecture;
