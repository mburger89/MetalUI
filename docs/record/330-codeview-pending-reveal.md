# 330 - A CodeView reveal pending at mount is applied (`CV-BA`)

Branch `fix/codeview-pending-reveal` from master `ab099a02`. Class M, no divergence. Alloy report: `paneState.select(range, reveal: true)` in the transaction that activates an inactive tab (the `CodeView` mounts in that build), or F12 into a file loaded but not yet shown in the pane, left the caret moved and the view at the top.

**Why the first-frame rule existed.** `CV-V`: the reveal is a compared write of the view's own state, so a view appearing later must not replay an old reveal; `CV-AY`: a swapped state reveals nothing. Both were implemented as `revealSeen == nil` on the first frame meaning "honour nothing".

**What landed.** `CodeSelectionState.revealHandledSerial` / `revealHandledFrame` (`package`, `@ObservationIgnored`), written by the plan when a view takes a serial in. A mounting view applies the reveal if the serial is ahead of the handled one (pending) or if another view took it in during the same `Frame`; otherwise it is stale. A first frame with a zero-width or zero-height viewport leaves the reveal pending. A swap is not a mount and reveals nothing, and marks the new state's serial handled. Rule and rejected alternatives (a frame-generation tolerance): `CV-BA`.

**Steady-frame cost.** Zero: no observed access added; the two fields are plain writes made only when the serial changed. Literals as on master ab099a02: one retained card 4 requests / 0 hits / 1 miss / 0 ineligible, two 5 / 1 / 1 / 0 (`aSteadyFrameWithAHandledRevealCostsWhatItDidBefore`).

**Tests** (`Tests/MetalUITestingTests/CodeViewPendingRevealTests.swift`), each with its mutation in its doc comment.

**Limits.** A reveal requested long ago on a state no view has ever shown is still applied when the first view mounts; callers that do not want that pass `reveal: false`.
