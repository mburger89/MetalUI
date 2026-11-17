# 358 - The fold chevron lane in `CodeView` (`CV-BN`)

Branch `feat/codeview-fold-gutter` from master `7d4d38ff`. Class M, no divergence (labels untouched). PR 9 of the editor-essentials plan for Alloy (G6); builds on the fold model of record 343 (`CV-BL`) and the hidden-row layout of record 354 (`CV-BM`). Numbered 358 because 350 to 357 are taken by master and open lines; expect renumbering.

**What landed.**
- `CodeView.foldGutter(showsOnHover:onToggle:)` and `CodeViewGeometry.foldChevronRect(line:)` (two public declarations, inventory rows covered by the existing view and `code-geometry` rows, doc comments).
- `Code/CodeFoldGutter.swift`: the stored config, `CodeViewPlan`'s chevron hit test, geometry cell, toggle and accessibility nodes, `CodeViewStats.foldChevronNodes`.
- `CodeViewPlan`: `chevronPx` (the lane, added to `gutterPx` only with a fold state), `Row.chevron`, the two glyph layouts from the marker cache, `chevronsShown` from `CodeViewState.gutterHovered`; the numbers move left by the lane; paint draws the glyphs by translation in the gutter clip.
- `CodeView.prepaint`: the hover attachment (composed with the text hover's `localContinuous`), only for `showsOnHover`; `CodeEditSession.press`: the chevron press first (toggle, `onToggle`, consumed).

**Costs.** See the ruling: with and without `foldGutter`, steady 2 / 0 / 1 / 0 / 1 and keystroke the same; a hover enter and leave one frame at the keystroke cost; a move within the gutter adds no frame and no state write over the same move with no fold gutter (a pointer move over a `CodeView` costs a frame and two plain writes in the harness regardless, the scroll chrome's).

**Tests.** `CodeViewFoldGutterTests.swift` (11). Mutations shown red (each alone): the press falling through to the bar handler, the hover write not compared, open chevrons always drawn, the outermost range chosen, the lane reserved without a fold state, `onToggle` not called, accessibility nodes built without a client.

**Not done / notes.** The chevron's accessibility node is a button to read and locate; a press from accessibility is not wired. A chevron on a line a fold hides is not drawn (no row). The chevron cell overlaps the reach of the gutter bar by a few points; the chevron press wins there on lines with a chevron.
