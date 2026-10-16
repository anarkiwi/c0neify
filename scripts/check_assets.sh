#!/usr/bin/env bash
# Report which gated reference assets (scripts/assets.tsv) are in reference/.
# Usage: check_assets.sh [--json] [--require NAME]...
#   REFERENCE_DIR overrides the reference directory.
#   Exit 0 unless a --require'd file is missing (1) or usage is wrong (2).
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REF=$(realpath -m -- "${REFERENCE_DIR:-$HERE/../reference}")
MANIFEST=$HERE/assets.tsv

usage() {
	sed -n '2,5s/^# \{0,1\}//p' "$0" >&2
	exit 2
}

json=0
require=()
while (($#)); do
	case $1 in
	--json) json=1 ;;
	--require)
		(($# >= 2)) || usage
		require+=("$2")
		shift
		;;
	*) usage ;;
	esac
	shift
done

# Leading-byte signature per kind; "text" only rejects saved HTML pages.
valid() {
	local head
	head=$(head -c 512 -- "$2" | tr -d '\0' | tr '[:upper:]' '[:lower:]')
	[[ $head == *'<!doctype html'* || $head == *'<html'* ]] && return 1
	case $1 in
	pdf) [[ $head == %pdf-* ]] ;;
	zip) [[ $head == pk$'\003\004'* ]] ;;
	elf) [[ $head == $'\177'elf* ]] ;;
	exe) [[ $head == mz* ]] ;;
	deb) [[ $head == '!<arch>'* ]] ;;
	*) true ;;
	esac
}

rows() {
	local name kind need src unblocks size state
	while IFS=$'\t' read -r name kind need src unblocks; do
		size=''
		state=missing
		if [[ -f $REF/$name ]]; then
			size=$(stat -L -c %s -- "$REF/$name")
			state=present
			valid "$kind" "$REF/$name" || state=invalid
		fi
		printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$name" "$need" "$src" "$unblocks" "$size" "$state"
	done < <(tail -n +2 "$MANIFEST")
}

if ((json)); then
	rows | jq -Rn --arg dir "$REF" '{reference_dir: $dir, assets: [inputs | split("\t")
		| {name: .[0], need: .[1], source: .[2], unblocks: .[3], state: .[5],
		   present: (.[5] == "present"),
		   size: (if .[4] == "" then null else (.[4] | tonumber) end)}]}'
else
	printf 'reference: %s\n' "$REF"
	rows | awk -F'\t' '{ n++; p += $6 == "present"
		printf "%-8s %-8s %12s  %-36s %s\n", $6, $2, ($5 == "" ? "-" : $5), $1, $4 }
		END { printf "%d/%d present\n", p, n }'
fi

rc=0
for name in "${require[@]}"; do
	rows | awk -F'\t' -v n="$name" '$1 == n && $6 == "present" { ok = 1 } END { exit !ok }' || {
		printf 'required asset missing or invalid: %s/%s\n' "$REF" "$name" >&2
		rc=1
	}
done
exit "$rc"
