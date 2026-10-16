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

The extender speaks Minimig V2.01's link over the vid lines
(`cone_mm_link.vhd`): IOclk out on vid[15], one serial line each way
(vid[14], vid[13]) for PS/2, TxD, joysticks and audio, six lines out
(vid[9:4]) and four in (vid[3:0]) for an IDE tunnel to the C-One's CF
slot. `cone_sd_ata.vhd` turns substitute_mcu's SD commands into ATA
transfers through that tunnel, so the firmware is unchanged. Protocol,
timing windows and simulation: [minimig_link.md](minimig_link.md). The
earlier mux protocol ([vidbus.md](vidbus.md)) is kept in `fallback/`;
[protocol_decision.md](protocol_decision.md) compares the two.

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
  support.rbf      1k100: Minimig V2.01's, unchanged
  support.bin      1k30: Minimig V2.01's, unchanged (1k30/acex.vhd + gdemux)
```

* **1k30** owns the PS/2 pins (203/202/200/199), the IDE/CF pins and the
  vid bus; Minimig's image bridges all three to the link.
* **1k100** owns `ioshift`/`pclk` (joysticks via the 7064 CPLD), the
  SRAM, and the 1k30-reconfigure block from the manual; Minimig's
  `support.rbf` relays the joystick stream to the 1k30 on gb[5].

## Storage

The C-One's CF slot, through the 1k30's IDE pins and the link's IDE
tunnel, with `cone_sd_ata` presenting it to the firmware as an SDHC card.
An SD socket would need a hardware addition (the 1k100 PCI header).
