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
