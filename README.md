# cone-demistify

DeMiSTify board target `cone_ext` for the C-One FPGA Extender
(Cyclone III EP3C25E144C8), so MiST cores can run on a Commodore One,
plus the 1k30-side vid-bus slave and the tooling to lint, simulate,
verify pins against reference files and build NewBoot CF-card trees.

Hardware facts come from the Wendrich manual, the board's pin report and
schematic in `reference/`; remaining gaps are in `BLOCKED.md`.

## Layout

```
Board/cone_ext/        DeMiSTify board definition (pins, PLL, SDC, cone_io, cone_mergeinputs)
templates/cone_ext/    toplevel template (guest + substitute_mcu + cone_io)
cone_1k30/             1k30 side of the vid-bus mux
sim/                   testbench, models, altera_mf and DeMiSTify stubs for GHDL
scripts/               lint, sim, asset checks, pin verification, Quartus install, CF card
reference/             gated inputs (not committed), see reference/README.md
docs/                  architecture and protocol documentation
```

## Usage

```
scripts/lint.sh            # GHDL/verilator/shellcheck/black/pylint, pins if present, then sim
scripts/sim.sh             # vid-bus simulation matrix (--no-sweep, --only REGEX)
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

The keyboard, joystick and storage link is still being ported to
Minimig's protocol; [docs/hardware.md](docs/hardware.md) has the full steps
and what works today.

## Documentation

* [docs/architecture.md](docs/architecture.md): pin budget, SDRAM, clocks, NewBoot layout, storage options
* [docs/hardware.md](docs/hardware.md): building a CF card and booting a core on a real C-One
* [docs/vidbus.md](docs/vidbus.md): vid-bus protocol, timing windows, simulation results
* [docs/protocol_decision.md](docs/protocol_decision.md): our vid-bus protocol vs Minimig's (option B chosen)
* [docs/firmware.md](docs/firmware.md): toolchain, firmware, patch series, core build
* [reference/README.md](reference/README.md): expected reference files and their sources
* [BLOCKED.md](BLOCKED.md): what is missing and which file unblocks it

## Licence

GPL-3.0 (see `COPYING`), as DeMiSTify. `gen_reset.vhd` is LGPL-3 (Syntiac).
