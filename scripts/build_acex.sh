#!/usr/bin/env bash
# Compile an ACEX 1K (1k30 / 1k100) Quartus project with Quartus II 9.0 Web
# Edition under Wine in Docker (docker/quartus90). The image is built from
# reference/90_quartus_free.exe on first use.
# Usage: build_acex.sh [--out DIR] [--compare FILE]... [--rebuild-image] PROJECT_DIR REVISION
#        build_acex.sh --image-only [--rebuild-image]
#   --out DIR        copy results here (default PROJECT_DIR)
#   --compare FILE   report how many bytes of REVISION.rbf differ from FILE
#   QUARTUS90_IMAGE  image name (default c0neify/quartus90); the tag is a hash of its recipe
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(dirname "$HERE")
REF=$(realpath -m -- "${REFERENCE_DIR:-$ROOT/reference}")
INSTALLER=90_quartus_free.exe
DOCKERFILE=$ROOT/docker/quartus90/Dockerfile
STAGES=(map fit asm tan)

usage() {
	sed -n '2,10s/^# \{0,1\}//p' "$0" >&2
	exit 2
}

OUT=
COMPARE=()
REBUILD=0
IMAGE_ONLY=0
ARGS=()
while (($#)); do
	case $1 in
	--out)
		OUT=${2:?--out needs DIR}
		shift
		;;
	--compare)
		COMPARE+=("${2:?--compare needs FILE}")
		shift
		;;
	--rebuild-image) REBUILD=1 ;;
	--image-only) IMAGE_ONLY=1 ;;
	-*) usage ;;
	*) ARGS+=("$1") ;;
	esac
	shift
done
((IMAGE_ONLY ? ${#ARGS[@]} == 0 : ${#ARGS[@]} == 2)) || usage

TAG=$(cat "$DOCKERFILE" "$HERE/isx_unpack.py" | sha256sum | cut -c1-12)
IMAGE=${QUARTUS90_IMAGE:-c0neify/quartus90}:$TAG

ensure_image() {
	if ((!REBUILD)) && docker image inspect "$IMAGE" >/dev/null 2>&1; then
		printf 'image %s present\n' "$IMAGE"
		return
	fi
	"$HERE/check_assets.sh" --require "$INSTALLER" >/dev/null
	local exe
	exe=$(realpath -- "$REF/$INSTALLER")
	printf 'building %s from %s\n' "$IMAGE" "$exe"
	DOCKER_BUILDKIT=1 docker build --progress=plain -f "$DOCKERFILE" \
		--build-context installer="$(dirname "$exe")" \
		--build-arg INSTALLER="$(basename "$exe")" -t "$IMAGE" "$ROOT"
}

# Runs inside the container: one Quartus executable per stage, progress on
# stderr, the finished work directory as a tar stream on stdout.
# shellcheck disable=SC2016
STAGE_SH='
rev=$1; shift; n=$#; i=0; t0=$(date +%s)
tar -x
rm -f "$rev".*.rpt "$rev".*.summary "$rev".rbf "$rev".sof "$rev".pof "$rev".wine.log
for s in "$@"; do
	i=$((i + 1)); t=$(date +%s)
	printf "[%d/%d] quartus_%s %s ... " "$i" "$n" "$s" "$rev" >&2
	if wine "$QUARTUS_BIN/quartus_$s.exe" --read_settings_files=on \
		--write_settings_files=off "$rev" -c "$rev" >>"$rev.wine.log" 2>&1; then
		printf "ok %ds\n" $(($(date +%s) - t)) >&2
	else
		printf "FAILED\n" >&2; grep -E "^(Error|Internal Error)" "$rev.wine.log" >&2 || tail -n 20 "$rev.wine.log" >&2
		tar -c .; exit 1
	fi
done
printf "done in %ds\n" $(($(date +%s) - t0)) >&2
tar -c .
'

if ((!IMAGE_ONLY)); then
	PROJECT=$(realpath -- "${ARGS[0]}")
	REV=${ARGS[1]}
	if [[ ! -f $PROJECT/$REV.qsf ]]; then
		printf 'no %s.qsf in %s\n' "$REV" "$PROJECT" >&2
		exit 1
	fi
	OUT=$(realpath -m -- "${OUT:-$PROJECT}")
fi
ensure_image
((IMAGE_ONLY)) && exit 0

mkdir -p "$OUT"
rm -f "$OUT/$REV".{fit,tan}.summary "$OUT/$REV".{rbf,sof,pof}
rc=0
tar -C "$PROJECT" --exclude=./db --exclude=./incremental_db -c . |
	docker run -i --rm "$IMAGE" sh -c "$STAGE_SH" sh "$REV" "${STAGES[@]}" |
	tar -C "$OUT" -x || rc=$?
for f in "$OUT/$REV".{fit,tan}.summary; do
	if [[ -f $f ]]; then
		grep -E '^(Fitter Status|Device|Total|Type|Slack)' "$f"
	fi
done
RBF=$OUT/$REV.rbf
if [[ -f $RBF ]]; then
	printf '%s: %d bytes\n' "$RBF" "$(stat -c %s "$RBF")"
	for f in "${COMPARE[@]}"; do
		printf 'vs %s (%d bytes): %d bytes differ\n' "$f" "$(stat -c %s "$f")" \
			"$(cmp -l -- "$RBF" "$f" 2>/dev/null | wc -l)"
	done
fi
exit "$rc"
