#!/usr/bin/env bash
# Regenerate patches/<submodule>/ on top of the commits the superproject pins:
#   DeMiSTify            Board/cone_ext and templates/cone_ext from this repo
#   cores/BBC_DemiSTify  demistify_joybits, cone_ext/ (template + overlay
#                        diff), overrides.c port to DeMiSTify's diskimage
# Author and dates are fixed so unchanged inputs give identical patches.
#   export_patches.sh [--check]   (--check: fail if any series is out of date)
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
CHECK=0
[[ ${1:-} == --check ]] && CHECK=1
tmp=$(mktemp -d)
worktrees=()
cleanup() {
	local w
	for w in "${worktrees[@]}"; do git -C "${w%%:*}" worktree remove --force "${w#*:}" >/dev/null 2>&1 || true; done
	rm -rf "$tmp"
}
trap cleanup EXIT
export GIT_AUTHOR_NAME="Josh Bailey" GIT_AUTHOR_EMAIL="josh@overlyspecific.com"
export GIT_COMMITTER_NAME=$GIT_AUTHOR_NAME GIT_COMMITTER_EMAIL=$GIT_AUTHOR_EMAIL
export GIT_AUTHOR_DATE="2026-10-16T00:00:00Z"
export GIT_COMMITTER_DATE=$GIT_AUTHOR_DATE

# start SUBMODULE: worktree of the pinned commit at $wt
start() {
	base=$(git ls-files -s -- "$1" | cut -d" " -f2)
	wt=$tmp/${1//\//_}
	git -C "$1" worktree add -q --detach "$wt" "$base"
	worktrees+=("$1:$wt")
}
commit() { git -C "$wt" add -A && git -C "$wt" commit -q -m "$1"; }

# finish SUBMODULE: format-patch, then write or compare patches/SUBMODULE
finish() {
	local out=patches/$1
	git -C "$wt" format-patch -q --no-signature --zero-commit -o "$wt.patches" "$base"
	if ((CHECK)); then
		diff -r "$out" "$wt.patches" >/dev/null || {
			echo "$out is out of date: run scripts/export_patches.sh" >&2
			exit 1
		}
		echo "$out up to date"
	else
		rm -rf "$out"
		mkdir -p "$out"
		cp "$wt.patches"/*.patch "$out/"
		ls "$out"
	fi
}

start DeMiSTify
for dir in Board/cone_ext templates/cone_ext; do
	mkdir -p "$wt/$dir"
	cp -- "$dir"/* "$wt/$dir/"
	case $dir in
	Board/*) commit "Board: add cone_ext, the C-One FPGA Extender (Cyclone III EP3C25E144C8)

The extender reaches keyboard, mouse, joysticks and storage only through
the 16 vid lines to the C-One's ACEX 1K30. cone_mm_link speaks the
Minimig V2.01 link there, so Minimig's prebuilt 1k30/1k100 images are
used unchanged, and cone_sd_ata answers substitute_mcu's SD commands
with ATA transfers to the C-One's CF card through that link. Its
simulation is maintained in the cone-demistify project." ;;
	*) commit "templates: add cone_ext toplevel template" ;;
	esac
done
finish DeMiSTify

start cores/BBC_DemiSTify
sed -i 's/^constant demistify_button1 : integer := 4;/constant demistify_joybits : integer := 8;\n\n&/' \
	"$wt/demistify_config_pkg.vhd"
commit "demistify_config_pkg: define demistify_joybits

Current DeMiSTify board templates size their joystick words with
demistify_joybits."
mkdir -p "$wt/cone_ext"
cp templates/cone_ext/cone_ext_top.vhd "$wt/cone_ext/"
patch -s "$wt/cone_ext/cone_ext_top.vhd" overlays/BBC_DemiSTify/cone_ext_top.diff
cp overlays/BBC_DemiSTify/top.qip "$wt/cone_ext/"
commit "Add cone_ext (C-One FPGA Extender) toplevel

Guest CLOCK_27 is fed 27.09 MHz from the board PLL, so the MiST clockgen
is used unchanged. The core's SDRAM map ends at 0xDFFFF, within the
extender's 12 row bits."
sed -i 's/if(!diskimg\[0\]\.file\.size)/if(!diskimg[0].type.file.size)/' "$wt/firmware/overrides.c"
commit "firmware: follow DeMiSTify's diskimage union

struct diskimage now holds the file as type.file (DeMiSTify f94b6b9)."
finish cores/BBC_DemiSTify
