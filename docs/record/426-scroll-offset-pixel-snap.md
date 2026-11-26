# 426: a scroller presents its offset on the device-pixel grid (`DSA-J`; Piece 3(b) of the exact-redo plan)

Class `A` (a SwiftUI fidelity fix), no divergence row, no public API. Branch `fix/scroll-offset-pixel-snap`, base master `e3e566c7`. Plan: `docs/superpowers/plans/2026-11-25-exact-redo-and-movable-records.md`, Piece 3(b); evidence: record 425 and `docs/probes/swiftui-scroll-offset-pixel-snap.swift`.

## What changed

SwiftUI never presents a fractional scroll offset of its own making (record 425). MetalUI's wheel and trackpad deltas did, and every moved record under the scroller was refused (`fractionalTranslation`, then `inexactTranslation`) and paid a redo. The presented offset is now `round(offset * scale) / scale` (ties up).

- **Where it snaps: once, at the commit.** `ScrollChrome.resolveSlot` (prepaint's write-back) stores `presentedOffset(raw)` in `ScrollState.offset`. Paint reads it back through the same idempotent function (`resolvedOffset(pass: PaintPass)`), so `activeOffset`, `ScrollerFrame.offset`, hitboxes, the clip, `scrollTo` and the `scrollPosition(id:)` registry see one number. Layout cannot see the content size, so it reads `ScrollChrome.layoutOffset` (raw position snapped, unclamped) into `ScrollContext.offset`: lazy windows and `List` plan against the snapped value. `Window.scroll`'s `didScroll` and `Frame.applyScrollResolutions`' `moved` use `ScrollChrome.snap`. No rounding exists in the paint path (`Frame.swift` and `ClipMask.swift` are untouched; `Frame.swift` only gained the residue reset in `land` and the snapped `moved`).
- **Accumulation.** `ScrollState.residue` (and `ScrollAxisSlot.residue`) holds what the grid did not take. A wheel still writes `offset += delta`; the next prepaint computes `raw = offset + residue`, clamps, snaps, commits `offset`, and stores `residue = raw - presented`. Ten 0.3 pt deltas at 1x present 0 1 1 1 2 2 2 2 3 3. A program's position (a `scrollTo` landing, a glide step, an anchor placement, the clamp at an end) sets `residue = 0`. `sameScrollState` compares it, so a settled scroller writes nothing.
- **Bottom anchor and the end.** Clamp, then snap, then `min(snapped, snapDown(max(0, content - viewport)))`: the end is the last grid position at or before the content's end. Probe `F1` (399.5 in 300) reports 99.0 and so does `presentedOffset(99.5)` at 1x; at 2x 99.5 is on the grid. MetalUI's layout rounds to whole points (divergence 77), so a window builds a fractional extent only at a fractional scale; the rule is pinned through `resolveSlot`.
- **Open: the 2x grid.** Unverified (1x display only); the probe's injected 2x kept whole-point scroll positions (the window's backing stayed 1). Human check `PSN1` in `docs/verification/human-checks.md`; if SwiftUI stays whole-point at 2x, one function changes. No divergence row: no real difference is known.
- Not touched: `CodeView`, `TextEditor`, the table body (own offsets).

## Tests (`ScrollOffsetPixelSnapTests`) and their mutations

| Test | Mutation that reddens it (all run) |
|---|---|
| `aFractionallyMovedRowReplaysExactly` (scale 1, 2) | `presentedOffset` returns the clamped value unsnapped (M1: fractional/inexact refusals, no translation) |
| `slowSubPixelScrollingStillAdvances` (1, 2) | residue always dropped (M2: stalls at 0); M1 also |
| `aProgrammaticFractionalPositionIsReportedSnapped` (6 cases) | M1 (stored and painted differ) |
| `aBottomAnchoredScrollerWithAFractionalExtentSitsWhereSwiftUIPutsIt` | end bound rounds to nearest (M3: 100 at 1x), M1 |
| `aBottomAnchoredScrollerInAWindowSitsFlushWithTheEnd` | positive control |
| `thePresentedOffsetIsIdempotentAndNeverPastTheEnd` | M3 |
| `snappingAddsNoAllocationsAndNoElementRequestsToIdleAndScrolledFrames` | an allocation in `snap` (M4: 1562 to 1566) |

**Cost pin.** An idle forced frame of a scrolled scroller (scale 2) is 1562 allocations and 43 element requests, with and without a residue, and the same 1562 with snapping mutated out (M1): snapping adds none. The scroller's state version does not move on an idle frame.

## Existing tests that changed

- `scrollToAnAnchorLandsTheTargetAtTheAnchor` (`ScrollToTests`): the `y: 0.25` case expected 282.5; the offset is now presented on the 1x grid, ties up, so 283 (probe `F4a`: `scrollPosition(y:)` 0.3, 100.3, 100.7 present 0, 100, 101).
- `aFractionalScrollIsRefusedWithItsFieldAndWhoIsFractional` and `theRefusalDetailIsBuiltOnlyWhileSomethingListens` (`FractionalMoveAttributionTests`, record 425): they made a fractional offset with a 0.3 pt wheel step at scale 2, which SwiftUI never presents and MetalUI no longer does. They now scroll at scale 1.2 in whole points, where the entry offset in `Float` (`k / 1.2 * 1.2`) is still a hair off a sixteenth and the line says `fractional=entryOffset`; the `inexactTranslation` arm of the first test went (that refusal at scale 1.2 names the layout origin, which the second test already pins). **A fractional scale still refuses moved records** (`k/1.2` pt is a whole device pixel but not an exact `Float`); that is not fixed here and is the one case left for the plan's recompute cure (`FS-W`) if Alloy's trace shows it.
- The snapping itself needed no change to any other existing test: 7446 root tests in 80 suites ran before these two edits with exactly those three failing.

## Counts

See the CLAUDE.md line.
