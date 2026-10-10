#!/bin/zsh
# The shadow-cache probes (C13 / PERF-a, rulings `PF-C`, `PF-F` item 3,
# `PF-K`; spec docs/superpowers/specs/2026-10-09-shadow-cache-design.md §6, §7).
#
#   run.sh pixels  <workdir> <commit>...   0 px expected, commit to commit
#   run.sh measure <workdir> <commit>...   release frame time, report only
#
# METHOD (the `demo-pixels` method). Each commit is exported with
# `git archive` into <workdir>/src-<sha> — the directory name
# docs/probes/demo-pixels/compare.sh uses, so running both scripts on one
# workdir builds each commit once — and the harness next to this script is
# copied into its `Tests/MetalUITests/`:
#
# - `pixels`: ZZShadowCachePixels.swift renders a FROZEN copy of 2155f1e's
#   LooksDemo shadow, gradient and blur rows (light, dark, 2×) and a five-frame
#   drag of a nine-leaf shadowed node in ONE warm window at 1× and 2× (+1 pt,
#   +0.5 pt, +0.3 pt, +1 pt), through a real `Window` over a
#   `FakePlatformWindow` — raw BGRA per image. Frames 1 and 4 of each drag hit
#   the cache after the shadow cache, so they are where a stale or misplaced
#   raster would show. CONTROLS FIRST: light vs dark and drag f0 vs f1 must
#   differ, and each image must hold more than one value.
# - `measure`: ZZShadowCacheMeasure.swift, a release build with testing
#   enabled (`-c release -Xswiftc -enable-testing`, own scratch path), runs a
#   headless 20-node shadowed graph at 2×, one node moving 2 pt a frame, and
#   prints median/mean ms per frame and the per-frame work counters. Wall
#   clock: REPORT ONLY (the suite pins the counted work). From lane 2 on,
#   ZZShadowCacheMeasureComposited.swift (the same graph with
#   `.compositingGroup()` before each shadow) is copied in too where the commit
#   has `compositingGroup()`, and prints `SHADOWMEASURE composited` lines.
#
# Recorded output is in docs/record/90-shadow-cache.md.
set -e
MODE=$1; W=$2; shift 2
HERE=${0:A:h}; REPO=$(git -C $HERE rev-parse --show-toplevel)
mkdir -p $W; cd $W

exportCommit() {  # $1 commit -> echoes the short sha, src-<sha> exported
  local sha=$(git -C $REPO rev-parse --short $1)
  if [ ! -d src-$sha ]; then
    mkdir -p src-$sha
    git -C $REPO archive $1 | tar -x -C src-$sha
  fi
  echo $sha
}

case $MODE in
pixels)
  [ -x rawdiff ] || xcrun swiftc -O $REPO/docs/probes/demo-pixels/rawdiff.swift -o rawdiff
  IMAGES=(looks-light looks-dark looks-light-2x
          drag-1x-f0 drag-1x-f1 drag-1x-f2 drag-1x-f3 drag-1x-f4
          drag-2x-f0 drag-2x-f1 drag-2x-f2 drag-2x-f3 drag-2x-f4)
  for c in "$@"; do
    sha=$(exportCommit $c)
    [ -f shadow-$sha/drag-2x-f4.bgra ] && continue
    cp $HERE/ZZShadowCachePixels.swift src-$sha/Tests/MetalUITests/ZZShadowCachePixels.swift
    mkdir -p shadow-$sha
    (cd src-$sha \
      && swift build --build-system native --build-tests > ../shadow-build-$sha.log 2>&1 \
      && METALUI_SHADOW_PIXEL_OUT=$W/shadow-$sha swift test --build-system native --no-parallel \
           --skip-build --filter zzCaptureShadowCachePixels >> ../shadow-build-$sha.log 2>&1)
    echo "captured $c ($sha): $(ls shadow-$sha/*.bgra | wc -l | tr -d ' ') images"
  done
  first=$(git -C $REPO rev-parse --short $1)
  echo
  echo "controls at $1 ($first) — each must be non-zero:"
  printf '  %-30s %s\n' "looks light vs dark" "$(./rawdiff shadow-$first/looks-light.bgra shadow-$first/looks-dark.bgra)"
  printf '  %-30s %s\n' "drag 1x f0 vs f1" "$(./rawdiff shadow-$first/drag-1x-f0.bgra shadow-$first/drag-1x-f1.bgra)"
  printf '  %-30s %s\n' "drag 2x f2 vs f3" "$(./rawdiff shadow-$first/drag-2x-f2.bgra shadow-$first/drag-2x-f3.bgra)"
  printf '  %-30s %s\n' "distinct, looks-light" "$(./rawdiff --distinct shadow-$first/looks-light.bgra)"
  printf '  %-30s %s\n' "distinct, drag-2x-f4" "$(./rawdiff --distinct shadow-$first/drag-2x-f4.bgra)"
  prev=""
  for c in "$@"; do
    sha=$(git -C $REPO rev-parse --short $c)
    if [ -n "$prev" ]; then
      echo
      echo "$prevref ($prev) -> $c ($sha):"
      for m in $IMAGES; do
        printf '  %-16s %s\n' $m "$(./rawdiff shadow-$prev/$m.bgra shadow-$sha/$m.bgra)"
      done
    fi
    prev=$sha; prevref=$c
  done
  ;;
measure)
  for c in "$@"; do
    sha=$(exportCommit $c)
    cp $HERE/ZZShadowCacheMeasure.swift src-$sha/Tests/MetalUITests/ZZShadowCacheMeasure.swift
    # The composited arm (lane 2) only where compositingGroup() exists.
    [ -f src-$sha/Sources/MetalUI/CompositingGroup.swift ] \
      && cp $HERE/ZZShadowCacheMeasureComposited.swift src-$sha/Tests/MetalUITests/ZZShadowCacheMeasureComposited.swift
    (cd src-$sha \
      && swift build -c release -Xswiftc -enable-testing --build-tests --scratch-path .build-release \
           > ../measure-build-$sha.log 2>&1 \
      && METALUI_SHADOW_MEASURE=1 swift test -c release -Xswiftc -enable-testing --skip-build \
           --scratch-path .build-release --filter zzMeasureShadowCache >> ../measure-build-$sha.log 2>&1)
    echo "$c ($sha):"
    grep SHADOWMEASURE measure-build-$sha.log | sed 's/^/  /'
  done
  ;;
*)
  echo "usage: run.sh pixels|measure <workdir> <commit>..." >&2; exit 2 ;;
esac
