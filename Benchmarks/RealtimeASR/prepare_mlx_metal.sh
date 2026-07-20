#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

cd "$SCRIPT_DIR"
/usr/bin/swift build -c release
BUILD_BIN_DIR="$(/usr/bin/swift build -c release --show-bin-path)"
"$REPO_ROOT/script/runtime/embed_mlx_metallib.sh" "$BUILD_BIN_DIR/mlx.metallib" -

echo "$BUILD_BIN_DIR/mlx.metallib"
