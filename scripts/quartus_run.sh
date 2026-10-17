#!/usr/bin/env bash
# Run a command with Quartus II 13.1 in 64-bit mode and libtbbmalloc's
# malloc replacement disabled (docs/firmware.md, "quartus_fit hang").
#   quartus_run.sh CMD [ARG]...
# Builds scripts/tbbmalloc_stub.c into an empty library with the soname
# libtbbmalloc_proxy.so.2 and preloads it, so the Quartus binaries that
# need that soname bind malloc/new to glibc. QUARTUS_64BIT=1 is the
# environment form of --64bit and reaches every tool a flow spawns.
#   TBBSTUB_DIR overrides where the library is built (default build/tools).
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SRC=$HERE/tbbmalloc_stub.c
DIR=$(realpath -m -- "${TBBSTUB_DIR:-$HERE/../build/tools}")
LIB=$DIR/libtbbmalloc_proxy.so.2
(($#)) || {
	sed -n '4p' "$0" | sed 's/^# \{0,1\}//' >&2
	exit 2
}
if [[ ! $LIB -nt $SRC ]]; then
	mkdir -p "$DIR"
	"${CC:-cc}" -shared -fPIC -Wl,-soname,libtbbmalloc_proxy.so.2 -o "$LIB" "$SRC"
fi
export QUARTUS_64BIT=1 LD_PRELOAD=$LIB${LD_PRELOAD:+:$LD_PRELOAD}
exec "$@"
