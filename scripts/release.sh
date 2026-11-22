#!/usr/bin/env bash
# Builds and publishes the family's prebuilt ffmpeg (README.md).
#
#   scripts/release.sh build [-j N]   # macOS on Apple silicon: out/<key>/
#   scripts/release.sh publish        # a GitHub release <key> with out/<key>/*
#   scripts/release.sh pin            # the line for an app's ffmpeg-prebuilt.txt
#
# out/<key>/ holds
#   ffmpeg-<key>.tar.xz                 the product (<key>/bin, lib, licenses,
#                                       manifest.json), what the apps'
#                                       scripts/fetch-ffmpeg.sh unpacks
#   actnow-ffmpeg-source-<key>.tar      the LGPL corresponding source: the
#                                       five archives as published, the
#                                       build script, a README
#   SHA256SUMS
# The release's tag is the key; the URL of the tarball is stable:
#   https://github.com/hehehai/actnow-ffmpeg/releases/download/<key>/ffmpeg-<key>.tar.xz
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO=hehehai/actnow-ffmpeg
BUILD="$ROOT/scripts/build-ffmpeg-lgpl.sh"
KEY="$("$BUILD" hash)"
OUT="$ROOT/out/$KEY"
URL="https://github.com/$REPO/releases/download/$KEY/ffmpeg-$KEY.tar.xz"

sha256() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

step="${1:-}"
shift || true
case "$step" in
  build)
    jobs=(-j "${JOBS:-4}")
    while (($#)); do
      case "$1" in
        -j) jobs=(-j "$2"); shift 2 ;;
        *) echo "release.sh build: unknown argument $1" >&2; exit 2 ;;
      esac
    done
    product="$ROOT/.cache/ffmpeg/$KEY"
    "$BUILD" build "${jobs[@]}" --out "$product"
    rm -rf "$OUT" && mkdir -p "$OUT"
    tar -C "$(dirname "$product")" -cJf "$OUT/ffmpeg-$KEY.tar.xz" "$KEY"
    "$BUILD" source "$OUT/actnow-ffmpeg-source-$KEY.tar"
    (cd "$OUT" && shasum -a 256 ./* | sed 's| \./| |' >SHA256SUMS)
    cat "$OUT/SHA256SUMS"
    ;;
  publish)
    [[ -f "$OUT/ffmpeg-$KEY.tar.xz" ]] || { echo "no out/$KEY: run scripts/release.sh build on the Mac first" >&2; exit 1; }
    (cd "$OUT" && shasum -a 256 -c SHA256SUMS)
    sum="$(sha256 "$OUT/ffmpeg-$KEY.tar.xz")"
    notes="$(mktemp)"
    {
      echo "The family's LGPL ffmpeg $(sed -n 's/^FFMPEG_VERSION=//p' "$BUILD") for macOS on Apple silicon, build \`$KEY\` (scripts/build-ffmpeg-lgpl.sh at $(git -C "$ROOT" rev-parse --short HEAD))."
      echo
      echo "Pin it in an app's ffmpeg-prebuilt.txt (with a byte-identical copy of scripts/build-ffmpeg-lgpl.sh):"
      echo
      echo '```'
      echo "$KEY $sum $URL"
      echo '```'
      echo
      echo "- \`ffmpeg-$KEY.tar.xz\`: bin/ffmpeg, bin/ffprobe, lib/libav*.dylib, lib/libsw*.dylib (signed ad hoc; the app signs them with its own identity), licenses/, manifest.json (sources, configure line, toolchain, SHA-256 of each file)."
      echo "- \`actnow-ffmpeg-source-$KEY.tar\`: the corresponding source (LGPL-2.1-or-later): the five source archives unchanged, the build script, a README."
    } >"$notes"
    if gh release view "$KEY" --repo "$REPO" >/dev/null 2>&1; then
      gh release upload "$KEY" --repo "$REPO" --clobber "$OUT"/*
      gh release edit "$KEY" --repo "$REPO" --notes-file "$notes"
    else
      gh release create "$KEY" --repo "$REPO" --target "$(git -C "$ROOT" rev-parse HEAD)" --title "ffmpeg $KEY" --notes-file "$notes" "$OUT"/*
    fi
    rm -f "$notes"
    echo "$KEY $sum $URL"
    ;;
  pin)
    [[ -f "$OUT/ffmpeg-$KEY.tar.xz" ]] || { echo "no out/$KEY" >&2; exit 1; }
    echo "$KEY $(sha256 "$OUT/ffmpeg-$KEY.tar.xz") $URL"
    ;;
  *)
    sed -n '2,/^set -euo/p' "$0" | sed '$d; s/^# \{0,1\}//'
    exit 2
    ;;
esac
