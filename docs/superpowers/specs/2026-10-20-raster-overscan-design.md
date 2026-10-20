# Raster overscan for shadows, blurs and gradients, and a pooled rasterizer scratch (P4)

Branch `perf/raster-overscan` from `4d91f27f`. Not a plan task: item P4 of the gpui-gap list (user request 2026-10-02), the carried
halves of record §118 §6 (`PN-C`: "overscan for them is P3b"; P3d). Rulings `OS-A`…`OS-K` in
[`../2026-10-20-raster-overscan-decisions.md`](../2026-10-20-raster-overscan-decisions.md). Divergence labels reserved 545–554:
none expected. **No public declaration, no SwiftUI-facing claim** (internal, pixels equal): no SwiftUI probe is owed (`OS-J`); gpui
draws raster coverage with the clip as a GPU content mask, never a CPU cut, which is the precedent `PN-A` already used.

## 1. Inventory (the code at `4d91f27f`)

- `RasterAnchor` (`RasterAnchor.swift`): modes `.uncut`/`.cut`/`.localMask`; `.cut` keys `clip - S`, so a pan relative to the clip
  misses. `overscanned(extent:clip:target:)` (PN-A) turns a `.cut` anchor `.uncut` for an extent within `overscanLimit` (2^20 px) and
  within half the target's size of it. Only `pathImage` calls it.
- `shadowImage` (`Shadow.swift`), `blurImage` (`Blur.swift`), `gradientImage` full raster (`GradientRaster.swift`) build the same
  `RasterAnchor(rx:ry:full:extent:placement:)` and pass `placement.clip` as the raster clip. Their extents are already conservative:
  shadow and blur `RasterExtent.of(leaf, map:)` grown by `BoxBlur.padding(sigma) + 1` (`PF-J` item 1, nested reach included);
  gradient `paint.bounds` (a stroke grown by the miter pad) grown 1.
- The image quad's `contentMask`/`maskCornerRadii` already cut at draw time for every kind (`RasterPlacement.quad`); the CPU crop to
  the clip is therefore redundant for pixels (the argument of `PN-A`).
- The gradient **strip** (`stripImage`) is already translation-free and untouched.
- Scratch: `CoverageRasterizer` (`MetalUIPath/Rasterizer.swift`) holds only a counter; each `rasterize` allocates `cells`
  (`[Double]`, `(w+2)·h`) and the returned `alpha` (escapes into the cache). `BoxBlur.blur` allocates `a`, `b` (`Int32`, `w·h`),
  `columnSums` and the returned `out` (escapes). Call sites create a `CoverageRasterizer()` per primitive.
- Measurement scenarios (`docs/probes/pan-rasters/Sources/Prof`): `shadows` is static (steady all hits, 1.24 ms) and the bracket
  fixture holds no shadow, blur or gradient. **No existing scenario pans shadows**, so lane 1 adds one (`OS-K`).

## 2. Design

### Lane 1 — overscan (P3b), files: `RasterAnchor.swift` (only if a helper is needed), `Shadow.swift`, `Blur.swift`,
`GradientRaster.swift` (the `*Image` functions only), `Tests/MetalUITests/RasterOverscanTests.swift` (new), amended pins,
`docs/probes/raster-overscan/`.

In each of `shadowImage`, `blurImage`, `gradientImage` (full raster, `transform` or not):

```
var anchor = RasterAnchor(...)            // as today
var rasterClip = placement.clip
if let o = anchor.overscanned(extent: extent, clip: placement.clip, target: rasterTarget) { anchor = o; rasterClip = extent }
let clip = anchor.canonical(rasterClip)   // the raster's clip (and the make closure's `clip`)
... key uses anchor.keyed(&key, clip: clip, ...)   // .uncut: no clip word
... after the cache lookup: if rasterClip != placement.clip, anchor.placed(rect).intersection(placement.clip).isEmpty { return nil }
```

`overscanned` is reused unchanged (same predicate, same limit, `OS-D`); `.localMask` stays absolute (`OS-E`). A shadow's extent is
the shadow's own extent including its blur padding, so a large radius binds the area limit and keeps today's cut key. Nothing else
in the pipeline moves: `shadowCoverage`/`blurLayer`/`gradientPixels` take the (larger) clip they are given and crop to it.
**Each kind lands independently, and only with its byte-equality test green (`OS-A`)**: if a kind's raster over `E` differs inside
the clip from the cut one, that kind keeps today's keys and the record says which and by how many bytes.

### Lane 2 — pooled scratch (P3d), files: `MetalUIPath/Rasterizer.swift`, `MetalUIPath/BoxBlur.swift`, new
`MetalUIPath/RasterScratch.swift`, `RasterCache.swift` (the `scratch` property), the `var rasterizer = CoverageRasterizer()` lines in
`Shadow.swift`/`Blur.swift`/`GradientRaster.swift` (`silhouette`, `colourRaster`, `gradientPixels` only, not the `*Image`
functions lane 1 edits), `PathRaster`'s rasterizer parameter, `Tests/MetalUITests/RasterScratchTests.swift`,
`Tests/MetalUIPathTests` (portable). **Sequenced after lane 1** in this one worktree (`OS-I`); the sites overlap in four files, the
lines do not.

`package struct RasterScratch { var cells: [Double]; var ints: [Int32] }` (MetalUIPath, imports nothing; value type, so
`Sendable` and bit-identical on every platform, `GX-B`). `RasterCache` owns one (`var scratch`, main actor, one per window); a
rasterization passes `&cache.scratch` as an optional `scratch:` argument whose default is a fresh one (so every other caller and
test is unmoved). `rasterize` takes `cells` from the scratch: `removeAll(keepingCapacity: true)` then `append(repeating: 0, count:)`
(**zero-fill stays**: stale cells would change bytes); `BoxBlur.blur` takes `a`, `b`, `columnSums` likewise. The returned
`alpha`/`out` still allocate (they are the cached result). Exclusivity: a `make` closure reads `cache.scratch` while
`cache.coverage(for:make:)` runs; `coverage` must not hold `scratch` inout (it does not: separate stored property). Capacity is
capped (release above 4 Mi elements) so one huge raster does not pin memory.

**Gate (OS-H): lane 2 lands code only if** on release, paired A/B (alternated, 5 rounds, `ab.sh`), the scenario `bracket-value` or
the new `shadow-drag` shows allocated bytes per drawn frame down at least 10 % **or** median ms/frame down at least 3 % in at least
4 of 5 paired rounds. Otherwise lane 2 records the numbers, rules the pool not justified (as §118 did P3c), and lands only its
instrument (the pins as characterizations, `RasterScratch` not built). Expected honestly: steady pan after lane 1 rasterizes
nothing, so the pool can only help the drag's and first frames' misses (`cells` is 8 of ~13 B per rasterized px).

## 3. Tests (every one named; red-before on `4d91f27f`; the mutation that must redden it)

Lane 1, `RasterOverscanTests` (all `@Test @MainActor`, harness `TransitionHarness`, a `.clipped()` canvas panned by whole pixels as
`PanRasterTests`; counters `RasterCache.lastRasterizedPixels`/`lastBlurredPixels`/`lastTexturesMade`, never time):

| id | name | red before | must be reddened by |
|---|---|---|---|
| S1 | `aShadowedCardPannedByWholePixelsAcrossTheClipEdgeRasterizesNothing` | red: 5 pans each `rasterized/blurred/made > 0`, texture differs | `overscanLimit = 0`; removing the call in `shadowImage` |
| S2 | `aBlurredLeafPannedByWholePixelsAcrossTheClipEdgeBlursNothing` | red, as S1 | `overscanLimit = 0`; removing the call in `blurImage` |
| S3 | `aFullGradientPannedByWholePixelsAcrossTheClipEdgeRasterizesNothing` (radial and a diagonal linear; a vertical linear strip is the separating arm, green before) | red for the full raster | `overscanLimit = 0`; removing the call in `gradientImage` |
| S4 | `anOverscannedShadowBlurAndGradientEqualTheCutOnesInsideTheClip` | green by design (equivalence); instrument is its mutations | `pad` of the shadow extent `0`, blur extent `pad` `0`, gradient extent not grown; the clip is chosen to include the blur tail so a short extent shows; leaves: rect, rounded rect, path, glyph, image under 1× and 2×, a scale effect (resampled leaf), fill and stroke gradients |
| S5 | `aPannedShadowBlurAndGradientDrawTheColdRendersPixels` (`drawnTexels`, as T8, counts images too) | green by design | `rasterClip = placement.clip` while keyed uncut; dropping the draw-time cut; dropping the outside-the-clip drop (`aSurplusRasterWhollyOutsideTheClipDrawsNothing` arm) |
| S6 | `aShadowOverTheLimitOrOutsideTheWindowKeepsTheCutKey` (large radius binds the limit; far off-window) | green by design | removing the area test; removing the window test |
| S7 | `aShadowBlurAndGradientUnderALocalMaskKeepTheirAbsoluteKey` | green by design | routing `.localMask` through overscan |
| S8 | `aDragRastersOnlyTheMovingShadows` (static plus moving card; frames 2–4 rasterize what the moving one alone does; a half-pixel pan and a radius change miss) | green by design (characterization, no mutation) | none |
| S9 | `theShadowCacheKeyPinsNameTheirBranch` — each existing `PF-` pin that asserts a clip-dependent shadow, blur or gradient key is **read before editing** (`PN-G`/`PN-H`), amended only if it pins a key not a behaviour, each amendment listed in the record | n/a | n/a |

Also green-on-arrival characterizations are listed as such in the record; the fourteen images (`compare.sh <scratch> 4d91f27f HEAD`)
read 0 px; `DemoFrameDeterminismTests` `Expected.swift` is not edited.

Lane 2 (`RasterScratchTests`, portable ones in `Tests/MetalUIPathTests`, written even if the gate rules the pool out):

| id | name | red before | must be reddened by |
|---|---|---|---|
| P1 | `aPooledRasterizerEqualsAFreshOneAcrossShrinkingAndGrowingSizes` | compile-red (no scratch API) | skipping the zero-fill; reusing without `removeAll` |
| P2 | `aPooledBoxBlurEqualsTheReferenceByteForByte` (extends `theFastBoxBlurEqualsTheReferenceByteForByte`) | compile-red | skipping the zero-fill of `a`/`b`/`columnSums` |
| P3 | `aWarmRasterAllocatesOnlyItsResult` (`countAllocations`, thread-filtered, differential, floor-corrected, Darwin only: second raster of equal size allocates at most the result's buffers) | red: at least two more allocations | no scratch passed at a call site |
| P4 | `thePoolDoesNotPinAHugeBuffer` (capacity capped after a 2^23-element raster) | compile-red | removing the cap |

Mutate each new typecheck guard red once (none expected: no new public or cross-module surface; `RasterScratch` is `package`, and
`MetalUIPath` imports nothing, so the manifest import rules are unchanged; confirm with the Linux image build).

## 4. Measurement (dated, never pins; `OS-K`)

`docs/probes/raster-overscan/` adds Prof scenarios `shadow-pan` (a 6x4 grid of shadowed, blurred and radial-gradient cards in a
panned clipped region, whole-pixel steps) and `shadow-drag` (one card moving over static ones), `counters.sh`, `ab.sh` (alternated
per round against `4d91f27f`), reporting release ms/frame, allocations per frame and the work counters. Reported with the load
average, as `docs/probes/pan-rasters/README.md`.

## 5. Platforms, demo, human checks

No platform seam, shader or `Backends/SDL` change (the pixels are drawn by the same image pipeline; the draw-time mask is the
`MUIImage` content mask both renderers already apply), so replay parity is untouched; the Linux image runs `MetalUIPath` and the
portable tests (`swift:6.4-noble`), and Windows is CI's. No demo section; the Looks demo (`METALUI_LOOKS_DEMO=1`) scrolled across a
panel edge is the look. **Record-phase human-check addition `RO1`**: scroll a shadowed, blurred and gradient list across a panel
edge on AppKit and SDL, no seam, flicker or clipped glow at the edge (nothing in the suite sees a look).

## 6. Deferred (named, with owner)

- Overscan for **mode 3** (local masks): needs a measured, byte-equal case; none exists (`OS-E`). Owner: next perf item, no number.
- A **cheaper cold frame for a half-visible card** (rasterizing `E`, not the clip, costs up to the extent once): accepted, bounded by
  the 2^20 limit (`OS-F`).
- Overscan **for backdrops (`Material`)**: they are GPU, not CPU-raster, nothing to cache (`BB-`).
- R8 coverage with a shader tint (P3c) stays ruled out (§118 §7).
- `AmbientKey` reshape, array-indexed measure cache (P3, §119): unchanged.
