# Record 220: shape clips as masked groups (R4-5 PR C)

Branch `feat/clip-mask` (master `3c7eadb9`). Rulings `CM-A`..`CM-H` in `docs/superpowers/2026-11-07-clip-mask-decisions.md` (new prefix; `CM-G` is the SDL half, `CM-H` the divergences; next `CM-I`). Divergences **91 and 92 retired**, **224 added** (a clip the per-primitive rounded-rect mask cannot express falls back to the bounding box wherever no offscreen mask is built). Probe `docs/probes/swiftui-clip-mask.swift` (committed at `965dcb3f`). Plan: the reviewed R4-5 PR C plan; the deviations are in section 4.

## 0. Rulings as the code cites them

- **CM-A** (the mask as a group multiplier). An ellipse, a path, an even-odd or a non-antialiased `clipShape` paints its content into an offscreen group (`Frame.paintWithMask`, a `PaintScope` of kind `.composite` with a `mask` field; no new `Kind`) and the group's target is multiplied by the shape's coverage before it is drawn back. `Scene.insert(_:group:layer:transform:filter:mask:)` carries the mask as a second finalized scene (`Scene.groupMasks`, parallel to `groupFilters`; rects and images only, a precondition). A rounded rectangle, circle or capsule is exactly today's per-primitive mask (no group). **How `TE-AD` is met:** no record changes its stride and no shader source is new: the mask pass is `group_tint_fragment` at tint (1, 1, 1, 1) with a **destination-in blend** (source factor zero, destination factor source alpha, colour and alpha), so `dst *= mask.a`; `BackdropPipelines.mask` is the one new pipeline state (Metal), and the SDL/D3D12 equivalent is `g->mask`, the same stage over `BLEND_DST_IN` in `make_pipeline` (`replay.hlsl` and the blobs are unchanged, `SOURCE.sha256` too; parity frame 18 judges the blend on SDL-over-MSL, byte-equal, so stop condition 6 did not fire).
- **CM-B** (crossing rounded clips, divergence 92). `Frame.clipsCross` is true where `Frame.intersect` takes its last square-box fallback with some radius non-zero **and the box reaches a corner cut** of either rounded rect (the square beyond a corner's disc): a pair whose box misses every cut is exact as pushed and takes no group. At a `pushClip` (`Frame.paintClipped`) the crossing opens a mask scope whose mask is one rect: the new clip as its outline, the clip in force as its `contentMask` (coverage is the product of both rounded rects). At a flattening effect's entry (`cutToEntryClip`) the primitive keeps its own mapped mask uncut and joins a masked group whose mask is the entry clip. The pushed clip stays the square box, so hit testing and every primitive's own mask are unchanged.
- **CM-C** (opacity). Probe `CM6` reads per leaf (191, 64, 128): an opacity outside a clip fades each leaf. The mask mark carries alpha 1, `CapturedPrimitive.multiplyAlpha` multiplies the colours when the outermost mark is a mask (`fadesByOutermostMark`), and the quad is drawn at opacity 1.
- **CM-D** (what a group cannot hold). A scope holding a backdrop (material or glass) gets no mark and keeps the bounding clip (divergence 224, `masksFlattenedBackdrop`); a masked group over 8192 on a side is drawn per primitive under the bounding clip (`masksFlattenedOversize`); a surface is allowed. A lone untransformed plain rect that holds the whole ellipse is that ellipse rect (`masksBakedToEllipse`).
- **CM-E** (hit testing and accessibility). Both are the bounding rect (`TE-AQ` item 4), unchanged; pinned by `anEllipseClipStillClipsHitboxesToItsBoundingRect`.
- **CM-F** (mapping). Every site that edits a primitive's geometry maps the mask a mark carries (section 3).
- **CM-G** (SDL, D3D12 and the fixture). Section 7.
- **CM-H** (divergences). 91 and 92 retired, 224 added (`docs/divergences.md`, `docs/record/04-divergences.md`).

## 1. What was measured

- [MEASURED, probe header] `CM0` separates (ellipse exact: 0 differing pixels against `Ellipse().fill`, 1436 against the box; edge alphas 0/255 gap); `CM1` winding, even-odd and non-antialiased forms read as the plan expected; `CM2`/`CM2b`/`CM2c` read white at the square-box corners, so crossing rounded clips are exact in SwiftUI (92 is real); `CM3` the shadow is elliptical; `CM4` the mask turns with the content; `CM5` blur-then-clip is a sharp elliptical edge, clip-then-blur blurs it; `CM6` per leaf (so plan section 2.4 "do nothing"); `CM7` control holds.
- [MEASURED] The edge: the Metal ellipse mask against the ellipse primitive's own coverage is within 2/255 on four sample rows (`anEllipseClipMasksItsCorners`; stop condition 3 did not fire: the gap is below 2, the limit was 8).
- [NOT RUN] Window arms (hit testing in a live window), human checks `CM1`..`CM3` (an agent cannot; the screen was not touched).

## 2. Mutations (a scratch `git worktree` of `53a1c843`/`43d21478`, restored and removed; branch and spelling in the table)

Filter for every row: `ClipMaskTests|GroupMaskTests|finalizeKeepsEachGroupsMask|RetainedClipMaskTests|ClipStackTests|ClipShapeTests|PathTests|PathOpsTests|RenderEffectTests` (plus `GroupFilterTests|CompositingGroupTests` for M10 and M11 only). "Reddened" lists the tests that failed.

| id | mutation (file, spelling) | reddened |
|---|---|---|
| M1 | `Renderer.encodeGroups`: `if let mask = scene.groupMasks[index], false` (mask pass skipped) | `aMaskedGroupMultipliesItsTargetByTheMasksAlpha`, `aMaskScalesAllFourChannelsByItsAlpha`, `anEllipseClipMasksItsCorners`, `aPathClipMasksToItsWinding`, `anEvenOddPathClipLeavesTheHoleClear`, `aNonAntialiasedClipHasHardEdges`, `twoCrossingRoundedClipsIntersectExactly`, `crossingClipsAcrossAnOffsetIntersectExactly`, `anEllipseClipUnderARotationTurnsItsMask`, `anEllipseClipInsideAnOffsetMovesItsMask`, `aShadowOfAnEllipseClipIsElliptical`, `aSteadyMaskedFrameMakesNoTexture`, `aMaskAllocationFailureDrawsTheGroupUnmaskedByName`, `aLoneFillClippedToAnEllipseIsAnEllipseRect`, and others |
| M2 | `maskPrimitive(for:)` `.path`: the path's bounding rect as a plain rect | `aPathClipMasksToItsWinding`, `anEvenOddPathClipLeavesTheHoleClear`, `aNonAntialiasedClipHasHardEdges`, `aSteadyMaskedFrameMakesNoTexture` |
| M3 | `ShapeGeometry.clip` `.path`: `eoFill: own.isEOFilled` (the call's style dropped) | `anEvenOddPathClipLeavesTheHoleClear` |
| M4 | `ShapeGeometry.clip` `.ellipse`: `guard false else { …ellipse mask }` (antialiased flag ignored). **First spelling `guard true` was inverted and reddened ten unrelated tests; re-run with the right spelling** | `aNonAntialiasedClipHasHardEdges` |
| M5a | `Frame.clipsCross`: `return false` | `twoCrossingRoundedClipsIntersectExactly`, `crossingClipsAcrossAnOffsetIntersectExactly`, `aPairWhoseBoxMissesEveryCornerCutTakesNoGroup`, `aClipTouchingARoundedOutersEdgePushesTheSquareBoxAndIsMasked`, `aClipInsideNestedFlatteningEffectsIsCutOnlyByTheOutermostEntryClip` (first spelling `return false && …` mis-parsed as `false && A \|\| B`) |
| M5b | `paintClipped`: the crossing mask rect's `contentMask` the whole target, radii 0 (only one rounding) | `twoCrossingRoundedClipsIntersectExactly`, `aClipTouchingARoundedOutersEdgePushesTheSquareBoxAndIsMasked` |
| M6 | `cutContentToEntryClip`: `if false, clipsCross(…)` (the crossing arm removed) | `crossingClipsAcrossAnOffsetIntersectExactly`, `aClipInsideNestedFlatteningEffectsIsCutOnlyByTheOutermostEntryClip` |
| M7 | `ShapeGeometry.clip` rounded rect: `guard true else {…}` (every clip gets a path mask; "paintWithMask opened for every clipShape") | `aCircleCapsuleOrContainedClipTakesNoGroup`, `aPairWhoseBoxMissesEveryCornerCutTakesNoGroup`, `clipShapeClipsToTheShapesGeometry`, `clippedAndCornerRadiusClipOnTheProposalPath`, `clipShapeChangesNoLayout`, `aLegacyClipShapeClipsItsChildrenAndItsHitboxes`, `aLegacyClipShapeWinsOverClipped`, `aRoundedClipContainedInARoundedClipKeepsItsRadii`, `anUnevenRectangleIsARoundedRectangleGeometryWhenSmall`, `aClipInsideNestedFlatteningEffectsIsCutOnlyByTheOutermostEntryClip`, `aClipInsideAScaleInAScaledCanvasIsCutOnlyByTheOutermostEntryClip`, `aClipInsideNestedFlatteningEffectsAtDepthZeroIsNotCutByTheWindow` |
| M8 | `RenderEffect.apply`: `guard … isMasked, flattens else { return p }` (masks unmapped in the non-flattening branch) | `anEllipseClipUnderARotationTurnsItsMask` |
| M9 | the same with `!flattens` (the flattening branch) | `anEllipseClipInsideAnOffsetMovesItsMask`, `aShadowOfAnEllipseClipIsElliptical` |
| M10 | `liftSharedMarks`: the `!first.isMasked` condition removed (both arms) | `aShadowOfAnEllipseClipIsElliptical`, `aBlurInsideAnEllipseClipIsCutSharp` |
| M11 | `processScopes` blur arm only: an inline lift of every shared mark | `aBlurInsideAnEllipseClipIsCutSharp` |
| M12 | `paintWithMask`: the backdrop guard `if false, captures.contains…` | `aMaterialInsideAShapeClipClipsToItsBox` |
| M13 | `insertMaskedGroup`: the 8192 test `if false` | `anOversizeMaskedGroupClipsToItsBox` |
| M14 | `withoutRenderEffects`: `$0.kind == .composite && $0.mask == nil` (no barrier for a mask scope) | `aDeferredInsideAnEllipseClipIsNotMasked` |
| M15 | `Renderer.applyMask`: `state.release(scratch)` removed | `aSteadyMaskedFrameMakesNoTexture` |
| M16 | `Renderer.applyMask` failure branch: clears the target (the fallback draws nothing) | `aMaskAllocationFailureDrawsTheGroupUnmaskedByName` |
| M17 | `Scene.finalize`: `groupMasks = sortedGroupMasks` removed | `finalizeKeepsEachGroupsMask` |
| M18 | `bakingToEllipse`: `r.bounds.origin.x <= m…` flipped to `>=` (x and y). **Green on arrival** (the first test's leaf was exactly the ellipse rect, so `<=` and `>=` agree); the test gained a larger-leaf arm and a smaller-leaf arm, then red | `aLoneFillClippedToAnEllipseIsAnEllipseRect` |
| M19 | `Scene.capturedGroup`: the masked arm's mark replaced by `_ = shape` | `aRemovedEllipseClipFadesItsGhostMasked` |
| M20 | `replayPaint` fast path back to `insertIntoScene` per primitive | `aRetainedReplayOfAMaskedClipEqualsAFreshFrame`, `aMaskedClipInsideAnOccurrenceMissesWhenItMovesAndEqualsAFreshFrame` |
| M21 | `ShapeGeometry.clip` `.ellipse`: bounds inset 10 (the hit region routed through the mask) | `anEllipseClipStillClipsHitboxesToItsBoundingRect` (and four pixel tests) |
| M22 | `paintWithMask`: `withOpacityBase(body)` and the mark alpha = the entry opacity (the other `CM6` branch) | `anOpacityOutsideAShapeClipIsPerLeaf` |
| M23 | `Renderer.applyMask`: identity projection for the mask view | `aMaskedGroupMultipliesItsTargetByTheMasksAlpha` and every pixel test |
| M24 | `BackdropPipelines.mask`: destination factor `.one` | `aMaskedGroupMultipliesItsTargetByTheMasksAlpha`, `aMaskScalesAllFourChannelsByItsAlpha` and the pixel tests |
| M25 | `processScopes`: `flagMarkMasks` removed. **Green on arrival**: no test had a crossing pair whose outer clip was pushed inside an outer flattening scope; `aCrossingPairInsideAnOffsetMovesWithIt` added, then red | `aCrossingPairInsideAnOffsetMovesWithIt` |
| M26 | `cutToEntryClip`: a fresh `GroupToken()` per primitive instead of `scope.crossingMaskToken`. **Green, and by construction today**: every fill is its own leaf through `processScopes`, so the scope token merges only the primitives of one leaf array (a text draw's glyphs), and no test paints a multi-primitive leaf at a flattening-entry crossing. The pin counts one group per leaf (`groupsMasked == 2`); the token is kept for text | none |
| M27 | `RetainedTranslation.movedLeaf`: the marks' masks not moved | none: **unreachable**. An occurrence that holds a mask scope has passed an inner scope, and `paintTranslation` refuses with `innerScope` (`FS-D`) before `movedOps` runs; `aMaskedClipInsideAnOccurrenceMissesWhenItMovesAndEqualsAFreshFrame` pins the refusal by name. The code is kept for the day `innerScopes` loosens |
| M28 | `clipsCross`: the corner-cut test replaced by `return true` | `aPairWhoseBoxMissesEveryCornerCutTakesNoGroup` |

SDL half (`Backends/SDL`, run 2): scratch `git worktree` of the head (`cm-mut`, restored and removed), filter `SDLClipMaskTests|ReplayFixtureTests`, each mutation applied to one spelling and the tree restored with `git checkout -- .` before the next.

| id | mutation (file, spelling) | reddened |
|---|---|---|
| S1 | `ensure_backdrop_pipelines`: `i == 3 ? BLEND_OVER : BLEND_NONE` (the mask pipeline source-over, not destination-in) | `aMaskedGroupMatchesMetal`, `aMaskIsAppliedBeforeTheGroupsFilter`, `aMaskThatCannotBeMadeDrawsTheGroupUnmaskedByName` |
| S2 | `SDLGroupSet.Builder.visit`: the `if let mask = scene.groupMasks[index] { append(mask, childQuads: []) }` line removed (no mask runs). **First run trapped (`Index out of range` in the test's own subscript, which reddens but kills the process); the test now `#require`s the index** | `aGroupsMaskRunsAreShifted`, `aMaskedGroupMatchesMetal`, `aMaskIsAppliedBeforeTheGroupsFilter`, `aHalfTransparentMaskHalvesTheGroup`, `aMaskThatCannotBeMadeDrawsTheGroupUnmaskedByName` |
| S3 | `ReplayFixture.encoded()`: `if let mask = group.mask, false` (the writer omits the mask, writes `hasMask` 0 but a mask body is expected by the test's own v8 walk) | `aGroupsMaskRoundTripsInVersionNineAndVersionEightLoadsUnmasked` |
| S4 | `FlatFrame.init`: the mask's `append(mask, transformShift: 0, …)` (no shift) | `aFlatFrameShiftsAMaskScenesTransforms` |
| S5 | `render_groups` failure branch: a CLEAR pass over the target (the degrade draws nothing) | `aMaskThatCannotBeMadeDrawsTheGroupUnmaskedByName` |

`aMaskThatCannotBeMadeDrawsTheGroupUnmaskedByName` uses the `maskPoolFailsAllocation` hook (the scratch cannot be made); the plan's other degrade cause (no portable shaders) is the same branch (`ensure_backdrop_pipelines` fails before the scratch is asked for) but cannot be reached from `SDLWindowRenderer`, which always has them. [NOT RUN] a window-less renderer without the shader directory.

## 3. The mapping audit (plan section 2.2, stop condition 5 did not fire)

Every site that edits a primitive's geometry or its clip, and what it does with a mark's mask:

| site | mask handling |
|---|---|
| `RenderEffect.apply(to:flattens:outer:)` | wrapper over `applyToShape`: maps each mark's mask with the effect's geometry and none of its fade (`RenderEffect(alpha: 1, homography:)`); a mask that cannot be mapped (degenerate or behind the eye) drops its content (M8, M9) |
| `Frame.processScopes` | `flagMarkMasks` sets each mask's `innerMask` (from `GroupMark.maskDepth`) and `outerMaskInner` per scope (M25) |
| `Frame.cutToEntryClip` | the masks go through `cutContentToEntryClip`; the crossing arm (M6) |
| `Frame.insertFilteredGroup` | maps through `effect.apply`, so masks follow; no edit |
| `RetainedTranslation.movedLeaf` | moves each mask by the depth it was read at; unreachable (M27) |
| `CapturedPrimitive.replayed(mask:layer:)` (drag preview) | replays each mask the same way; `paintDragPreview` now inserts through `insertLeaves` after `bakeOpacityMarks()` (opacity marks fade the colours, masks are kept) |
| `Scene.capturedGroup(at:)` (ghosts) | a masked group re-marks its content with the mask scene's first primitive, read back (M19) |
| `bakeGroupAlpha`, `insertIntoScene`'s belt | drop masks with their marks (the bounding clip still cuts) |
| `liftSharedMarks` | stops at a masked mark (M10, M11) |

## 4. What the code forced (deviations from the plan)

1. **The mask carries no clip of its own for a shape mask.** The plan built the mask primitive with `contentMask = activeClip`; the shape masks use an unbounded content mask (the content is already cut by the bounding clip, and the product is the same whichever side cuts first), so they have no `innerMask` question. A crossing mask rect does carry a content mask (the outer clip), hence `GroupMark.maskDepth` (new, not in the plan).
2. **`clipsCross` is narrower than the plan's `exactIntersection`.** The plan returned non-nil wherever `intersect` fell to its last fallback with a radius non-zero. That made every rounded child touching a rounded parent, and every rounded node straddling a square canvas edge, a masked group. `clipsCross` also requires the square box to reach a corner cut of either rect (`boxReachesACornerCut`), the only places the box and the exact pair differ.
3. **A crossing at a flattening entry is one group per leaf**, not one per scope: see M26. Each group's box is its leaf's (small targets). Carried.
4. **No `PaintScope.Kind` was added** (stop condition 4 did not fire); the mask scope is `.composite` with `PaintScope.mask`, `crossingMaskToken` is a lazy property.
5. **`LayoutModifier.clipShape` gained a payload**: `case clipShape(any Shape, style: FillStyle = FillStyle())` (public enum). An external `case let .clipShape(shape)` pattern binds a tuple; `docs/migration.md` carries the line (record 220 section). `clipShape(_:style:)` is on both vocabularies; `ClipShapeBox` carries the style.
6. **Retained.** A mask scope inside an `.equatable()` occurrence is an inner scope: a moved occurrence misses with `innerScope` (a new member of the allowed refusal set in `aTranslatedLayoutReplayEqualsAFreshFrameAtEveryScale`). A replay at the same position is an exact hit and re-groups through `insertLeaves` (M20).
7. **SDL/D3D12** came in run 2 (section 7).
8. **Fixes to my own first drafts of the mutations** (M4, M5a spellings) are in the table; M18 and M25 were green on arrival and fixed with tests.

## 5. Pins moved (each with its cause)

| pin | was | now | cause |
|---|---|---|---|
| `clipShapeOfAnEllipseTrapsNamingDivergence91`, `clipShapeOfAPathTrapsNamingDivergence91` | trap | removed | 91 retired; replaced by `anEllipseClipMasksItsCorners`, `aPathClipMasksToItsWinding` |
| `twoCrossingRoundedClipsIntersectAsTheSquareBox` | named 92 | `twoCrossingRoundedClipsPushTheSquareBox` (same arithmetic, the pushed clip is still the box) | 92 retired; the exact pair is `twoCrossingRoundedClipsIntersectExactly` |
| `aClipTouchingARoundedOutersEdgeFallsBackToSquareCorners` | one root rect with square corners | `…PushesTheSquareBoxAndIsMasked`: one group, the content rect keeps the square mask, the mask scene holds the inner rounded rect cut by the outer | the pair is a crossing now |
| `aClipInsideNestedFlatteningEffectsIsCutOnlyByTheOutermostEntryClip` | node B's mask (290, 130) 30 x 40 | 60 x 40 whole, with a mask group whose mask is the canvas's clip (right edge 320); `lfbMasks` reads group scenes too | B crosses the canvas's square edge |
| `theBracketNodeDragIsCountedAfterTheGraft`, `…AtFb9a7e42`, `…AfterPrepaintReplay`, `theBracketNodeDragRebuildsTheWholeWindow` | rects 182, glyphs 550 | **174 and 437** | the bracket's nodes straddling the canvas's clip are masked groups; the group scenes' contents are not the root scene's count. Images 6, rasterized pixels 78312 and new textures 2 did not move |
| `aTranslatedLayoutReplayEqualsAFreshFrameAtEveryScale` | allowed refusals without `innerScope` | `innerScope` added | a rounded card straddling the scroller's edge is a masked crossing and an inner scope |
| `everyFrameChannelIsClassified` | — | five `.frameLocal` rows | `maskScopesPushed`, `groupsMasked`, `masksBakedToEllipse`, `masksFlattenedBackdrop`, `masksFlattenedOversize` |
| `PathOpsTests` | `geometry.clipRegion` | `geometry.clip()` | the trapping accessor is gone |
| allocation pins, the 1 MB stack test, `sceneSideTables…` | — | **did not move** | stop condition 7 did not fire |

## 6. Runs

- [MEASURED] Root on the final head (run 2), `swift package clean`, `swift build --build-system native --build-tests`, unfiltered `swift test --build-system native --no-parallel`: **`Test run with 5305 tests in 14 suites passed after 316.437 seconds`** (`FR-J no-argument frame: succeeded=true`, so the guards ran; 0 `✘` lines). The same suite with `METALUI_VERIFY_RETAINED=1`: **`Test run with 5305 tests in 14 suites passed after 314.690 seconds`**. The count is the run-1 count: run 2 added no root test (the demo strip is built by the existing `everyProductionTreeBuildsOnAOneMegabyteThread`, which passed with the strip in it). Run 1's first unfiltered run (before the corner-cut refinement and the pin moves of section 5) failed 26 issues in `aTranslatedLayoutReplayEqualsAFreshFrameAtEveryScale`, the four bracket pins and `aClipInsideNestedFlatteningEffectsIsCutOnlyByTheOutermostEntryClip`; 5261 was record 218's line.
- [MEASURED] `Backends/SDL` on macOS (AccessKit flags), by filter `SDLClipMaskTests|ReplayFixtureTests`: **5 tests (SDLClipMaskTests) and 39 tests (ReplayFixtureTests) passed**. The whole target exits mid-run on this Mac at `aFailedBlurTextureDrawsTheFlatTint` (the same on master) and was not run in one process.
- [MEASURED] Parity on SDL-over-MSL (`Replay --portable`), frames 0-18: **`differing pixels=0, max channel delta=0` on every frame, outside and inside sprites max delta 0**, including the new **frame 18** (`720x380: 0 rects, 0 glyphs, 0 images, 0 transforms, 10 groups, 10 runs`); the draw-order mutation control still detects (283 differing pixels). Stop condition 6 (destination-in not byte-equal) did not fire. Linux Vulkan and Windows D3D12 not run (CI only).
- [MEASURED] `zsh docs/probes/closeout-inventory-check.sh` and `closeout-undocumented.sh` print nothing.
- [MEASURED] Portable (`metalui-portable:latest`, from a `git archive` of the final head): see the line the finishing commit adds below.

## 7. The SDL/D3D12 half (run 2, `CM-G`)

- **Bridge.** `ReplayGroup` gained `mask_run_start`, `mask_run_count` (after `tint`). `make_pipeline` takes `BLEND_NONE`, `BLEND_OVER` or `BLEND_DST_IN` (source factor zero, destination factor source alpha, colour and alpha); `ensure_backdrop_pipelines` builds `g->mask` as a fourth pass pipeline (pass vertex + the `tint` stage, destination-in), so a masked group needs the portable shaders and otherwise degrades **by name** to unmasked (`mask_failures`). `render_groups` runs, after a group's content pass and before its filter, a scratch slot of the group's size (`backdrop_acquire`), the mask runs under the group's projection (CLEAR), one LOAD pass over the target with `g->mask` at tint (1, 1, 1, 1), and `backdrop_release`. Counters `mui_renderer_mask_counters` (`lastMaskPasses`, `lastMaskFailures`) and the hook `mui_renderer_set_mask_hook` (`maskPoolFailsAllocation`). `replay.hlsl`, the compiled blobs and `SOURCE.sha256` are untouched: stop condition 6 did not fire.
- **Flattening.** `SDLGroupSet.Builder.append(_:childQuads:)` is the one routine that places a scene's records and runs (extracted from `visit`); the mask scene goes through it after its group, so a mask's transform indices are shifted like any record's. `sharedTextures(of:)` includes a mask's textures (a path clip's raster). `FlatFrame`/`FixtureGroupTree` do the same on the fixture side (`FixtureGroup.mask: FixtureBody?`, `FlatGroup.maskRunStart/maskRunCount`); the two flattenings are pinned equal by parity frame 18 playing the fixture form against Metal.
- **Fixture version 9**: after a group's body, `u32 hasMask` and (1) a second nested body; versions 2-8 load unmasked. `validate` checks a mask body like a group body with no earlier group (a mask holding a group run is refused).
- **Parity frame 18** (`Experiments/SDLGPU/Sources/Replay/main.swift`, `clipMaskFrame`, 720 x 380): an ellipse clip, a triangle (nonzero) and an even-odd ring path clip, crossing rounded clips through `pushClip` (by `padding`) and across an `.offset` (flattening entry), an ellipse clip under `rotationEffect` and `rotation3DEffect`, one inside an opacity group and one under a blur; 10 group quads. `--expect 19` on both lines of `.github/workflows/sdl-gpu-linux.yml`.
- **Demo.** `looksClipMaskStrip` (a `Component`, `LooksClipMaskStrip`) in three column functions (`looksClipEllipseColumn`, `looksClipPathColumn`, `looksClipCrossingColumn`), built in its own frame by `buildTheClipMaskStrip()` in `everyProductionTreeBuildsOnAOneMegabyteThread`.
- **Ledger.** Divergences 91 and 92 retired, 224 added; live 210 to 209 (counted: 210 rows under `## Live` before, 209 after); 225 is a live row (the popover rect source), so the next label is 226 and 224 was free. `docs/divergences.md`, `docs/record/04-divergences.md`, the shards (`drawing.md`, `sdl.md`, `retained.md`), `decision-prefixes.md` (`CM-`, next `CM-I`), `human-checks.md` group `CM` (CM1..CM4, not run), the inventory map rows 93, 119 and 183 (the `91 92` citations dropped; 119 now cites 224), `api-overview.md`, `migration.md`, two guide sentences in `docs/guides/drawing-and-gpu.md` (`noGuideCitesARetiredDivergence` found the citations of 91; the replacement is a 224 line), the record README, `Tasks.md` (R4-5 still unticked), `CLAUDE.md` and `AGENTS.md` (byte-identical).

## 8. Not done

- [NOT RUN] Linux Vulkan and Windows D3D12 frame 18 (CI only, as frames 16 and 17), the window arms (hit testing in a live window), human checks `CM1`..`CM4`.
- [NOT RUN] The whole `Backends/SDL` target in one process: it exits mid-run on this Mac at `aFailedBlurTextureDrawsTheFlatTint` (the same on master); `SDLClipMaskTests` and `ReplayFixtureTests` were run by filter.
- Carried: a crossing at a flattening entry is one masked group per leaf (M26); the continuous-corner shape (90) could be drawn through a path mask.
