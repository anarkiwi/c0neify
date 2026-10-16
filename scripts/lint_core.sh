#!/usr/bin/env bash
# Elaborate a core's generated cone_ext toplevel with GHDL: the project's own
# VHDL file list (DeMiSTify controller, EightThirtyTwo, firmware ROMs, config
# package) plus Board/cone_ext, with altera_mf from sim/altera_mf_stub. The
# guest core (Verilog) stays an unbound component.
#   lint_core.sh [CORE_DIR] [PROJECT]   (default cores/BBC_DemiSTify BBC)
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
CORE=${1:-cores/BBC_DemiSTify}
PROJECT=${2:-BBC}
BOARD=cone_ext
PRJ=$CORE/$BOARD
W=build/lint_core/${CORE##*/}

[[ -f $PRJ/${PROJECT}_${BOARD}_files.tcl ]] || {
	echo "$PRJ/${PROJECT}_${BOARD}_files.tcl missing: run scripts/build_core.sh --init-only" >&2
	exit 1
}
rm -rf "$W"
mkdir -p "$W/altera_mf" "$W/work"
mapfile -t VHDL < <(python3 scripts/qip_files.py --base "$PRJ" --kind VHDL_FILE \
	--exclude files.qip "${PROJECT}_${BOARD}_files.tcl" top.qip | cut -f2)
VHDL+=(Board/"$BOARD"/*.vhd)
printf '%d VHDL files\n' "${#VHDL[@]}"

GHDL=(--std=08 -frelaxed --workdir="$W/work" -P"$W/altera_mf")
ghdl -a --std=08 --work=altera_mf --workdir="$W/altera_mf" sim/altera_mf_stub/*.vhd
ghdl -i "${GHDL[@]}" "${VHDL[@]}"
ghdl -m "${GHDL[@]}" -Wno-binding -Wno-hide -Wno-shared "${BOARD}_top"
ghdl -r "${GHDL[@]}" -Wno-binding -Wno-hide -Wno-shared "${BOARD}_top" --stop-time=0ns --assert-level=error >/dev/null
echo "${PROJECT} ${BOARD}_top elaborates"
