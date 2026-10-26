#!/bin/zsh
# FS-O (EL-, record 157): the work probe of the combined layout-and-effect replay. A work probe, not a SwiftUI probe (EL-A):
# it prints, per combined step (a header growing 4 pt above a zooming set of six .equatable() cards, display scale 2), the retained
# translated count, the retained hits, the cards' element paints and the named refusals, with the retained trace
# (METALUI_TRACE_RETAINED=1) filtered to the paint-translation and miss lines of the first step.
#
# Run from the repository root:  zsh docs/probes/effect-layout-moved/trace.sh
#
# Recorded output (the red line is the baseline at aad9faf4 before any source change):
#   RED   aad9faf4 (no source change, the header step and the zoom step in one frame; the 6 cards' paints run in full):
#     T1 step 0: translated 0 hits 0 paints 98 skipped 0 refused [:]
#     T1 step 1: translated 0 hits 0 paints 98 skipped 0 refused [:]
#     T1 step 2: translated 0 hits 0 paints 98 skipped 0 refused [:]
#   GREEN 2678062a (lane A, paint only; prepaint still runs in these frames, lane B owns it):
#     T1 step 0: translated 6 hits 6 paints 14 skipped 84 refused [:]
#     T1 step 1: translated 6 hits 6 paints 14 skipped 84 refused [:]
#     T1 step 2: translated 6 hits 6 paints 14 skipped 84 refused [:]
#   (the baseline combined frame is a silent paint miss: no refusal is counted at all, EL-J)
set -e
cd "${0:A:h}/../../.."
METALUI_TRACE_RETAINED=1 swift test --build-system native --no-parallel \
    --filter aHeaderGrowingWhileAPanelSetZoomsReplaysItsPaint 2>&1 \
  | grep -E "^T1 step|retained paint (miss|translation)|retained prepaint miss" | head -60
