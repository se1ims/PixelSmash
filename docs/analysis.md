# Analysis — CVE-2026-8461 (PixelSmash)

## Summary

Out-of-bounds write in FFmpeg's MagicYUV decoder (`libavcodec/magicyuv.c`).
A crafted AVI file causes `magy_decode_slice()` to write past the end of an
allocated plane buffer. Under the right conditions, this corrupts an
adjacent `AVBuffer` struct, allowing a function pointer hijack.

- **CVE:** CVE-2026-8461
- **Component:** `libavcodec` / MagicYUV decoder
- **Class:** CWE-787 (out-of-bounds write)
- **Fixed in:** FFmpeg 8.1.2
- **CVSS:** 8.8

## Root cause

`magy_decode_slice()` uses the slice height (`sheight`) as the loop bound
when writing into the Cb/Cr output plane, but the plane buffer is allocated
using the frame height (`height`). On the last slice of a specially crafted
frame, the loop writes past the end of the allocation.

The bug was introduced when the decoder gained support for slices and the
bounds check was not updated to account for the difference between slice
height and frame height.

## Primitive

The write is a controlled byte pattern of bounded length, landing in a
subsequently allocated `AVBuffer` struct. The exploit shapes the heap so
that this struct is within the write range, overwrites `AVBuffer.free`
with the address of `system()`, and overwrites `AVBuffer.opaque` with the
address of the command string. When the frame is freed, `av_buffer_unref()`
calls `system(cmd)`.

## Requirements for exploitation

- **ASLR disabled.** The PoC does not include an info leak, so the `system()`
  address and the command string address must be predictable.
- **Matching glibc.** The heap layout depends on glibc's allocator.
- **Matching FFmpeg build.** The offsets are specific to a build. The
  supplied calibration targets FFmpeg 8.0.1 with `--disable-optimizations
  --enable-debug --enable-shared` on glibc 2.31.
- **The AVI path is fixed.** The path string is part of the heap layout.

## Trigger surface

The exploit fires when the file is **decoded**, not when it is probed:

| Command | Fires? |
|---|---|
| `ffmpeg -i evil.avi -f null -` | Yes |
| `ffmpeg -i evil.avi out.mp4` | Yes |
| Media player using libavcodec | Yes |
| Thumbnail generator | Yes |
| `ffmpeg -i evil.avi` (no output) | No |
| `ffprobe evil.avi` | No |

The distinction matters because it defines the real-world attack surface:
any automated pipeline that decodes untrusted media — transcoders, preview
generators, media scanners — is exposed.

## Affected software

Applications that bundle a vulnerable FFmpeg:

- Media servers: Jellyfin, Emby, Nextcloud
- Players: mpv, Kodi, and players using system FFmpeg
- Thumbnail generators: ffmpegthumbnailer and derivatives
- Transcoding pipelines: any service calling ffmpeg on uploaded media

Applications that bundle FFmpeg 8.1.2 or later are not affected.

## Mitigation

- **Patch.** Upgrade to FFmpeg 8.1.2 or later.
- **Sandbox media processing.** Run decoding in a container with no network
  and no credentials.
- **Disable automatic thumbnails** for untrusted directories.
- **Validate uploads.** Reject files that fail strict format checks.

## What this lab does not cover

- **ASLR-on exploitation.** Would require a separate info leak.
- **aarch64.** The heap layout differs; the calibration is x86_64 only.
- **Remote delivery.** The exploit file must reach the target by some other
  means (download, shared folder, upload).

## References

- NVD: CVE-2026-8461
- FFmpeg security advisory
- Upstream PoC: https://github.com/Y5neKO/CVE-2026-8461-EXP
