# Setup

Builds the vulnerable FFmpeg, clones the PoC, generates an exploit AVI, and
builds the Qt player.

## Requirements

- Ubuntu 20.04 or Lubuntu 20.04 (glibc 2.31)
- 2 GB RAM, 8 GB disk
- Network access for apt and git
- sudo

The glibc version is not optional. The PoC's calibration targets glibc 2.31.
On other distributions the heap layout differs and the payload will not fire.

## Quick start

    git clone https://github.com/Shellmates/PixelSmash
    cd PixelSmash
    chmod +x setup.sh
    ./setup.sh

`setup.sh` runs three steps:

1. `lab/setup_lab.sh` — installs build dependencies, builds FFmpeg 8.0.1
   from source into `/usr/local`, clones the PoC into `exploit/`. Requires
   sudo. Takes 10–20 minutes.
2. `lab/prepare_payload.sh "xcalc &"` — calibrates against the fresh FFmpeg
   and generates `lab/vids/xcalc.avi`. No root needed.
3. `player/compile.sh` — builds the Qt player into `player/build/`.
   Installs `qtbase5-dev` if missing.

## Manual steps

If you prefer to run each step separately:

    sudo lab/setup_lab.sh
    lab/prepare_payload.sh "xcalc &"
    player/compile.sh

## Verifying the build

After step 1:

    /usr/local/bin/ffmpeg -version 2>&1 | head -1
    # ffmpeg version n8.0.1 ...

    /usr/local/bin/ffmpeg -decoders 2>/dev/null | grep magicyuv
    #  VFS..D magicyuv   MagicYUV video

    ldd /usr/local/bin/ffmpeg | grep libav
    # libavcodec.so.62 => /usr/local/lib/libavcodec.so.62
    # libavutil.so.60  => /usr/local/lib/libavutil.so.60
    # ...


## ASLR

The exploit requires ASLR to be disabled. This is a per-boot setting that
resets on reboot. Disable it before every demo:

    sudo sysctl -w kernel.randomize_va_space=0
    cat /proc/sys/kernel/randomize_va_space   # must print 0

Re-enable after the demo:

    sudo sysctl -w kernel.randomize_va_space=2

## Important constraints

- **Do not change the AVI path** used during calibration. The path string is
  baked into the exploit. If you move the repo, regenerate the AVI.
- **Do not add flags to the ffmpeg command.** The player passes exactly
  `-i <file> -f null -`. Adding `-hide_banner`, `-loglevel`, or anything else
  shifts the heap layout and the payload will not fire.
- **The vulnerable build lives in `/usr/local`.** It does not replace the
  system ffmpeg package. `/usr/bin/ffmpeg`, if present, is unaffected.

## Layout

    lab/ffmpeg-src/        FFmpeg 8.0.1 source
    /usr/local/bin/ffmpeg  Vulnerable build
    /usr/local/lib/        Vulnerable shared libraries
    exploit/               PoC scripts
    lab/vids/              Generated exploit AVIs (gitignored)
    player/build/          Qt player binary (gitignored)
