# Backdrop blur behind a Material — design

C21 / C10-c (`LK-A`, `LK-L` item 4, record §85): `.background(.ultraThinMaterial)`
and the other five materials blur what is already drawn beneath them, GPU
surfaces (`MetalView`, `GPUSurface`) included, on both renderers. Requested by
MetalCreator (`/Users/maxburger/Developer/MetalCreator/docs/metalui-gaps.md`,
C10-a / M5-c: floating glass panels over a 3D `MetalView` viewport). Not a plan
task. Branch `feat/backdrop-blur` from `f2fe54a`; rulings `BB-A`… in
[`../2026-10-10-backdrop-blur-decisions.md`](../2026-10-10-backdrop-blur-decisions.md);
divergence labels reserved for this branch **245–254**; record §94 (written in
the Record phase).

Evidence: [`docs/probes/swiftui-backdrop-blur.swift`](../../probes/swiftui-backdrop-blur.swift)
(recorded output in its header, two byte-identical runs) and the unchanged
`swiftui-controls-looks.swift` arms `M1`/`M5`. Code inventory at `f2fe54a` below.

## 0. What the probe says (the numbers every ruling rests on)

| arm | finding |
|---|---|
| `S`, `S2`, `F` | `ImageRenderer`'s backdrop under a material is a smooth, near-Gaussian blur of **sigma 49–55 pt** (rms ≤ 0.021 where the tint leaves contrast), independent of image width. One constant: **52 pt**. |
| `E`, `E2` | the blur is (nearly) **clamped to the material's own shape**: black outside the rect darkens the interior edge pixel by only 0.06–0.12 of the full effect, 0 by 32–64 px. |
| `R` | outside a `Circle`/`RoundedRectangle` fill the backdrop is unblurred. |
| `N` | a material over a material blurs twice (rise 144.75 px vs 115.25). |
| `O` | `.opacity(0.5)` on a material = half-weight composite of the (blurred, tinted) layer over the **sharp** backdrop (arithmetic matched ±3). |
| `T` | Reduce Transparency: **inconclusive** (the swizzle reads true, pixels unchanged) — unmeasured. |
| `W` | **a real window shows no in-window blur**: the material samples what is behind the window (every x reads one value). SwiftUI's in-window answer exists only in `ImageRenderer`. |

## 1. Public API

SwiftUI's spelling and nothing new: `Material` and its six constants, the
`.background(_ material:)` sites and `Shape.fill(_ material:)` all exist
(`LK-L`) and **start blurring**. No new modifier, no new `Material` member. The
only public additions are the scene vocabulary a renderer needs:

- `MUIBackdrop` (C struct, `MetalUIShaderTypes`, imported as a Swift struct; §3).
- `PrimitiveKind.backdrop` (public break: an exhaustive `switch` outside the
  package adds an arm, as `.surface` did in `MV-C`; `docs/migration.md` row; a
  typecheck guard pins it).
- `Scene.backdrops`, `Scene.insert(_ backdrop: MUIBackdrop, layer:transform:)`,
  `Scene.backdropRegion(_:target:)` (§3.3).
- Every new public declaration owes a doc comment and a
  `closeout-inventory-map.tsv` row (class `M`: MetalUI-only); the census is
  re-recorded.

Build note: `MUIBackdrop`, `PrimitiveKind.backdrop` and `Scene`'s new stored arrays cross a module boundary, so every lane runs `swift package clean` after Step 0 lands (`BB-O` 5).

Deferred, named: a per-site blur radius override (owner none; MetalCreator may
re-request); `ProgressView` tint hook (unrelated to the renderer, not probed;
owner none); Reduce Transparency (§8, owner a platform-services follow-up).

## 2. Code inventory (f2fe54a)

- `Sources/MetalUI/Material.swift`: `Material.color` (a `Color(light:dark:)`
  of the `LK-L` table) is all the sites use: `ShapeView.swift:150,155,255,260`
  (`fill(material.color…)`), `Box.swift:944`, `NativeModifiedContent.swift:139`
  (`background(material.color)`).
- `Sources/MetalUIScene/Scene.swift`: `PrimitiveKind { rect, glyph, image,
  surface }`, one array + `Sequence` + `Layer` side array per kind, `finalize()`
  merges by `(layer, order, sequence)` and builds `drawList`; **the number of
  runs is the draw-call count**.
- `Sources/MetalUI/Transition.swift`: `CapturedPrimitive.Kind` (rect, glyph,
  image, surface, path, shadow, gradient, blur) — what transitions' ghosts and
  drag previews replay; `multiplyAlpha`, `RenderEffect.apply` are the two fade
  flattenings.
- `Sources/MetalUIRender/Renderer.swift` `encode(_:view:in:surfaces:)`: **one
  render pass into the drawable** (`loadAction .clear`), one instanced draw per
  run; `MetalWindowRenderer.finishFrame` runs the app's surface draws before it.
  The drawable is `framebufferOnly = true` (`MetalLayerSurface.swift:20`).
- `Backends/SDL/Sources/SDLBridge/SDLBridge.c` `mui_renderer_finish` (line 616):
  one render pass over `r->target` (the swapchain texture or the offscreen
  texture), a blit to the swapchain for offscreen (line 417). **A swapchain
  texture cannot be sampled** — hence the intermediate target.
- `Backends/SDL/Sources/ReplayFixture/ReplayFixture.swift`: version 3,
  `FixtureRun.Kind { rect, glyph, image }`, `init(scene:)` traps on `.surface`.
- Only `LooksDemo.swift:769` uses a `Material`, outside `demoContent()`, so the
  fourteen offscreen images cannot move.

## 3. Design

### 3.1 One primitive: blur + tint (`BB-A`, `BB-B`)

A material is **one scene primitive**, `MUIBackdrop`: the blurred backdrop of its
shape with the material's tint composited over it, shape-masked, with an
opacity. 96 bytes, six `float4` lanes (HLSL reads it as `primitives[base + i]`):

| lane | fields |
|---|---|
| 0 | `bounds` (`MUIBounds`) |
| 1 | `contentMask` (`MUIBounds`, the clip, as `MUIRect`) |
| 2 | `maskCornerRadii` |
| 3 | `cornerRadii` |
| 4 | `tint` (`MUIHsla`, resolved by `PaintPass.resolve`, straight alpha like a rect's `background`) |
| 5 | `order` (uint), `shape` (uint; bits 0–7 `MUIShape`, bits 8…31 transform index, exactly `MUIRect.shape`), `sigma` (float, **device pixels**), `opacity` (float) |

Output (premultiplied, source-over): `c · o · (T + (1 − T.a) · B)` with `c` the
rect-shader coverage (shape SDF × clip mask), `o` the opacity, `T` the premultiplied
tint, `B` the premultiplied blurred backdrop sampled at the fragment's device
position. This is exactly the probe-`O` arithmetic. When the renderer has no
blurred texture for a record (allocation failure, a size 0 region) it draws the
same quad through `backdrop_flat_fragment`: `c · o · T` = today's flat tint over
the sharp backdrop, so the fallback is today's pixels by construction.

Every material site stops calling `fill(material.color)` and calls
`Frame.fillBackdrop(…)`, which mirrors `Frame.fill`'s clip, transform, layer and
`CapturedPrimitive` handling and inserts one `MUIBackdrop`. The legacy decoration
(`Box.background(_:)`) carries the material in `DecorationExtras` (`LK-W` item 10:
a new stored `Decoration` property goes there), painted where the background fill
is.

### 3.2 Pass structure (`BB-C`)

- **A scene with no backdrop primitive takes the old path, byte for byte** (one
  pass into the drawable, no new texture, every new counter 0). The
  `VL-I`-style rule: a change to one branch leaves the other's pins unmoved.
- **A scene with backdrops renders into a frame target `F`** (`bgra8Unorm`,
  render + sample, device-pixel size of the drawable, per window renderer, cached
  and reallocated only on a size change) in **segments**: segment 0 clears
  transparent and draws draw-list runs up to the first backdrop run; at each
  `.backdrop` run the segment ends, every record of the run is blurred (§3.4),
  and a new segment (`loadAction .load`) begins with the run's quads and
  continues. After the last segment, `F` is copied to the drawable by a
  full-screen **copy draw** (Metal: `copy_vertex`/`copy_fragment`, no blend,
  nearest; SDL: `SDL_BlitGPUTexture` 1:1) — `framebufferOnly` stays `true`, the
  swapchain is never sampled, and both renderers use the same structure.
- GPU surfaces: `finishFrame` still runs the app's surface draws into their
  targets before MetalUI's first segment, and `.surface` runs are ordinary
  runs drawn into `F`, so **a backdrop below a surface run in scene order sees
  the surface** — the MetalCreator case. A surface drawn after the backdrop is
  not blurred (scene order is the semantics, as in SwiftUI).

### 3.3 Region and shared helper (`BB-D`)

`Scene.backdropRegion(_ index:target:) -> (x: Int, y: Int, width: Int, height: Int)?`
is **the one function both renderers call**: the record's bounds mapped by its
transform's bounding box, floor/ceil to integer device pixels, intersected with
the target, `nil` when empty. The blurred texture covers exactly this region;
the quad samples the level-`L` texture (a region of `w × h` is `⌈w/2^L⌉ × ⌈h/2^L⌉` there) at `uv = (devicePosition − origin) / (levelSize · 2^L)` (**amended by `BB-R`**: dividing by the region size instead is a `levelSize·2^L / size` scale error, up to 8 levels of a step at σ = 104), clamped to the
edge, so only the backdrop inside the region contributes (probe `E`). The
clip (`contentMask`) masks the quad but does not shrink the region
(`BB-D` item 5: cost accepted, named).

### 3.4 The blur (`BB-D`)

`sigma_dev = 52 pt × scale` (a constant; `MUIBackdropSigmaPoints`). Levels
`L = min(6, smallest L ≥ 0 with sigma_dev / 2^L ≤ 4)`. Steps, identical on both
shader languages:

1. `L` **downsample** passes, each a 2×2 bilinear fetch at the texel corner
   (region → `ceil(w/2)×ceil(h/2)` …), source level 0 is a bilinear/clamped
   read of `F` over the region.
2. A separable **Gaussian** at level `L`, `sigma_L = sigma_dev / 2^L`, taps
   `-⌈3σ⌉…+⌈3σ⌉` computed in the shader from σ (weights normalized in-shader,
   clamped edge), horizontal then vertical.
3. The quad's bilinear read of the level-`L` texture is the upsample, at texel coordinate `(p + ½)/2^L − ½` for the region pixel `p` (`BB-R`).

Scratch textures (two per level-size, `bgra8Unorm`, render + sample) come from
a per-window-renderer pool keyed by size and are reused across frames.
`BackdropBlurReference` (`MetalUIPath`, imports nothing, `package`) implements
the same algorithm in `Float` so tests have a ground truth on every platform.

### 3.5 Batching and cost (`BB-E`)

`Scene.finalize()` makes **a `.backdrop` run end where a backdrop's device
region intersects an earlier backdrop's in the run** (a later one must see the
earlier one) — and, as for every kind, wherever another kind interleaves in
z-order (a material's own children are drawn after it, so adjacent materials
usually break; a stack of side-by-side panels painting their backdrops
consecutively batches). Cost, counted as work:

- **splits** = backdrop runs (one segment break each);
- **blurs** = records;
- **blur passes** = Σ over records of `2L + 2`;
- **draws** = one per record for the quad (each binds its own blurred texture;
  an atlas of regions is deferred, `BB-E` item 4), plus the copy draw;
- frame-target copies = 1 for any backdrop frame, 0 otherwise.

Both renderers publish these as `lastBackdropSplits`, `lastBackdropBlurs`,
`lastBackdropPasses`, `lastFrameTargetCopies`, `lastBackdropTexturesMade`
(0 on a steady frame), pinned by tests, never wall time.

### 3.6 Everything that rides along (`BB-G`, `BB-H`)

- **Opacity and transitions**: `opacity` in the record; fade flattenings
  (`multiplyAlpha`, `RenderEffect.apply`) multiply it, **not** the tint alpha
  (that is `O`); a removal ghost and a drag preview replay the record and blur
  the live backdrop (a ghost does not freeze its blur).
- **Clips**: `contentMask` + `maskCornerRadii` exactly as a rect's.
- **Transforms** (`.offset`, `.scaleEffect`, `.rotationEffect`): the transform
  index in `shape`; the region is the transformed bounding box and the quad
  samples the screen-space blurred texture at its own device position, so a
  rotation costs nothing extra (clamped at the bounding box).
- **Shapes**: rounded rect and ellipse. A `Path` fill, and any other
  `Shape.geometry` that is a `Path`, draws today's flat tint rect (divergence 248).
- **Under `.blur`, `.shadow`, `.compositingGroup()` captures**: those rasterize
  leaves on the CPU, which cannot read a GPU backdrop: a backdrop leaf inside
  one draws its **flat tint** (the surface-leaf precedent, divergences 104/167;
  divergence 248).
- **Nested materials**: sequential in scene order; the second sees the first.
- **No change** to identity, state, hit testing (a material is not a hitbox),
  accessibility, focus, `List` windowing, `Deferred` (a deferred material is in
  the root layer's order like any primitive), text input.

## 4. Lanes (3, disjoint files; lane 1 lands the contract first)

**Lane 1 — scene and frame (agent order 1, must commit `Step 0` first).**
Step 0 (committed before lanes 2/3 start): `MetalUIShaderTypes` header
(`MUIBackdrop`, `MUIBackdropSigmaPoints`, `MUIBackdropBlurMaxLevel`),
`Sources/MetalUIScene/Scene.swift` (`PrimitiveKind.backdrop`, `backdrops`,
`insert`, `finalize`, `backdropRegion`, `isEmpty`, `clear`), and
`BackdropBlurReference` in `Sources/MetalUIPath/`. Then: `Material.swift`,
`ShapeView.swift`, `Box.swift`, `NativeModifiedContent.swift`, `Frame*.swift`
(`fillBackdrop`), `Transition.swift` (`CapturedPrimitive.backdrop`, both fade
flattenings), `Shadow.swift`/`Blur.swift`/`RasterCache.swift` (the degrade),
`Decoration.swift` (`DecorationExtras`), `LooksDemo.swift` (own function),
fakes in `Tests/MetalUITestSupport`, tests 1.x. Files lanes 2/3 never touch.

**Lane 2 — Metal.** `Sources/MetalUIRender/Renderer.swift`,
`MetalWindowRenderer.swift`, `Shaders/shaders.metal`, new
`BackdropBlurPipeline.swift`, `RenderSurface.swift` only if the frame target
needs it; tests 2.x in `Tests/MetalUITests/BackdropRenderTests.swift`.

**Lane 3 — SDL, replay, Linux.** `Backends/SDL/Sources/SDLBridge/SDLBridge.c`
(+ header), `SDLWindowRenderer.swift`, `Shaders/replay.hlsl` (+ compiled
outputs), `ReplayFixture.swift` (version 4), `SDLReplayer.swift`,
`PortableReplay/main.swift`, `Backends/SDL/Tests`, the Linux image run; tests 3.x.
Lanes 2 and 3 start after Step 0 and read the same `BackdropBlurReference`.

## 5. Tests (each: red before, mutation that must redden)

Every test reads its count with `try #require`; none sleeps; performance tests
count work. "Red before" = fails or does not compile at `f2fe54a`.

**Lane 1 (headless `Window` over `FakePlatformWindow`, root package):**

| # | test | red before | mutation (must redden it) |
|---|---|---|---|
| 1.1 | `aMaterialBackgroundEmitsOneBackdropRecordAndNoTintRect` | scene has a rect, no backdrops | `Material` site back to `fill(material.color)` |
| 1.2 | `theBackdropTintIsTheLKLTableForEverySchemeAndMaterial` | no record | swap two table rows in `Material.fill` |
| 1.3 | `theBackdropShapeIsTheFilledRoundedRectOrEllipse` | no record | encode an ellipse as `MUIShapeRoundedRect` |
| 1.4 | `aPathFilledWithAMaterialDrawsTheFlatTint` | n/a (passes) pins divergence 248 | emit a backdrop for a path |
| 1.5 | `opacityMultipliesTheRecordOpacityAndLeavesTheTintAlone` | no field | multiply `tint.a` instead |
| 1.6 | `aClipAndAnOffsetMapIntoTheRecord` | no record | drop `contentMask` |
| 1.7 | `aTransitionGhostAndADragPreviewReplayTheRecord` | no arm | make `multiplyAlpha`'s `.backdrop` arm return the record unchanged (deleting the arm does not compile, so it is not the mutation, `BB-O` 2) |
| 1.8 | `aMaterialInsideBlurShadowOrCompositingGroupDrawsItsFlatTint` | n/a | remove the degrade arm |
| 1.9 | `backdropRunsBreakWhereRegionsOverlapAndWhereAnotherKindInterleaves` | no kind | break on touching instead of intersecting |
| 1.10 | `aSceneHoldingOnlyABackdropIsNotEmptyAndClearForgetsIt` | no kind | drop `backdrops` from `isEmpty` |
| 1.11 | `backdropRegionIsTheTransformedBoundingBoxClampedToTheTarget` | no function | skip the clamp |
| 1.12 | `theReferenceBlurMatchesAnErfStepWithinTwoLevels` and `theLevelCountFollowsSigma` | no reference | `theLevelCountFollowsSigma` reddens on the `≤ 4` to `≤ 8` change (literal levels for three sigmas); the erf test is mutated separately by dropping the weight normalization (`BB-O` 3) |
| 1.13 | `anExhaustiveSwitchOverPrimitiveKindNeedsABackdropArm` (typecheck guard; mutate red once by deleting the arm from the fixture) | n/a | the guard's own mutation |
| 1.14 | existing `theSevenRetentionSlotsAreMutuallyDistinct`, the animation/identity guards | green | unchanged (a regression pin, not new) |

**Lane 2 (real Metal device; `renderOffscreen` + readback):**

| # | test | mutation |
|---|---|---|
| 2.1 | `aBackdropOverAStepEqualsTheReferenceWithinTolerance` (≤ 3 levels, 200×40, the three sigmas σ=16, 52 pt at scales 1 and 2) | halve σ in `backdrop_*` / skip the blur pass |
| 2.2 | `theBackdropBlursAGPUSurfaceBeneathIt` (red/blue stripes surface; backdrop above → purple; same scene with the backdrop below the surface in order leaves stripes sharp) | emit the backdrop run before the surface run |
| 2.3 | `aSceneWithoutBackdropsTakesTheOldPathByteForByte` (all counters 0, no frame target made, readback equal to the same scene rendered with the backdrop path forced off by the package test hook; the f2fe54a comparison is `compare.sh`, not this test, `BB-O` 4) | always route through `F` |
| 2.4 | `splitsCountRunsAndBlursCountRecords` (adjacent non-overlapping: 1 split, 2 blurs; interleaved: 2 splits; overlapping: 2) | count per record |
| 2.5 | `pixelsOutsideTheShapeAreUntouched` (circle) | ignore the shape SDF |
| 2.6 | `opacityHalfIsAHalfWeightCompositeOverTheSharpBackdrop` (±3 of the `O` arithmetic) | tint-alpha multiply |
| 2.7 | `aFailedBlurTextureDrawsTheFlatTint` (test hook fails the pool) equals the old pixels | draw nothing on failure |
| 2.8 | `nestedBackdropsBlurTwice` | blur both from one snapshot |
| 2.9 | `theClipCutsTheBackdropQuad` | ignore `contentMask` |
| 2.10 | `aSteadyFrameMakesNoTexturesAndAResizeMakesTheFrameTargetOnce` (`lastBackdropTexturesMade`) | allocate per frame |
| 2.11 | `theDrawableStaysFramebufferOnly` (source guard on `MetalLayerSurface`) | set `false` |
| 2.12 | `aClippedTransformedBackdropStaysInsideItsClip` (rotation) | skip the transform index |

**Lane 3 (Backends/SDL, root portable, Linux image):**

| # | test | mutation |
|---|---|---|
| 3.1 | `theBackdropABIIsTheOneTheShadersRead` (stride 96, six lanes) | pad the struct |
| 3.2 | `replayParityBackdropStepAndSurfaceFixturesMatchMetalWithinTolerance` (fixture v4, Metal recorded with `--record`, tolerance 3 levels) | change one HLSL tap weight |
| 3.3 | `sdlOffscreenBackdropEqualsTheReferenceAndCountsMatchMetal` | skip the HLSL downsample |
| 3.4 | `aFixtureRunRecordsABackdropAndStillTrapsOnASurface` | restore the trap for `.backdrop` |
| 3.5 | `sdlBackdropBlursAGPUSurfaceUnderIt` (`.enabled(if:)` a presenting driver) | draw before the surface |
| 3.6 | `theFixtureVersionIsFourAndOldVersionsStillLoad` | bump without the reader |
| 3.7 | Linux image build + tests, Windows via CI (and `metalui-win` if it answers) | — |

## 6. Gates

`swift build --build-system native --build-tests` 0 `error:`, 0 `warning:`
beyond SwiftPM's notice; unfiltered `swift test --build-system native
--no-parallel`, the one summary line, the `FR-J no-argument frame: succeeded=`
line; each new typecheck guard mutated red once; `docs/probes/demo-pixels/compare.sh
<scratch> f2fe54a HEAD` reads **0 px in all fourteen images** (the only material in
a demo is `LooksDemo`'s section, outside `demoContent()`);
`DemoFrameDeterminismTests` `Expected.swift` unedited;
`closeout-inventory-check.sh` and `closeout-undocumented.sh` print nothing;
`Backends/SDL` (macOS) and the Linux image build and pass; replay-parity harness
green on 8 + the new fixtures. Mutations: commit first, restore from a copy, full
unfiltered suite, `git status --short` after each, name every reddened test.

## 7. Demo expectation

`LooksDemo` gains `backdropBlurSection()` in its own function (Windows 1 MB stack;
`everyProductionTreeBuildsOnAOneMegabyteThread` already covers the composer):
red/blue stripes and a `Canvas`, with the six materials as panels over them. It
is reached only with `METALUI_LOOKS_DEMO=1`, so the fourteen images stay at 0 px
and `Expected.swift` is unedited. The GPU-surface case has no demo (it needs
`METALUI_METALVIEW_DEMO=1`; a panel over it is added to the existing MetalView
demo section's own function, same gating).

## 8. Honest scope

Built: the six materials blur on Metal and SDL; shapes rounded rect and ellipse;
clip, transform, opacity, transitions. Named and not built: Reduce Transparency
(unmeasured; needs two defaultless platform requirements per window, the
reduce-motion pattern; owner a platform-services follow-up; divergence 249),
saturation lift (divergence 246), per-site radius, a regions atlas (one quad
draw per record), backdrop inside CPU-rasterized leaves (divergence 248), a
real-window comparison (divergence 245; human check BB1), Windows D3D12 locally
(CI; the VM only if `ssh metalui-win` answers).

## 9. Human-checks additions (group BB, recorded in Record)

BB1: a panel over the MetalView demo — the viewport is blurred behind each of the
six materials, light and dark; compare against SwiftUI in a real window knowing
it blurs behind-window (divergence 245). BB2: drag a panel over moving content —
no tearing, no one-frame lag. BB3: nested panels. BB4: resize the window while a
panel is up — no stale blur. BB5: Windows (D3D12) and Linux sight. BB6: a fading
panel (transition) cross-fades with the live backdrop.
