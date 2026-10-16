#!/usr/bin/env bash
# Build and run the vid-bus simulation (sim/tb_vidbus.vhd) with GHDL.
# Uses DeMiSTify's own spi_controller.vhd when the submodule is checked out,
# otherwise sim/models/spi_controller_model.vhd.
#   scripts/sim.sh [--no-sweep] [--only REGEX] [--jobs N]
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
W=build/sim
rm -rf "$W"
mkdir -p "$W/altera_mf" "$W/work"

SPI=sim/models/spi_controller_model.vhd
if [[ -f DeMiSTify/controller/spi_controller.vhd ]]; then
	SPI=DeMiSTify/controller/spi_controller.vhd
fi
echo "spi_controller: $SPI"

ghdl -a --std=08 --work=altera_mf --workdir="$W/altera_mf" sim/altera_mf_stub/*.vhd
ghdl -a --std=08 --workdir="$W/work" -P"$W/altera_mf" \
	Board/cone_ext/hostclocks.vhd Board/cone_ext/cone_io.vhd \
	Board/cone_ext/cone_mergeinputs.vhd cone_1k30/cone_1k30_mux_slave.vhd \
	"$SPI" sim/tb_vidbus.vhd

OMP_NUM_THREADS=1 python3 scripts/run_sim.py --workdir "$W/work" \
	--altera-mf "$W/altera_mf" --logdir "$W/logs" "$@"
