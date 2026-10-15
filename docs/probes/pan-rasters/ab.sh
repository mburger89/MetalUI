#!/bin/zsh
# A/B release timing for P3 (record 118). Alternates a baseline checkout and this one, N rounds, records the load average.
# usage: ab.sh <baseline-checkout> <head-checkout> [rounds=5] [secs=8]   (checkouts need no build; ab.sh builds both)
# Each build lives in its own scratch dir; this script never touches another workflow's .build.
set -u
BASE=$1; HEADCO=$2; ROUNDS=${3:-5}; SECS=${4:-8}
HERE=${0:A:h}; W=${AB_SCRATCH:-/private/tmp/claude-501/pan-rasters-ab}
mkdir -p $W
for side in base head; do
  co=$BASE; [[ $side == head ]] && co=$HEADCO
  rm -rf $W/$side; mkdir -p $W/$side
  cp -R $HERE/Package.swift $HERE/Sources $W/$side/
  ln -s $co $W/$side/MetalUI
  [[ -f $W/$side/MetalUI/Sources/MetalUI/RasterCache.swift ]] || { echo "bad checkout $co"; exit 1; }
  (cd $W/$side && swift build -c release --build-system native >$W/$side.build.log 2>&1) || { echo "build $side failed"; tail $W/$side.build.log; exit 1; }
done
bin() { echo $W/$1/.build/release/Prof; }
echo "# date $(date +%F) base=${AB_BASE_LABEL:-$(git -C $BASE rev-parse --short HEAD)} head=$(git -C $HEADCO rev-parse --short HEAD) rounds=$ROUNDS secs=$SECS"
for r in $(seq $ROUNDS); do
  for sc in bracket-pan bracket-pan-panels bracket-value shadows; do
    for side in base head; do
      l=$(uptime | sed 's/.*averages*: //')
      out=$($(bin $side) $sc $SECS 2>&1 | tail -1 | sed 's/ | .*//')
      echo "round=$r side=$side load=[$l] $out"
    done
  done
done
# Allocations per frame (malloc_logger counts every main-thread malloc; PROF_ALLOC=8 samples stacks), 400 frames each.
for side in base head; do
  for sc in bracket-pan; do
    PROF_OUT=$W $(bin $side) $sc n400 >/dev/null 2>&1 # warm the path
    line=$(PROF_ALLOC=8 PROF_OUT=$W $(bin $side) $sc n400 2>&1 | grep '^ALLOC')
    echo "alloc side=$side $sc $line"
  done
done
