# `drawText` in a GPU surface — design

Round 2 item 5; rulings `DT-A`…`DT-H` in
[`../2026-10-22-draw-text-decisions.md`](../2026-10-22-draw-text-decisions.md).
Branch `feat/draw-text` from `5f03ab7b`. Record §141. Status: LANDED, built (both lanes verified `ok`; record §141).

## Outcome

**Built, not carried** (`DT-A`), on a capability basis, not a speed one (`DT-I`: the overlay is 0 layout measures, 1 measure and 1 `placeGlyphs` per label per frame at head): the three things `GT-F` named as blockers are
gone on inspection. No shader change (the glyph pipelines are already premultiplied
source-over into the target's format on both renderers, so `TE-AD` and replay parity
are untouched); the atlas upload order is movable (`DT-B`); the pipeline is
MetalUI's, not the app's (`DT-A`, a MetalUI-owned pass per surface, after the
app's draw). Scope is **plain text**; rich text refuses by name and text-under-later-drawing
is carried (`DT-E`).

## Inventory (what exists at `5f03ab7b`)

`MetalDrawContext` (`MetalUIRender`, public struct, `package init`),
`SDLGPUDrawContext` (`Backends/SDL`, outside the census), `GPUSurfaceContext`
(`MetalUIPlatform`, public protocol, five reads and `clear`), `SurfaceDrawRequest`,
`SurfaceTargetTable`; `MetalWindowRenderer.finishFrame` (upload, table update, draws,
encode), `Renderer.upload`/`encodeGlyphs`/`atlasTextureWasEncoded`;
`SDLWindowRenderer.finishFrame` and C `mui_renderer_finish`/`encode_frame`/
`draw_primitives`; `TextMeasurer.ResolvedText` (`MetalUI/TextMeasurer.swift`);
`Frame.drawSprite` (`Frame.swift` ~3090) and `Text.paint` (`Text.swift` ~416), the
two functions `drawText` must reuse; `HeadlessWindowRenderer.finishFrame` (records
surface requests, runs no draw).

## Public API

```swift
// MetalUI (the module that owns ResolvedText, Color, UnitPoint)
extension GPUSurfaceContext {
    @MainActor public func drawText(_ text: TextMeasurer.ResolvedText, at point: Point<Pixels>,
                                    anchor: UnitPoint = .center, width: Pixels? = nil, color: Color? = nil)
}
```

Doc comment names `DT-A` (drawn over the app's drawing, after its draw returns), the
point's space (points from the surface's top-left, y down, times `scaleFactor`),
anchor and width semantics (probe arms B and C), plain-only (`DT-E`), and that a
context with no sink (an app-defined fake) traps. Class **M** (inventory map row for
`drawText`; `MetalDrawContext` and `GPUSurfaceContext` rows unchanged because no
public member is added to them). `docs/api-overview.md` §GPU surfaces gains the verb;
`docs/migration.md`: **no note** (no public or defaultless requirement is added;
`GPUSurfaceContext.textSink` is `package` with a default).

`package` (no census row): `SurfaceTextSink` and `GPUSurfaceContext.textSink`
(`MetalUIPlatform`), the contexts' `package` sink parameter. `ResolvedText` gains an
internal colour-context field (a new stored property crossing a module boundary:
`swift package clean` once, `CLAUDE.md`).

## Files and lanes (sequential: one agent at a time here; disjoint files)

**Lane 1 — root package, Metal and the portable seam.**
- `Sources/MetalUIPlatform/SurfaceTextSink.swift` (new), `GPUSurface.swift` (the
  `package` requirement and default).
- `Sources/MetalUI/SurfaceText.swift` (new, the verb: `textLines`, `placeGlyphs`,
  `atlas.packed`, `MUIGlyph` with a whole-target mask), `TextMeasurer.swift` (capture
  the reading point's theme and scheme beside the font).
- `Sources/MetalUIRender/MetalDrawContext.swift` (sink field),
  `MetalWindowRenderer.swift` (create the sink per frame, move `renderer.upload(atlas)`
  after the draws, run the text passes), `Renderer.swift` (`encodeSurfaceText(batch:
  into: target in: commandBuffer)` over the existing `glyphPipeline`; a counter
  `lastSurfaceTextPasses`).
- `Sources/MetalUITesting/HeadlessWindowRenderer.swift` (honest: records, never
  runs a draw; a comment and a pin).
- Tests under `Tests/MetalUITests`, `Tests/MetalUITestingTests`; `docs/guides/drawing-and-gpu.md`
  (the "How do I put a label over a GPU surface?" section gains the `drawText` recipe
  and keeps the overlay recipe for accessible, selectable, themed labels) and its
  `GuideMirrors*.swift` region; `docs/api-overview.md`; the inventory map and census.
- Lane 1 lands, builds and commits **before** lane 2 starts (lane 2 reads the sink).

**Lane 2 — `Backends/SDL`.**
- `Sources/MetalUISDL/SDLGPUDrawContext.swift` (sink field),
  `SDLWindowRenderer.swift` (append the recorded glyphs after the scene's, build
  `ReplaySurfaceText` entries, pass them), `Sources/SDLBridge/SDLBridge.c` and its
  header (`mui_renderer_finish` parameter, the pass loop between the atlas copy and
  `encode_frame`, `mui_renderer_last_text_passes`), SDL tests.
- Every new test helper creating an `SDLPlatform` arms `armMainRunLoopExitCheck()`;
  run in `Backends/SDL` (`METALUI_REQUIRE_GPU=1`) and in the Linux image
  (`metalui-portable`, lavapipe, volume `metalui-sdl-build-draw-text`); Windows is
  compiled by CI only (check SI3).

## Implementation notes

1. The sink is created by the renderer per `finishFrame`, handed to each context,
   read after the draw loop. A surface that recorded no glyph gets no pass.
2. `drawText` order inside one surface is call order; across surfaces, request order.
3. Skipped glyph (`slot.width == 0`, a space) records nothing, as `drawSprite` does.
4. An atlas that cannot place a glyph (`packed` returns nil) drops that glyph, as
   `drawSprite` does, and counts nothing new.
5. The text pass's projection is the window's ortho for the target's size; the
   viewport uniform is the target's width and height; load action `.load`, store
   `.store`.
6. `MV-F` item 5's `commandBuffer.status == .notEnqueued` trap runs after the text
   passes too (they only encode).

## Tests (name — red before — mutation that must redden it)

Lane 1, portable (`Tests/MetalUITestingTests/DrawTextTests.swift`):
`HeadlessWindowRenderer` never runs a draw (`DT-F`), so these tests call `drawText`
on a `package` test context (a `GPUSurfaceContext` fake holding a real
`SurfaceTextSink` and an atlas) and compare the sink's `MUIGlyph` records with the
records a `TestWindow` frame's scene holds for the same `Text`.
1. `drawTextEmitsTheGlyphRecordsATextEmitsAtTheSameDevicePosition` — does not compile
   before; mutation: `drawText` places with a rounded-point origin instead of the
   `Text.paint` call's `origin`/`scaleFactor` — reddens.
2. `everyAnchorPlacesTheLayoutBoxAtThePoint` (nine anchors vs the measured size,
   probe B) — mutation: swap the anchor's x and y fractions.
3. `aFiniteWidthWrapsAndNilIsUnbounded` (probe C; line count and height) —
   mutation: ignore `width`.
4. `theColourIsTheResolvedForegroundUnlessOverridden` (a token colour under a dark
   scheme; an explicit `color:`) — mutation: resolve against the default theme.
5. `aRichResolvedTextTrapsNamingDTE` and `aContextWithoutASinkTrapsNamingDTF`
   (exit tests) — mutation: replace each `precondition` by a silent return.
6. `aHeadlessRendererRecordsButNeverRunsASurfaceDraw` — mutation: run the draw.

Lane 1, Metal (`Tests/MetalUITests/DrawTextMetalTests.swift`, macOS, an offscreen
`MetalWindowRenderer` as the existing `MetalView` tests use):
7. `aSurfaceTextReadsBackEqualToTheSameTextDrawnByMetalUI` — the target's pixels
   (read back, whole-device-pixel origin, scale 1 and 2) equal the window pixels of
   the same `Text` at that origin, both over a transparent clear (premultiplied
   bytes compared, no opaque backdrop); mutation: set the pass's viewport to the
   window's size (pixels shift).
8. `textIsDrawnOverTheAppsOwnDrawing` (the app clears opaque red, then `drawText`;
   red survives, text on top) — mutation: the text pass's load action `.clear`.
9. `aGlyphFirstInsertedByASurfaceDrawIsUploadedBeforeTheTextPass` (counted dirty
   rects after the draw and non-blank readback) — mutation: move `renderer.upload`
   back before the draws (blank glyphs).
10. `aFrameWithNoSurfaceTextRunsNoTextPassAndOneUpload` (`lastSurfaceTextPasses == 0`,
    upload count equals today) — mutation: always run a (empty) pass.
11. `theTextPassAddsNoSubmission` (buffer `.notEnqueued` after, one commit) —
    mutation: commit inside the pass helper.
12. Compile guards (`typecheckFile`, plain import): `drawTextCompilesFromAPlainImport`
    and `theSurfaceTextSinkIsUnreachableFromAPlainImport` — mutate each red once
    (make the sink `public`; make `drawText` `internal`).
13. `theDrawingGuideASurfaceDrawsItsOwnLabel` (a `// guide: drawing-and-gpu.md #n`
    mirror; `GuideDocCheck` red until the block is copied byte for byte).

Lane 2 (`Backends/SDL/Tests/MetalUISDLTests/SDLDrawTextTests.swift`):
14. `anSDLSurfaceTextReadsBackEqualToTheSameTextDrawnByTheReplay` — readback of the
    surface target (`mui_surface_read_rgba`) equals the replay of the same scene's `Text` (the replay harness
    is the SDL pixel oracle); mutation: swap `first_instance` for 0.
15. `aGlyphInsertedByASurfaceDrawIsUploadedBeforeTheTextPassOnSDL`
    (`lastAtlasBytes > 0`, non-blank) — mutation: encode the text pass before the
    copy pass.
16. `textIsDrawnOverTheAppsOwnPassOnSDL` — mutation: load op `CLEAR`.
17. `anSDLFrameWithNoSurfaceTextRunsNoTextPass` (`mui_renderer_last_text_passes`).
18. `aSurfaceTextRangeOutsideTheGlyphBufferIsRefused` — mutation: drop the bounds check.
19. `drawTextInsideADrawDoesNotTripTheDrawGuard` — `SDLGPUWindowGuard` stays quiet;
    the two existing guard pins stay green.
All gated per `windowsPresentFrames` only where a presented window is needed; the
offscreen-renderer tests run in the Linux image.

Every mutation: commit first, restore from a copy, full unfiltered suite, `git
status --short` after, name every reddened test; a suite with no summary after 12
minutes is a hang (kill only this worktree's run).

## Verification

Root: `swift package clean`, native build 0 `error:`, only SwiftPM's deprecation
`warning:`; native unfiltered run, one summary line (**4248 tests in 3 suites** at
`5f03ab7b` plus the new), `FR-J no-argument frame: succeeded=true`; `swift build
--build-tests` 0 warnings; inventory and undocumented scripts print nothing, census
re-recorded; the fourteen images 0 px against `5f03ab7b`
(`docs/probes/demo-pixels/compare.sh <scratch> 5f03ab7b HEAD`); `Backends/SDL` on macOS
and in the Linux image; replay parity unmoved (no shader byte changes: `git diff --stat`
shows no `.metal`, `.hlsl`, `.spv`, `.msl`, `.dxil`); the `MetalUILayout`/`MetalUIScene`
import rules; `theLegacyEngineSymbolsAreAbsentFromTheTestProcess`.

## Demo expectation

No default-demo change (`DemoFrameDeterminismTests` `Expected.swift` unedited, fourteen
images 0 px). `METALUI_METALVIEW_DEMO=1` may gain a section **in its own function**
(Windows 1 MB stack) labelling the existing surface with `drawText`, only if it is
not one of the fourteen; otherwise none.

## Human checks (group `DT`, added at the Record phase; an agent cannot run them)

- `DT1` macOS: a `drawText` label beside the same `Text` overlay at 1x and 2x —
  same weight, position within a device pixel, no halo at the glyph edges.
- `DT2` Linux and Windows (SDL): the same, on a real window.
- `DT3` A label moving every frame with a `.continuous` surface: no flicker, no
  one-frame lag against the app's own drawing.
- `DT4` Resizing the window while a label is up: the label stays crisp (the target
  is recreated and redrawn).

## Deferred, with owner

- Rich `ResolvedText` in a surface (`DT-E` 1) — the first request needing a styled label.
- Text under later app drawing (`DT-E` 2) — the first request needing it; a layered verb.
- `ResolvedText.firstBaseline` (`GT-G`) — unchanged.
- A per-label effect (shadow, blur) — not offered; the surface's own `.opacity`/`.blur` apply.
