# cone_ext architecture

Hardware facts here come from Peter Wendrich, *C-One core development*
(syntiac.com / iComp wiki), section 13 "Pins and Signals", cross-checked
against `reference/C1_extender.pin` (all locations match) and
`reference/C1_extender_schem.pdf`. Items marked **unverified** are tracked
in `BLOCKED.md`.

## Pin budget

`Board/cone_ext/cone_ext_pins.tcl` assigns 82 pins (Quartus reports 83
usable on the EP3C25E144 with this configuration):

| Group | Pins | Notes |
|---|---|---|
| clocks | 2 | 14.31818 MHz (pin 55), 28.37516 MHz (pin 126) |
| VGA | 18 | red 5, grn 6, blu 5, nHSync, nVSync (sync is open-collector: drive pin '1' to pull low) |
| SDRAM | 36 | 12 addr, 16 data, clk, ras, cas, we, 2 ba, 2 dqm. CKE tied to V33 and nCS to ground on the board (schematic) |
| vid bus | 16 | the only link to the 1k30. vid[3:0] = pins 91..88 = CLK4..7 and vid[13:11] are input-only (manual; Quartus device database) |
| mdb | 8 | board data bus, owned by 1k30/1k100. mdb[3:0] (pins 25..22) and mdb[7:5] (pins 127..129) are input-only locations, so the port is an input |
| audio | 2 | sigma1 PIN_10, sigma2 PIN_11 (pin file, schematic): sigma-delta outputs, RC-filtered to the geek port's SID1/SID2 external-audio inputs |

There are no spare extender pins for an SD socket, so storage is reached
through the 1k30 over the vid bus.

## vid bus

Of the 16 vid lines only 9 are bidirectional from the extender side, so
the link is 4 bits out + 4 bits in + 4 select + clock, the shape of the
Chameleon's CPLD mux. The Minimig V2.01 core uses the same lines with a
different protocol; [protocol_decision.md](protocol_decision.md) compares
the two. `cone_io.vhd` (extender) and
`cone_1k30/cone_1k30_mux_slave.vhd` (1k30) implement it so
`substitute_mcu` is used unchanged with `SPI_EXTERNALCLK => true`.
Protocol, slot map, timing windows and simulated rates: [vidbus.md](vidbus.md).

## SDRAM

16 MB: 128 Mbit x16, 4 banks x 4096 rows x 512 columns: 12 row bits,
9 column bits (`SDRAM_ROWBITS=12`, `Board_SDRAM_RowBits = 12`). Guest
cores usually assume 13 row bits / 32 MB; the template drops
`SDRAM_A[12]` and memory-size options must be capped at 16 MB. The fitted
part is a Samsung K4S281632-UC60 (schematic). The macros in
`cone_ext_support.tcl` follow the K4S281632F datasheet's -60 column: CL3
(tCK >= 6 ns, no CL2 rating), tRCD 18 ns, tRP 18 ns, tRC 60 ns, tRDL 2
CLK. Cores with their own controller set their own timing; the BBC
core uses CL2 (`BLOCKED.md`).

## Clocks

`hostclocks.vhd` runs the PLL from clk14 (VCO = 14.31818 x 70 =
1002.27 MHz): c0 = 100.23 MHz (vid mux, SDRAM), c1 = 50.11 MHz
(substitute_mcu), c2 = 27.09 MHz (guest `CLOCK_27`, +0.33 %).
`base_clock 27` in `cone_ext_defs.tcl` matches that. For a core sensitive
to +0.33 %, regenerate its PLL for the 28.37516 MHz crystal and set
`base_clock 28`, as the Chameleon ports do for 8 MHz.

## The other two FPGAs

NewBoot's load order is extender.rbf -> support.rbf (1k100) ->
support.bin (1k30 image into SRAM) -> target.rbf (1k100, reconfigures the
1k30). A DeMiSTified core therefore ships as (built by
`scripts/make_cfcard.sh`):

```
c1dcores/<core>/
  select.raw       icon
  extender.rbf     the DeMiSTified MiST core
  support.rbf      1k100: SRAM loader
  support.bin      1k30 image = cone_1k30_mux_slave + PS/2 + gb relay
  target.rbf       1k100: joystick reader (ioshift/pclk), SD relay, 1k30 reconfig logic
```

* **1k30** owns the PS/2 pins (203/202/200/199) and the vid bus. It needs
  the mux slave plus a gb[] relay.
* **1k100** owns `ioshift`/`pclk` (joysticks via the 7064 CPLD), the
  SRAM, and the 1k30-reconfigure block from the manual. If the SD socket
  is on the PCI header it also relays SPI. The Minimig V2.01 source is the
  reference implementation for this side.

## Storage options

1. SD socket on the 1k100 PCI header (32 x 5 V-tolerant I/O per the
   manual), SPI relayed 1k100 -> gb[] -> 1k30 -> vid -> extender. No
   firmware changes; `cone_io`'s SPI slot carries it.
2. CF card via the 1k30's mass-storage pins: replace DeMiSTify's SPI/SD
   block layer with an ATA PIO driver whose register accesses use further
   mux slots. Keeps the machine stock; more work on both sides.
