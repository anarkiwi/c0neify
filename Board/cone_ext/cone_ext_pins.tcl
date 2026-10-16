# C-One FPGA Extender (Cyclone III EP3C25E144C8) pin assignments
# for a DeMiSTify "cone_ext" board target.
#
# Source: Peter Wendrich, "C-One core development", section 13
# (Pins and Signals), Ext. column, July 2010.
# Cross-check against C1_extender.pin from the iComp wiki before first use:
# that file is taken directly from the working Minimig Quartus project.
#
# Naming follows the DeMiSTify Chameleon convention (red/grn/blu,
# ram_*, sigma_*) so the Chameleon templates port with minimal edits.

# ---------------------------------------------------------------
# Clocks (extender has its own crystals)
# ---------------------------------------------------------------
set_location_assignment PIN_55  -to clk14      ;# 14.31818 MHz (4x NTSC colour burst)
set_location_assignment PIN_126 -to clk28      ;# 28.37516 MHz (PAL-derived)

# ---------------------------------------------------------------
# VGA - direct from extender. 5/6/5 bits.
# ---------------------------------------------------------------
set_location_assignment PIN_86 -to red[0]
set_location_assignment PIN_85 -to red[1]
set_location_assignment PIN_83 -to red[2]
set_location_assignment PIN_80 -to red[3]
set_location_assignment PIN_77 -to red[4]

set_location_assignment PIN_72 -to grn[0]
set_location_assignment PIN_69 -to grn[1]
set_location_assignment PIN_67 -to grn[2]
set_location_assignment PIN_65 -to grn[3]
set_location_assignment PIN_64 -to grn[4]
set_location_assignment PIN_59 -to grn[5]

set_location_assignment PIN_49 -to blu[0]
set_location_assignment PIN_51 -to blu[1]
set_location_assignment PIN_50 -to blu[2]
set_location_assignment PIN_44 -to blu[3]
set_location_assignment PIN_42 -to blu[4]

# Sync lines are shared with the 1k30 and are open-collector from the
# extender side: drive the FPGA pin HIGH to pull the sync line LOW.
# NewBoot tri-states the 1k30's sync outputs when it loads extender.rbf.
set_location_assignment PIN_33 -to hsync_oc    ;# nHSync, drive '1' = line low
set_location_assignment PIN_39 -to vsync_oc    ;# nVSync, drive '1' = line low

# ---------------------------------------------------------------
# SDRAM - 16 MB, 4 banks x 4096 rows x 512 cols x 16 bit (128 Mbit)
# A0..A11 only (12 row bits). reference/C1_extender_schem.pdf: U2 is a
# Samsung K4S281632-UC60 ("128MBit SD-Ram ... 166 MHz type"); CKE is tied
# to V33 and nCS to ground (with NC1/pin 36, "grounded for 256MBit
# compatibility"), so neither has an FPGA pin.
# ---------------------------------------------------------------
set_location_assignment PIN_99  -to ram_clk
set_location_assignment PIN_32  -to ram_ras_n
set_location_assignment PIN_144 -to ram_cas_n
set_location_assignment PIN_143 -to ram_we_n
set_location_assignment PIN_31  -to ram_ba_0
set_location_assignment PIN_30  -to ram_ba_1
set_location_assignment PIN_142 -to ram_ldqm
set_location_assignment PIN_98  -to ram_udqm

set_location_assignment PIN_8   -to ram_addr[0]
set_location_assignment PIN_7   -to ram_addr[1]
set_location_assignment PIN_6   -to ram_addr[2]
set_location_assignment PIN_4   -to ram_addr[3]
set_location_assignment PIN_119 -to ram_addr[4]
set_location_assignment PIN_114 -to ram_addr[5]
set_location_assignment PIN_112 -to ram_addr[6]
set_location_assignment PIN_110 -to ram_addr[7]
set_location_assignment PIN_103 -to ram_addr[8]
set_location_assignment PIN_105 -to ram_addr[9]
set_location_assignment PIN_28  -to ram_addr[10]
set_location_assignment PIN_100 -to ram_addr[11]

set_location_assignment PIN_121 -to ram_data[0]
set_location_assignment PIN_125 -to ram_data[1]
set_location_assignment PIN_132 -to ram_data[2]
set_location_assignment PIN_133 -to ram_data[3]
set_location_assignment PIN_135 -to ram_data[4]
set_location_assignment PIN_136 -to ram_data[5]
set_location_assignment PIN_137 -to ram_data[6]
set_location_assignment PIN_141 -to ram_data[7]
set_location_assignment PIN_87  -to ram_data[8]
set_location_assignment PIN_106 -to ram_data[9]
set_location_assignment PIN_104 -to ram_data[10]
set_location_assignment PIN_101 -to ram_data[11]
set_location_assignment PIN_111 -to ram_data[12]
set_location_assignment PIN_113 -to ram_data[13]
set_location_assignment PIN_115 -to ram_data[14]
set_location_assignment PIN_120 -to ram_data[15]

# ---------------------------------------------------------------
# "vid" bus - the 16 lines to the 1k30. In bypass mode these carry
# RGB from the 1k30; once the extender is loaded they are the only
# general-purpose link to the rest of the C-One, and therefore the
# channel for keyboard, mouse, joysticks and CF block traffic.
# Port names follow cone_mm_link (Minimig V2.01 link); vid index and
# pin from the manual's table; every location and direction is the
# one reference/C1_extender.pin uses (Minimig names in brackets).
# Input-only locations (vid[3:0], vid[13:11]) are confirmed by the
# Quartus 13.1 EP3C25E144 device database (fitter error 169009 for
# any other direction).
# ---------------------------------------------------------------
set_location_assignment PIN_91 -to vid_ide_in[0]    ;# vid[0]  IN only [addbi[0]]
set_location_assignment PIN_90 -to vid_ide_in[1]    ;# vid[1]  IN only [addbi[1]]
set_location_assignment PIN_89 -to vid_ide_in[2]    ;# vid[2]  IN only [addbi[2]]
set_location_assignment PIN_88 -to vid_ide_in[3]    ;# vid[3]  IN only [addbi[3]]
set_location_assignment PIN_79 -to vid_ide_out[0]   ;# vid[4]  [addbo[0]]
set_location_assignment PIN_76 -to vid_ide_out[1]   ;# vid[5]  [addbo[1]]
set_location_assignment PIN_71 -to vid_ide_out[2]   ;# vid[6]  [addbo[2]]
set_location_assignment PIN_68 -to vid_ide_out[3]   ;# vid[7]  [addbo[3]]
set_location_assignment PIN_66 -to vid_ide_out[4]   ;# vid[8]  [addbo[4]]
set_location_assignment PIN_60 -to vid_ide_out[5]   ;# vid[9]  [addbo[5]]
set_location_assignment PIN_58 -to vid_spare_out    ;# vid[10] [addbo[6]]
set_location_assignment PIN_54 -to vid_spare_in[0]  ;# vid[11] IN only [sysclk]
set_location_assignment PIN_53 -to vid_spare_in[1]  ;# vid[12] IN only [addbi[4]]
set_location_assignment PIN_52 -to vid_ser_in       ;# vid[13] IN only [addbi[5]]
set_location_assignment PIN_46 -to vid_ser_out      ;# vid[14] [addbo[7]]
set_location_assignment PIN_43 -to vid_ioclk        ;# vid[15] [addbo[8]]

# Link data lines are registered in their I/O elements so they share one
# clock-to-pin delay against vid_ioclk (constraints.sdc).
set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to vid_ide_out[*]
set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to vid_ser_out
set_instance_assignment -name FAST_INPUT_REGISTER ON -to vid_ide_in[*]
set_instance_assignment -name FAST_INPUT_REGISTER ON -to vid_ser_in

# ---------------------------------------------------------------
# mdb[7:0] - the board-wide 8-bit data bus (SID, cartridge, SRAM,
# CPLDs). Slow (<=8-10 MHz) and owned by the 1k30/1k100 at run time.
# mdb[3:0] sit on CLK0..CLK3 (pins 25,24,23,22); they and mdb[7:5]
# (pins 127..129) are input-only locations (Quartus device database),
# so the port is an input. reference/C1_extender.pin uses the same
# names and locations, all as inputs.
# ---------------------------------------------------------------
set_location_assignment PIN_25  -to mdb[0]    ;# IN only (CLK0)
set_location_assignment PIN_24  -to mdb[1]    ;# IN only (CLK1)
set_location_assignment PIN_23  -to mdb[2]    ;# IN only (CLK2)
set_location_assignment PIN_22  -to mdb[3]    ;# IN only (CLK3)
set_location_assignment PIN_13  -to mdb[4]
set_location_assignment PIN_127 -to mdb[5]
set_location_assignment PIN_128 -to mdb[6]
set_location_assignment PIN_129 -to mdb[7]

# ---------------------------------------------------------------
# Audio: not in the manual's table. Locations from
# reference/C1_extender.pin (sigma1 PIN_10, sigma2 PIN_11, outputs,
# 3.3-V LVTTL, bank 1). reference/C1_extender_schem.pdf: sigma1/sigma2
# are the "sigma-delta converters" Audio1/Audio2 (4n7 to ground, 10k and
# 1uF in series) to the geek port's SID1_exaudio / SID2_exaudio, i.e.
# the C-One's two SID external-audio inputs; their stereo placement is
# set by the main board.
# ---------------------------------------------------------------
set_location_assignment PIN_10 -to sigma_l     ;# [sigma1]
set_location_assignment PIN_11 -to sigma_r     ;# [sigma2]

# I/O standard: the whole bank set is 3.3 V LVTTL on the extender.
set_global_assignment -name STRATIX_DEVICE_IO_STANDARD "3.3-V LVTTL"
