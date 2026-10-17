# Running a core on a real C-One

Steps to put a DeMiSTified core (first core: BBC Micro) on a Commodore One
with the FPGA Extender, loaded from CF by NewBoot. No JTAG cable is needed.

## Status

| Part | State |
|---|---|
| Extender bitstream (`cone_ext`) | builds, fits, meets timing, pins verified against `C1_extender.pin` |
| 1k100 / 1k30 images | Minimig V2.01 `support.rbf` / `support.bin`, reused unchanged ([protocol_decision.md](protocol_decision.md), option B) |
| vid-bus link speaking Minimig's protocol (`cone_mm_link`) | implemented; passes simulation against a 1k30 model and against Minimig's own `1k30/acex.vhd` ([minimig_link.md](minimig_link.md)); not yet run on hardware |
| Storage: SD over SPI bridged to ATA on the CF slot (`cone_sd_ata`) | implemented; DeMiSTify's SD init, sector reads and writes pass simulation against a CF model; not yet run on hardware |
| Keyboard, mouse, joysticks, TxD | through the link; simulated |
| Audio | guest audio on the extender's sigma1/sigma2 pins as before; the 1k30's DAC gets silence |

Nothing beyond configuration, the PLL, SDRAM and VGA has been seen on a
real C-One yet. The link's round-trip delay on the board is the main
unknown (`BLOCKED.md` #3).

The order in which to test a new board, from NewBoot alone up to this
core, is in [programming.md](programming.md#hardware-bring-up-order).

## You need

* C-One with FPGA Extender (Cyclone III EP3C25), VGA monitor, PS/2
  keyboard.
* A CF card (FAT) and reader.
* NewBoot V2.01, `NewbootV201.zip` from the iComp wiki
  (https://wiki.icomp.de/w/images/3/33/NewbootV201.zip). The
  `File:NewbootV201.zip` wiki page itself is HTML, not the archive.
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
  select.txt            selector text
  select.raw.MISSING    no menu icon is generated (see step 2)
  target.rbf.MISSING    not used: Minimig's support.rbf reconfigures the 1k30
```

Check timing yourself with
`python3 scripts/check_timing.py cores/BBC_DemiSTify/cone_ext/output_files/BBC_cone_ext.sta.rpt`.

## 2. Prepare the CF card

From `NewbootV201.zip` (`readme.txt`, `readme_minimig.txt`):

1. Copy the archive's contents to the root of the FAT CF card. The root
   `extender.rbf` (206 KB) is the bypass core that routes the 1k30's video
   through the extender; without it the VGA output stays black once the
   extender is fitted.
2. If the C-One is not yet running NewBoot, test cores from the BigBoot
   menu ("Config 0") first, then flash NewBoot with the `updater` core, as
   `readme.txt` describes.
3. Copy `build/cfcard/c1dcores/bbc/` to `c1dcores/bbc/` on the card and
   delete the zero-byte `*.MISSING` placeholders. `select.txt` (written by
   `make_cfcard.sh --label`) is the text shown in NewBoot's selector.
4. Every core directory has a `select.raw` icon (25600 bytes). Until this
   repo generates one, copy any core's `select.raw`, for example
   `c1dcores/Sdram_haus/select.raw` from the NewBoot archive.
5. To start the core at power-on without the menu ("direktcore"), copy the
   files of `c1dcores/bbc/` over the root files, as `readme.txt` describes.
6. `BBC.ROM` goes in the root of the card (`ROM_FILENAME` in the core's
   `firmware/config.h`); the firmware reads the same CF card through the
   SD-to-ATA bridge, addressing it by LBA.

## 3. Boot

1. Insert the card and power on. NewBoot's menu appears on VGA, generated
   by the 1k30 with the extender in feed-through mode.
2. Select the BBC entry. NewBoot loads `extender.rbf` into the extender,
   `support.rbf` into the 1k100 and `support.bin` into SRAM, then the
   1k100 reconfigures the 1k30 (manual section 4.3).
3. Expected: the extender drives VGA itself (sync through the
   open-collector drivers), at the BBC core's video timing, and the
   control firmware loads `BBC.ROM` from the card. F12 on the PS/2
   keyboard opens the OSD.

## If something is wrong

* No picture after selecting the core: check that `extender.rbf` is the
  `BBC_cone_ext.rbf` from this build (about 325 KB, compressed) and that the build log shows
  `timing met` and `82 assignments, 0 virtual` at the pin check.
* Garbage on screen: the guest runs from the 27.09 MHz clock derived from
  the 14.31818 MHz crystal (+0.33 %); monitors that are strict about
  timing may need the core's PLL regenerated for 28.37516 MHz
  (`docs/architecture.md`, Clocks).
* Report findings with the board revision and the build's commit hash.
