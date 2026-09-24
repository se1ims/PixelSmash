selim@debian:~/Desktop/pixelsmash-cve-2026-8461$ cat README.md
# CVE-2026-8461 — PixelSmash

A working proof-of-concept for CVE-2026-8461, an out-of-bounds write in
FFmpeg's MagicYUV decoder. Includes a lab harness that builds a vulnerable
FFmpeg from source, and a small Qt player used to demonstrate the exploit
in a video-player context.

**For research and education only. Do not use against systems you do not own.**

## Quick start

    git clone https://github.com/Shellmates/PixelSmash.git
    cd PixelSmash
    sudo setup.sh
    lab/prepare_payloads.sh "YOUR_COMMAD_GOES_HERE"

Before running the demo, disable ASLR:

    sudo sysctl -w kernel.randomize_va_space=0

Then open the generated AVI in the player:

    player/build/ffplayer

## Layout

- `exploit/` — the PoC (calibration + AVI generator) by Y5neKO
- `lab/`     — scripts that build the environment and generate AVIs
- `player/`  — a small Qt GUI player used as a demo harness
- `docs/`    — vulnerability analysis and setup/demo guides

## References

- NVD: https://nvd.nist.gov/vuln/detail/cve-2026-8461
- FFmpeg security advisory: https://github.com/advisories/GHSA-qff7-4q6c-m8h6
- Vendor fix: FFmpeg 8.1.2

