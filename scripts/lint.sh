#!/usr/bin/env bash
# Static checks for everything this repo owns:
#   VHDL     analyse + elaborate every entity with GHDL (--std=08), plus a
#            VHDL-93 analysis of files that must also build for the ACEX 1k30
#   Verilog  verilator --lint-only on any .v/.sv we own
#   shell    bash -n + shellcheck on scripts/*.sh
#   python   black --check + pylint on scripts/ and tests/
#   actions  actionlint on .github/workflows when installed
#   pins     verify_pins.py when reference/C1_extender.pin is present
#   sim      scripts/sim.sh unless LINT_NO_SIM=1
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
W=build/lint
rm -rf "$W"
mkdir -p "$W/altera_mf" "$W/work08" "$W/work93"

OWN_VHDL=(Board/cone_ext/*.vhd templates/cone_ext/*.vhd cone_1k30/*.vhd)
# Board templates instantiate "component guest"; each core renames it to its
# own guest entity. Lint a copy renamed to the stub package's guest_top.
mkdir -p "$W/templates"
for f in templates/*/*_top.vhd; do
	sed -E 's/(:[[:space:]]*component[[:space:]]+)guest\b/\1guest_top/I' "$f" >"$W/templates/${f##*/}"
done
ELAB_VHDL=(Board/cone_ext/*.vhd "$W"/templates/*.vhd cone_1k30/*.vhd)
# Must stay VHDL-93 clean: these are shared with the 1k30 build.
VHDL93=(cone_1k30/*.vhd Board/cone_ext/cone_mergeinputs.vhd)
STUBS=(sim/demistify_stub/*.vhd)
GHDL08=(--std=08 --workdir="$W/work08" -P"$W/altera_mf")

step() { printf '\n== %s\n' "$*"; }

step "GHDL: altera_mf stub"
ghdl -a --std=08 --work=altera_mf --workdir="$W/altera_mf" \
	sim/altera_mf_stub/altera_mf_components.vhd sim/altera_mf_stub/altpll.vhd

step "GHDL: import ${#OWN_VHDL[@]} owned files + ${#STUBS[@]} stubs"
ghdl -i "${GHDL08[@]}" "${ELAB_VHDL[@]}" "${STUBS[@]}"

mapfile -t ENTITIES < <(sed -nE 's/^[[:space:]]*entity[[:space:]]+([A-Za-z0-9_]+)[[:space:]]+is.*/\1/Ip' \
	"${OWN_VHDL[@]}" | tr '[:upper:]' '[:lower:]' | sort -u)
n=0
for e in "${ENTITIES[@]}"; do
	n=$((n + 1))
	printf '[%d/%d] elaborate %s\n' "$n" "${#ENTITIES[@]}" "$e"
	ghdl -m "${GHDL08[@]}" -Wno-binding "$e" >/dev/null
done

step "GHDL: VHDL-93 analysis of 1k30-shared files"
ghdl -a --std=93 --workdir="$W/work93" "${VHDL93[@]}"

mapfile -t OWN_VLOG < <(git ls-files -- '*.v' '*.sv' ':!:DeMiSTify/**' ':!:cores/**')
if ((${#OWN_VLOG[@]})); then
	step "Verilator lint: ${#OWN_VLOG[@]} files"
	verilator --lint-only -Wall "${OWN_VLOG[@]}"
fi

step "Shell"
for f in scripts/*.sh; do
	bash -n "$f"
done
shellcheck -x scripts/*.sh

shopt -s nullglob
PY=(scripts/*.py tests/*.py)
shopt -u nullglob
if ((${#PY[@]})); then
	step "Python: ${#PY[@]} files"
	black --check --quiet "${PY[@]}"
	pylint --score=n "${PY[@]}"
fi

if [[ -x build/tools/actionlint ]] || command -v actionlint >/dev/null; then
	step "actionlint"
	PATH=$ROOT/build/tools:$PATH actionlint
else
	step "actionlint not installed (scripts/get_actionlint.sh), skipped"
fi

if [[ -f reference/C1_extender.pin ]]; then
	step "Pins: C1_extender.pin vs cone_ext_pins.tcl"
	python3 scripts/verify_pins.py reference/C1_extender.pin Board/cone_ext/cone_ext_pins.tcl
else
	step "Pins: reference/C1_extender.pin absent, skipped"
fi

if [[ ${LINT_NO_SIM:-0} != 1 && -x scripts/sim.sh ]]; then
	step "Simulation"
	scripts/sim.sh
fi

step "lint OK"
