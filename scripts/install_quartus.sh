#!/usr/bin/env bash
# Non-interactive install of Quartus II 13.1 Web Edition (Cyclone only) from
# reference/, falling back to 13.0sp1 when only that installer is present,
# then prune the tree to what the quartus_sh flow needs.
# Usage: install_quartus.sh [--prefix DIR] [--reference DIR] [--dry-run] [--prune-only]
#   --dry-run     print every system-changing command instead of running it
#   --prune-only  only prune an existing tree at --prefix
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
VERSIONS=(13.1.0.162:13.1 13.0.1.232:13.0sp1)
PREFIX=
REF=${REFERENCE_DIR:-$HERE/../reference}
DRY=0
PRUNE_ONLY=0

I386_PKGS=(libc6 libncurses5 libstdc++6 libpng12-0 libfreetype6 libsm6 libxrender1
	libfontconfig1 libxext6 libxtst6 libxi6 libgtk2.0-0)
# BitRock component ids; the installer still installs whatever the .qdz files
# beside it provide.
DISABLE_COMPONENTS=quartus_help,modelsim_ase,modelsim_ae
PRUNE_PATHS=(modelsim_ase modelsim_ae nios2eds quartus/common/help docs)
DEVINFO=quartus/common/devinfo
FAMILY_RE='^(acex|apex|arria|cyclone|excalibur|flex|hardcopy|max|mercury|stratix)'
KEEP_FAMILY_RE='^cyclone(ii|iii|iiils|iv[a-z]*)$'

usage() {
	sed -n '2,6s/^# \{0,1\}//p' "$0" >&2
	exit 2
}
step() { printf '\n== [%s] %s\n' "$1" "$2"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
run() {
	local a
	printf '+'
	for a in "$@"; do
		[[ $a =~ ^[[:alnum:]_./:=,+@%-]+$ ]] && printf ' %s' "$a" || printf ' %q' "$a"
	done
	printf '\n'
	((DRY)) || "$@"
}

while (($#)); do
	case $1 in
	--prefix)
		PREFIX=${2:?--prefix needs DIR}
		shift
		;;
	--reference)
		REF=${2:?--reference needs DIR}
		shift
		;;
	--dry-run) DRY=1 ;;
	--prune-only) PRUNE_ONLY=1 ;;
	*) usage ;;
	esac
	shift
done
REF=$(realpath -m -- "$REF")
for v in "${VERSIONS[@]}"; do
	QUARTUS_VERSION=${v%%:*}
	RUNFILE=$REF/QuartusSetupWeb-$QUARTUS_VERSION.run
	[[ -f $RUNFILE ]] && break
done
QDZ=$REF/cyclone_web-$QUARTUS_VERSION.qdz
PREFIX=$(realpath -m -- "${PREFIX:-/opt/altera/${v#*:}}")

ROOT=()
((EUID == 0)) || ROOT=("${SUDO:-sudo}")
writable_ancestor() {
	local d=$1
	until [[ -e $d ]]; do d=$(dirname -- "$d"); done
	[[ -w $d ]]
}
PRIV=()
writable_ancestor "$PREFIX" || PRIV=("${ROOT[@]}")

has_candidate() { apt-cache policy "$1" 2>/dev/null | grep -Eq 'Candidate: [^(]'; }

apt_deps() {
	run "${ROOT[@]}" dpkg --add-architecture i386
	run "${ROOT[@]}" apt-get update
	local p c have=() missing=()
	if ((DRY)); then
		have=("${I386_PKGS[@]/%/:i386}")
		printf '(each package is checked with apt-cache policy, also as <name>t64, before installing)\n'
	else
		for p in "${I386_PKGS[@]}"; do
			for c in "$p" "${p}t64"; do
				has_candidate "$c:i386" && have+=("$c:i386") && continue 2
			done
			missing+=("$p")
		done
	fi
	((${#have[@]})) && run "${ROOT[@]}" env DEBIAN_FRONTEND=noninteractive \
		apt-get install -y --no-install-recommends "${have[@]}"
	((${#missing[@]} == 0)) ||
		warn "no i386 candidate for: ${missing[*]} (GUI only; the quartus_sh flow does not need them)"
}

install_quartus() {
	[[ -f $QDZ ]] || warn "$QDZ absent: the install will have no Cyclone device support"
	run chmod +x "$RUNFILE"
	printf 'running installer into %s (no progress output; several minutes)\n' "$PREFIX"
	run "${PRIV[@]}" "$RUNFILE" --mode unattended --unattendedmodeui none \
		--installdir "$PREFIX" --disable-components "$DISABLE_COMPONENTS"
}

prune() {
	if [[ ! -d $PREFIX ]]; then
		((DRY)) || {
			printf 'no Quartus tree at %s\n' "$PREFIX" >&2
			exit 1
		}
		printf 'would remove under %s: %s, and %s/* families matching %s but not %s\n' \
			"$PREFIX" "${PRUNE_PATHS[*]}" "$DEVINFO" "$FAMILY_RE" "$KEEP_FAMILY_RE"
		return
	fi
	local p d n i=0 targets=()
	for p in "${PRUNE_PATHS[@]}"; do
		[[ -e $PREFIX/$p ]] && targets+=("$PREFIX/$p")
	done
	for d in "$PREFIX/$DEVINFO"/*/; do
		[[ -d $d ]] || continue
		d=${d%/} n=${d##*/}
		[[ $n =~ $FAMILY_RE && ! $n =~ $KEEP_FAMILY_RE ]] && targets+=("$d")
	done
	printf 'size before: %s\n' "$(du -sh -- "$PREFIX" | cut -f1)"
	for d in "${targets[@]}"; do
		printf '[%d/%d] ' $((++i)) "${#targets[@]}"
		run "${PRIV[@]}" rm -rf -- "$d"
	done
	printf 'size after: %s\n' "$(du -sh -- "$PREFIX" | cut -f1)"
}

if ((PRUNE_ONLY)); then
	step 1/1 "prune $PREFIX"
	prune
	exit 0
fi
if [[ ! -f $RUNFILE ]]; then
	printf 'installer not present, skipping (%s)\n' "$REF/QuartusSetupWeb-{13.1.0.162,13.0.1.232}.run"
	exit 0
fi
step 1/4 "i386 runtime libraries"
apt_deps
step 2/4 "Quartus II $QUARTUS_VERSION installer"
install_quartus
step 3/4 "prune $PREFIX"
prune
step 4/4 "verify"
run "$PREFIX/quartus/bin/quartus_sh" --version
