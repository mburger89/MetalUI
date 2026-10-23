#!/bin/sh
# Compile-time measurement of run-time HLSL compute compilation (XP-G25, rulings RC-H, RC-K; record 151).
#
#   zsh/sh docs/probes/runtime-compile-measure.sh /path/to/shadercross/install-prefix
#
# The prefix is an install of libsdl-org/SDL_shadercross at the pin
# 1ff05bec573988a98ef9e0260b4da44f512b8367 (docs/packaging.md 4a/4b). Needs SDL3 headers and libs
# discoverable by pkg-config, a C compiler. Prints a dated block: the machine, the library load time,
# the first compile in the process, then HLSL to SPIR-V, SPIR-V to MSL and HLSL to DXIL for generated
# kernels of about 200, 1000 and 2000 lines (median of 3). **Wall clock on a shared machine: dated
# readings, never pinned** (a pin counts work, not time). In the Linux image:
#   docker run --rm -v "$PWD":/work -v metalui-shadercross-<slug>:/vol -w /work metalui-portable \
#     sh docs/probes/runtime-compile-measure.sh /vol/install
set -e
SX="${1:?usage: $0 shadercross-install-prefix}"
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="${TMPDIR:-/tmp}/runtime-compile-measure.$$"
mkdir -p "$OUT"
LIBDIR="$SX/lib"
[ -d "$LIBDIR" ] || LIBDIR="$SX/lib64"
case "$(uname -s)" in
  Darwin) EXT=dylib ;;
  *) EXT=so ;;
esac
cc -O1 -I"$SX/include" $(pkg-config --cflags sdl3) "$HERE/runtime-compile-measure.c" $(pkg-config --libs sdl3) -o "$OUT/measure"
MAIN=$(ls "$LIBDIR"/libSDL3_shadercross.$EXT* | head -1)
DEPS=""
for f in "$LIBDIR"/libdxcompiler.$EXT "$LIBDIR"/libspirv-cross-c-shared.$EXT* "$LIBDIR"/libdxil.$EXT; do
  [ -e "$f" ] && DEPS="$DEPS $f"
done
echo "# runtime-compile-measure $(date -u +%Y-%m-%dT%H:%M:%SZ) $(uname -sm), $(getconf _NPROCESSORS_ONLN) cores, load average $(uptime | sed 's/.*load average[s]*: //')"
echo "# library $MAIN"
"$OUT/measure" "$MAIN" $DEPS
rm -rf "$OUT"
