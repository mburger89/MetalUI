#!/bin/zsh
# GPU cost of the continuous rect kind (R4-5 PR F, record 226, plan section 8 (ii)).
#
#   zsh docs/probes/continuous-corner-cost/run.sh [BASE]    # BASE defaults to the merge base with master
#
# Prints `COST ...` lines: the median over 50 frames of MTLCommandBuffer.gpuEndTime - gpuStartTime for 10,000 opaque
# overlapping rects in a 2560 x 1440 target, two shapes (96 x 64 r 20, and 24 x 24 r 12), per shape kind. Three arms:
#   branch  kinds 0 and 2 with this branch's shaders;
#   base    kind 0 with the base commit's shaders (kind 2 is a value the base's shader does not know), the branch's
#           Swift otherwise: the arm that shows whether the kind-0 path regressed.
# The base arm puts the base's two shader files in place and restores them (git checkout of the branch's), so run it on a
# clean tree. The test is Tests/MetalUIRenderTests/ContinuousCornerCostTests.swift, env-gated (METALUI_CORNER_COST=1).
set -e
base=${1:-$(git merge-base HEAD origin/master)}
files=(Sources/MetalUIRender/Shaders/shaders.metal Sources/MetalUIRender/Shaders/MetalUIShaderTypes.h)
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
run() { METALUI_CORNER_COST=1 METALUI_CORNER_COST_KINDS=$1 swift test --build-system native --no-parallel --filter theGPUCostOfTheContinuousKind 2>&1 | grep '^COST'; }
echo "== branch shaders, kinds 0 and 2"
run 0,2
run 0,2
echo "== base shaders ($base), kind 0"
git checkout $base -- $files
trap 'git checkout HEAD -- $files' EXIT
run 0
run 0
