# 141 — `drawText` in a GPU surface (round 2 item 5)

Branch `feat/draw-text` from `5f03ab7b`. Not a plan task: round 2 item 5 of the gpui-gap
priority list (user request 2026-10-21), the item `GT-F` (record §99) deferred. Spec
`docs/superpowers/specs/2026-10-22-draw-text-design.md`; rulings `DT-A`…`DT-L` in
`docs/superpowers/2026-10-22-draw-text-decisions.md` (next unused `DT-M`); probe
`docs/probes/swiftui-draw-text.swift` (arms A0, A, B, C, D, output in its header). Divergence
labels 705–714 reserved and **unused** (`DT-H`: a class-M verb, no SwiftUI API has a GPU
context).

**Status: LANDED — built, not carried.** Two lanes, each red first. The basis is capability,
not speed (`DT-I`: the overlay is 0 layout measures and 1 measure plus 1 `placeGlyphs` per
label per frame at head, so `drawText` saves nothing a user can see). What the three blockers of
`GT-F` turned out to be: no shader change (the glyph pipelines already blend premultiplied
source-over into `bgra8Unorm`), the atlas upload is movable (`DT-B`), and the pipeline is
MetalUI's own, not the app's (`DT-A`).

## §1 What was built

`GPUSurfaceContext.drawText(_:at:anchor:width:color:)` (MetalUI-only, class `M`, one inventory
row) records `MUIGlyph` sprites into a per-frame `SurfaceTextSink` (`package`, `MetalUIScene`,
`DT-K`); the renderer, after every surface draw has returned and the atlas is uploaded, runs
**one MetalUI-owned load-op pass per surface that recorded text**, over the app's own drawing, in
the frame's own command buffer (no submission, no fence, `MV-F` untouched). Plain text only; a
rich `ResolvedText` traps naming `DT-E`; a context with no sink traps naming `DT-F`. Layout is
the `Text` placement (`DT-C`), colour the one resolution function (`DT-J`).

- **Metal (lane 1):** `MetalWindowRenderer.finishFrame` makes the sink, moves `renderer.upload`
  after the draws (`DT-B`), `Renderer.encodeSurfaceText` over the existing `glyphPipeline`,
  counter `lastSurfaceTextPasses`.
- **SDL (lane 2, `DT-G`, `DT-L`):** `SDLGPUDrawContext` adopts `SurfaceTextSinkProviding`;
  `SDLWindowRenderer.finishFrame` appends the sink's glyphs after the scene's and passes
  `ReplaySurfaceText` entries; `mui_renderer_finish` validates each entry first (target, size,
  the range through `transforms_valid` as a glyph run), then after the atlas copy pass and before
  `encode_frame` runs one `LOADOP_LOAD` pass per entry with the viewport the target's size and
  `first_instance` through the existing vertex uniform. `mui_renderer_last_text_passes` is the
  work recorder. **No `.metal`, `.hlsl`, `.spv`, `.msl` or `.dxil` byte changed** (`git diff
  --stat`), so `TE-AD` and replay parity have nothing to land.

## §2 Measurements and pins

| Check | Result |
|---|---|
| Root, `swift package clean`, native build | 0 `error:`, the only `warning:` SwiftPM's deprecation notice |
| Root native unfiltered run, `--no-parallel` | **4264 tests in 5 suites passed** (4248 at `5f03ab7b` + 16 lane 1); `FR-J no-argument frame: succeeded=true` |
| `Backends/SDL` on macOS, `METALUI_REQUIRE_GPU=1` | 30 + 256 passed (six new: tests 14–19, `SDLDrawTextTests`) |
| `Backends/SDL` in `metalui-portable` (lavapipe, `METALUI_REQUIRE_GPU=1`) | 30 + 253 passed, the six new ones run (not skipped); 0 `warning:` |
| Inventory and undocumented scripts | print nothing; census unmoved by lane 2 (`Backends/SDL` is outside it) |

SDL mutations (each: commit first, one change in a copy, full unfiltered `Backends/SDL` run,
`git checkout` of the sources, `git status --short` empty after):

| # | Mutation | Reddened |
|---|---|---|
| 14 | text pass `first_instance` 0 instead of `start` | `anSDLSurfaceTextReadsBackEqualToTheSameGlyphsDrawnDirectly` |
| 15 | the text pass moved before the atlas copy pass (frame setup and loop moved above `SDL_BeginGPUCopyPass`) | `textIsDrawnOverTheAppsOwnPassOnSDL`, `anSDLSurfaceTextReadsBackEqualToTheSameGlyphsDrawnDirectly`, `aGlyphInsertedByASurfaceDrawIsUploadedBeforeTheTextPassOnSDL` |
| 16 | text pass load op `CLEAR` | `textIsDrawnOverTheAppsOwnPassOnSDL` |
| 17 | an empty pass for every surface drawn (C `continue` removed, a zero-count entry per request) | `anSDLFrameWithNoSurfaceTextRunsNoTextPass` |
| 18 | the text-range validation loop removed | `aSurfaceTextRangeOutsideTheGlyphBufferIsRefused` |
| 19 | `SDLGPUWindowGuard.beginDraw()` removed | `drawTextInsideADrawDoesNotTripTheDrawGuard` and the existing `aWaitInsideADrawTrapsInDebug` |

A first attempt at 15 moved the wrong `FrameDraw` block (an earlier function's) and did not
compile; its "result" was a stale binary and is discarded. The recorded run is the second, with
the block taken from `mui_renderer_finish`.

Instrument notes. Test 14 compares the surface path against the **same glyph records drawn by a
scene directly** (a scene that holds a glyph of its own, so the text range starts past zero and
`first_instance` matters); it does not re-derive the records from a `Text`, which lane 1's
portable test 1 pins. Readback is through the composite (`DT-L` 1). Test 18 drives
`mui_renderer_finish` by hand with a control arm; a deliberately out-of-range range with glyph
records present was not used (without the check it would be a real out-of-bounds GPU read).

## §3 Verification owed or not run

- The fourteen demo images: `docs/probes/demo-pixels/compare.sh <scratch> 5f03ab7b HEAD` (HEAD `6a7747f4`) read `differing=0` and `scene identical` for all fourteen, controls as recorded.
- **Windows** compiles the new bridge signature in CI only (check SI3); the bridge adds no C
  enum, so no `rawValue` width question.
- Looks: human checks group `DT` (`DT1`–`DT4`), not run, an agent cannot.
- The locked-screen state was not probed; no real window was driven.

## §4 Deferred, with owner

Rich `ResolvedText` in a surface (`DT-E` 1); text under later app drawing (`DT-E` 2, a layered
verb); `ResolvedText.firstBaseline` (`GT-G`); a per-label effect. Each waits for its first request.
