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

Lane 1 mutations (thirteen sites, numbered here in the order of the test headers' own `Mutation:` lines, not the implementer's m-numbers; run as the filtered 34-test set, the draw-text and surface suites; the
verifier re-ran **m9 only**, as a full unfiltered suite). The test named in each header is the one expected red:

| # | Mutation | Reddened |
|---|---|---|
| m1 | place with a rounded-point origin instead of `Text.paint`'s `origin`/`scaleFactor` | `drawTextEmitsTheGlyphRecordsATextEmitsAtTheSameDevicePosition`; it **survived** test 1 at 1x, so `aFractionalPointKeepsItsSubPixelPhase` was added (`923ad946`) and reddens it |
| m2 | swap the anchor's x and y fractions | `everyAnchorPlacesTheLayoutBoxAtThePoint` |
| m3 | ignore `width` | `aFiniteWidthWrapsAndNilIsUnbounded` |
| m4 | resolve against the default (light) theme | `theColourIsTheResolvedForegroundUnlessOverridden` |
| m5 | the rich-text `precondition` replaced by a pass-through | `aRichResolvedTextTrapsNamingDTE` |
| m6 | the no-sink `precondition` replaced by a pass-through | `aContextWithoutASinkTrapsNamingDTF` |
| m7 | the draw run in `finishFrame` of the headless renderer | `aHeadlessRendererRecordsButNeverRunsASurfaceDraw` |
| m8 | the pass's viewport the window's size, not the target's | `aSurfaceTextReadsBackEqualToTheSameTextDrawnByMetalUI` |
| m9 | **`renderer.upload(atlas)` moved back before the surface draws** | `aGlyphFirstInsertedByASurfaceDrawIsUploadedBeforeTheTextPass`, `aSurfaceTextReadsBackEqualToTheSameTextDrawnByMetalUI`, `textIsDrawnOverTheAppsOwnDrawing` (full suite, verifier) |
| m10 | text pass load action `.clear` | `textIsDrawnOverTheAppsOwnDrawing` |
| m11 | an empty pass always run | `aFrameWithNoSurfaceTextRunsNoTextPassAndOneUpload` |
| m12 | commit inside the pass helper | `theTextPassAddsNoSubmission` |
| m13 | `drawText` / `SurfaceTextSink` made `internal` / `public` | `drawTextCompilesFromAPlainImport`, `theSurfaceTextSinkIsUnreachableFromAPlainImport` (the two new guards, each red once) |

The verifier's first m9 added an extra early upload and left the later one: an equivalent mutant (the atlas is
unbound at the second upload anyway), killed and redone as a true move. Not re-run as full suites: m1-m8, m10-m13
(filtered sets only); the 34-test set covers each mutated site.

SDL mutations (each: commit first, one change in a copy, full unfiltered `Backends/SDL` run,
`git checkout` of the sources, `git status --short` empty after):

| # | Mutation | Reddened |
|---|---|---|
| 14 | text pass `first_instance` 0 instead of `start` | `anSDLSurfaceTextReadsBackEqualToTheSameGlyphsDrawnDirectly` |
| 15 | the text pass moved before the atlas copy pass (frame setup and loop moved above `SDL_BeginGPUCopyPass`) | `textIsDrawnOverTheAppsOwnPassOnSDL`, `anSDLSurfaceTextReadsBackEqualToTheSameGlyphsDrawnDirectly`, `aGlyphInsertedByASurfaceDrawIsUploadedBeforeTheTextPassOnSDL` |
| 16 | text pass load op `CLEAR` | `textIsDrawnOverTheAppsOwnPassOnSDL` |
| 17 | an empty pass for every surface drawn (C `continue` removed, a zero-count entry per request) | `anSDLFrameWithNoSurfaceTextRunsNoTextPass` (the verifier's counter-only stand-in, `last_text_passes` +2, also reddened `aSurfaceTextRangeOutsideTheGlyphBufferIsRefused` and the readback test) |
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

Record-phase re-take (merged with master `d062168c`, docs only; `swift package clean`, native build, unfiltered
`--no-parallel` run on a **locked screen**): `Test run with 4264 tests in 5 suites`, 0 `error:`, exactly the five
`AppKitPresentationTests` sheet issues of `CI-AF` and nothing else, `FR-J no-argument frame: succeeded=true`; typecheck
guards 263 (261 + the two of `DrawTextCompileGuards`). Inventory and undocumented scripts print nothing.

## §3 Verification owed or not run

- The fourteen demo images: `docs/probes/demo-pixels/compare.sh <scratch> 5f03ab7b HEAD` (HEAD `6a7747f4`) read `differing=0` and `scene identical` for all fourteen, controls as recorded.
- **Windows** compiles the new bridge signature in CI only (check SI3); the bridge adds no C
  enum, so no `rawValue` width question.
- Looks: human checks group `DT` (`DT1`–`DT4`), not run, an agent cannot.
- The locked-screen state was not probed; no real window was driven.

- **Limits the record states** (verifier's request): the headless renderer records no `drawText` glyphs and runs no
  text pass, so the Metal pixel pins run only on macOS hardware; a rich `ResolvedText` traps naming `DT-E`; text is
  drawn only after the app's draw returns, never under later app drawing (`DT-E` 2).
- Not re-run by the verifier: mutation 19 (`SDLGPUWindowGuard.beginDraw` removed; the implementer's table names the two
  tests it reddened), the Linux image (the implementer's 30 + 253), Windows (CI only). One `Backends/SDL` test,
  `SDLGPUShaderBuildProductTests.aBuildProductWithoutAMarkerIsAccepted`, failed once under a mutation run with an
  `NSCocoaErrorDomain 513` copying `append.comp.spv` on a loaded machine and passed in the unmutated 30 + 256 run:
  environmental, to confirm on a quiet one.
- The verifier read the default-build warning count from an incremental build; the implementer's clean re-take read 0.

## §4 Deferred, with owner

Rich `ResolvedText` in a surface (`DT-E` 1); text under later app drawing (`DT-E` 2, a layered
verb); `ResolvedText.firstBaseline` (`GT-G`); a per-label effect. Each waits for its first request.

## Adversarial branch check (5f03ab7b..22ade62c)

Re-taken by the checker on the final tree after `swift package clean`: native build 0 `error:` and no `warning:`; unfiltered run
`Test run with 4264 tests in 5 suites failed after 814.344 seconds with 5 issues`, the five being the `AppKitPresentationTests` sheet issues of
`CI-AF`; `FR-J no-argument frame: succeeded=true`. The inventory and undocumented scripts print nothing; `cmp CLAUDE.md AGENTS.md` identical.
The fourteen offscreen images read 0 differing pixels (scene identical) against 5f03ab7b with the compare script's controls non-zero.
`Backends/SDL` on macOS with `METALUI_REQUIRE_GPU=1`: 256 tests in 11 suites passed; Linux image: 253 passed.
Two mutations of the checker's own design: (A) `drawText` ignores its `color` argument (`SurfaceText.swift`) reddened
`theColourIsTheResolvedForegroundUnlessOverridden` (run cut short after the red, so a partial run); (B) the atlas upload moved back before the
surface draws (`MetalWindowRenderer.finishFrame`, a full unfiltered run, 4 issues) reddened `aGlyphFirstInsertedByASurfaceDrawIsUploadedBeforeTheTextPass`,
`aSurfaceTextReadsBackEqualToTheSameTextDrawnByMetalUI` and `textIsDrawnOverTheAppsOwnDrawing`. Both restored, `git status` clean.
