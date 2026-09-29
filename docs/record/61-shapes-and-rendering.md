# 61 — Shapes and rendering (plan task 11, part 2)

*Written as §60 on `feat/shapes-and-rendering` from `ff2ae92` and renumbered
60→61 at its merge with `master` `0714528` (PR #31), because `master` had
already published §60 (`60-text-page-and-tab.md`, `TI-I`/`TI-J`) — the same
shape as the 24→25, 26→27, 30→38 and 53→59→60 renumberings. Every §60 this
branch wrote was swept to §61 in the merge; master's §60 citations name the
text-page record and stay. The merge's own close is §8 below.*

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

## §5 Lane 3 — `Image`, `aspectRatio(nil)`, the `UnitPoint` grid anchor (2026-09-29)

Commits: red `346c07d`, implementation `02f1e0f`, `TE-AU`, the spec's
amendments and this section after them. Ruling **`TE-AU`** (what landed
differently from the design); next unused `TE-AV`.

**Red first** (`346c07d`, against a skeleton that compiled: `ImageBitmap`
copying its bytes as given, `Image` answering its pixel size with
`resizable()` a no-op and one filter, a nil ratio read as 1, `scaledToFill`
mapped to `.fit`, the `UnitPoint` anchor rounded to the nearest nine-point):
the unfiltered suite read `Test run with 1762 tests in 3 suites failed after
108.424 seconds with 23 issues` — **13 of the 15 new tests red with 23
issues**, no retained test red. Green on arrival by design, each with a
mutation that reddens it below: 3.5 (a fixed child — the skeleton's ratio-1
node already answered its child's answer), G3.1 (the inverted guard — the
skeleton offered the overload; the retired guard it replaces would have been
red) and G3.2. One line per red test (first failure; issues in brackets):

| # | test | red line |
|---|---|---|
| 3.1 | `anImageAnswersItsPointSizeAtEveryProposal` (1) | `ImageTests.swift:63` the scale-2 image == 40×20 ×5 |
| 3.2 | `aResizableImageAnswersItsProposal` (2) | `ImageTests.swift:74` I2's row |
| 3.3 | `anImagePaintsOneTexturedQuadOverItsBoundsAtTheScale` (1) | `ImageTests.swift:91` bounds == (60, 40, 80, 40) |
| 3.4 | `aspectRatioWithNoRatioTakesTheChildsIdealRatio` (4) | `AspectRatioIdealTests.swift:55` A3's row |
| 3.6 | `scaledToFitAndScaledToFillAreAspectRatioNil` (2) | `ImageTests.swift:130` fit == (0, 5, 100, 50) |
| 3.7 | `aFillImageOverflowsItsFrameUnlessClipped` (1) | `ImageTests.swift:149` the fill image's bounds (the skeleton's ratio-1 fill) |
| 3.8 | `interpolationNoneIsNearestAndEveryOtherLinear` (1) | `ImageTests.swift:170` `.none` → filter 1 |
| 3.9 | `anImageBitmapPremultipliesStraightAlpha` (1) | `ImageTests.swift:186` (100, 50, 25, 128) |
| 3.10 | `anImageBitmapOfTheWrongByteCountOrAZeroSideTraps` (2) | `ImageTests.swift:201` stderr names `ImageBitmap` (the child died in `ImageTexture`) |
| 3.10b | `anImageOfANonPositiveOrNonFiniteScaleTraps` (4) | `ImageTests.swift:217` exit status success |
| 3.11 | `anImageBitmapDecodesAPNGThroughImageIO` (1) | `ImageTests.swift:263` the PNG decodes (nil) |
| 3.12 | `aGridCellAnchorTakesAUnitPoint` (1) | `GridElementTests.swift:1290` GL14's a at (10, 20) |
| 3.12b | `aNonFiniteGridCellAnchorTraps` (2) | `GridElementTests.swift:1304` exit status success |

**Counts** (`02f1e0f`, after `swift package clean` — `LayoutTree`'s
anchor dictionary changed type, `GridCellAttribute` gained a case,
`NativeNode.aspectRatio`'s payload became optional): unfiltered `swift test
--build-system native --no-parallel` → **`Test run with 1762 tests in 3 suites
passed after 108.568 seconds`**, the `FR-J no-argument frame: succeeded=` line
present, 0 `error:`, the one SwiftPM deprecation `warning:`; the default build
system (`swift build --build-tests`) 0 `error:`/`warning:`. **1762 = 1747 +
15**: 14 tests (the spec's twelve plus 3.10b and 3.12b, `TE-AU` item 2) and 1
guard (`ImageCompileGuards`' G3.2, whole-file `typecheckFile`; guards **107 →
108**; G3.1 renames `GridCompileGuards`' G4 and adds none). One test lands in
`MetalUILayoutTests` (3.4, portable), so Linux and Windows CI's figure for that
target moves by one. No `@Test` removed. 0 goldens.

**Retained tests.** One T row, by ruling (`TE-AN`, `TE-AU` item 5): guard
`aGridCellAnchorIsNinePoint` → `aGridCellAnchorTakesAUnitPointAndTheNinePointSpellingsStillResolve`,
its answer inverted (a fractional anchor compiled nowhere; it now compiles,
and the nine-point leading-dot spellings still resolve). Three re-spellings
whose answers do not move (`TE-AU` item 4): `NativeGridTests`'
`resetClearsGridCellAttributeMarks` and
`cellAttributesAndRowTokensAreReadThroughModifierNodesAndNotContainers` compare
a plan's anchor with `ProposalAnchor(.topLeading)`, and `GridElementTests`'
`everyProposalModifierCarriesAGridCellAttributeAsTheProbeReads`' `anchor`
helper maps its expected alignment through `ProposalAnchor.init`.

**Divergence 64 retires** (a fractional grid cell anchor, `GR-O` 4): pinned
now by 3.12 at GL14's reading. Divergence 93's pin (`.high` drawn bilinear) is
3.8. Live count after all three lanes: 65 + 90, 91, 92, 93 − 64 = **68**, as
spec §3 planned.

**Pixels**: `docs/probes/demo-pixels/compare.sh <scratch> ff2ae92 02f1e0f` —
controls as in §3 and §4 (light vs dark 1048576, default vs modal 1031003,
default vs animation 454895, f0 vs f3 0, chrome pair 0, distinct 544 and 216,
prod default vs modal 491221, prod distinct 529, indicator rects 0); **0
differing, scene identical, in all fourteen**. The demo's own
`.aspectRatio(16.0 / 9.0)` takes the given-ratio path, unchanged.

**Mutations** (each on `02f1e0f`, one spelling applied from a copy of the
committed file, build, whole unfiltered suite, the file restored from the
copy, `git status --short` read clean of source after each — only this
round's three doc files listed):

| id | mutation (spelling) | reddened (issues) |
|---|---|---|
| M3a | `Image`'s point size `bitmap.width`/`height`, `scale` ignored | `anImageAnswersItsPointSizeAtEveryProposal`, `aResizableImageAnswersItsProposal`, `anImagePaintsOneTexturedQuadOverItsBoundsAtTheScale` (3) |
| M3b | `resizable()` sets `isResizable = false` | `aResizableImageAnswersItsProposal`, `scaledToFitAndScaledToFillAreAspectRatioNil`, `aFillImageOverflowsItsFrameUnlessClipped` (5) |
| M3c | the quad drawn at the bitmap's pixel size at the bounds' origin (`TE-AU` item 7) | `anImagePaintsOneTexturedQuadOverItsBoundsAtTheScale`, `scaledToFitAndScaledToFillAreAspectRatioNil`, `aFillImageOverflowsItsFrameUnlessClipped` (4) |
| M3d | the kernel's ideal ratio `1.0` (no nil×nil measurement) | `aspectRatioWithNoRatioTakesTheChildsIdealRatio`, `scaledToFitAndScaledToFillAreAspectRatioNil`, `aFillImageOverflowsItsFrameUnlessClipped` (7) |
| M3e | the node answers the ratio-shaped proposal when both axes are concrete (first spelling assigned the `let` twice and **did not build**; re-spelled with an `else`) | `aFixedChildKeepsItsSizeUnderAspectRatioNil`, `anAspectRatioAnswersItsChildsAnswerToTheRatioProposal`, `anAspectRatioTreatsInfinityAsAConcreteAxis`, `aspectRatioFitInscribesTheParentProposalBeforeMeasuringItsChild`, `aspectRatioFillCircumscribesTheParentProposalBeforeMeasuringItsChild`, `theCrossAxisMarkReachesASpacerThroughEveryWrapperButAStack` (17) |
| M3f | `scaledToFill()` → `aspectRatio(nil, contentMode: .fit)` | `scaledToFitAndScaledToFillAreAspectRatioNil`, `aFillImageOverflowsItsFrameUnlessClipped` (2) |
| M3g | `Image.paint` wraps `drawImage` in `pass.clipped(to: bounds, …)` | `aFillImageOverflowsItsFrameUnlessClipped` (1) |
| M3h | `filter` always `.linear` | `interpolationNoneIsNearestAndEveryOtherLinear` (1) |
| M3i | `ImageBitmap` builds `ImageTexture(premultipliedRGBA:)` from the straight bytes | `anImageBitmapPremultipliesStraightAlpha` (1) |
| M3j | `ImageBitmap`'s two preconditions removed | `anImageBitmapOfTheWrongByteCountOrAZeroSideTraps` (2: both children still die, in `ImageTexture`, unnamed) |
| M3k | `contentsOfFile:` reverses the decoded rows | `anImageBitmapDecodesAPNGThroughImageIO` (1) |
| M3l | the `UnitPoint` factors rounded to the nearest nine-point in `GridCellModifier.mark` | `aGridCellAnchorTakesAUnitPoint`, `aNonFiniteGridCellAnchorTraps` (3: NaN rounds to 1, so the child exits 0) |
| M3m | `Image`'s scale precondition removed | `anImageOfANonPositiveOrNonFiniteScaleTraps` (4) |
| M3n | `markNativeGridCell`'s finite-anchor precondition removed | `aNonFiniteGridCellAnchorTraps` (1) |
| MG3a | `@_disfavoredOverload` removed from `gridCellAnchor(_: UnitPoint)` | **did not build**: 26 leading-dot `gridCellAnchor(.…)` sites in `GridElementTests.swift` and 1 in `ModifierCompositionProofTests.swift` go ambiguous (`DD-P` item 4's hazard, in the package itself) |
| MG3a′ | MG3a, plus those 27 in-repo sites spelled `ProposalAlignment.…` so the package builds | `aGridCellAnchorTakesAUnitPointAndTheNinePointSpellingsStillResolve` (1: `4 nine-point control: succeeded=false`, `ambiguous use of 'topLeading'`) |
| MG3b | `Image.init(systemName:)` stub added | `anImageHasNoSystemNameOrAssetInitialiser` (3) |

**17 rows, 16 of which build and redden** (MG3a does not build; MG3a′
replaces it); every building mutation reddens its designed test, none
reddened nothing.

**Fix round** (review of lane 3, one major and two minors). The verifier's
**V5** — `gridCellAnchors[index] = anchorPoint` unconditionally in
`LayoutTree.markNativeGridCell`, the `UnitPoint` copy of the first-mark-stands
rule (`TE-AU` item 4) — and **V9** — that path's finiteness precondition
shrunk to `anchorPoint.horizontalFactor.isFinite` — each left the whole
1762-test suite green: only the nine-point copy was pinned (GL16), and 3.12b
fed a NaN x only; 3.10b fed scale 0 and +∞ but no negative or NaN. Added,
green on arrival against the unmutated code and committed before mutating:
**3.12c** `theInnerAnchorWinsThroughTheUnitPointOverload` (GL14's layout,
GL16's inner-wins reading carried to a `UnitPoint` chain — in SwiftUI
`.topLeading` is itself a `UnitPoint`, so GL16 already is such a chain; no new
probe arm: two `UnitPoint`s → a at (10, 20), a nine-point inside a `UnitPoint`
→ (0, 0), and the control, a `UnitPoint` inside a nine-point → (10, 20));
3.12b gains a `UnitPoint(x: 0, y: .infinity)` child; 3.10b gains a scale −2
and a NaN child. Counts: unfiltered `swift test --build-system native
--no-parallel` → **`Test run with 1763 tests in 3 suites passed`**, the
`FR-J no-argument frame: succeeded=` line present; **1763 = 1762 + 1** (3.12c,
`MetalUITests`, so the container's figures do not move). Mutations, each on
the fix commit from a copy of the committed file, whole unfiltered suite,
restored, `git status --short` clean after:

| id | mutation (spelling) | reddened (issues) |
|---|---|---|
| V5 | `if gridCellAnchors[index] == nil { gridCellAnchors[index] = anchorPoint }` → `gridCellAnchors[index] = anchorPoint` | `theInnerAnchorWinsThroughTheUnitPointOverload` (2: the two-`UnitPoint` arm and the nine-point-inside-`UnitPoint` arm; the control arm green, as designed) |
| V9 + M3o | V9 in `LayoutTree.swift` together with **M3o**, `Image`'s `scale > 0` → `scale != 0`, in one run (disjoint files and disjoint tests) | V9: `aNonFiniteGridCellAnchorTraps` (1: the y child still aborts, but not at the anchor check); M3o: `anImageOfANonPositiveOrNonFiniteScaleTraps` (2: the scale −2 child exits 0) |

The NaN-scale child is not separated by M3o (`NaN != 0` holds but `isFinite`
still traps it); it pins the `isFinite` half against NaN, which zero and −2
cannot.

**Elsewhere**: `Backends/SDL` (`PKG_CONFIG_PATH=.accesskit`) builds against
`02f1e0f` and runs **22 + 25**, unmoved from §3 (lane 3 adds no primitive; its
image draws through lane 1's `drawImage`, whose parity frame 6 already
covers a linear, a nearest, a half-alpha and a masked image). A
`swift:6.4-noble` aarch64 container builds the root package at `02f1e0f` with
0 `error:`/`warning:` (`ImageBitmap(contentsOfFile:)` compiled out, no
ImageIO) and runs **199 + 10 + 22** (`MetalUILayoutTests` 198 → 199, 3.4;
`MetalUICrossPlatformTests`, `MetalUICoreTests` unmoved).
`theLegacyEngineSymbolsAreAbsentFromTheTestProcess` and
`everyProductionTreeBuildsOnAOneMegabyteThread` green in both the macOS suite
and the container; `MetalUILayout`'s imports still read `import MetalUICore`
alone; `Expected.swift` unedited.

**Real window**: lock probe 04:58 PDT — `CGSSessionScreenIsLocked = 1`,
`displayAsleep main: 1` — so `capture.sh` was not run; owed, as in §3 and §4.
Lane 3 touches no tree the demo builds (the fourteen read 0).

## §6 Record phase close (2026-09-29)

All three lanes verified `ok: true` (lane 1's four remaining items are minor
test-coverage gaps, not code defects — disposed below, none blocking). This
section is an independent re-take of the suite, guard and golden counts, the
pixel comparison, the probe, `Backends/SDL` and a `swift:6.4-noble` container,
plus the tick decision (`TE-AP`) and the outstanding hazards. Commit: this one.

**Suite**, from a clean tree (`swift package clean`, the accumulated stored-
property changes across all three lanes — `MUIRect`'s renamed field, `Scene`'s
new arrays, `Rectangle`'s optional colour, `Decoration`'s clip field,
`NativeNode.aspectRatio`'s optional payload, the grid anchor storage):
`swift build --build-system native --build-tests` → 0 `error:`, the one
SwiftPM deprecation `warning:`; `swift build --build-tests` (default build
system) → 0 `error:`, 0 `warning:`. Unfiltered `swift test --build-system
native --no-parallel` → **`Test run with 1763 tests in 3 suites passed after
108.877 seconds`**, one summary line, the `FR-J no-argument frame:
succeeded=true` line present (guards ran). **1763 = 1706 + 12 + 25 + 4 + 15 +
1**: §3's 12, §4's 23 tests + 2 guards (25) and its fix round's 4, §5's 12 +
2 traps + 1 guard (15), and §5's fix round's 3.12c (1) — the same arithmetic
as §3–§5's own close paragraphs (1718, 1743, 1747, 1762, 1763), re-verified
rather than re-derived. *(Corrected by the branch check: this paragraph first
read "1706 + 12 + 25 + 15 + 1 + 1 + 1 + 1 + 1" with §4's 25 explained as
"23 + 2 fix-round" — the total was right, the explanation miscounted §4's
two guards as its fix round and left four `+ 1` terms unexplained.)* `goldensUnchanged`
for the whole part: 0 goldens throughout (`find Tests/MetalUILayoutTests -name
"*.json" | wc -l` reads 0); no `@Test` was removed by any lane (the T rows —
one in §3, one in §4, one in §5 — are retained tests with a re-derived or
inverted answer, each with its own row in that lane's section, `TE-AR` item
10, `TE-AS` item 7, `TE-AU` item 5). `theLegacyEngineSymbolsAreAbsentFromThe
TestProcess`, `everyProductionTreeBuildsOnAOneMegabyteThread`,
`theDemoFrameMatchesTheValuesRecordedOnMacOS`, `theSevenRetentionSlotsAreMutu
allyDistinct`, `everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn` and
`everyReportNamesALiveOwnerOrIsRefusedByName` all green. `MetalUILayout`
imports only `MetalUICore` (`grep -h '^import' Sources/MetalUILayout/*.swift
| sort -u` reads one line); `MetalUIScene` imports only `MetalUIShaderTypes`.

**Guards**: `grep -c canTypecheck` across every guard file CLAUDE.md names
(30 files, `Tests/MetalUITests` and `Tests/MetalUICoreTests/UnitSafetyTests.swift`)
reads 109 raw hits, less `UnitSafetyTests`' one comment hit = **108**. New
this part: `ShapeCompileGuards` (2: G2.1 `anOutsideShapeNeedsOnlyItsGeometry`,
G2.2 `theRectangleColorInitialiserIsDeprecatedTowardFill`, both whole-file
`typecheckFile`) and `ImageCompileGuards` (1: G3.2
`anImageHasNoSystemNameOrAssetInitialiser`, whole-file `typecheckFile`); G3.1
renames `GridCompileGuards`' G4 in place (same file, same count, 4). **108 =
105 + 0 (lane 1) + 2 (lane 2) + 1 (lane 3)**, matching every lane's own
close. The `typecheckFile`-based helper count moves **66 → 69** (ShapeCompile
Guards' 2 plus ImageCompileGuards' 1); the `typecheck`-based helper count
stays 39; 39 + 69 = 108.

**`_reserved`**: `git grep -n "_reserved" -- '*.swift' '*.h' '*.metal'
'*.hlsl'` reads 14 lines, all `MUIGlyph`'s own field, its memberwise call
sites (`PortableText.swift`, `ShaderTypesBridge.swift`, five
`Tests/MetalUIRenderTests` files) and the header comment naming the old word
— no `MUIRect`/rect site, confirming `TE-AR` item 9's claim independently
(checked call by call, not just counted).

**Pixels**: `docs/probes/demo-pixels/compare.sh <scratch> ff2ae92 HEAD` —
controls unmoved since stage 9 (light vs dark 1048576, default vs modal
1031003, default vs animation 454895, f0 vs f3 0, chrome pair 0, distinct 544
and 216, prod default vs modal 491221, prod distinct 529, indicator rects 0);
**0 differing pixels, scene identical, in all fourteen images**, independently
re-taken from a fresh `git archive` of both commits (not reused from any
lane's own run).

**Probe**: `swiftui-shapes-and-rendering.swift` recompiled (`swiftc -O`) and
run interpreted (`/usr/bin/swift`); both outputs byte-identical to each
other and, after stripping the `//` comment prefix, byte-identical to the
78 recorded lines in the file's own header (P1 through K12, then O6, then
`done`) — including O6's reading (`background(in:)` paints white over a red
canvas, 5968 px). No new SwiftUI claim is made in this section; every one
used above is one of these 78 lines or `swiftui-grid.swift`'s GL14 (re-run
by the critic round, §2, and pinned again by 3.12).

**`Backends/SDL`** (`PKG_CONFIG_PATH=$PWD/.accesskit`): `swift build
--build-tests` → 0 `error:`; the one `warning:` is SwiftPM's pre-existing
`-Wl,-rpath,/opt/homebrew/lib` "prohibited flag" notice (unrelated to this
part — the same warning fires on an unmodified checkout, not one of this
part's changes). `swift test --skip-build` → **`Test run with 22 tests in 0
suites passed`** then **`Test run with 25 tests in 0 suites passed`** —
**22 + 25**, matching §3's own reading, unmoved since (lanes 2 and 3 touch
no file `Backends/SDL` builds).

**A `swift:6.4-noble` (aarch64) container** (`docker run --rm -v "$PWD":/work
-w /work swift:6.4-noble …`): the root package builds with 0
`error:`/`warning:` and runs `MetalUISystemFontsTests` 6,
`MetalUILayoutTests` **199**, `MetalUICrossPlatformTests` **10**,
`MetalUICoreTests` **22** — **199 + 22 + 10**, matching §5's own reading
(unmoved since — lane 3's 3.4 is the one test in `MetalUILayoutTests`, 198 →
199, `TE-AU` item 4's Windows-safe payload change). `Tests/PortableTests`
(a separate package, in the same container and independently on macOS):
`swift build --build-tests` then `swift test --skip-build` →
**`Test run with 21 tests in 7 suites passed`**,
**`Test run with 6 tests in 1 suite passed`**,
**`Test run with 5 tests in 1 suite passed`** — **21 + 6 + 5** on both
platforms; unaffected by this part (no `MetalUIPortableText`/`MetalUITextSystem`/
`MetalUIFreeType`/`MetalUIHarfBuzz` source touched by any of the three lanes).

**A pre-existing documentation slip corrected in passing** (found while
re-taking this figure, not part of this task's own scope, but CLAUDE.md's own
practice is to fix a refuted claim everywhere it was copied): record §59 and
CLAUDE.md's task-11-part-1 Counts entry both read "`Tests/PortableTests`
20 + 6 + 5" — arithmetic that does not check out. `PortableTextDeterminism
Tests.swift` held 18 `@Test` functions before task 11 part 1 (confirmed by
`git show 169d166:…PortableTextDeterminismTests.swift | grep -c @Test`); lane
1 of part 1 added a new file, `TruncationDeterminismTests.swift`, with 3
`@Test` functions (one gated); 18 + 3 = **21**, not 20, and both this
container and a native macOS run of `Tests/PortableTests` read 21 for that
target today. **Five occurrences in record §59 corrected** (§2.1, §2.5 close,
the lane-1 fix-round close, and both sentences in §6's `Tests/PortableTests`
paragraph) to `21 + 6 + 5`, each noting the correction and citing this
section; CLAUDE.md's own occurrence is fixed in the same commit as this
part's other CLAUDE.md edits. No test was ever miscounted in a suite total —
the slip was confined to this one aside about a separate package's own
reading.

**Real window**: lock probe at this close, 06:39 PDT —
`CGSSessionScreenIsLocked = 1`, `displayAsleep main: 1` — locked at every
check across design, the critic round and all three lanes, and now at this
close too; the real-window capture stays owed, as it has since task 8.

**Lane 1's four open items, disposed** (none blocks the tick — each is a
test-coverage gap or a latent contract note, not a defect; `ok: true` stands).
*(Branch-check note: the mutation labels in items 1–3 — S-A, V1, V6, V7, V8,
V9 — are lane 1's verifier's own, not rows of §3's M1 table, and are recorded
nowhere else; §5's V5 and V9 are lane 3's fix-round labels, a different
mutation under the same name. Item 2's "V9" is not §5's V9.)*

1. **SDL texture-eviction leak, untested.** Removing the release call in
   `SDLWindowRenderer.prepareTextures` (mutation S-A) leaves the whole
   `Backends/SDL` suite green, because `cachedTextureIdentities` reads the
   Swift-side dictionary, which drops an entry whether or not the C bridge
   actually released the GPU handle. Metal is safe by construction (ARC frees
   the texture with the dictionary entry); SDL is not measured. **Owed, owner
   none**: a live-handle or release count on the C bridge side, asserted by
   `imageTexturesPersistAndAreReleasedWhenAbsent`.
2. **Three Metal shader facts pinned only by the SDL parity job, not by any
   root test**: image opacity (mutation V1), the image's vertical
   orientation/row order (V9), and the ellipse kind's circle branch (V6).
   Every root `ImagePrimitiveTests`/`EllipsePrimitiveTests` case uses opacity
   1, a one-row or 1×1 texture, or a non-equal-axis ellipse; only
   `Experiments/SDLGPU`'s `Replay --portable` (the `sdl-gpu-linux.yml` job on
   push) catches a regression in any of the three. **Owed, owner none**: a
   half-opacity image test, a two-row nearest-filtered image test, and an
   equal-axis (circle) ellipse test in the root suite — or, short of that, a
   named row in `TE-AR` stating the parity job is these three facts' only
   pin.
3. **Two `TE-AR` claims (items 6 and 7) are stated but not tested**: a band at
   least as wide as the shorter diameter fills the whole ellipse (mutation
   V7), and an empty scene releases every cached image texture (mutation V8).
   Neither mutation reddens anything, root or SDL. **Owed, owner none**: a
   wide-band ellipse fill test and an empty-scene-after-an-image-scene
   eviction test.
4. **The Metal image cache is per-`Renderer`, and `AppKitPlatform` shares one
   `Renderer` across every window** (`RS-C`): two windows each showing a
   different image evict each other's texture every frame, re-uploading each
   time frames alternate (test 1.9's own sequence shows the count). SDL keeps
   one renderer per window and does not have this. **No production code draws
   an image yet** (lane 2's/lane 3's `Shape`/`Image` surface exists, but
   `demoContent()` calls neither), so nothing observable regresses on this
   branch. **Owed, owner: before any multi-window image consumer ships** —
   either key the Metal cache per surface, or evict only textures unused for
   a frame or more, pinned by an alternating two-window test.

None of the four is a rendered-output difference between Metal and SDL for a
single window (the parity harness's own promise); all four are additional
test coverage or a documented latent limitation, so they do not gate the tick
below.

**Tick decision (`TE-AP`)**. All three lanes landed; spec §3's collection
table is checked row by row:

| row | disposition | satisfies `TE-AP`? |
|---|---|---|
| shapes | built | yes |
| fills/strokes | built | yes |
| `foregroundStyle` on a shape | built | yes |
| clipping | built (divergences 91, 92 as documented traps/constraints) | yes |
| `.cornerRadius` clipping (divergence 47) | kept, numbered divergence | yes |
| overlays/backgrounds with shapes | audited unchanged, two spellings added | yes (built) |
| images | built (divergence 93 as a documented constraint) | yes |
| `aspectRatio(nil)`, `scaledToFit`/`Fill` | built | yes |
| `UnitPoint` grid anchor | built, divergence 64 retires | yes |
| `colorScheme`/appearance, pre-paint theme | not built, documented absence, owner none | a **renderer constraint**, explicit (§9) — the task's own text asks for exactly this disposition |
| colour glyphs | kept, record §05's renderer-constraint row, owner none | a **renderer constraint**, explicit (§9), pre-existing since before this task |
| SF Symbols, `Path`, gradients, `StrokeStyle`, a labelled `Image` | constraints, each with an owner or `owner: none`, §9 | every one named, explicit |

The last three rows read "owner: none" rather than "re-owned to a task", but
the task's own text is "keep renderer constraints explicit when an exact
effect is not supportable yet" — an explicit, permanent boundary with no
owner is exactly that disposition, not an unfinished clause; none of the
three was created by this task (`EV-G`, record §05's colour-glyph row and the
excluded-surface list all predate it), and each is named, with a reason, in
spec §9. Every row is therefore built, kept with a numbered divergence, or an
explicit renderer constraint (owned or not) — **task 11 is ticked**.

**Live divergence count**: 65 → **68** (90, 91, 92, 93 added; 64 retires),
next label **94**. **Declared but inert**: no row added or deleted; the
colour-glyphs row (already in the inline list) is re-confirmed unmoved
(`TE-AO` item 2 — the image primitive is now the draw path a polychrome
sprite would use, but rasterizing `COLR`/`sbix` stays a text-system
milestone, not this one).

**Spec status**: `docs/superpowers/specs/2026-09-28-shapes-and-rendering-design.md`
marked "lanes 1–3 landed; Record phase close applied; task 11 ticked
(both parts close every clause)".

## §7 Adversarial branch check (2026-09-29)

Against `ff2ae92..8b09f80`, independently of §3–§6.

**Suite**: after `swift package clean`, `swift build --build-system native
--build-tests` (0 `error:`, the one SwiftPM deprecation `warning:`), then
unfiltered `swift test --build-system native --no-parallel` → **`Test run
with 1763 tests in 3 suites passed after 110.256 seconds`**, one summary
line, `FR-J no-argument frame: succeeded=` present. Default build system
(`swift build --build-tests`): 0 `error:`, 0 `warning:`. Goldens 0; guards
**108** (110 raw `canTypecheck` hits less `Typecheck.swift`'s declaration and
`UnitSafetyTests`' comment). `theLegacyEngineSymbolsAreAbsentFromTheTestProcess`,
`everyProductionTreeBuildsOnAOneMegabyteThread`,
`theDemoFrameMatchesTheValuesRecordedOnMacOS` (`Expected.swift` unedited)
and `theSevenRetentionSlotsAreMutuallyDistinct` green. `MetalUILayout`
imports only `MetalUICore`. No diff under `StateTable.swift`,
`StateDispatch.swift`, `ExplicitIdentity.swift`, `MetalUIDemoContent` or
`Tests/MetalUICrossPlatformTests`. `Frame.insertHitbox` intersects with the
clip's box alone, so `TE-AJ` item 5's new contained-radius case cannot move
a hitbox (read, and the hit-testing suites green). `cmp CLAUDE.md AGENTS.md`
clean. Every `TE-` id added to a changed doc resolves to a `## TE-` heading
(`TE-AW`, the next unused, excepted); all 89 camel-case test/symbol names
added to the record, spec, decisions doc, plan and CLAUDE.md resolve in
`git grep` over `Tests`, `Sources`, `Backends/SDL` and `Experiments`.

**Two mutations of this check's own** (committed tree, file restored from a
copy, full unfiltered native suite, `git status --short` clean after each):

| id | mutation | reddened |
|---|---|---|
| B1 | `paintShapeStroke`'s `grown(r)` returns `r` — a centred stroke's outer radius not grown by `w/2` (K6, K7, K12) | `aStrokeRoundsItsOuterEdgeByHalfTheWidthOnlyOverACurve`, `aShapeBackgroundOrOverlayTakesTheContentsSize` (4 issues) |
| B2 | `LayoutTree.aspectRatioProposal`'s nil-ratio branch divides `height / width` — the ideal ratio inverted (`TE-AM`) | `aspectRatioWithNoRatioTakesTheChildsIdealRatio`, `scaledToFitAndScaledToFillAreAspectRatioNil`, `aFillImageOverflowsItsFrameUnlessClipped` (5 issues) |

**Pixels**: `docs/probes/demo-pixels/compare.sh <scratch> ff2ae92 HEAD`,
fresh archives — controls as §6 reads them (1048576, 1031003, 454895, 0,
1048576, 0, 544, 216, 491221, 529, 0); **0 differing, scene identical, in
all fourteen**. **Probe**: `swiftui-shapes-and-rendering.swift` recompiled
(`-O`) and run: 78 lines, every one present verbatim in the header.
**`Backends/SDL`** (`PKG_CONFIG_PATH=.accesskit`): 22 + 25 passed.
**`swift:6.4-noble`** (aarch64, fresh `git archive`): root package builds
with 0 `error:`/`warning:`, `MetalUILayoutTests` + `MetalUICoreTests` +
`MetalUICrossPlatformTests` **199 + 22 + 10**. **Real window**: lock probe
06:54 PDT, `CGSSessionScreenIsLocked = 1`, `displayAsleep main: 1` — not
taken, still owed.

**Doc defects fixed** (commit `8b09f80`): the spec's header read next unused
`TE-AV` (now `TE-AW`); spec §10 stopped at "as landed 1762" (1763 after
3.12c); §6's count arithmetic explained §4's two guards as a fix round and
left four `+ 1` terms unexplained (the total was right); §6's verifier labels
(S-A, V1–V9) resolved nowhere and collided with §5's V5/V9 (note added);
CLAUDE.md (twice) and the plan's progress note said frame 6 was checked
"byte-for-byte … on Metal, llvmpipe and D3D12" — measured is 0 px on SDL's
Metal backend, within `ParityTolerance` on llvmpipe (Δ1/Δ2, §3), and D3D12
only on push, which this branch has not had; the plan note said "four"
lane-1 gaps and listed three (the two untested `TE-AR` claims added).

**Verdict**: no code defect found. The four §6 coverage gaps stand as owed.
One note, not a defect: `LayoutModifier` is a public enum and gains
`.clipShape(any Shape)`, so an outside exhaustive `switch` over it stops
compiling — the same shape as every earlier case this enum has gained.
Task 11's tick stands: parts 1 and 2 close every clause of its text, the
renderer constraints listed in spec §9. **Merge: yes**, with Windows
(D3D12) parity and Linux CI to be read on push.

## §8 Merge with `master` `0714528` (2026-09-29)

`master` had published §60 (`60-text-page-and-tab.md`, `TI-I` Page Up/Down in
`TextEditor` and `TI-J` Tab between inputs, PR #31) first, so this record was
renumbered 60→61 (`git mv`, header note) and every §60 this branch wrote was
swept to §61 — found by `git grep '§60'` at `ff2ae92`, which reads nothing,
so every §60 in a file only this branch touched was the branch's
(`DecorationCompileGuards.swift`, `GridCompileGuards.swift`,
`ShapeTests.swift`, record §59, the text-semantics decisions doc, the
alignment plan, the shapes spec, this file). In the three files both sides
touched (`CLAUDE.md`, `AGENTS.md`, `docs/record/README.md`) only the branch's
lines moved; master's §60 citations name the text-page record and stay:
`CLAUDE.md`'s text-page counts paragraph and its Focus paragraph (§60
§Merge), the README's text-page row, record §04's 2026-09-28 section, record
§60 itself, `2026-09-25-data-and-scrolling-decisions.md`'s erratum and
`specs/2026-09-23-text-input-design.md`.

**Conflicts**: only `CLAUDE.md`/`AGENTS.md` (the counts paragraphs, kept
both, a merged one added above them). The prefix list auto-merged with
master's `TI-` next `TI-K` and this branch's `TE-` next `TE-AW`. No source
file was changed by both sides: master touched `Focus.swift`,
`TextEditing.swift`, `TextEditor.swift`, `Window.swift`; this branch none of
those. No divergence number collides — master added none (its 04 section
widens 80), this branch added 90–93 and retired 64; live count **68**.

**Semantic check.** Tab visits every *registered* focusable element
(`FocusRegistry.tabOrder`). `Image` and every `Shape` are proposal leaves
registering no hitbox, focus entry or accessibility record (`Image.swift`'s
and `Shape.swift`'s doc comments; a grep of `Image`, `ImageBitmap`, `Shape`,
`ShapeView`, `Shapes`, `ClipShape` finds no focus or handler registration),
and the legacy `clipShape` returns `Self` and changes paint and the hitbox's
clip only. Pinned by a new merge test,
`tabPassesOverImagesAndShapesAndStopsAtAFocusableClippedBox`
(`FocusTraversalTests`): a field, a `VStack` of an `Image`, a filled `Circle`
and a `Rectangle` clipped to a `Capsule`, an unfocusable `Box` clipped to a
`Circle`, a `.focusable()` `Box` clipped to a `RoundedRectangle`, a field —
the tab order reads 3 and Tab visits 0, 1, 2, 0, the middle stop not a text
target. Control: making the unfocusable clipped box `.focusable()` reddens it
(`tabOrder.count == 3` fails — 4), so the count discriminates. The
`FocusTraversal`/`TextEditorTests`/`TextEditingTests` filter ran 54 tests,
all passing, before the clean re-take.

**Re-take** after `swift package clean`: `swift build --build-system native
--build-tests` 0 `error:`, the one SwiftPM deprecation `warning:`; `swift
build --build-tests` (default) 0 `warning:`/`error:`; unfiltered `swift test
--build-system native --no-parallel` → **`Test run with 1773 tests in 3
suites passed after 110.381 seconds`**, the FR-J line present. **1773 = 1715
− 1706 + 1763 + 1** (the expected 1772 plus the merge test). Guards 108,
goldens 0. `Expected.swift` identical to both parents;
`theDemoFrameMatchesTheValuesRecordedOnMacOS`,
`everyProductionTreeBuildsOnAOneMegabyteThread`,
`theLegacyEngineSymbolsAreAbsentFromTheTestProcess` green.
`docs/probes/demo-pixels/compare.sh` from `0714528` to the merge tree:
**0 differing, scene identical, in all fourteen**.

**`Backends/SDL`** (`PKG_CONFIG_PATH=$PWD/.accesskit`): builds with 0
`error:` (the pre-existing `-Wl,-rpath` prohibited-flag notice and two
`ld` SDL-dylib version notices). `swift test` lists **22 + 25** = 47 tests;
`ReplayFixtureTests` prints `Test run with 22 tests … passed`, but
`MetalUISDLTests`' output is **truncated** in an unfiltered run — the last
test or two and its summary line never print, exit status 0. Measured
**pre-existing, not the merge's**: a detached worktree at this branch's own
tip `3296e9e` truncates the same way in three of three runs (45, 46, 46
`passed` lines of 47). It follows
`theRunLoopTicksLinksAndEndsWhenTheLastWindowCloses`: with it skipped the
target prints `Test run with 24 tests in 0 suites passed`, and it alone
prints `Test run with 1 test … passed` — so all 25 pass, read in two runs.
§6's "Test run with 25 tests" reading is not reproduced here; the output
loss is owed an investigation (the run loop ending the process's output
when the last window closes is the suspect), not fixed on this branch. *(Found and fixed after the merge, §9: the suspect was wrong — HIToolbox's
wake stopped Swift Testing's outermost run loop.)*

## §9 `MetalUISDLTests`' truncated run: HIToolbox's wake stops Swift Testing's run loop (2026-09-29)

§8's open item, found and fixed. **Nothing in the texture work was at
fault**; the branch's two new SDL tests only moved the timing.

**Reproduced.** `PKG_CONFIG_PATH=$PWD/.accesskit swift test --skip-build
--no-parallel --filter MetalUISDLTests` at `8d7526b`: exit 0, 24 `passed`
lines of 25, no `Test run with` line, **three of three** runs. In the
default (parallel) mode it did **not** reproduce — 36 runs (20 filtered, 6
unfiltered, 10 filtered under eight busy-looping `yes` processes), every one
`Test run with 25 tests … passed`. §8's runs were all `--no-parallel`.

**Instrument.** An interposing dylib (`DYLD_INSERT_LIBRARIES`, the
toolchain's `swift` rather than `/usr/bin/swift`, whose wrapper strips it)
printing a backtrace at `exit`, `_exit`, `abort`, `CFRunLoopStop` and at every
`CFRunLoopPerformBlock` on the main run loop (wrapping each block so a stop
names the block that ran it, and naming the block's invoke function with
`dladdr`):

1. The test process's `exit(0)` comes from `swift_task_asyncMainDrainQueue`
   after `CFMainExecutor.run` returned — i.e. Swift Testing's outermost
   `CFRunLoopRun` **returned**, which it does only when stopped.
2. The stop is `CFRunLoopStop(main)` from a block, **block #8 of 8**, queued
   in common modes from **HIToolbox's event thread** (`_NSEventThread` →
   `PullEventsFromWindowServerOnConnection` → `PushToCGEventQueue`), invoke
   function `SignalMainThread()_block_invoke`. It was queued during
   `aWindowRendererFrameIsTheReplayPathsFrame` while the main thread was
   busy in the test (not inside `nextEventMatchingMask`, counted by a
   swizzle: 0 in flight), and ran when the main thread next returned to the
   executor's loop — the queued remainder of the run was never started.
3. `dyld_info -disassemble` of HIToolbox: `PushToCGEventQueue` calls
   `sCGEventEnqueueSignalBlock` if one is installed, and **only otherwise**
   `SignalMainThread`, which (once per `pending` flag) queues `^{ pending =
   0; CFRunLoopStop(main) }` and wakes the loop — a wake meant to break a
   main thread blocked in `ReceiveNextEvent`, harmless in any nested run,
   fatal to an outermost `CFRunLoopRun` whose return ends the process.
4. The setter `_SetCGEventQueueEnqueueSignalBlock` is **never called** in the
   test process (interposed, 0 calls). In a scratch AppKit program it is
   called from `NSUpdateCycleInitialize` ← `-[NSApplication run]`, and only
   there. SDL3 (3.4.16, Homebrew) calls `finishLaunching` and
   `nextEventMatchingMask` but never `run`, so an SDL process always takes
   HIToolbox's fallback.

**Root cause.** SDL video on macOS without `-[NSApplication run]` leaves
HIToolbox waking the main thread by stopping the main run loop. An SDL app's
own loop (`SDLPlatform.run()`, synchronous) never notices; a host whose
outermost loop is `CFRunLoopRun` — Swift Testing's main executor, or any
`async` main driving SDL between awaits — returns from it and exits 0. On
the branch the extra tests shifted when window-server traffic reached the
event thread relative to the main thread's idle moments; master's 23 tests
happened not to hit the window. Timing, not the texture path.

**Fix** (`Backends/SDL/Sources/MetalUISDL/SDLPlatform+AppKit.swift`, called
from `SDLPlatform.init` under `#if canImport(AppKit)`): once per process,
unless `NSApp.isRunning` (an AppKit host's own `run` installed it), queue a
common-modes block that calls `NSApp.stop(nil)` and posts an
application-defined event, then call `NSApp.run()` — which runs
`NSUpdateCycleInitialize`, installs AppKit's signal blocks, processes the
posted event and returns at once. Its own file so AppKit's
`AccessibilityRequest` stays out of `SDLPlatform.swift`'s type lookup (the
first draft, in that file, failed on the ambiguity). Under the instrument,
after the fix, a whole `--no-parallel` run reads **0** `SignalMainThread`
blocks and two `CFRunLoopStop(main)` calls, **both inside the one-shot
`-[NSApplication run]`** (its own stop, and UpdateCycle's
`modeEventProcessingWaitEnter`), none on the executor's loop. The offscreen
renderer alone (`SDLWindowRenderer(offscreenWidth:…)`, 20 created and
drawn) never produced a stop in a probe, so it does not call the install;
windows are what generate the traffic. Not by reordering or skipping tests:
no test moved.

**Guards, red first.**

- `windowServerTrafficNeverStopsTheMainRunLoop`
  (`Tests/MetalUISDLTests/SDLMainRunLoopTests.swift`, `#if os(macOS)`): 40
  times, open a hidden window, pump, touch its renderer and drop it, then
  `CFRunLoopRunInMode(.defaultMode, 0.05, false)`; expects no
  `.stopped`. **Red before the fix**: stopped 35, 35 (twice, before the fix
  existed) and, with the call commented out afterwards, 28, 31, 25, 25 of
  40. Green after, three of three alone and in every full run below. It
  reproduces the mechanism deterministically where the truncation itself was
  timing-dependent — the nested run is harmless, so it observes the stop
  instead of dying of it.
- `armMainRunLoopExitCheck()` (same file): an `atexit` that, on the main
  thread with **no current mode** on the main run loop (so `CFRunLoopRun`
  has returned — Swift Testing's own exit runs inside a job the loop is
  servicing), prints `error: the main run loop returned …` and `_exit(1)`s.
  Armed by the new test and by each of the four `SDLPlatform`-creating
  helpers (`AccessKitTests`, `SDLControlStateTests`, `SDLPlatformTests`,
  `SDLTextInputTests`). **Its first draft trapped** (signal 5) at every
  normal exit: the `atexit` closure written inside a `@MainActor` function
  carried a main-actor isolation check; moved to a nonisolated function, it
  is silent on a clean run (exit 0, three of three). **Mutation** (the
  install call commented out): the whole `--no-parallel` run exits **1**
  with the message, three of three, the new test red; with the new test also
  skipped — the original bug's exact shape — exits **1** with the message
  and no summary line (22, 24, 23 `passed` lines), three of three, where it
  used to exit 0.

**After the fix** (`PKG_CONFIG_PATH=$PWD/.accesskit`, macOS):

| run | `ReplayFixtureTests` | `MetalUISDLTests` | exit |
|---|---|---|---|
| unfiltered `--no-parallel` ×3 | `Test run with 22 tests in 0 suites passed` | `Test run with 26 tests in 0 suites passed` (3.96, 3.91, 4.05 s) | 0 |
| `--no-parallel --filter MetalUISDLTests` ×3 | — | `Test run with 26 tests in 0 suites passed` | 0 |
| unfiltered, parallel ×3 | 22 passed | 26 passed | 0 |

**26 = 25 + 1** (the new test). The build adds no `error:`/`warning:`
beyond the pre-existing `-Wl,-rpath` prohibited-flag notice and the `ld`
SDL-dylib version notices. **Linux** (`swift:6.4-noble` aarch64,
`metalui-portable-ax`, `SDL_VIDEO_DRIVER=offscreen`, a copy of this working
tree, `--scratch-path /tmp/sb`): 0 `error:`, `Test run with 22 tests … passed`
and `Test run with 24 tests … passed`, exit 0, both parallel and
`--no-parallel` — unmoved, the new test and the helper arming being
macOS-only. **Root package**: `swift build --build-system native
--build-tests` 0 `error:`, the one SwiftPM deprecation `warning:`; unfiltered
`swift test --build-system native --no-parallel` → **`Test run with 1773
tests in 3 suites passed after 110.254 seconds`**, the FR-J line present;
`swift build --build-tests` (default) 0 `warning:`/`error:` — the root
package has no file in this change. macOS CI does not run `Backends/SDL`'s
tests (its macOS job only records fixtures), which is why a false green
there was local-only; `CLAUDE.md` gains a CI-hazard bullet.

## §10 An intermittent Direct3D 12 crash: the offscreen renderer released an unsignalled fence (2026-09-29)

Branch `fix/sdl-test-windows-enum` (PR #32, from `31f2e7a`).

**The symptom.** The SDL GPU workflow's Windows x64 D3D12 job (debug
validation layers on, "Microsoft Basic Render Driver") crashed in
`Backends/SDL`'s `MetalUISDLTests` in run **36588257167** (pull_request) and
passed in run **36588249657** (push, same commit): `*** Program crashed:
Exception 0x0000087d ***` — the D3D12 debug layer's break on an error — with
the stack `D3D12SDKLayers.dll` → `D3D12_INTERNAL_DestroyBuffer`
(`SDL_gpu_d3d12.c:1349`, the resource's final `Release`) ←
`D3D12_INTERNAL_PerformPendingDestroys` (:7739) ← `D3D12_WaitForFences`
(:8272) ← `mui_renderer_read_offscreen` (`SDLBridge.c:612`) ←
`SDLWindowRenderer.readPixels` ← `imageTexturesPersistAndAreReleasedWhenAbsent`.
The log carries **no validation message text** (the debug layer writes to
`OutputDebugString`, which the runner does not capture); the crashed
thread's registers held fragments of the message being formatted —
`" allocat"`, `"complete"`, `"or have "`, `"ATOR_SYN"` — consistent with
`COMMAND_ALLOCATOR_SYNC` ("…is being reset before previous executions
associated with the allocator have completed"), read from the register
dump, not from a printed message. The tests ran serially on the main actor
(each `@MainActor`, synchronous), so thread concurrency was not the cause.

**The root cause (SDL 3.4.16's D3D12 backend, read in source).**
`SDL_SubmitGPUCommandBufferAndAcquireFence` gives the caller the command
buffer's `inFlightFence` with one reference and `autoReleaseFence = false`.
`D3D12_ReleaseFence` returns the fence to the pool **at once** when that
reference drops, while the still-submitted command buffer keeps pointing at
it. The next `D3D12_INTERNAL_AcquireFence` pops that same fence and signals
it back to 0 from the CPU. Two in-flight command buffers then share one
fence: the older one's queue signal sets it to 1 while the newer is still
executing, and the next cleanup (any submit's or wait's "check for
cleanups" loop) calls `D3D12_INTERNAL_CleanCommandBuffer` on the newer —
resetting its command allocator mid-execution and dropping its resources'
reference counts — and `PerformPendingDestroys` then destroys the storage
and transfer buffers `mui_renderer_finish` had released, while the GPU
still reads them. `mui_renderer_finish` released the previous offscreen
frame's fence **unwaited** whenever two frames ran without a readback
between them. Every test before plan task 11 part 2 read back after each
frame (`read_offscreen` waited first), so the path was never taken;
`imageTexturesPersistAndAreReleasedWhenAbsent` is the first test to run
three frames back to back, and whether the older signal lands in the window
depends on WARP's timing — hence one crash in two runs.

**The fix** (`SDLBridge.c`): `retire_fence` waits for the last offscreen
frame before releasing its fence — used by `mui_renderer_finish` and
`mui_renderer_read_offscreen`; `mui_renderer_destroy` releases after
`SDL_WaitForGPUIdle`. The wait also runs SDL's cleanup of that command
buffer, so it leaves the submitted list before its fence can be recycled.
The window path is untouched (plain `SDL_SubmitGPUCommandBuffer`, whose fence
SDL releases itself after cleanup). No test was serialized and validation
was not disabled.

**The instrument.** `release_fence` counts a release made while
`SDL_QueryGPUFence` reads unsignalled
(`mui_renderer_unsignaled_fence_releases`, surfaced as
`SDLWindowRenderer.unsignaledFenceReleaseCount`); the renderer also counts
image-texture releases (`textureReleaseCount`, closing lane 1's verifier
note that no SDL test counted them). New test
`backToBackFramesNeverReleaseAnUnsignaledFence` (32 frames, no readback,
count 0, then the replay path's pixels), and
`imageTexturesPersistAndAreReleasedWhenAbsent` gains `textureReleaseCount ==
1` and the count at 0. **Red before, on macOS Metal, deterministic**: with
the counter in and `mui_renderer_finish` still releasing unwaited (and,
after the fix, with `retire_fence` in `finish` mutated back to
`release_fence`), the image-texture test reads **2** and the new test **31**
(31 of 31 releases before the GPU signalled), both red, three of three
runs; with the fix, 0 and green. The hazard is therefore observable off
Windows even though only Direct3D 12's fence reset turns it into a crash.

**Results.** macOS (`PKG_CONFIG_PATH=$PWD/.accesskit`): `--no-parallel`
and parallel both `Test run with 22 tests … passed` and `Test run with 27
tests … passed` (**27 = 26 + 1**). Root package: `swift build
--build-system native --build-tests` 0 `error:` (no root file changed).
CI after the fix (commit `e9f558f`): SDL GPU runs **36589957513** (push) and
**36589964381** (pull_request) — every job green, Windows x64 D3D12
`MetalUISDLTests` `Test run with 25 tests … passed` in both (the new test
2.1 s and 3.5 s under WARP with validation), Linux x86_64/aarch64 25 too
(the two macOS-only tests absent). Further Windows D3D12 runs are listed
below as they were taken.
