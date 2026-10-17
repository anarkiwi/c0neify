# Minimig link and SD-to-ATA bridge

The extender speaks the Minimig V2.01 C-One link
([protocol_decision.md](protocol_decision.md), option B), so NewBoot
loads Minimig's prebuilt `support.rbf` (1k100) and `support.bin` (1k30)
unchanged. Two board modules implement it:

* `Board/cone_ext/cone_mm_link.vhd`: the extender half of Minimig's
  `cfide.vhd` IDE tunnel and `cyclone.vhd` serial slots, with an IDE
  register port, PS/2, TxD, joysticks and the 1k30's audio DAC.
* `Board/cone_ext/cone_sd_ata.vhd`: an SD card in SPI mode, as far as
  DeMiSTify's `firmware/spi_sd.c` uses one, backed by ATA PIO transfers to
  the C-One's CF card through the link's IDE port.

`substitute_mcu` and its firmware are unchanged. Citations: `src:` =
`third_party/C1minimigV201_source/` (`gdemux.tdf` only in
`reference/C1minimigV201_source.zip`), `spi_sd.c` =
`DeMiSTify/firmware/spi_sd.c`.

```
substitute_mcu --SPI--> cone_sd_ata --IDE port--> cone_mm_link ==vid==> 1k30 (acex) --> CF card
substitute_mcu --PS/2-----------------------------> cone_mm_link ==vid==> 1k30 PS/2 pins
cone_mergeinputs <--joy_a/joy_b------------------- cone_mm_link <==vid== 1k30 <-- gb[5] <-- 1k100 <-- CPLD ioshift
```

## Lines

| vid | pin | toplevel port | dir | Minimig (`src:Extender.qsf`) | use |
|---|---|---|---|---|---|
| 15 | 43 | `vid_ioclk` | out | IOclk | link clock, clk_100 / 2 |
| 14 | 46 | `vid_ser_out` | out | addbo[7] | serial slots to the 1k30 |
| 13 | 52 | `vid_ser_in` | in | addbi[5] | serial slots from the 1k30 |
| 12, 11 | 53, 54 | `vid_spare_in[1:0]` | in | addbi[4], sysclk | unused ('1', 1k30 clock) |
| 10 | 58 | `vid_spare_out` | out | addbo[6] | driven '1' as Minimig does |
| 9..4 | 60..79 | `vid_ide_out[5:0]` | out | addbo[5:0] | IDE command, address, write data |
| 3..0 | 88..91 | `vid_ide_in[3:0]` | in | addbi[3:0] | IDE read nibbles |

Locations and directions are those of `reference/C1_extender.pin`
(`verify_pins.py --strict` with `pin_aliases.txt`, in lint and after fit).

## Clocking and capture windows

IOclk is clk_100 (hostclocks c0, 100.23 MHz, period Tc = 9.977 ns) / 2 =
50.11 MHz; Minimig runs it at 113.5 / 2 = 56.75 MHz (`src:cfide.vhd:524`,
`src:palclk.tdf:53,60`). All link logic runs on the clk_100 edge that
raises IOclk ("tick"); outputs are re-registered on the falling clk_100
edge while IOclk is high (`src:cfide.vhd:517-520`,
`src:cyclone.vhd:99-102`); the 1k30 samples on IOclk rise
(`src:1k30/acex.vhd:86-87,213`).

* 1k30 capture: data changes Tc/2 + skew after IOclk rises (skew = data
  wire minus IOclk wire), so setup = 1.5 Tc - skew = 14.97 ns - skew and
  hold = 0.5 Tc + skew.
* Extender capture: the 1k30 launches on IOclk rise k and the extender
  samples at tick k+1, 2 Tc later. With rt = IOclk wire + 1k30 tCO +
  return wire (measured from the extender's IOclk pin), setup = 2 Tc - rt
  and hold = rt, so 0 < rt < 19.95 ns less the extender's own setup/hold.
  Minimig's 56.75 MHz leaves 17.6 ns; its round trip works on hardware.

There are no strobes or valid flags: both ends count IOclk cycles, and
every count below assumes rt within one IOclk period.

## IDE tunnel

Extender states and counts from `src:cfide.vhd:527-603`; the 1k30 decodes
`src:1k30/acex.vhd:84-161`. Idle output is "111111".

| extender (one IOclk each) | vid_ide_out | 1k30 |
|---|---|---|
| ide1 | read "010000", write "100000" | starts an access |
| set_addr | bit 5 = /CS1, bit 4 = /CS0, bit 3 = 0, bits 2..0 = register | latches register and chip selects |
| write: 3 data cycles | data[5:0], data[11:6], data[15:12] | DIOW- low, drives data from the third |
| waitclose, 10 cycles (`:552,563`) | "111111" | strobe held |
| close | "000000" | releases DIOR-/DIOW-, latches the read word |
| read1 (5-cycle wait, `:571`), read2..4 | - | sends the word as nibbles, low first, on vid[3:0] |
| setwaitend: `ide_ack` | - | - |
| waitend, 5 cycles (`:595`) | - | - |

Strobe timing follows from the counts (simulated with both 1k30 models):
DIOR- low 11 IOclk = 219 ns, DIOW- low 14 IOclk = 279 ns, address and
chip select 1 IOclk = 20 ns before the strobe. Minimig's are 194 ns,
247 ns and 17.6 ns, which work with real CF cards. The link takes
`ide_req`/`ide_wr`/`ide_cs0`/`ide_cs1`/`ide_reg`/`ide_wdata` when an
access starts and pulses `ide_ack` with `ide_rdata`.

## Serial slots

One bit per IOclk, eight slots per frame (`src:cyclone.vhd:106-166`,
`src:1k30/acex.vhd:171-226`):

| slot | 1k30 -> extender | extender -> 1k30 |
|---|---|---|
| 0 | sync (toggles every frame) | frame counter bit 3 (ignored) |
| 1 | keyboard data | keyboard data |
| 2 | keyboard clock | keyboard clock |
| 3 | mouse data | mouse data |
| 4 | mouse clock | mouse clock |
| 5 | RxD (never driven by `acex.vhd`) | TxD |
| 6 | C2MHz | audio lrclk |
| 7 | ioshift (CPLD joystick stream) | audio data |

The extender slips one slot per frame until the sync bit toggles, locks
after 16 good frames and sends all '1' until then (`src:cyclone.vhd:110-111,
150-163`). PS/2 lines are open drain at the 1k30: a '0' from
substitute_mcu's `ps2*_out` pulls the line low. The 1k30 drives no RxD,
so the template leaves `rxd` open and substitute_mcu's `txd` goes to the
1k30's TxD pin.

**Joysticks.** C2MHz and ioshift are rebuilt from slots 6/7; on each C2MHz
rise the 16-bit CPLD frame (Cone_core_development section 7.3) shifts in
and is decoded when its sync '0' reaches the top bit
(`src:cyclone.vhd:206-222`). `joy_a` is port A (J18), `joy_b` port B (J17),
both `fire2 fire1 right left down up`, active low; the stream has no second
fire button, so fire2 is '1'. As in Minimig, the frame locks onto the
first '0' that reaches the top bit, so a button held while the link locks
can misframe the ports until it is released.

**Audio.** `audio_l`/`audio_r` are shifted out as in
`src:cyclone.vhd:171-201`: 24 C2MHz periods per channel, lrclk low for
left, 16 bits MSB first from the eighth period. The template feeds zeros
(silence); the guest's `AUDIO_L/R` stay on the extender's sigma1/sigma2
pins. A core with parallel PCM outputs can feed the 1k30's DAC instead.

## SD-to-ATA bridge

`substitute_mcu` runs with `SPI_EXTERNALCLK => false`: the bridge is an
on-chip mode-0 slave in the clk_100 domain that answers each rising SCK
within one clk_100 cycle, and spi_controller samples MISO a full SCK
period later (12.5 MHz fast, 385 kHz init). The slow init clock ignores
`spi_ack` in either mode (`substitute_mcu.vhd:373-383`).

| command (`spi_sd.c:36-45`) | response |
|---|---|
| CMD0 | R1 01, enter idle |
| CMD8 (arg 1AA) | R1, then 00 00 01 AA (echo of arg[11:0]) |
| CMD55 | R1 |
| CMD41 | R1 00, leave idle |
| CMD58 | R1, then OCR C0 FF 80 00 (power-up done, CCS: block addressing, `spi_sd.c:232-238`) |
| CMD9 | ATA IDENTIFY; R1, FF while it runs, then FE + 16-byte CSD v2 + FF FF |
| CMD16 | R1 |
| CMD17 | ATA READ SECTORS; R1, FF while it runs, then FE + 512 bytes + FF FF, or the data error token 01 if the device sets ERR |
| CMD24 | R1; host sends FE + 512 bytes + 2 CRC; data response 05, then 00 until the ATA write completes, then FF |
| other | R1 04 (illegal command) |

R1 carries the idle bit. It comes in the second byte after the CRC byte
(NCR = 2) and is held back (FF) until the ATA side is idle; `spi_sd.c`
polls up to 40000 bytes for it (`:118-125`), so a command never overlaps
an ATA transfer that a previous, abandoned command started. ATA commands
start only while the link is locked (`sync_ok`), so nothing reaches the
CF card before Minimig's 1k30 image runs; until then CMD9/CMD17 answer
FF, which the firmware treats as a slow card. CRC bytes the
bridge sends are FF; it ignores the host's.

The CSD carries only what `spi_sd.c:417-420` reads: byte 0 = 40 (CSD v2)
and C_SIZE in bytes 7-9 = sectors / 1024 - 1, where sectors is the LBA28
count from IDENTIFY words 60-61 (DeMiSTify `firmware/ide.c:145-146`). The
firmware turns it back into (C_SIZE + 1) x 1024 sectors, at most 1023
below the card's size.

ATA sequence, as Minimig's `_MMC_Read`/`_MMC_Write`
(`src:Armreplacement/start.asm:113-268`), device 0 on CS0, LBA28, one
sector:

1. read status (reg 7) until BSY = 0 and DRDY = 1;
2. write sector count (reg 2) = 1, LBA 7:0 / 15:8 / 23:16 (regs 3-5),
   device (reg 6) = E0 | LBA[27:24], command (reg 7) = EC / 20 / 30;
3. read status until BSY = 0 and DRQ = 1, or ERR (abort);
4. 256 words through the data register (reg 0), low byte first;
5. after a write, read status until BSY = 0.

Registers `src:minimig/Gayle.v:59-66`, status bits `Gayle.v:88-91` (7 BSY,
6 DRDY, 3 DRQ, 0 ERR), commands `start.asm:16-19`. A word takes one link
access; one sector buffer (256 x 16 block RAM) holds the data between the
SPI and ATA sides. Write errors cannot be reported:
`spi_sd.c:331-338` returns success once busy ends.

## Simulation

`scripts/sim.sh` builds `sim/tb_mmlink.vhd` and runs the cases in
`scripts/run_sim.py`. The testbench connects:

* DeMiSTify's `spi_controller` with substitute_mcu's SPI timer and the
  CPU-side SPI()/SPI_READ()/chip-select timing, driven by a sequencer that
  replays `spi_sd.c`: `sd_init` (CMD0 at the slow clock, CMD8 + R7,
  CMD55 + ACMD41, CMD58 + OCR, CMD9 + CSD), then sector reads at LBA
  0x1234567, 0 and the last sector, writes with read-back, a read beyond
  the card (error token) and an illegal command;
* `cone_sd_ata`, `cone_mm_link` and `cone_mergeinputs` at clk_100;
* the 1k30: `sim/models/k30_mm_model.vhd`, written from the protocol
  above and stricter than the hardware (it flags any link word the
  extender should not send), or Minimig's own `1k30/acex.vhd` (`acex_*`
  cases, `third_party/C1minimigV201_source/1k30/acex.vhd` copied by
  `sim.sh` into `build/` with its internal signals initialised to the
  ACEX's power-up '0');
* `sim/models/ata_device_model.vhd`: a CF card with IDENTIFY, BSY/DRQ
  timing, a sector store, ERR for LBAs beyond the card, and assertions on
  the task-file protocol (no writes while BSY or DRQ, CS1 unused, sector
  count 1, LBA device 0);
* PS/2 keyboard and mouse sending frames on the 1k30's open-drain lines,
  after the extender inhibits the keyboard; the CPLD joystick stream
  re-timed to a 2 MHz C2MHz; TxD; the 1k30's lrclk/adat decoded back to
  the audio samples.

The `late_k30` cases start the 1k30 0.5 ms into the run, after CMD9 has
been sent; until then its lines carry a constant pattern that would read
as a ready ATA status. They pass only because the bridge waits for the
link to lock (without that check the identify goes to a 1k30 that is not
there and the CSD is wrong).

It asserts every sector byte, the written data on read-back, the
IDENTIFY-derived size in the CSD, every PS/2 frame, the joystick words
(also through `cone_mergeinputs`), audio, TxD, sync lock with no later
loss, no contention on the vid or IDE lines, and setup/hold of at least
1 ns at both capture points. It reports the measured windows.

Wires: T_E2K on IOclk, T_E2K + skew on the other extender outputs, T_K2E
back. The sweep varies rt = T_E2K + T_K2E over 0..30 ns and skew over
2.5..17.5 ns. `run_sim.py` predicts each outcome and each measured
setup/hold from the windows above (`mm_windows`, `mm_predict`); both must
match to 2 ps.

| case | 1k30 | sync | SD init | sector read | sector write | DIOR- / DIOW- | extender setup / hold | 1k30 setup / hold |
|---|---|---|---|---|---|---|---|---|
| firmware timing, rt 6 ns | model | 3.7 us | 15.2 ms | 557 us | 515 us | 219 / 279 ns | 13.95 / 6.00 ns | 14.97 / 4.99 ns |
| firmware timing, rt 6 ns | `acex.vhd` | 3.7 us | 15.2 ms | 557 us | 515 us | 219 / 279 ns | 13.95 / 6.00 ns | 14.97 / 4.99 ns |
| 1k30 starts at 0.5 ms (`late_k30`) | both | 503 us | 0.70 ms | 560 us | 515 us | 219 / 279 ns | 13.95 / 6.00 ns | 14.97 / 4.99 ns |

SD init uses the firmware's 200-byte spins at 385 kHz; sector times are at
12.5 MHz SCK and include the command, ATA transfer and data block.
Sweep: 40/40 outcomes (20 per 1k30 model) and every measured window match
the prediction: pass for 2.5 <= rt <= 17.5 ns and skew <= 12.5 ns; rt = 0
fails the 1 ns hold margin; rt >= 20 ns and skew >= 15 ns slip a cycle and
fail functionally.

## Synthesis

`scripts/build_core.sh` (Quartus II 13.1, BBC core, EP3C25E144C8):
11,900 LEs (48 %), 5,192 registers, 198,656 memory bits (33 %). The
`cone_io` build of the same core used 11,421 LEs and 194,560 bits; the
difference is the link, the bridge and its 4 Kbit sector buffer.
`check_timing.py`: timing met in all three corners; worst setup slack
1.36 ns (slow 85C), on the half-period path from the tick registers to
the falling-edge output registers that the protocol prescribes; worst
hold slack 0.14 ns (fast 0C, guest clock).

`constraints.sdc` defines `ioclk` on the `cone_mm_link|ioclk` register
(clk_100 / 2) and `vid_ioclk` on the pin, and constrains the link against
the pin, with the 0.5 ns placeholder delays of `BLOCKED.md` #3. The
multicycles reproduce the protocol's edges, which
`quartus_sta -t scripts/sta_paths.tcl` confirms:

| paths | setup relationship | hold relationship | setup / hold slack |
|---|---|---|---|
| `vid_ide_out`, `vid_ser_out` (falling clk_100 launch, IOclk capture) | 1.5 Tc = 14.966 ns | -0.5 Tc = -4.988 ns | 12.15 / 4.85 ns |
| `vid_ide_in`, `vid_ser_in` (IOclk launch, next tick capture) | 2 Tc = 19.954 ns | 0 | 10.83 / 6.46 ns |

The slack is what remains for board wiring and the 1k30's clock-to-out
and setup beyond the placeholders. All 82 fitted pins match
`cone_ext_pins.tcl` (`verify_pins.py --strict`).

## Remaining risks on hardware

1. The round trip and skew on the real board and the ACEX's timing
   (`BLOCKED.md` #3): the windows above are wide and Minimig runs the
   same link faster, but nothing has been measured.
2. `support.rbf` has no source; the joystick relay through it is assumed
   (`BLOCKED.md` #6).
3. CF card behaviour beyond the model: power-up BSY, cards that need
   more than BSY/DRDY polling. The bridge polls without a timeout, so a
   missing card stalls storage (the firmware's own timeouts still return).
4. NewBoot configures the extender before the 1k30 (manual section 4.3).
   The bridge starts ATA commands only once the link has locked to the
   1k30's sync bit; an image other than Minimig's whose vid[13] happens to
   toggle every eight IOclk cycles would defeat that check.
