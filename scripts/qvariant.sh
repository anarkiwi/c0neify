#!/usr/bin/env bash
# Map (and optionally fit) a variant of a generated Quartus project.
#   qvariant.sh [--fit MINUTES] PROJDIR REVISION NAME [QSF_LINE]...
# Copies PROJDIR without its databases and outputs to PROJDIR_NAME, appends
# the QSF_LINEs to REVISION.qsf, runs quartus_map (and quartus_fit, killed
# after MINUTES) through quartus_run.sh, and prints their summaries.
#   QUARTUS_BIN overrides the Quartus bin directory (default 13.1).
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
usage() {
	sed -n '3p' "$0" | sed 's/^# \{0,1\}//' >&2
	exit 2
}
FIT=0
if [[ ${1:-} == --fit ]]; then
	(($# >= 2)) || usage
	FIT=$2
	shift 2
fi
(($# >= 3)) || usage
SRC=$(realpath -- "$1") REV=$2 NAME=$3
shift 3
[[ -f $SRC/$REV.qsf ]] || {
	echo "no $REV.qsf in $SRC" >&2
	exit 2
}
Q=${QUARTUS_BIN:-/opt/altera/13.1/quartus/bin}
DST=${SRC}_$NAME
rm -rf -- "$DST"
mkdir -p "$DST"
find "$SRC" -mindepth 1 -maxdepth 1 ! -name db ! -name incremental_db ! -name output_files \
	-exec cp -a -t "$DST" {} +
{
	echo
	printf '%s\n' "$@"
} >>"$DST/$REV.qsf"
cd "$DST"

stage() {
	local t0=$SECONDS rc=0
	printf '[%s] %s %s: start\n' "$(date +%T)" "$NAME" "$1"
	timeout --signal=KILL "$2" "$HERE/quartus_run.sh" "$Q/$1" \
		--read_settings_files=on --write_settings_files=off "$REV" -c "$REV" >"$1.log" 2>&1 || rc=$?
	printf '[%s] %s %s: rc=%d after %ds\n' "$(date +%T)" "$NAME" "$1" "$rc" $((SECONDS - t0))
	return "$rc"
}
stage quartus_map 60m
cat "output_files/$REV.map.summary"
((FIT)) || exit 0
stage quartus_fit "${FIT}m"
cat "output_files/$REV.fit.summary"
