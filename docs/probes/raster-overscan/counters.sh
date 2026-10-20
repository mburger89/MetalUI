#!/bin/zsh
# Work counters per frame (rasterized px, tinted px, textures made) for the drag and the pan, HEAD only
# (the counter lastTintedPixels is lane 1's; 34491ff4 tints exactly the rasterized pixels). usage: counters.sh <head-checkout>
set -u
HEADCO=$1; HERE=${0:A:h}; W=${AB_SCRATCH:-/private/tmp/claude-501/raster-overscan-ab}/counters
rm -rf $W; mkdir -p $W; cp -R $HERE/Package.swift $HERE/Sources $W/; ln -s $HEADCO $W/MetalUI
(cd $W && swift build -c debug --build-system native -Xswiftc -DPROF_TINT -Xswiftc -enable-testing >$W/build.log 2>&1) || { tail $W/build.log; exit 1; }
for sc in shadow-pan shadow-drag bracket-value bracket-pan; do
  PROF_RASTER_FRAMES=88 $W/.build/debug/Prof $sc 2>&1 | tail -1
done
