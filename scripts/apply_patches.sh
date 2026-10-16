#!/usr/bin/env bash
# Apply patches/<submodule path>/*.patch to each submodule on a local branch
# "cone_ext" based on the commit the superproject pins. Idempotent.
#   apply_patches.sh [SUBMODULE_PATH]...   (default: every patched submodule)
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
BRANCH=cone_ext

if (($#)); then
	subs=("$@")
else
	mapfile -t subs < <(find patches -name '*.patch' -printf '%h\n' | sed 's|^patches/||' | sort -u)
fi

for sub in "${subs[@]}"; do
	base=$(git ls-files -s -- "$sub" | cut -d" " -f2)
	mapfile -t series < <(printf '%s\n' "patches/$sub"/*.patch | sort)
	git submodule update --init -q -- "$sub"
	git -C "$sub" checkout -q -B "$BRANCH" "$base"
	git -C "$sub" -c user.name=cone-demistify -c user.email=cone-demistify@localhost \
		am -q --whitespace=nowarn --committer-date-is-author-date "${series[@]/#/$ROOT/}"
	printf '%s: %s on %s + %d patches\n' "$sub" "$BRANCH" "${base:0:12}" "${#series[@]}"
done
