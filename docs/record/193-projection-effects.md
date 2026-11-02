# 193 - 3D render effects (`PJ-A`..`PJ-K`)

2026-11-02, branch `feat/projection-effects` from master `5c47e0d8`; round-3 item R3-10 item 6. Rulings: `docs/superpowers/2026-11-02-projection-effects-decisions.md`. Rules in
`docs/rules/drawing.md`, `retained.md` and `input-focus.md`. **Partial: paint (`PJ-G`) is not built**; see section 5.

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

`ProjectionEffectTests.swift` (25 tests) and the updated `RenderEffectCompileGuards` guard. Mutation table: see the end of this record.

## 5. Not built, and why

The pinned `shadercross` (`1ff05bec`, `docs/packaging.md` 4a) is not installed here (no `shadercross`, `dxc`, `libSDL3_shadercross` on the machine or in the Docker images), and the SDL
shader blobs and `SOURCE.sha256` cannot be rebuilt without it. A source edit with stale blobs would fail `verifyingSources`, so nothing of the GPU side was committed: the 80-byte
record (`MetalUIShaderTypes.h`), `shaders.metal`, `replay.hlsl`, `SDLBridge` stride, replay fixture v6, the blobs, the parity frame 15 and the SDL tests; the CPU leaf scopes
(divergences 1065-1067, 1069); the demo strip; tests 18, 19, 21-29 and 33 of the plan; the 106 and 109 amendments. Until then a projective scope paints nothing (`PJ-STEP4` in
`paintWithDeviceMap`).

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
