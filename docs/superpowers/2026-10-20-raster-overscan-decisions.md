# Raster overscan — decisions

Rulings for P4 (user request 2026-10-02). Spec: [`specs/2026-10-20-raster-overscan-design.md`](specs/2026-10-20-raster-overscan-design.md).
Record: `../record/124-raster-overscan.md` (at the Record phase). Branch `perf/raster-overscan` from `4d91f27f`; divergence labels
reserved 545–554 (none taken).

**Next unused id: `OS-L`.** (Moves in the commit that appends a ruling; read the last `## OS-` heading if they disagree.)

Evidence: the code at `4d91f27f` (`RasterAnchor.swift`, `RasterCache.swift` `pathImage`, `Shadow.swift`, `Blur.swift`,
`GradientRaster.swift`, `MetalUIPath/Rasterizer.swift`, `BoxBlur.swift`), record §118 (`PN-A`…`PN-K`), §90, §111, §119. No
SwiftUI-facing claim is made, so no probe is owed (`OS-J`).

## OS-A — Shadows, blurs and full gradients take `PN-A`'s overscan, each kind only with its bytes proven equal

**Ruling.** `shadowImage`, `blurImage` and `gradientImage`'s full raster call `RasterAnchor.overscanned` as `pathImage` does,
rasterize over `E` keyed `.uncut`, and let the image's content mask cut at draw time. A kind lands only if its byte-equality test
(S4) is green: the raster over `E` equals the cut raster inside the clip. **Why.** The silhouette coverage and the gradient's
per-pixel colour are clip-independent, and the box blur is integer with zero padding, so a pixel's value depends only on input within
`BoxBlur.padding` of it, inside `E`'s reach; the CPU crop buys nothing and costs a miss per pan for every card straddling a panel
edge. **Evidence to take.** S4 per kind at 1× and 2×, the fourteen images 0 px. **Cost if wrong.** A byte differing from a changed
float summation order at the clip edge (the `PN-A` risk, measured 0 for paths): that kind keeps today's keys and the record names it.

## OS-B — The extents are the ones the keys already use

**Ruling.** No new extent function: shadow and blur use `RasterExtent.of(leaf)` grown by `BoxBlur.padding(sigma) + 1` (nested reach,
`PF-J` item 1), gradient uses `paint.bounds` grown 1. **Why.** They are what decides `.uncut` today, so they are already pinned
conservative; a second function would drift. **Cost if wrong.** A too-small extent crops a glow inside the clip: S4 puts the clip over
the tail, with the pad mutated to 0, to catch exactly this.

## OS-C — The raster clip is `E`; the make closures are unchanged

**Ruling.** Only the clip passed to the existing `shadowCoverage`/`blurLayer`/`gradientPixels` and the key changes (`rasterClip`), as
in `pathImage`; nothing inside them is edited by lane 1. **Why.** They already crop to what they are given and add `BoxBlur.padding`
to reach; silhouettes outside the leaf's bounds rasterize nothing, so a larger clip costs no empty work. **Cost if wrong.** None
beyond OS-A's.

## OS-D — One limit, one predicate

**Ruling.** `overscanLimit` (2^20) and the half-target bound of `PN-B` apply unchanged. **Why.** `E` for a blurred leaf includes the
padding, so a large radius (or a window-sized card) binds and keeps today's cut key: the behaviour is exactly today's for the cases
where overscanning would be expensive. **Cost if wrong.** Too low: big shadows keep missing on a pan (performance only). Too high:
a larger one-off first raster. Re-takeable by the constant; S6 pins that a limit exists, not its value.

## OS-E — Mode 3 stays absolute

**Ruling.** A placement with a local mask is never overscanned (`overscanned` already returns `nil` for non-`.cut`). **Why.** The
local mask's key is the absolute one by `PF-B`; no measured byte-equal case exists. **Cost if wrong.** A masked card cut by a panel
edge misses on a pan (performance only, deferred in the spec).

## OS-F — The retained texture can be larger; the cost is bounded and accepted

**Ruling.** An overscanned raster is at most `E.area <= 2^20` pixels (4 MiB RGBA plus 1 MiB coverage), held while a frame touches it
(the cache's existing lifetime, unchanged). **Why.** A half-visible card rasterizes its whole extent once instead of its visible half
on every pan step. **Cost if wrong.** A higher resident peak where many large shadows are on screen: the limit is the constant to
lower.

## OS-G — The gradient strip is untouched

**Ruling.** `stripImage` keeps its own translation-free key; overscan applies to the full raster only. **Why.** The strip already
hits on a pan (S3's separating arm is green before the change).

## OS-H — The pooled scratch is built only if it measures

**Ruling.** Lane 2 lands `RasterScratch` only past the gate in the spec (allocated bytes per drawn frame −10 % or median ms −3 % in 4
of 5 paired release rounds, on `bracket-value` or `shadow-drag`); otherwise it records the numbers and rules the pool not justified,
landing only its pins as characterizations. **Why.** After lane 1 a steady pan rasterizes nothing, and only `cells`/`a`/`b`
(not the returned buffers) can be pooled, so the win is confined to misses and is unproven; §118 ruled P3c out on the same grounds.
**Cost if wrong.** A skipped optimization the drag would have felt (small): the numbers are in the record to re-open it.
Design if built: a `package` value `RasterScratch` (MetalUIPath, imports nothing, bit-identical, `GX-B`), owned by `RasterCache`,
zero-filled on every use (stale cells change bytes), capacity capped.

## OS-I — Two lanes, sequential in one worktree, split by function

**Ruling.** Lane 1 edits the three `*Image` functions, `RasterAnchor.swift` and its tests; lane 2 edits `MetalUIPath`, `RasterCache`'s
scratch property and only the `CoverageRasterizer()` creation lines inside `silhouette`/`colourRaster`/`gradientPixels`. Lane 2 runs
after lane 1. **Why.** The call sites share four files; the edited lines are disjoint and the worktree runs one agent at a time.
**Cost if wrong.** A trivial textual merge, resolved by the later lane.

## OS-J — No SwiftUI probe

**Ruling.** No probe: the item is internal and pixel-identical, no SwiftUI claim rests on it. gpui's content-mask-as-scissor is the
precedent for the draw-time cut (it makes no claim either). **Cost if wrong.** None: any pixel difference is S4/S5/the fourteen
images, not a SwiftUI answer.

## OS-K — A shadow-pan scenario, because none exists

**Ruling.** The probe directory gains Prof scenarios `shadow-pan` and `shadow-drag`; ms/frame, allocations and counters are dated
measurements beside `docs/probes/pan-rasters/`'s, never pins (pins count work). **Why.** `shadows` is static and the bracket fixture
holds no shadow, blur or gradient, so neither lane has a measured win to show on the existing scenarios. **Cost if wrong.** None.
