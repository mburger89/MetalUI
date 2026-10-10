# Shadow cache — decisions

Rulings for C13 / PERF-a: the CPU raster cache that misses on every move, one
shadow per container, and a faster portable blur (user request 2026-10-02,
item C13 of the gpui-gap priority list; **not a plan task**). Reported by
MetalCreator (`/Users/maxburger/Developer/MetalCreator/docs/metalui-gaps.md`,
"Node-drag performance, 2026-10-08", PERF-a, measured on MetalUI `dc6528c`).
Spec: [`specs/2026-10-09-shadow-cache-design.md`](specs/2026-10-09-shadow-cache-design.md).
Record: `../record/90-shadow-cache.md` (written in the Record phase).
Branch `perf/shadow-cache` from `2155f1e`; divergence labels reserved for this
branch: **205–214**.

**Next unused id: `PF-O`.** (Moves in the commit that appends a ruling; read
the last `## PF-` heading, not this line, if they disagree.)

Evidence (each header carries its recorded output and how to run it):

- [`../probes/swiftui-shadow-cache.swift`](../probes/swiftui-shadow-cache.swift)
  (**new**; groups `P` positive controls, `CG` `compositingGroup()`, `SP` shift
  invariance and sub-pixel placement; compiled form run twice, 25 lines
  byte-identical, `ImageRenderer` only, no window).
- [`../probes/swiftui-paths-shadows-transforms.swift`](../probes/swiftui-paths-shadows-transforms.swift)
  arms `SH3` (sigma = radius), `SH5`/`SH5c` (per leaf; `compositingGroup()`
  composites), `SH11` (a nested shadow is a leaf) — re-run as `P1`/`P2` here.
- The code inventory below (2155f1e), and MetalCreator's measurements (counts
  exact, timings ±20 %): moving one shadowed node blurs 500,904 px,
  rasterizes 231,177 px and makes 9 new textures per frame; a release
  `sample` puts ~70 % of the frame in `BoxBlur.blur`, ~14 % in
  `RasterCache.tint`.

Code inventory (2155f1e) — why every move misses:

- `Frame.shadowImage` (`Sources/MetalUI/Shadow.swift`) keys coverage on `full`
  (the composed affine, translation included), `RasterPlacement.keyed` (the
  absolute device `clip`, plus the local mask) and `keyLeaf` (every leaf
  primitive's **absolute** device bounds and content masks). A layout move
  changes the leaf bounds; a render-effect move (`.offset` outside the shadow)
  changes `full`; a pan changes both. `Frame.blurImage` (`Blur.swift`,
  `LK-K`) shares `keyLeaf` and `placement.keyed` — same misses.
  `Frame.pathImage` (`RasterCache.swift`) and `Frame.gradientImage`
  (`GradientRaster.swift`, `LK-J`) key the outline by value (control points in
  window points, absolute) plus `full` — same misses. The gradient strip keys
  its absolute device `origin`/`start`/`end`.
- `RasterCache.endFrame` drops every entry a frame did not touch (`GX-K`), so
  a miss never meets an older entry again.
- `RasterCache` already counts `lastRasterizedPixels`/`lastBlurredPixels`; it
  does not count textures made.
- `BoxBlur.blur` (`Sources/MetalUIPath/BoxBlur.swift`): `[Int]` buffers,
  checked subscripts, six full-buffer passes with `swap`, a strided vertical
  pass (cache-hostile), and a final `map` with clamping. `RasterCache.tint`,
  `RasterMath.multiply/crop`, `AlphaCompositor.union`: checked per-pixel
  loops.

---

## PF-A — Translation-free raster keys: a canonical anchor, the raster a pure function of the key

*Amended by the critic: PF-I (masks) amends item 1. Amended by lane 1: PF-M (nested content re-anchors) amends item 1.*

**Ruling.**

1. Every CPU raster that today keys absolute positions — the shadow
   (`shadowImage`), the blur (`blurImage`), the path (`pathImage`) and the full
   gradient raster (`gradientImage`'s non-strip branch) — is computed and keyed
   in **canonical coordinates**:
   - **Anchor `R`**, in the raster's creation space: the content's minimum
     corner floored to that space's device-pixel grid. A shadow's or a blur's
     leaf is in device pixels (grid 1); a path's or gradient's outline is in
     points under `local = scale · s + offset`, grid `1/s` when `s` is a power
     of two (1, 2, 4), else grid 1. On that grid `x − R` is exact in `Float`
     and `Double` for every coordinate the window can hold.
   - **Canonical content**: the leaf (or outline) translated by `−R`. For a
     shadow/blur leaf that is every creation-space quantity: rect, glyph,
     image and surface bounds and content masks; a path's, gradient's,
     nested shadow's and nested blur's `local.tx/ty` and content mask (their
     own content stays in their own space under `local`); a primitive's own
     `PrimitiveTransform` is **conjugated** (`T(−R)·A·T(R)`, its local bounds
     `− R`, its outer mask `− R`). For a path/gradient: the `PathGeometry`
     translated by `−R` (a new `package` `PathGeometry.translated(dx:dy:)`).
   - **Device anchor** `D = full(R)`, `S = ⌊D⌋` (integers), `f = D − S` (exact).
     The canonical map is `full' = (linear part of full, translation f)`.
   - **Key** = the existing key fields computed on the canonical content, plus
     `full'` (bit patterns) and the mode word of `PF-B`. **No absolute
     coordinate enters the key.**
   - The raster is made **from the canonical values only**, then placed at
     `+S` (the image quad's origin, the mask rect). So the bytes are a pure
     function of the key: a hit draws exactly what a fresh frame at that
     position draws (history-independent, test L1.4), and `GX-K`'s rule —
     "every number that decides a coverage byte is in the key" — still holds.
2. A cache hit hands back the same coverage, the same tinted `ImageTexture`
   (shadow, path) or the same colour `ImageTexture` (blur, gradient) — the
   identity `TE-AF` uploads once. Colour stays in the tint key (`GX-K`), so a
   colour animation still re-tints without re-rasterizing.
3. **Whole-pixel moves and pans hit**: a layout move, an outer `.offset`, a
   parent's padding or position change by a whole number of device pixels
   (1 point at 1×, 0.5 point at 2×) moves `R`, `D` and `S` by that integer and
   leaves the canonical content and `f` bit-identical. Under a non-translation
   outer effect (rotation, non-uniform scale) or a primitive with its own
   transform, `f` and the conjugated affine are computed in floating point and
   may differ in the last bits between positions: those **may miss**
   (correct, just not cached; named, spec §9 D5).

**Evidence.** The inventory above (every key holds absolute positions).
`SP1`/`SP4b`: SwiftUI's shadow moved by 1 or 7 whole pixels is
pixel-identical, moved — a shifted cached raster is SwiftUI's answer. The
rasterizer already works in coordinates relative to its output rect
(`CoverageRasterizer.rasterize` subtracts `rect.x/y`), so an integer device
shift is invisible to it when the inputs are exact.

**Cost if wrong.** A key that omits a field the canonical raster depends on
draws a stale raster after a move (wrong pixels, silently). Guarded by L1.4
(hit bytes = fresh bytes, at a non-integer move that separates) and L1.5
(canonical = absolute, shifted). A canonicalization that is not exact makes
whole-pixel moves miss (performance only) — guarded by L1.1/L1.2/L1.7/L1.8.

## PF-B — Unclipped when the raster lies inside its clip; today's clipped raster otherwise

*Amended by the critic: PF-J (conservative extent, today's clip shifted) amends items 1–2.*

**Ruling.**

1. Let `E` be the raster's full device extent at its position: the enclosing
   integer rect of the content's device bounding box (for a shadow, the leaf
   union moved by the mapped offset), grown by `BoxBlur.padding(sigma)` on
   every side for a shadow or a blur. When **`E ⊆ placement.clip`** (the
   common case — a node fully on screen inside its panel) the raster is made
   over the canonical `E − S` with **no clip in the key**: any whole-pixel move
   that keeps it inside the clip hits.
2. Otherwise (the content is cut by its clip, the window edge, or a mask
   pushed inside a non-flattened effect) the raster is made exactly as today,
   inside `placement.clip − S` in canonical coordinates, and that relative clip
   is **in the key**: a move relative to the clip misses, as at 2155f1e. No
   crop-after-lookup (spec §9 D2).
3. **The local-mask case keeps today's absolute key unchanged**:
   `RasterPlacement.localMask != nil` (a clip pushed inside a rotation or
   non-uniform scale) is keyed and rasterized exactly as at 2155f1e (spec §9
   D3).
4. Because `E ⊆ clip` means today's crop to `clip` was the identity on the
   blurred mask, mode 1 makes the same mask rect and image bounds as today;
   mode 2 is today's code path. **Every existing pin holds**: `3.20`
   (`aShadowIsCutByAnOuterClipAndShapedByAnInnerOne`: cut bounds), `3.14`
   (`theCacheKeyIncludesColourTransformAndClip`: a clip that cuts re-rasterizes),
   `3.12` (`aDiagonalOrClippedGradientRastersInFull`: 2000 px clipped).

**Evidence.** The three tests named; `RasterPlacement`'s GPU mask
(`imageMask`) still cuts every image exactly, so pixels are unchanged in both
modes.

**Cost if wrong.** A raster made unclipped while cut would show pixels past
the clip only if the GPU mask failed — it does not — but would change image
bounds and work counts (3.20, 3.12 redden). Nodes straddling a panel edge
still miss on every move (performance only, D2).

## PF-C — Bit-identity: canonical rasters equal today's absolute rasters, byte for byte

*Amended by the critic: PF-K item 1 amends item 1 (the run.sh fixture). Amended by lane 1: PF-N amends items 2–3 (measured).*

**Ruling.**

1. The binding pixel criteria are: 0 px in the fourteen offscreen images
   (`docs/probes/demo-pixels/compare.sh`), **and** 0 px in the looks-demo and
   drag-sequence images of the new `docs/probes/shadow-cache/run.sh` against
   2155f1e (the fourteen images contain **no shadow, no blur and no gradient** —
   `demoContent()` names none; a 0 there proves only that paths are
   untouched), and `DemoFrameDeterminismTests`' `Expected.swift` unedited.
2. Test L1.5 compares the canonical raster with the absolute one (the
   2155f1e call, `shadowCoverage(paint, full:, clip:)` etc. at the absolute
   position) on fixtures at integer, dyadic and non-dyadic positions, scales 1
   and 2: **expected 0 differing bytes**.
3. **Contingency** (pre-ruled, so the implementer does not improvise): if a
   non-dyadic fixture whose outline has curves (rounded rect, ellipse, glyph
   resample) differs — `Flattener` and the bilinear resample evaluate in
   absolute coordinates today, and rounding at 1e−13 can flip a byte that sits
   exactly on a rounding boundary — the implementer records the differing
   count and the maximum delta in the record, L1.5 pins **dyadic fixtures
   exact and non-dyadic ones `max |Δ| ≤ 1`**, and the run.sh images must still
   read 0 (they are whole-point layouts). Any larger delta, or any pixel in the
   fourteen or the looks images, stops the lane: the canonical transform is
   then wrong, not rounding.

**Cost if wrong.** A silent sub-LSB drift between a cold and a warm frame is
impossible by construction (PF-A item 1: the bytes are a function of the
key); the only drift is canonical vs 2155f1e, measured here.

## PF-D — Sub-pixel moves: no quantization, no resampling (they miss, as today)

**Ruling.** The fractional anchor enters the key with its exact bits.
A move by a fraction of a device pixel changes the canonical content's
fraction (or `f`) and **misses**, re-rasterizing at the exact position —
2155f1e's pixels. Neither quantizing the fraction (to ¼ px, say) nor drawing
the cached image at a fractional offset with bilinear filtering is built.

**Evidence.** Probe `SP0` — the positive control for the sub-pixel arms —
reads 0: SwiftUI (`ImageRenderer`) snaps layout positions and `.offset` to
whole pixels (`SP2b`, `SP4c`), so there is no SwiftUI sub-pixel shadow to
match and no measured tolerance to quantize within. MetalUI does not snap
content to pixels, so a quantized shadow would sit up to ⅛ px off its own
content (a pixel change against 2155f1e in every shadow at a fractional
position — every looks-demo shadow is a candidate). Quantizing alone does not
make a drag hit anyway: `RasterCache.endFrame` drops what a frame did not
touch (`GX-K`), so with fractional deltas consecutive frames rarely share a
quantum. Resampling moves pixels too and makes a crisp (radius 0) shadow
blurry.

**Cost if wrong.** A trackpad drag with fractional deltas keeps missing
(2155f1e's cost, reduced by PF-F's faster blur and by `compositingGroup()`'s
fewer shadows). Owner: none — reopened by a measured report. MetalCreator's
measured harness moved the node 2 points per frame (whole device pixels);
the fractional deltas of a real mouse or trackpad drag are **unmeasured**
here, so how often a real drag hits is unknown until the human check PF1 or
a MetalCreator re-measure (spec §9 D1).

## PF-E — Per leaf stays the default; one shadow per container is SwiftUI's `.compositingGroup()`

**Ruling.**

1. `.shadow` and `.blur` stay **per leaf** (`GX-J`, `LK-K`, divergence rows
   unchanged): SwiftUI is per leaf (`P1` re-runs `SH5`: black at (65,65)).
   Changing the default would change pixels of every shadowed overlapping
   stack and contradict the probe.
2. **`compositingGroup()`** is built — SwiftUI's own spelling for "shadow the
   composite" (`P2`: blue at (65,65); `CG7` `.drawingGroup()` likewise):
   - `ProposalElementGroup.compositingGroup() -> ModifiedContent<ProposalBase, LayoutModifier>`
     (a new public case `LayoutModifier.compositingGroup`; one layer, one
     identity level, `MC-C`) and `StyledElement.compositingGroup() -> Self`
     (`RenderEffectSpec.compositingGroup`, joining `Decoration.renderEffects`
     in written order, around the whole element — divergence 108's rule).
   - **Paint**: a new `PaintScope.Kind.composite`. While it is open, every
     leaf that reaches it (after the scopes inside it: inner shadows, effects,
     transitions) is **collected**; when it closes, the collected primitives,
     in order, go through the scopes outside it as **one leaf**. So an
     enclosing shadow casts one shadow of the union silhouette, drawn before
     the whole group (`SH5c`), and an enclosing blur blurs the composite
     (`CG2`) — the existing leaf machinery (`insertThroughScopes(leaf:)`), no
     new raster code.
   - **Only when it matters**: the scope is pushed only when a shadow or blur
     scope is open outside it (above the last barrier); otherwise
     `compositingGroup()` paints its content directly (`CG4`: alone it changes
     nothing). A `Deferred` barrier inside it stops collection as it stops a
     shadow (`GX-G`).
   - **Render only**: no layout change (`CG3`), no hitbox, nothing published;
     nothing animates (no numbers); a layer-count change resets state like any
     layer (`MC-A`).
3. **Divergence 205**: `.compositingGroup().opacity(_:)` (and any other
   non-shadow, non-blur effect outside it) is **not** composited — MetalUI's
   opacity multiplies each primitive (`CG1`: SwiftUI (255,128,128), MetalUI
   (191,64,128)). Compositing opacity needs an offscreen pass in both renderers
   (`TE-AD`); owner none. `drawingGroup()` stays unbuilt (divergence row of
   `GX-A`'s deferred list, amended to drop `compositingGroup()`).
4. **Migration**: `LayoutModifier` is a public enum; an exhaustive `switch`
   outside the package gains one arm (`docs/migration.md`), as `LK-R` item 3
   recorded for `.blur`. `swift package clean` after adding the case.

**Evidence.** `P1`/`P2`, `CG1`–`CG7`; the existing leaf group
(`beginLeafGroup`, text as one leaf, `SH4`/`SH5e`) is the precedent for "many
primitives, one leaf".

**Cost if wrong.** A composite that escaped a barrier would shadow a
presentation (test L2.8). A scope pushed with nothing outside it costs every
primitive the scoped path (test L2.5 counts it). Opacity semantics differ from
SwiftUI until an offscreen pass exists (pinned, divergence 205).

## PF-F — A faster `BoxBlur`, bit-identical, in `MetalUIPath` with no import

*Amended by the critic: PF-K item 2 assigns item 2's loops.*

**Ruling.**

1. `BoxBlur.blur` is rewritten for speed with **byte-identical output**:
   one pair of `Int32` buffers, `withUnsafeMutableBufferPointer` (no per-pixel
   bounds checks), horizontal passes per row, vertical passes **row-major
   with a per-column running-sum array** (cache-friendly), the same
   `(sum + half) / width` integer rounding and zero padding, and the final
   narrowing in the same unchecked loop. Optional, at the lane's discretion:
   stdlib `SIMD` types (they are the standard library, portable, no import),
   only if L2.1 stays exact. **No vImage/Accelerate**: `MetalUIPath` imports
   nothing (`GX-B`), so its output is bit-identical on every platform.
2. `AlphaCompositor.union` (same file) gets the same unchecked treatment;
   `RasterCache.tint` and `RasterMath.multiply/crop/scale` (lane 1's file)
   too. Each faster loop has a reference test against the 2155f1e code
   copied into the test target.
3. **Speed is reported, never pinned** (CLAUDE.md: performance tests count
   work, never wall clock): the blur's work (pixels) is unchanged by
   construction. The release-mode frame time of a 20-node shadowed graph,
   before and after, is measured by `docs/probes/shadow-cache/run.sh measure`
   and recorded.

**Evidence.** MetalCreator's release profile (~70 % `BoxBlur.blur`, ~14 %
`tint`); the 2155f1e code read above.

**Cost if wrong.** A non-identical fast path changes every shadow and blur
pixel — caught by L2.1/L1.11 and by run.sh's looks images.

## PF-G — Work counters: textures made per frame; pins count work, red on arrival

**Ruling.** `RasterCache` gains `lastTexturesMade` (internal): the
`ImageTexture`s the last completed frame created (tint misses + colour-image
misses) — the headless stand-in for "textures uploaded" (the renderers upload
once per new identity, `TE-AF`). With `lastBlurredPixels` and
`lastRasterizedPixels` it is what L1.1, L1.2, L1.7, L1.8 pin: after the first
frame of a whole-pixel drag or pan, **0 blurred, 0 rasterized, 0 textures
made**, and every image's texture `===` frame 1's. Each of those tests is red
at 2155f1e (every frame misses) — "red on arrival" is taken by running them
against the lane's first commit (counter added, keys unchanged) before the
keys change.

## PF-H — Lanes, files and what must not move

*Amended by the critic: PF-K items 2–4 amend the lanes.*

**Ruling.** Two lanes, disjoint files (spec §2):

- **Lane 1** (keys, Opus): `Sources/MetalUI/RasterCache.swift`,
  `Shadow.swift`, `Blur.swift`, `GradientRaster.swift`, new
  `Sources/MetalUI/RasterAnchor.swift`, `Sources/MetalUIPath/PathGeometry.swift`;
  tests `Tests/MetalUITests/RasterAnchorTests.swift` (new),
  `Tests/MetalUIPathTests/PathGeometryTranslationTests.swift` (new); probes
  `docs/probes/shadow-cache/` (new).
- **Lane 2** (blur speed + `compositingGroup()`, Opus):
  `Sources/MetalUIPath/BoxBlur.swift`, new `Sources/MetalUI/CompositingGroup.swift`,
  `NativeModifiedContent.swift`, `ModifiedContent.swift`, `RenderEffects.swift`,
  `ProposalAnimation.swift`, `TransitionStore.swift`, `Frame.swift`
  (`insertThroughScopes` only), `Sources/MetalUIDemoContent/LooksDemo.swift`;
  tests `Tests/MetalUIPathTests/BoxBlurTests.swift` (appended),
  `Tests/MetalUIPathTests/BoxBlurReference.swift` (new),
  `Tests/MetalUITests/CompositingGroupTests.swift` (new); docs
  `docs/divergences.md`, `docs/migration.md`, `docs/api-overview.md`,
  `docs/verification/human-checks.md`, `docs/probes/closeout-inventory-map.tsv`
  and the census.

Nothing in identity, state retention, hit testing, accessibility, animation,
focus, `List`, `Deferred` or text input moves; no renderer, shader or
`Backends/SDL` file changes (CPU-side only; SDL replay parity untouched), so
the Linux image is not required by `PX-` rules — it is still run once at the
end because `MetalUIPath` is portable and Linux CI builds it.

---

Critic rulings (2026-10-09). The probe was re-run byte for byte (compiled,
twice: 25 lines identical to its header). The code inventory was re-read at
2155f1e. Defects in the design are fixed by the amending rulings below. Each
rejected attack is in `PF-L` with its reason.

## PF-I — Only masks that decide a byte enter the key (amends PF-A item 1)

**Ruling.** `keyLeaf` keys a primitive's `contentMask`/`maskCornerRadii`
(translated by `−R`) **only when `innerMask` is set**, and a primitive
transform's `outerMask`/`outerMaskRadii` (conjugated) **only when
`outerMaskInner` is set**. Otherwise a fixed word `-2` stands in. The same
rule applies to a nested shadow's or blur's own mask (`case .shadow`,
`case .blur`). This stays in the one shared switch.

**Why.** At 2155f1e `keyLeaf` keys every mask unconditionally. `silhouette` and
`colourRaster` read a mask only under `q.innerMask` / `q.outerMaskInner`
(`Shadow.swift`, `Blur.swift`). A mask at or outside the scope's entry is the
clip in force there: `activeClip.scaled(by:)`, the panel's or window's rect,
absolute (`Frame.swift` `contentMask:` sites). A node moving inside a fixed
panel moves against that rect. So `PF-A` as first written ("rect … bounds and
content masks" translated by `−R`) would still change the key on every move.
That is MetalCreator's exact case (nodes inside a clipped canvas panel), so
the cache would have missed every frame. Dropping a mask that decides no byte
keeps `GX-K`'s rule ("every number that decides a coverage byte is in the
key").

**Pinned by** L1.9 (a node in a `.clipped()` panel dragged hits). Mutation
M1c (key the non-inner masks) reddens it.

## PF-J — Mode 1 rasterizes with today's clip, shifted; `E` is conservative (amends PF-B)

**Ruling.**

1. `E` is a **conservative superset** of every pixel the raster can cover: each
   leaf's `screenBounds` under `moved`, enclosed, grown by 1 px. A shadow or blur
   is then grown by `BoxBlur.padding(sigma)`. A nested shadow's or blur's own
   reach uses `padding(σ_inner)`, **not** `ShadowPaint.bounds`' `3·radius`,
   which can be smaller than the boxes' reach. A stroke uses `PathPaint.bounds`'
   miter pad.
2. In mode 1 the raster is made by **today's code, with today's
   `placement.clip` translated by `−S`**. It is not made over `E − S`. The bytes
   are then 2155f1e's bytes by construction, up to `PF-C` item 3's rounding,
   even if `E` were wrong. `E` decides one thing only: whether leaving the clip
   out of the key is sound.
3. An `E` that underestimates would let a cut raster and an uncut one share a
   key: stale pixels. An overestimate only sends more rasters to mode 2.

**Why.** As first written, `PF-B` made the mode-1 raster "over the canonical
`E − S`". That makes `E` a clip that decides bytes. With `3·radius` reach for a
nested shadow, or an under-padded stroke, it would cut pixels 2155f1e draws.

**Pinned by** L1.6, including a fixture where only the blur padding crosses the
clip. Mutation M1e (`E` without the padding) reddens it.

## PF-K — Pixel fixture, lane assignments, the measure's owner (amends PF-C, PF-F, PF-H)

**Ruling.**

1. `docs/probes/shadow-cache/run.sh pixels` renders **its own fixture**,
   `ZZShadowCachePixels.swift`, copied into each exported commit's tests (the
   demo-pixels method). The fixture holds a frozen copy of 2155f1e's LooksDemo
   shadow, blur and gradient rows, and a drag sequence. It does **not** render
   the live LooksDemo. Lane 2 adds a LooksDemo section, which would move a
   live-demo comparison, and `compositingGroup()` does not exist at 2155f1e.
   The fixture spells only API present at 2155f1e.
2. `RasterCache.tint` and `RasterMath.multiply/scale/crop` are in
   `RasterCache.swift`, so they are **lane 1's**. Lane 1 does them last, pinned
   against reference copies (L1.11). `AlphaCompositor.union` is in
   `BoxBlur.swift`, so it is lane 2's.
3. Lanes run in order, lane 1 first. Lane 1 writes `run.sh measure` and records
   the 2155f1e and after-lane-1 columns. Lane 2 records after-lane-2, with and
   without `compositingGroup()`.
4. Lane 2's `Frame.swift` diff is limited to `PaintScope.Kind.composite` and
   `insertThroughScopes`. The file is shared with parallel branch C9.

## PF-L — Attacks considered and rejected

1. **"SP2/SP4 show nothing, so `PF-D` rests on no probe."** Rejected as a
   defect. The header says so (`SP0`, the positive control, reads 0), and
   `PF-D` does not claim a SwiftUI sub-pixel answer. It rests on MetalUI's own
   pixels against 2155f1e and on `GX-K`'s drop-untouched rule.
2. **"`compositingGroup()` is new public API without a SwiftUI probe of its
   identity."** Rejected. `CG3`/`CG4` cover layout and the no-op case. Identity
   follows `MC-C` (one layer, one level) like every other `LayoutModifier`,
   and L2.6 pins it.
3. **"Make one shadow per container the default (MetalCreator's ask 2)."**
   Rejected, as `PF-E` rules: `P1` shows SwiftUI is per leaf. The default would
   change pixels of every overlapping shadowed stack. The opt-in is SwiftUI's
   own spelling.
4. **"Crop after the lookup for cut rasters (the report's proposal)."**
   Rejected (§9 D2). It needs the full unclipped raster of content that may be
   arbitrarily large off-screen (a long scrolled list's shadow). The common
   case (uncut) already hits through `PF-B`/`PF-J`.
5. **"vImage on Apple platforms (the report's proposal)."** Rejected (`PF-F`,
   `GX-B`). `MetalUIPath` imports nothing, so its output is bit-identical on
   every platform. Two blur implementations would split pixels between macOS
   and Linux/Windows CI.
6. **"No renderer change, so SDL/Linux needn't run."** Rejected in part.
   Replay parity is untouched (no shader or primitive change). The Linux image
   still builds and runs once at the end, because `MetalUIPath` is portable
   (`PF-H`).
7. **Lane size.** Two lanes on disjoint files is kept. Lane 1 is the larger;
   its faster loops (`PF-K` item 2) are last and severable. If the lane runs
   long they move to the Record phase's list, with an owner, rather than
   growing the lane.

---

Lane 1 rulings (2026-10-09, the implementer). Each amends a design ruling
with what the implementation measured.

## PF-M — Nested content re-anchors to its own corner; layout moves are whole points (amends PF-A item 1, spec §8)

**Ruling.**

1. A nested outline or leaf inside a canonical raster — a path's or a
   gradient's outline, a nested shadow's or blur's leaf — is **re-anchored to
   its own floored minimum corner** `R_i` (grid `1/s` for an outline under a
   uniform scale `s ∈ {1, 2, 4}`, else 1; grid 1 for a leaf), its `local`
   becoming `T(−R)·local·T(R_i)` (`Affine2D.reanchored`, the integer sums
   first). `PF-A` item 1 as written translated only the nested `local.tx/ty`
   and left "their own content in their own space": a path's control points
   and a nested shadow's leaf are **absolute window coordinates**, so a node
   holding a shadowed path or a shadow of a shadow would still have missed on
   every layout move. The map from nested content to device pixels is
   unchanged in exact arithmetic.
2. **Layout places on whole points** (measured: a padding of 40.5 pt at 2×
   draws where 41 pt does). So a half-point *layout* move does not exist; the
   tests drag by whole points at 2× through layout and by half points through
   an `.offset` (a flattened effect: the fraction lands in the shadow's or
   path's `local`, i.e. in `f`). L1.4 and L1.10 move by 0.3 and 0.25 pt
   through an `.offset` for the same reason, and L1.5's fractions are
   `.offset`s inside each shadow (the leaf's own bounds) and outside the whole
   fixture (the map).
3. The test probe `RasterCache.onRaster` (internal; `nil` costs one test per
   raster) hands L1.5 every raster as the scope carried it, so the canonical
   result is compared with 2155f1e's absolute helpers on the same input.

**Evidence.** `RasterAnchorTests` L1.1–L1.3, L1.7–L1.9 (red at `e8d70c2`,
green at `06393c6`); `aCachedShadowIsPlacedAtTheNewPosition`.

**Cost if wrong.** A re-anchoring that is not exact makes nested content miss
(performance only; L1.4 and L1.5 still hold, the bytes being a function of the
key).

## PF-N — Canonical against 2155f1e: 0 px where it binds, measured rounding elsewhere (amends PF-C items 2–3)

**Ruling.**

1. **The binding criteria hold unchanged** (`PF-C` item 1), measured at
   `06393c6` against `2155f1e`: the fourteen `demo-pixels` images 0 px, every
   scene dump identical; the thirteen `shadow-cache/run.sh pixels` images 0 px
   (frozen looks rows light, dark and 2×; both five-frame drags, whose frames
   1 and 4 hit the cache), controls non-zero; `Expected.swift` unedited.
2. **L1.5 compares on the device**: each texel at its device pixel, 0 outside
   its rectangle, so a raster one all-zero row wider is no difference.
   Measured, 21 rasters per configuration (every kind `PF-C` item 2 names):

   | position (inner, outer offset, pt) | 1× | 2× |
   |---|---|---|
   | integer (0, 0), (0, 0) | 0 bytes (1 raster one zero column wider) | 0 bytes (2 wider) |
   | dyadic (0.25, 0.5), (0.5, 0.25) | 0 bytes | **53 bytes, max Δ 1** (the bordered rounded box's two shadows, both strokes) |
   | non-dyadic (0.3, 0.7), (0.1, 0.45) | 0 bytes | 0 bytes |

   `PF-C` item 3 expected dyadic positions exact: **refuted at 2×**. Cause: a
   curved outline's edge deposits (a rounded ring's corners, a stroke's joins)
   are computed at another magnitude and round differently, and the
   rasterizer's per-row running sum carries that difference to a
   half-covered straight-edge pixel whose exact value is 127.5 + 0.5 = 128,
   which then reads 127. L1.5 pins **device max Δ ≤ 1 at every position, 0
   bytes at integer positions**.
3. **An integer coincidence can move a resampled leaf's bleed column** (L1.5b,
   pinned as measured): a 6 × 6 image whose inner and outer fractions sum to
   whole device pixels at 2× differs in 609 bytes, max Δ 4, in that one
   shadow. 2155f1e's `Affine2D.boundingBox(of: MUIBounds)` returns `Float`, so
   at absolute magnitude 163.99999991 rounds up to 164 while the canonical
   0.99999991 stays below 1: the canonical resample rectangle holds one more
   column, the bilinear filter's bleed past the image's edge (texel −1 = 0
   blended at weight ¼), and the blur spreads it to Δ 4. Neither rectangle is
   the right one — 2155f1e keeps that column wherever its box rounds down.
   This is rounding, not a wrong transform, so `PF-C` item 3's stop does not
   apply. A `Double` resample rectangle in both would remove the magnitude
   dependence; it is a pixel change against 2155f1e and is not taken. Owner:
   none.
4. **`PF-A` item 1 is kept**: the bytes are a function of the key (L1.4, L1.10
   green), so what differs from 2155f1e differs the same way warm or cold.

**Evidence.** `aCanonicalRasterEqualsTheAbsoluteOne`,
`aResampledLeafAtAnIntegerCoincidenceMayGainItsBleedColumn` (each prints its
row); `docs/probes/demo-pixels/compare.sh` and `docs/probes/shadow-cache/run.sh
pixels` logs in record §90.

**Cost if wrong.** A shadow at a half-pixel position at 2× can differ from
2155f1e by one level at a few edge pixels; the record's numbers and L1.5 bound
it.
