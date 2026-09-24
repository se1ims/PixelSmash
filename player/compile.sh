#!/usr/bin/env bash
#
# player/compile.sh
#
# Builds the Qt player into player/build/.
# Works no matter where you call it from.

set -euo pipefail

# Directory this script lives in (= player/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

BUILD_DIR="$SCRIPT_DIR/build"

echo "[*] Player dir:  $SCRIPT_DIR"
echo "[*] Build dir:   $BUILD_DIR"

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

cmake "$SCRIPT_DIR"
make -j"$(nproc)"

echo
echo "[+] Built: $BUILD_DIR/ffplayer"
echo
echo "    Run with:"
echo "      $BUILD_DIR/ffplayer"
