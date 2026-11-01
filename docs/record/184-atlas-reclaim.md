# 184 - glyph atlas reclaim (`GL-A`..`GL-J`)

2026-11-01, branch `fix/atlas-reclaim` from master `3a2c5715`; item MF-atlas (MetalFlow's report). Rulings:
`docs/superpowers/2026-11-01-atlas-reclaim-decisions.md`.

## 1. The report, re-measured

`Window.atlasExtent` is 1024; the shelf packer never reclaimed; `GlyphAtlas.evictUnusedSince` had no caller; `Frame.draw` returned silently on a full
atlas (record 05's row said so). MetalFlow's node cards are `.font(size: 14 * zoom)`, so each zoom level is a new set of `GlyphKey`s; a headless sweep
25% to 150% in 1% steps at scale 2 with one node filled all 1024 rows and every glyph after that was dropped (the readout drew "15 %"). The same sweep
is now the first test (`aZoomSweepNeverDropsAGlyph`: no drop, every emitted glyph inked and equal to a fresh window's, at least one rebuild).

## 2. What a retained record stores for a glyph

A `MUIGlyph` **by value, atlas rect included** (`atlasBounds`), not a `GlyphKey`. Holders found by grep of `MUIGlyph`/`.glyph(`: the retained paint
record (`RetainedSubtree`, via `CapturedPrimitive.glyph`) and its translated copies (`RetainedTranslation`, `RasterAnchor`), `TransitionStore` captures
and ghosts, `DragSession.snapshot` and `Frame.previousDragSnapshot`, `RasterCache` keys (`Shadow.keyLeaf` adds `g.atlasBounds`), and
`RetainedVerifySnapshot.glyphs`. `ShapingCache`/`ShapedText.placedGlyphs` store keys and pen positions, no rects. A graft stores a build journal, no
sprites. So a rebuild that moves glyphs makes the first group stale, which is why the design avoids moving a slot while any frame is in flight (`GL-A`,
`GL-B`) and keys or drops each holder across the one place a slot moves (`GL-D`).

## 3. Design (restart or next frame, growth, cap, keying)

- **No restart.** Growth inside the frame (`packed` doubles the atlas, every slot keeps its coordinates) removes the reason to restart, and a restart
  would need a checkpoint every frame (`GL-A`). Where growth cannot help (the cap, with older glyphs holding room) the frame drops and the window asks
  for exactly one more frame after it (`setNeedsRedraw()` in `Window.draw`, outside every phase).
- **Rebuild between frames** (`reclaimAtlasIfNeeded()`, top of `draw`): when three quarters of the rows are used and a quarter of the packed area was
  not touched by the last frame, or a drop asked. Lazy re-rasterizing, in paint order. Sized for the working set, back down after a busy frame.
- **Cap** 4096 (`Window.atlasMaximumExtent`); `GlyphAtlas(width:height:)` alone never grows.
- **Past the cap** a glyph is dropped, `droppedGlyphs` counts it, one DEBUG line on stderr.
- **Keying** `AmbientKey.atlasGeneration` (paint and prepaint records and every relation built on them), `BuildKey.atlasGeneration` (a graft the
  prepaint then refuses would redo the frame - measured), the raster key; transition captures and the drag snapshot are dropped on the frame the
  generation changed.

## 4. A finding worth keeping

With only `AmbientKey` carrying the generation, a rebuild frame **redid** (`retainedRedos == 1`): the graft still matched, the prepaint key did not, and
`EquatableComponent.prepaintGroup` requests a redo for a grafted occurrence its prepaint refuses (`RK-C`). The abandoned first attempt packed glyphs in
a different order, so the presented atlas differed from a fresh window's. `BuildKey.atlasGeneration` removes the redo; the retained test asserts
`retainedRedos == 0`.

## 5. Tests and mutations

| mutation (one at a time, then reverted) | tests turned red |
|---|---|
| `growAndPlace` never loops (growth off) | `aFullAtlasGrowsInPlaceAndKeepsEarlierSlots`, `aReclaimShrinksAGrownAtlasToTheWorkingSet`, `pastTheCapAGlyphIsDroppedAndCounted`, `aSingleFramesWorkingSetLargerThanTheAtlasGrowsIt`, `aGrownAtlasReplacesTheTextureAndKeepsEarlierGlyphs` |
| `wantsReclaim` always false | `aZoomSweepNeverDropsAGlyph` (`reclaimCount >= 1`), `aDropWithStaleGlyphsIsRecoveredByTheNextFrame`, `anAtlasWantsAReclaimOnlyWhenItIsNearlyFullOfStaleGlyphs` |
| `retainedAmbientKey()` drops `atlasGeneration` (set to 0) | `aRetainedOccurrenceMissesAfterTheAtlasIsRebuilt` |
| `graftBuildKey()` drops `atlasGeneration` (set to 0) | `aRetainedOccurrenceMissesAfterTheAtlasIsRebuilt` (the redo of section 4) |
| `reclaim()` marks nothing dirty | `aReclaimForgetsEveryGlyphAndAdvancesTheLayoutGeneration`; SDL: `aRebuiltAtlasIsUploadedInFull` (bytes moved are not the whole atlas) |
| `noteAtlasPressureAfterFrame` never redraws | `aDropWithStaleGlyphsIsRecoveredByTheNextFrame` |
| `packed` does not increment `droppedGlyphs` | `pastTheCapAGlyphIsDroppedAndCounted`, `pastTheCapGlyphsAreDroppedAndCounted`, `anAtlasMadeWithoutAMaximumNeverGrows`, `aDropAsksForARebuildOnlyWhenOlderGlyphsHoldRoom`, `aDropWithStaleGlyphsIsRecoveredByTheNextFrame` |
| `Window` never calls `reclaim()` | `aZoomSweepNeverDropsAGlyph`, `aDropWithStaleGlyphsIsRecoveredByTheNextFrame` |
| `reclaimAtlasIfNeeded` ignores a generation it did not cause | `aWindowNoticesARebuild` |
| `Renderer.upload` ignores a changed extent | `aGrownAtlasReplacesTheTextureAndKeepsEarlierGlyphs` (Metal) |
| `mui_renderer_finish`'s `atlas_new` ignores a changed extent (SDL) | the `SDLWindowRendererTests` process aborts (signal 6) in the grown-atlas frame; `aGrownAtlasIsRecreatedAndFullyUploaded` is the test that grows |
| `reclaim()` sizes for "everything" (no fit) | `aReclaimShrinksAGrownAtlasToTheWorkingSet`, `aZoomSweepNeverDropsAGlyph` |
| `resize` copies rows at the old stride | `aFullAtlasGrowsInPlaceAndKeepsEarlierSlots`, `aSingleFramesWorkingSetLargerThanTheAtlasGrowsIt` |
| the hit path never adds to `frameLiveArea` | `aReclaimShrinksAGrownAtlasToTheWorkingSet` |
| `Shadow.keyLeaf` drops the generation from a glyph's key | `aGlyphLeafKeyChangesWhenTheAtlasIsRebuilt` |

Each mutation was applied to the single spelling named, one at a time, and reverted. **Not covered by a red test:** `TransitionStore.forgetCapturedPrimitives()` and the drag snapshot's clearing in `reclaimAtlasIfNeeded` (no test builds a ghost or a drag across a rebuild); removing either reddens nothing.

## 6. Counts

2026-11-01, on `fix/atlas-reclaim` after `swift package clean`: `swift build --build-system native --build-tests`, then an unfiltered
`swift test --build-system native --no-parallel`: **root 4800 tests passed in 12 suites** (`FR-J no-argument frame: succeeded=true` printed). The new
tests are 13 in `AtlasReclaimTests` (replacing the 9 `AtlasEvictionTests`), 8 in `AtlasReclaimWindowTests`, 1 each in `AtlasGenerationKeyTests` and
`GlyphABITests`, the renamed `theGlyphAtlasIsReclaimedOnlyAtTheTopOfADraw`, and 1 field added to `everyReplayKeyFieldIsNamedWhenItDiffersAlone`
(`AmbientKey` is nine fields). Guards: not re-tallied by grep (none added). The retained test also passes under `METALUI_VERIFY_RETAINED=1`
(its hit counts are skipped there). `Backends/SDL`, `swift test $(python3 scripts/fetch-accesskit.py --print-flags) --filter 'SDLWindowRendererTests|SDLDrawTextTests|SDLSurfaceTests|ReplayFixtureTests|SDLGPUContractTests'`:
31 passed, including the two new (`aGrownAtlasIsRecreatedAndFullyUploaded`, `aRebuiltAtlasIsUploadedInFull`). The CLAUDE.md counts line is not edited.
