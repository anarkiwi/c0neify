# Programming the C-One

What each programmable part of the C-One does, how its images are built
and loaded, and which part reaches which connector. The primary reference
is Peter Wendrich's *C-One core development* manual
(`reference/Cone_core_development.pdf`, cited as M§); this page adds what
was verified against the schematic, the pin files and working sources,
and corrects the manual where they disagree.

Citations: `sch:pN` = `reference/C1schematics.pdf` page N,
`A1k30.pin`/`A1k100.pin`/`C1_extender.pin` in `reference/`, archives by
file name (see [Reference archives](#reference-archives)).

## Parts

| Part | Device | Role | Toolchain | Image |
|---|---|---|---|---|
| Extender | Cyclone III EP3C25E144C8 | large cores; SDRAM, VGA, two sigma-delta audio pins, crystals 14.31818 / 28.37516 MHz | Quartus II 13.1 (`scripts/install_quartus.sh`) | `extender.rbf` |
| 1k100 | ACEX EP1K100QC208-3 | cartridge port, CPU slot (65816 + 128 KB SRAM), DIMM, PCI, joysticks and IEC via the 7064 CPLD (M§4.1) | Quartus II 9.0 under Wine (`scripts/build_acex.sh`) | `support.rbf`, `target.rbf` (166,965 bytes) |
| 1k30 | ACEX EP1K30QC208-3 | IDE/CF, SIMM, PS/2, VGA in bypass mode, the SID bus and its 1 MHz clock, the 16-line vid bus to the extender | same | `support.bin` (59,215 bytes) |
| 7064 CPLD | MAX 7064 | joystick shift register, printer port, IEC, status register (nCONFIG of the 1k30, 65816 reset) | fixed | – |
| 3032 CPLD | MAX 3032 (instant-on board) | power-up configuration from flash, flash address / 1k30 CONF_DONE (M§5) | fixed | – |

## Loading (NewBoot V2.01)

NewBoot runs on the 1k30 and loads one directory of the CF card
(`c1dcores/<core>/`, layout in [hardware.md](hardware.md)). Order (M§4.3):

1. `extender.rbf` into the extender. Without it the extender stays in
   bypass mode and forwards the 1k30's video (the card root's
   `extender.rbf` is that bypass core).
2. `support.rbf` into the 1k100.
3. `support.bin` into the first half of the SRAM, through the core in the
   1k100, which must implement the loader.
4. `target.rbf`, if present, into the 1k100. The SRAM keeps its contents.
5. The 1k100 core (`support.rbf` or `target.rbf`) reconfigures the 1k30
   from SRAM. The 1k30 signals that the SRAM is filled by a rising edge on
   gb[6]; wait for it.

Consequences for a design:

* The extender starts first and the 1k30 last, so every multi-FPGA design
  needs a readiness check before it trusts the other side
  (`cone_sd_ata` waits for the link's sync lock, [minimig_link.md](minimig_link.md)).
* Two 1k100 conventions exist:
  * one `support.rbf` that both loads SRAM and reconfigures the 1k30
    (Minimig V2.01, sha256 `c1326c46…e325`);
  * a standard memory loader as `support.rbf` plus a `target.rbf` that
    reconfigures the 1k30 and then runs the 1k100 core (FPGA-64 0.29,
    loader sha256 `f257200d…c65a`, named in M§4.3 and in the
    `reconfig1k30_example` readme as the loader to reuse).

### Reconfiguring the 1k30 from the 1k100

M§4.4 and M§5, implemented in `reconfig1k30_example.zip`
(`third_party/reconfig1k30_example/rtl/cone_reconfig1k30.vhd`, LGPL-3,
about 200 LEs):

1. cselect `0110b`, A3 A2 = `00`: clear the 3032's flash address, which
   drives the 1k30's CONF_DONE low.
2. cselect `1000b`, wr low, mdb bit 0 = 0, then 1: pulse the 1k30's
   nCONFIG through the 7064 status register. M§7.4's table gives `1001b`
   for this register; M§7.2's table and the working example use `1000b`.
3. Wait at least 40 µs.
4. For each of the 59,215 bytes: read the SRAM (`ramcs` low, wr high,
   address on a[16:0]), then write the byte to the 1k30 (mdb, wr low,
   taken on wr's rising edge).
5. Increment and shift the 3032's flash address 16 times
   (cselect `0110b`, A3 A2 = `10`, then `01`) to raise CONF_DONE.

The 3032 is clocked at 2 MHz: each select is held at least 1 µs and A3/A2
stay stable 500 ns after deselecting (M§5).

## Buses between the parts

| Bus | Between | Notes |
|---|---|---|
| vid[15:0] | extender, 1k30 | the 1k30's video pins (1k30 pins 170–193, `A1k30.pin`); extender vid[3:0] and vid[13:11] are input-only (`C1_extender.pin`, Quartus device data). Protocol in use: Minimig's link ([minimig_link.md](minimig_link.md)) |
| gb[7:0] | 1k30, 1k100 | GBridge (`Gbridge.tdf`): video from the 1k100 at 16 bit/25 MHz (`GBmode=0`) or 12 bit/33 MHz (`GBmode=1`) (M§9.4), plus a serial stream with `iauda`, `ioshift` and the SID clock on gb[5] (`Gbridge.tdf:124-135`). Redefinable when both ACEX images are custom |
| mdb[7:0] | all three FPGAs, SIDs, SRAM, CPLDs, cartridge port | slow: 8–10 MHz at most (M§3). On the extender only mdb[4] (PIN_13) can drive; mdb[3:0] (dedicated clock inputs) and mdb[7:5] are input-only (Quartus device data, `Board/cone_ext/cone_ext_pins.tcl`) |
| a[4:0] | 1k30, 1k100, SIDs | the 1k30 drives only a[4:0] (pins 25, 163, 167–169); a[16:0] is on the 1k100 (`A1k30.pin`, `A1k100.pin`) |
| cselect[3:0] | 1k30, 1k100 (both drive it) | decoded by a 74LS138 (sch:p9, U10) when cselect[3] = 0 and by the 7064 when cselect[3] = 1 (table below) |

## Who reaches which connector

| Connector | Reachable from | How | Source |
|---|---|---|---|
| VGA | extender directly; 1k30 in bypass mode; 1k100 via GBridge | extender hsync/vsync are open-collector, active by driving the pin high; NewBoot tri-states the 1k30's syncs when it loads an extender core | M§9.2–9.4 |
| PS/2 keyboard, mouse | 1k30 (pins 203/202, 200/199) and 1k100 (70/69, 68/67) | extender only through the 1k30 (Minimig's link carries both). Clock and data are swapped in the schematic | M§10 |
| Joysticks | 1k100 (via the 7064's serial stream on ioshift, 1k100 pin 174, one bit per pclk) | 16-bit frame with a 0 sync bit; extender gets them through GBridge gb[5] → 1k30 → link | M§7.3, `Gbridge.tdf:124-135` |
| SID 1, SID 2 | 1k30 alone, or the 1k100 if the 1k30 supplies the clock | 74LS138 Y6/Y7 (cselect `0011b`/`0111b`) to SID nCS; wr to nWR, mdb to D0–7, a[4:0] to A0–4, nreset to nRES; both φ2 pins on net `1mhz`, driven by 1k30 pin 150 | sch:p1, sch:p9, `A1k30.pin`, M§11 |
| CF / IDE | 1k30 | extender through Minimig's IDE tunnel (`cone_sd_ata`) | `third_party/C1minimigV201_source/1k30/acex.vhd` |
| IEC | 1k100 | 7064 register cselect `1011b`, bits 3/4/5 = ATN/CLK/DATA (1 = pull low), written on pclk's falling edge. pclk exists only on 1k100 pin 168. ATN is output-only and SRQ-IN is unreadable, so drive emulation on this port is impossible | M§7.1, M§7.6 |
| Cartridge port | 1k100 (a[15:0]); the 1k30 can raise ROML/ROMH/IO1/IO2 but has only a[4:0] | 74LS138 Y0/Y1/Y5/Y4 (ROML/ROMH/IO1/IO2); BA needs the BA mod (R72 removed, wire to PCI data bit 1) | sch:p9, M§12.1 |
| Printer port | 1k100 | 7064 `1001b`/`1010b`, strobe in the IEC register | M§7.2, M§7.5 |

### cselect decode

| cselect | Decoded by | Selects |
|---|---|---|
| `0000b` | 74LS138 Y0 | ROML |
| `0001b` | Y4 | IO2 |
| `0010b` | Y2 | clock port cs (clk1cs) |
| `0011b` | Y6 | SID 1 |
| `0100b` | Y1 | ROMH |
| `0101b` | Y5 | IO1 |
| `0110b` | Y3 | 3032 CPLD (clk2cs, also `video_cs`) |
| `0111b` | Y7 | SID 2 |
| `1000b` | 7064 | status register (1k30 nCONFIG, IRQ, 65816 reset) |
| `1001b` / `1010b` | 7064 | printer data / direction |
| `1011b` | 7064 | IEC |
| `1100b`–`1110b` | 7064 | PCI grant control |
| `1111b` | – | nothing (idle) |

The 74LS138 has cselect[3] on G2A and G1 tied high (sch:p9), so its
selects are combinational and need no pclk; only the 7064 rows need
pclk, hence the 1k100. The Y outputs are the schematic's net names; they
agree with M§7.2's table only with A = cselect[2], B = cselect[1],
C = cselect[0], which is the reversed bit order M§7.2 warns about.

### SID access timing (M§11)

Address, data and wr stable at least 45 ns before cselect selects the
SID; cselect held at least 300 ns while `1mhz` is high; address, data
and wr held 20 ns after deselecting. `1mhz` should be close to 50 % duty.
`fpga64_cone.vhd` (`ninevoltz/c64-fpga`, FPGA-64 0.18) shows a working
sequence from the 1k100: SID writes are queued and replayed in a fixed
slot of each C64 cycle, with the SID clock raised about 120 ns early to
cover the 20–80 ns through GBridge (`fpga64_cone.vhd:449-462,556-584`).

## Clocks

| Clock | Where | Source |
|---|---|---|
| sysclk 101 MHz | 1k30 pin 79, 1k100 pin 79 | M§13 |
| pclk (7064 and joystick stream) | 1k100 pin 168 only | M§7, M§13 |
| 2mhz (fixed, from sysclk) | 1k30 pin 184 | M§13, `A1k30.pin` |
| 1mhz (SID φ2) | 1k30 pin 150 out | sch:p1, `A1k30.pin` |
| cpuclk (cartridge, 65816) | 1k30 183, 1k100 163 | M§13 |
| clk14 14.31818 MHz, clk28 28.37516 MHz | extender PIN_55, PIN_126 (ordinary I/O, not dedicated clock pins) | `C1_extender.pin`, `Board/cone_ext/cone_ext_pins.tcl` |

## Development paths

### Extender core, stock ACEX images (in use)

DeMiSTify cores with Minimig V2.01's `support.rbf`/`support.bin`
unchanged: PS/2, joysticks (fire 1 only), CF as an SD card, VGA, audio on
the extender's sigma pins. `scripts/build_core.sh`; card steps in
[hardware.md](hardware.md). No SID, IEC or cartridge access.

### Extender core plus a custom 1k30 (adds the real SIDs)

1. Take `1k30/` from `third_party/C1minimigV201_source/` plus
   `gdemux.tdf` from `C1minimigV201_source.zip` and rebuild it with
   `scripts/build_acex.sh`; the result must be byte-identical to
   `support.bin` before any change ([acex_toolchain.md](acex_toolchain.md)).
2. Add a SID write path: the extender sends register writes over a spare
   link line or slot (vid[10] is unused by Minimig's link), the 1k30
   replays them with the M§11 timing, generating `1mhz` itself.
3. Ship the result as `support.bin` with Minimig's `support.rbf`, which
   reconfigures the 1k30 from SRAM.

### Custom 1k100 as well (adds IEC, cartridge, printer)

1. Reuse FPGA-64's `support.rbf` as the SRAM loader.
2. Write a `target.rbf` from `cone_reconfig1k30` (reconfiguration),
   `Gbridge.tdf` (gb bus and joystick relay), and the IEC/cartridge
   logic; drive pclk for the 7064. Starting points for a 1k100 top level
   with pins: `VC20_V12.zip` (`source/a1k100.qsf`, GBridge, ioshift),
   `Bigpicview.zip`, `Picview.zip`.
3. Keep the 1k100's pins tri-stated until gb[6] rises, then reconfigure
   the 1k30 (M§4.3).

## Hardware bring-up order

Each step needs only what the previous one proved.

| Step | Card contents | Proves | Expected |
|---|---|---|---|
| 1 | NewBoot V2.01 as shipped | board, CF, bypass video | NewBoot menu on VGA |
| 2 | `third_party/cone_800x600_test_v3/800x600/` as a core directory (add any `select.raw`) | extender configuration, clk28 + PLL, VGA DAC, open-collector syncs | 800×600 colour bars |
| 3 | Minimig V2.01 (`C1minimigV201_build.zip`) | the prebuilt `support.rbf`/`support.bin` and the link on this board | Minimig's on-screen menu, keyboard works |
| 4 | BBC cone_ext (`scripts/build_core.sh`) | `cone_mm_link`, `cone_sd_ata`, SDRAM, DeMiSTify firmware | BBC boots `BBC.ROM` from CF; keyboard, joystick fire |
| 5 | rebuilt Minimig 1k30 as `support.bin` | the ACEX toolchain on hardware | identical behaviour to step 3 |

If step 4 fails where step 3 works, the link timing on this board is the
first suspect (`BLOCKED.md` #3).

## Reference archives

All in `reference/` (gitignored; `scripts/check_assets.sh`). Commodore
ROMs inside some archives must never be committed. The files this repo
uses from the GPL/LGPL archives are vendored in
[third_party/](../third_party/README.md).

| Archive | Contents | Licence |
|---|---|---|
| `Cone_core_development.pdf` | the manual | – |
| `C1schematics.pdf`, `C1_extender_schem.pdf` | main board and extender schematics | – |
| `A1k30.pin`, `A1k100.pin`, `C1_extender.pin` | fitted pin reports | – |
| `C1minimigV201_source.zip` | Minimig extender, 1k30 (`1k30/`, builds to `support.bin`); partly vendored | GPL-3, TG68 LGPL; `1k30/gdemux.tdf` all rights reserved |
| `C1minimigV201_build.zip` | Minimig V2.01 card files | GPL-3 |
| `Minimig_source211108.zip` | Minimig 2008 source (extender, 1k30, NTSC) | GPL-3 |
| `Snapshot_ver1.26.zip`, `Symb_cpc_source.zip` | Minimig snapshot, SymbOS CPC: extender + 1k30 projects | GPL |
| `Gbridge.tdf` | GBridge, 1k100 side | BSD-style (Gubener) |
| `reconfig1k30_example.zip` | 1k100 reconfiguration of the 1k30; vendored | LGPL-3 (Wendrich) |
| `cone_800x600_test_v3.zip` | extender VGA test, source and `extender.rbf`; vendored | LGPL-3 (Wendrich) |
| `VC20_V12.zip`, `Bigpicview.zip`, `Picview.zip`, `Pong_chapter1.zip` | 1k100 projects with GBridge or gbmux | per file |
| `fpga64_029.zip` | FPGA-64 0.29 card files (`support.rbf`, `target.rbf`, loader `boot.bin`, Commodore ROMs); no source | – |
| `NewbootV201.zip` | NewBoot V2.01 card | – |
| github.com/ninevoltz/c64-fpga | FPGA-64 0.18 sources incl. `fpga64_cone.vhd` (stale against the shared files; does not elaborate as published) | none stated |
