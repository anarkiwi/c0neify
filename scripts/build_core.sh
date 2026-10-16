#!/usr/bin/env bash
# Build a DeMiSTified core for cone_ext end to end:
#   submodules -> patches -> site.mk -> EightThirtyTwo toolchain -> firmware
#   -> project generation -> GHDL lint of the toplevel -> Quartus compile
#   -> NewBoot CF-card tree in build/cfcard.
#   build_core.sh [--init-only]   (stop after project generation and lint)
# Without quartus_sh (Q13 in site.mk, or $QUARTUS_BIN) only the project's
# file list is generated, then lint runs and the build stops.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
CORE=cores/BBC_DemiSTify
PROJECT=BBC
BOARD=cone_ext
ROM=build/mist-binaries/cores/bbc/bbc.rom
INIT_ONLY=0
[[ ${1:-} == --init-only ]] && INIT_ONLY=1
n=0
step() { printf '\n== [%d] %s\n' $((++n)) "$*"; }

step "submodules"
git submodule update --init -- DeMiSTify "$CORE"
git -C DeMiSTify submodule update --init -- EightThirtyTwo Board/chameleon-modules
git -C "$CORE" submodule update --init -- fpga/mist/mist-modules rtl/fdc1772-verilator rtl/T65

step "patches"
scripts/apply_patches.sh

step "site.mk and shared DeMiSTify"
cp site.mk DeMiSTify/site.mk
if [[ ! -L $CORE/DeMiSTify ]]; then
	git -C "$CORE" submodule deinit -q -f -- DeMiSTify 2>/dev/null || true
	rm -rf -- "$CORE/DeMiSTify"
	ln -s ../../DeMiSTify "$CORE/DeMiSTify"
fi

step "EightThirtyTwo toolchain"
make -s -C DeMiSTify -f bootstrap.mk >build/e832.log 2>&1 || {
	tail -20 build/e832.log
	exit 1
}
[[ -x DeMiSTify/EightThirtyTwo/vbcc/bin/vbcc832 && -f DeMiSTify/EightThirtyTwo/lib832/lib832.a ]]

step "firmware"
make -s -C "$CORE" firmware
ls -l "$CORE"/firmware/controller.bin

step "project generation"
QBIN=${QUARTUS_BIN:-$(sed -n 's/^Q13 *= *//p' site.mk)}
# DeMiSTify only remakes the .qsf when the file list changes, not when the
# board's tcl does, so always start from a fresh project.
rm -f "$CORE/$BOARD"/*.qsf "$CORE/$BOARD"/*.qpf "$CORE/$BOARD"/*_files.tcl
if [[ -x $QBIN/quartus_sh ]]; then
	make -s -C "$CORE" init BOARD="$BOARD"
	grep -q "0 errors" "$CORE/$BOARD/init.log"
else
	echo "quartus_sh not found in '$QBIN': generating the file list only"
	mkdir -p "$CORE/$BOARD"
	(cd "$CORE/$BOARD" && bash ../DeMiSTify/Scripts/expandtemplate_quartus.sh ../ ../project_files.rtl \
		>"${PROJECT}_${BOARD}_files.tcl")
	INIT_ONLY=1
fi

step "GHDL elaboration of the generated toplevel"
scripts/lint_core.sh "$CORE" "$PROJECT"
((INIT_ONLY)) && exit 0

step "Quartus compile"
make -s -C "$CORE" compile BOARD="$BOARD"
RBF=$CORE/$BOARD/output_files/${PROJECT}_${BOARD}.rbf
ls -l "$RBF"

step "fitted pins vs $BOARD pin assignments"
python3 scripts/verify_pins.py --strict "$CORE/$BOARD/output_files/${PROJECT}_${BOARD}.pin" \
	"Board/$BOARD/${BOARD}_pins.tcl"

step "BBC ROM"
if [[ ! -f $ROM ]]; then
	rm -rf build/mist-binaries
	git clone -q --depth 1 --filter=blob:none --sparse \
		https://github.com/mist-devel/mist-binaries build/mist-binaries
	git -C build/mist-binaries sparse-checkout set cores/bbc
fi

step "CF card"
scripts/make_cfcard.sh --core "${PROJECT,,}" --rbf "$RBF" --out build/cfcard --rom "$ROM"
