create_clock -period 35 [get_ports clk28];
derive_pll_clocks
# create_clock -period 6.34 [get_nets {cone_chameleon_for_c1|sysclk}];

