# 372 - The marker lane's width in `CodeView` (`CV-BU`)

Branch `feat/codeview-marker-width` from master `9dc1e9a8`. Class M, no divergence (labels untouched). Alloy wave 2, answer 8: centred.

**API.** `CodeView.gutterMarkerLane(width:)`, space advances clamped to 1...16, reserves the lane; default two, byte-identical. Markers stay centred and are clipped to the lane (a clip only for a marker wider than it). The hit area is the lane, which `gutterHit` already read from `laneWidthPx`.

**Costs.** Unchanged literals (`costLiteralsAreUnchangedByTheWidth`): the width is one plan integer.

**Tests** (`CodeViewMarkerWidthTests`): text shift and clip, default identical, clamp, hit area, cost. Mutations in the doc comments.
