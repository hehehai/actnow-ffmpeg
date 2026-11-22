# actnow-ffmpeg

The LGPL ffmpeg that ships inside the ActNow apps (Refto, CaptionCraft,
Paralign, Onda): one build script, one key, one prebuilt tarball per key
on this repository's [releases](https://github.com/hehehai/actnow-ffmpeg/releases).

- **What**: FFmpeg 8.1.3 for macOS 15+ on Apple silicon (arm64), as small
  `ffmpeg`/`ffprobe` executables and the `libav*`/`libsw*` dylibs they load
  by `@rpath` (relinkable). zimg, Opus, LAME and dav1d are linked into the
  dylibs statically; VideoToolbox and AudioToolbox for hardware H.264/HEVC/
  ProRes and AAC. Every decoder, demuxer and parser; only the encoders,
  muxers and filters the apps use (see `SLIM` in the script).
- **Licence**: LGPL-2.1-or-later. Configured with `--disable-gpl
  --disable-nonfree`, no x264/x265/fdk-aac; the build fails if `ffmpeg -L`
  is not LGPL or the configuration enables GPL, version3 or nonfree parts.
  The tarball carries the licence texts (`licenses/`); each release carries
  the corresponding source (`actnow-ffmpeg-source-<key>.tar`: the five
  upstream archives unchanged, the script, a README). The scripts in this
  repository are MIT ([LICENSE](LICENSE)).
- **Signing**: the files are signed ad hoc only. An app signs them again
  with its own Developer ID when it is built (MyGo's `macos.contents`
  puts `bin/*` in `Contents/Helpers` and `lib/*` in `Contents/Frameworks`);
  no signing identity is in the tarball.

## The key

`scripts/build-ffmpeg-lgpl.sh hash` prints the key, for example
`slim-shared-7100d8774f7e69dc`: the variant and the first 16 hex digits of
the SHA-256 of the script's code (comment lines, blank lines and the
`source` step left out) and the variant. Versions, source checksums,
configure flags, patches and steps are all in the script, so any change
to them is a new key; rewording a comment is not.

## Using it in an app

Each app keeps a **byte-identical** copy of `scripts/build-ffmpeg-lgpl.sh`
(the key is computed from it) and its own `scripts/fetch-ffmpeg.sh`, which
looks for the build of that key in its cache, then in the pins file, and
only then builds it. Pin the release in the app's `ffmpeg-prebuilt.txt`:

```
<key> <sha256 of ffmpeg-<key>.tar.xz> https://github.com/hehehai/actnow-ffmpeg/releases/download/<key>/ffmpeg-<key>.tar.xz
```

The line for each release is in its notes and `scripts/release.sh pin`.
The tarball holds one directory, `<key>/`, with `bin/`, `lib/`,
`licenses/` and `manifest.json` (the key, sources, configure line,
toolchain and the SHA-256 of every file in `bin/` and `lib/`).

## Building and publishing

On macOS on Apple silicon (Xcode command line tools; `pkg-config`, the
rest of the build tools come from Homebrew or are built from pinned
sources under `.cache/`):

```sh
scripts/release.sh build -j 4   # .cache/ffmpeg/<key>, then out/<key>/
scripts/release.sh publish      # GitHub release <key> (gh)
```

To change the build: edit `scripts/build-ffmpeg-lgpl.sh` here, build and
publish the new key, then copy the script into each app with the new pin
line (and update the app's licence notes if a version changed).

To rebuild from the corresponding source alone: unpack
`actnow-ffmpeg-source-<key>.tar` and run
`./build-ffmpeg-lgpl.sh build --src sources --work work --out out`.
