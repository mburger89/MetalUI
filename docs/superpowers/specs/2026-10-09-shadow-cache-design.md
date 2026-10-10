# Shadow cache — design (C13, PERF-a)

Item C13 of the gpui-gap priority list (user request 2026-10-02; **not a plan
task**). Reported by MetalCreator, `docs/metalui-gaps.md` "Node-drag
performance, 2026-10-08", PERF-a (measured on MetalUI `dc6528c`). Branch
`perf/shadow-cache` from `2155f1e`. Rulings: `PF-A`…`PF-L` in
[`../2026-10-09-shadow-cache-decisions.md`](../2026-10-09-shadow-cache-decisions.md)
(the binding text; this spec only arranges them into work). Record:
`docs/record/90-shadow-cache.md` (Record phase). Divergence labels reserved for
this branch: **205–214**. Probe: `docs/probes/swiftui-shadow-cache.swift`
(re-run byte for byte by the critic, 2026-10-09: 25 lines identical to its
header).

## 1. The problem and what is built

Moving a `.shadow(radius: 10)` node by 2 points re-rasterizes and re-blurs
every one of its per-leaf shadows on every frame (500,904 px blurred, 231,177
px rasterized, 9 new textures per frame for a Circle node), because every CPU
raster key holds absolute device positions (`PF-A` inventory) and
`RasterCache.endFrame` drops what a frame did not touch.

Built:

1. **Translation-free raster keys** (`PF-A`, `PF-I`): shadow, blur, path and the
   full gradient raster key and rasterize their content relative to a floored
   device anchor; the cached mask or image is placed at the integer anchor.
   Whole-device-pixel moves and pans hit, handing back the same `ImageTexture`.
2. **Unclipped key when nothing is cut** (`PF-B`, `PF-J`): the clip leaves the
   key only when the raster's conservative extent lies inside it. A cut raster
   keeps today's clipped key.
3. **`compositingGroup()`** (`PF-E`): SwiftUI's own spelling for one shadow (or
   one blur) of a container's composite. Per-leaf stays the default.
4. **A faster `BoxBlur`** (`PF-F`), byte-identical output, still importing
   nothing.
5. **Work counters** (`PF-G`): `RasterCache.lastTexturesMade` beside the two
   pixel counters, which the pins read.

Not built (§9): sub-pixel quantization or resampling (`PF-D`), crop after the
lookup for a cut raster, a key for the local-mask case, composited opacity
(divergence 205), `drawingGroup()`, vImage.

## 2. Lanes and files (`PF-H`, amended by `PF-K`)

Lanes run **in order** in this worktree, lane 1 first.

**Lane 1 — keys, counters, pixel/measure harness (Opus).**
`Sources/MetalUI/RasterCache.swift` (incl. `tint`, `RasterMath`), `Shadow.swift`,
`Blur.swift`, `GradientRaster.swift`, new `Sources/MetalUI/RasterAnchor.swift`,
`Sources/MetalUIPath/PathGeometry.swift` (`package translated(dx:dy:)` only);
tests `Tests/MetalUITests/RasterAnchorTests.swift` (new),
`Tests/MetalUIPathTests/PathGeometryTranslationTests.swift` (new),
`Tests/MetalUITests/RasterMathReferenceTests.swift` (new); probes
`docs/probes/shadow-cache/` (new: `run.sh`, `ZZShadowCachePixels.swift`,
`ZZShadowCacheMeasure.swift`).

**Lane 2 — blur speed and `compositingGroup()` (Opus).**
`Sources/MetalUIPath/BoxBlur.swift`, new `Sources/MetalUI/CompositingGroup.swift`,
`NativeModifiedContent.swift`, `ModifiedContent.swift`, `RenderEffects.swift`,
`ProposalAnimation.swift`, `TransitionStore.swift` (exhaustive switches only),
`Frame.swift` (`PaintScope.Kind.composite` and `insertThroughScopes` only),
`Sources/MetalUIDemoContent/LooksDemo.swift` (one new section in its own
function, `everyProductionTreeBuildsOnAOneMegabyteThread`); tests
`Tests/MetalUIPathTests/BoxBlurTests.swift` (appended),
`Tests/MetalUIPathTests/BoxBlurReference.swift` (new),
`Tests/MetalUITests/CompositingGroupTests.swift` (new), one typecheck guard;
docs `docs/divergences.md` (row 205, the `GX-A` deferred row amended),
`docs/migration.md`, `docs/api-overview.md`,
`docs/verification/human-checks.md` (group PF),
`docs/probes/closeout-inventory-map.tsv` and the census. Lane 2 re-runs
`run.sh measure` after the blur and records the "after" column.

No renderer, shader, `Backends/SDL`, `MetalUIScene` or `MetalUILayout` file
changes. `Frame.swift` is shared with parallel branches (C9): lane 2 keeps its
diff to the scope kind and the one function.

## 3. Lane 1 — canonical keys (`PF-A`, `PF-I`)

### 3.1 `RasterAnchor`

A new internal type (`RasterAnchor.swift`) computes, for one raster:

- `R` — the creation-space anchor: the content's minimum corner floored to the
  creation space's device grid (device pixels for a shadow/blur leaf; for a
  path/gradient outline in points under `local`, grid `1/s` when `s ∈ {1,2,4}`,
  else 1; `PF-A` item 1).
- `D = full(R)`, `S = ⌊D⌋` (integers), `f = D − S`; `full'` = `full`'s linear
  part with translation `f`.
- The canonical leaf: every creation-space quantity that **decides a byte**
  translated by `−R` — primitive bounds, a nested shadow's/blur's/path's/
  gradient's `local.tx/ty`, a primitive's own transform conjugated
  `T(−R)·A·T(R)` — and **only the masks that decide a byte** (`PF-I`): a
  primitive's `contentMask`/`maskCornerRadii` enter the key (translated) only
  when its `innerMask` is set; a transform's `outerMask`/radii only when
  `outerMaskInner` is set; otherwise a fixed word (`-2`) stands in. Today
  `keyLeaf` keys every mask unconditionally; a mask at or outside the scope's
  entry is the panel's or window's absolute clip, which a moving node moves
  against, so translating it by `−R` would still miss on every move.
- `RasterKey` gains nothing absolute; `RasterKey.add(_:)` overloads are reused.

`keyLeaf` stays **one switch** shared by shadow and blur (`GX-J`, `LK-K`); it
gains the anchor and the inner-mask rule in that one place.

### 3.2 Modes (`PF-B`, `PF-J`)

- **Mode 1 (uncut)**: `E` = a **conservative** device extent of the raster
  (each leaf's `screenBounds` mapped by `moved`, enclosed, grown by 1 px, then
  by `BoxBlur.padding(sigma)` for a shadow/blur; nested shadows/blurs grown by
  their own `padding(σ_inner)`, not `3·radius`; strokes by `PathPaint.bounds`'
  miter pad). When `E ⊆ placement.clip` and `placement.localMask == nil`, the
  key carries mode word 1 and **no clip**; the raster is made by **today's
  code with today's clip translated by `−S`** (so its bytes are 2155f1e's bytes
  whatever `E` says; `E` only decides whether omitting the clip from the key is
  sound).
- **Mode 2 (cut)**: `E ⊄ clip`: mode word 2 plus `clip − S` in the key; same
  raster code. Moves relative to the clip miss, as today.
- **Mode 3 (local mask)**: `placement.localMask != nil`: today's absolute key
  and code, unchanged (`PF-B` item 3).

The cached `AlphaMask` (coverage cache) and the cached colour-image `rect`
(image cache) are stored **canonical**; the caller shifts by `S` before
`placement.quad(over:)`. Tint keys stay the coverage key plus colour (`GX-K`).

### 3.3 Per raster

| Raster | Today's absolute key fields | Canonical |
|---|---|---|
| `shadowImage` | `full`, `placement.clip`, `keyLeaf` bounds/masks | anchor + modes |
| `blurImage` | same, colour image `rect` | anchor + modes, `rect − S` stored |
| `pathImage` | `full`, `placement.clip` | geometry `translated(−R)` or `full'` only, + modes |
| `gradientImage` (full raster) | outline, `full`, clip | as path |
| `gradientImage` (strip) | absolute `origin/start/end` | **unchanged** (§9 D4) |

### 3.4 Counters (`PF-G`)

`RasterCache.lastTexturesMade` (internal), set in `endFrame` from a per-frame
count of `ImageTexture`s created by `tint` misses and image-cache misses.

### 3.5 Faster loops in lane 1's file (`PF-F` item 2, `PF-K`)

`RasterCache.tint`, `RasterMath.multiply/scale/crop`: unchecked
`withUnsafe…BufferPointer` loops, byte-identical; each pinned against a copy
of the 2155f1e loop in `RasterMathReferenceTests.swift`. Done last in the lane.

## 4. Lane 2 — `BoxBlur` (`PF-F`)

One pair of `Int32` buffers, unchecked buffer pointers, horizontal passes per
row, vertical passes row-major with a per-column running-sum array, the same
three widths, the same per-pass `(sum + half) / width` rounding and zero
padding, the narrowing in the same loop. `AlphaCompositor.union` unchecked.
Stdlib `SIMD` only if L2.1 stays exact. No Accelerate (`GX-B`: `MetalUIPath`
imports nothing).

## 5. Lane 2 — `compositingGroup()` (`PF-E`)

- `ProposalElementGroup.compositingGroup() -> ModifiedContent<ProposalBase, LayoutModifier>`
  (new public case `LayoutModifier.compositingGroup`; one layer, one identity
  level, `MC-C`); `StyledElement.compositingGroup() -> Self`
  (`RenderEffectSpec.compositingGroup`, written order, divergence 108).
- `PaintScope.Kind.composite`: pushed only when a shadow or blur scope is open
  outside it above the last barrier; collects every leaf that reaches it, and
  on close sends the collected primitives through the outer scopes **as one
  leaf** via `insertThroughScopes(leaf:)`. A barrier inside stops collection.
  The shadow item takes the first primitive's layer (as a text leaf does).
- Render only: no layout, hitbox, accessibility, focus or animation change.
- Divergence 205: composited opacity is not built (`CG1`).
- Migration: an exhaustive `switch` over `LayoutModifier` outside the package
  gains an arm. `swift package clean` after adding the case.
- LooksDemo gains one section (its own function): a two-square overlap with
  `.shadow` and with `.compositingGroup().shadow` side by side.

## 6. Pixels (`PF-C`, amended by `PF-K`)

- Fourteen offscreen images: `docs/probes/demo-pixels/compare.sh <scratch>
  2155f1e HEAD` — 0 px (they hold no shadow/blur/gradient; a 0 proves paths
  untouched).
- `docs/probes/shadow-cache/run.sh pixels <scratch> 2155f1e HEAD`: exports
  each commit, copies `ZZShadowCachePixels.swift` into its tests (the
  demo-pixels method) and renders **its own fixture**: a frozen copy of
  2155f1e's LooksDemo shadow, blur and gradient rows plus a five-frame drag
  sequence of a 9-leaf shadowed node (whole-pixel, half-pixel and 0.3-px
  steps, 1× and 2×). The fixture uses no API absent at 2155f1e, so lane 2's
  LooksDemo section moves nothing it compares. Expected 0 px, controls first
  (frame 0 vs frame 1 of the drag differs; light vs dark differs).
- `DemoFrameDeterminismTests`' `Expected.swift` unedited.
- Contingency for non-dyadic curved fixtures in L1.5: `PF-C` item 3.

## 7. Measurement (report only, `PF-F` item 3)

`run.sh measure`: a release-mode headless frame loop over a 20-node graph
(each node a 9-leaf container with `.shadow(color:, radius: 10)`, one moving
2 pt per frame at 2×, 1440 × 900), median ms per frame over 60 frames, and the
three counters. Taken at 2155f1e, after lane 1, after lane 2; with and without
`.compositingGroup()` after lane 2. Recorded in record §90, never pinned.

## 8. Tests and mutations

Performance pins count work. Each L1.1–L1.3, L1.7–L1.9 is red at lane 1's
first commit (counter added, keys unchanged) — taken and named in the record.

**Lane 1**

- **L1.1** layout drag: a 9-leaf `.shadow(radius: 10)` container moved 1 px
  per frame (1×) and 0.5 pt (2×) for 5 frames: frames 2–5 read 0 blurred, 0
  rasterized, 0 textures made; every image's texture `===` frame 1's.
- **L1.2** pan: the same under a parent `.offset` changing by whole pixels.
- **L1.3** blur: a `.blur(radius: 4)` container dragged: same counters.
- **L1.4** history independence: warm at x, move to x + 0.3: bytes equal a
  cold window at x + 0.3.
- **L1.5** canonical = absolute: per raster kind (rect, rounded rect, ellipse,
  bordered rect, text, image, stroked path with miter, nested shadow, gradient,
  nested blur), at integer, dyadic and non-dyadic positions, scale 1 and 2:
  canonical raster shifted by `S` equals today's absolute call, 0 bytes
  (contingency `PF-C` 3).
- **L1.6** cut: a shadow straddling a `.clipped()` edge, dragged: rasterizes
  every frame (mode 2), bounds equal today's (3.20 unchanged).
- **L1.7** path dragged by whole pixels: 0 rasterized after frame 1.
- **L1.8** full gradient raster dragged: 0 rasterized after frame 1.
- **L1.9** a shadowed node inside a `.clipped()` panel (clip outside the
  shadow, not cutting) dragged: hits (`PF-I`).
- **L1.10** pin, `PF-D`: a 0.25-px move misses (rasterized > 0) and draws the
  exact-position bytes.
- **L1.11** `tint`/`RasterMath` = reference copies over seeded masks.
- **L1.12** `PathGeometry.translated` exact on integer and dyadic offsets.
- **L1.13** `lastTexturesMade`: a colour change 1, a hit 0.
- Existing pins unchanged: 3.12, 3.14, 3.20, GX-K's.

Mutations (each on its own commit copy, full suite, tests named):
**M1a** key `full` with its absolute translation (L1.1, L1.2, L1.7, L1.8);
**M1b** drop `f` from the key (L1.4); **M1c** key non-inner masks (L1.9);
**M1d** always mode 1 (3.14, 3.20, L1.6); **M1e** `E` without the blur padding
(a fixture in L1.6 whose padding alone crosses the clip); **M1f** stored rect
not shifted by `S` (L1.1 bounds); **M1g** counter not incremented (L1.13);
**M1h** a `tint` rounding changed (L1.11).

**Lane 2**

- **L2.1** `BoxBlur` = reference copy: sigmas 0.3, 0.8, 1, 2.5, 10, 33; masks
  1×1, 1×N, N×1, odd and even sizes, seeded LCG bytes: 0 differing bytes.
- **L2.2** `union` = reference copy.
- **L2.3** `overlap().compositingGroup().shadow(radius: 0, x: 10, y: 10)`: one
  shadow image; the overlap pixel is the blue square's, not shadow (`P2`).
- **L2.4** per-leaf default unchanged (`P1`; cite the existing SH5 pin).
- **L2.5** `compositingGroup()` with no shadow/blur outside: scene identical to
  without, no composite scope pushed (`CG4`; a scope-push counter).
- **L2.6** one layer, one identity level; `@State` under it retained across
  frames; adding it resets as any layer (`MC-A`).
- **L2.7** `compositingGroup().blur`: one blur image (`CG2`).
- **L2.8** a `Deferred` inside is not shadowed.
- **L2.9** pin divergence 205: `.compositingGroup().opacity(0.5)` overlap is
  per-primitive.
- **L2.10** legacy `compositingGroup()` in written order (divergence 108).
- **L2.11** 9-leaf node with `.compositingGroup().shadow(radius: 10)` blurs one
  mask (blurred pixels = one padded area).
- **Guard** `compositingGroup` spellable on both vocabularies under a plain
  import (`typecheckFile`), mutated red once.

Mutations: **M2a** `(sum + half)` → `sum` (L2.1); **M2b** vertical running sum
off by one row (L2.1); **M2c** composite forwards per primitive (L2.3, L2.11);
**M2d** composite always pushed (L2.5); **M2e** barrier ignored (L2.8);
**M2f** no identity level (L2.6).

## 9. Deferrals and named limits

- **D1** Sub-pixel moves miss (`PF-D`). Owner: none; reopened by a measured
  report. Human check PF1 measures how often a real trackpad drag hits.
- **D2** A cut raster (node straddling a panel edge) misses on every move; no
  crop after the lookup (it would need the full unclipped raster of a possibly
  huge cut content). Owner: none.
- **D3** The local-mask case (a clip inside a rotation/non-uniform scale)
  keeps its absolute key. Owner: none.
- **D4** The gradient strip keeps its absolute key (its cost is one row; not
  in the report). Owner: none.
- **D5** Under a non-translation outer effect or a primitive transform the
  conjugated affine may differ in its last bits between positions: those may
  miss. Correct, not cached.

## 10. Human checks (group PF, not run — an agent cannot)

- **PF1** MetalCreator-style drag of a shadowed node with a trackpad: smooth;
  the record's counters logged per frame show how many frames hit.
- **PF2** LooksDemo's compositingGroup section: one shadow under the pair vs
  per-leaf shadows; matches SwiftUI's `P1`/`P2` reading.
