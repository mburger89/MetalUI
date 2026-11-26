# 428: an axis that does not move needs no sixteenth (`FS-W`)

Class `M`, no divergence, no public API. Branch `perf/unmoved-axis-fraction`, base master `3de15d73` (record 426). Cost rule from the user: Alloy is to be fast without
using a lot of memory or resources, so nothing is added per frame: one compare against zero per number, no allocation, no cache.

## Evidence

Alloy's streaming transcript (real CoreText measures), `METALUI_TRACE_RETAINED=1` over 30 streamed deltas: 236 `inexactTranslation` refusals, every one
`[leaf=rect field=bounds.origin.x value=369.356445 fractional=leaf move=(0,-26)]` (also x = 371.063965, 371.400391; moves (0,-26), (0,-42), (0,-91)). The moves are purely
vertical and whole-pixel; the x is the text-measured start of an inline background and never moves. `movedLeaf` demanded `p.x`, `p.y`, `p.x + dx` and `p.y + dy` all be sixteenths.

## The change

On an axis whose shift is exactly `0` the moved coordinate is the old one bit for bit (`shifted(_:by:)` returns it), so the sixteenth check of that axis is skipped
(`isExactShift(_:by:free:)`); the axis that moves keeps both checks. Sites changed: `movedPaintRecord`'s entry gate, `movedLeaf`'s `exactMove`, `movedHitbox` (three guards), the
element bounds of `movedPrepaintLedger` and `movedCombinedLedger`, the geometry notes' origin (`movedGeometryNotes`, `movedCombinedGeometryNotes`), the accessibility frames
(`movedAccessibility`, `shiftedLocals`), and the RK-AO detail text, which skips the unmoved axis so a remaining refusal names a number that really failed.
Left: `foldedRecord` (its numbers are the fold's inputs, compared bit for bit by `same`), the named spaces' `tx`/`ty` and linear part (rebuilt with `a * dx + c * dy`),
`hasDyadicLinearPart`, and `dx`/`dy` themselves (zero already passes).

## The condition that verify mode found

`METALUI_VERIFY_RETAINED=1` trapped on the first version in `anInexactCoordinateIsRefusedNotApproximated` (scale 1.2): moved y -30.0, fresh -30.000002. At a scale that is no multiple of
1/16 the unmoved axis's check was also the only witness that device numbers are exact products `pt * scale` (the moving axis's own checks pass on the old end by luck), so on master
that record was refused for its x. The skip is therefore made only where `isUnmovedAxisFree(scale:)` holds (a scale that is a multiple of 1/16: 1, 1.125, 1.5, 2, 3 ...), carried as
`Frame.unmovedAxisIsFree` and `PaintTranslation.free`; at 1.2, 1.1 or 4/3 the two-axis check stays. With it forced `false` the same 8 tests fail under verify mode as with it on (below), so none is new.

## Figures (debug build, `--build-system native`, portable text system)

The portable text system measures quarter points, so at scale 1 and 2 an inline background's x is a sixteenth and the harness cannot show the case; at scale 9/8 it measures 162.35774 px (no
sixteenth) and the fixture uses that scale, wheeled in steps of 8 pt (9 px, an offset of a multiple of 8 is exact; a streamed word's anchor move is a whole-point layout move, no whole pixel at 9/8).
`aWheeledTranscriptWithInlineBackgroundsMovesItsRows`: 50-row lazy transcript, tinted rounded chrome rows with an inline background in the first paragraph, 12 wheel steps.

| | element requests a step | allocations a step | records translated | refused |
|---|---|---|---|---|
| before (two-axis check) | 130.0 | 115,245 | 3 | `inexactTranslation` 85, `maskCrossingChanged` 5, `innerScope` 2 |
| after | 32.0 | 73,584 | 59 | `maskCrossingChanged` 5, `innerScope` 4 |

Steady frames: no pin moved, no ceiling moved (G51's fixture is at scale 2 with dyadic numbers, so its figures are the same; none could be lowered).

## Tests (`UnmovedAxisFractionTests`) and mutations

- `aLeafAtAFractionalXIsMovedByAVerticalScroll`: rows with an inline background at a non-sixteenth x, 9/8 scale, whole-pixel steps: translated, nothing refused, frame equals a fresh one. Mutation: `isExactShift` back to `sixteenth(v) && sixteenth(v + shift)` reddens it (inexactTranslation, translated 0).
- `aLeafAtAFractionalXIsStillRefusedByAHorizontalScroll`: the axis that moves keeps its checks.
- `aZeroShiftIsExactAndReturnsTheValueItself`: bit-for-bit return (negative zero stays), the not-free case, and which scales are free.
- `aWheeledTranscriptWithInlineBackgroundsMovesItsRows`: the table above.
- No end-to-end arm for a fractional y under a vertical move: the portable text system gives whole-point lines, so no fixture has one; the rule is symmetric in the code and the helper test pins it.

Verify mode (`METALUI_VERIFY_RETAINED=1`) over the retained, translation, scoped-redo, G51, scroll, finer-scopes and exact-redo suites (686 tests): no trap; 8 issues in 6 tests
(`TableRetainedTests` x4, `TableFrameCostTests`, `CodeViewInactiveSelectionTests`), the same with the skip forced off.
