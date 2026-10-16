#!/usr/bin/env bash
# Assemble a NewBoot core directory OUT/c1dcores/<core>/.
# Usage: make_cfcard.sh --core NAME --rbf PATH --out DIR [--icon select.raw]
#          [--support-rbf PATH] [--support-bin PATH] [--target-rbf PATH]
#          [--rom FILE]... [--reference DIR] [--strict]
#   Support files not given explicitly come from reference/C1minimigV201_build.zip
#   when present, otherwise a zero-byte <name>.MISSING placeholder is written.
#   Exit 3 with --strict if any placeholder was written.
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REF=${REFERENCE_DIR:-$HERE/../reference}
BUILD_ZIP=C1minimigV201_build.zip
FILES=(select.raw extender.rbf support.rbf support.bin target.rbf)
SUPPORT=(support.rbf support.bin target.rbf)

usage() {
	[[ -n ${1-} ]] && printf 'make_cfcard: %s\n' "$1" >&2
	sed -n '2,9s/^# \{0,1\}//p' "$0" >&2
	exit 2
}
die() {
	printf 'make_cfcard: %s\n' "$*" >&2
	exit 1
}

# zip_extract ZIP DEST NAME...: extract members whose basename matches NAME
# case-insensitively to DEST/NAME; prints NAME<TAB>MEMBER per extracted file.
zip_extract() {
	python3 -I - "$@" <<'PY'
import posixpath, shutil, sys, zipfile

zp, dest, *names = sys.argv[1:]
with zipfile.ZipFile(zp) as z:
    files = [i for i in z.infolist() if not i.is_dir()]
    hits = {n: [i for i in files if posixpath.basename(i.filename).lower() == n.lower()] for n in names}
    bad = {n: h for n, h in hits.items() if len(h) > 1}
    for n, h in bad.items():
        print(f"{zp}: {n} is ambiguous: " + ", ".join(i.filename for i in h), file=sys.stderr)
    if bad:
        sys.exit(1)
    for n, h in hits.items():
        if h:
            with z.open(h[0]) as src, open(f"{dest}/{n}", "wb") as dst:
                shutil.copyfileobj(src, dst)
            print(f"{n}\t{h[0].filename}")
PY
}

core='' out='' strict=0
roms=()
declare -A SRC=() FROM=()
while (($#)); do
	k=$1
	shift
	case $k in
	--strict)
		strict=1
		continue
		;;
	-h | --help) usage ;;
	esac
	(($#)) || usage "$k needs a value"
	v=$1
	shift
	case $k in
	--core) core=$v ;;
	--out) out=$v ;;
	--rbf) SRC[extender.rbf]=$v ;;
	--icon) SRC[select.raw]=$v ;;
	--support-rbf) SRC[support.rbf]=$v ;;
	--support-bin) SRC[support.bin]=$v ;;
	--target-rbf) SRC[target.rbf]=$v ;;
	--rom) roms+=("$v") ;;
	--reference) REF=$v ;;
	*) usage "unknown option $k" ;;
	esac
done
[[ -n $core && -n $out && -v SRC[extender.rbf] ]] || usage "--core, --rbf and --out are required"
[[ $core =~ ^[[:alnum:]._-]+$ && $core != . && $core != .. ]] || die "invalid core name: $core"
for f in "${SRC[@]}" "${roms[@]}"; do
	[[ -f $f ]] || die "no such file: $f"
done

dest=$out/c1dcores/$core
mkdir -p -- "$dest"

need=()
for f in "${SUPPORT[@]}"; do
	[[ -v SRC[$f] ]] || need+=("$f")
done
if ((${#need[@]})) && [[ -f $REF/$BUILD_ZIP ]]; then
	got=$(zip_extract "$REF/$BUILD_ZIP" "$dest" "${need[@]}")
	while IFS=$'\t' read -r f m; do
		[[ -n $f ]] && FROM[$f]=$BUILD_ZIP:$m
	done <<<"$got"
fi

row() { printf '%-14s %-12s %s\n' "$@"; }
row FILE STATUS SOURCE
placeholders=0
for f in "${FILES[@]}"; do
	if [[ -v SRC[$f] ]]; then
		cp -- "${SRC[$f]}" "$dest/$f"
		FROM[$f]=${SRC[$f]}
	fi
	if [[ -v FROM[$f] ]]; then
		rm -f -- "$dest/$f.MISSING"
		row "$f" copied "${FROM[$f]}"
	else
		rm -f -- "$dest/$f"
		: >"$dest/$f.MISSING"
		row "$f" placeholder "$f.MISSING"
		placeholders=$((placeholders + 1))
	fi
done
for f in "${roms[@]}"; do
	cp -- "$f" "$dest/"
	row "${f##*/}" copied "$f"
done
printf '%s: %d placeholder(s)\n' "$dest" "$placeholders"
((strict && placeholders)) && exit 3
exit 0
