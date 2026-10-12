# 94 — Backdrop blur behind a Material

Branch `feat/backdrop-blur` from `f2fe54a` (master: C13 shadow cache §90, C12 drawn menu bar §89),
merged with master `5f35df6` at the Record phase (§91 test harness, §92 overlays and coordinates,
§93 input follow-ups and §95 `ForEach` identity had landed; **§94 was free on master and is kept**,
the number this branch was told at its start). **Not a plan task**: item C21 of the gpui-gap
priority list, requested by MetalCreator (developer-0a, `docs/metalui-gaps.md` C10-a / M5-c:
floating glass panels over a 3D `MetalView` viewport) on 2026-10-02. It discharges `LK-L` item 4's
deferral (record §85, divergence 166's "C10-c"). Spec
`docs/superpowers/specs/2026-10-10-backdrop-blur-design.md`; rulings `BB-A`…`BB-T` in the new
decisions doc `docs/superpowers/2026-10-10-backdrop-blur-decisions.md` (next unused `BB-U`); probe
`docs/probes/swiftui-backdrop-blur.swift` (groups `P`, `S`, `S2`, `F`, `E`, `E2`, `R`, `N`, `O`,
`T`, `W`). Divergence labels reserved for this branch: 245–254; used 245–249.

**Status: LANDED — every agent-doable clause is built; the looks are owed to a human**
(`docs/verification/human-checks.md` group BB, §8). Three lanes, each red first, each verified
`ok: true` by an independent checker; the run was interrupted once by the weekly limit (after lane 1's
implementation, HEAD `be60f3e`) and continued; the Record phase re-took the suite, the counts, the
inventory check and the fourteen-image comparison (§7). Not built and named: Reduce Transparency,
saturation lift, a path or CPU-leaf material, the `ProgressView` tint hook (§9).

## §0 What it is

`.background(.ultraThinMaterial)` (the five thicknesses and `.bar`, both vocabularies, the legacy
`Box.background`, `Shape.fill`, `ShapeView.fill`) now **blurs what is already drawn beneath it,
`MetalView`/`GPUSurface` pixels included, on both renderers**, then draws the material's tint over it.
Before, a material was a fitted flat tint (divergence 166) and `.blur(radius:)` blurred only a view's
own pixels (divergence 167), so a viewport under a glass panel stayed sharp.

- **One primitive** (`BB-A`, `BB-B`): `PrimitiveKind.backdrop`, `MUIBackdrop`, 96 bytes (bounds,
  content mask, mask radii, corner radii, tint `MUIHsla`, then `order`/`shape`/`sigma`/`opacity`),
  `Scene.backdrops` with its own runs; composited `c · o · (T + (1 − T.a) · B)`. The tint is inside
  the record so `.opacity(0.5)` on a material is a half-weight composite of the blurred, tinted
  layer over the **sharp** backdrop (probe `O`), and the flat fallback is the same record drawn as
  `c · o · T` — today's pixels.
- **Old path untouched** (`BB-C`): a scene with no backdrop is one pass into the drawable, every
  new counter 0, no new texture. A scene with backdrops renders into a per-window **frame target**
  in segments split at each backdrop run and ends with a copy to the drawable (a full-screen copy
  draw on Metal, a 1:1 `SDL_BlitGPUTexture` on SDL). The drawable stays `framebufferOnly`.
- **The blur** (`BB-D`, `BB-R`): sigma **52 pt** (device pixels in the record), `L` 2× bilinear
  downsamples until `sigma_dev / 2^L ≤ 4` (`L ≤ 6`), a separable Gaussian at level `L` (weights
  computed and normalised in the shader), then the quad's bilinear read as the upsample at
  texel coordinate `(p + ½)/2^L − ½`. Region = the transformed bounds' integer box ∩ target,
  edge-clamped (`Scene.backdropRegion`, the one function). `BackdropBlurReference`
  (`MetalUIPath`, imports nothing) restates it in `Float`.
- **Batching** (`BB-E`, `BB-S` 1): `Scene.finalize()` ends a backdrop run where regions intersect
  (a later material must see an earlier one) or another kind interleaves; per run one split, per
  record one blur chain of **`L + 2` passes** (the spec's `2L + 2` over-counted the upsample, which
  is the quad's read) and one quad draw. Counters on both renderers: `lastBackdropSplits`,
  `lastBackdropBlurs`, `lastBackdropPasses`, `lastFrameTargetCopies`, `lastBackdropTexturesMade`.
- **Sites** (`BB-P`): the proposal `.background(material)` is a new `LayoutModifier` case
  `.backgroundMaterial(Material)` (one layer, one identity level, as `.background(Color)`); the
  legacy `Box` keeps the material in `DecorationExtras.Fields.backgroundMaterial`
  (`LK-W` item 10); `Shape`/`ShapeView.fill(material)` is `ShapeView.Layer.materialFill`.
- **Degrades to the flat tint by name** (`BB-H`, divergence 248): a `Path` fill, and a material leaf
  captured inside `.shadow`, `.blur(radius:)` or `.compositingGroup()` (CPU-rasterized leaves cannot
  read a GPU backdrop); on a renderer: an empty region, a failed blur texture, a failed frame
  target, a non-`bgra8Unorm` drawable, a non-identity projection or a rasterization rate map
  (`BB-I`, `BB-S` 5).
- **Fades and previews** (`BB-G`, `BB-Q` 3): `CapturedPrimitive.backdrop` has an arm in both fade
  flattenings (`multiplyAlpha`, `RenderEffect.apply`; a scale also scales `sigma`), in
  `DragSession`, in `bounds`/`screenBounds`/`maskDepth`; a removal ghost and a drag preview blur the
  **live** backdrop at their place.
- **Replay** (`BB-J`, `BB-T`): `shaders.metal` and `replay.hlsl` hold the same arithmetic (eleven
  compiled SDL stages, six old ones byte-identical); `ReplayFixture` is **version 4** (a `backdrops`
  table, stride 96, `FixtureRun.Kind.backdrop = 3`; versions 2 and 3 still load, 1 stays refused);
  three parity fixtures (frames 9–11, `--expect 12` in CI).

## §1 Baseline and design

- **Baseline** at `f2fe54a`: **3237 tests in 3 suites**, 0 goldens, 205 typecheck guards,
  14 demo images, `Backends/SDL` 24 + 108 on macOS.
- **Carried items.** `LK-L` item 4 and divergences 166/167 name "C10-c, a backdrop blur in both
  renderers"; no other decisions doc carries it. Discharged here for 166 (amended: the flat tint
  now remains only in the degrade cases) and left standing for 167 (a GPU surface *inside* `.blur`
  is still drawn unblurred; a surface *under* a material is now blurred).
- **Probe** `swiftui-backdrop-blur.swift` on `ImageRenderer` (`P1`–`P3` positive controls, the blur
  of every material in both schemes `S`/`F`, the edge `E`/`E2`, the shape `R`, nesting `N`, opacity
  `O`, Reduce Transparency `T`, a real window `W`), two byte-identical runs on an unlocked screen,
  re-run in part by the critic round (`P1`, `P3`, `S light regular`, `N1`, `O1`, byte for byte,
  `BB-O`). Findings: sigma 49–55 pt (one constant, 52); the blur is nearly clamped to the shape;
  outside a `Circle`/`RoundedRectangle` fill the backdrop is unblurred; a material over a material
  blurs twice; `.opacity` is a half-weight composite over the sharp backdrop; **`W` (a real window)
  shows no in-window blur at all, only the window-behind backdrop** (divergence 245, `BB-F`);
  `T` (Reduce Transparency) was inconclusive (`BB-I`).
- **Critic round** (`BB-O`): the primitive, pass structure and lanes were attacked and held;
  four pins re-spelled (test 1.7's mutation could not compile as written, 1.12's two tests each
  got their own mutation, 2.3 compared to an unnamed scene, `swift package clean` per lane after
  Step 0's stored properties); a per-material sigma table rejected (the spread is inside the fit's
  error).

## §2 Lane 1 — scene, frame, sites

Step 0 first (the header struct, `PrimitiveKind.backdrop`, `Scene` arrays/insert/finalize/
`backdropRegion`, `BackdropBlurReference`), then `Frame.fillBackdrop` and every material site.
Interim renderer arms drew `.backdrop` as the flat tint until lanes 2 and 3 landed (`BB-Q` 1).

| file | tests |
|---|---|
| `Tests/MetalUITests/BackdropRecordTests.swift` | 8 `@Test`s: 1.1 `aMaterialBackgroundEmitsOneBackdropRecordAndNoTintRect`, 1.2 `theBackdropTintIsTheLKLTableForEverySchemeAndMaterial`, 1.3 `theBackdropShapeIsTheFilledRoundedRectOrEllipse`, 1.4 `aPathFilledWithAMaterialDrawsTheFlatTint`, 1.5 `opacityMultipliesTheRecordOpacityAndLeavesTheTintAlone`, 1.6 `aClipAndAnOffsetMapIntoTheRecord`, 1.7 `aTransitionGhostAndADragPreviewReplayTheRecord`, 1.8 `aMaterialInsideBlurShadowOrCompositingGroupDrawsItsFlatTint` |
| `Tests/MetalUIRenderTests/BackdropSceneTests.swift` | 3: 1.9 `backdropRunsBreakWhereRegionsOverlapAndWhereAnotherKindInterleaves`, 1.10 `aSceneHoldingOnlyABackdropIsNotEmptyAndClearForgetsIt`, 1.11 `backdropRegionIsTheTransformedBoundingBoxClampedToTheTarget` |
| `Tests/MetalUIPathTests/BackdropBlurReferenceTests.swift` | 1.12 `theReferenceBlurMatchesAnErfStepWithinTwoLevels`, `theLevelCountFollowsSigma`, `theKernelIsNormalizedAndTheExponentialMatches`, `aUniformBackdropStaysUniform` |
| `Tests/MetalUITests/BackdropCompileGuards.swift` | 1 typecheck guard, 1.13 `anExhaustiveSwitchOverPrimitiveKindNeedsABackdropArm` (fixtures: the `PrimitiveKind` switch with and without the arm, `Scene.BackdropRegion` spelled by an importer, the `LayoutModifier` `.backgroundMaterial` arm) |
| `Tests/MetalUITests/MaterialTests.swift` | `everyMaterialMatchesSwiftUIOverWhiteAndBlackM5` and `aMaterialFollowsTheColourScheme` **re-pinned** on the backdrop record (`BB-M`): one record, no tint rect, and `flatTintRect` equal to the table within one level |
| `SceneFinalizeIdentityTests`, `DecorationPaintTests`, `DragPreviewTests`, `RasterAnchorTests` | switch arms for the new kind; the `[Int]` side-table count 8 → 10 (two per kind, five kinds) |

Sites: `ShapeView` (`materialFill`), `Box`/`AnimatedColor.paintDecorationBody`,
`NativeModifiedContent`/`ModifiedContent` (`.backgroundMaterial`), `Shape.swift`; the demo section
`backdropBlurSection()` in `LooksDemo` in its own function (Windows' 1 MB stack).

## §3 Lane 2 — Metal renderer

`Sources/MetalUIRender/Renderer.swift`, `BackdropBlurPipeline.swift`, `shaders.metal`,
`MetalUIShaderTypes.h` (`BB-S`). A per-window `BackdropFrameState` (frame target replaced on a size
change; a free list of blur textures by size, sizes a frame did not acquire dropped at its end, a
frame with no backdrop drops the target and the pool); `backdrop_vertex`/`backdrop_fragment`/
`backdrop_flat_fragment`, the downsample and Gaussian fragments, the copy draw; coverage is the
rect shader's of a white borderless rect (an edge is a rect's by construction). Test hooks
`backdropPoolFailsAllocation`, `routesEveryFrameThroughTheFrameTarget`, `hasBackdropFrameTarget`.

`Tests/MetalUIRenderTests/BackdropRenderTests.swift`, 12 tests: 2.1 `aBackdropOverAStepEqualsTheReferenceWithinTolerance`
(σ = 16, 52 pt at scales 1 and 2), 2.2 `theBackdropBlursAGPUSurfaceBeneathIt`, 2.3
`aSceneWithoutBackdropsTakesTheOldPathByteForByte`, 2.4 `splitsCountRunsAndBlursCountRecords`, 2.5
`pixelsOutsideTheShapeAreUntouched`, 2.6 `opacityHalfIsAHalfWeightCompositeOverTheSharpBackdrop`, 2.7
`aFailedBlurTextureDrawsTheFlatTint`, 2.8 `nestedBackdropsBlurTwice`, 2.9 `theClipCutsTheBackdropQuad`,
2.10 `aSteadyFrameMakesNoTexturesAndAResizeMakesTheFrameTargetOnce`, 2.11 `theDrawableStaysFramebufferOnly`
(a source-text check), 2.12 `aClippedTransformedBackdropStaysInsideItsClip`.

## §4 Lane 3 — SDL, replay, Linux

`Backends/SDL`: `SDLBridge.c`/`.h` (`encode_frame` with segments, the pyramid, the blit, the pool,
`mui_backdrop_levels`), `SDLWindowRenderer`, `replay.hlsl` identical to the MSL, the eleven compiled
stages (`compile-shaders.py`, `SOURCE.sha256`), `ReplayFixture` v4, `SDLReplayer`, `PortableReplay`,
`Experiments/SDLGPU`'s replay, and `.github/workflows/sdl-gpu-linux.yml` (now also triggers on
`Sources/MetalUIShaderTypes/**` and `Sources/MetalUIPath/**`, `--expect 12`). `MetalUISDL` gains a
dependency on `MetalUIShaderTypes` in the root manifest (`BB-Q` 1). The flat tint is not an HLSL
stage: `pack_records` appends a rect per backdrop record with `tint.a × opacity` (`BB-T` 4).

`SDLBackdropTests.swift` (10 tests, 3.1 ABI, 3.3 a–i, 3.5) and `ReplayFixtureTests.swift` (+30 `@Test`s
in the file: the ABI, the harness 3.2/3.2b, 3.4 a–c, 3.6). Three tests were added **because a mutation
survived** (§6): 3.3e over a 2D field (shape and clip), 3.3h a 2D field over an odd region
(downsample rows), 3.3i a turned backdrop (the transform index). 3.5 needs no `.enabled(if:)`
(it composites into the offscreen renderer; the Linux image's offscreen driver changes nothing);
every helper arms `armMainRunLoopExitCheck()`. Replay parity on frames 9–11: Metal-backend SDL 0,
Mesa lavapipe (Vulkan) 2 levels, tolerance `insideBackdrops = 3`.

## §5 Counts

- **At the merge** (master `5f35df6`): **3443 tests in 3 suites**, 0 goldens, **217 typecheck guards**
  (master's 3415 + 28 tests, 216 + 1 guard): lane 1's 16 (`BackdropRecordTests` 8, `BackdropSceneTests` 3,
  `BackdropBlurReferenceTests` 4, `BackdropCompileGuards` 1) and lane 2's 12 (`BackdropRenderTests`); the
  `MaterialTests` re-pins add none. Lane 3's tests are in `Backends/SDL` and outside the root count:
  **`Backends/SDL` 30 + 121 on macOS** (the checker's reading; baseline 24 + 108). Public census **3414**
  (3405 + 9: `Scene.backdrops`, `Scene.insert(_:layer:)` for a record, `Scene.BackdropRegion` with its
  four fields and initialiser, `Scene.backdropRegion`).
- Before the merge, the checkers read **3253 tests** (lane 1, native after `swift package clean`) and
  **3265** (lane 3's root run, including lane 2's 12), each with exactly the five known locked-screen
  `AppKitPresentationTests` sheet issues.
- **Divergences:** 245–249 added (248 by lane 1, the rest at the Record phase), 166 amended; 137 → 142
  live (master's 137 after 79 retired and 255 added). Next label stays 206 in the header (the merge
  of the open ranges settles it); 250–254 unused by C21.

## §6 Mutation tables

Every mutation: commit first, restore from a copy, unfiltered suite (lane 2's checker ran its
mutations filtered to `BackdropRenderTests`, noted per row), `git status --short` clean after
each. "Survived" rows name the test added.

**Lane 1** (checker; the implementer's own table agrees, all expected):

| # | mutation | reddened |
|---|---|---|
| 1.1a | `ModifiedContent` `.backgroundMaterial` site back to `pass.fill(flat colour)` | `aMaterialBackgroundEmitsOneBackdropRecordAndNoTintRect`, `aClipAndAnOffsetMapIntoTheRecord`, `aMaterialFollowsTheColourScheme`, `aMaterialInsideBlurShadowOrCompositingGroupDrawsItsFlatTint`, `opacityMultipliesTheRecordOpacityAndLeavesTheTintAlone` |
| 1.1b | legacy `Box` (`paintDecorationBody`) `fillBackdrop` → `fill` | the record test, the scheme test, `aTransitionGhostAndADragPreviewReplayTheRecord`, the opacity test |
| 1.1c | `Shape`/`ShapeView` `paintShapeMaterial` `fillBackdrop` → `fill` | the record test, the scheme test, `everyMaterialMatchesSwiftUIOverWhiteAndBlackM5`, `theBackdropShapeIsTheFilledRoundedRectOrEllipse` |
| 1.2 | swap thin-light with regular-light in `Material.fill` | `theBackdropTintIsTheLKLTableForEverySchemeAndMaterial`, `everyMaterialMatchesSwiftUIOverWhiteAndBlackM5` |
| 1.3 | every shape encoded as a rounded rectangle | `theBackdropShapeIsTheFilledRoundedRectOrEllipse` |
| 1.4 | a backdrop emitted for a path fill | `aPathFilledWithAMaterialDrawsTheFlatTint` |
| 1.5 | record opacity fixed at 1 | `opacityMultipliesTheRecordOpacityAndLeavesTheTintAlone` |
| 1.6 | `contentMask` = bounds instead of the active clip | `aClipAndAnOffsetMapIntoTheRecord` |
| 1.7a/b/c | `multiplyAlpha` arm returns the record unchanged; `RenderEffect.apply` drops `sigma *= sx`; `DragSession` drops the `contentMask` assignment | `aTransitionGhostAndADragPreviewReplayTheRecord` each |
| 1.8 | `insertThroughScopes` degrade disabled | `aMaterialInsideBlurShadowOrCompositingGroupDrawsItsFlatTint` |
| 1.9 | run break on touching (`<=`) | `backdropRunsBreakWhereRegionsOverlapAndWhereAnotherKindInterleaves` |
| 1.10 | `isEmpty` drops backdrops | `aSceneHoldingOnlyABackdropIsNotEmptyAndClearForgetsIt` |
| 1.11 | `backdropRegion` skips the clamp | `backdropRegionIsTheTransformedBoundingBoxClampedToTheTarget` |
| 1.12a/b | level threshold `> 4` → `> 8`; Gaussian weights unnormalised | `theLevelCountFollowsSigma`; `theReferenceBlurMatchesAnErfStepWithinTwoLevels`, `theKernelIsNormalizedAndTheExponentialMatches`, `aUniformBackdropStaysUniform` |
| 1.13 | the `.backdrop` arm deleted from the guard fixture | `anExhaustiveSwitchOverPrimitiveKindNeedsABackdropArm` |
| 1.14 | `MUIBackdrop.flatTintRect` drops `color.a *= opacity` | **survived** — see §9 gap 1 |

**Lane 2** (checker, `BackdropRenderTests` only):

| # | mutation | reddened |
|---|---|---|
| M1a | halve the Gaussian sigma | 2.1 (all cases), 2.8, 2.6 |
| M1b | the vertical Gaussian pass runs horizontal | 2.1, 2.8, 2.6 |
| M3 | always route through the frame target | 2.3, 2.4 |
| M4 | count splits per record | 2.4 |
| M5a / M5b | corner radii zeroed in `backdrop_coverage` (test uses an ellipse: wrong lever, **survived**); `r.shape = 0` | none; 2.5 |
| M6 | tint alpha multiplied into the composite | 2.1, 2.8, 2.6, 2.2 |
| M9 | content-mask clip ignored in coverage | 2.9 |
| M10 | bypass the texture pool's free list | 2.10 |
| M12a / M12d | `transformIndex = 0` in `backdrop_coverage` (fragment, **survived**); in `backdrop_vertex` | none; 2.12 |
| M2, M7, M8, M11 | taken by the implementer with full-suite runs (not re-taken by the checker) | recorded in the implementer's report; no independent re-take |

**Lane 3**: the table in `BB-T` (M1–M24, 24 rows, `Backends/SDL` suite unfiltered). The checker
re-took two: `level_sigma = sigma` (ignoring the `2^levels` division) reddened `aBackdropOverA2DFieldEqualsTheReferenceOfItsRegion`,
`opacityHalfIsAHalfWeightCompositeOverTheSharpBackdrop`, `pixelsOutsideTheShapeAndTheClipAreUntouched`,
`sdlBackdropBlursAGPUSurfaceUnderIt`, `sdlOffscreenBackdropEqualsTheReferenceAndCountsMatchMetal`; the first Gaussian pass flipped to vertical
reddened the `Backends/SDL` suite (9 issues).

**The same bug class three times.** A step scene with a vertical edge is blind to anything vertical
or far from the edge: M2 (downsample rows), M9 (shape), M10 (clip) and M24 (transform index) survived
the lane 3 suite until a 2D field and a turned backdrop were added, and 2.12's fragment-side half
survived lane 2's. Test the shader with a field that varies on both axes (§9 gap 2).

## §7 Gates

- `swift package clean`, `swift build --build-system native --build-tests`, unfiltered
  `swift test --build-system native --no-parallel`: after the merge,
  **3443 tests in 3 suites, 5 issues** — exactly the five `AppKitPresentationTests` sheet tests
  (`appKitOpenDialogIsASheetWithTheDeclaredTypes`, `appKitSaveDialogCarriesTheNameTypesAndExportPrompt`,
  `appKitCancelledDialogArrivesAsQueuedInput`, `appKitDismissPresentationEndsTheSheetAndAnswersNothing`,
  `appKitSecondDialogWhileASheetIsUpAnswersFalse`) that a locked screen fails (`CI-AF`; the lock probe read
  `CGSSessionScreenIsLocked = 1`); `FR-J no-argument frame: succeeded=true`; 0 `error:`; the only `warning:`
  is SwiftPM's `--build-system native` deprecation notice. The default build system's
  `swift build --build-tests` is {DEFAULTWARN}.
- **Fourteen demo images 0 px against `f2fe54a`** (`docs/probes/demo-pixels/compare.sh <scratch>
  f2fe54a HEAD`, scene identical): {DEMO}. The only `Material` in a demo is `LooksDemo`'s section,
  outside `demoContent()` and the chrome pair (`BB-M`); `DemoFrameDeterminismTests` `Expected.swift`
  unedited.
- Inventory: `closeout-inventory-check.sh` and `closeout-undocumented.sh` print nothing; census
  re-recorded: 3414 declarations, `docs/probes/closeout-public-api.tsv` regenerated.
- `Backends/SDL` on macOS builds and passes (the checker: 30 + 121); the Linux image and the
  replay-parity harness were run by the implementer, not re-run by the checker or the Record phase;
  **Windows D3D12 is unmeasured** (`ssh metalui-win` timed out): the five DXIL stages are compiled and
  reflected, CI's `--expect 12` on frames 9–11 is the measurement.

## §8 Looks owed

`docs/verification/human-checks.md` group **BB**, none performed (an agent cannot): BB1 a panel over
the MetalView demo (six materials, light and dark; SwiftUI in a real window blurs *behind* the
window, divergence 245, and the tint table is owed a window capture); BB2 dragging a panel over
moving content (no tearing, no one-frame lag); BB3 nested panels; BB4 a window resize with a panel up
(no stale blur); BB5 Windows (D3D12) and Linux sight; BB6 a fading panel cross-fades with the live
backdrop. The screen lock was not probed for a real-window capture in the Record phase.

## §9 Hazards, deferrals and gaps

Deferrals with owners:

- **Reduce Transparency** is not honoured (divergence 249, `BB-I`): probe `T` was inconclusive, and
  it needs two defaultless `PlatformWindow` requirements and honest AppKit/SDL/fake answers. Owner:
  a platform-services follow-up (none scheduled). The flat fallback it would select exists.
- **Saturation lift** (divergence 246, `BB-D`), **bleed from outside the shape** (247), **path and
  CPU-leaf materials** (248): by name.
- **The `ProgressView` tint hook** (`BB-N`): not built, not probed; owner none.
- **A regions atlas / independent-material reordering** (`BB-E`): a glass list pays `records ×
  (L + 2)` small passes and a split each; owner whoever measures it.
- **Rendering the last segment straight into the drawable** to save the frame-target copy (`BB-C`
  cost-if-wrong): owner none.
- **A frame-count grace period for the pool** (`BB-S` 4): a panel that flickers every other frame
  re-allocates; owner none.

Open gaps the checkers reported (minor, unfixed in the Record phase, which changes no source):

1. `MUIBackdrop.flatTintRect`'s `color.a *= opacity` is unpinned (mutation 1.14 reddens nothing):
   `aMaterialInsideBlurShadowOrCompositingGroupDrawsItsFlatTint` checks the degraded rect at
   opacity 1 only. Required: a case under `.opacity(0.5)` expecting `tint.a * 0.5`.
2. Test 2.12 does not pin the fragment-side transform handling in `backdrop_coverage` (`pixelScale`
   and the transform's `outerMask`): its outer mask is the whole frame and `pixelScale` is 1.
   Required: an outer mask smaller than the frame and a scale other than 1.
3. A failed lazy pipeline load on SDL (`ensure_backdrop_pipelines`, first material frame) draws flat
   tints silently; no test sees it (`BB-T` cost-if-wrong).

Hazards for the next reader:

- **A new stored property on a public type** (`Scene`, step 0) needed `swift package clean` in each
  lane; so will the next one.
- **`MetalUISDL` now depends on `MetalUIShaderTypes`** in the root manifest; `Backends/SDL`'s own
  manifest follows. A change to those targets is run in `Backends/SDL` and in the Linux image.
- **A `.backdrop` run in `FixtureRun(scene:)`** records; a `.surface` still traps (`MV-C`). A
  fixture older than version 4 loads without backdrops.
- **A material under a changing clip** blurs its whole bounds (`BB-D` 5), by design.
- **The pool is dropped by a frame with no backdrop** (`BB-S` 4): do not read `lastBackdropTexturesMade`
  across a backdrop-free frame.
- **Merge note.** Master added divergences 225, 235, 236, 255 beside this branch's 248; the header's
  count and next label are the merge's. The inventory-map `materials` row is this branch's
  (it cites 166, 248 and `BB-A BB-H BB-P`); `docs/migration.md` gains two rows
  (`PrimitiveKind` `.backdrop`, `LayoutModifier` `.backgroundMaterial`) and a note that a renderer
  outside the package must draw `.backdrop` or fall back to `flatTintRect`, and that `ReplayFixture`
  v4 and `SDLBridge`'s new parameters are package-internal.
