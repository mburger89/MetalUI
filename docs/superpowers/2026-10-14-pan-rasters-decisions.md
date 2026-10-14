# Pan rasters — decisions

Rulings for P3 (the pan path-raster miss, user request 2026-10-02). Spec:
[`specs/2026-10-14-pan-rasters-design.md`](specs/2026-10-14-pan-rasters-design.md). Record: `../record/118-pan-rasters.md`
(Record phase). Branch `perf/pan-rasters` from `34491ff4`; divergence labels reserved 485–494 (none taken).

**Next unused id: `PN-F`.** (Moves in the commit that appends a ruling; read the last `## PN-` heading if they disagree.)

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
