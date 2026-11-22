#!/usr/bin/env bash
# Builds the ffmpeg and ffprobe that ship inside the ActNow apps (Refto,
# CaptionCraft, Paralign, Onda): LGPL-2.1-or-later, arm64, macOS, as
# small executables and the libav*/libsw* dylibs they link (relinkable:
# the plainest way to meet the LGPL). VideoToolbox and AudioToolbox
# (hardware decode and encode, AAC), zimg (zscale: HDR → SDR), libopus,
# LAME (MP3) and dav1d (AV1 in software: M1/M2 have no AV1 decoder) are
# linked into the dylibs statically; FLAC, AAC, ALAC, PCM, VP8/VP9 and the
# rest are ffmpeg's own. No x264/x265 (H.264/HEVC encoding is
# VideoToolbox), no GPL or nonfree parts: the build fails if any shows.
#
# The one source of this file is github.com/hehehai/actnow-ffmpeg
# (scripts/build-ffmpeg-lgpl.sh); each app keeps a byte-identical copy in
# its scripts/, so that the key below is the family's and every app pins
# the same prebuilt tarball (that repository's GitHub releases). Change it
# there, publish, then copy it to the apps with the new pin.
#
# Every input is pinned below, the sources by SHA-256. `hash` prints the
# key of the build: the SHA-256 of this file's code with the variant. The
# versions, the configure line, the patches and the steps are all in this
# file, so any change to them makes a new key, under which
# each app's scripts/fetch-ffmpeg.sh caches and pins it. Comment lines, blank lines and
# the `source` step (it only packs the source tarball: its README text) are
# left out, so rewording them (as the rename to Refto did) keeps the key.
#
#   scripts/build-ffmpeg-lgpl.sh fetch            # download and check the sources (any OS)
#   scripts/build-ffmpeg-lgpl.sh hash             # print the build's key
#   scripts/build-ffmpeg-lgpl.sh source FILE      # the corresponding source as a tarball (any OS)
#   scripts/build-ffmpeg-lgpl.sh [build] [opts]   # build (macOS on Apple silicon)
#
# Options:
#   -j N             parallel jobs (default $JOBS, else 4: the Mac is shared)
#   --out DIR        the product (default .cache/ffmpeg/<key>)
#   --work DIR       sources unpacked, deps, logs (default .cache/ffmpeg-build)
#   --src DIR        the source archives (default $ACTNOW_FFMPEG_SRC, else .cache/ffmpeg-src)
#   --tools MODE     brew: Homebrew's autoconf, automake, libtool, meson,
#                    ninja and pkg-config (CI: brew install autoconf automake
#                    libtool meson ninja pkg-config); local: GNU m4,
#                    autoconf, automake and libtool built from pinned
#                    sources and meson/ninja in a venv, under --work (a
#                    pkg-config must be on PATH or in /opt/homebrew/bin);
#                    auto (default): brew when it has them all, else local.
#   --variant V      slim-shared (default, what ships) or slim (static
#                    executables, for debugging; not what the app expects)
#
# The product (--out):
#   bin/ffmpeg, bin/ffprobe   rpath @executable_path/../Frameworks (an app:
#                             Contents/Helpers + Contents/Frameworks) and
#                             @executable_path/../lib (this directory)
#   lib/libav*.N.dylib, lib/libsw*.N.dylib   install names @rpath/<name>
#   manifest.json             the key, versions, URLs and SHA-256 of the
#                             sources, the configure line, the toolchain
#   licenses/                 the licence texts of FFmpeg and of the
#                             libraries linked into it
# Signed ad hoc only: each app signs them again with its own identity
# (mygo build's macos.contents), no signing identity is in the tarball.
# Each file is checked: arm64, links only system libraries and @rpath's
# libav*/libsw*, `ffmpeg -L` says LGPL, the configuration has no
# --enable-gpl/--enable-nonfree.
#
# No x86 assembly on arm64, so no nasm. Downloads use $https_proxy if set.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

# ---- pins ----------------------------------------------------------------
# name version url sha256 licence
FFMPEG_VERSION=8.1.3
SOURCES=(
  "ffmpeg $FFMPEG_VERSION https://ffmpeg.org/releases/ffmpeg-$FFMPEG_VERSION.tar.xz 7138d28c96d9d3e3af4ee3d8cad72741f8ffb40da90c1112235dea3ecd3178a3 LGPL-2.1-or-later"
  "zimg 3.0.6 https://github.com/sekrit-twc/zimg/archive/refs/tags/release-3.0.6.tar.gz be89390f13a5c9b2388ce0f44a5e89364a20c1c57ce46d382b1fcc3967057577 WTFPL"
  "opus 1.5.2 https://downloads.xiph.org/releases/opus/opus-1.5.2.tar.gz 65c1d2f78b9f2fb20082c38cbe47c951ad5839345876e46941612ee87f9a7ce1 BSD-3-Clause"
  "lame 3.100 https://downloads.sourceforge.net/project/lame/lame/3.100/lame-3.100.tar.gz ddfe36cab873794038ae2c1210557ad34857a4b6bdc515785d1da9e175b1da1e LGPL-2.0-or-later"
  "dav1d 1.5.4 https://downloads.videolan.org/pub/videolan/dav1d/1.5.4/dav1d-1.5.4.tar.xz 686616b7c69eb88d44459391ab25cac13b6647a3b288835c5784e71c1514a5c5 BSD-2-Clause"
)
# Build tools for --tools local (not part of the product).
TOOL_SOURCES=(
  "m4 1.4.19 https://ftp.gnu.org/gnu/m4/m4-1.4.19.tar.xz 63aede5c6d33b6d9b13511cd0be2cac046f2e70fd0a07aa9573a04a82783af96"
  "autoconf 2.72 https://ftp.gnu.org/gnu/autoconf/autoconf-2.72.tar.xz ba885c1319578d6c94d46e9b0dceb4014caafe2490e437a0dbca3f270a223f5a"
  "automake 1.17 https://ftp.gnu.org/gnu/automake/automake-1.17.tar.xz 8920c1fc411e13b90bf704ef9db6f29d540e76d232cb3b2c9f4dc4cc599bd990"
  "libtool 2.5.4 https://ftp.gnu.org/gnu/libtool/libtool-2.5.4.tar.xz f81f5860666b0bc7d84baddefa60d1cb9fa6fceb2398cc3baca6afaa60266675"
)
PIP_TOOLS=(meson==1.11.2 ninja==1.13.2)
# The oldest macOS the code runs on: mygo.json's minimumSystemVersion.
MIN_MACOS=15.0

COMMON=(
  --disable-gpl --disable-nonfree --disable-debug --disable-doc --disable-ffplay
  --enable-pic --enable-runtime-cpudetect
  --enable-videotoolbox --enable-audiotoolbox
  --enable-libzimg --enable-libopus --enable-libmp3lame --enable-libdav1d
  --disable-network --disable-devices --disable-sdl2 --disable-xlib --disable-libxcb
  --disable-lzma --disable-securetransport --disable-avfoundation --disable-coreimage
  --pkg-config-flags=--static
)
# Every decoder, demuxer, parser and bitstream filter (open anything); only
# the encoders, muxers, filters and protocols the apps use (the union of
# Refto, CaptionCraft, Paralign and Onda), the lavfi input (no capture
# devices) and a few sources (black, silence, test patterns) for renders
# and tests. rawvideo, pcm_s16le and pcm_f32le (-f s16le, -f f32le): raw
# frames and samples to a pipe (Onda); gif with palettegen/paletteuse
# (Refto's GIF tool). Not metadata (it links libavformat into
# libavfilter: the scene lists use showinfo), not boxblur: it is GPL
# (LICENSE.md).
# shellcheck disable=SC2054 # the commas are configure's
SLIM=(
  --disable-encoders --disable-muxers --disable-filters --disable-protocols
  --enable-protocol=file,pipe,concat,fd
  --enable-indev=lavfi
  --enable-encoder=h264_videotoolbox,hevc_videotoolbox,prores_videotoolbox,aac,aac_at,alac,alac_at,libopus,libmp3lame,flac,pcm_s16le,pcm_s24le,pcm_f32le,png,mjpeg,gif,rawvideo,movtext,srt,subrip,webvtt,ass,ssa,wrapped_avframe
  --enable-muxer=mp4,mov,ipod,matroska,webm,mp3,adts,flac,ogg,opus,wav,pcm_s16le,pcm_f32le,rawvideo,gif,image2,image2pipe,srt,webvtt,ass,null,segment,framemd5,md5,ffmetadata
  --enable-filter=aresample,aformat,anull,null,format,scale,crop,pad,fps,setpts,asetpts,trim,atrim,split,asplit,overlay,gblur,drawbox,zscale,tonemap,scale_vt,transpose_vt,hwdownload,hwupload,colorspace,transpose,hflip,vflip,amix,amerge,pan,volume,loudnorm,ebur128,silencedetect,atempo,concat,ssim,psnr,showwavespic,thumbnail,select,setsar,setdar,copy,apad,color,nullsrc,anullsrc,sine,testsrc2,adelay,afade,fade,tpad,setparams,sidechaincompress,alimiter,volumedetect,showinfo,premultiply,palettegen,paletteuse
)
SHARED=(--disable-static --enable-shared --install-name-dir=@rpath)
STATIC=(--enable-static --disable-shared)

# ---- options -------------------------------------------------------------
step=build
JOBS="${JOBS:-4}"
OUT="" WORK="" SRC="${ACTNOW_FFMPEG_SRC:-}" TOOLS_MODE=auto VARIANT=slim-shared
while (($#)); do
  case "$1" in
    fetch | hash | build) step="$1"; shift ;;
    source) step=source; source_out="${2:?source wants the tarball to write}"; shift 2 ;;
    -j) JOBS="$2"; shift 2 ;;
    -j*) JOBS="${1#-j}"; shift ;;
    --out) OUT="$2"; shift 2 ;;
    --work) WORK="$2"; shift 2 ;;
    --src) SRC="$2"; shift 2 ;;
    --tools) TOOLS_MODE="$2"; shift 2 ;;
    --variant) VARIANT="$2"; shift 2 ;;
    -h | --help) sed -n '2,/^set -euo/p' "$SELF" | sed '$d; s/^# \{0,1\}//'; exit 0 ;;
    *) echo "build-ffmpeg-lgpl.sh: unknown argument $1" >&2; exit 2 ;;
  esac
done
case "$VARIANT" in slim-shared | slim) ;; *) echo "unknown variant $VARIANT (slim-shared or slim)" >&2; exit 2 ;; esac
case "$TOOLS_MODE" in auto | brew | local) ;; *) echo "unknown --tools $TOOLS_MODE (auto, brew or local)" >&2; exit 2 ;; esac
[[ "$JOBS" =~ ^[1-9][0-9]*$ ]] || { echo "-j wants a number, not $JOBS" >&2; exit 2; }

sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

# key_input: the lines the product is built from: this file without its
# comment lines, blank lines and the `source` step (up to its closing fi).
key_input() {
  awk '/^if \[\[ \$step == source \]\]; then$/ { skip = 1 }
       skip { if ($0 == "fi") skip = 0; next }
       /^[[:space:]]*(#|$)/ { next }
       { print }' "$SELF"
}
# key: what the product is built from (the code above, the variant).
key() {
  local h
  h="$( { key_input; echo "variant=$VARIANT"; } | if command -v sha256sum >/dev/null 2>&1; then sha256sum; else shasum -a 256; fi | cut -c1-16)"
  echo "$VARIANT-$h"
}
KEY="$(key)"
if [[ $step == hash ]]; then
  echo "$KEY"
  exit 0
fi

SRC="${SRC:-$ROOT/.cache/ffmpeg-src}"
WORK="${WORK:-$ROOT/.cache/ffmpeg-build}"
OUT="${OUT:-$ROOT/.cache/ffmpeg/$KEY}"
mkdir -p "$SRC"

# fetch_one "name version url sha256 ...": SRC/<name>-<version>.<ext>, checked.
fetch_one() {
  local name version url sum ext file got
  read -r name version url sum _ <<<"$1"
  case "$url" in *.tar.xz) ext=tar.xz ;; *.tar.gz) ext=tar.gz ;; *) echo "unknown archive $url" >&2; exit 1 ;; esac
  file="$SRC/$name-$version.$ext"
  if [[ -f $file && "$(sha256 "$file")" == "$sum" ]]; then
    return
  fi
  echo "downloading $name $version"
  curl -fsSL --retry 5 --retry-delay 3 --connect-timeout 20 -o "$file.part" "$url"
  got="$(sha256 "$file.part")"
  if [[ "$got" != "$sum" ]]; then
    rm -f "$file.part"
    echo "$name $version: checksum mismatch (got $got, want $sum, from $url)" >&2
    exit 1
  fi
  mv -f "$file.part" "$file"
}
archive() { # archive name: the checked archive of a pinned source
  local entry
  for entry in "${SOURCES[@]}" "${TOOL_SOURCES[@]}"; do
    read -r n v u _ <<<"$entry"
    if [[ $n == "$1" ]]; then
      case "$u" in *.tar.xz) echo "$SRC/$n-$v.tar.xz" ;; *) echo "$SRC/$n-$v.tar.gz" ;; esac
      return
    fi
  done
  echo "no pin for $1" >&2
  exit 1
}

if [[ $step == fetch ]]; then
  for entry in "${SOURCES[@]}" "${TOOL_SOURCES[@]}"; do fetch_one "$entry"; done
  echo "sources checked in ${SRC#"$ROOT"/}"
  exit 0
fi

# The LGPL's corresponding source of what ships: the pinned archives as
# downloaded (checked), this script, which configures and builds them, and
# a README. The release publishes it beside the app (docs/architecture.md §8).
if [[ $step == source ]]; then
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/actnow-ffmpeg-source.XXXXXX")"
  dir="$tmp/actnow-ffmpeg-source-$KEY"
  mkdir -p "$dir/sources"
  {
    echo "The source of the ffmpeg and ffprobe in the ActNow apps (build $KEY)"
    echo
    echo "The ffmpeg and ffprobe in Contents/Helpers of Refto.app, CaptionCraft.app,"
    echo "Paralign.app and Onda.app, and the libraries in their Contents/Frameworks,"
    echo "are FFmpeg $FFMPEG_VERSION (LGPL-2.1-or-later) with zimg, Opus, LAME and dav1d"
    echo "linked into its libraries, built for macOS on Apple silicon by"
    echo "build-ffmpeg-lgpl.sh (here; https://github.com/hehehai/actnow-ffmpeg)"
    echo "from these archives, unchanged as published:"
    echo
    for entry in "${SOURCES[@]}"; do
      read -r name version url sum licence <<<"$entry"
      fetch_one "$entry"
      cp "$(archive "$name")" "$dir/sources/"
      printf '  %-7s %-7s %s\n          %s\n          SHA-256 %s\n' "$name" "$version" "$licence" "$url" "$sum"
    done
    echo
    echo "The script patches two files before building (see it): LAME's"
    echo "include/libmp3lame.sym drops lame_init_old, and zimg's installed zimg.pc"
    echo "links libc++ instead of libstdc++. To rebuild, on macOS on Apple silicon:"
    echo
    echo "  ./build-ffmpeg-lgpl.sh build --src sources --work work --out out"
    echo
    echo "The libraries in Contents/Frameworks can be replaced by your own build"
    echo "of them: ffmpeg and ffprobe load them by @rpath from"
    echo "@executable_path/../Frameworks. Sign what you change and the app again"
    echo "(codesign --force --sign - …), as macOS runs signed code only."
  } >"$dir/README.txt"
  cp "$SELF" "$dir/build-ffmpeg-lgpl.sh"
  mkdir -p "$(dirname "$source_out")"
  tar -C "$tmp" -cf "$source_out" "actnow-ffmpeg-source-$KEY"
  rm -rf "$tmp"
  echo "wrote $source_out ($(du -h "$source_out" | cut -f1))"
  exit 0
fi

# ---- build ---------------------------------------------------------------
if [[ "$(uname -s)" != Darwin || "$(uname -m)" != arm64 ]]; then
  echo "the ffmpeg build needs macOS on Apple silicon (fetch and hash run anywhere)" >&2
  exit 1
fi
for entry in "${SOURCES[@]}"; do fetch_one "$entry"; done

B="$WORK"
TOOLS="$B/tools"
DEPS="$B/deps"
LOGS="$B/logs"
mkdir -p "$B" "$LOGS" "$TOOLS/bin"
export MACOSX_DEPLOYMENT_TARGET=$MIN_MACOS
export CFLAGS="-O2 -mmacosx-version-min=$MIN_MACOS" CXXFLAGS="-O2 -mmacosx-version-min=$MIN_MACOS" LDFLAGS="-mmacosx-version-min=$MIN_MACOS"

timed() { # timed name command...: run, log to LOGS/name.log, say how long
  local name=$1 t
  shift
  t=$(date +%s)
  if ! "$@" >"$LOGS/$name.log" 2>&1; then
    echo "FAILED: $name (log: $LOGS/$name.log)" >&2
    tail -30 "$LOGS/$name.log" >&2
    exit 1
  fi
  echo "  $name $(($(date +%s) - t)) s"
}
unpack() { # unpack name: a fresh source tree in B/name
  rm -rf "${B:?}/$1"
  mkdir -p "$B/$1"
  tar -xf "$(archive "$1")" -C "$B/$1" --strip-components 1
}

# The tools: on PATH only what the build needs, so that nothing else of
# Homebrew (x264, SDL…) is found; pkg-config reads our .pc files only.
pkgconfig="$(PATH="$PATH:/opt/homebrew/bin:/usr/local/bin" command -v pkg-config || true)"
brew_prefix="$(command -v brew >/dev/null 2>&1 && brew --prefix || true)"
has_brew_tools() {
  [[ -n $brew_prefix ]] || return 1
  local t
  for t in autoreconf automake glibtoolize meson ninja pkg-config; do
    [[ -x "$brew_prefix/bin/$t" ]] || return 1
  done
}
if [[ $TOOLS_MODE == auto ]]; then
  if has_brew_tools; then TOOLS_MODE=brew; else TOOLS_MODE=local; fi
fi
echo "ffmpeg $FFMPEG_VERSION $VARIANT ($KEY), -j$JOBS, tools: $TOOLS_MODE"
rm -rf "${TOOLS:?}/bin" && mkdir -p "$TOOLS/bin"
if [[ $TOOLS_MODE == brew ]]; then
  has_brew_tools || { echo "Homebrew lacks some tools: brew install autoconf automake libtool meson ninja pkg-config" >&2; exit 1; }
  for t in autoconf autoheader autom4te autoreconf autoscan autoupdate ifnames aclocal automake meson ninja pkg-config; do
    [[ -x "$brew_prefix/bin/$t" ]] && ln -sf "$brew_prefix/bin/$t" "$TOOLS/bin/$t"
  done
  # GNU libtool's are g-prefixed (macOS has its own libtool).
  ln -sf "$brew_prefix/bin/glibtoolize" "$TOOLS/bin/libtoolize"
  # Homebrew's autoconf wants Homebrew's m4 (macOS's is too old).
  [[ -x "$brew_prefix/opt/m4/bin/m4" ]] && ln -sf "$brew_prefix/opt/m4/bin/m4" "$TOOLS/bin/m4"
else
  [[ -n $pkgconfig ]] || { echo "no pkg-config: brew install pkg-config (or pkgconf)" >&2; exit 1; }
  ln -sf "$pkgconfig" "$TOOLS/bin/pkg-config"
  LOCAL="$B/local-tools"
  stamp="$LOCAL/.done-$(printf '%s\n' "${TOOL_SOURCES[@]}" "${PIP_TOOLS[@]}" | shasum -a 256 | cut -c1-12)"
  if [[ ! -f $stamp ]]; then
    for entry in "${TOOL_SOURCES[@]}"; do fetch_one "$entry"; done
    rm -rf "$LOCAL" && mkdir -p "$LOCAL/bin"
    # macOS's m4 (1.4.6) is too old for autoconf: GNU m4 first.
    for t in m4 autoconf automake libtool; do
      unpack "$t"
      timed "tool-$t" env PATH="$LOCAL/bin:/usr/bin:/bin:/usr/sbin:/sbin" bash -c "cd '$B/$t' && ./configure --prefix='$LOCAL' && make -j$JOBS && make install"
    done
    timed tool-meson bash -c "/usr/bin/python3 -m venv '$LOCAL/venv' && '$LOCAL/venv/bin/pip' install -q ${PIP_TOOLS[*]}"
    ln -sf "$LOCAL/venv/bin/meson" "$LOCAL/venv/bin/ninja" "$LOCAL/bin/"
    touch "$stamp"
  fi
  for t in "$LOCAL"/bin/*; do ln -sf "$t" "$TOOLS/bin/"; done
fi
export PATH="$TOOLS/bin:/usr/bin:/bin:/usr/sbin:/sbin"
# ffmpeg's configure runs pkg-config from PATH (it ignores $PKG_CONFIG).
export PKG_CONFIG="$TOOLS/bin/pkg-config" PKG_CONFIG_LIBDIR="$DEPS/lib/pkgconfig" PKG_CONFIG_PATH=""

# The dependencies, static, into DEPS (rebuilt when their pins change).
deps_stamp="$DEPS/.done-$(printf '%s\n' "${SOURCES[@]:1}" "$MIN_MACOS" | shasum -a 256 | cut -c1-12)"
if [[ ! -f $deps_stamp ]]; then
  rm -rf "$DEPS" && mkdir -p "$DEPS"
  for t in zimg opus lame dav1d; do unpack "$t"; done
  timed zimg bash -c "cd '$B/zimg' && ./autogen.sh && ./configure --prefix='$DEPS' --disable-shared --enable-static && make -j$JOBS && make install"
  # zimg is C++: the link needs libc++ (its .pc says libstdc++).
  sed -i '' 's/-lstdc++/-lc++/' "$DEPS/lib/pkgconfig/zimg.pc"
  grep -q -- '-lc++' "$DEPS/lib/pkgconfig/zimg.pc" || sed -i '' 's/^Libs.private:.*/& -lc++/' "$DEPS/lib/pkgconfig/zimg.pc"
  timed opus bash -c "cd '$B/opus' && ./configure --prefix='$DEPS' --disable-shared --enable-static --disable-doc --disable-extra-programs && make -j$JOBS && make install"
  # LAME 3.100 exports a symbol it does not define on macOS.
  sed -i '' '/lame_init_old/d' "$B/lame/include/libmp3lame.sym"
  timed lame bash -c "cd '$B/lame' && ./configure --prefix='$DEPS' --disable-shared --enable-static --disable-frontend --disable-decoder --enable-nasm=no && make -j$JOBS && make install"
  timed dav1d bash -c "cd '$B/dav1d' && meson setup build --prefix='$DEPS' --libdir=lib --buildtype=release --default-library=static -Denable_tools=false -Denable_tests=false && ninja -j$JOBS -C build install"
  touch "$deps_stamp"
fi

# ffmpeg.
config=("${COMMON[@]}" "${SLIM[@]}")
if [[ $VARIANT == slim-shared ]]; then config+=("${SHARED[@]}"); else config+=("${STATIC[@]}"); fi
# LAME has no .pc file: ffmpeg finds it by -I/-L. Room in the headers for
# the rpaths added below (and for whoever relinks or renames the libraries).
config+=("--extra-cflags=-mmacosx-version-min=$MIN_MACOS -I$DEPS/include" "--extra-ldflags=-mmacosx-version-min=$MIN_MACOS -L$DEPS/lib -Wl,-headerpad_max_install_names")
unpack ffmpeg
PREFIX="$B/prefix-$VARIANT"
rm -rf "$PREFIX"
timed ffmpeg-configure bash -c "cd '$B/ffmpeg' && ./configure --prefix='$PREFIX' $(printf '%q ' "${config[@]}")"
cp "$B/ffmpeg/ffbuild/config.log" "$LOGS/ffmpeg-config.log"
timed ffmpeg-make bash -c "cd '$B/ffmpeg' && make -j$JOBS && make install"

# The product: a fresh directory, moved into place when it checks out.
stage="$OUT.part"
rm -rf "$stage"
mkdir -p "$stage/bin"
cp "$PREFIX/bin/ffmpeg" "$PREFIX/bin/ffprobe" "$stage/bin/"
if [[ $VARIANT == slim-shared ]]; then
  mkdir -p "$stage/lib"
  # One file per library, named as its install name (@rpath/libavcodec.62.dylib):
  # no version links, which a signed bundle would only carry along.
  for lib in "$PREFIX"/lib/*.dylib; do
    [[ -L $lib ]] && continue
    id="$(otool -D "$lib" | tail -n +2)"
    [[ $id == @rpath/* ]] || { echo "$lib: install name $id, not @rpath/…" >&2; exit 1; }
    cp "$lib" "$stage/lib/${id#@rpath/}"
  done
  for b in ffmpeg ffprobe; do
    install_name_tool -add_rpath @executable_path/../Frameworks -add_rpath @executable_path/../lib "$stage/bin/$b"
  done
fi
# The licence texts, from the archives built (as file names: one each).
mkdir -p "$stage/licenses"
for entry in "${SOURCES[@]}"; do
  read -r name _ <<<"$entry"
  case "$name" in ffmpeg) files=(LICENSE.md COPYING.LGPLv2.1) ;; *) files=(COPYING) ;; esac
  for f in "${files[@]}"; do
    tar -xOf "$(archive "$name")" "$(tar -tf "$(archive "$name")" | head -1 | cut -d/ -f1)/$f" >"$stage/licenses/$name-$f.txt"
    [[ -s "$stage/licenses/$name-$f.txt" ]] || { echo "$name has no $f" >&2; exit 1; }
  done
done
for f in "$stage"/bin/* "$stage"/lib/*.dylib; do
  [[ -f $f ]] || continue
  strip -x "$f"
  # strip and install_name_tool leave the signature broken; Apple silicon
  # runs signed code only (the app signs it again with its own identity).
  codesign --force --sign - "$f" 2>/dev/null
done

# Checks.
fail() { echo "check failed: $*" >&2; exit 1; }
for f in "$stage"/bin/* "$stage"/lib/*.dylib; do
  [[ -f $f ]] || continue
  [[ "$(lipo -archs "$f")" == arm64 ]] || fail "$f is not arm64 only"
  while read -r dep _; do
    case "$dep" in
      /usr/lib/* | /System/Library/*) ;;
      @rpath/libav*.dylib | @rpath/libsw*.dylib) [[ $VARIANT == slim-shared && -f "$stage/lib/${dep#@rpath/}" ]] || fail "$(basename "$f") links $dep, which is not in lib/" ;;
      *) fail "$(basename "$f") links $dep (only system libraries and libav*/libsw*)" ;;
    esac
  done < <(otool -L "$f" | tail -n +2)
done
# (Whole outputs first: grep -q stops reading, and pipefail would take
# ffmpeg's SIGPIPE for a failure.)
ff() { "$stage/bin/ffmpeg" -hide_banner "$@"; }
licence="$(ff -L)" buildconf="$(ff -buildconf)" encoders="$(ff -encoders)" decoders="$(ff -decoders)" filters="$(ff -filters)"
grep -q "GNU Lesser General Public" <<<"$licence" || fail "ffmpeg -L does not say LGPL"
grep -qE -- '--enable-(gpl|nonfree|version3)' <<<"$buildconf" && fail "the configuration enables GPL, version3 or nonfree parts"
for need in h264_videotoolbox hevc_videotoolbox libopus libmp3lame aac flac mov_text srt; do
  grep -q " $need " <<<"$encoders" || fail "no encoder $need"
done
for need in zscale scale_vt overlay tonemap color anullsrc; do
  grep -q " $need " <<<"$filters" || fail "no filter $need"
done
grep -q " libdav1d " <<<"$decoders" || fail "no decoder libdav1d"
muxers="$(ff -muxers)"
for need in rawvideo s16le f32le wav mp4 mov matroska gif image2pipe; do
  grep -qE "^ +E +$need " <<<"$muxers" || fail "no muxer $need"
done
for need in rawvideo gif; do
  grep -q " $need " <<<"$encoders" || fail "no encoder $need"
done
for need in palettegen paletteuse; do
  grep -q " $need " <<<"$filters" || fail "no filter $need"
done
"$stage/bin/ffprobe" -hide_banner -version >/dev/null || fail "ffprobe does not run"

# The manifest.
json() { # json STRING: a JSON string
  local s=${1//\\/\\\\}
  s=${s//\"/\\\"}
  printf '"%s"' "$s"
}
{
  echo "{"
  echo "  \"key\": $(json "$KEY"),"
  echo "  \"variant\": $(json "$VARIANT"),"
  echo "  \"licence\": \"LGPL-2.1-or-later\","
  echo "  \"minimumSystemVersion\": $(json "$MIN_MACOS"),"
  echo "  \"built\": $(json "$(date -u +%Y-%m-%dT%H:%M:%SZ)"),"
  echo "  \"toolchain\": $(json "$(clang --version | head -1)"),"
  echo "  \"sdk\": $(json "$(xcrun --show-sdk-version 2>/dev/null || echo unknown)"),"
  echo "  \"sources\": ["
  n=${#SOURCES[@]}
  for i in "${!SOURCES[@]}"; do
    read -r name version url sum licence <<<"${SOURCES[$i]}"
    sep=","; ((i == n - 1)) && sep=""
    echo "    {\"name\": $(json "$name"), \"version\": $(json "$version"), \"url\": $(json "$url"), \"sha256\": $(json "$sum"), \"licence\": $(json "$licence")}$sep"
  done
  echo "  ],"
  echo "  \"configure\": ["
  n=${#config[@]}
  for i in "${!config[@]}"; do
    arg="${config[$i]//$DEPS/\$DEPS}"
    sep=","; ((i == n - 1)) && sep=""
    echo "    $(json "$arg")$sep"
  done
  echo "  ],"
  echo "  \"files\": {"
  files=()
  while IFS= read -r f; do files+=("$f"); done < <(cd "$stage" && find bin lib -type f 2>/dev/null | sort)
  n=${#files[@]}
  for i in "${!files[@]}"; do
    sep=","; ((i == n - 1)) && sep=""
    echo "    $(json "${files[$i]}"): $(json "$(sha256 "$stage/${files[$i]}")")$sep"
  done
  echo "  }"
  echo "}"
} >"$stage/manifest.json"

rm -rf "$OUT"
mkdir -p "$(dirname "$OUT")"
mv "$stage" "$OUT"
echo "built ffmpeg $FFMPEG_VERSION ($KEY) in ${OUT#"$ROOT"/}: $(du -sh "$OUT" | cut -f1)"
otool -L "$OUT/bin/ffmpeg" | tail -n +2 | sed 's/^/  /'
"$OUT/bin/ffmpeg" -hide_banner -L | head -3 | sed 's/^/  /'
