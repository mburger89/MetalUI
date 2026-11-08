# Record 245: the gutter-bar context menu at any offset (Alloy gap G12)

Branch `fix/gutter-context-menu-offset` (master `585e3e06`). Ruling `CV-AF` in `docs/superpowers/2026-11-07-code-view-decisions.md`. Class `M`, no divergence, no public API change.

## 1. The bug

`CodeView.gutterBarContextMenu { hit in ... }` opened only when the view sat at the window origin; with a 50 pt spacer above it a secondary press on a bar opened nothing. `onGutterBarClick` worked at any offset.

## 2. Root cause

Two paths, two spaces. The press path (`Window.dispatchTextInput`) hands the code session `Hitbox.localPoint(mouse.position)`, which is the window point itself outside an effect, i.e. the view's **bounds space**; `CodeViewPlan.gutterHit(at:)` (`plan.originX/originY` are the bounds origin) hits in that space. The context-menu path (`Window.dispatchContextMenu`) hands the builder the press **relative to the region's origin** (`CI-R` item 3: `inRegion - region.origin`), and the closure in `CodeView.prepaint` passed that straight to `gutterHit(at:)`. The two spaces coincide only at the origin.

## 3. Fix

The closure adds `bounds.origin` back before `gutterHit(at:)` (`Sources/MetalUI/Code/CodeView.swift`, the `gutterMenu` block). The fall-through to the view's own `contextMenu` is unchanged (it takes the region-relative point by contract). Checked and left alone: the press, the drag and its autoscroll take `localPoint` (bounds space) like the press; the menu anchor is the region's drawn bounds (`MA-B`), not the located point.

## 4. Test and mutation

`aContextMenuOnAGutterBarHitsTheBarWhereverTheViewSits` (`CodeViewImeBlinkTests.swift`): a `CodeView` under a 50 pt spacer and a 30 pt leading inset; the press reports the bar, the secondary press presents `Revert 7`, the item runs, a press off the column presents nothing. Red on master `585e3e06` (no menu presented), green with the fix. Reverting the fix reddens that test only; the existing 14.1 and 14.2 stay green because their view sits at the origin, which is why the bug survived.
