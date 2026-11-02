# 193 - 3D render effects (`PJ-A`..`PJ-K`)

2026-11-02, branch `feat/projection-effects` from master `5c47e0d8`; round-3 item R3-10 item 6. Rulings: `docs/superpowers/2026-11-02-projection-effects-decisions.md`. Rules in
`docs/rules/drawing.md`, `retained.md` and `input-focus.md`. Built through the GPU (80-byte record, both shader backends, rebuilt SDL blobs, parity frame 15).

## 1. What was there

Render effects were affine (`Affine2D` through prepaint, paint and the 64-byte `MUITransform`); `transformEffect`, `projectionEffect`, `rotation3DEffect` were documented absences
(`GX-A`).

## 2. The probe

`docs/probes/swiftui-projection-effects.swift`, compiled, two runs byte-identical (ink boxes at scale 1). It reproduces the plan's measurements: 45 degrees about y on 200 x 100
(near edge x -9 and 154 tall, far edge 76 tall; 100 x 200 the same eye distance), perspective 0 orthographic, negative perspective the negated angle, z axis equals `rotationEffect`,
axis normalised, `anchorZ` not added back with the exact-zero quirk, a corner behind the eye draws nothing (`m13` -0.01; 60 degrees at 2.5 nothing, 2.2 draws), nested effects compose,
the row-vector `m13`/`m33`/`m31` arms, `transformEffect` in local coordinates, layout unaffected.

## 3. Design (built)

`Homography2D` and the carrier type changes (`PJ-A`), `RenderEffectSpec.rotation3D`/`.projection`, `ProjectionTransform`, three modifiers in both vocabularies, hit testing, bounding boxes
for geometry and accessibility, right-to-left conjugation, animation, retained refusal `effectProjective`.

## 4. Tests

`ProjectionEffectTests.swift` (25 tests), `ProjectionPaintTests.swift` (8), `ProjectivePrimitiveTests.swift` (5, Metal pixels), two SDL tests, the ABI pins, and the updated `RenderEffectCompileGuards` guard. Mutation table: see the end of this record.

## 5. The GPU side

The pinned shadercross was built from source at `1ff05bec` (outside the repo, `~/Developer/tools/shadercross`, 1303 ninja steps) and first compiled HEAD's `replay.hlsl` to byte-identical blobs. Then: `MUITransform` 64 to 80 bytes (`MetalUIShaderTypes.h`; a compatibility `init` without lane 4 keeps every affine call site), `shaders.metal` and `replay.hlsl` projective branches (`projective_w/scale/screen/fringe/clip` and their HLSL twins; rect, glyph and image stages; backdrops never get one), `SDLBridge` stride, fixture version 6 (2-5 load), `Experiments/SDLGPU` parity frame 15 and `--expect 16` (two places in `.github/workflows/sdl-gpu-linux.yml`), blobs and `SOURCE.sha256`, `transform_abi_probe` lane 4. Measured: frame 15 on macOS, Metal against SDL over MSL: 0 differing pixels. Not run here: Linux Vulkan and Windows D3D12 (CI); those replay the SPIR-V and DXIL the same compile produced.

CPU side: the scope applies the homography, drops primitives behind the eye, degrades backdrops, drops projective leaves from shadow and blur scopes, rasterises CPU images in creation space and inserts them with the record. The `PJ-STEP4` gate is gone.

## 6. Mutation table

Each mutation applied to `Sources/MetalUI/`, the filtered new tests run, the file reverted. Reddened tests (names only):

| Mutation (spelling) | Reddened |
|---|---|
| `Homography2D.rotation3D`: `let extent = max(...)` to `min(...)` | `aPositiveXTurnBringsTheBottomForward`, `anchorZShiftsThePlaneAndIsNotAddedBack`, `anyCornerBehindTheEyeDrawsNothing`, `nestedProjectiveEffectsComposeAsFlattenedMaps`, `rotation3DEffectMatchesTheMeasuredPerspective`, both geometry tests |
| same: `p / extent` to `p` | the above plus `aPositiveYTurn...`, `perspectiveZero...`, `theAccessibilityFrameUnder...`, `theAxisIsNormalised...` |
| same: `sinCos(theta)` to `sinCos(-theta)` (the Rodrigues sign) | `aPositiveYTurn...`, `aPositiveXTurn...`, `aProjectedHitbox...`, `aZAxisRotation3DIsRotationEffect`, `nestedProjective...`, `rotation3DEffectMatches...`, both geometry tests |
| same: `r01 = ... - uz * s` to `+` (transpose of the z part) | `aZAxisRotation3DIsRotationEffect` |
| same: drop `r22 * anchorZ * k` from `i` | `anchorZShiftsThePlaneAndIsNotAddedBack` |
| same: delete `radians != 0` | `anExactlyZeroAngleIsIdentity` |
| same: skip the axis normalisation | `theAxisIsNormalisedAndAZeroAxisIsIdentity` |
| same: `perspective == 0` returns identity; drop `theta = -theta` for a negative one | `perspectiveZeroIsOrthographicAndNegativeMirrorsTheAngle` (each) |
| `ProjectionTransform.homography` transposed | `projectionEffectReadsRowVectorsWithTheWColumn`, `rightToLeftConjugates...`, `transformEffectAppliesInCoreGraphicsOrder...`, `anyCornerBehind...`, `aPointBehindTheEyeNeverHits` |
| `RenderEffectSpec.map`: skip `about(origin)` | `transformEffectAppliesInCoreGraphicsOrderLocalToTheView` |
| `isInFront`: test only the centre | `anyCornerBehindTheEyeDrawsNothing` |
| `mirroredSpec`: `.rotation3D` returns `self`; `reflected(aboutX:)` dropped for a projection | `rightToLeftConjugatesEveryProjectiveEffect` (each) |
| `requestNativeLayout`: `.rotation3DEffect` gets a padding node | `rotation3DEffectChangesPaintAndNotLayout`, `theAccessibilityFrameUnder...`, `theGeometryFrameReachesTheCallbackProjected` |
| `concatenating`: drop `r.2 * inner.g` | `aProjectedHitbox...`, `aProjectiveEffectsPrepaintVector...`, `anAffineHomography...`, `anyCornerBehind...`, `projectionEffectReads...`, accessibility and geometry-callback tests |
| `apply`: drop the divide by `w` | 14 tests incl. `aProjectedHitboxIsHitWhereItIsDrawn` |
| `apply`: drop `guard w > 0 else { return nil }` | `aPointBehindTheEyeNeverHits` |
| `corners`: no `apply` (unprojected box) | both geometry tests, `theAccessibilityFrameUnder...`, `anyCornerBehind...` |
| `numbers`: `.projection` returns `[p.m11]` | `rotation3DEffectAnimatesEightNumbersAndProjectionSnaps` |
| `prepaintExtras()`: write `[0, 0, 1]` for the composed row | `aProjectiveEffectsPrepaintVectorCarriesItsBottomRows` |
| `effectScopeDiff`: drop the projective flag branch | `aProjectiveScopeInTheAmbientKeyRefusesByNameAndAnEqualOneIsNoDiff` |
| `indirect` removed from `rotation3DEffect` | **nothing: equivalent** (`LR-X`): the payload is 64 bytes, under the enum's 81 set by an existing case, so `theLayoutModifierKeepsItsSize` (pinned at 81) holds either way; it is a ceiling pin |

Not mutated (no test yet; belong to the deferred GPU work): plan tests 13, 18, 19, 21-29, 33. `aClipInsideAProjectiveEffectProjectsAndOneOutsideStays` (13) needs the projective clip split and is deferred with paint.

## 7. Counts (2026-11-02, `feat/projection-effects`)

`swift package clean`, `swift build --build-system native --build-tests`, `swift test --build-system native --no-parallel` unfiltered: **root 4948 tests in 14 suites passed, 0 failures**
(the 25 new tests included); `FR-J no-argument frame: succeeded=true`; the render-effect spellings guard ran (`GX-H spellings: succeeded=true ... Rotation3D` refused). `Backends/SDL`
builds (`swift build $(python3 scripts/fetch-accesskit.py --print-flags)`); its tests were not run (no SDL shader or fixture change was made).

Added with the GPU work (Metal, `ProjectivePrimitiveTests`; Swift, `ProjectionPaintTests`; SDL, `ReplayFixtureTests` and `SDLWindowRendererTests`):

| Mutation (spelling) | Reddened |
|---|---|
| `shaders.metal` `projective_clip`: `W` written as `1.0` | `aProjectedRectCoversItsTrapezoidAndNotItsBounds`, `aProjectedEdgeAntialiasesOverOneScreenPixelAtBothDepths`, `aProjectedImageSamplesPerspectiveCorrect`, `theOuterMaskUnderAProjectionIsTestedAtTheScreenPoint`, `aForcedProjectiveIdentityRowMatchesTheAffineBranch` |
| `projective_scale` returns `t.pixelScale` | `aProjectedEdgeAntialiasesOverOneScreenPixelAtBothDepths` |
| `[[center_no_perspective]]` on `ImageVertexOut.uv` | `aProjectedImageSamplesPerspectiveCorrect` |
| `rect_fragment` reads `in.screenPosition` for the outer mask | `theOuterMaskUnderAProjectionIsTestedAtTheScreenPoint` |
| `projective_scale`: `w * w` for `w * w * w` | `aForcedProjectiveIdentityRowMatchesTheAffineBranch`, `aProjectedEdgeAntialiasesOverOneScreenPixelAtBothDepths` |
| `SDLBridge.c` `TRANSFORM_STRIDE` 64 | `aProjectedFrameIsTheReplayPathsFrame`, `aTransformedFrameIsTheReplayPathsFrame` |
| fixture: widen a version-5 record with 0xFF | `aVersionFiveFixtureWidensItsTransformsWithAnAffineTail` |
| fixture: read a version-5 table at the new stride | `aVersionFiveFixtureWidensItsTransformsWithAnAffineTail`, `theFixtureStrideIs256AndVersion4Widens`, `theFixtureVersionIsSixAndOldVersionsStillLoad` |
| `replay.hlsl` `projectiveScale`: `w * w` (blobs recompiled to a temp directory, `REPLAY_SHADERS`) | Replay frame 15: `differing pixels=1411, max channel delta=26`, "Parity failed" (frame 7: 0) |
| `PrimitiveTransform.record`: `det3` written for an affine record | `anAffineRecordsTailIsZero` |
| `pathImage`: rasterise under the effect's affine part | `anAnimatingFlipRasterizesNothingAfterTheFirstFrame` |
| `processScopes` shadow arm casts from every leaf | `aShadowOutsideAProjectiveEffectCastsNothingFromIt` |
| `processScopes`: skip the backdrop degrade | `aMaterialUnderAProjectiveEffectDrawsItsFlatTint` |
| `RenderEffect.apply`: drop both `isInFront` guards | `aPrimitiveBehindTheEyeIsNotEmitted` |
| `paintWithDeviceMap`: outer mask made 100000 wide; or an inner rect's content mask replaced by the outer one | `aClipInsideAProjectiveEffectProjectsAndOneOutsideStays` (each) |
| `looksProjectionStrip` without `@inline(never)` | **not measurable here**: the overflow shows only on `swift:6.4-noble` (`CI-AI`); the test passes on macOS either way |
