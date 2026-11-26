# 429: the close X sits inside a shaped selected tab (`TBS-R`)

Class `M` (TabStrip is MetalUI-only), no divergence row, no public API. Branch `fix/tab-close-inside-pill`, base master `3de15d73`. Reported by the Alloy code-editor app: under `.selectedTabShape(.capsule)` with `.selectedTabFill(.color(...))` the selected tab's close X straddled the pill's rounded right end (screenshot in the report). Ruling: `docs/superpowers/2026-11-07-tab-strip-decisions.md`, `TBS-R`.

## Cause

`TBS-M` insets a shaped fill 4 points above and below and 3 at the sides, so the capsule is 23 points tall with radius 11.5. The close slot (`TabStripCloseSlot`, 18 wide, the 16 x 16 glyph frame centred) still ended at the cell's trailing edge, so the frame's right edge was 1 point inside the cell and 4 inside the fill: its corners lay up to 8 points past the arc. The frame's corner stays inside the end cap only if its edge is about 6.4 points in from the fill's end (a 2 point clearance: 7.3).

## What changed

- `TabStripMetrics.closeTrailingInset(for: TabStripSelectionShape)`: the least whole number of points that puts the whole glyph frame inside the fill with 2 points (`closeClearance`) to spare. The glyph frame sits on a whole-point row (7.5 rounds to 8 in the 31-point cell), so the corner nearest the arc is `dy = r - 3` from the arc's centre; the frame's edge may lie `max(2, r - sqrt((r - 2)^2 - dy^2))` from the fill's end; the inset is `ceil(fillInsetX + that - 1)`, the 1 being the slot's own margin around the glyph. Values: capsule 10, `roundedRectangle(6)` 6, `roundedRectangle(2)` 4, `.rectangle` 0. The fill's insets (3, 4) and the glyph side (16) are now named constants shared with `TabStripFill` and the slot.
- `TabStripCloseSlot` takes `trailingInset` and pads its outermost modifier chain (outside the gestures, the accessibility node and the identifier): the hover wash and the hit target are the slot's and move with the X, the inset closes nothing. `.rectangle` passes 0 and builds no padding at all: tree and scene as before.
- Every tab of a shaped strip carries the inset (a tab with no slot has none), so the glyph does not jump when the selection moves.
- Width: a tab's natural width grows by the inset (capsule +10, `roundedRectangle(6)` +6). The width layout clamps to 96..220 and lays the content out at the clamped width, so at 220 the label gives the points up and truncates as before (`aTabAtTheMaximumWidthTruncatesAndKeepsTheXInside`: label 192, the cell 220).

## Tests and mutations

| Test | Mutation that reddens it (run) |
|---|---|
| `theCapsulesCloseXLiesInsideThePill`, `aRoundedRectanglesCloseXLiesInsideIt` (radius 6 and 2): all four corners of the laid-out 16 x 16 frame at least 2 points inside the fill rect (read from the scene) | **M1** `closeTrailingInset` returns 0: both fail (right corners at x 95 against a pill ending at 93, no clearance) |
| `theRectanglesCloseXIsWhereItWas`: the frame ends 17 past the label's frame, exactly | an inset applied to `.rectangle` |
| `everyTabCarriesTheInsetAndItGrowsTheCellByIt`: the next tab starts 10 (capsule) or 6 later, the unselected tab's cell too | M1; an inset only when `isSelected` |
| `aTabAtTheMaximumWidthTruncatesAndKeepsTheXInside` | M1 |
| `theCloseTargetMovesWithTheX`: a click on the X closes the tab; clicks in the cell's last 2 points close nothing | the inset inside the slot (the target grows with it) |
| `theCloseInsetCostsNoRequestPerTab` (`TabSplitSteadyCostTests`): capsule and rounded strips 76 requests, `.rectangle` 70 | an element per tab around the slot |

M1 was run: the capsule and rounded-rectangle geometry tests and the width test fail with the inset forced to 0. The first formula (a centred 16-point frame, 8 from the arc's centre) gave 9 and failed the test: the frame is pixel-snapped to y 8..24 in a 31-point cell, 8.5 from the pill's centre line, which is why the formula takes the nearer gap.

## Cost

The inset is one padding (a layout modifier) per slot, no element: a three-tab capsule strip is 76 element requests with and without it (measured with the inset forced to 0), `.rectangle` 70, the existing pins (`TabSplitSteadyCostTests` 70 with and without a menu) unmoved. TabStrip has no allocation pin.

## Human check

`TBS8` in `docs/verification/human-checks.md`.
