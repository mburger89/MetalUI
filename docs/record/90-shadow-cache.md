# 90 — Shadow cache: translation-free raster keys, `compositingGroup()`, a faster blur (item C13, PERF-a)

Branch `perf/shadow-cache` from `2155f1e`, merged with master `70e9389`
(`feat/app-shell`, §87; the one conflict, `docs/divergences.md`, kept 175 and 176
then 205; the header's count and next label are the merge to master's). **Not a plan task**: item C13 of
the gpui-gap priority list (user request 2026-10-02), reported by MetalCreator
(`docs/metalui-gaps.md`, "Node-drag performance, 2026-10-08", PERF-a, measured
on MetalUI `dc6528c`). Spec `docs/superpowers/specs/2026-10-09-shadow-cache-design.md`;
rulings `PF-A`…`PF-N` in `docs/superpowers/2026-10-09-shadow-cache-decisions.md`
(next unused `PF-O`; no ruling was appended in lane 2 or the Record phase); probes `docs/probes/swiftui-shadow-cache.swift`,
`docs/probes/shadow-cache/run.sh`. Divergence labels reserved for the branch:
205–214. Parallel branches at the time: `feat/app-shell` (§87),
`feat/key-focus` (§88), `fix/smk-port-gaps` (§89).

**Status: both lanes landed, each verified `ok` (2026-10-10).** §1 lane 1
(canonical keys), §2 lane 2 (`compositingGroup()`, the faster `BoxBlur`), §3 the
Record phase (suite, counts, pixels, Linux, docs), §4 hazards and deferrals.

## 1. Lane 1 — canonical keys (`PF-A`, `PF-B`, `PF-I`, `PF-J`, `PF-M`, `PF-N`)

Commits: `e8d70c2` (red: counter, `PathGeometry.translated`, the pins),
`06393c6` (the keys, `RasterAnchor.swift`, the probes), `9700aef` (`PF-M`,
`PF-N`), `31c88a4` (unchecked `tint` and `RasterMath` loops).

### 1.1 What was built

- `Sources/MetalUI/RasterAnchor.swift`: `RasterAnchor` (mode, `R`, `S`,
  `full'`), the conservative extent (`RasterExtent`, `ExtentBox`), and the
  canonical moves (`CapturedPrimitive.movedCanonically`, the paints'
  re-anchoring, `Affine2D.reanchored`).
- `shadowImage`, `blurImage`, `pathImage` and the full gradient raster make
  and key their raster in canonical coordinates and place it at `+S`; mode 1
  (extent inside the clip) keys no clip, mode 2 keys `clip − S`, mode 3 (a local
  mask) is 2155f1e's absolute key and raster. The gradient strip is unchanged
  (§9 D4).
- `keyLeaf` keys a mask only when it decides a byte (`PF-I`).
- `RasterCache.lastTexturesMade` (`PF-G`), the `onRaster` test probe.
- `RasterCache.tint`, `RasterMath.multiply/scale/crop` over unchecked buffers.

### 1.2 Red at `e8d70c2` (counter added, keys unchanged)

Filtered run of the three new files: L1.1, L1.2, L1.3, L1.7, L1.8, L1.9 red,
every whole-pixel frame missing. First failing frame of each:

| test | 1× | 2× |
|---|---|---|
| L1.1 `aShadowedContainerDraggedByWholePixelsHitsTheCache` | frame 2: blurred 64300, rasterized 2740, made 9 | blurred 255920, rasterized 10960, made 9 (layout and `.offset`) |
| L1.2 `aShadowedContainerPannedByWholePixelsHitsTheCache` | blurred 64300, rasterized 2740, made 9 | blurred 255920, rasterized 10960, made 9 |
| L1.3 `aBlurredContainerDraggedByWholePixelsHitsTheCache` | blurred 19804, rasterized 2740, made 9 | blurred 78512, rasterized 10960, made 9 |
| L1.7 `aPathDraggedByWholePixelsHitsTheCache` | rasterized 2896, made 2 | rasterized 11441, made 2 |
| L1.8 `aGradientRasterDraggedByWholePixelsHitsTheCache` | rasterized 1600, made 1 | rasterized 6400, made 1 |
| L1.9 `aShadowInsideAClippedPanelHitsWhenDragged` | blurred 64300, rasterized 2740, made 9 | — |

Green there, as designed: L1.4, L1.5 (trivially: nothing canonical yet),
L1.6 (2155f1e's cut behaviour), L1.10, L1.11, L1.12, L1.13.

### 1.3 Suite

`swift test --build-system native --no-parallel`, unfiltered, at `06393c6`:
**3037 tests in 3 suites** (3021 + 16: `RasterAnchorTests` 13,
`RasterMathReferenceTests` 2, `PathGeometryTranslationTests` 1), `FR-J
no-argument frame: succeeded=true`, 0 `error:`. Five failures, all
`AppKitPresentationTests` sheet tests (`appKitOpenDialogIsASheetWithTheDeclaredTypes`,
`appKitSaveDialogCarriesTheNameTypesAndExportPrompt`,
`appKitCancelledDialogArrivesAsQueuedInput`,
`appKitDismissPresentationEndsTheSheetAndAnswersNothing`,
`appKitSecondDialogWhileASheetIsUpAnswersFalse`: `turn { nsWindow.attachedSheet
!= nil }` after 61 s) — **environmental**: the lock probe read
`CGSSessionScreenIsLocked = 1`, `displayAsleep main: 1`, and the same five
passed in the M1e, M1f and M1g runs on the same tree (code that does not touch
AppKit). Final-commit suite: §1.7.

### 1.4 Mutations (each on a committed tree, restored from a copy, full unfiltered suite, `git status --short` clean after)

Applied to `06393c6`'s spelling unless noted. The five environmental AppKit
sheet failures above are left out of the lists.

| | mutation | reddened |
|---|---|---|
| M1a | `RasterAnchor.keyed` also keys `S` (an absolute translation in the key) | L1.1, L1.2, L1.3, L1.7, L1.8, L1.9 |
| M1b | `keyed` keys `full'` with translation 0 (`f` dropped) | L1.4 `aRasterIsTheSameWarmOrCold`, L1.10 `aSubPixelMoveMissesAndDrawsTheExactPosition` |
| M1c | `keyLeaf` keys every mask | L1.9, L1.1, L1.3 (the window's clip is every leaf's mask too; the pan L1.2 stays green — a pan moves no leaf) |
| M1d | always mode 1 (`.uncut`) | L1.6 `aShadowCutByItsClipIsRasterizedOnEveryMove`, 3.14 `theCacheKeyIncludesColourTransformAndClip`. **3.20 stays green**: it reads one frame, and mode 1 still rasterizes with today's clip (`PF-J` item 2) — the spec's "M1d reddens 3.20" was wrong |
| M1e | the shadow's extent without `BoxBlur.padding` | L1.6 (its second fixture, where only the padding crosses the clip) |
| M1f | the shadow's image not shifted by `S` | L1.1b `aCachedShadowIsPlacedAtTheNewPosition`, L1.5, L1.5b, L1.6, `aDeferredStopsAnEnclosingShadow`, `aFadingTransitionScalesAPathsAndAShadowsAlpha`, `aLegacyShadowReturnsSelfAndShadowsTheWholeElement`, `aLegacyShadowsColourRadiusAndOffsetAnimate`, `aMetalViewsShadowIsItsQuad`, `aSecondShadowShadowsTheFirst`, `aShadowFollowsItsContentsAlpha`, `aShadowInsideARotationOrScaleHasItsOffsetTransformed`, `aShadowIsCutByAnOuterClipAndShapedByAnInnerOne`, `aShadowIsDrawnBelowEachLeaf`, `aShadowSeesAGradientLeafsAlpha`, `shadowColourRadiusAndOffsetAnimate`, `theDefaultShadowColourIsTheShadowToken`, `theShadowBlurMatchesSwiftUIsProfile` |
| M1g | `texture(for:)` does not count its miss; and (verifier) `RasterCache.image(for:)` does not count a made entry | L1.13 `texturesMadeCountsTintAndImageMisses` (both halves) |
| M1h | `tint`'s alpha rounds `+ 128` (on `31c88a4`'s unchecked loop; lane 1 verifier) | `tintMatchesItsReferenceCopy` |
| X1 | `blurImage`'s extent without `BoxBlur.padding` (verifier extra) | **nothing** at `31c88a4` — issue 1; L1.6b `aBlurOrNestedShadowCutOnlyByItsPaddingIsRasterizedOnEveryMove` added in `ab65ef3`; reddens it, §2.5 |
| X5 | `RasterExtent.of`'s nested arms grown by 1 (verifier extra) | **nothing** at `31c88a4` — issue 2; the same L1.6b, reddens it, §2.5 |
| X2 | `RasterMath.crop`'s unchecked row offset drops the column term (verifier extra) | `maskArithmeticMatchesItsReferenceCopies` |
| X3 | `PathGeometry.translated` leaves a quad control point unmoved (verifier extra) | `aTranslatedPathMovesEveryPointExactly` |

### 1.5 Pixels (`PF-C`, `PF-N` item 1)

- `docs/probes/demo-pixels/compare.sh <scratch> 2155f1e 06393c6`: controls as
  recorded (light vs dark 1048576, default vs modal 1031003, default vs
  animation 454895, f0 vs f3 0, preview light vs dark 1048576, chrome 0,
  distinct 544 / 216, prod default vs modal 491221, distinct prod 529,
  indicator rects 0); **all fourteen images `differing=0`, scene identical**.
- `docs/probes/shadow-cache/run.sh pixels <scratch> 2155f1e 06393c6`: controls
  looks light vs dark 17610, drag 1× f0 vs f1 5101, drag 2× f2 vs f3 8016,
  distinct looks-light 1853, distinct drag-2x-f4 539; **all thirteen images
  `differing=0`** (looks light, dark, 2×; drag 1× and 2× f0–f4, frames 1 and 4
  being cache hits after this lane).
- `DemoFrameDeterminismTests`' `Expected.swift` unedited.

### 1.6 Canonical against 2155f1e (L1.5, `PF-N`)

Measured on the device, 21 rasters per configuration:

| position (inner, outer offset, pt) | 1× | 2× |
|---|---|---|
| integer | 0 bytes (1 raster a zero column wider) | 0 bytes (2 wider) |
| dyadic (0.25, 0.5), (0.5, 0.25) | 0 bytes | 53 bytes, max Δ 1 (bordered rounded box's two shadows, both strokes) |
| non-dyadic (0.3, 0.7), (0.1, 0.45) | 0 bytes | 0 bytes |
| L1.5b coincidence (0.7, 0.3), (0.3, 0.7) | — | 609 bytes, max Δ 4, one `shadow(image)` (the bleed column) |

### 1.7 Measurement (report only, `PF-F` item 3)

`run.sh measure <scratch> 2155f1e 06393c6`, release with testing enabled, a
20-node shadowed graph at 2× (1440 × 900 points), one node moving 2 pt per
frame, median of 60 frames after one warm-up. Other workflows were building
on the same Mac, so the times are indicative only; the counters are exact.

| column | median ms/frame | mean | blurred px/frame | rasterized px/frame | textures made/frame |
|---|---|---|---|---|---|
| 2155f1e | 10.78 | 10.78 | 330264 | 23184 | 9 |
| after lane 1 (`06393c6`) | 2.59 | 2.64 | 0 | 0 | 0 |
| after lane 2 (`f0da9a8`, lane 2 verifier) | 2.66 | 2.67 | 0 | 0 | 0 |
| after lane 2, `.compositingGroup()` on each node (`f0da9a8`) | 2.46 | 2.49 | 0 | 0 | 0 |

Lane 2's Linux readings (CI's image, `SDL_VIDEO_DRIVER=offscreen`):
`Backends/SDL` 24 + 96; the `swift:6.4-noble` root 6 + 35 + 21 + 199 + 67 + 22,
0 warnings. Lane 2's verifier found the captures' clip depths
(`PaintScope.captureDepths`) unpinned (mutation **Xa**, `insertThroughScopes(leaf:
scope.captures)`, reddened nothing but the five environmental
`AppKitPresentationTests`); L2.12 `aClipInsideACompositingGroupCutsItsShadow`
pins it.

### 1.8 Deferrals and limits (lane 1)

- Spec §9 D1–D5 stand as written (sub-pixel moves miss; a cut raster misses;
  the local-mask case keeps its absolute key; the gradient strip keeps its
  absolute key; a non-translation effect may miss).
- `PF-N` item 3: a resampled leaf's bleed column can differ from 2155f1e at an
  integer coincidence; a `Double` resample rectangle would remove it at a pixel
  cost against 2155f1e. Owner: none.
- The Linux image run is lane 2's / the Record phase's (`PF-H`: once at the
  end; lane 1 touches no `Backends/SDL` file).

## 2. Lane 2 — `compositingGroup()` and the faster `BoxBlur` (`PF-E`, `PF-F`)

Commits: `9b34739` (red: `compositingGroup()` spelled with a stub scope, L2.1–L2.11
and the plain-import guard), `ab65ef3` (the composite scope, `BoxBlur`, `AlphaCompositor.union`,
the LooksDemo pair, L1.6b), `b325e10` (divergence 205 and the docs), `515ab2a` (the measure's
composited arm), `c803590` (the guard names its mutation), `f0da9a8` (spec §8 corrected: M1d),
`ef3b11c` (L2.12, the verifier's Xa).

### 2.1 What was built

- `LayoutModifier.compositingGroup` (a new public case; one layer, one identity level,
  `MC-C`), `ProposalElementGroup.compositingGroup()` and `StyledElement.compositingGroup() ->
  Self` (`RenderEffectSpec.compositingGroup`, in written order among
  `Decoration.renderEffects`, around the whole element — divergence 108's rule), wired through
  every exhaustive switch (`ModifiedContent`, `NativeModifiedContent`, `ProposalAnimation`,
  `RenderEffects`). `Sources/MetalUI/CompositingGroup.swift`.
- `Frame.paintWithCompositingGroup` and `PaintScope.Kind.composite`: pushed **only when a
  shadow or blur scope is open outside it above the last barrier** (CG4); it collects every
  leaf that reaches it with that primitive's emission clip depth (`captureDepths`), and at
  close hands the collection to the outer scopes as **one leaf** through
  `insertThroughScopes(leaf:depths:)`; a `Deferred` barrier inside stops collection
  (`.composite where pastBarrier`). No new raster code, no renderer or shader change.
  `Frame.compositeScopesPushed` counts pushes (test probe). The `Frame.swift` diff is the scope
  kind and that one function (`TransitionStore` gains the `Kind` arm).
- `BoxBlur.blur`: `Int32` buffers behind unchecked pointers, horizontal passes per row, vertical
  passes row-major with per-column running sums, the same `(sum + half) / width` rounding;
  `AlphaCompositor.union` over unchecked rows. `MetalUIPath` still imports nothing.
- `LooksDemo`: a per-leaf versus `compositingGroup()` pair in its own function (human check PF2).
- Docs in `b325e10`: divergence 205 (an opacity outside `compositingGroup()` is not
  composited: `CG1`, SwiftUI (255,128,128), MetalUI (191,64,128)), `GX-A`'s deferred row drops
  `compositingGroup()`, migration (an exhaustive `switch` over `LayoutModifier` gains an arm),
  api-overview, human checks PF, the inventory family `compositing-group` and the census.

### 2.2 Tests and guards, per file

| file | tests |
|---|---|
| `Tests/MetalUIPathTests/BoxBlurTests.swift` + `BoxBlurReference.swift` | L2.1 `theFastBoxBlurEqualsTheReferenceByteForByte`, L2.2 `theFastUnionEqualsTheReferenceByteForByte` (against 2155f1e's loops copied verbatim; masks 1×1, 1×N, N×1, odd, even, seeded noise) |
| `Tests/MetalUITests/CompositingGroupTests.swift` (10) | L2.3 `aCompositingGroupCastsOneShadowOfTheUnion`, L2.5 `aCompositingGroupAloneChangesNothingAndPushesNoScope`, L2.6 `theCompositingGroupLayerIsOneIdentityLevel`, L2.6b `addingACompositingGroupResetsStateAndStateUnderItIsRetained`, L2.7 `aCompositingGroupIsBlurredAsOneLeaf`, L2.8 `aDeferredInsideACompositingGroupIsNotShadowed`, L2.9 `aCompositingGroupDoesNotCompositeAnOpacity` (pins 205), L2.10 `theLegacyCompositingGroupJoinsRenderEffectsInWrittenOrder`, L2.11 `aCompositedNodeBlursOneMask`, L2.12 `aClipInsideACompositingGroupCutsItsShadow` |
| `Tests/MetalUITests/CompositingGroupCompileGuards.swift` | one typecheck guard, `compositingGroupIsSpellableOnBothVocabularies` (plain import, `typecheckFile`; positive arm `succeeded=true`, control `drawingGroup()` `succeeded=false`) |
| `Tests/MetalUITests/RasterAnchorTests.swift` | L1.6b `aBlurOrNestedShadowCutOnlyByItsPaddingIsRasterizedOnEveryMove` (lane 1 verifier's issues 1 and 2) |

L2.11's separating arm counts distinct textures (equal leaves share one canonical raster,
`PF-A`). No test sleeps; L2.5, L2.11 and L2.12 count work.

### 2.3 Red at `9b34739` (stub scope, `BoxBlur` unchanged)

L2.3 (`CompositingGroupTests.swift:56`, `images.count == 1`), L2.5 (`:81`,
`compositeScopesPushed == 1`), L2.7 (`:196`), L2.8 (`:223`), L2.10 (`:266`), L2.11 (`:309`,
`images.count == 1`, got 9) red; L2.1/L2.2 compare the unchanged loops with their copies and
pass by construction (they pin the new loops once `ab65ef3` lands); L2.6, L2.6b, L2.9 and the
guard (positive `succeeded=true`, control `succeeded=false`) are pins, green at red.

### 2.4 Suites

At `ab65ef3`: **3050 tests in 3 suites**, the only issues the five environmental
`AppKitPresentationTests` sheet expectations (screen locked, `CI-AF`), `FR-J no-argument
frame: succeeded=true`. At `ef3b11c` (lane 2 verifier, `swift package clean`, unlocked screen):
**3051 tests in 3 suites passed after 329.961 seconds** (3037 + L1.6b + L2.1/L2.2 + the ten
`CompositingGroupTests` + the guard), `FR-J no-argument frame: succeeded=true`, 0 `error:`, the
only `warning:` SwiftPM's deprecation notice; the five sheet tests passed. Lane 2 Linux
readings: `Backends/SDL` 24 + 96 in the image; `swift:6.4-noble` root 6 + 35 + 21 + 199 + 67 +
22, 0 warnings (§3.3 takes them again after the merge).

### 2.5 Mutations

Applied on lane 2's committed tree, restored from a copy, `git status --short` after each.

| | mutation | reddened |
|---|---|---|
| Xa | (lane 2 verifier, full unfiltered suite at `ef3b11c`) `insertThroughScopes(leaf: scope.captures, depths: scope.captureDepths)` → `insertThroughScopes(leaf: scope.captures)` | `aClipInsideACompositingGroupCutsItsShadow` (3 issues: the shadow's width 30, diff 0, outside 0). Before L2.12 (`ab65ef3`) this mutation reddened nothing but the five environmental sheet tests |
| guard | (lane 2, once) the legacy `StyledElement.compositingGroup()` declared `internal` | `compositingGroupIsSpellableOnBothVocabularies` (positive arm `succeeded=false`); the proposal spelling cannot be narrowed alone: `MetalUIDemoContent`'s LooksDemo spells it and the package stops building |
| M2a | `BoxBlur`'s two `(sum + half) / width` → `sum / width` (horizontal and vertical) | `theFastBoxBlurEqualsTheReferenceByteForByte` (L2.1); `theBoxBlurApproximatesAGaussianOfSigmaRadius` stays green |
| M2b | the vertical pass drops one row late (`leaving = i - r - 1`) | `theFastBoxBlurEqualsTheReferenceByteForByte` |
| M2c | the composite arm of `insertThroughScopes` `continue`s (leaves forward per primitive) | `aCompositingGroupCastsOneShadowOfTheUnion`, `aCompositingGroupIsBlurredAsOneLeaf`, `aCompositedNodeBlursOneMask` |
| M2d | `paintWithCompositingGroup` always pushes (`compositeHasAReader \|\| true`) | `aCompositingGroupAloneChangesNothingAndPushesNoScope` |
| M2e | the composite ignores a `Deferred` barrier (`.composite where pastBarrier` removed) | `aDeferredInsideACompositingGroupIsNotShadowed` |
| X1 | `blurImage`'s extent pad `= 1` (lane 1 verifier's, with L1.6b now present) | `aBlurOrNestedShadowCutOnlyByItsPaddingIsRasterizedOnEveryMove` (6 issues) |
| X5 | `RasterExtent.of`'s nested arms grown by 1 (as X1) | `aBlurOrNestedShadowCutOnlyByItsPaddingIsRasterizedOnEveryMove` (3 issues) |

The Record phase re-applied M2a–M2e, X1 and X5 on the merged tree (`d6a2add`), each restored from
a copy with `git status --short` clean after, and ran **only the named tests** (filtered, native):
they were the pinned tests for the mutated declaration, not a whole-suite run — the full suite
ran once unmutated (§3.1). **M2f** (no identity level) is not re-run: removing the layer changes a
return type, so it is not a one-line mutation; L2.6 (`theCompositingGroupLayerIsOneIdentityLevel`)
and L2.6b pin it and were green in the unmutated suite.

### 2.6 Measurement (`PF-F` item 3)

The table in §1.7 carries the lane 2 columns. Lane 2 on top of lane 1 moves the median from
2.59 to 2.66 ms/frame (noise: other workflows were building on the Mac; counters 0/0/0 in both),
and `.compositingGroup()` on each node reads 2.46 ms. The portable blur's own speed-up is the
unchecked loops (`BoxBlur` was ~70 % of MetalCreator's release `sample`); with the cache hitting
there is little blur left in a drag frame to measure, which is the point of lane 1.

## 3. The Record phase (2026-10-10)

### 3.1 Merge and suite

- Master moved to `70e9389` (C8 app shell, §87) while the branch was paused. `git merge`
  produced one conflict, `docs/divergences.md` (both sides appended at the table's end): kept
  master's 175 and 176, then this branch's 205 (`431b4c6`). Master holds no record numbered 90.
  The header's count (126 live) and next label (175) are left for the merge to master.
- `swift package clean`, then `swift build --build-system native --build-tests` on `d6a2add`:
  0 `error:`, the only `warning:` SwiftPM's `--build-system native` deprecation notice.
  `swift test --build-system native --no-parallel`, unfiltered, unlocked screen:
  **`Test run with 3099 tests in 3 suites passed after 344.118 seconds`** (master's 3069 + 30:
  16 in lane 1, 14 in lane 2), `FR-J no-argument frame: succeeded=true`, no issue recorded (the
  five `AppKitPresentationTests` sheet tests passed). `COMPOSITING GROUP GUARD L2.G positive:
  succeeded=true`, `control: succeeded=false`.
- Typecheck guards: **196** (master's 195 + `compositingGroupIsSpellableOnBothVocabularies`;
  the count of `canTypecheck`-gated tests grew by one against `origin/master`).
- Census: `docs/probes/closeout-public-api.sh` reads **3023** lines (3021 + the two
  `compositingGroup()` declarations), identical to the recorded
  `closeout-public-api.tsv`; `closeout-inventory-check.sh` and `closeout-undocumented.sh` print
  nothing.
- The suite was re-taken a second time in the same phase on the same tree (clean, native): **`Test run with 3099 tests in 3 suites passed after 210.910 seconds`**, `FR-J no-argument frame: succeeded=true`, 0 `error:`, the native deprecation notice the only `warning:`. `swift build --build-tests` (default build system): 0 `warning:` lines (§3.1 default-build line, taken after the second run).

### 3.2 Pixels against `2155f1e`

- `docs/probes/demo-pixels/compare.sh <scratch> 2155f1e HEAD` (HEAD the merge, `431b4c6`):
  controls as recorded (light vs dark 1048576, default vs modal 1031003, default vs animation
  454895, f0 vs f3 0, preview light vs dark 1048576, chrome 0, distinct 544 / 216, prod default
  vs modal 491221, distinct prod 529, indicator rects 0); **all fourteen images `differing=0`,
  scene identical**.
- `docs/probes/shadow-cache/run.sh pixels <scratch> 2155f1e HEAD` (`d6a2add`): controls looks
  light vs dark 17610, drag 1x f0 vs f1 5101, drag 2x f2 vs f3 8016, distinct looks-light 1853,
  distinct drag-2x-f4 539; **all thirteen images `differing=0`**.
- `DemoFrameDeterminismTests`' `Expected.swift` unedited (not in `git diff 2155f1e HEAD`);
  Linux and Windows CI confirm on push.
- No real-window capture (an agent cannot judge a look; PF1 and PF2 are owed).

### 3.3 Linux image and other targets

Taken on the merged tree, CI's Linux image (`SDL_VIDEO_DRIVER=offscreen`), OrbStack left running:

- `Backends/SDL` in `metalui-portable`: **24 + 105** passed (master's figures, unmoved: this branch
  touches nothing under `Backends/SDL`; lane 2 read 24 + 96 before the merge brought master's `AS-`
  tests).
- Root package in `swift:6.4-noble`: `swift build --build-tests` then `swift test --skip-build`
  read **6 + 35 + 21 + 199 + 67 + 22**, all passed, 0 source `warning:`/`error:`. (A first attempt
  with a differently named scratch path failed on a module-cache path mismatch left in a reused
  Docker volume; it is volume state, not source, and the rerun at `/tmp/build` was clean.)
- Windows: not run locally (no VM session this phase); CI confirms on push. The branch changes no
  C-enum use and adds no target.

### 3.4 Docs changed

`CLAUDE.md` (the `PF-` paragraph under Architecture rules, the prefix list, the counts bullet,
the human-checks groups, the record map) and `AGENTS.md` (copied, `cmp` equal);
`docs/api-overview.md` (lane 2: `compositingGroup()` and the translation-free cache),
`docs/divergences.md` (205; `GX-A`'s deferred row amended; the header left for the merge),
`docs/migration.md` (an exhaustive `switch` over `LayoutModifier` gains `.compositingGroup`),
`docs/verification/human-checks.md` (group PF), `docs/record/README.md` (row 90),
`docs/record/03-verified-on-real-hardware.md` (looks owed), `README.md` (a summary paragraph),
the inventory map and the census (`b325e10`), the spec's Status.

## 4. Hazards, deferrals and owners

- **Spec §9 D1–D5 stand** (sub-pixel moves miss; a cut raster misses on every move; the
  local-mask case and the gradient strip keep their absolute keys; a non-translation effect may
  miss). Owner: none; a measured report reopens them.
- **`PF-N` item 3**: a resampled leaf's bleed column can differ from 2155f1e at an integer
  coincidence (L1.5b, 609 bytes, max delta 4). Owner: none.
- **Divergence 205**: an opacity (or any effect but a shadow or blur) outside
  `compositingGroup()` is not composited; compositing it needs an offscreen pass in both
  renderers (`TE-AD`). Owner: none. `drawingGroup()` stays unbuilt.
- **A new raster site must key through `RasterAnchor`** and keep a conservative extent: an
  extent too small treats a cut raster as uncut and shares a key with the uncut one (X1, X5 are
  the pins). A new drawn-primitive kind owes its arm in `RasterExtent.of`.
- **`LayoutModifier` gained a public case**: `swift package clean` after the change, and an
  exhaustive `switch` outside the package gains an arm (migration).
- **Measured wall time is indicative only** (other workflows shared the Mac); the pins count
  work. Not re-measured in the Record phase.
- **Human checks owed**: group PF (PF1 a trackpad drag, PF2 the LooksDemo pair), none performed.
- No ruling was appended in lane 2 or the Record phase; `PF-O` is the next unused id.

## 5. Branch checker (2026-10-10, adversarial, `2155f1e..d79e1b9`)

- **Suite.** `swift package clean`, native build (0 `error:`, the only `warning:` SwiftPM's
  deprecation notice), unfiltered `--no-parallel` at `474892c`: **`Test run with 3099 tests in 3
  suites passed after 272.064 seconds.`** `FR-J no-argument frame: succeeded=true`; `COMPOSITING
  GROUP GUARD L2.G` positive `succeeded=true`, control `succeeded=false`. No existing test file
  was edited on the branch (`git diff --name-status 70e9389..HEAD -- Tests`: six added, only
  `BoxBlurTests.swift` modified, additions only), so the identity, hit-testing, accessibility and
  animation pins stand unedited and green: `theSevenRetentionSlotsAreMutuallyDistinct`,
  `everyNamingSiteStartsAReturningNameFresh`,
  `everyRegisteringSiteAnimatesItsLoweredRectUnderTheProposalAuthority`,
  `everyBackgroundPaintingSiteAnimatesItsColour`, `everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn`,
  `everyProductionTreeBuildsOnAOneMegabyteThread`, `theLegacyEngineSymbolsAreAbsentFromTheTestProcess`.
- **Docs.** `cmp CLAUDE.md AGENTS.md` equal; every `PF-` id cited in a changed doc resolves to a
  heading (`PF-A`…`PF-N`, next `PF-O`); every test or symbol name of 23+ characters added to a
  changed doc resolves in `Sources`/`Tests`/`docs/probes` (55 names). Inventory and undocumented
  checks print nothing; the census re-run equals `closeout-public-api.tsv` (3023 rows). Fixed in
  `d79e1b9`: the amended `GX-A` deferred row still listed `.blur(radius:)` (built since `LK-K`).
- **Mutation C1** (`insertThroughScopes`' effect arm, captured depths dropped: `emitted = nil`
  instead of `kept`): the full suite **3099 passed — nothing reddens**. A checker probe (not
  committed) — L2.12's clipped square with `.compositingGroup().offset(x: 4, y: 0)` under the
  shadow — reads the group's shadow 60 wide under C1 and 30 wide restored: the effect arm's depth
  carry (`kept`) is live and unpinned. Owner: the merge (a test like L2.12 with an effect between
  the group and the shadow).
- **Mutation C2** (`shadowImage` keys and cuts with the absolute `placement.clip` instead of
  `anchor.canonical(placement.clip)`): 39 issues in `aBlurOrNestedShadowCutOnlyByItsPaddingIsRasterizedOnEveryMove`,
  `aCanonicalRasterEqualsTheAbsoluteOne`, `aCompositedNodeBlursOneMask`,
  `aLegacyShadowsColourRadiusAndOffsetAnimate`, `aResampledLeafAtAnIntegerCoincidenceMayGainItsBleedColumn`,
  `aShadowCutByItsClipIsRasterizedOnEveryMove`, `aShadowIsCutByAnOuterClipAndShapedByAnInnerOne`,
  `shadowColourRadiusAndOffsetAnimate`. Both restored from copies; `git status --short` clean.
- **Pixels** re-taken (`compare.sh <scratch> 2155f1e HEAD` at `d79e1b9`): controls 1048576 /
  1031003 / 454895 / 0 / 1048576 / 0 / 544 / 216 / 491221 / 529 / 0; all fourteen images
  `differing=0`, scenes identical.
- **Linux.** `metalui-portable`: `Backends/SDL` **24 + 105**; `swift:6.4-noble` root **6 + 35 + 21
  + 199 + 67 + 22**, 0 `warning:`. **macOS** `Backends/SDL`: **24 + 108** (its two `warning:` lines,
  `AccessKitControlsParityTests.swift:83` and the SDL dylib's deployment target, are master's; the
  branch touches nothing under `Backends/SDL`).
- **Dead code** (reported, not fixed): `TransitionStore.Record.captureDepths` is a stray copy of
  `PaintScope.captureDepths` (mis-indented, never read or written). Owner: the merge.
- `swift build --build-tests` (default build system): 0 `warning:`.
- No real-window capture; human checks PF1, PF2 owed, none claimed.
