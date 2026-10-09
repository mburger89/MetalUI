# 73 — Paths, shadows and transforms

Branch `feat/paths-shadows-transforms` from `dc96395` (master: the scaffold
review merged, PR #42). **Not a plan task**: item 3 of the user's gpui-gap
priority list (request 2026-10-02) — what the renderer could not draw until
now (`Path`, a blurred shadow, a rotated or scaled view) and what the shapes
spec's §9 table (`specs/2026-09-28-shapes-and-rendering-design.md`) listed as
documented renderer constraints. Spec
`docs/superpowers/specs/2026-10-02-paths-shadows-transforms-design.md`;
rulings `GX-A`…`GX-V` in the new decisions doc
`docs/superpowers/2026-10-02-paths-shadows-transforms-decisions.md` (next
unused `GX-W`); probe `docs/probes/swiftui-paths-shadows-transforms.swift`
(arms `P`, `PA`, `ST`, `SH`, `T`, `H`, `X`, `N`; recorded 2026-10-02 with the
screen unlocked, run twice byte-identical).

**Numbering.** Written as §73 directly: master's last record is §72
(scaffold) and `git fetch` at the Record phase showed `origin/master` still at
`dc96395`, so no renumbering. **The human-checks group is Q** (after P,
MetalView); no collision.

**Status: LANDED — every agent-doable clause is built; the looks are owed to a
human** (`docs/verification/human-checks.md` group Q, §7). Three lanes run
strictly in order, each red first, lanes 2 and 3 with review rounds, all
verified `ok: true`; the Record phase's close (§9) re-took the suite and the
checks.

## §0 Baseline, design session and critic round

- **Baseline** at `dc96395`: **2124 tests in 3 suites**, 0 goldens, 129
  typecheck guards, 70 live divergences (next label 104), `Backends/SDL`
  24 + 57.
- **Carried items.** The shapes spec's §9 rows for `Path`/`path(in:)` and
  `StrokeStyle` (owner none), `TE-AG` (`Shape` narrowed to `geometry(in:)`),
  `Shape.swift`/`ShapeView.swift` header comments, the divergences page's
  absences row, and the `.scale` transition's post-transform machinery
  (`AN-AE`) that this branch generalizes rather than duplicates (`GX-G`).
- **Design session and critic round**: rulings `GX-A`…`GX-O` (design) and
  `GX-P`…`GX-R` (critic: a handler written after an effect follows it, point
  consumers read local points, the anchor lives in scrolled space;
  `ColorToken.shadow` keeps `Theme`'s initialiser source-compatible; instruments
  replaced, cross-references fixed). The SwiftUI probe measured every claim
  the rulings rest on (fills, strokes and dashes, shadow profile and
  per-leaf behaviour, transform order, hit testing, accessibility frames,
  animation).

## §1 What landed

**Lane 1 — the renderer transform and `MetalUIPath`** (`GX-B`, `GX-F`,
`GX-K` in part, `GX-S`).

- **`MetalUIPath`**, a new portable target importing **nothing** (no
  Foundation, no `MetalUICore`; `package` API): an exact-area scanline
  rasterizer (nonzero and even-odd), an adaptive flattener (Wang's bound,
  0.1 device px), a stroker (caps, joins, miter limit, dashes), a triple box
  blur approximating a Gaussian with sigma = radius, and `PathMath.sinCos`
  (Cody–Waite reduction, fixed polynomial) so a path's bytes are the same on
  macOS, Linux and Windows. Declared on every platform; its tests run on Linux
  and Windows CI as a fourth portable target.
- **`MUITransform`**, a 64-byte per-scene affine record (a, b, c, d, tx, ty,
  `pixelScale`, the outer mask and its radii). **No stride moved**: the index
  rides in `MUIRect.shape`'s bits 8…31, `MUIImage.filter`'s bits 8…31 and
  `MUIGlyph._reserved` (renamed `transform`); index 0 is identity and never
  stored, so every earlier scene keeps its bytes and `Expected.swift` is
  unedited. `Scene.transforms`, `Scene.insert(_:layer:transform:)` (a nil
  insert clears a stale index), a shared zero record on the Metal renderer,
  `ReplayFixture` version 3 carrying the table, validated on SDL
  (`transforms_valid` refuses an index past the table).
- **Shaders**: `shaders.metal` and `Backends/SDL/Shaders/replay.hlsl` gain
  the same transformed branch for rects, ellipses, glyphs and images (index 0
  runs today's code), antialiased in screen pixels (`pixelScale`), cut by the
  outer mask in screen space.

**Lane 2 — render effects in `MetalUI`** (`GX-G`, `GX-H`, `GX-I`, `GX-P`,
`GX-T`, `GX-U`).

- `Angle`, `.rotationEffect(_:anchor:)`, `.scaleEffect(_:anchor:)` (scalar,
  `SizeD`, `x:y:`), `.offset(x:y:)`/`.offset(_:)` on both vocabularies: three
  `LayoutModifier` cases (one layer, one node, one identity level each) on the
  proposal path; on the legacy path they return `Self` and append to
  `Decoration.renderEffects` (written order kept among effects, always around
  the whole element — divergence 108).
- **One paint-scope stack** (`Frame.paintScopes`): transition groups, render
  effects and (lane 3) shadows; `TransitionEffect` became `RenderEffect`
  (alpha + affine), `CapturedPrimitive` a struct carrying an optional
  by-value `PrimitiveTransform` so ghosts and drag previews replay transformed
  content. An empty stack is today's fast path, pinned by a work counter.
- **Hit testing, hover, gestures, drag and drop follow the transform**
  (`Hitbox` stores its local rect, the inverse affine and the outer clip);
  accessibility frames are the transformed bounding box (divergence 107 for a
  non-right-angle rotation). A handler written after an effect shares it
  through `Frame.shareCandidates` under a **share floor** (`GX-U`: a `ZStack`,
  overlay or background between stops the share); a shared record's
  `visibleFrame` is the one the direct path computes.
- Animation at the layout phase (`AN-AB`), legacy effects on an
  `$anim-effects` store track; the reserved `StateTable` names stay seven.

**Lane 3 — `Path`, styles, shadows, demo, documents** (`GX-C`, `GX-D`,
`GX-E`, `GX-J`, `GX-K`, `GX-L`, `GX-Q`, `GX-V`).

- `Path` (a value type, a `Shape` and a view: move/line/lines/quad/cubic/two
  arcs/rect/rects/rounded rect/ellipse/path/close, `boundingRect`,
  `contains(_:eoFill:)`, `offsetBy`), `Shape.path(in:)` beside
  `geometry(in:)` (each defaulting to the other, a mutual-recursion trap
  naming `GX-D`), `ShapeGeometry.path`, `FillStyle`, `StrokeStyle`,
  `LineCap`, `LineJoin`; a stroke with a join, dash or cap beyond the plain
  band goes through the stroker, a plain width keeps the rounded-rect band.
- **A path is a vector until `insertIntoScene`**: `CapturedPrimitive.path`
  carries its outline, paint and a local map; at insertion the composed map
  decides the raster, always untransformed (index 0), cut by the outer mask
  with the local mask folded in. A window-owned `RasterCache` keyed by value
  (path, style, colour tint, affine, scale, clip) returns the same
  `ImageTexture` identity on a hit and drops untouched entries each frame.
- `.shadow(color:radius:x:y:)` on both vocabularies and `ColorToken.shadow`
  (black at 0.33 in both themes): **per leaf** (a text draw's glyphs are one
  leaf, an image or path is one), silhouette on the CPU from the leaf's
  alpha, blurred with sigma = radius, drawn immediately below the leaf, a
  shadow never hits and publishes nothing, a `Deferred` stops it as it stops
  an effect; radius/offset animate in layout, the colour in paint.
- The looks demo's Q section (its own function, Windows' 1 MB stack), frame 7
  of the replay-parity fixtures gains four `MetalUIPath` rasters, human
  checks group Q, `docs/api-overview.md`, `docs/migration.md`, the shapes
  spec §9 lifted, divergences 104–106 added (107–109 lane 2), 41/90/91/97
  amended.

## §2 Tests and guards, per file

Root suite **2124 → 2227** (+103: lane 1 +34, lane 2 +33 and its review
round, lane 3 +33 and its review round's three), guards **129 → 133**.

| file | tests | what it pins |
|---|---|---|
| `Tests/MetalUIPathTests/` `BoxBlurTests`, `PathMathTests`, `RasterizerTests`, `StrokerTests` | 2 + 2 + 8 + 6 | the blur's mass and profile, `sinCos` against a hashed corpus (1.26, bit-identical off Apple), exact-area coverage under both fill rules, caps, joins, dashes |
| `Tests/MetalUIRenderTests/TransformPrimitiveTests` | 13 | a transformed rect, ellipse, glyph, image and surface against their analytic coverage; the outer-mask and scaled-mask rules; the shared zero record; a nil insert clearing a stale index |
| `Tests/MetalUIRenderTests/SceneTests`, `ShaderABITests`, … | extended | the transform table, strides unmoved, the new field names |
| `Tests/MetalUITests/RenderEffectTests`, `RenderEffectHitTests`, `RenderEffectAnimationTests` | 18 + 12 + 2 | written-order composition on both vocabularies, hit testing under every effect, the share floor, accessibility frames, animation, the stack budget |
| `Tests/MetalUITests/PathTests`, `StrokeStyleTests` | 15 + 2 | `Path` geometry, styles, rasters under transforms, the cache's keys, hit testing by winding |
| `Tests/MetalUITests/ShadowTests` | 16 | the blur profile, per-leaf shadows, text as one leaf, clips, a shadow never hits, animation, the `Deferred` barrier, a fading transition |
| `Tests/MetalUITests/PathCompileGuards` | 3 guards | `G3.1` the path spellings from a plain import, `G3.2` `path(in:)`, `G3.3` the `shadow:` default |
| `Tests/MetalUITests/RenderEffectCompileGuards` | 1 guard | `G2.1` the effect spellings and the closed `LayoutModifier` |
| `Tests/MetalUITests/ShapeCompileGuards` | amended | `G2.1`'s control re-derived (`GX-D` defaults both requirements; the control is now the struct without `Shape` conformance) |
| `ThemeTests`, `CloseoutTests` | amended | `everyTokenDiffersBetweenLightAndDark` exempts `.shadow` by name; `F1.3` counts the I1 bitmaps only |

## §3 Probes

`docs/probes/swiftui-paths-shadows-transforms.swift` — arms **P1–P6**
(controls), **PA1–PA9** (fills, arcs, corners), **ST1–ST11** (width, caps,
joins, miter limit, dashes), **SH0–SH13** (the default colour, the blur's
sigma, per-leaf versus composited, text, opacity, nesting, clips),
**T0–T16** (anchor, order, flips, text re-rasterization, a diagonal under
`scaleEffect(4)`), **H1–H7** (hit testing), **X1–X6** (accessibility frames),
**N1–N10** (animation). Each family has a positive control and a separating
arm; the header carries the recorded output. Re-runs were not possible at
lane 3's close (screen locked); the recorded output stands from the design
session. Pre-existing probes were not re-run.

## §4 Red runs

Each lane's tests were written first against a compiling skeleton and
measured red: lane 1 against a skeleton with no transform branch; lane 2
(`267fd8e`) 31 tests; lane 3 (`53f18ac`, filtered to the lane's files, 65
tests) 26 of the 28 spec tests red, **green on arrival 3.5 (the built-ins'
SDF pin) and 3.21 (a shadow registers nothing — true of no shadow)** and the
three guards (each then mutated red). Lane 2's review round re-ran today's
`RenderEffectTests.swift` against `267fd8e`'s sources: `effectsComposeInWrittenOrder`
and `theLegacyVocabularyKeepsWrittenOrderAmongEffectsAndMovesNoID` red.

## §5 Mutation tables

Whole unfiltered suite each, `git status --short` clean after every restore.

**Lane 1** (on `53fa4c7`): glyph transformed branch drops the outer-mask
factor → `aTransformedGlyphAndImageAreCutByTheScreenOuterMask` (glyph arm);
the same in the image branch → its image arm; `mask_coverage_scaled` drops
`* s` → `aScaledContentMaskAntialiasesInScreenPixels`; glyph branch drops
`quad_edge` → `aTransformedGlyphAndImageAreCutByTheScreenOuterMask` (3
issues); `Scene.insert(MUIRect)` keeps a stale index on a nil insert →
`aNilInsertClearsAStaleTransformIndex`; per-frame `makeBuffer` of the zero
record → `aSceneWithoutTransformsReusesOneZeroRecord`; `SDLBridge.c`
`transforms_valid` drops its refusal → `aRecordNamingAMissingTransformIsRefused`
(6 issues; `Backends/SDL` 24 + 57 with one failing).

**Lane 2** (on `ad2c3f7`): MU1 (the share floor ignored) →
`aWrapperOverAZStackOrOverlayDoesNotShareAChildsEffect`; MU2 and V4 (a shared
record's `visibleFrame` untransformed) → `anAccessibilityRecordWrittenAfterAnEffectFollowsIt`,
`theAccessibilityFrameIsTheTransformedBoundingBox`; MU4
(`sharingRegistrationsWithEffects` without `passingShareFloorThrough`) →
`aTapWrittenAfterAnEffectHitsTheTransformedFrame`; MU6 (no
`enteringShareBarrier` in `Element.prepaintGroup`) →
`aWrapperOverAZStackOrOverlayDoesNotShareAChildsEffect`. **Green: MU5**
(`AnyElement`'s mirrored barrier removed): a scratch probe showed no tree can
reach that copy today (a legacy `.onTapGesture` sits on the element's own
handlers and pushes no share candidate; an `AnyElement` cannot sit under a
proposal sharing wrapper) — defensive, green is the right answer (§6).

**Lane 3** (on `a131187`): M3a (the path scaled into its frame) → 3.1, 3.25;
M3b (a fixed colour) → 3.2, 3.14; M3c (`path(in:)` handed the window rect) →
3.3 alone; M3d (the reentrancy check removed) → 3.4 alone (a stack overflow
with no message); M3e (every fill routed through the path) → a truncated run
with nineteen existing shape, overlay, background, border and preview tests
red first, 3.5 red in a supplementary filtered run; M3f (corner control arms
0.5 for 0.5523) → 3.6; M3g (`ShapeView` drops the `FillStyle`) → 3.7; M3h
(every stroke rasterized) → 3.8, 3.30, 3.5, `F1.3` and eight stroke/shape band
pins; M3i (`contains` its box) → 3.9; M3j (a path clip as its box) → 3.10;
M3k (raster at the local resolution, image transformed) → 3.11, 3.12, 3.14;
M3l (no cache) → 3.13, 3.14; M3m (colour, transform, clip or path dropped
from the key, four runs) → 3.14 each (the path's also 3.25); M3n (one
composited shadow after the content) → 3.15, 3.16, 3.22, 3.23, 3.26, 3.28;
M3o (no leaf group) → 3.16, 3.26; M3p (sigma = radius / 2) → 3.17, 3.24; M3q
→ 3.18; M3r (the leaf's alpha ignored) → 3.19; M3s (the silhouette ignores the
leaf's masks) → 3.20; M3t (the shadow's bounds registered as a hitbox) →
3.21; M3u → 3.22; M3v (offset unmapped) → 3.23; M3w (radius snaps) → 3.24;
M3y (legacy `.shadow` returns `self`) → 3.16, 3.26, 3.28; M3z → 3.27; M3aa →
3.28; **M3x not run** (no code interpolates a path to remove — 3.25 pins an
absence, discriminated by M3a and M3m-path). Guards: MG3.1 → G3.1, MG3.2 →
G3.2 then a trap at 3.3's recording shape, MG3.3 → G3.3.

**Lane 3 review round** (on `0ce3c77`/`0b26d57`, each green on the 2224-test
suite before): MV1 and MV1b (`Deferred` barrier for a shadow) →
`aDeferredStopsAnEnclosingShadow`; MV2, MV3 (legacy shadow colour and
`RenderEffectSpec.with(_:)`) → `aLegacyShadowsColourRadiusAndOffsetAnimate`;
MV4 (`withRenderEffect`'s shadow guard) → `aShadowNeverHitsChangesNoLayoutAndPublishesNothing`;
MV6, MV6b (a fading transition's `.path` / `.shadow` alpha) →
`aFadingTransitionScalesAPathsAndAShadowsAlpha`; MV8 (the non-antialiased fill
branch) → `evenOddFillStyleEmptiesTheRing`; MV9 (no shadow under a narrow entry
clip) → `aShadowIsCutByAnOuterClipAndShapedByAnInnerOne`; MV13 (`eoFill`
ignored) → `contentShapeOfAPathHitsByWinding`. Each reddened only its test.

## §6 Green mutations and pins that prove less than they look

- **MU5** (above): the `AnyElement` copy of the share barrier is unreachable
  today; `GX-U` item 3's "mirror per layer" rule keeps it. Mutate it again if
  a proposal sharing wrapper can ever hold an `AnyElement`.
- **3.5 and 3.21 were green on the skeleton** (§4): 3.5 pins the built-ins'
  SDF pixels (true before and after), 3.21's original arm is vacuous for a
  tree that draws no shadow — the review round added a window arm with a
  shadow on each vocabulary pushing 0 effect scopes.
- **M3x** is a pin of absence: nothing interpolates a path to remove, and
  3.25's discriminator is M3a/M3m-path, not its own mutation.
- **The census blind spot** (`GX-V` item 8): `nonisolated public` hides a
  declaration from `closeout-public-api.sh` and `closeout-undocumented.sh`;
  24 `Path` members were invisible until respelled `public nonisolated`. A
  future declaration with any leading modifier escapes both checks silently.
- **Stack budget** (`GX-U` item 5): the smallest thread that builds every
  production tree is **672 KB** at this branch and **also 672 KB at
  `dc96395`** (656 KB SIGBUS at both) — unmoved, inside 1 MB; the earlier
  "656 KB" figure was a 16 KB bisection artefact.

## §7 Demo comparison and looks

**0 differing pixels and identical scenes in all fourteen offscreen images
against `dc96395`** (`docs/probes/demo-pixels/compare.sh`), taken at lane 3 and
re-taken at the Record phase. No production tree uses a new API; the looks
demo's Q section is in none of the fourteen. `DemoFrameDeterminismTests`'
`Expected.swift` is **unedited**. The lock probe read
`CGSSessionScreenIsLocked = 1`, `displayAsleep main: 1` at lane 3's close, so
**no real-window capture and no demo launch**; the last unlocked reading
remains 2026-09-30.

**Owed, new here — group Q of `docs/verification/human-checks.md`, none
performed (an agent cannot)**: Q1 fills (nonzero versus even-odd stars, smooth
edges); Q2 strokes and dashes (round caps and joins, dashes following
corners); Q3 shadows in light and dark (soft, per leaf, glyph-shaped, no
box behind text; the dark theme's near-invisible default); Q4 rotated text and
image edges (legible glyphs, nearest squares inside antialiased outer edges);
Q5 crisp path versus soft text under `scaleEffect(3)` (divergence 106); Q6 the
rotating square (smooth 0.6 s turn, hover and click only over the drawn
diamond). SwiftUI's answers were measured in a real unlocked window by the
probe; MetalUI's are pinned headless (scene bytes, CPU rasters, hitboxes) and
nothing has been seen on a real display.

## §8 Hazards

- **A path whose `contains` ignores the fill rule** reddens only 3.9's even-odd
  ring; `Path.contains(_:eoFill:)` must stay in step with the rasterizer's rule.
- **An outside shape answering `geometry(in:)` with `.path` answers in the
  rect's own space** (window points), unlike `path(in:)`, whose local path the
  default `geometry(in:)` moves to the rect (`GX-V` item 16).
- **A shadow item's mask depth.** A shadow's own mask is the clip at its
  scope's entry, so its `innerMask` against an outer scope is read at that
  depth (`CapturedPrimitive.maskDepth`), not the emission depth.
- **A new `PlatformWindow`/renderer** needs the transform table: `ReplayFixture`
  version 3, `transforms_valid`, the shaders in both languages (`TE-AD`).
- **A path's image is always index 0** — rotated or scaled, the raster is
  made at the composed device resolution. A change that rasterizes locally and
  transforms the image reddens 3.11, 3.12, 3.14 (M3k) and makes paths soft.
- **A new text-drawing element** must bracket its draw with `beginLeafGroup`/
  `endLeafGroup` (through `Frame`'s emitters) or a shadow is one per glyph.
- **Windows 1 MB stack**: the Q section is its own function; 672 KB measured.

## §9 The Record phase's own close (2026-10-02)

- `git fetch`: `origin/master` still `dc96395`; nothing to merge, §73 stands.
- `swift package clean`, native build, unfiltered `swift test --build-system
  native --no-parallel`: 0 `error:`, **`Test run with 2227 tests in 3 suites
  passed after 120.362 seconds`**, the `FR-J no-argument frame: succeeded=true`
  line present.
- The fourteen-image comparison (`compare.sh <scratch> dc96395 HEAD`, HEAD
  `0b26d57`): every control at its recorded value (light vs dark 1048576,
  default vs modal 1031003, default vs animation 454895, prod default vs modal
  491221, 544/216/529 distinct values), **all fourteen `differing=0`, scene
  identical**.
- `GX-W` records this close; the decisions doc's next unused letter is `GX-X`.
- `zsh docs/probes/closeout-inventory-check.sh` and
  `zsh docs/probes/closeout-undocumented.sh` print nothing; census **2086**
  declarations in **105** inventory families (`paths`, `stroke-styles`,
  `shadows` added).
- `Backends/SDL` (`PKG_CONFIG_PATH=$PWD/.accesskit`) **24 + 57**;
  `Replay --portable --record` passes all 8 frames, frame 7 at 0 differing
  pixels on SDL's Metal backend (6 rects, 28 glyphs, 6 images, 9 transforms);
  `PortableReplay --expect 8` and `DemoCapture` pass; Linux llvmpipe and
  Windows D3D12 confirm on push. A `swift:6.4-noble` aarch64 container built
  with 0 `error:`/`warning:` at lane 3 and ran **199 + 22 + 21 + 31 + 18 + 6**
  (the last two the fourth portable target's and `MetalUICrossPlatformTests`'
  additions; unmoved by the Record phase's docs-only commits).

## §10 Counts, divergences and deferrals

**Counts: 2227 tests in 3 suites, 0 goldens, 133 typecheck guards**
(2124 + 103; guards 129 + 4), 0 `error:` on both build systems, the one
`warning:` SwiftPM's deprecation notice under native, 0 under the default
build; the `FR-J no-argument frame: succeeded=` line present. Divergences
**70 → 76 live, next label 110**: 104 (a shadow's leaves), 105 (the blur
profile), 106 (text and images resampled under an effect), 107 (an
accessibility frame under a non-right-angle rotation), 108 (legacy effects
against a legacy background or border), 109 (a clip between two nested
rotations) added; 41, 90, 91 and 97 amended; none retired.

**Deferred, owner none** (spec §9): `transformEffect`, `projectionEffect`,
`rotation3DEffect`; `Path.applying`, `transform:` parameters,
`addRelativeArc`, `trimmedPath`/`Shape.trim`, `strokedPath`, SVG strings;
`compositingGroup()`/`drawingGroup()`; inner shadows, `ShapeStyle` shadows,
`.blur(radius:)` (`BoxBlur` is ready); an analytic GPU shadow for rect leaves;
a shape's stroke width animating (97); text and images re-rasterized at an
effect's scale (106 — needs a quantized scale ladder with an evicting atlas);
`clipShape` of a path or ellipse (91); effects and `.shadow` on a `Component`
(`GX-P` item 5); gradients, SF Symbols, colour glyphs. **Owed to CI on push**:
Linux and Windows builds, `MetalUIPathTests` and the transform replay on
llvmpipe and D3D12.

## §11 Adversarial branch check (2026-10-02)

Re-taken independently over `dc96395..8141567`:

- After `swift package clean`, `swift build --build-system native --build-tests`
  gives 0 `error:`, and the one `warning:` is SwiftPM's deprecation notice.
  `swift build --build-tests` (the default build system) gives 0 `error:`
  and 0 `warning:`.
- The unfiltered `swift test --build-system native --no-parallel` prints
  `Test run with 2227 tests in 3 suites passed after 119.365 seconds`, and
  the `FR-J no-argument frame: succeeded=true` line is present.
- Guards: `enabled(if: canTypecheck` reads **132** across `Tests/` against
  128 at `dc96395`. Adding `theTypecheckGuardsRanWhereTheyAreRequired` gives
  **133**.
- `cmp CLAUDE.md AGENTS.md` is clean.
- **Two mutations of the checker's own**, each run as a full unfiltered
  suite, then restored with a clean `git status`:
  - **C1**: `Hitbox.contains` tests the window point against the local rect
    and skips `inverse.apply`. This reddens 6 tests:
    `aRotatedHitboxIsHitWhereItIsDrawn`,
    `aRotatedSquaresFrameCornerMissesAndItsTipHits`,
    `aTapWrittenAfterAnEffectHitsTheTransformedFrame`,
    `hoverAndGestureArenasFollowTheTransform`,
    `pointConsumersReadTheDeclarersLocalPoint` and
    `scaleAndOffsetMoveTheHitRegion` (16 issues).
  - **C2**: `Rasterizer`'s even-odd branch clamps the winding as nonzero
    does. This reddens 3 tests: `evenOddFillStyleEmptiesTheRing`,
    `nonZeroFillsASameDirectionRingAndEvenOddEmptiesIt` and
    `theRasterizerIsBitIdenticalEverywhere` (3 issues).
- `docs/probes/demo-pixels/compare.sh` from `dc96395` to `8141567`: all
  fourteen images read `differing=0` and the scenes are identical. The
  controls are unchanged from `dc96395`'s own values.
- `Replay --portable --record`: all 8 frames pass, and frame 7 has 0
  differing pixels with 9 transforms. `PortableReplay --expect 8` on SDL's
  Metal backend passes. `Backends/SDL` runs **24 + 57**.
- A `swift:6.4-noble` container builds with 0 `error:`/`warning:` and runs
  **199 + 22 + 21 + 31 + 18 + 6**.
- The census reads **2086**, and the inventory and undocumented checks print
  nothing.
- No identity, hit-testing, accessibility or animation test file outside the
  new ones was edited, and all of them stay green. Among them:
  `theSevenRetentionSlotsAreMutuallyDistinct`,
  `everyNamingSiteStartsAReturningNameFresh`,
  `everyBackgroundPaintingSiteAnimatesItsColour` and
  `aPresentationsContainingBlockIsTheWindowWhateverSurroundsIt`.
- The lock probe read locked (`displayAsleep main: 1`), so no real-window
  capture was taken. Group Q stays owed to a human.
- **Doc defects fixed**:
  - Spec test row 2.5 named two tests that do not exist. It now names the
    one test, `scaleEffectSizeEqualsXYAndOffsetSizeEqualsXY`.
  - In `Hitbox.swift`, `ContentShape`'s doc comment had been separated from
    its class by the new `HitboxTransform` declaration. It is now back above
    `ContentShape`, and the change is comment-only.

## §12 The LF-a fix: a clip inside a flattening effect (2026-10-09, `GX-X`)

Branch `fix/clip-in-flattening-effect` from master `67a579e`. MetalCreator's
gap **LF-a**: a `.clipped()` inside an `.offset` or a uniform positive
`.scaleEffect` forgot the clip outside the effect. Ruling `GX-X`.

**Cause, as found.** `GX-G` item 3 split the paint clip (`clipBase`) only at a
non-flattening scope's entry. Inside a flattening one `pushClip` intersected
the inner clip with the outer one in the content's pre-effect space, and
`RenderEffect.apply` moved that mask by the effect without cutting it by the
clip in force at the entry. The reporter's reading holds, and the same cause
has a second symptom it did not name: content laid out outside the outer clip
and moved into it got an empty mask and drew nothing. Prepaint always splits,
so hitboxes were right.

**Red run** (`d8c6e83`, filtered, native) — six issues in five tests:
- `aClipInsideAnOffsetIsStillCutByTheClipOutsideIt`: proposal mask
  `(80.0, 20.0, 40.0×40.0)`, legacy `(80.0, 20.0, 40.0×40.0)`; expected
  `(80.0, 50.0, 40.0×10.0)`.
- `aClipInsideAUniformScaleIsStillCutByTheClipOutsideIt`: proposal and legacy
  `(20.0, 20.0, 160.0×160.0)`; expected `(50.0, 50.0, 100.0×100.0)`.
- `aClipInsideNestedFlatteningEffectsIsCutByTheClipOutsideBoth`:
  `(80.0, 20.0, 40.0×40.0)`.
- `contentMovedIntoTheOuterClipByAnOffsetKeepsItsOwnClip`:
  `(50.0, 130.0, 40.0×0.0)`; expected `(50.0, 70.0, 40.0×40.0)`.
- `aRecordsOuterMaskInsideAnOffsetIsCutByTheClipOutsideIt`: outer mask
  `(80.0, 20.0, 40.0×40.0)`.
- `aHitboxInsideAnOffsetIsCutByTheClipOutsideIt` passed: a pin.

The first legacy arms put `.clipped()` on the legacy bar itself. They read
`(50, 50) 100 × 100`, because a legacy `.clipped()` clips an element's
children and not its own background. They now clip a `Box` around the bar.

**Fix.** See `GX-X` items 1 and 2: `Frame.flatteningClipBase`, the flattening
scope's entry clip kept as `outer`, and `Frame.cutToEntryClip` after `apply` in
`insertThroughScopes`. There is no scene, shader or record-format change, so
the SDL replay parity is not engaged.

**Mutations.** Each was run as a full unfiltered native suite, 2879 tests, and
then reverted. Besides the five pre-existing sheet failures below, each
reddened only:
- **M-X1** (`guard p.innerMask, false` in `cutToEntryClip`): the offset,
  scale and nested tests.
- **M-X2** (`firstInsideFlattening = false`): the moved-in test.
- **M-X3** (`guard p.outerMaskInner, false`): the record test.
- **M-X4** (prepaint: `if !map.isUniformPositiveScaleTranslation { clipBase =
  clipDepth }`): the hit pin's "moved in" arm.

**Suite.** `swift package clean`, then the native build (0 `error:`) and
`swift test --build-system native --no-parallel`: **2879 tests in 3 suites**,
5 issues. The `FR-J no-argument frame: succeeded=true` line is present.
Guards are unmoved at 185; no guard was added.

The five issues are the AppKit sheet tests in `AppKitPresentationTests`
(`appKitOpenDialogIsASheetWithTheDeclaredTypes`,
`appKitSaveDialogCarriesTheNameTypesAndExportPrompt`,
`appKitCancelledDialogArrivesAsQueuedInput`,
`appKitDismissPresentationEndsTheSheetAndAnswersNothing`,
`appKitSecondDialogWhileASheetIsUpAnswersFalse`). Each timed out at 61 s with
"no sheet attached". They are **pre-existing and environmental**:
- An unmodified `67a579e` full run fails the same five: 2873 tests, 5 issues.
- The five pass filtered on both commits.
- The screen read `CGSSessionScreenIsLocked=Yes`.

`swift build --build-tests` prints 0 warnings.

**Pixels.** `docs/probes/demo-pixels/compare.sh` from `67a579e` to `5d96c04`
(the fix): all fourteen images read `differing=0`, and every scene is
identical. No demo tree pushes a clip inside an `.offset` or `.scaleEffect`.

The controls at `67a579e` read:

| Control | Reading |
|---|---|
| light vs dark | 1048576 |
| default vs modal | 1031003 |
| default vs animation | 454895 |
| f0 vs f3 | 0 |
| preview light vs dark | 1048576 |
| chrome legacy vs proposal | 0 |
| distinct, default-light-f0 | 544 |
| distinct, chrome-legacy | 216 |

The two figures that differ from the script header's quoted values are the
baseline's own and were not caused by this change.
