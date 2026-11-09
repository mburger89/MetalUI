# 253. A test window to pixels (Alloy gap G25, `HT-AB`)

Branch `feat/test-window-snapshot`. Alloy wants README screenshots of a headless `TestWindow` with no desktop. Blocked: `Window.glyphAtlas` internal and `HeadlessWindowRenderer.finishFrame` dropped the atlas, so `Renderer.renderOffscreen(scene, size:)` drew blank text.

- **Portable seam.** `HeadlessWindowRenderer.lastAtlas` and `TestWindow.glyphAtlas` (read-only, the window's own atlas). `MetalUITesting` imports unchanged (`HT-A`). A fresh `Renderer.upload(_:)` copies the whole atlas when it has no texture, so no dirty-rect state is needed (`finishFrame` still clears it).
- **Helper.** New macOS-only library target and product `MetalUITestingSnapshot` (in `#if os(macOS)`, `PC-A`; no existing macOS target depended on both `MetalUITesting` and `MetalUIRender`): `TestWindow.snapshot() throws -> CGImage`, `snapshotPNG() throws -> Data`, `SnapshotError`. Size = content size x window scale factor; no `scale:` parameter. Class M, no divergence.
- **Why not only `lastAtlas`.** The fallback leaves each app to size the target, wrap BGRA and encode PNG; kept as the documented lower layer.
- **Linux/Windows.** Out of scope; see `HT-AB` item 4.
- **Tests** (`MetalUITestingSnapshotTests`, gated on a Metal device): size is 120 x 100 times scale at 1 and 2; red inside the rectangle; white background; ink in the text rows; an empty atlas draws none; PNG signature.
- **Mutation.** `snapshot()` passing an empty `GlyphAtlas`: `aSnapshotIsPointsTimesScaleWithTheRectangleAndTheText` reddened (glyph arm, both scales); restored.
- **Counts** (2026-11-09, `swift package clean`, native build, unfiltered `swift test --build-system native --no-parallel`): `Test run with 5756 tests in 26 suites passed after 566.155 seconds`, 0 `✘`, `FR-J no-argument frame: succeeded=true`. The three closeout probes print nothing.
