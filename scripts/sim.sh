#!/usr/bin/env bash
# Build and run the GHDL simulations:
#   sim/tb_mmlink.vhd       Minimig link + SD/ATA bridge, against the 1k30 model
#                           and, when reference/C1minimigV201_source.zip is
#                           present, against Minimig's own 1k30/acex.vhd
#   fallback/tb_vidbus.vhd  the cone_io link kept as the fallback
# Uses DeMiSTify's spi_controller.vhd when the submodule is checked out,
# otherwise sim/models/spi_controller_model.vhd.
#   scripts/sim.sh [--no-sweep] [--vidbus-sweep] [--only REGEX] [--jobs N]
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
W=build/sim
ZIP=reference/C1minimigV201_source.zip
rm -rf "$W"
mkdir -p "$W/altera_mf" "$W/work"

SPI=sim/models/spi_controller_model.vhd
if [[ -f DeMiSTify/controller/spi_controller.vhd ]]; then
	SPI=DeMiSTify/controller/spi_controller.vhd
fi
echo "spi_controller: $SPI"

ghdl -a --std=08 --work=altera_mf --workdir="$W/altera_mf" sim/altera_mf_stub/*.vhd
ghdl -a --std=08 --workdir="$W/work" -P"$W/altera_mf" \
	Board/cone_ext/hostclocks.vhd Board/cone_ext/cone_mergeinputs.vhd \
	Board/cone_ext/cone_mm_link.vhd Board/cone_ext/cone_sd_ata.vhd \
	fallback/cone_io.vhd fallback/cone_1k30_mux_slave.vhd "$SPI" \
	sim/models/ata_device_model.vhd sim/models/k30_mm_model.vhd \
	sim/tb_mmlink.vhd fallback/tb_vidbus.vhd

ACEX=()
if [[ -f $ZIP ]]; then
	# Extracted copy only, never committed. GHDL starts signals at 'U'
	# where the ACEX 1K's registers power up at 0, so the internal signals
	# get explicit zero initial values.
	unzip -p "$ZIP" 1k30/acex.vhd | sed -E \
		-e "s/^(\s*signal\s+[^:]+:\s*std_logic)\s*;/\1 := '0';/I" \
		-e "s/^(\s*signal\s+[^:]+:\s*std_logic_vector\s*\([^)]*\))\s*;/\1 := (others => '0');/I" \
		>"$W/acex.vhd"
	ghdl -a --std=08 -fsynopsys --workdir="$W/work" "$W/acex.vhd"
	ACEX=(--acex)
	echo "1k30/acex.vhd from $ZIP: running the tb_mmlink cases against it too"
else
	echo "$ZIP absent: tb_mmlink runs against sim/models/k30_mm_model.vhd only"
fi

OMP_NUM_THREADS=1 python3 scripts/run_sim.py --workdir "$W/work" \
	--altera-mf "$W/altera_mf" --logdir "$W/logs" "${ACEX[@]}" "$@"
