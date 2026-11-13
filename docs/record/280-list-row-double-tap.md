# 280. A count-2 tap on a List row's child no longer swallows the row's selection (`DD-AJ`, Alloy G39)

Branch `fix/list-row-double-tap`. In `List(selection:)`, a row child with `.onTapGesture(count: 2)` stopped a single click on it from selecting the row, even after the double-click interval; a click elsewhere in the row selected.

- **Root cause.** The row's selection is its `Box`'s `onClick`. The gesture-carrying child is the press's topmost opaque hitbox, so the arena forms on it and `IX-D` item 2 (an ancestor's `onClick` never joins) leaves the row's click unrun. Not a timing problem: the pending count-2 never mattered.
- **Fix.** `AXNode.isSelectableRow` (a flag, set by `List` on its row boxes); `GestureArena.holdsMultiClickTap`; `Window.owedRowSelection` records, at each press, the nearest flagged row above a no-`onClick` target when the arena holds a live tap of >= 2 clicks, and `runRowSelectionClick` runs the row's click at the release (same moment and same pressed-and-released-on-the-target test as `dispatchClick`; selection stays on mouse-up). The double tap still fires once; the second click's selection writes nothing.
- **Single-count `onTapGesture` on a row child**: does not select today and is left unchanged (pinned by a test). Widening is dropping the `>= 2`. SwiftUI's behaviour is as reported by Alloy; no probe was run.
- **Not touched**: Buttons in rows (their `onClick` target keeps the press), gestures outside Lists, `SpatialTapGesture.clickCount`, the arena tests.
- **Tests** (`ListSelectionTests`): `aSingleClickOnACountTwoChildSelectsTheRow`, `aDoubleClickOnACountTwoChildSelectsAndFiresTheDoubleTapOnce`, `aCountTwoTapOutsideAListStillFiresOnTheDoubleClick`, `aSingleCountTapOnARowChildKeepsItsCurrentBehaviour`. Mutation: `holdsMultiClickTap` forced false reddens the first two (4 issues).
- **Human check**: `VL6`.
