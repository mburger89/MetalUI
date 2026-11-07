# Record 226: continuous rounded corners, outlines (round-4 item R4-5 PR F, run 1)

Run 1 of two, shipped alone. Branch `feat/continuous-corners` (from master `17b76c1b`, merged with `#222`), prefix `CC-`, decisions `docs/superpowers/2026-11-07-continuous-corners-decisions.md` (next `CC-J`). Class `D`; **divergence 90 narrowed** (**208 live after 167 is retired**, next label 227) to a continuous `clipShape`/`.cornerRadius` clip and multi-member glass, carried to run 2. Plan: the planner's `cc-plan.md`; probe `docs/probes/swiftui-continuous-corners.swift`. Human checks group `CC`. What run 1 builds: SwiftUI's `.continuous` corner for **every outline** - fill, capsule, `strokeBorder`/`stroke`, material and single-member glass, shadow and blur silhouettes, `Path`, hit test. It does not touch the clip stack or `mask_coverage` (user decision: kind 0's shader stays the base's).

**Divergence 167 retired here too**, on the user's decision and without SwiftUI's side measured: PR #215's `GF-` work implements a GPU surface blurred with its siblings, the window arm `W1` (a layer-backed `NSViewRepresentable` under `.blur(radius: 6)`) was never run, `ImageRenderer` draws no platform view (`GF6`); human check `GF3` stays as the confirmation.

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

- **Shader kind** `MUIShapeContinuousRect = 2` in the byte `MUIRect.shape` and `MUIBackdrop.shape` already hold (stride 120 and the fixture version 9 unchanged; kind 0 runs today's statements). `continuous_rect_sdf` in `shaders.metal` and `continuousRectSDF` in `replay.hlsl`, the same statements and constants (a test reads the constants out of both files and pins them to `ContinuousCorner`): `rect_sdf` first, and only where `|d| <= 0.02 r + band` the distance to ONE cubic picked by the joints' tangents (3 seeds, 3 Gauss-Newton steps; section 6), plus the two straight rays, the sign from the tangent at the nearest point. **The continuous kind has its own fragment entry** (`rect_continuous_fragment`, `continuous.fragment`) so kind 0's shader is the base's. The border is the **ellipse branch's band model** on the inset curve (`borderWidths.top`, `shrink = w/2`, a non-positive inset radius left square by the Chebyshev distance). `backdrop_coverage` calls `rect_shade_continuous` for kind 2; the single-member glass SDF takes it with `band + 2`.
- **CPU**: `ContinuousCorner` in `MetalUIPath` (imports nothing; `package`): the constants, `cubics`, `reach`, `fitPair`, `fit`, `room`, `fitsQuadrants`; `PathGeometry.addContinuousRoundedRect` (uneven and elliptical). `Path.addRoundedRect(in:cornerSize:style:)`, `Path(roundedRect:...)`, `Path(ShapeGeometry)`; `ShapeGeometry.primitiveShape` (kind 2 for any nonzero radius, kind 0 for a plain rectangle), `contains` (the path's winding), `paintShapeStroke` (no `kept` rule for kind 2), `RasterMath.outline`/`continuousOutline`, the shadow and blur silhouettes (the band is the stroked inset outline); the raster key already carries `shapeKind` (`keyLeaf` is shared by shadow and blur). `UnevenRoundedRectangle(.continuous)` is the renderer's rect while every corner's curve stays in its quadrant (`fitsQuadrants`), else a `Path` (`PG-G`).
- **Parity frame 21** (`continuousCornersFrame`, 640x380, through `renderFrame`): fills at r 8, 20, 60 and a capsule; `strokeBorder` 1, 6 and 20; a `stroke`; a rotated rect (the scaled distance); a `rotation3DEffect` band (the projective scale); a material over stripes (a kind-2 backdrop). `--expect 22` on both workflow lines, the README's count.
- **Blobs** rebuilt with shadercross `1ff05bec` (`compile-shaders.py`, `SOURCE.sha256`); the baseline run before the edit reproduced the checked-in blobs with no diff.

## 3. Design changes the probe and the measurements forced

- **Newton from 4 seeds needed 4 steps, not three** (stop condition 5 did not fire, because it was caught on the test): a capsule 400x300 at r 150 read **12 levels (0.047 px)** off the exact distance at the pixels beside the junction of cubic `C` with its side; in Python, 3 steps leave **1.0e-3 r** worst case near a cubic's flat end (the parametrisation is cubic there), 4 leave **4.5e-7 r**. The final design (section 6) replaces it: Gauss-Newton on the one cubic the joints pick reaches 1.8e-5 r in 3 steps from 3 seeds.
- **Rooms come from the neighbour radius, not from the half side**: the SDF reads `r`, `rH`, `rV` of the picked corner and its two neighbours, so every uneven shape the fold can hold is exact.
- **The fold needs a quadrant rule**: the shader folds into the corner's quadrant, so a curve that reaches past the centre line (TL 30 beside BL 10 on 100x60 takes 45 of 60) is a `Path`. A reach past the half whose tail is under 0.01 px off its side stays the renderer's (`fitsQuadrants`: `k1 d^3 / (27 (t - c1)^3 r^2)`; the common 100x60 card with 20 radii reaches 30.57 on 30 and is 1.5e-5 px off).
- **`point` is an HLSL keyword** (`float2 point;` fails to compile in the first `CCNearest`); the field is `nearest` in both shaders.
- **The corner's joints are not tangent**; the test the plan implied (G1) was wrong and is now "turns by under 0.05 rad".
- **No diagonal fold**: with `tx != ty` (a clipped room on one side) the curve is not symmetric, so the plan's "reflect across the diagonal" is not valid; the corner's joints pick the cubic instead (section 6).
- **A distinct kind for a clipped continuous clip is run 2**; no sign-encoded mask radii exist yet.

## 4. Mutations (each applied alone in place after committing, restored with `git checkout`; `swift test --build-system native --no-parallel --filter <the continuous tests and their neighbours>`)

30 mutations (M01-M21 on the first design, N1-N6 after the split fragment entry and the cheaper distance), every one reddened at least one test (the filter is the 67 continuous tests and their neighbours; M-ids are the harness's). **Mutating `shaders.metal` needs no Swift rebuild (a resource), so those ran in seconds.** M01 does not redden `aContinuousRectDrawsItsCurve` because the r 20 in 100x60 corner reaches 30 (the half side) whichever constant caps it; the element-by-element test is the one that sees the cap.

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
| N1 | Scene.finalize does not break a rect run at the continuous kind change | `Scene.swift` | aRunBreaksWhereTheContinuousKindChanges |
| N2 | Renderer always binds the circular rect pipeline | `Renderer.swift` | aContinuousBorderWiderThanItsRadiusKeepsASquareOuterCorner, aContinuousRectDrawsItsCurve, aContinuousRectIsTheCurveThePathRasterFills, aContinuousStrokeBorderIsTheInsetCurvesBand, aTransformedContinuousRectUsesTheContinuousDistance |
| N3 | shaders.metal: the joint tangent test never picks cubic A (selection wrong) | `shaders.metal` | aContinuousRectDrawsItsCurve, aContinuousRectIsTheCurveThePathRasterFills, aContinuousStrokeBorderIsTheInsetCurvesBand |
| N4 | shaders.metal: Gauss-Newton 3 steps -> 1 in cc_nearest | `shaders.metal` | aContinuousRectDrawsItsCurve, aContinuousRectIsTheCurveThePathRasterFills, aContinuousStrokeBorderIsTheInsetCurvesBand |
| N5 | shaders.metal: the deep fallback (all three cubics, Newton) never taken | `shaders.metal` | aContinuousStrokeBorderIsTheInsetCurvesBand |
| N6 | shaders.metal: rect_continuous_fragment shades with the circular rect_shade | `shaders.metal` | aTransformedContinuousRectUsesTheContinuousDistance |
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

**Stop condition 6 fired on the first design; the decision was (a) its own fragment entry and (b) a cheaper distance, re-measured below. The final cost (1.49x on `big`, 2.46x on `small`) was ACCEPTED by the user.** The probe is `docs/probes/continuous-corner-cost/run.sh` (test `theGPUCostOfTheContinuousKind`, env-gated `METALUI_CORNER_COST=1`, Apple M6, `gpuEndTime - gpuStartTime`, median of 50 frames after 10 warm-up, 10,000 opaque overlapping rects in 2560x1440, two or three runs per arm, medians agree to 0.1 % on a quiet machine). Medians in ms (the 2.3x/4.3x row is what stop condition 6 read):

| Arm | `big` 96x64 r 20 | `small` 24x24 r 12 |
| --- | --- | --- |
| base shaders (`17b76c1b`), kind 0 | 3.000 | 0.347 |
| first design: continuous inside `rect_fragment`, kind 0 | 3.270 (+9.0 %) | 0.385 (+11 %) |
| first design, kind 2 | 7.500 (2.29x) | 1.659 (4.31x) |
| **(a)** own fragment entry, kind 0 | **3.000-3.004 (0.0 %)** | **0.347 (0.0 %)** |
| (a), kind 2, distance unchanged | 7.298 (2.43x) | 1.649 (4.75x) |
| (a) + cubic picked by the joints' tangents, 4 seeds, 4 Newton steps | 4.930 (1.64x) | 1.809 (noisy machine) |
| **(a)+(b) final**: one cubic, 3 seeds, 3 Gauss-Newton steps, kind 2 | **4.481 (1.49x)** | **0.855 (2.46x)** |

- **(a) made kind 0 the base's, byte for byte**: `rect_shade` and `rect_fragment` in `shaders.metal` and the `rect.fragment`, `glyph.fragment` and `image.fragment` blobs equal `17b76c1b`'s (`git diff 17b76c1b --stat` on `compiled/` lists only `backdrop.fragment.*`, which carries the continuous SDF for material backdrops, and `SOURCE.sha256`; the new `continuous.fragment.{spv,msl,dxil,json}` are additions). The continuous kind is `rect_continuous_fragment` (shares `rect_vertex`; portable stage `continuous.fragment`, `-DCONTINUOUS_STAGE`), a pipeline in `Renderer` and in `SDLBridge.c` (`g->continuous`, chosen in `draw_primitives` from the first packed record's shape word), and **`Scene.finalize` starts a rect run wherever the continuous kind changes** (no new `PrimitiveKind`, run kind or fixture version: the pipeline is read from the run's first rect, so fixtures v9 and every SDL consumer stay as they were). A mixed scene pays one extra run at each kind change.
- **(b) the distance**, in `shaders.metal` and `replay.hlsl` identically: the tangent at each cubic joint picks the nearest cubic (the curve is convex; a point in the 0.043 rad kink wedge clamps to the joint on either); a 3-sample seed and **three Gauss-Newton steps** (`t -= v.e / v.v`) on that cubic; Python on 1500 near-curve points: Newton with the curvature term needs 4 steps from 4 seeds for 1.8e-5 r, Gauss-Newton reaches the same **1.8e-5 r floor (the joint wedge) in 3 steps from 3 seeds**; a point more than 0.2 r from the outline (a wide border's band, the r 30 border 24 test) keeps the full search of all three cubics with four Newton steps (Gauss-Newton there read 9 levels off). Accuracy is the tests': **`aContinuousRectDrawsItsCurve` holds 3 levels (0.012 px) on 8 cases including 520x520 r 256, 600x520 r 230 and the 400x300 r 150 capsule**, the border test on three (r, w) pairs, and every element test.
- **The target (1.5x on both) is met on `big` (1.49x) and not on `small` (2.46x).** `small` is a circle-sized rect: every fragment of every rect is within a pixel of a corner, so the whole shape pays the closest-point code and there is nothing for a gate to skip; what is left is 3 seed evaluations, 3 steps of (point, tangent) and the joint tests, against the circular one's single `length`. Measured and not kept: tightening the gate to `0.015 r` and returning the straight side's distance past the reach (`q.x >= ex`) read no better on a noisy machine (an OrbStack container held 200 % of the CPU for part of the session; the figures above are from quiet runs, three agreeing to 0.05 %), and the all-cubics-refine-best variant of the first round was inaccurate. **Best accurate number: 4.481 / 0.855 ms.** Not tried: a closed-form seed for the flat cubics, or Newton on the corner's chord parameter; the circular kind's 0.347 ms is a floor no search reaches.

## 7. Parity

- **SDL over the shadercross MSL** (`Replay --portable`, SDL Metal driver, Apple M6): frames 0-21 **0 differing pixels, max channel delta 0** (frame 21: 15 rects in 3 runs, 2 transforms, 1 backdrop; the draw-order control detected; re-run after the fragment-entry and distance change, same result).
- **`PortableReplay` on SDL Metal**: 22 fixtures, every frame 0 px, max delta 0.
- **llvmpipe Vulkan** (the `metalui-portable` image from `git archive HEAD`, llvmpipe LLVM 20.1.2): all 22 fixtures within tolerance. **Frame 21: outside sprites 228 px, max delta 1 (limit 1); inside backdrop quads 8448 px, max delta 1 (limit 3); inside glyph and image quads 0 px.** Frames 0-20 as before the change (max delta 1 outside, 3 inside).
- Not run: Direct3D 12 (Windows CI is the judge).

## 8. Carried: run 2

- the clip stack's masks will need `mask_coverage` continuous in **`rect_fragment` and every other fragment**, which is outside the base-identical `rect_fragment` this run keeps: decide then whether the mask helper change (a sign test per helper) is allowed to touch kind 0's shader.

- the clip stack: `ShapeGeometry.clip` for continuous (negated mask radii), `pushClip`, `Frame.intersect`/`clipsCross` on the continuous extent, the 19 `activeClipRadii` readers and every `max(0, ...)`, `mask_coverage`/`mask_coverage_scaled`/the transform outer mask in both shaders, `aContinuousClipCutsItsCurve` (rect, image and glyph content arms);
- multi-member glass (`GlassMember` radii sign, `glass_member_sdf`/`glassMemberSDF`); `GlassReference` (the CPU twin) still draws kind 2 circular;
- the ledger for run 1 is done (divergence 90 narrowed; decisions, shards, human checks `CC`, inventory rows, `api-overview.md`, `migration.md`, README, `Tasks.md`, CLAUDE.md/AGENTS.md); run 2 retires 90.
- unmeasured: built-in control looks (a `Button`'s, a text field's corner) are not measurable through `ImageRenderer`; note, no row.

## 9. Verbatim summary lines (after the fragment-entry and distance change; head is this commit)

`swift package clean` first (the new stored property of `Renderer` left a stale incremental build that failed two `Ellipse` clip tests until cleaned), `swift build --build-system native --build-tests`, then:

- `swift test --build-system native --no-parallel --skip-build`: `✔ Test run with 5404 tests in 14 suites passed after 313.189 seconds.` and `FR-J no-argument frame: succeeded=true deprecations=2`.
- `METALUI_VERIFY_RETAINED=1` the same: `✔ Test run with 5404 tests in 14 suites passed after 293.619 seconds.`
- Portable Docker (`git archive HEAD`, `metalui-portable`): MetalUIPathTests 53, MetalUILayoutTests 286, MetalUICoreTests 154, MetalUICrossPlatformTests 24, all passed; `PortableReplay --driver vulkan --expect 22`: `SDL GPU driver: vulkan; fixtures: 22`, `PASS`, frame 21 outside sprites 228 px max Δ1 (limit 1), backdrop quads 8448 px max Δ1 (limit 3).
- `Backends/SDL` filter `ReplayFixture|SDLGroup|SDLClipMask|SDLTextGradient|ShaderABI|ShaderSlot`: `✔ Test run with 55 tests in 0 suites passed after 0.933 seconds.`; `PortableReplay ../../Experiments/SDLGPU/fixtures --expect 22` on SDL Metal: 22 fixtures, `PASS` (frame 21: 3 runs).
- `Replay --portable --record`: frames 0-21 all `differing pixels=0, max channel delta=0`, `PASS`; `Replay` (no `--portable`, the adapted MSL, frames 0-8): `PASS`.
- closeout scripts: no output.
