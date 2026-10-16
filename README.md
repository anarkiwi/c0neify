# DeMiSTify target: C-One FPGA Extender (`cone_ext`)

Draft board definition for running DeMiSTified MiST cores on the
Cyclone III EP3C25E144C8 on the C-One's FPGA Extender card.

Everything here is derived from published documents, not from a running
board. Treat it as a starting point that still needs to be verified
against `C1_extender.pin` and the extender schematic (both on the iComp
wiki C-One page), neither of which could be fetched automatically.

## Layout (drop into a DeMiSTify checkout)

```
Board/cone_ext/
  board.mk               Quartus Cyclone III toolchain
  cone_ext_defs.tcl      have_sdram / base_clock / fpga
  cone_ext_opts.tcl      device + fitter settings (from MiST/Chameleon)
  cone_ext_pins.tcl      pin assignments (from Wendrich manual, sec. 13)
  cone_ext_support.tcl   SDC + SDRAM macros + extra VHDL files
  constraints.sdc        clocks and pin groups
  Board_Config.vhd       SDRAM geometry, VGA depth
  hostclocks.vhd         altpll: clk14 -> 100 / 50 / 27 MHz
  gen_reset.vhd          copied from Board/chameleon64
  cone_io.vhd            extender side of the vid-bus mux
templates/cone_ext/
  cone_ext_top.vhd       toplevel template (guest + substitute_mcu + cone_io)
  top.qip
cone_1k30/
  cone_1k30_mux_slave.vhd  1k30 side of the vid-bus mux (sketch)
```

Then add `cone_ext` to `BOARDS` in `site.mk` of a core that already has
a Chameleon port, e.g. `robinsonb5/BBC_DemiSTify`, and copy
`templates/cone_ext/` into the core's `cone_ext/` directory.

## Pin budget - the hard constraint

The EP3C25E144 has 82 user I/O + 4 dedicated clock inputs. The manual's
pin table accounts for all of them:

| Group | Pins | Notes |
|---|---|---|
| SDRAM | 40 | 12 addr, 16 data, clk, ras, cas, we, 2 ba, 2 dqm. No nCS/CKE pins listed -> assumed hardwired. |
| VGA | 18 | red 5, grn 6, blu 5, nHSync, nVSync (sync is open-collector: drive pin '1' to pull low) |
| vid bus | 16 | the only link to the 1k30. **vid[3:0] = pins 91..88 = CLK4..7, input-only; vid[13:11] input-only** |
| mdb | 8 | board data bus, slow, owned by 1k30/1k100. mdb[3:0] = pins 25..22 = CLK0..3, input-only |
| clocks | 2 | 14.31818 MHz (pin 55), 28.37516 MHz (pin 126) |

Consequences:

* There are **no spare extender pins** for an SD socket. Storage must be
  tunnelled through the 1k30 (over the vid bus) or come from a socket
  wired to the 1k100's unused PCI connector (32 x 5 V-tolerant I/O, per
  the manual) and relayed 1k100 -> gb[] -> 1k30 -> vid -> extender.
* The audio DAC pins on the extender are not in the manual's table.
  Get them from `C1_extender.pin` and fill in `sigma_l` / `sigma_r`.
* Of the 16 vid lines only 9 are bidirectional from the extender side,
  so the link is 4 bits out + 4 bits in + 4 select + clock, which is
  exactly the shape of the Chameleon's CPLD mux. `cone_io.vhd` copies
  that scheme so `substitute_mcu` can be used unchanged with
  `SPI_EXTERNALCLK => true` and the req/ack handshake.

## SDRAM

16 MB: 128 Mbit x16, 4 banks x 4096 rows x 512 columns -> 12 row bits,
9 column bits. `SDRAM_ROWBITS=12`, `Board_SDRAM_RowBits = 12`. Guest
cores that bring their own SDRAM controller usually assume 13 row bits /
32 MB; tie `SDRAM_A[12]` open and cap any memory-size options at 16 MB.
Timings in `cone_ext_support.tcl` are generic -7 values; check the part
number on your extender.

## Clocks

`hostclocks.vhd` runs the PLL from clk14 (VCO 1002.27 MHz):
100.23 MHz (mux + SDRAM), 50.11 MHz (controller), 27.09 MHz for the
guest's `CLOCK_27` (+0.33 %). If a core is sensitive to that, set
`base_clock 28` in `cone_ext_defs.tcl` and regenerate the guest PLL for
28.37516 MHz instead, as the Chameleon ports do for 8 MHz.

## What the other two FPGAs must do

NewBoot's load order is: extender.rbf -> support.rbf (1k100) ->
support.bin (1k30 image into SRAM) -> target.rbf (1k100, reconfigures
the 1k30). So a DeMiSTified core ships as a NewBoot directory:

```
c1dcores/<core>/
  select.raw       icon
  extender.rbf     the DeMiSTified MiST core
  support.rbf      1k100: SRAM loader (copy from VC20/FPGA-64 archives)
  support.bin      1k30 image = cone_1k30_mux_slave + PS/2 + gb relay
  target.rbf       1k100: joystick reader (ioshift/pclk), SD relay, 1k30 reconfig logic
```

* **1k30** owns the PS/2 pins (203/202/200/199) and the vid bus. It
  needs only the mux slave plus a gb[] relay. ~200 LEs.
* **1k100** owns `ioshift`/`pclk` (joysticks via the 7064 CPLD), the
  SRAM, and the ~200-LE 1k30-reconfigure block from the manual. If the
  SD socket lives on the PCI header it also relays SPI. The Minimig
  V2.01 source archive already contains working versions of most of
  this and is the reference to crib from.

## Storage options, in order of effort

1. SD socket on the 1k100 PCI header, SPI relayed over gb[] and the
   vid bus. No firmware changes; `cone_io`'s SPI slot carries it.
   Expect ~5 MHz SCK.
2. CF card via the 1k30's existing mass-storage pins: replace the SPI/SD
   block layer in DeMiSTify's firmware (`firmware/`) with an ATA PIO
   driver whose register reads/writes go over additional mux slots.
   Keeps the machine stock; more work on both sides.

## Open items before first synthesis

- [ ] Diff `cone_ext_pins.tcl` against `C1_extender.pin`
- [ ] Audio DAC pins, geek-port lines
- [ ] Confirm SDRAM part and whether nCS/CKE are really hardwired
- [ ] Confirm which vid pins are input-only (manual lists 0-3, 11-13)
- [ ] Fill in the joystick mapping in `cone_ext_top.vhd` (see
      `chameleon_mergeinputs.vhd` for the button constants)
- [ ] Write the 1k100 support core

## Sources

- Peter Wendrich, *C-One core development*, syntiac.com (pin table, SDRAM, VGA, PS/2, reconfiguration sequence)
- iComp wiki, C-One page (extender schematic, .pin files, NewBoot layout, Minimig V2.01 source)
- robinsonb5/DeMiSTify: `Board/chameleon64`, `Board/mist`, `templates/chameleon64/chameleon64_top.vhd`, `controller/substitute_mcu.vhd`
- robinsonb5/chameleon-modules: `chameleon_io.vhd` (mux protocol this mirrors)
