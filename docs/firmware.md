# Toolchain, firmware and core build

`scripts/build_core.sh` runs every step below for the first core
(`cores/BBC_DemiSTify`); `--init-only` stops after project generation and
the GHDL check. Without `quartus_sh` it generates only the project's file
list, lints, and stops.

## Dependencies

apt: `build-essential libncurses-dev` (EightThirtyTwo; ncurses is for the
`832ocd` debugger), `ghdl`, `python3`; Quartus II 13.1 for project
generation and compile (`scripts/install_quartus.sh`).

## Submodules and patches

```
git submodule update --init DeMiSTify cores/BBC_DemiSTify
git -C DeMiSTify submodule update --init EightThirtyTwo Board/chameleon-modules
git -C cores/BBC_DemiSTify submodule update --init fpga/mist/mist-modules rtl/fdc1772-verilator rtl/T65
scripts/apply_patches.sh
```

The superproject pins upstream commits. `apply_patches.sh` puts each
patched submodule on a local branch `cone_ext` at the pinned commit plus
`patches/<submodule path>/*.patch`:

* `patches/DeMiSTify`: `Board/cone_ext` and `templates/cone_ext`, generated
  from this repo's copies by `scripts/export_patches.sh`
  (`--check` fails when they differ). This series is the upstream PR.
* `patches/cores/BBC_DemiSTify`: `demistify_joybits` in the core's config
  package, the `cone_ext/` toplevel directory, and a port of
  `firmware/overrides.c` to DeMiSTify's current `struct diskimage`.

The BBC core's own DeMiSTify submodule (an older revision) is not used:
`cores/BBC_DemiSTify/DeMiSTify` is a symlink to the top-level `DeMiSTify`,
so the core's relative paths resolve to the patched framework.

## EightThirtyTwo toolchain

```
make -C DeMiSTify -f bootstrap.mk
```

Unpacks the vbcc 0.9g source shipped in `EightThirtyTwo/vbcc0_9g.tar.gz`,
builds `vbcc/bin/vbcc832`, the `832a` assembler/linker, `romgen`, `832ocd`
and `lib832`, then runs the compiler test suite under `832emu`
(`EightThirtyTwo/test.log`).

## Firmware

```
cp site.mk DeMiSTify/site.mk
make -C cores/BBC_DemiSTify firmware
```

Builds DeMiSTify's control firmware with the core's
`firmware/config.h` and `overrides.c` into `firmware/controller.bin` and
the ROM images `controller_rom{1,2}_byte.vhd` (8 KiB + 8 KiB, set by the
core's `ROMSIZE1/2`). The firmware is board-independent.

## Project and compile

```
make -C cores/BBC_DemiSTify init BOARD=cone_ext      # quartus_sh -t mkproject.tcl
make -C cores/BBC_DemiSTify compile BOARD=cone_ext   # quartus_sh -t compile.tcl
scripts/lint_core.sh                                 # GHDL elaboration of cone_ext_top
```

`site.mk` sets `BOARDS = cone_ext` and Quartus 13.1 at
`/opt/altera/13.1/quartus/bin/`. The project lands in
`cores/BBC_DemiSTify/cone_ext/` (the core uses `PROJECTPATH=./`); the
bitstream is `output_files/BBC_cone_ext.rbf`.

## ROM and CF card

The core loads `BBC.ROM` (`ROM_FILENAME` in `config.h`) from the card the
firmware reads over SPI. `build_core.sh` fetches `cores/bbc/bbc.rom` from
mist-devel/mist-binaries with a sparse clone into `build/` and passes it
to `scripts/make_cfcard.sh`, which writes `build/cfcard/c1dcores/bbc/`.
