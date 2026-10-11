# Backdrop blur — decisions

Rulings for C21 / C10-c: a real backdrop blur behind a `Material` on both
renderers (user request 2026-10-02, gpui-gap priority list; **not a plan
task**). Requested by MetalCreator (`/Users/maxburger/Developer/MetalCreator/docs/metalui-gaps.md`,
C10-a, M5-c). Supersedes `LK-L` item 4's deferral (record §85,
[`2026-10-08-controls-looks-decisions.md`](2026-10-08-controls-looks-decisions.md)).
Spec: [`specs/2026-10-10-backdrop-blur-design.md`](specs/2026-10-10-backdrop-blur-design.md).
Record: `../record/94-backdrop-blur.md` (Record phase). Branch `feat/backdrop-blur`
from `f2fe54a`; divergence labels reserved for this branch: **245–254**
(used: 245–249, planned below).

**Next unused id: `BB-P`.** (Moves in the commit that appends a ruling; read the
last `## BB-` heading, not this line, if they disagree.)

Evidence: [`../probes/swiftui-backdrop-blur.swift`](../probes/swiftui-backdrop-blur.swift)
(groups `P`, `S`, `S2`, `F`, `E`, `E2`, `R`, `N`, `O`, `T`, `W`; compiled form,
two byte-identical runs on an unlocked screen, `ImageRenderer` plus one
real-window arm); the code inventory in spec §2. gpui has no backdrop blur
(it has `blur` only as a shadow primitive); where SwiftUI is silent MetalUI's
own constraint is named.

## BB-A — One primitive, `MUIBackdrop`: the blurred backdrop and the tint together

**Ruling.** A material is one scene primitive of a new kind, `.backdrop`
(`PrimitiveKind.backdrop`, `Scene.backdrops`), composited `c · o · (T + (1 − T.a) · B)`
(premultiplied): `c` shape × clip coverage, `o` opacity, `T` the tint, `B` the
blurred backdrop. It is not a blurred-copy primitive followed by an ordinary tint
rect.

**Reasoning.** Probe `O`: `.opacity(0.5)` on a material is a half-weight composite
of the *whole* (blurred, tinted) layer over the *sharp* backdrop (x = 100: 226 =
(255 + 199)/2). A two-primitive stack faded per primitive gives backdrop weight
`½(1 − ½α)` where SwiftUI has `½(1 − α)` and destination weight `½(1 − ½α)`
where SwiftUI has `½` — for α = 0.71 the destination is 32 % instead of 50 %.
One primitive reproduces the arithmetic exactly with the existing fade
flattenings (`multiplyAlpha` multiplies `opacity`). It also makes the fallback
free: a record the renderer cannot blur draws through `backdrop_flat_fragment`
as `c · o · T`, which is today's flat tint (`LK-L`) pixel for pixel. Fitting the
tint into the record keeps `Material.fill`'s table the one source.

**Cost if wrong.** If a later effect needs the blurred backdrop alone (a frosted
image without a tint), a second record kind is added; `MUIBackdrop` keeps its
bytes (a tint of alpha 0 is that).

## BB-B — The record: 96 bytes, six lanes, `shape` is `MUIRect.shape`

**Ruling.** `MUIBackdrop` is `bounds`, `contentMask`, `maskCornerRadii`,
`cornerRadii`, `tint` (`MUIHsla`), then `order`, `shape`, `sigma`, `opacity` (four
words). `shape` carries `MUIShape` in bits 0–7 and the transform index in bits
8…31 exactly as `MUIRect` (GX-F); `sigma` is in **device pixels**; `order`
sorts like every kind. Defined once in `MetalUIShaderTypes` and compiled into
`shaders.metal` and read by `replay.hlsl` as six `float4` lanes; a stride test
pins both.

**Reasoning.** Reusing the rect's mask/shape/transform conventions lets the
fragment code share `maskCoverage`, `rect_sdf` and `ellipse` helpers, so a
clipped, rounded or transformed material matches a rect's edges by construction
(the `TE-AD` risk is the new arithmetic, not the edge). `sigma` is in the record
(not a shader constant) so the renderer, the reference and a future per-site
override read one number.

**Cost if wrong.** A field added later needs a lane; the stride test fails
loudly, as the rect's did for `GX-F`.

## BB-C — The old path is untouched; a backdrop frame renders into a frame target

**Ruling.** A scene with no backdrop primitive is encoded exactly as before: one
pass into the drawable, no new texture, every new counter 0. A scene with
backdrops renders into a per-window-renderer frame target `F` (`bgra8Unorm`,
render + sample, device-pixel size) in segments, ends a segment at each backdrop
run, and copies `F` to the drawable at the end with a full-screen copy draw
(Metal) or a 1:1 blit (SDL). The drawable stays `framebufferOnly = true`.

**Reasoning.** Alternatives: (a) `framebufferOnly = false` and read the
drawable: toggling a layer property per frame, a slower drawable on some GPUs,
and impossible on SDL, whose swapchain texture cannot be sampled — the two
renderers would diverge structurally (`TE-AD` and the replay harness need one
structure). (b) render *every* frame through `F`: costs every window a full-frame
copy, and moves the fourteen images' path. Chosen: the intermediate exists only
when needed and both renderers share its shape. A `F`-to-drawable copy is one
full-screen read + write per backdrop frame; counted, not timed
(`lastFrameTargetCopies`).

**Cost if wrong.** A window whose every frame has a panel pays the copy
forever; the follow-up is rendering the last segment straight into the drawable
(sample `F` only for the earlier blur sources), a change inside the renderers.

## BB-D — The blur: sigma 52 pt, clamped to the region, downsample + Gaussian

**Ruling.**

1. **Sigma 52 points** for all six materials, scaled to device pixels
   (`MUIBackdropSigmaPoints`). Probe `F`: fitted 49.1–55.1 pt in both schemes
   wherever the tint leaves contrast (rms 0.008–0.021); light thick/ultraThick
   are low-contrast (rms 0.08/0.17) and ignored. No per-material table: the
   spread (±3 pt) is inside the plateau-bleed error (E2: 5–12 %, so ±10 %) of the
   fit itself.
2. **Algorithm** (identical in MSL and HLSL): `L` bilinear 2× downsample passes
   until `sigma_dev / 2^L ≤ 4` (`L ≤ 6`), a separable Gaussian at level `L` with
   taps `±⌈3σ⌉` and weights computed and normalized in the shader, then the
   quad's bilinear read as the upsample. A true Gaussian at 104 device px would be
   ±312 taps; the pyramid costs `2L + 2` passes over shrinking textures.
3. **Region**: the transformed bounds' integer bounding box ∩ target
   (`Scene.backdropRegion`, the one shared function), edge-clamped. Probe `E`/`E2`:
   SwiftUI's backdrop is nearly clamped to the shape (outside black moves the edge
   pixel by 0.06–0.12 of the full effect, 0 by 32–64 px); clamping to the bounding
   box differs from it by that small bleed and from a rounded corner by a clamp at
   the box, not the curve (divergence 247).
4. **A reference** (`BackdropBlurReference`, `MetalUIPath`, imports nothing,
   `package`) implements the same algorithm in `Float`; tests compare readbacks to
   it (tolerance 3 levels, the replay harness's) and it is checked against an `erf`
   step within 2 levels (1.12), so the algorithm's own error is measured, not
   assumed.
5. **The clip does not shrink the region.** A material under a tiny clip still
   blurs its whole bounds: the cost is bounded by the material's size, and a
   region that varied with the clip would change the blur as the clip moves.
   Named, not hidden.

**Reasoning.** `ImageRenderer` is the only SwiftUI instrument that shows an
in-window blur at all (`W`); its answer is the only one to fit. 52 pt is large
(a 104 px kernel at 2×); the pyramid keeps it to a few passes over small
textures. Saturation lift (`M1`: SwiftUI's green rises where the stripes have
none) is not modelled (divergence 246).

**Cost if wrong.** If a real window's tint over a blur differs from `LK-L`'s
table, the table is refit from a window capture (human check 8 already owes it);
the constant moves in one header line and the reference with it.

## BB-E — Batching: a split per backdrop run, a draw per record, counted

**Ruling.** `Scene.finalize()` ends a `.backdrop` run where a record's device
region intersects an earlier record's in the run (a later material must see an
earlier one — probe `N`) and, as for every kind, where another kind
interleaves. Per run: one split (segment break) and, per record, one blur chain
and one quad draw. An atlas of regions to draw a run in one instanced call is
**deferred** (owner none; records per frame are few). Both renderers expose
`lastBackdropSplits`, `lastBackdropBlurs`, `lastBackdropPasses` (Σ `2L + 2`),
`lastFrameTargetCopies`, `lastBackdropTexturesMade`; pins count these.

**Reasoning.** A material's own children paint after it, so adjacent *panels*
interleave with their content and mostly cost a split each; batching consecutive
non-overlapping backdrops only helps a tiled layout. Breaking on intersection is
the only correctness condition. Counters, not clocks, per the practices.

**Cost if wrong.** Many small materials (a list of glass rows) cost
`records × (2L + 2)` tiny passes and a split each: the follow-up is the atlas and
reordering independent materials, owned by whoever measures it.

## BB-F — SwiftUI's answer is two answers; MetalUI follows the in-window one

**Ruling.** Probe `W`: in a real window (opaque or clear, `NSHostingView`) a
SwiftUI `Material` shows no in-window blur — every sampled x of a black|white step
reads one value, the window-behind backdrop; `ImageRenderer` (probes `S`–`O`) blurs the
in-window content. MetalUI implements the in-window behaviour, which is what the
user wants (glass over an in-window viewport) and the only measured one;
**divergence 245** records both halves: SwiftUI-in-a-window blurs behind the
window, MetalUI blurs its own window's content, and the tint table (`LK-L`,
fitted from uniform backdrops) is unchanged, so the flat-backdrop pixels still
match within one level.

**Reasoning.** A claim of "SwiftUI blurs X" needs a probe run now. The honest
reading is that SwiftUI differs by instrument; the divergence says so rather than
choosing the convenient one silently. A window capture by `docs/probes/window-capture`
(unlocked) is the instrument for the tint; it is a Record-phase human check.

**Cost if wrong.** If the real-window material is later found to blur in-window
content in some configuration (a sibling `NSVisualEffectView` blending
mode), only the divergence text changes.

## BB-G — Opacity, transitions, ghosts and drag previews

**Ruling.** `opacity` in the record is multiplied by `multiplyAlpha` and
`RenderEffect.apply`; tint alpha is never touched (BB-A). `CapturedPrimitive`
gains `.backdrop(MUIBackdrop)`, owed an arm in both fade flattenings, in
`bounds`, `screenBounds`, `maskDepth` and replay. A removal ghost and a drag
preview replay the record and so blur the **live** backdrop at their place; a ghost
does not freeze its blur.

**Reasoning.** Freezing needs a snapshot texture per ghost: more state, no
measured demand. A fading material over a changing backdrop looking live is the
same as SwiftUI's. `CapturedPrimitive.Kind` already requires an arm for each new
kind (LK-U); the compiler finds the omissions.

**Cost if wrong.** A ghost over an animating backdrop shows the new blur, not
the old one: invisible at transition durations.

## BB-H — Shapes, clips, transforms, and where a material degrades to its flat tint

**Ruling.** Supported: rounded rectangle and ellipse (`MUIShape`), the clip stack
as `contentMask`/`maskCornerRadii`, render effects (`.offset`, `.scaleEffect`,
`.rotationEffect`) by the transform index with a screen-space region. **Degrades
to today's flat tint rect (divergence 248):** a `Path` fill or any
`Shape.geometry` that is a `Path`; a material leaf captured inside `.blur(radius:)`,
`.shadow`, `.compositingGroup()` (CPU-rasterized leaves cannot read a GPU
backdrop; the surface-leaf precedent, divergences 104 and 167). A material inside
a `Deferred` blurs what is drawn before it in the root layer's order.

**Reasoning.** Rect and ellipse are the shapes the rect shader's SDF handles
(`TE-AD`: no new silhouette arithmetic). A path would need coverage from the CPU
raster as a mask: possible later (a path's mask is already an `ImageTexture`), not
asked for. The degrade is by name and pinned (tests 1.4, 1.8), never a silent
approximation.

**Cost if wrong.** A glass panel with a path outline looks flat; MetalCreator's
panels are rounded rectangles.

## BB-I — Fallbacks and what is not built: allocation failure, Reduce Transparency

**Ruling.** A record whose region is empty, or whose blur textures cannot be
allocated, draws through `backdrop_flat_fragment` (today's flat tint, BB-A); the
frame-target allocation failing draws the frame by the old path (no backdrop
records encoded). **Reduce Transparency is not honoured** (divergence 249):
probe `T` was inconclusive (swizzled getter read true, `ImageRenderer` pixels
unchanged), so SwiftUI's behaviour is unmeasured and MetalUI would be guessing;
and it needs two defaultless `PlatformWindow` requirements and honest AppKit/SDL/
fake implementations (the reduce-motion pattern) — a platform-services item, not
a renderer one. Owner: a follow-up named in the record; the flat fallback it would
select already exists.

**Reasoning.** The fallback path is the reason BB-A merged blur and tint; the
accessibility setting is a different seam and deserves its own probe first.

**Cost if wrong.** Users with Reduce Transparency still see the blur until the
follow-up; the setting is one switch onto an existing path.

## BB-J — Replay parity: fixture version 4, one tolerance, the surface case

**Ruling.** `ReplayFixture` becomes version 4: a `backdrops` byte array and
stride (`MUIBackdrop`, 96), `FixtureRun.Kind.backdrop = 3`, and `FixtureRun(scene:)`
records a backdrop (still trapping on `.surface`, `MV-C`); older versions still
load. Replay renders segments into `F` as the renderers do. Parity: the Metal
renderer's recorded pixels against the SDL replay within the harness's existing
tolerance (3 levels), over three new fixtures — step under a material, rounded
rect with a clip, two nested materials. A GPU-surface backdrop is tested in
each renderer against the reference (2.2, 3.5), not through a fixture
(a fixture cannot hold a surface).

**Reasoning.** `TE-AD`: a new drawable capability lands in `shaders.metal` and
`replay.hlsl` identically, checked, or is a documented constraint. The pyramid is
bilinear on both; the one numerical difference is MSL vs HLSL `exp` in the
weights, inside tolerance by design (weights normalized).

**Cost if wrong.** If WARP/D3D12 differs beyond tolerance, the weights are
computed on the CPU into the record's side buffer (the shaders then read data, not
`exp`); the structure is unchanged.

## BB-K — How tests drive it headless

**Ruling.** Lane 1 inspects the finalized `Scene` of a `Window` over
`FakePlatformWindow` (records, kinds, runs, regions). Lanes 2 and 3 render
offscreen (`Renderer.renderOffscreen`, `SDLPlatform(offscreenRenderers:)`) and
read back, comparing to `BackdropBlurReference`. A test hook on the
renderer's pool (`package`) makes allocation fail for 2.7 and counts textures for
2.10. Counters are plain integers, read after one frame. No test sleeps.

**Reasoning.** The reference makes the shader's arithmetic checkable on every
platform; the Linux image has no presenting window, so renderer tests use the
offscreen seam (`TF-C`).

**Cost if wrong.** A reference that shares the shaders' misreading of the
algorithm passes wrongly: 1.12 compares it to an `erf` step independent of both.

## BB-L — Lanes and files

**Ruling.** Three lanes, disjoint files, lane 1 first: Step 0 commits the header
struct, `Scene`, `backdropRegion` and `BackdropBlurReference`; then lane 1 (frame
and sites), lane 2 (`MetalUIRender` + `shaders.metal`), lane 3 (`Backends/SDL`,
`replay.hlsl`, fixtures, Linux image) run in parallel. Off-limits (other
branches): `feat/overlays-coords` (C15, `OV-`, 225–234), `feat/input-followups`
(C16, `IF-`, 235–244), `feat/test-harness` (item 8, §91); this branch edits no
`Window.swift` input hook, `Popover.swift`, `Tooltip.swift`, `Gesture*.swift`,
`ContextMenu.swift`, `Platform.swift`. `CLAUDE.md`, `AGENTS.md`, `README.md`, the
plan and `docs/record/` change only in the Record phase.

**Reasoning.** The three lanes touch Swift/MSL in `Sources/`, Swift/MSL in
`MetalUIRender`, and C/HLSL/Swift in `Backends/SDL`; only the shader-types
header and `Scene` are shared, and Step 0 freezes them.

**Cost if wrong.** A lane that needs a Step 0 field not there amends it by a
dated ruling and tells the others.

## BB-M — Pixels, demo, human checks, divergences

**Ruling.** The fourteen offscreen images stay **0 px** against `f2fe54a`
(`compare.sh`): the only `Material` in a demo is `LooksDemo`'s section, outside
`demoContent()` and the chrome pair, and a no-backdrop scene takes the old path
(BB-C). `DemoFrameDeterminismTests`' `Expected.swift` is unedited. The new
section `backdropBlurSection()` sits in its own function. Human checks BB1–BB6 (spec
§9). Divergences, labels from 245: **245** SwiftUI's real-window material blurs
behind the window, MetalUI's blurs its window's content (BB-F); **246** no
saturation lift (BB-D); **247** the region is the shape's bounding box, edge-clamped,
SwiftUI bleeds a little from outside the shape (BB-D); **248** a material in a
`Path` fill or inside a CPU-rasterized leaf effect draws its flat tint (BB-H);
**249** Reduce Transparency not honoured (BB-I). `250`–`254` unused. `LK-L`'s
divergence 166 is **amended** in the Record phase (the flat tint remains only in
the degrade cases); its pin
`everyMaterialMatchesSwiftUIOverWhiteAndBlackM5` is re-pinned on the flat
fallback record (`backdrop_flat`) and on the blurred result over a uniform backdrop.

**Reasoning.** Zero-pixel movement is the acceptance criterion every renderer
change carries; the divergence list is what the code does not do, by name.

**Cost if wrong.** A demo that turns out to paint a material in one of the images
reads a nonzero delta; the ruling then names it and records the delta.

## BB-N — Out of scope: the `ProgressView` tint hook

**Ruling.** Not built. It is unrelated to the renderer, was not probed, and the
spinner's colour follows the control accent today (`LK-F`); owner none.

**Reasoning.** "Low priority if cheap": probing SwiftUI's `ProgressView` tint
semantics is its own item, not a by-product of this one.

**Cost if wrong.** MetalCreator keeps its current spinner colour.

## BB-O — Critic review of the committed design: what was changed, what was rejected

**Ruling.** The critic re-ran probe arms `P1`, `P3`, `S light regular`, `N1`, `O1`
byte for byte against the header (all equal); the SwiftUI claims rest on them.
Changes: (1) none to the primitive, pass structure or lanes: attacked and held
(F cleared transparent equals the old pass's clear, `Renderer.swift:199`, so segment 0
is the old pixels; no platform requirement, so no default or fake owed; the
renderer counters are concrete-type reads). (2) Test 1.7's mutation named
"delete the arm" cannot compile; the mutation is the arm returning the record
unchanged. (3) Test 1.12's mutation named one test; each of its two tests now
has its own mutation. (4) Test 2.3 compared to an unnamed "pre-change" scene;
it now compares to the same scene with the backdrop path forced off, and the
f2fe54a claim belongs to `compare.sh`. (5) Step 0 adds stored properties on a
public type across a module boundary: `swift package clean` in each lane.
(6) Reduce Transparency and the `ProgressView` tint hook have **no owner**: they
are open items for the human (a rejection of scope, not a hidden deferral).
**Rejected:** a per-material sigma table (BB-D 1: the spread is inside the fit's
error); nested "blurs twice" is pinned against the reference, not against the
probe's 1.26 rise ratio, which tint compression distorts.

**Reasoning.** Each change makes a pin able to go red; none moves a pixel.

**Cost if wrong.** None to the design; a mutation that still does not redden is
reported by the lane that applies it.
