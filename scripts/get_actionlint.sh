#!/usr/bin/env bash
# Fetch the static actionlint binary from its GitHub release into build/tools.
#   get_actionlint.sh [VERSION]
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
VERSION=${1:-1.7.7}
DEST=$ROOT/build/tools
if [[ -x $DEST/actionlint ]] && "$DEST/actionlint" -version | grep -qx "$VERSION"; then
	exit 0
fi
mkdir -p "$DEST"
url=https://github.com/rhysd/actionlint/releases/download/v$VERSION/actionlint_${VERSION}_linux_amd64.tar.gz
curl -fsSL "$url" | tar -xz -C "$DEST" actionlint
"$DEST/actionlint" -version | head -1
