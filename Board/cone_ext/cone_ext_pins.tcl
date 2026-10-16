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
# A0..A11 only (12 row bits). No nCS / CKE pins are listed in the
# manual; assume hardwired active, as on the Chameleon.
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
# channel for keyboard, mouse, joysticks and CF/SD block traffic.
#
# INPUT-ONLY on the extender: vid[3:0] (pins 91..88 are the
# EP3C25E144 CLK4..CLK7 dedicated clock inputs) and vid[13:11].
# Bidirectional: vid[10:4], vid[14], vid[15]  (9 lines).
# ---------------------------------------------------------------
set_location_assignment PIN_91 -to vid[0]     ;# IN only
set_location_assignment PIN_90 -to vid[1]     ;# IN only
set_location_assignment PIN_89 -to vid[2]     ;# IN only
set_location_assignment PIN_88 -to vid[3]     ;# IN only
set_location_assignment PIN_79 -to vid[4]
set_location_assignment PIN_76 -to vid[5]
set_location_assignment PIN_71 -to vid[6]
set_location_assignment PIN_68 -to vid[7]
set_location_assignment PIN_66 -to vid[8]
set_location_assignment PIN_60 -to vid[9]
set_location_assignment PIN_58 -to vid[10]
set_location_assignment PIN_54 -to vid[11]    ;# IN only
set_location_assignment PIN_53 -to vid[12]    ;# IN only
set_location_assignment PIN_52 -to vid[13]    ;# IN only
set_location_assignment PIN_46 -to vid[14]
set_location_assignment PIN_43 -to vid[15]

# ---------------------------------------------------------------
# mdb[7:0] - the board-wide 8-bit data bus (SID, cartridge, SRAM,
# CPLDs). Slow (<=8-10 MHz) and owned by the 1k30/1k100 at run time.
# mdb[3:0] sit on CLK0..CLK3 (pins 25,24,23,22) so are input-only
# on the extender. Keep tri-stated unless a core really needs it.
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
# NOT in the manual's table - take from C1_extender.pin / schematic:
#   * audio DAC pins on the extender (the board has its own converter)
#   * the "few global signals from the geek-port"
#   * any SDRAM nCS / CKE if they are not hardwired
# ---------------------------------------------------------------
# set_location_assignment PIN_?? -to sigma_l
# set_location_assignment PIN_?? -to sigma_r

# I/O standard: the whole bank set is 3.3 V LVTTL on the extender.
set_global_assignment -name STRATIX_DEVICE_IO_STANDARD "3.3-V LVTTL"
