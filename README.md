# cone-demistify

DeMiSTify board target `cone_ext` for the C-One FPGA Extender
(Cyclone III EP3C25E144C8), so MiST cores can run on a Commodore One
with Minimig V2.01's unchanged 1k100/1k30 images, plus the tooling to
lint, simulate, verify pins against reference files and build NewBoot
CF-card trees.

Hardware facts come from the Wendrich manual, the board's pin report and
schematic in `reference/`; remaining gaps are in `BLOCKED.md`.

## Layout

```
Board/cone_ext/        DeMiSTify board definition (pins, PLL, SDC, cone_mm_link, cone_sd_ata, cone_mergeinputs)
templates/cone_ext/    toplevel template (guest + substitute_mcu + link + SD-to-ATA bridge)
fallback/              cone_io vid-bus mux, its 1k30 slave and testbench (not built)
sim/                   tb_mmlink, 1k30/ATA models, altera_mf and DeMiSTify stubs for GHDL
scripts/               lint, sim, asset checks, pin verification, Quartus install, CF card
reference/             gated inputs (not committed), see reference/README.md
docs/                  architecture and protocol documentation
```

## Usage

```
scripts/lint.sh            # GHDL/verilator/shellcheck/black/pylint, pins if present, then sim
scripts/sim.sh             # simulation matrix (--no-sweep, --vidbus-sweep, --only REGEX)
scripts/check_assets.sh    # which reference/ files are present
scripts/build_core.sh      # toolchain, firmware, project, GHDL check, Quartus compile, CF card
python3 -m pytest -n auto tests/
```

Requires `ghdl verilator shellcheck jq python3` (apt) and
`pytest pytest-xdist pytest-cov black pylint` (pip).

## Running on a C-One

1. Install Quartus II 13.1 from `reference/` (`scripts/install_quartus.sh`) and put `C1minimigV201_build.zip` in `reference/`.
2. `scripts/build_core.sh` builds the BBC core and writes `build/cfcard/c1dcores/bbc/`.
3. Copy that directory to `c1dcores/bbc/` on a NewBoot V2.01 CF card, without the `*.MISSING` placeholders.
4. Boot the C-One and select the core in NewBoot.

[docs/hardware.md](docs/hardware.md) has the full steps and the status:
the link and storage pass simulation but have not run on hardware yet.

## Documentation

* [docs/architecture.md](docs/architecture.md): pin budget, SDRAM, clocks, NewBoot layout, storage options
* [docs/hardware.md](docs/hardware.md): building a CF card and booting a core on a real C-One
* [docs/minimig_link.md](docs/minimig_link.md): Minimig link and SD-to-ATA bridge, timing windows, simulation and synthesis results
* [docs/protocol_decision.md](docs/protocol_decision.md): our vid-bus protocol vs Minimig's (option B, implemented)
* [docs/vidbus.md](docs/vidbus.md): the fallback `cone_io` protocol
* [docs/firmware.md](docs/firmware.md): toolchain, firmware, patch series, core build
* [reference/README.md](reference/README.md): expected reference files and their sources
* [BLOCKED.md](BLOCKED.md): what is missing and which file unblocks it

## Licence

GPL-3.0 (see `COPYING`), as DeMiSTify. `gen_reset.vhd` is LGPL-3 (Syntiac).
