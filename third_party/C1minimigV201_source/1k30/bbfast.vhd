-- Copyright (C) 1991-2009 Altera Corporation
-- Your use of Altera Corporation's design tools, logic functions 
-- and other software and tools, and its AMPP partner logic 
-- functions, and any output files from any of the foregoing 
-- (including device programming or simulation files), and any 
-- associated documentation or information are expressly subject 
-- to the terms and conditions of the Altera Program License 
-- Subscription Agreement, Altera MegaCore Function License 
-- Agreement, or other applicable license agreement, including, 
-- without limitation, that your use is for the sole purpose of 
-- programming logic devices manufactured by Altera and sold by 
-- Altera or its authorized distributors.  Please refer to the 
-- applicable agreement for further details.

-- PROGRAM		"Quartus II"
-- VERSION		"Version 9.0 Build 132 02/25/2009 SJ Web Edition"
-- CREATED ON		"Sat Oct 24 15:02:46 2009"

LIBRARY ieee;
USE ieee.std_logic_1164.all; 

LIBRARY work;

ENTITY bbfast IS 
	PORT
	(
		sysclk :  IN  STD_LOGIC;
		2MHz :  IN  STD_LOGIC;
		RxD :  IN  STD_LOGIC;
		nreset :  IN  STD_LOGIC;
		hostclk :  IN  STD_LOGIC;
		nIrq :  IN  STD_LOGIC;
		keyboard_clk :  INOUT  STD_LOGIC;
		keyboard_data :  INOUT  STD_LOGIC;
		mice_clk :  INOUT  STD_LOGIC;
		mice_data :  INOUT  STD_LOGIC;
		addbi :  IN  STD_LOGIC_VECTOR(8 DOWNTO 0);
		cselects :  IN  STD_LOGIC_VECTOR(3 DOWNTO 0);
		gb :  IN  STD_LOGIC_VECTOR(5 DOWNTO 0);
		idedb :  INOUT  STD_LOGIC_VECTOR(15 DOWNTO 0);
		bank0_we :  OUT  STD_LOGIC;
		bank0_cas :  OUT  STD_LOGIC;
		bank0_ras0 :  OUT  STD_LOGIC;
		bank0_ras1 :  OUT  STD_LOGIC;
		1K100cs :  OUT  STD_LOGIC;
		1MHz :  OUT  STD_LOGIC;
		nC1K100 :  OUT  STD_LOGIC;
		CS :  OUT  STD_LOGIC;
		addon :  OUT  STD_LOGIC;
		iowr :  OUT  STD_LOGIC;
		iord :  OUT  STD_LOGIC;
		ide1cs :  OUT  STD_LOGIC;
		adac_data :  OUT  STD_LOGIC;
		lrclk :  OUT  STD_LOGIC;
		ide2cs :  OUT  STD_LOGIC;
		TxD :  OUT  STD_LOGIC;
		addo_clk :  OUT  STD_LOGIC;
		addbo :  OUT  STD_LOGIC_VECTOR(5 DOWNTO 0);
		gbo :  OUT  STD_LOGIC_VECTOR(7 TO 7);
		idea :  OUT  STD_LOGIC_VECTOR(2 DOWNTO 0)
	);
END bbfast;

ARCHITECTURE bdf_type OF bbfast IS 

COMPONENT gdemux
	PORT(C100MHz : IN STD_LOGIC;
		 C2MHz : IN STD_LOGIC;
		 ioclk : IN STD_LOGIC;
		 iowr : IN STD_LOGIC;
		 memwr : IN STD_LOGIC;
		 adr : IN STD_LOGIC_VECTOR(21 DOWNTO 0);
		 Csel : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
		 data : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
		 gbi : IN STD_LOGIC_VECTOR(5 DOWNTO 0);
		 ovsync : OUT STD_LOGIC;
		 ohsync : OUT STD_LOGIC;
		 olr_clk : OUT STD_LOGIC;
		 oauda : OUT STD_LOGIC;
		 busfree : OUT STD_LOGIC;
		 ioshift : OUT STD_LOGIC;
		 1MHzout : OUT STD_LOGIC;
		 gbo : OUT STD_LOGIC_VECTOR(7 TO 7);
		 ovid : OUT STD_LOGIC_VECTOR(15 DOWNTO 0)
	);
END COMPONENT;

COMPONENT acex
	PORT(ide1irq : IN STD_LOGIC;
		 C2MHz : IN STD_LOGIC;
		 ioshift : IN STD_LOGIC;
		 kb_clk : INOUT STD_LOGIC;
		 kb_data : INOUT STD_LOGIC;
		 ms_clk : INOUT STD_LOGIC;
		 ms_data : INOUT STD_LOGIC;
		 addonin : IN STD_LOGIC_VECTOR(8 DOWNTO 0);
		 idedata : INOUT STD_LOGIC_VECTOR(15 DOWNTO 0);
		 ide_wr : OUT STD_LOGIC;
		 ide_rd : OUT STD_LOGIC;
		 ide_csp0 : OUT STD_LOGIC;
		 ide_css0 : OUT STD_LOGIC;
		 TxD : OUT STD_LOGIC;
		 lrclk : OUT STD_LOGIC;
		 adat : OUT STD_LOGIC;
		 addonout : OUT STD_LOGIC_VECTOR(5 DOWNTO 0);
		 idea : OUT STD_LOGIC_VECTOR(2 DOWNTO 0);
		 ring_o : OUT STD_LOGIC_VECTOR(3 DOWNTO 0)
	);
END COMPONENT;

SIGNAL	g :  STD_LOGIC;
SIGNAL	v :  STD_LOGIC;
SIGNAL	SYNTHESIZED_WIRE_13 :  STD_LOGIC;
SIGNAL	SYNTHESIZED_WIRE_14 :  STD_LOGIC_VECTOR(0 TO 21);
SIGNAL	SYNTHESIZED_WIRE_4 :  STD_LOGIC;
SIGNAL	SYNTHESIZED_WIRE_5 :  STD_LOGIC;
SIGNAL	SYNTHESIZED_WIRE_15 :  STD_LOGIC;


BEGIN 
bank0_we <= '1';
bank0_cas <= '1';
bank0_ras0 <= '1';
bank0_ras1 <= '1';
1K100cs <= '1';
nC1K100 <= '1';
CS <= '1';
addon <= '1';
addo_clk <= sysclk;
SYNTHESIZED_WIRE_13 <= '1';
SYNTHESIZED_WIRE_14 <= "1111111111111111111111";



b2v_inst : gdemux
PORT MAP(C100MHz => sysclk,
		 C2MHz => 2MHz,
		 ioclk => v,
		 iowr => SYNTHESIZED_WIRE_13,
		 memwr => SYNTHESIZED_WIRE_13,
		 adr => SYNTHESIZED_WIRE_14,
		 Csel => cselects,
		 data => SYNTHESIZED_WIRE_14(7 DOWNTO 0),
		 gbi => gb,
		 ioshift => SYNTHESIZED_WIRE_5,
		 1MHzout => 1MHz,
		 gbo(0) => gbo(7));


b2v_inst1 : acex
PORT MAP(ide1irq => SYNTHESIZED_WIRE_4,
		 C2MHz => hostclk,
		 ioshift => SYNTHESIZED_WIRE_5,
		 kb_clk => keyboard_clk,
		 kb_data => keyboard_data,
		 ms_clk => mice_clk,
		 ms_data => mice_data,
		 addonin => addbi,
		 idedata => idedb,
		 ide_wr => iowr,
		 ide_rd => iord,
		 ide_csp0 => ide1cs,
		 ide_css0 => ide2cs,
		 TxD => TxD,
		 lrclk => lrclk,
		 adat => adac_data,
		 idea => idea);




SYNTHESIZED_WIRE_4 <= NOT(nIrq);





PROCESS(sysclk)
BEGIN
IF (RISING_EDGE(sysclk)) THEN
	addbo(5 DOWNTO 0) <= addbi(5 DOWNTO 0);
END IF;
END PROCESS;



g <= '0';
v <= '1';
END bdf_type;