#!/usr/bin/env bash
#
# lab/setup_lab.sh
#
# One-time setup for the PixelSmash (CVE-2026-8461) lab.
# Builds vulnerable FFmpeg 8.0.1 from source, installs to /usr/local,
# and clones the exploit PoC into exploit/.
#
# Run once per fresh VM. Requires sudo.
#
#   sudo lab/setup_lab.sh
#
# After this completes, run lab/prepare_paylaods.sh to generate AVIs.

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

FFMPEG_TAG="n8.0.1"
FFMPEG_SRC="$REPO_ROOT/lab/ffmpeg-src"
FFMPEG_INSTALL="/usr/local"
POC_DIR="$REPO_ROOT/exploit"
POC_REPO="https://github.com/Y5neKO/CVE-2026-8461-EXP.git"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

info() { echo -e "\n\033[1;34m[*]\033[0m $*"; }
ok()   { echo -e "\033[1;32m[+]\033[0m $*"; }
die()  { echo -e "\033[1;31m[✗]\033[0m $*" >&2; exit 1; }

[ "$EUID" -eq 0 ] || die "Run with sudo: sudo $0"

# ---------------------------------------------------------------------------
# Step 1 — glibc check
# ---------------------------------------------------------------------------

info "Checking glibc..."
GLIBC=$(ldd --version | head -1)
echo "    $GLIBC"
case "$GLIBC" in
    *2.31*) ok "glibc 2.31 — matches PoC target." ;;
    *) die "This lab targets Ubuntu 20.04 (glibc 2.31). Detected: $GLIBC" ;;
esac

# ---------------------------------------------------------------------------
# Step 2 — Build dependencies (no SDL, no ffplay)
# ---------------------------------------------------------------------------

info "Installing build dependencies..."
apt update
apt install -y \
    build-essential gcc make git gdb pkg-config nasm yasm \
    zlib1g-dev libssl-dev x11-apps cmake qtbase5-dev qt5-qmake

ok "Dependencies installed."

# ---------------------------------------------------------------------------
# Step 3 — Build FFmpeg 8.0.1
# ---------------------------------------------------------------------------

if [ -d "$FFMPEG_SRC" ]; then
    info "Removing existing FFmpeg source at $FFMPEG_SRC..."
    rm -rf "$FFMPEG_SRC"
fi

info "Cloning FFmpeg $FFMPEG_TAG..."
git clone --branch "$FFMPEG_TAG" --depth 1 \
    https://git.ffmpeg.org/ffmpeg.git "$FFMPEG_SRC"

cd "$FFMPEG_SRC"

info "Configuring FFmpeg..."
./configure \
    --enable-gpl \
    --enable-debug \
    --disable-optimizations \
    --enable-shared \
    --disable-static 

info "Building FFmpeg (10-20 minutes)..."
make -j"$(nproc)"

info "Installing FFmpeg to $FFMPEG_INSTALL..."
make install
ldconfig
hash -r

# Verify ffmpeg exists
[ -x "$FFMPEG_INSTALL/bin/ffmpeg" ] || die "ffmpeg not installed."

ok "FFmpeg: $("$FFMPEG_INSTALL/bin/ffmpeg" -version 2>&1 | head -1)"


#---------------------------------------------------------------------------
#Step 4 — Clone PoC
# ---------------------------------------------------------------------------

if [ -d "$POC_DIR/.git" ]; then
    info "PoC already cloned — skipping."
else
    info "Cloning PoC into $POC_DIR..."

    TMP_README=""
    if [ -f "$POC_DIR/README.md" ]; then
        TMP_README="$(mktemp)"
        mv "$POC_DIR/README.md" "$TMP_README"
    fi

    TMP_CLONE="$(mktemp -d)"
    git clone "$POC_REPO" "$TMP_CLONE/poc"
    shopt -s dotglob
    mv "$TMP_CLONE/poc"/* "$POC_DIR/"
    shopt -u dotglob
    rm -rf "$TMP_CLONE"

    if [ -f "$POC_DIR/README.md" ]; then
        mv "$POC_DIR/README.md" "$POC_DIR/POC_README.md"
    fi
    if [ -n "$TMP_README" ]; then
        mv "$TMP_README" "$POC_DIR/README.md"
    fi

    ok "PoC cloned."
fi

[ -f "$POC_DIR/auto_calibrate_nosym.py" ] \
    || die "auto_calibrate_nosym.py missing from $POC_DIR."
[ -f "$POC_DIR/exploit_cve_2026_8461.py" ] \
    || die "exploit_cve_2026_8461.py missing from $POC_DIR."

ok "PoC files present."

# ---------------------------------------------------------------------------
# Step 5 — Summary
# ---------------------------------------------------------------------------

cat <<EOF

============================================================
  Lab setup complete.
============================================================

  Vulnerable FFmpeg:  $FFMPEG_INSTALL/bin/ffmpeg
  FFmpeg source:      $FFMPEG_SRC
  PoC:                $POC_DIR

Next steps:

  1. Build the player:
       cd $REPO_ROOT/player
       mkdir -p build && cd build
       cmake ..
       make -j\$(nproc)

  2. Generate an exploit AVI:
       $REPO_ROOT/lab/prepare_paylaods.sh "xcalc &"

  3. Disable ASLR before the demo:
       sudo sysctl -w kernel.randomize_va_space=0

  4. Verify from the CLI:
       LD_LIBRARY_PATH=$FFMPEG_INSTALL/lib \\
         $FFMPEG_INSTALL/bin/ffmpeg -i <avi> -f null -

IMPORTANT:
  - The vulnerable build lives in $FFMPEG_INSTALL (e.g. /usr/local).
    It does NOT replace any system ffmpeg package.
  - ASLR resets on reboot. Re-disable before every demo.
  - Generated AVIs are tied to their exact path. Do not move them.

============================================================
EOF
