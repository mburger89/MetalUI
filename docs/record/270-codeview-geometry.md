# 270. CodeView geometry (Alloy gap G35 A, `CV-AJ`, `CV-AK`)

Branch `feat/codeview-geometry` (master `b7df7e6a`). Rulings `CV-AJ` and `CV-AK` in `docs/superpowers/2026-11-07-code-view-decisions.md`. Class `M`; no divergence. Nothing was run on a display.

Alloy's LSP support (hover, diagnostics underlines, completion popups) needs point to offset and range to rectangles from outside the view. The plan (`CodeViewPlan`) existed only in `Layout` and in the frame's handler closures, in bounds space and device pixels.

## Shipped

- `CodeViewGeometry` (`@MainActor` class, shared through `CodeView.geometry(_:)`): `version`, `hit(at:) -> CodeHit?`, `rects(for:) -> [Bounds<Pixels>]`, `caretRect()`, `visibleRows`. `CodeHit` is `offset` (the boundary a press places), `character` (the grapheme under the point), `row`, `region` (`.text`, `.pastLineEnd`, `.virtualRow`, `.gutter`).
- `CodeViewPlan.hit(at:)` is the old `offset(at:)` extended; `offset(at:)` is now `hit(at:).offset`, so the press, drag and autoscroll paths are unchanged. `CodeViewPlan.rects(forBounds:)` walks the shown rows with `xPx`.
- Prepaint stores `plan` and `bounds.origin` into the box (one optional check when none). The box is not observable. Under retained replay prepaint is skipped and the box keeps the replayed frame's plan.

## Coordinates

View-local with render effects undone: `Hitbox.localPoint(point) - region.origin` is `onContinuousHover(.local)` (`Hover.swift` ~193), and `PopoverAttachmentAnchor.resolve(in:)` adds `bounds.origin` to `.rect(r)` (`AnchoredOverlay.swift` ~40). The plan hits in bounds space (`CV-AF`), so the geometry adds or subtracts `bounds.origin` at its edge.

## Staleness

Answers are for the last drawn frame, in its `version`'s offsets. After an edit and before the next frame they are stale; map an older offset with `CodeBuffer.map(_:from:bias:)`.

## Tests

`CodeViewGeometryTests` (five), each with a recorded mutation; see the PR description for the results.
