#!/bin/zsh
# The native recursion's stack ceiling, per node kind, on a 1 MB thread — the
# measurement `SA-L` sets `NativeLayoutRun.maxDepth` from, and that `LR-Q` asks
# stage 6b to re-take in RELEASE before the root switch.
#
# Committed by plan task 7, stage 6b's design (record §39). Until now every
# re-bisection (SA-L 2026-09-14, the grids track's three) was rebuilt from prose.
#
# METHOD. The commit is exported with `git archive`; `ZZDepthCeilingProbe.swift`
# (next to this script) is copied into its `Tests/MetalUILayoutTests/`, and its
# `NativeLayoutRun.maxDepth` is raised to 1 000 000 with `sed` so the guard never
# fires and the only thing that can stop a chain is the stack. The package is
# built once per configuration; then, per kind, one `swift test --skip-build`
# process per candidate depth runs a chain of N one-child nodes of that kind
# over a leaf through `computeNativeLayout` at 400x400, on a `Thread` whose
# stack is 1 MB. A depth "completes" iff its log carries `DEPTH-OK <kind> <n>`;
# a stack overflow kills the process before that line. Exponential search up,
# then bisection; the boundary is re-confirmed (last-ok passes again, first-bad
# dies again) before it is printed.
#
# POSITIVE CONTROL. Before any kind, `padding 10` must complete and a chain far
# past any plausible ceiling (`padding 2000000`) must not — so a harness that
# never ran the chain (no DEPTH-OK ever) or never overflowed (DEPTH-OK always)
# reads as broken rather than as a number.
#
# USAGE: bisect.sh <workdir> <commit> <debug|release> [kind ...]
#   kinds: padding frame flexframe stack hstack overlay custom scroll grid
set -e
W=$1; C=$2; CFG=$3; shift 3
KINDS=(${@:-padding frame flexframe stack hstack overlay custom scroll grid})
HERE=${0:A:h}; REPO=$(git -C $HERE rev-parse --show-toplevel)
sha=$(git -C $REPO rev-parse --short $C)
SRC=$W/depth-src-$sha
if [ ! -d $SRC ]; then
  mkdir -p $SRC
  git -C $REPO archive $C | tar -x -C $SRC
  cp $HERE/ZZDepthCeilingProbe.swift $SRC/Tests/MetalUILayoutTests/
  sed -i '' 's/static let maxDepth = [0-9_]*/static let maxDepth = 1_000_000/' \
    $SRC/Sources/MetalUILayout/NativeLayoutRun.swift
fi
cd $SRC
swift build --build-system native -c $CFG --build-tests > $W/depth-build-$sha-$CFG.log 2>&1

ok() {  # ok <kind> <n>
  METALUI_DEPTH_KIND=$1 METALUI_DEPTH_N=$2 swift test --build-system native -c $CFG \
    --skip-build --filter zzDepthCeilingProbe > $W/depth-run.log 2>&1 || true
  grep -q "DEPTH-OK $1 $2\$" $W/depth-run.log
}

ok padding 10 || { echo "CONTROL FAILED: padding 10 did not complete"; exit 1; }
ok padding 2000000 && { echo "CONTROL FAILED: padding 2000000 completed"; exit 1; }
echo "controls ok ($CFG, $sha): padding 10 completes, padding 2000000 dies"

for k in $KINDS; do
  lo=10; hi=20
  while ok $k $hi; do lo=$hi; hi=$((hi * 2)); done
  while [ $((hi - lo)) -gt 1 ]; do
    mid=$(((lo + hi) / 2))
    if ok $k $mid; then lo=$mid; else hi=$mid; fi
  done
  ok $k $lo && ! ok $k $hi || { echo "$k: boundary $lo/$hi did not re-confirm"; continue; }
  echo "$k $CFG last-completes=$lo first-dies=$hi"
done
