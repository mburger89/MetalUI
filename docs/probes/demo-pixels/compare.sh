#!/bin/zsh
# The `CN-R` twelve-image demo pixel comparison, commit to commit.
#
# Committed by plan task 7, stage 4, lane 1 (ruling `LR-CB`). Every lane of
# every engine-replacement stage has "0 differing pixels in all twelve `CN-R`
# images" as its acceptance criterion, and until this script existed the
# criterion was not reproducible from anything in the repository: record §18's
# generator lived in a session scratchpad, and record §25 §7.6, §8.8, §9.8 and
# §14.4 each rebuilt it from prose, at about an hour apiece, certifiable only
# against a handful of control numbers.
#
# METHOD. Offscreen, not a real window: each commit is exported with
# `git archive`, `ZZDemoPixels.swift` (next to this script) is copied into its
# `Tests/MetalUITests/`, and the suite is run filtered to that one test with
# `METALUI_PIXEL_OUT` pointing at a per-commit directory. The test renders
# twelve images through a real `Window` over a `FakePlatformWindow`, writing raw
# BGRA and a scene dump for each. This sees the scene, the renderer and the
# frame loop; it does NOT see the drawable, the real window, input, hover, focus
# or a mid-flight animation — `docs/probes/window-capture/capture.sh` is the
# real-window instrument, and it needs an unlocked screen.
#
# CONTROLS FIRST. The script prints five pairwise controls and two distinct-value
# counts before any commit-to-commit row, because a harness that wrote uniform
# or identical images would read 0 everywhere and prove nothing. Their recorded
# values (record §25 §7.6, §8.8, §9.8, §14.4 — four independent rebuilds agree):
#
#   light vs dark, f0            1048576   (every pixel of a 1024 square)
#   default vs modal (light)     1030498
#   default vs animation (light)  210027
#   f0 vs f3 (light)                   0
#   preview light vs dark        1048576
#   distinct values, default-light-f0    544
#   distinct values, chrome-legacy       216
#   chrome-legacy vs chrome-proposal       0
#
# A rebuild that disagrees with one of these is a finding, and the quoted
# number is what gets corrected — not the harness, silently.
#
# WHAT THE TWELVE COVER, AND WHAT THEY DO NOT. `demoContent()` names no
# proposal type (check with a grep; each stage re-checks), so **the ten legacy
# and preview images cannot be moved by a kernel change** and a zero there
# proves only that the legacy path is untouched. `chrome-legacy` vs
# `chrome-proposal` is the one pair that crosses the authority boundary. And
# none of the twelve scenes is ever scrolled, so `ScrollState.lastScrollTime` is
# `-.infinity`, `alpha` is 0 and no scroll indicator is painted anywhere in the
# set (record §25 §7.6's caveat, measured by scanning every `.scene` dump for a
# 3pt cross-axis rect: zero in all twelve).
#
# FROM STAGE 6b ON (record §39, `LR-DJ`) the paragraph above is history: the
# demo and preview images are taken at the window's default authority, which
# stage 6b makes `.proposal`, so the eight demo images CAN move with a kernel or
# lowering change, and a comparison across the switch itself differs by design.
# Its expected differences are named in the stage 6b spec §9 and must be
# accounted for region by region from the `.scene` dumps, not read as 0.
#
# USAGE: compare.sh <workdir> <commit>...   (in commit order; two or more)
#   e.g. docs/probes/demo-pixels/compare.sh /tmp/pix f2e981f HEAD
set -e
W=$1; shift
HERE=${0:A:h}; REPO=$(git -C $HERE rev-parse --show-toplevel)
mkdir -p $W; cd $W
[ -x rawdiff ] || xcrun swiftc -O $HERE/rawdiff.swift -o rawdiff

IMAGES=(default-light-f0 default-light-f3 default-dark-f0 default-dark-f3
        modal-light modal-dark animation-light animation-dark
        preview-light preview-dark chrome-legacy chrome-proposal
        prod-default-light prod-modal-light)
# Stage 6b (`LR-DO` item 3): the two `prod-*` images are 920x560, not square;
# rawdiff is told their row width.

for c in "$@"; do
  sha=$(git -C $REPO rev-parse --short $c)
  [ -f img-$sha/prod-modal-light.bgra ] && continue
  rm -rf src-$sha && mkdir -p src-$sha
  git -C $REPO archive $c | tar -x -C src-$sha
  cp $HERE/ZZDemoPixels.swift src-$sha/Tests/MetalUITests/ZZDemoPixels.swift
  mkdir -p img-$sha
  (cd src-$sha \
    && swift build --build-system native --build-tests > ../build-$sha.log 2>&1 \
    && METALUI_PIXEL_OUT=$W/img-$sha swift test --build-system native --no-parallel \
         --skip-build --filter zzCaptureDemoPixels >> ../build-$sha.log 2>&1)
  echo "captured $c ($sha): $(ls img-$sha/*.bgra | wc -l | tr -d ' ') images"
done

first=$(git -C $REPO rev-parse --short $1)
echo
echo "controls at $1 ($first) — every one must be non-zero except the two marked 0:"
printf '  %-34s %s\n' "light vs dark, f0 [1048576]" \
  "$(./rawdiff img-$first/default-light-f0.bgra img-$first/default-dark-f0.bgra)"
printf '  %-34s %s\n' "default vs modal, light [1030498]" \
  "$(./rawdiff img-$first/default-light-f0.bgra img-$first/modal-light.bgra)"
printf '  %-34s %s\n' "default vs animation, light [210027]" \
  "$(./rawdiff img-$first/default-light-f0.bgra img-$first/animation-light.bgra)"
printf '  %-34s %s\n' "f0 vs f3, light [0]" \
  "$(./rawdiff img-$first/default-light-f0.bgra img-$first/default-light-f3.bgra)"
printf '  %-34s %s\n' "preview light vs dark [1048576]" \
  "$(./rawdiff img-$first/preview-light.bgra img-$first/preview-dark.bgra)"
printf '  %-34s %s\n' "chrome legacy vs proposal [0]" \
  "$(./rawdiff img-$first/chrome-legacy.bgra img-$first/chrome-proposal.bgra)"
printf '  %-34s %s\n' "distinct, default-light-f0 [544]" \
  "$(./rawdiff --distinct img-$first/default-light-f0.bgra)"
printf '  %-34s %s\n' "distinct, chrome-legacy [216]" \
  "$(./rawdiff --distinct img-$first/chrome-legacy.bgra)"
printf '  %-34s %s\n' "prod default vs modal [not 0]" \
  "$(./rawdiff img-$first/prod-default-light.bgra img-$first/prod-modal-light.bgra 920)"
printf '  %-34s %s\n' "distinct, prod-default-light" \
  "$(./rawdiff --distinct img-$first/prod-default-light.bgra)"
printf '  %-34s %s\n' "indicator rects in all twelve [0]" \
  "$(cat img-$first/*.scene | awk '$1=="R" {print $3}' | grep -c '^3\.0x' || true)"

prev=""
for c in "$@"; do
  sha=$(git -C $REPO rev-parse --short $c)
  if [ -n "$prev" ]; then
    echo
    echo "$prevref ($prev) -> $c ($sha):"
    for m in $IMAGES; do
      case $m in prod-*) wd=920 ;; *) wd= ;; esac
      d=$(./rawdiff img-$prev/$m.bgra img-$sha/$m.bgra $wd)
      s=$(cmp -s img-$prev/$m.scene img-$sha/$m.scene && echo "scene identical" || echo "SCENE DIFFERS")
      printf '  %-18s %-46s %s\n' $m "$d" "$s"
    done
  fi
  prev=$sha; prevref=$c
done
