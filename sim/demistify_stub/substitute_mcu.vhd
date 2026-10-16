-- Interface-only stand-in for DeMiSTify's controller/substitute_mcu.vhd so
-- board toplevels can be elaborated without the DeMiSTify submodule or a
-- generated controller_rom. The entity declaration is copied from upstream
-- (GPL-3, Alastair M. Robinson); outputs hold their idle levels.

library ieee;
use ieee.std_logic_1164.all;

entity substitute_mcu is
	generic (
		joybits : integer := 8;
		debug : boolean := false;
		jtag_uart : boolean := false;
		spirtc : boolean := false;
		sysclk_frequency : integer := 500; -- Sysclk frequency * 10
		SPI_SLOWBIT : integer := 6;  -- ~384KHz when sysclk is 50MHz
		SPI_FASTBIT : integer := 2 ; -- ~5MHz when sysclk is 50MHz
		SPI_INTERNALBIT : integer := 1; -- Full speed when 0, half speed when 1
		SPI_EXTERNALCLK : boolean := false
	);
	port (
		clk 			: in std_logic;
		reset_in 	: in std_logic;
		reset_out   : out std_logic;

		-- SPI signals
		spi_miso		: in std_logic := '1'; -- Allow the SPI interface not to be plumbed in.
		spi_clk		: out std_logic;
		spi_cs 		: out std_logic;
		spi_mosi    : out std_logic;
		spi_toguest : out std_logic;
		spi_fromguest : in std_logic;
		spi_ss2 : out std_logic;
		spi_ss3 : out std_logic;
		spi_ss4 : out std_logic;
		spi_srtc : out std_logic;
		conf_data0 : out std_logic;
		spi_req : out std_logic;
		spi_ack : in std_logic := '1';
		
		-- PS/2 signals
		ps2k_clk_in : in std_logic := '1';
		ps2k_dat_in : in std_logic := '1';
		ps2k_clk_out : out std_logic;
		ps2k_dat_out : out std_logic;
		ps2m_clk_in : in std_logic := '1';
		ps2m_dat_in : in std_logic := '1';
		ps2m_clk_out : out std_logic;
		ps2m_dat_out : out std_logic;

		-- Joysticks and other inputs
		
		joy1 : in std_logic_vector(joybits-1 downto 0) := (others => '1');
		joy2 : in std_logic_vector(joybits-1 downto 0) := (others => '1');
		joy3 : in std_logic_vector(joybits-1 downto 0) := (others => '1');
		joy4 : in std_logic_vector(joybits-1 downto 0) := (others => '1');
		
		buttons : in std_logic_vector(31 downto 0) := (others => '1');
		
		c64_keys	: in std_logic_vector(63 downto 0) :=X"FFFFFFFFFFFFFFFF";

		-- UART
		rxd	: in std_logic;
		txd	: out std_logic;
		intercept : out std_logic
);
end entity;

architecture stub of substitute_mcu is
begin
	reset_out <= reset_in;
	spi_clk <= '1';
	spi_cs <= '1';
	spi_mosi <= '1';
	spi_toguest <= '1';
	spi_ss2 <= '1';
	spi_ss3 <= '1';
	spi_ss4 <= '1';
	spi_srtc <= '1';
	conf_data0 <= '1';
	spi_req <= spi_ack;
	ps2k_clk_out <= '1';
	ps2k_dat_out <= '1';
	ps2m_clk_out <= '1';
	ps2m_dat_out <= '1';
	txd <= rxd;
	intercept <= '0';
end architecture;
