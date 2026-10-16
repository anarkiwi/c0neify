# Running a core on a real C-One

Steps to put a DeMiSTified core (first core: BBC Micro) on a Commodore One
with the FPGA Extender, loaded from CF by NewBoot. No JTAG cable is needed.

## Status

| Part | State |
|---|---|
| Extender bitstream (`cone_ext`) | builds, fits, meets timing, pins verified against `C1_extender.pin` |
| 1k100 / 1k30 images | Minimig V2.01 `support.rbf` / `support.bin`, reused unchanged ([protocol_decision.md](protocol_decision.md), option B) |
| vid-bus link speaking Minimig's protocol | **not yet implemented**: the extender still speaks the original `cone_io` protocol |
| Storage (SD over SPI bridged to ATA on the CF slot) | **not yet implemented** |

Until the last two rows are done, a card built today exercises
configuration, the PLL, SDRAM and VGA output. Keyboard, joysticks and
storage do not work, so the firmware cannot load `BBC.ROM`.

The current extender bitstream is safe to run with Minimig's 1k30 image.
That image clocks its whole link from vid[15] (`src:1k30/acex.vhd`
IOclk). Our extender drives vid[15] as `mux_sel[3]`, which stays low
after reset (no slot uses `sel >= 8`), so the 1k30 never starts an IDE
cycle on the CF card.

## You need

* C-One with FPGA Extender (Cyclone III EP3C25), VGA monitor, PS/2
  keyboard.
* A CF card and reader, with NewBoot V2.01 installed (iComp wiki,
  `File:NewbootV201.zip`; see its instructions for preparing the card).
* Either a local build (below) or the `cone_ext-<sha>` artifact of the
  `build` workflow's `synth` job.

## 1. Build

```
git clone https://github.com/anarkiwi/c0neify
cd c0neify
sudo apt-get install -y ghdl build-essential libncurses-dev python3 jq
# Quartus II 13.1 Web Edition: put QuartusSetupWeb-13.1.0.162.run and
# cyclone_web-13.1.0.162.qdz into reference/ (see reference/README.md), then
scripts/install_quartus.sh
# put C1minimigV201_build.zip into reference/ for the 1k100/1k30 images
scripts/build_core.sh
```

`build_core.sh` initialises the submodules it needs and applies
`patches/`. It then builds the EightThirtyTwo toolchain, the firmware and
the Quartus project, and checks the fitted pins and the generated
toplevel. Finally it writes the card tree:

```
build/cfcard/c1dcores/bbc/
  extender.rbf          the BBC core for the extender
  support.rbf           1k100 image, from C1minimigV201_build.zip
  support.bin           1k30 image, from C1minimigV201_build.zip
  bbc.rom               ROM image fetched from mist-devel/mist-binaries
  select.raw.MISSING    no menu icon is generated (see step 2)
  target.rbf.MISSING    not used: Minimig's support.rbf reconfigures the 1k30
```

Check timing yourself with
`python3 scripts/check_timing.py cores/BBC_DemiSTify/cone_ext/output_files/BBC_cone_ext.sta.rpt`.

## 2. Prepare the CF card

1. Install NewBoot V2.01 on the card as its instructions describe.
2. Copy `build/cfcard/c1dcores/bbc/` to `c1dcores/bbc/` on the card.
3. Delete the zero-byte `*.MISSING` placeholders.
4. For a menu icon, copy `select.raw` (and `select.txt`, the menu text)
   from another core directory, for example the Minimig one in
   `C1minimigV201_build.zip`, and edit `select.txt`. The icon format is
   not documented here.
5. Once storage works, `BBC.ROM` belongs in the root of the card the
   firmware reads (`ROM_FILENAME` in the core's `firmware/config.h`).

## 3. Boot

1. Insert the card and power on. NewBoot's menu appears on VGA, generated
   by the 1k30 with the extender in feed-through mode.
2. Select the BBC entry. NewBoot loads `extender.rbf` into the extender,
   `support.rbf` into the 1k100 and `support.bin` into SRAM, then the
   1k100 reconfigures the 1k30 (manual section 4.3).
3. Expected today: the extender drives VGA itself (sync through the
   open-collector drivers), at the BBC core's video timing. The control
   firmware finds no storage.

## If something is wrong

* No picture after selecting the core: check that `extender.rbf` is the
  `BBC_cone_ext.rbf` from this build (325 KB) and that the build log shows
  `timing met` and `82 assignments, 0 virtual` at the pin check.
* Garbage on screen: the guest runs from the 27.09 MHz clock derived from
  the 14.31818 MHz crystal (+0.33 %); monitors that are strict about
  timing may need the core's PLL regenerated for 28.37516 MHz
  (`docs/architecture.md`, Clocks).
* Report findings with the board revision and the build's commit hash.
