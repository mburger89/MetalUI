# 402: `CodeDecorations.paintedLineDecoration(row:)` (`CV-BZ`, Alloy)

Class `M` (MetalUI-only API; SwiftUI has no code view), no divergence (labels unchanged). Branch `feat/code-line-decoration-readback`, base master `a306e124`. Requested by Alloy, whose plugin-decoration tests found gutter bars by scanning drawn rects for 3 pt-wide ones (brittle, flaky). It follows `CV-AT` (`paintedRuns(in:)`, Alloy G36). **Numbering:** written as 401; renumbered to 402 because #411 (`fix/titlebar-live-resize`) merged first as 401 (#412 took 400 and #414 took 403).

## Change

- **API** (`CodeDecorations.swift`): `paintedLineDecoration(row:) -> CodePaintedLineDecoration?`; `CodePaintedLineDecoration` (`background`, `backgroundOwner`, `gutterBar: CodePaintedGutterBar?`, `gutterMarker`, `gutterMarkerTag`, `gutterMarkerOwner`, `changeBar`, `changeBarTag`, `changeBarOwner`); `CodePaintedGutterBar` (`color`, `lines`, `tag`, `owner`). Owners are names, `nil` for the default owner. The inventory-map row `code-decorations` names them.
- **One resolution.** The read is `lineDecoration(row:)` (the merged tree the plan reads), `gutterBar(overRow:)` (the span) and `strongestMarker(in: row..<row+1)` (the marker, empty text absent). The merged payload keeps an owner for the bar, marker and change mark but not for the tint, so the tint's owner is found by walking the owners' trees from the highest (priority, name) down. That order moved out of `rebuildLines` into a private `lineTreesAscending` both use, so the priority logic is written once. `rebuildLines` runs at a set only; the sort is the same.
- **Limits** (documented on the method): buffer rows only; a virtual row is not read back (its decoration lives in the plan; an accessor would need the plan); a folded header's hidden-row marker and change mark are fold state and are not merged in.

## Cost evidence

No stored state, no new cache and nothing on the paint path changes (only the owner sort was extracted, at set time), so no steady-frame pin was added; the existing owner cost tests (`anEditCostsLogarithmicWorkPerOwner`, `setCostIsLinearInGroupsAndZeroPerFrame`) pass unchanged.

## Tests

`CodeViewPaintedLineDecorationTests`, six: the higher-priority owner wins tint and bar and is named (swap, tie, per-field owners); a bar span reads the same from every row; a marker's winner follows `strongestMarker`; an undecorated row is `nil`; an edit above shifts the rows; the agreement test, for a scripted overlapping two-owner set every row's read-back against the scene's tint alpha, 3 pt bar hue and marker glyph, before and after an edit. 
## Mutations

Run on the committed code and restored from a backup copy (`cp`), `git status --short` clean after each.

| test | mutation | red |
|---|---|---|
| `theHigherPriorityOwnerWinsTheTintAndBarAndIsNamed` | the tint's owner walked from the lowest priority up (`.reversed()` dropped) | itself |
| `theHigherPriorityOwnerWinsTheTintAndBarAndIsNamed` | the bar's owner read as `nil` | itself, and `anEditAboveShiftsTheReadBackRows` |
| `aBarSpanReadsTheSameFromEveryRow` | `lines: row..<(row + 1)` | itself, and the two above |
| `aMarkersWinnerFollowsStrongestMarker` | the marker read from the raw payload, not `strongestMarker` | itself |
| `aMarkersWinnerFollowsStrongestMarker` | no `nil` for a row with nothing painted (the empty-marker row returns an empty result) | itself |
| `anEditAboveShiftsTheReadBackRows` | `sync()` removed from the accessor | itself |
| `theReadBackIsWhatTheViewPaints` | the tint taken from the lowest-priority owner that sets one | itself (8 rows) and the first test |
| `theReadBackIsWhatTheViewPaints` | (first attempt: `lineTreesAscending.first`, the empty default owner's tree, so it fell back to the real value and nothing reddened: a broken instrument, replaced by the `compactMap` form above) | |
| `anUndecoratedRowReadsNil` | the `guard` on an undecorated row and the final collapse to `nil` both removed (an empty result for every row) | itself, and four others |

Root 7309 to 7315 tests in 79 suites (+6, over master with #414), `--build-system native`, `--no-parallel`, green; both closeout probes print nothing.
