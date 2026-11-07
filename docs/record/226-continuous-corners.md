# Record 226: continuous rounded corners, outlines (round-4 item R4-5 PR F, run 1) - DRAFT

**Draft.** Run 1 of two. Branch `feat/continuous-corners` (from master `17b76c1b`), prefix `CC-` (new; no decisions document yet, no ledger edit yet: divergence 90, the rules shards, `decision-prefixes.md`, human checks group `CC`, CLAUDE.md/AGENTS.md and the counts line all wait for run 2). Plan: the planner's `cc-plan.md`; probe `docs/probes/swiftui-continuous-corners.swift`. What run 1 builds: SwiftUI's `.continuous` corner for **every outline** - a rounded rectangle or capsule fill, a `strokeBorder` and `stroke`, a material or glass backdrop, a shadow or blur silhouette, a `Path`, a hit test. What it does **not** touch: a `clipShape(RoundedRectangle)` or `.cornerRadius` clip is still circular (run 2, sign-encoded mask radii), and multi-member glass members.

## 1. What SwiftUI does (probe, macOS 27.2, compiled, run twice, identical)

**The corner is read, not fitted.** `Path.forEach` hands out SwiftUI's own Beziers; a model of them agrees to **7.5e-6 absolute (6.5e-8 of the radius)** on a 17-case `RoundedRectangle` grid (100x60 at r 0..50, 100x100, 200x60, an offset origin, 1000x600 at r 256), five capsules, the 21-case `UnevenRoundedRectangle` grid, **2000 random uneven radii** and the elliptical `cornerSize` (CC1-CC4). A corner is **three cubics** (probe header has the table): `A` along the horizontal side, `B` the middle, `C` along the vertical side, in units of the radius `r`, with `T0 = 1.528664947` the reach along a side:

- `A = (t,0) (c1(t),0) (c2(t),0) (0.631493986, 0.074911401)`, `B = (0.631493986, 0.074911401) (0.372824013, 0.169060007) (0.169060007, 0.372824013) (0.074911401, 0.631493986)`, `C` the mirror of `A` with its own `t`;
- `t = min(room / r, T0)`, `c1(t) = 0.716953795 + 0.243046205 t`, `c2(t) = 0.728435369 + 0.091564631 t`: **linear in the room**, the whole large-radius regime. `B` never moves;
- the **room** of a side for a corner is `side * r / (r + neighbour's r)`: half the side beside an equal corner, all of it beside a square one. For `RoundedRectangle` and `Capsule` that is the half side, and the radius clamps to half the shorter side (S4);
- **uneven radii** (CC3, 2000 random, 0 mismatches; the other 23 orders of the four sides mismatch 38 to 186): fit the **horizontal sides first** (top, then bottom), then the vertical sides (right, then left), each pair by `fitPair` (if they overlap the larger gives way to what the smaller leaves, both become half when both are at least half). **The circular `UnevenRoundedRectangle` fits the same way (CC3c: 0 of 847) and the shipped `fitted(width:height:)` fitted all four sides at once and missed SwiftUI on 39 of 847**; it now uses `ContinuousCorner.fit` for both styles;
- an **elliptical** `cornerSize` scales the pair together, keeping its ratio, until it fits half the sides (60x20 on 100x60 is 50x16.667); the corner scales `u` by `rx` and `v` by `ry` (CC4);
- the outline starts on the right edge at `(tr + h - br) / 2` and runs down (BR, BL, TL, TR); every corner emits its line and three cubics even at radius 0 (all radii 0 is a plain rectangle) (CC9).

**The rasteriser caveat (CC0).** The pixel arm cannot read 0 px: SwiftUI's shape fill is **not** rasterised like the same cubics as a generic `Path` at 1x (240 px, gap 36, `RoundedRectangle.path(in:)` re-filled element by element). So CC0 uses an exact-area metric (sum of |coverage difference| in pt2 over the 100x60 canvas) with the circular corner's own comparison as the noise floor: continuous fill against the flattened model **2.72 pt2 at scale 8** (5.30 at 1x), circular **18.2** (196 px at 1x, S3), superellipse n=4 **243** and n=5 **280**; the circular corner against its own flattened elements, **0.65 at scale 8**. Residual 0.02 pt mean offset at r 20, 1e-3 r. **Stop condition 1 did not fire** (the elements fit a closed form to 6.5e-8 r).

Other readings: CC5 `strokeBorder(w)` is **exactly the inset band** (the stroke of the shape inset by `w/2` with radius `r - w/2`), 0 px apart on four (r, w) pairs; an inset radius that is not positive leaves a **square outer corner** (CC5b: pixel (0,0) is covered, and equals the inset `Rectangle`'s miter stroke). **Stop condition 4 did not fire.** CC6 a continuous clip (`clipShape`, `.cornerRadius(20)`) equals the fill, 0 px, the circular clip is 196 px away. CC7 a shadow follows the curve (1384 px from the circular one). CC8 `Path.contains` follows it. CC2 `Capsule(.continuous)` is `RR(50)` is the capsule at r = min/2, 230 px from the circular capsule; the 60x60 capsule is the `Circle`.

**The corner is not exactly tangent at its joints** (the elements kink by 0.043 rad at the full reach): the model keeps it, since the target is SwiftUI's elements. The curve lies within **0.0138 r** of the circular corner of the same r for every `(tx, ty)` (two-sided, brute force), which is the shader's gate.

## 2. What was built

- **Shader kind** `MUIShapeContinuousRect = 2` in the byte `MUIRect.shape` and `MUIBackdrop.shape` already hold (stride 120 and the fixture version 9 unchanged; kind 0 runs today's statements). `continuous_rect_sdf` in `shaders.metal` and `continuousRectSDF` in `replay.hlsl`, the same statements and constants (a test reads the constants out of both files and pins them to `ContinuousCorner`): `rect_sdf` first, and only where `|d| <= 0.02 r + band` the distance to the three cubics by a fixed 4-sample seed per cubic and **four** Newton steps (plus the two straight rays), the sign from the tangent at the nearest point. The border is the **ellipse branch's band model** on the inset curve (`borderWidths.top`, `shrink = w/2`, a non-positive inset radius left square by the Chebyshev distance). `backdrop_coverage` gets it through `rect_shade`; the single-member glass SDF takes it with `band + 2`.
- **CPU**: `ContinuousCorner` in `MetalUIPath` (imports nothing; `package`): the constants, `cubics`, `reach`, `fitPair`, `fit`, `room`, `fitsQuadrants`; `PathGeometry.addContinuousRoundedRect` (uneven and elliptical). `Path.addRoundedRect(in:cornerSize:style:)`, `Path(roundedRect:...)`, `Path(ShapeGeometry)`; `ShapeGeometry.primitiveShape` (kind 2 for any nonzero radius, kind 0 for a plain rectangle), `contains` (the path's winding), `paintShapeStroke` (no `kept` rule for kind 2), `RasterMath.outline`/`continuousOutline`, the shadow and blur silhouettes (the band is the stroked inset outline); the raster key already carries `shapeKind` (`keyLeaf` is shared by shadow and blur). `UnevenRoundedRectangle(.continuous)` is the renderer's rect while every corner's curve stays in its quadrant (`fitsQuadrants`), else a `Path` (`PG-G`).
- **Parity frame 21** (`continuousCornersFrame`, 640x380, through `renderFrame`): fills at r 8, 20, 60 and a capsule; `strokeBorder` 1, 6 and 20; a `stroke`; a rotated rect (the scaled distance); a `rotation3DEffect` band (the projective scale); a material over stripes (a kind-2 backdrop). `--expect 22` on both workflow lines, the README's count.
- **Blobs** rebuilt with shadercross `1ff05bec` (`compile-shaders.py`, `SOURCE.sha256`); the baseline run before the edit reproduced the checked-in blobs with no diff.

## 3. Design changes the probe and the measurements forced

- **Four Newton steps, not three** (stop condition 5 did not fire, because it was caught on the test): a capsule 400x300 at r 150 read **12 levels (0.047 px)** off the exact distance at the pixels beside the junction of cubic `C` with its side; in Python, 3 steps leave **1.0e-3 r** worst case near a cubic's flat end (the parametrisation is cubic there), 4 leave **4.5e-7 r**, 5 leave 2e-14. With four steps the worst case over 2500 wide and 3000 near-curve points is 6.7e-6 r.
- **Rooms come from the neighbour radius, not from the half side**: the SDF reads `r`, `rH`, `rV` of the picked corner and its two neighbours, so every uneven shape the fold can hold is exact.
- **The fold needs a quadrant rule**: the shader folds into the corner's quadrant, so a curve that reaches past the centre line (TL 30 beside BL 10 on 100x60 takes 45 of 60) is a `Path`. A reach past the half whose tail is under 0.01 px off its side stays the renderer's (`fitsQuadrants`: `k1 d^3 / (27 (t - c1)^3 r^2)`; the common 100x60 card with 20 radii reaches 30.57 on 30 and is 1.5e-5 px off).
- **`point` is an HLSL keyword** (`float2 point;` fails to compile in the first `CCNearest`); the field is `nearest` in both shaders.
- **The corner's joints are not tangent**; the test the plan implied (G1) was wrong and is now "turns by under 0.05 rad".
- **No diagonal fold**: with `tx != ty` (a clipped room on one side) the curve is not symmetric, so the plan's "reflect across the diagonal" is not valid and all three cubics are searched. The cost probe (section 6) judges it.
- **A distinct kind for a clipped continuous clip is run 2**; no sign-encoded mask radii exist yet.

## 4. Mutations (each applied alone in place after committing, restored with `git checkout`; `swift test --build-system native --no-parallel --filter <the continuous tests and their neighbours>`)

24 mutations, every one reddened at least one test (the filter is the 67 continuous tests and their neighbours; M-ids are the harness's). **Mutating `shaders.metal` needs no Swift rebuild (a resource), so those ran in seconds.** M01 does not redden `aContinuousRectDrawsItsCurve` because the r 20 in 100x60 corner reaches 30 (the half side) whichever constant caps it; the element-by-element test is the one that sees the cap.

| Id | Mutation (spelling) | File | Reddened |
| --- | --- | --- | --- |
| M01 | reach constant 1.528664947 -> 1.5 (ContinuousCorner.extent, Swift only) | `ContinuousCorner.swift` | aContinuousCornerPathIsSwiftUIs, aContinuousStrokeBorderIsTheInsetCurvesBand, theContinuousOutlineIsSwiftUIsElementForElement, theCurvesConstantsAreTheSameInEveryRenderer |
| M02 | clipped-room control arms replaced by the full-reach ones (a1+b1 t -> 1.088490009, a2+b2 t -> 0.868407011), cubics() | `ContinuousCorner.swift` | aContinuousCornerPathIsSwiftUIs, aContinuousRectDrawsItsCurve, aContinuousRectIsTheCurveThePathRasterFills, aCornersCubicsMeetAndMirror |
| M03 | start point at the right edge's midpoint (h/2) instead of (tr + h - br)/2 | `ContinuousCorner.swift` | aContinuousCornerPathIsSwiftUIs, theContinuousOutlineIsSwiftUIsElementForElement |
| M04 | shaders.metal: kind 2 treated as kind 0 (rect_shade branch never taken) | `shaders.metal` | aContinuousBorderWiderThanItsRadiusKeepsASquareOuterCorner, aContinuousRectDrawsItsCurve, aContinuousRectIsTheCurveThePathRasterFills, aContinuousStrokeBorderIsTheInsetCurvesBand |
| M05 | shaders.metal: Newton 4 steps -> 1 | `shaders.metal` | aContinuousRectDrawsItsCurve, aContinuousRectIsTheCurveThePathRasterFills, aContinuousStrokeBorderIsTheInsetCurvesBand |
| M06 | shaders.metal: the two straight rays dropped from the unsigned distance | `shaders.metal` | aContinuousStrokeBorderIsTheInsetCurvesBand |
| M06b | shaders.metal: the sign taken from the opposite side of the tangent | `shaders.metal` | aContinuousRectDrawsItsCurve, aContinuousRectIsTheCurveThePathRasterFills |
| M07 | shaders.metal: border inner edge as continuous(r - w) on the full rect instead of the inset band | `shaders.metal` | aContinuousStrokeBorderIsTheInsetCurvesBand |
| M08 | shaders.metal: Chebyshev (square outer corner) branch dropped | `shaders.metal` | aContinuousBorderWiderThanItsRadiusKeepsASquareOuterCorner |
| M09 | RasterMath.outline ignores the kind (circular outline for kind 2) | `RasterCache.swift` | aContinuousShapesShadowFollowsItsCurve |
| M10 | ShapeGeometry.contains ignores the corner style (circular test) | `Shape.swift` | aBuiltInShapesPathMatchesItsGeometry, aContinuousContentShapeHitsItsCurve |
| M11 | uneven eligibility always the SDF for .continuous | `Shapes.swift` | anUnevenContinuousCornerPastItsQuadrantIsAPath |
| M12 | a continuous RoundedRectangle routed through Path (geometry returns a .path) | `Shapes.swift` | aCircleCapsuleOrContainedClipTakesNoGroup, aContinuousRectCostsOneRect, aContinuousShapeEmitsTheContinuousKind, aContinuousStrokeKeepsItsRadii, aStrokeBorderWiderThanTwiceTheRadiusHasASquareOuterCorner, aStrokeRoundsItsOuterEdgeByHalfTheWidthOnlyOverACurve, theBackdropShapeIsTheFilledRoundedRectOrEllipse |
| M13 | M2n: RoundedRectangle and Capsule default style .circular | `Shapes.swift` | aContinuousRectCostsOneRect, aContinuousShapeEmitsTheContinuousKind, aContinuousStrokeKeepsItsRadii, aStrokeBorderWiderThanTwiceTheRadiusHasASquareOuterCorner, anAxisAlignedRectGradientDrawsAOnePixelStrip, theBackdropShapeIsTheFilledRoundedRectOrEllipse, theContinuousStyleIsTheDefaultAndDrawsItsCurve |
| M13b | Capsule default style .circular | `Shapes.swift` | aContinuousCornerPathIsSwiftUIs, aContinuousShapeEmitsTheContinuousKind, anEllipseEmitsTheEllipseKind, theContinuousStyleIsTheDefaultAndDrawsItsCurve |
| M14 | paintShapeStroke applies the kept rule to the continuous kind | `ShapeView.swift` | aContinuousStrokeKeepsItsRadii, aStrokeBorderWiderThanTwiceTheRadiusHasASquareOuterCorner |
| M15 | the shadow/blur key without the shape kind | `Shadow.swift` | aRastersKeyCarriesTheShapeKind |
| M16 | replay.hlsl alone: CC_K0 0.631493986 -> 0.631493987 (constants pin) | `replay.hlsl` | theCurvesConstantsAreTheSameInEveryRenderer |
| M17 | quadrant tail rule admits every overshoot | `ContinuousCorner.swift` | anUnevenContinuousCornerPastItsQuadrantIsAPath, theQuadrantRuleAdmitsAnOvershootOnlyWhileItsTailIsInvisible |
| M17b | quadrant tail rule admits no overshoot | `ContinuousCorner.swift` | anUnevenContinuousCornerPastItsQuadrantIsAPath, theQuadrantRuleAdmitsAnOvershootOnlyWhileItsTailIsInvisible |
| M18 | uneven fit: vertical sides before horizontal | `ContinuousCorner.swift` | theUnevenFitIsHorizontalSidesFirst |
| M19 | Path(ShapeGeometry) draws the circular arcs for a continuous geometry | `Path.swift` | aContinuousContentShapeHitsItsCurve, aContinuousCornerPathIsSwiftUIs |
| M20 | primitiveShape answers .roundedRectangle for every rounded rectangle | `Shape.swift` | aContinuousRectCostsOneRect, aContinuousShapeEmitsTheContinuousKind, aContinuousShapesShadowFollowsItsCurve, aContinuousStrokeKeepsItsRadii, aRastersKeyCarriesTheShapeKind, aStrokeBorderWiderThanTwiceTheRadiusHasASquareOuterCorner, anAxisAlignedRectGradientDrawsAOnePixelStrip, anEllipseEmitsTheEllipseKind, anUnevenContinuousCornerPastItsQuadrantIsAPath, theBackdropShapeIsTheFilledRoundedRectOrEllipse, theContinuousStyleIsTheDefaultAndDrawsItsCurve |
| M21 | the horizontal neighbour's radius ignored in the room (shader: room = whole side beside any corner) | `shaders.metal` | aContinuousRectDrawsItsCurve, aContinuousRectIsTheCurveThePathRasterFills |
| P1 | `replay.hlsl` alone: `CC_K0` 0.631493986 -> 0.531493986, blobs rebuilt, `Replay --portable` | `replay.hlsl` | frame 15 (the first continuous rect in the sequence): 156 px, max channel delta 213, `Parity failed` (the run stops there; frame 21 is not reached; restored with `git checkout -- Backends/SDL/Shaders`, then 0/0 again) |


## 5. Pins moved, with cause

| Pin | Cause |
| --- | --- |
| `ShapeTests` 2.14 `theContinuousStyleIsTheDefaultAndIsDrawnCircular` -> `...DrawsItsCurve` | divergence 90's pin: the default is still `.continuous`, and painted shapes now differ from `.circular` |
| `ShapeTests` 2.4 `anEllipseEmitsTheEllipseKind` (capsule arm) | `Capsule()` defaults to `.continuous`, kind 2; the circular arm uses `Capsule(style: .circular)` and a continuous arm is added |
| `ShapeStrokeTests` 2.10 `aStrokeBorderWiderThanTwiceTheRadiusHasASquareOuterCorner` | K11 is the **circular** kind's CPU rule; the default `RR(3)` strokeBorder is kind 2 and keeps its radius for the shader (CC5b); both arms |
| `BackdropRecordTests` 1.3 `theBackdropShapeIsTheFilledRoundedRectOrEllipse` | a material over the default `RoundedRectangle` is kind 2; `.circular` keeps the old arm |
| `GradientRasterTests` `anAxisAlignedRectGradientDrawsAOnePixelStrip` | the strip is a circular mask over one pixel; a continuous rect is rasterised in full (`GradientRaster` already sends any kind but `.roundedRectangle` there) |
| `PathOpsTests` PG-G 4 `anUnevenRectangleUsesTheSDFWhenItCanAndAPathWhenItMust` | TL 30 beside BL 10 on 100x60 is a `Path` under `.continuous` (reach 45 of 60); the circular style keeps the SDF arms |
| `ShaderABITests` 1.10 | `MUIRect.shape` read as 2 (the new value); a test pins `PrimitiveShape` to the shaders' enum |
| `RectangleCornerRadii.fitted(width:height:)` | fits horizontal sides first (CC3c), a behaviour change of the circular `UnevenRoundedRectangle` in 39 of 847 random cases; `radiiFitByTheSwiftUIRule` is unchanged |

The full unfiltered run before these edits read 7 failures, exactly the first six rows (the fits and the ABI arm were not failing).

## 6. GPU cost (plan section 8 (ii), `docs/probes/continuous-corner-cost/run.sh`, Apple M6, `gpuEndTime - gpuStartTime`, median of 50 frames, 10,000 opaque overlapping rects in 2560x1440)

**Stop condition 6 fires, twice.** The probe is `docs/probes/continuous-corner-cost/run.sh` (test `theGPUCostOfTheContinuousKind`, env-gated `METALUI_CORNER_COST=1`, Apple M6, `gpuEndTime - gpuStartTime`, median of 50 frames after 10 warm-up, 10,000 opaque overlapping rects in 2560x1440, two runs per arm, medians agree to 0.5 %). Medians in ms:

| Arm | `big` 96x64 r 20 | `small` 24x24 r 12 |
| --- | --- | --- |
| base shaders (`17b76c1b`), kind 0 | 3.000 | 0.347 |
| branch, kind 0 (circular) | **3.270** (+9.0 %) | **0.385** (+11 %) |
| branch, kind 2 (continuous) | **7.500** (2.29x the branch's circular) | **1.659** (4.31x) |

- **The kind-0 path regressed beyond noise** (noise is 0.3 %): +0.27 ms on 10,000 rects. Diagnosis by experiment (not committed): the continuous branch **stubbed with the circular distance** leaves kind 0 at **3.093 / 0.357 ms (+3 %)**, so the extra branch and the larger `rect_shade` cost 3 % by structure and the closest-point code another 6 % (register pressure; marking `cc_nearest` and `continuous_corner_sdf` `noinline` changes kind 0 by 0.0 % and makes kind 2 **8.724 / 2.016 ms**, worse). The stub's kind 2 is 2.888 / 0.337 ms.
- **Continuous is above 1.5x circular** on both frames. The gate (`|rect_sdf| <= 0.02 r + 0.5/s`) passes every pixel in the band along the whole outline, and with r 20 the corner zones are 77 % of the outline (`4 * 2 * 1.53 r` of `2 (w + h)`), so SIMD groups along the outline run the closest-point code; the cost is 3 cubics x (4 seeds + 4 Newton steps) a band pixel.
- **One cheaper arm was measured and is not free**: seeding all three cubics but refining only the best one (4 steps) reads **5.441 / 1.137 ms (1.67x / 2.96x)**, and `aContinuousRectDrawsItsCurve` goes red (gap above 3 levels: the flat cubic `A` and `C` ends mislead a 4-sample seed, the single-best variant read 6.5e-5 r in Python on near-curve points but not on the capsule's tip).
- **Options for the decision** (none taken): (a) a separate fragment function and draw-run kind for continuous rects (kind 0 returns to the base's 3.000, the plan's section 3 (a)+(c) per-primitive selection is replaced by a pipeline per kind, `replay.hlsl`'s rect stage needs a second entry point and `SDLBridge` a pipeline); (b) a cheaper distance: a longer seed (8 samples) plus 3 steps on the best cubic, or a per-region choice (the corner box decides which cubic), validated against the 3-level test and the 1/32 px criterion; (c) accept the cost as the price of the SwiftUI default (every `RoundedRectangle` and `Capsule`), which is what `Button`, `glassEffect` and material backgrounds draw.

## 7. Parity

- **SDL over the shadercross MSL** (`Replay --portable`, SDL Metal driver, Apple M6): frames 0-21 **0 differing pixels, max channel delta 0** (frame 21: 15 rects, 2 transforms, 1 backdrop; the draw-order control detected).
- **`PortableReplay` on SDL Metal**: 22 fixtures, every frame 0 px, max delta 0.
- **llvmpipe Vulkan** (the `metalui-portable` image from `git archive HEAD`, llvmpipe LLVM 20.1.2): all 22 fixtures within tolerance. **Frame 21: outside sprites 228 px, max delta 1 (limit 1); inside backdrop quads 8448 px, max delta 1 (limit 3); inside glyph and image quads 0 px.** Frames 0-20 as before the change (max delta 1 outside, 3 inside).
- Not run: Direct3D 12 (Windows CI is the judge).

## 8. TODO(run 2)

- the clip stack: `ShapeGeometry.clip` for continuous (negated mask radii), `pushClip`, `Frame.intersect`/`clipsCross` on the continuous extent, the 19 `activeClipRadii` readers and every `max(0, ...)`, `mask_coverage`/`mask_coverage_scaled`/the transform outer mask in both shaders, `aContinuousClipCutsItsCurve` (rect, image and glyph content arms);
- multi-member glass (`GlassMember` radii sign, `glass_member_sdf`/`glassMemberSDF`); `GlassReference` (the CPU twin) still draws kind 2 circular;
- the ledger: divergence 90 (retired, or narrowed to the clip if run 2 is cut), `decisions` document and `decision-prefixes.md`, `drawing.md`/`sdl.md` paragraphs, human checks group `CC`, the inventory map rows, `api-overview.md`, `migration.md`, the README row, `Tasks.md`, CLAUDE.md/AGENTS.md and the counts line.
- unmeasured: built-in control looks (a `Button`'s, a text field's corner) are not measurable through `ImageRenderer`; note, no row.

## 9. Verbatim summary lines

Head `61ef285f` plus this record. `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`, `swift package clean`, `swift build --build-system native --build-tests`, then:

- `swift test --build-system native --no-parallel` (unfiltered): `✔ Test run with 5402 tests in 14 suites passed after 359.829 seconds.` and `FR-J no-argument frame: succeeded=true deprecations=2`. (The same run before the test edits read `✘ Test run with 5386 tests in 14 suites failed after 363.044 seconds with 7 issues`: the six rows of section 5 and the second `2.14` expectation.)
- `METALUI_VERIFY_RETAINED=1 swift test --build-system native --no-parallel --skip-build`: `✔ Test run with 5402 tests in 14 suites passed after 366.970 seconds.`
- Portable (Docker image `metalui-portable`, a `git archive HEAD`, `swift test --scratch-path /tmp/root --filter "MetalUIPathTests|MetalUILayoutTests|MetalUICoreTests|MetalUICrossPlatformTests"`): 53, 286, 154 and 24 tests passed. (An earlier run read 18 issues in `aCornersCubicsMeetWithOneTangent`: the corner's joints are not tangent, the test was wrong.)
- `Backends/SDL`, `swift test --build-system native` with the AccessKit flags, `--filter 'ReplayFixture|SDLGroup|SDLClipMask|SDLTextGradient|ShaderABI|ShaderSlot'`: `✔ Test run with 55 tests in 0 suites passed after 0.802 seconds.`
- `PortableReplay ../../Experiments/SDLGPU/fixtures --expect 22` (SDL Metal): `SDL GPU driver: metal; fixtures: 22`, every frame 0 px, `PASS`; `--driver vulkan` (llvmpipe, Docker): `SDL GPU driver: vulkan; fixtures: 22`, `PASS`.
- `zsh docs/probes/closeout-inventory-check.sh` and `closeout-undocumented.sh`: no output.
