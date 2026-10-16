# vid-bus protocol: ours or Minimig's

**Decision: option B** (2026-10-16). The prebuilt Minimig V2.01
1k100/1k30 images in `reference/C1minimigV201_build.zip` (`support.rbf`,
`support.bin`; there is no `target.rbf`) can be reused unchanged only if
the extender speaks Minimig's link protocol, so the extender adopts it.
Storage keeps DeMiSTify's firmware unchanged: an SD-over-SPI to ATA
bridge on the extender answers the firmware's SD commands with ATA PIO
transfers through the IDE tunnel. **Implemented** as
`Board/cone_ext/cone_mm_link.vhd` and `Board/cone_ext/cone_sd_ata.vhd`
([minimig_link.md](minimig_link.md)); `cone_io` and its 1k30 slave are
kept in `fallback/`.

Citations: `src:` = `reference/C1minimigV201_source.zip`, `build:` =
`reference/C1minimigV201_build.zip`, `M:` = `reference/Cone_core_development.pdf`
(text line numbers from `pdftotext`).

## Minimig's link, as implemented

| vid | extender pin / Minimig name | dir at extender | 1k30 pin / name | use |
|---|---|---|---|---|
| 15 | 43 addbo[8] = IOclk | out | 170 addbi[8] | link clock, the only clock of the 1k30's acex block |
| 14 | 46 addbo[7] | out | 172 addbi[7] | 8-slot serial line, extender -> 1k30 |
| 13 | 52 addbi[5] | in | 173 addbo[5] | 8-slot serial line, 1k30 -> extender |
| 12 | 53 addbi[4] | in | 174 addbo[4] | constant '1' |
| 11 | 54 sysclk | in | 175 addo_clk | the 1k30's 101 MHz clock; unused by Minimig |
| 10 | 58 addbo[6] | out | 176 addbi[6] | unused |
| 9..4 | 60..79 addbo[5:0] | out | 177..189 addbi[5:0] | IDE command / address / write data |
| 3..0 | 88..91 addbi[3:0] | in | 190..193 addbo[3:0] | IDE read data nibbles |

Sources: `src:Extender.qsf:110-123`, `src:1k30/ehle.qsf:143-158`, M:1088-1103.
The physical lines and their directions are the same as ours.

* **Clock**: the extender is the master. IOclk = extender sysclk / 2
  (`src:cfide.vhd:524`), sysclk = 4 x clk28 = 113.5 MHz
  (`src:palclk.tdf:53,60`), so IOclk = 56.75 MHz. Outputs change on the
  sysclk falling edge while IOclk is high (`src:cfide.vhd:517-520`); both
  ends sample on the IOclk rising edge. No strobes or valid flags: both
  ends count cycles, with a fixed two-IOclk round trip.
* **IDE/CF tunnel** (`src:cfide.vhd:515-633`, `src:1k30/acex.vhd:84-161`):
  idle "111111"; command "010000" read / "100000" write; one address cycle
  (bits 2..0 register, bit 4 CS0, bit 5 CS1); write data in 6+6+4 bits;
  "000000" closes after a wait; reads return 16 bits as four nibbles on
  vid[3:0], low nibble first.
* **Serial slots** (8 per frame, one per IOclk): 1k30 -> extender sync toggle, kb_data,
  kb_clk, ms_data, ms_clk, RxD, C2MHz, ioshift (`src:1k30/acex.vhd:174-195`);
  extender -> 1k30 sync echo, kb_data, kb_clk, ms_data, ms_clk, TxD, lrclk,
  audio bit (`src:cyclone.vhd:112-121`). The extender aligns to the
  toggling sync bit and sends all '1' until locked
  (`src:cyclone.vhd:150-163`).
* **Joysticks**: the 7064 CPLD's ioshift stream goes 1k100 -> gb[5] -> 1k30
  (`reference/Gbridge.tdf:124-134`, `src:1k30/gdemux.tdf:127-163`) -> serial
  slots 6/7; the extender rebuilds both ports (`src:cyclone.vhd:206-222`).
* **Audio**: serialised left/right (24 C2MHz cycles each) over slots 6/7 to
  the 1k30's audio DAC (`src:cyclone.vhd:171-201`, `src:1k30/acex.vhd:202-208`).
  Minimig ties the extender's sigma1/sigma2 high.
* `build:support.bin` is a later build of `src:1k30` (same size as
  `src:1k30/ehle.rbf`, 59215 bytes, different contents, dated after the
  readme's 1k30 fix). `build:support.rbf` (1k100) has no source in either
  archive.

## Option A: keep our protocol (now `fallback/`)

`cone_io` + `cone_1k30_mux_slave`, documented in [vidbus.md](vidbus.md).

* For: proven in simulation, including a 188-case timing sweep; DeMiSTify's
  `substitute_mcu` and SD/SPI firmware are used unchanged
  (`SPI_EXTERNALCLK`), so the board patch stays small and upstreamable.
* Against:
  * Needs a new 1k30 image (mux slave + gb relay) and a new 1k100 support
    core (CPLD joystick reader, SPI relay, 1k30 reconfiguration). ACEX 1K
    needs Quartus II 9.0 Web Edition under Wine
    ([acex_toolchain.md](acex_toolchain.md)), and there is no 1k100 source
    to start from.
  * SD storage needs a socket wired to the 1k100's PCI header, which is a
    hardware addition. The alternative, CF through extra mux slots, needs
    the same firmware change as option B.
  * Real round-trip delays are unmeasured (BLOCKED.md #3).

## Option B: adopt Minimig's link

New extender module (for example `cone_minimig_io`) implementing
`cfide`/`cyclone`'s link side, with prebuilt `support.rbf` and
`support.bin` shipped unchanged.

* For:
  * No ACEX toolchain and no 1k100 work.
  * Uses the stock C-One CF slot, PS/2 keyboard and mouse, both joysticks,
    and the 1k30's audio DAC.
  * The link already runs on real hardware at 56.75 MHz IOclk. Our PLL's
    100.23 MHz c0 gives 50.1 MHz IOclk, which is slower, so the round trip
    has more margin.
  * The Minimig sources are GPL-3-or-later, compatible with this repo and
    DeMiSTify.
* Against:
  * Storage is IDE/CF, not SD/SPI. DeMiSTify's firmware needs an ATA PIO
    block driver in place of `spi_sd.c`, and `substitute_mcu` needs a
    host-side peripheral to drive the IDE tunnel. That change is to
    DeMiSTify's firmware and controller, not just a board directory, so
    it is harder to upstream. It could be a build-time option.
  * The extender must reproduce Minimig's cycle counts exactly: two-cycle
    latency, close and wait counts, slot order, and sync lock. Simulating
    it against the real `acex.vhd` is possible only while
    `reference/C1minimigV201_source.zip` is present (asset-gated sim).
  * The audio path moves from the guest's sigma-delta pins to the
    serialised DAC stream (`AUDIO_L/R` would need the guest's parallel
    `DAC_L/R` outputs, which BBC has).
  * `vid[11]` stays unused, and the joystick reconstruction is clocked by
    the relayed 2 MHz.

## Recommendation

Option B. Option A cannot be completed with the assets available: there is
no ACEX toolchain, no 1k100 source, and SD would need a hardware change.
Option B's extra work is all on the extender and firmware side, where the
toolchain, sources and simulation already exist. Most of this repo still
applies under B: the pins, PLL, SDRAM, template, CI and asset handling.
`cone_io`/`cone_1k30_mux_slave` and the vid-bus testbench would be kept
as the fallback, or retired.

As implemented, the storage drawback above did not apply: the SD-to-ATA
bridge in the extender keeps DeMiSTify's firmware and `substitute_mcu`
unchanged, and the guest's audio stays on the sigma-delta pins.
