# 60 — Shapes and rendering (plan task 11, part 2)

Branch `feat/shapes-and-rendering` from `ff2ae92` (part 1's tip, record §59).
Spec `docs/superpowers/specs/2026-09-28-shapes-and-rendering-design.md`;
rulings `TE-AC` onward in `docs/superpowers/2026-09-28-text-semantics-decisions.md`
(part 1's doc, same prefix); probe `docs/probes/swiftui-shapes-and-rendering.swift`.

## §1 Design (2026-09-29)

**Baseline re-taken at `ff2ae92`** in this worktree: `swift build
--build-system native --build-tests` 0 `error:`, the one SwiftPM deprecation
`warning:`; unfiltered `swift test --build-system native --no-parallel` →
`Test run with 1706 tests in 3 suites passed after 113.595 seconds`, the
`FR-J no-argument frame: succeeded=` line present. 105 guards, 0 goldens, 65
live divergences, next label 90.

**Probe.** `swiftui-shapes-and-rendering.swift`: revision 1 (68 lines, groups
P, S, F, K, C, O, I) was written by an interrupted first design pass and found
uncommitted; this pass re-ran it (stdout byte-identical to its header), then
added revision 2's separating arms — A1–A4 (`aspectRatio(nil)` on a
non-image), C8 (`clipShape` and layout), I11 (`.medium`), I12 (premultiplied
compositing), K11/K12 (a stroke wider than twice the radius) — and re-ran the
whole: compiled twice, interpreted once, byte-identical, 77 lines, screen
locked (`CGSSessionScreenIsLocked = 1`, `displayAsleep main: 1`). Readings
that decided rulings: K8 (an ellipse's `strokeBorder` is the inset ellipse's
stroke, 518 px from a concentric hole → exact distance in the shader, `TE-AE`);
K11/K12 (the outer corner rule, `TE-AI`); S3/C4 (continuous is the default and
differs from circular by 196 px → divergence 90); I8/I11 (only `.high` differs
from bilinear → divergence 93); A1–A4 (the nil ratio is the child's nil×nil
answer, `TE-AM`).

**Renderer inventory** (spec §2): `MUIRect` (circular rounded-rect SDF,
inside border, rounded mask, an unused `_reserved` word), `MUIGlyph` (R8
sprite); the SDL renderer draws the same bytes through `replay.hlsl`, its
compiled stages checked in and hash-checked in CI; parity is
`Experiments/SDLGPU`'s `Replay --portable --record` (Metal vs SDL-Metal live)
plus `PortableReplay --expect 6` and `DemoCapture` on Linux/Windows. Decided:
an ellipse kind in `_reserved` (stride unchanged) and an image primitive with
textures carried by the `Scene` (`WindowRenderer`'s signature unchanged),
frame 6 added to the parity set; every other effect a documented constraint
(`TE-AD`, spec §9).

**Collection** (`TE-AC`): `TE-O`'s table plus a re-grep; dispositions in spec
§3. Divergences planned: **90–93 added** (continuous corners drawn circular;
an ellipse clip traps; crossing rounded clips intersect as the square box;
`.high` drawn bilinear), **64 retired** (`UnitPoint` grid anchor), **47 kept**
(legacy `.cornerRadius` stays paint-only: making it clip would move hit
testing). Live count 65 → 68 if every lane lands.

**Lanes** (spec §8): 1 renderer (both), 2 shapes/fill/stroke/clip/backgrounds,
3 image/`aspectRatio(nil)`/grid anchor; run in order. Lock probe at design
time: locked, so the real-window capture is owed.

## §2 Critic round (2026-09-29)

Attacked the committed design (`08499e0`); ruling `TE-AQ`, next unused
`TE-AR`. **Re-runs**: the probe's revision 2 compiled and run unchanged, all
77 lines byte-identical to its header; `swiftui-grid.swift` compiled `-O`,
GL14's line byte-identical (the design had only re-read it). **O4 was not
separating** (white on white): revision 3 adds O6 over a red canvas with a
blue control — `background(in:)` paints (white, 5968 px), so `TE-AK`'s token
fill stands and its evidence is amended as an erratum; revision 3 re-ran
compiled twice and interpreted once, byte-identical, 78 lines. Lock probe
00:31 PDT: `CGSSessionScreenIsLocked = 1`, `displayAsleep main: 1` — the
real-window capture stays owed.

**Fixed in the spec** (`TE-AQ` items 1–12): `Shape` refines
`ProposalElement, Sendable` with default phase implementations (a
`Shape: Element` outside conformer could neither compile from `geometry(in:)`
alone nor sit in an `HStack`); `Rectangle.color` becomes `ColorToken?`, a
ruled public break with its migration; the legacy `clipShape` is
`<S: Shape & Hashable>` because `Decoration` is `Sendable, Hashable`; a clip's
hitbox clipping is stated as MetalUI's rule (square, `activeClip`), owner
plan task 12, no number (unmeasured); the ellipse distance is the trig-free
three-iteration method on both shader languages (loose transcendental
precision on Vulkan/D3D); the `MUIRect._reserved` rename's memberwise call
sites are listed for lane 1; `Image`'s `scale: Float` and missing
`orientation:` ruled; three stale "task 11" source comments assigned to lanes
2 and 3; 3.10/2.20 are single `@Test`s; the new `intersect` case runs after
the existing two. **Rejected**: splitting lane 1, replacing `intersect`'s
case 2, numbering an unmeasured hit-testing divergence (reasons in `TE-AQ`).

## §3 Lane 1 — the renderer: the ellipse kind and the image primitive, on Metal and SDL (2026-09-29)

Commits: red `afa7a98`, implementation `7e61deb`, this record and `TE-AR`
after them. Ruling **`TE-AR`** (next unused `TE-AS`) records what landed
differently from the design; the spec is amended in the same commit.

**Red first** (`afa7a98`, against a skeleton that compiled and drew, sorted
and cached nothing): unfiltered suite `Test run with 1718 tests in 3 suites
failed … with 38 issues` — exactly the twelve new tests, 1718 = 1706 + 12.
One line per test (first failure):

| # | test | red line |
|---|---|---|
| 1.1 | `anEllipseFillsItsInscribedEllipseAndNotTheCapsule` | `EllipsePrimitiveTests.swift:54` `pixel(ellipse, 10, 10, …).a == 0` |
| 1.2 | `anEllipseBorderIsTheStrokeOfTheInsetEllipse` | first draft at 100×60/10: `:100` `#require(separating)` — no separating pixel exists there (`TE-AR` item 3); at 120×40/16: `:105` `p.r > 200 && p.g < 50` |
| 1.3 | `aSceneHoldingOnlyAnImageIsNotEmpty` | `SceneTests.swift:64` `!s.isEmpty` |
| 1.4 | `imageRunsBreakWhereTheTextureChanges` | `DrawListTests.swift:249` `runs() == expected` |
| 1.5 | `anImageSamplesBilinearlyWithClampedEdges` | `ImagePrimitiveTests.swift:60`, all twelve x's |
| 1.6 | `aNearestImageReadsTheTexelUnderEachPixel` | `:71`/`:72`, all six x's |
| 1.7 | `aTranslucentImageCompositesPremultipliedSourceOver` | `:89` the composite |
| 1.8 | `anImageUnderARoundedMaskIsClippedByIt` | `:101` the centre pixel |
| 1.9 | `aTextureTheSceneNoLongerReferencesIsReleased` | `:117` `cachedImageTextureIdentities == [a]` (nine issues) |
| 1.10 | `metalAndSwiftAgreeOnTheImageStructAndTheShapeField` | `ShaderABITests.swift:109` `makeFunction(name: "image_abi_probe")` |
| 1.11 | `drawImageEmitsOneImageAtTheActiveOffsetClipOpacityAndLayer` | `PaintPrimitiveTests.swift:42` `scene.images.count == 2` |
| 1.12 | `fillCarriesTheEllipseShapeKind` | `:67` `rects[0].shape == 1` |
| S1.1 | `aVersionTwoFixtureRoundTripsImagesAndTextures` (`Backends/SDL`) | `ReplayFixtureTests.swift:209` `invalid fixture: run 0 image 0+1 exceeds 0 records`; the three re-spelled v2 literals (`encodingIsLittleEndianWithMagicAndVersion`, `anUnknownRunKindIsRejected`, `badMagicAndVersionAreRejected`) red with it |
| S1.2 | `anImageFrameIsTheReplayPathsFrame`, `imageTexturesPersistAndAreReleasedWhenAbsent` (`Backends/SDL`) | `SDLWindowRendererTests.swift:93` the nearest image's red texel; `:107` the cache |

**Implementation** (`7e61deb`): `ellipse_sdf`/`ellipseSDF` (the trig-free
three-iteration method, identical statements in MSL and HLSL) and the band
in `rect_fragment`/`replay.hlsl`; `image_vertex`/`image_fragment` and
`IMAGE_STAGE`; `Renderer`'s image pipeline and identity cache (updated before
the empty-scene return); `Scene`'s image arrays, run breaks and `isEmpty`;
`Frame.drawImage`/`fill(shape:)`; the SDL bridge's image pipeline, texture
create/release and exhaustive kind switch; `SDLWindowRenderer`'s cache;
`ReplayFixture` version 2 and `spriteMask()`; `compile-shaders.py`'s six
stages (SDL3_shadercross 3.0.0, a scratchpad copy; reproducibility checked
first — the unchanged `glyph.fragment` recompiled byte-identical in SPIR-V,
MSL and DXIL — and after the edit only `rect.fragment.*` and the new
`image.*` changed); `Experiments/SDLGPU` frame 6; CI `--expect 7` and a
`Sources/MetalUIRender/**` trigger.

**One retained test's literal moved (T row, `TE-AR` item 10)**:
`sceneSideTablesArePlainIntArraysThatKeepCapacityAcrossClear` — four `[Int]`
side tables → six, and it emits images so their capacity is read. It went red
(`SceneFinalizeIdentityTests.swift:199` `intArrays.count == 4`) on the first
clean run of the implementation and is the only retained root test whose
answer changed. No `@Test` removed. `Backends/SDL` re-spellings for version 2
are listed in `TE-AR` item 10. `git grep -n _reserved` (Swift, C header,
Metal; HarfBuzz excluded) now reads 14 lines: `MUIGlyph`'s field and its
memberwise calls, and the header comment naming the old word — no rect site.

**Counts**, after `swift package clean` (`Scene` gained stored arrays and
`MUIRect` a renamed field across a module boundary — a stale build had shown
an impossible `textures.count` mid-lane, exactly CLAUDE.md's hazard):
`swift build --build-system native --build-tests` 0 `error:`, the one
SwiftPM deprecation `warning:`; unfiltered `swift test --build-system native
--no-parallel` → **`Test run with 1718 tests in 3 suites passed after 108.016
seconds`**, the `FR-J no-argument frame: succeeded=` line present; `swift
build --build-tests` (default build system) 0 `error:`/`warning:`. **1718 =
1706 + 12.** Guards unmoved (lane 1 adds none, **105**). 0 goldens.
`theLegacyEngineSymbolsAreAbsentFromTheTestProcess`,
`everyProductionTreeBuildsOnAOneMegabyteThread` and
`theDemoFrameMatchesTheValuesRecordedOnMacOS` green, `Expected.swift`
unedited (`git diff ff2ae92 -- Tests/MetalUICrossPlatformTests` empty).
`MetalUILayout` imports only `MetalUICore`. `Backends/SDL`
(`PKG_CONFIG_PATH=.accesskit`): **22 + 25** on macOS (21 + 23 at `ff2ae92`);
in a `swift:6.4-noble` aarch64 container (`metalui-portable-ax`) **22 + 24**
on llvmpipe, and the root package builds there with 0 `error:`/`warning:`.

**Pixels**: `docs/probes/demo-pixels/compare.sh <scratch> ff2ae92 7e61deb` —
controls as recorded since stage 9 (light vs dark 1048576, default vs modal
1031003, default vs animation 454895, f0 vs f3 0, chrome pair 0, distinct 544
and 216, prod default vs modal 491221, prod distinct 529, indicator rects 0);
**0 differing, scene identical, in all fourteen**.

**Parity (P1)**: `swift run Replay --portable --record <dir>` in
`Experiments/SDLGPU` — 7 frames, every one 0 differing pixels on SDL's Metal
backend (frame 6: 7 rects, 4 images, 5 runs), draw-order control detected
(283 px); the adapted-native-MSL path (`swift run Replay`) likewise 7 frames
at 0. `PortableReplay <dir> --expect 7` PASS on Metal (all 0) and, in the
container on **Mesa llvmpipe Vulkan**, PASS: frames 0–5 as before (max Δ1
outside, ≤ Δ3 inside glyphs), frame 6 1038 px Δ1 outside sprites, 37 819 px
Δ2 inside image quads — the ellipse kind held to one step on a second
backend. `DemoCapture` PASS on macOS (scene byte-for-byte, 0 px). **The first
frame-6 draft failed llvmpipe** (55 px Δ97 in the nearest image) because its
texel boundary sat on a pixel centre (`TE-AR` item 5); moved a quarter pixel,
re-recorded, re-run on both. Windows (D3D12) re-confirms on push.
**Positive controls** (HLSL mutated in a scratchpad copy, compiled with the
same `shadercross`, `PortableReplay --shaders`): the image stage forced to
nearest → frame 6 FAIL, 42 948 px Δ144 inside image quads, frames 0–5 still
0; the ellipse branch dropped → frame 6 FAIL, 13 882 px Δ231 outside sprites,
frames 0–5 still 0.

**Mutations** (each on `7e61deb`, applied to one spelling from a copy,
build, whole unfiltered suite, `git checkout -- Sources`, `git status
--short` read clean of source after each — only this record's uncommitted
docs showed):

| id | mutation (spelling) | reddened (issues) |
|---|---|---|
| M1a | `rect_fragment`: `if (r.shape == MUIShapeEllipse)` → `if (false)` | `anEllipseFillsItsInscribedEllipseAndNotTheCapsule` (1), `anEllipseBorderIsTheStrokeOfTheInsetEllipse` (1) |
| M1b | the band as the concentric hole: outer `ellipse_sdf(p, halfSize)`, inner `ellipse_sdf(p, halfSize − w)` | `anEllipseBorderIsTheStrokeOfTheInsetEllipse` (1) |
| M1c | `isEmpty` without `images.isEmpty` | `aSceneHoldingOnlyAnImageIsNotEmpty` (1), and every render test whose scene holds only images: `anImageSamplesBilinearlyWithClampedEdges` (12), `aNearestImageReadsTheTexelUnderEachPixel` (6), `anImageUnderARoundedMaskIsClippedByIt` (1), `aTextureTheSceneNoLongerReferencesIsReleased` (2) — 22 |
| M1d | `sameTexture = previous.texture == image.texture \|\| true` | `imageRunsBreakWhereTheTextureChanges` (2) |
| M1e | `image_sampler` `filter::linear` → `filter::nearest` | `anImageSamplesBilinearlyWithClampedEdges` (6: the six x's between the texel centres) |
| M1f | `image_fragment`: `if (m.filter == MUIImageFilterNearest)` → `if (false)` | `aNearestImageReadsTheTexelUnderEachPixel` (3: x 25, 49, 50 — the rest are clamped either way) |
| M1g | `ImageTexture(straightRGBA:)` copies instead of premultiplying | `aTranslucentImageCompositesPremultipliedSourceOver` (2) |
| M1h | `image_fragment`: `clip = 1.0` | `anImageUnderARoundedMaskIsClippedByIt` (2) |
| M1i | `Renderer`: `imageTextures.merge(kept)` (never evict) | `aTextureTheSceneNoLongerReferencesIsReleased` (3) |
| M1j | `image_abi_probe`: `out[13] = r.order` | `metalAndSwiftAgreeOnTheImageStructAndTheShapeField` (1) |
| M1k | `Frame.drawImage`: `opacity: 1` | `drawImageEmitsOneImageAtTheActiveOffsetClipOpacityAndLayer` (1) |
| M1l | `Frame.fill`: `shape:` dropped from the `MUIRect` init | `fillCarriesTheEllipseShapeKind` (1) |
| M1m | `ReplayFixture.encoded()`: texture count 0, no texture bytes (`Backends/SDL` suite) | `aVersionTwoFixtureRoundTripsImagesAndTextures` (1) |
| M1n | `SDLWindowRenderer`: `.image` → kind 0 (images drawn as rects) (`Backends/SDL` suite) | `anImageFrameIsTheReplayPathsFrame` (3), `imageTexturesPersistAndAreReleasedWhenAbsent` (1) |

Every mutation reddened the test the spec named for it; none reddened
nothing. M1e's log interleaved stdout and its summary line printed torn
(`…r` + `un with 1718 tests … failed … with 6 issues`); the six issue lines
are the count above.

**Real window**: lock probe 01:15 PDT — `CGSSessionScreenIsLocked = 1`,
`displayAsleep main: 1` — so `capture.sh` was not run; owed, as for tasks
8–11 part 1. Lane 1 touches no tree the demo builds (the fourteen read 0).

**Deferred / for later lanes**: lane 2 draws shapes through
`PaintPass.fill(…, shape:)` (the stroke over outset bounds is its business,
spec §5); lane 3's `ImageBitmap` can use `ImageTexture(straightRGBA:)`
(`TE-AR` item 2) and `PaintPass.drawImage`; a nearest image whose texel
boundary lands on a pixel centre is backend-dependent (`TE-AR` item 5, spec
§9), which lane 3's 3.8 need not avoid (it asserts the filter field, not
pixels).

## §4 Lane 2 — `Shape`, the built-ins, fill/stroke, clipping, backgrounds in a shape (2026-09-29)

Commits: red `c73ab50`, implementation `05d6ea0`, `TE-AS` and the spec's
amendments `6e83b19`, the verifier's fix round `a420975` (tests) with `TE-AT`
and this section after it. Rulings **`TE-AS`** (what landed differently from
the design) and **`TE-AT`** (the fix round); next unused `TE-AU`.

**Red first** (`c73ab50`, against a skeleton that compiled and drew): the
unfiltered suite read `Test run with 1743 tests in 3 suites failed … with 54
issues` — **20 of the 25 new tests red with 53 issues**, plus one retained
guard with 1 (the T row below). Green on arrival, each with a mutation that
reddens it (`TE-AS` item 9): 2.6, 2.14, 2.17, 2.21 and G2.1. One line per red
test (first failure; issues in brackets):

| # | test | red line |
|---|---|---|
| 2.1 | `everyBuiltInShapeAnswersItsProposalAndACircleTheSmallerSquare` (4) | `ShapeTests.swift:122` `kernelAnswers(Circle()) == circleAnswers` |
| 2.2 | `aCircleDrawsCentredInItsFrame` (5) | `ShapeTests.swift:139` `wide.rect == shapeBounds(20, 0, 60, 60)` |
| 2.3 | `aCornerRadiusClampsToHalfTheShorterSideAndANegativeOneIsZero` (5) | `ShapeTests.swift:159` RR(50)'s radii == 30 |
| 2.4 | `anEllipseEmitsTheEllipseKind` (1) | `ShapeTests.swift:182` kind == ellipse |
| 2.5 | `aBareShapeFillsWithTheForegroundStyle` (8) | `ShapeTests.swift:211` `colour(Rectangle()) == lightColour(.textPrimary)` |
| 2.7 | `aStrokeDrawsOverTheFill` (1) | `ShapeStrokeTests.swift:21` `rects.count == 2` |
| 2.8 | `aStrokeBorderIsInsideTheEdge` (1) | `ShapeStrokeTests.swift:35` `rects.count == 1` |
| 2.9 | `aStrokeRoundsItsOuterEdgeByHalfTheWidthOnlyOverACurve` (1) | `ShapeStrokeTests.swift:51` `rects.count == 1` |
| 2.10 | `aStrokeBorderWiderThanTwiceTheRadiusHasASquareOuterCorner` (1) | `ShapeStrokeTests.swift:73` `rr3.count == 1` |
| 2.11 | `aStrokeOfZeroOrNegativeWidthDrawsNothing` (1) | `ShapeStrokeTests.swift:86` the width-1 control |
| 2.12 | `aStrokeChangesNoLayoutAndDefaultsToOnePoint` (1) | `ShapeStrokeTests.swift:108` `stroke.count == 1` |
| 2.13 | `anEllipseStrokeIsTheEllipseBandOverTheOutsetBounds` (1) | `ShapeStrokeTests.swift:126` `border.count == 1` |
| 2.15 | `clipShapeClipsToTheShapesGeometry` (4) | `ClipShapeTests.swift:33` the circle's mask |
| 2.16 | `clippedAndCornerRadiusClipOnTheProposalPath` (2) | `ClipShapeTests.swift:67` the rounded mask |
| 2.18 | `aLegacyClipShapeClipsItsChildrenAndItsHitboxes` (2) | `ClipShapeTests.swift:128` the capsule mask |
| 2.19 | `clipShapeOfAnEllipseTrapsNamingDivergence91` (4) | `ClipShapeTests.swift:141` exit status success |
| 2.20 | `aRoundedClipContainedInARoundedClipKeepsItsRadii` (6) | `ClipShapeTests.swift:176` C6's radii 30 |
| 2.22 | `aShapeBackgroundOrOverlayTakesTheContentsSize` (3) | `ShapeTests.swift:268` O1's rect and radii |
| 2.23 | `backgroundInAShapeIsTheFilledShapeAndDefaultsToTheBackgroundToken` (1) | `ShapeTests.swift:318` the defaulted token |
| G2.2 | `theRectangleColorInitialiserIsDeprecatedTowardFill` (1) | `ShapeCompileGuards.swift:100` one deprecation line naming `fill` |
| T | `theLegacyAndProposalDecorationModifiersDoNotCollide` (1, retained) | `DecorationCompileGuards.swift:211` the fixtures agree |

**Counts** (`05d6ea0`, after `swift package clean` — `Rectangle` gained a
stored optional and `Decoration` a field, public types across a module
boundary): unfiltered `swift test --build-system native --no-parallel` →
`Test run with 1743 tests in 3 suites passed after 108.927 seconds`. **1743 =
1718 + 25**: 23 tests and 2 guards (`ShapeCompileGuards`, G2.1 and G2.2, both
whole-file `typecheckFile`; guards **105 → 107**). No `@Test` removed. 0
goldens. The fix round (`a420975`) adds 4 tests (2.13b, 2.15b, 2.18b, 2.18c)
and one arm in 2.20: **`Test run with 1747 tests in 3 suites passed after
108.478 seconds`**, the `FR-J no-argument frame: succeeded=` line present, 0
`error:`, the one SwiftPM deprecation `warning:` (0 `error:`/`warning:` under the default build system, `swift build --build-tests`). **1747 = 1743 + 4.**

**Retained tests.** One T row: `theLegacyAndProposalDecorationModifiersDoNotCollide`
re-answered for SwiftUI's proposal `.clipped()` (`TE-AS` item 7; red on the
skeleton at `DecorationCompileGuards.swift:211`; its re-spelled `crossed`
fixture reddens again under MG3b′). One re-spelling whose answer does not
move: `rectangleUsesSwiftUIShapeProposalSizing`
(`NativeLayoutIntegrationTests.swift:601`) moves from the deprecated
`Rectangle(color: .accent)` to `Rectangle().fill(.accent)` and asserts bounds
only (`TE-AS` item 8). **The `Rectangle()` census gives no other T row**: 79
spellings at `ff2ae92` — 5 in `Sources` comments, 38 in typecheck-guard
fixtures, 19 in `ElementGroupTrapTests`, 9 in `HitRegionTests` comments, 5 in
`ProposalModifierValidationTests`, 3 in `ScrollToTests` — none asserts a bare
`Rectangle()`'s painted colour (`TE-AS` item 8).

**Pixels**: `docs/probes/demo-pixels/compare.sh <scratch> ff2ae92 05d6ea0` —
controls as in §3 (light vs dark 1048576, default vs modal 1031003, default
vs animation 454895, f0 vs f3 0, chrome pair 0, distinct 544 and 216, prod
default vs modal 491221, prod distinct 529, indicator rects 0); **0 differing,
scene identical, in all fourteen**. The fix round's `Sources` diff is one doc
comment (`Frame.roundedRect(_:radii:liesInside:radii:)`), so the images stand.

**Mutations** (each on `05d6ea0` — the fix round's five on `a420975` — one
spelling applied from the working tree's committed copy by
`muts.py`/`muts-fix.py`, build, whole unfiltered suite, `git checkout --
Sources Tests`, `git status --short` read clean of source after each):

| id | mutation (spelling) | reddened (issues) |
|---|---|---|
| M2a | `Circle.sizeThatFits` renamed away (the default answers) | `everyBuiltInShapeAnswersItsProposalAndACircleTheSmallerSquare`, `aShapeBackgroundOrOverlayTakesTheContentsSize` (5) |
| M2v | `Circle.sizeThatFits` returns the proposal (10 for nil) first | the same two (5) — M2a's answer by another spelling (`TE-AS` item 6) |
| M2b | the circle's square at the rect's origin, not centred | `aCircleDrawsCentredInItsFrame`, `aRoundedClipContainedInARoundedClipKeepsItsRadii`, `clipShapeClipsToTheShapesGeometry` (8) |
| M2c | `ShapeGeometry`'s `clamped` returns the radius | `aCornerRadiusClampsToHalfTheShorterSideAndANegativeOneIsZero` (3) |
| M2d | `Ellipse`'s geometry a square-cornered rounded rectangle | `anEllipseEmitsTheEllipseKind`, `anEllipseStrokeIsTheEllipseBandOverTheOutsetBounds`, `clipShapeOfAnEllipseTrapsNamingDivergence91` (7) |
| M2e | the bare fill's default `.surface` | `aBareShapeFillsWithTheForegroundStyle` (3) |
| M2f | the environment's `foregroundStyle` read before the fill's token | `aBareShapeFillsWithTheForegroundStyle`, `aFillWinsOverTheForegroundStyle` (2) |
| M2g | `ShapeView`'s layers painted `reversed()` | `aStrokeDrawsOverTheFill` (2) |
| M2h | `strokeBorder` outset | `aStrokeBorderIsInsideTheEdge`, `aStrokeBorderWiderThanTwiceTheRadiusHasASquareOuterCorner`, `aStrokeChangesNoLayoutAndDefaultsToOnePoint`, `anEllipseStrokeIsTheEllipseBandOverTheOutsetBounds` (5) |
| M2i | the stroke's outer radius `r + w/2` even at r = 0 | `aStrokeDrawsOverTheFill`, `aStrokeRoundsItsOuterEdgeByHalfTheWidthOnlyOverACurve` (2) |
| M2j | `strokeBorder`'s outer radius always `r` | `aStrokeBorderWiderThanTwiceTheRadiusHasASquareOuterCorner` (1) |
| M2k | the `w > 0` guard dropped | `aStrokeOfZeroOrNegativeWidthDrawsNothing` (6) |
| M2l | every default `lineWidth` 0 (four spellings) | `aStrokeChangesNoLayoutAndDefaultsToOnePoint` (1) |
| M2m | an ellipse's stroke not outset | `anEllipseStrokeIsTheEllipseBandOverTheOutsetBounds` (1) |
| M2n | `RoundedCornerStyle` defaults `.circular` (two spellings) | `theContinuousStyleIsTheDefaultAndIsDrawnCircular` (2) |
| M2o | the proposal `clipShape` clips to the bounds with the geometry's radii (both halves) | `aRoundedClipContainedInARoundedClipKeepsItsRadii`, `clipShapeClipsToTheShapesGeometry` (6) |
| M2p | the proposal `cornerRadius` wraps `.opacity(1)` instead of a clip | `clippedAndCornerRadiusClipOnTheProposalPath` (3) |
| M2q | `.clipShape` registers a native frame | `clipShapeChangesNoLayout` (1) |
| M2r | the legacy prepaint clip reads `clipsContent` before the region | `aLegacyClipShapeClipsItsChildrenAndItsHitboxes` (1) |
| M2s | the ellipse trap returns a square region | `clipShapeOfAnEllipseTrapsNamingDivergence91` (4) |
| M2t | `Frame.intersect`'s containment case removed | `aRoundedClipContainedInARoundedClipKeepsItsRadii` (6) |
| M2u | the crossing case returns the inner radii | `aClipTouchingARoundedOutersEdgeFallsBackToSquareCorners`, `twoCrossingRoundedClipsIntersectAsTheSquareBox` (3) |
| M2w | `background(in:)`'s default token `.surface` | `backgroundInAShapeIsTheFilledShapeAndDefaultsToTheBackgroundToken` (1) |
| MG2a | `Shape`'s default `sizeThatFits` removed (built-ins keep one) | `anOutsideShapeNeedsOnlyItsGeometry` (1) |
| MG2a′ | `Shape` refines `Element`, not `ProposalElement` — each built-in re-declared `ProposalElement` and `ShapeView`'s three `S.LayoutState` spelled `ShapeLayout` so the package builds (the first spelling, without the last edit, **did not build**: `ShapeView.swift:75` cannot convert `ShapeLayout` to `S.LayoutState`) | `anOutsideShapeNeedsOnlyItsGeometry` (1: the `HStack` arm) |
| MG2b | the `init(color:)` deprecation dropped | `theRectangleColorInitialiserIsDeprecatedTowardFill` (1) |
| MG3b′ | `hoverBackground(_:)` declared on `ElementGroup` | `theLegacyAndProposalDecorationModifiersDoNotCollide` (1) |
| X1 | `Decoration.clipRegion(in:)` reads `clipsContent` first | at `05d6ea0` **none**; at `a420975` `aLegacyClipShapeWinsOverClipped` (2) |
| X2 | `roundedRect(…liesInside…)` without `+ 1e-4` | **none**, at both commits — the tolerance is defensive (`TE-AT` item 2) |
| X3 | `ClipShapeBox.==` returns `true` | at `05d6ea0` **none**; at `a420975` `aLegacyClipShapeComparesByItsConcreteShape` (2) |
| X7 | the proposal `.clipShape`'s `_prepaint` returns `inside()` | at `05d6ea0` **none**; at `a420975` `aProposalClipShapeCutsTheHitboxesInsideIt` (1) |
| X8 | the legacy paint clip reads `clipsContent` before the region | `aLegacyClipShapeClipsItsChildrenAndItsHitboxes` (1) |
| X9 | the container's radius always `topLeft` | at `05d6ea0` **none**; at `a420975` `aRoundedClipContainedInARoundedClipKeepsItsRadii` (2) |
| K10a | `rect_fragment`'s inner half-size `abs(halfSize − border)` | `aBorderWiderThanHalfTheShapeFillsIt` (1) |

M2a–MG3b′ and X1–X9 at `05d6ea0` were taken by the lane's verifier; the five
re-runs and K10a at `a420975` by the fix round. The five `05d6ea0` rows
reading none are the verifier's findings, each closed by a fix-round test
(`TE-AT` item 1) except X2 (item 2).

**Real window**: lock probe 04:03 PDT — `CGSSessionScreenIsLocked = 1`,
`displayAsleep main: 1` — so `capture.sh` was not run; owed, as in §3. Lane 2
touches no tree the demo builds (the fourteen read 0).
