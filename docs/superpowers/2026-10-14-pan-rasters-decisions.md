# Pan rasters — decisions

Rulings for P3 (the pan path-raster miss, user request 2026-10-02). Spec:
[`specs/2026-10-14-pan-rasters-design.md`](specs/2026-10-14-pan-rasters-design.md). Record: `../record/118-pan-rasters.md`
(Record phase). Branch `perf/pan-rasters` from `34491ff4`; divergence labels reserved 485–494 (none taken).

**Next unused id: `PN-K`.** (Moves in the commit that appends a ruling; read the last `## PN-` heading if they disagree.)

Evidence: the code at `34491ff4` (`RasterCache.swift` `pathImage`, `tint`; `RasterAnchor.swift`; `Rasterizer.swift`), record §90
(`PF-A`, `PF-B`, `PF-J`, `PF-N`), §73, §111 §8. No SwiftUI-facing claim is made: the item is internal, pixels equal, so no probe is
owed; gpui's approach (it draws path coverage through the GPU with the clip as a scissor/content mask, never a CPU cut) is the
precedent for letting the draw-time mask cut, not a source for a claim.

## PN-A — The GPU mask cuts a path raster; the key no longer holds the clip

**Ruling.** Under no local mask, a path whose conservative extent `E` is small enough is rasterized over `E` and keyed
`.uncut`; `imageMask` does the cut. **Why.** The coverage is clip-independent (exact-area accumulator) and the image already
carries the clip as its content mask, so the CPU cut buys nothing and costs a miss per pan. **Evidence to take.** T2 (bytes inside
the clip), the fourteen images 0 px. **Cost if wrong.** A byte differing at the clip edge from folded floating rounding: then the
raster is no longer 34491ff4's by construction; the lane quantifies and stops (a ruling, not a silent re-take of `PF-` pins).
`PF-J` item 2's "today's bytes by construction" is amended for paths only: bytes equal up to that rounding, measured.

## PN-B — The overscan limit is 1,048,576 device pixels, within 1.5× of the target

**Ruling.** `RasterAnchor.overscanLimit = 1 << 20` on `E.area`, and `E` inside the target grown by half its size per axis.
**Why.** An overscanned raster costs `E.area` once (a wire's `E` is its bbox, typically 10⁴–10⁵ px); the limit keeps a
pathological off-screen shape from rasterizing a large area it mostly never shows; the window bound keeps a huge shape that is
mostly off-window on today's cut. **Cost if wrong.** Too low: pans of big shapes miss as today (performance only). Too high: a
one-off larger first raster. Re-takeable by the constant; T3 pins that a limit exists, not its value.

## PN-C — Paths only; mode 3 and every shadow, blur and gradient keep today's behaviour

**Ruling.** Only `pathImage` uses the overscan; `localMask` placements stay absolute; shadows, blurs and gradients are P3b.
**Why.** `E` for blurred leaves includes `BoxBlur.padding`, which makes them straddle more and the limit bind; the profile names
wires; `PF-I`/`PF-J`'s pins for shadows stay unmoved. **Cost if wrong.** A shadowed node cut by a panel edge still misses on a pan
(performance only, named in the spec).

## PN-D — Tint only the covered words now; R8 coverage with a shader tint is not built

**Ruling.** `RasterCache.tint` skips zero 8-byte words, byte-identical to the reference loop; R8 + shader tint is carried as P3c.
**Why.** After PN-A the tint runs only on misses (the drag's moving wires, first frames); the span skip is value-identical with no
shader, replay-parity or `ReplayFixture` change; (c) is the larger product change and is justified only by a measured residual.
**Cost if wrong.** If the drag's tint remains large after the measure, P3c is opened with the numbers (lane 2).

## PN-E — A cubic whose endpoint moves, and a sub-pixel translation, miss by design

**Ruling.** Nothing is done for the drag's two moving wires beyond PN-D; a translated whole-pixel wire hits (mode 1 or PN-A), a
sub-pixel one keeps its fraction in the key. **Why.** An endpoint move changes the control points: the outline is a new function
of the key; resampling a cached raster is rejected by `PF-D`. **Cost if wrong.** None to correctness; the drag stays at its
rasterization cost (78,312 px for two wires, record §109 §7) and a faster rasterizer (pooled buffers) is P3d.

## PN-F — Critic's rejection: no `SB-E` row for `lastTintedPixels`

**Ruling.** The spec's T8 (`everyNewCounterIsClassified`, `SB-E`) is dropped. **Why.** `SB-E`'s test
(`everyStateTableAndAnimationStoreChannelIsClassified`, record §111) classifies `StateTable`/`AnimationStore` channels; `RasterCache`
counters such as `lastTexturesMade` have no classification test, so T8 named a test that does not exist and could not be red. The
counter is covered by T5 (tinted < ⅓ of area, ≥ nonzero count) and T6. **Cost if wrong.** None.

## PN-G — An overscanned raster wholly outside its clip draws no image

**Ruling.** `pathImage` overscans only when the extent meets the clip, and returns `nil` when the placed mask misses the clip
entirely (as the cut raster, empty, always did). **Why.** Found by a reddening pin read before it was edited:
`theBracketNodeDragRebuildsTheWholeWindow` read 8 images against 6, because the overscan drew two wires whose coverage lay wholly
outside the canvas, fully masked by the GPU. Pixels were equal, but the scene's primitive count must not move. **Evidence.** The
three arms of that test green again after the fix; mutation M7 (the drop removed) reddens exactly those three arms. **Cost if wrong.**
A wire whose bounding box meets the clip while its curve does not (a diagonal cubic's corner) still draws a fully masked image,
as it did not at 34491ff4 only when the cut raster came out empty; the bracket fixture does not hit it.

## PN-H — 3.14's clip arm is amended (a reddening pin that is a fix)

**Ruling.** `theCacheKeyIncludesColourTransformAndClip`'s clip arm now expects the same texture and 0 pixels rasterized when a
`.clipped()` frame narrows from 60 to 20 over a 40-point triangle. **Why.** The pin said "a clip change re-rasterizes"; under
`PN-A` the clip is not in a path's key when it only cuts, and T2 pins that the bytes equal the cut raster inside the clip. The
shadow, blur and gradient pins (`aShadowCutByItsClipIsRasterizedOnEveryMove` and the rest) are unmoved: their sites keep the cut
key (`PN-C`). **Cost if wrong.** None to pixels (T2, the fourteen images).

## PN-I — T2's instrument: a 3 px shrink of the extent is invisible, the stroke pad is what T2 sees

**Ruling.** T2's mutation is `PathPaint.bounds`' miter pad made 0, not a shrink of `pathExtent`. **Why.** Measured: `pathExtent`
grown by -3 instead of 1 left the whole suite green (M2), because `PathPaint.bounds` pads a stroke by `width × max(miterLimit, 2)`
(40 px for a 2-pt wire, 60 for the 6-pt mitred triangle), far beyond the coverage. With the pad removed T2 reddened (M2b, two
issues, 1× and 2×). The generous pad also means the extent `PN-B` limits can be much larger than the coverage; whether the rasterizer allocates the extent or the coverage box is unmeasured here (carried to lane 2's pixels-rasterized table). **Cost if wrong.** None.

## PN-J — Verification on a locked screen skips `AppKitPresentationTests`

**Ruling.** Full runs read **3801 tests in 3 suites** with `--skip AppKitPresentationTests`, 0 issues, and the `FR-J` line. **Why.**
The screen was locked (`CGSSessionScreenIsLocked = 1`) and the suite's `NSOpenPanel.init()` hangs there (CLAUDE.md counts note). The
unlocked unfiltered figure, 34491ff4's 3803 plus the seven new tests, is **3810**; the nine skipped are the suite's. **Cost if wrong.**
The skipped suite touches no raster code; CI (macOS, unlocked) confirms.
