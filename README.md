# cone-demistify

DeMiSTify board target `cone_ext` for the C-One FPGA Extender
(Cyclone III EP3C25E144C8), so MiST cores can run on a Commodore One,
plus the 1k30-side vid-bus slave and the tooling to lint, simulate,
verify pins against reference files and build NewBoot CF-card trees.

Hardware facts are taken from the Wendrich manual and are unverified
against the board's own pin file and schematic until those are present in
`reference/`; see `BLOCKED.md`.

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
python3 -m pytest -n auto tests/
```

Requires `ghdl verilator shellcheck jq python3` (apt) and
`pytest pytest-xdist pytest-cov black pylint` (pip).

## Documentation

* [docs/architecture.md](docs/architecture.md): pin budget, SDRAM, clocks, NewBoot layout, storage options
* [docs/vidbus.md](docs/vidbus.md): vid-bus protocol, timing windows, simulation results
* [reference/README.md](reference/README.md): expected reference files and their sources
* [BLOCKED.md](BLOCKED.md): what is missing and which file unblocks it

## Licence

GPL-3.0 (see `COPYING`), as DeMiSTify. `gen_reset.vhd` is LGPL-3 (Syntiac).
