# 347 - Terminal grid sink (`TRM-AU`..`TRM-AW`)

Renumbered as needed: open PRs #349 and #350 hold 346.

Branch `feat/terminal-grid-sink` from master `a9827471`; Phase 5.1 of `docs/superpowers/plans/2026-11-16-terminal.md`. Class M, `package` only, no divergence label, no inventory row (no public declaration). Ids `TRM-AU`..`TRM-AW`; `TRM-AQ`..`TRM-AT` belong to open PR #350.

**What landed.** `SurfaceTextSink` (`MetalUIScene`, record 141) is now also the grid sink: `fillRect(_:color:clip:)` records a solid rectangle as a glyph instance over a reserved, fully covered atlas slot (`solidKey`, `solidSlot`, `solidSide` 4, `solidInset` 1), in call order with the glyph sprites, in the surface's one batch. The renderers' existing glyph pipelines, the `ReplaySurfaceText` pass and the `DT-B` atlas upload draw it; **no C, shader, blob, pipeline, fixture version or `PortableReplay --expect` change**.

**Solid slot, not quads.** The plan's first try held. Sampling the whole slot bleeds (the linear filter reads the neighbouring texels at the quad's right and bottom edges: a 17 x 9 rect's pixel at x 19 read 217/255, a 1-wide column's last pixel 170, an 8 x 8 cell's bottom row 191); sampling the inner 2 x 2 of the 4 x 4 slot does not, so `ReplaySurfaceQuads` was not built. Measured red-first with `solidInset` 0 on Metal and on SDL (llvmpipe is covered by the same SDL tests in `metalui-portable`).

**Retained target (`TRM-AV`).** The `SurfaceTargetTable` keeps a surface's texture across frames and clears only a new or resized one (`isNewTarget`); the grid pass loads. A damaged-rows redraw therefore records an opaque row background then the row's glyphs; the rest of the surface keeps its pixels (tested: rows outside the redrawn one are byte-equal, none of the old row shows through).

**Tests.** Portable `GridSinkTests` (5: instance shape, solid slot coverage and margin, packed once, call order and batches, full atlas); macOS `GridSinkMetalTests` (5: exact rects at scale 1 and 2 over their four sides, no seam, glyph over and under a rect, partial-row redraw, element requests equal to a text surface); SDL `SDLGridSinkTests` (2: exact rects and cells at scale factors 1 and 2, partial redraw). Mutations, each red then reverted: `solidInset` 0 (Metal 7 tests, SDL both), rect one pixel short (Metal 5), solid key per call (portable 3), record on a full atlas (portable 1), text-pass load op clear (Metal partial-row, SDL partial-row).

**Not done here.** Cell metrics, glyph cache and synthetic box-drawing glyphs (5.2), the view and its row damage policy (5.3).
