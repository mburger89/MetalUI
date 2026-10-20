# Raster overscan — decisions

Rulings for P4 (user request 2026-10-02). Spec: [`specs/2026-10-20-raster-overscan-design.md`](specs/2026-10-20-raster-overscan-design.md).
Record: `../record/124-raster-overscan.md` (at the Record phase). Branch `perf/raster-overscan` from `4d91f27f`; divergence labels
reserved 545–554 (none taken).

**Next unused id: `OS-Q`.** (Moves in the commit that appends a ruling; read the last `## OS-` heading if they disagree.)

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

## OS-L — The scratch is borrowed for one call, never across a callback; no static, no returned alias

**Ruling.** `RasterScratch` is passed `inout` into a single `rasterize`/`blur` call and is not held while any closure, `cache.coverage(for:make:)`
or nested `silhouette`/`blurLayer`/`gradientPixels` runs (a nested shadow or blur leaf rasterizes while the outer one is mid-silhouette:
the outer must have released its borrow, or the nested call takes a fresh scratch). It is never a global or static (thread-safety by
construction, `GX-B`), and a returned `alpha`/`out` never aliases it (the cached result is its own buffer). P1/P2 add an arm with a
nested leaf (shadow of a blurred leaf) against a fresh-scratch run, byte for byte. **Why.** The design's "separate stored property"
argument covers exclusivity only for the flat case; a nested leaf re-enters through `make`. **Cost if wrong.** An exclusivity trap or
stale cells (changed bytes): the nested arm and the zero-fill mutations catch it.

## OS-M — If the gate rules the pool out, only P3 and the allocation floor land

**Ruling.** The spec's lane 2 text said the P1, P2 and P4 tests would land "as characterizations" without `RasterScratch`; they cannot
compile or be red with no scratch API, so that is rejected. If OS-H's gate fails, lane 2 lands no `RasterScratch`, no P1/P2/P4, only
the dated numbers in the record and (optionally) P3 rewritten as a plain allocation-floor characterization of today's raster
(green on arrival, listed as such). **Why.** A test that cannot be red is not an instrument. **Cost if wrong.** None.

## OS-N — An empty colour mask makes an empty layer (a latent trap found by S4)

**Ruling.** `RGBALayer.init(mask:color:)` returns `.empty` for a mask whose rect is empty. **Why.** `blurLayer`'s `colourRaster` resamples a
glyph or image into `resampleRect(bounds)`, the bounds' enclosure cut by the raster clip; a glyph wholly outside the clip's reach
(a long blurred line against a narrow clip) gives a zero-width mask (`0×12`), and `RasterCache.tint` then built an `ImageTexture`
that traps on a zero side (`ImageTexture: 0×12 has a zero side`). The trap predates this branch (4d91f27f; S4 reached it by calling
`blurLayer` over the production cut clip) and is independent of overscan. **Pin.** S10 (`aBlurredLineOfTextWithGlyphsOutsideTheClipDoesNotTrap`),
mutation: drop the guard. **Cost if wrong.** None: an empty layer composes as nothing, as every other empty `RGBALayer` does.

## OS-O — The outside-the-clip drop of a shadow or blur is defensive and unobserved; a gradient's is pinned (S11)

**Ruling.** The `rasterClip != placement.clip, placed.intersection(placement.clip).isEmpty` return stays in `shadowImage`, `blurImage` and
`gradientImage`, but only the gradient's is pinned: S11 (`anOverscannedRasterWhollyOutsideTheClipDrawsNoImage`, a diagonal and a radial
gradient swept 2 device pixels at a time across both clip edges at 1x and 2x) reddens when it is removed from `gradientImage`. Removing it
from `shadowImage` or `blurImage` reddened **nothing**, in S5, in S11 over all four kinds swept every pixel (about 1900 cold renders per
site), or in the suites named in the record: for a shadow and a blur the raster's tight rect (silhouette bounds grown by the padding) was
never found wholly outside the clip while `E` (grown one more pixel) meets it. **Why keep it.** It is the same line `PN-G` pins for paths,
costs one rect test, and its absence would draw a masked-out image rather than change a pixel; it is not claimed as pinned. **Cost if wrong.**
At worst one fully masked image per such card per frame (counted, not seen). `OS-A`'s three sites each still own their call; the gradient
site is the pinned one.

## OS-P — The gate passes on allocated bytes; `RasterScratch` is built (cells, the blur's two planes and column sums)

**Ruling.** Lane 2 measured a throwaway prototype (static buffers, never committed) against `6ab9babd` with `ab.sh`, five alternated
release rounds, load 27-81 on a shared Mac (dated 2026-10-20). `shadow-drag`: main-thread allocated bytes of 400 frames
**244 813 208 to 194 453 304 (-20.6 %)**, allocations 670 564 to 670 175 (-389: the win is size, not count); the figure is
deterministic (the same code twice read the same bytes: `shadow-pan` 100 928 936 on both sides, where every raster hits the cache). Median
ms/frame of `shadow-drag`, base then head, rounds 1-5: 0.675/0.681, 0.659/0.669, 0.672/0.667, 0.656/0.655, 0.656/0.649 (head lower in 3 of
5 rounds, by at most 1.1 %: **below the 3 % bar**). `bracket-value` median 0.000 on both sides (the fixture holds no shadow, blur or
gradient, so the pool is idle there). The gate is "bytes down at least 10 % **or** median down at least 3 %": the bytes arm passes in
every round (a deterministic figure), the time arm does not. **Why build it anyway.** The gate as written is met; the saving is the
first-touch `cells` and blur planes of every miss (8 and 8 + 4 B per raster pixel), not a time win, and the record says so.
**Cost if wrong.** A `package` type and one `inout` per rasterization call site; the pins hold it equal byte for byte.
**Design as built.** A value `RasterScratch` (`MetalUIPath`, imports nothing) with four slots (`cells`, `Int32` planes `a`, `b`, column
`sums`); a buffer is **taken out** (slot left empty) zero-filled and **returned** after the call, longer than `capacityLimit` (2^22 elements)
dropped, so a re-entrant caller finds an empty slot and allocates its own (`OS-L` by construction, no static). `CoverageRasterizer.rasterize`,
`PathRaster.fill/stroke` and `BoxBlur.blur` gain `scratch:` overloads; the old spellings forward a fresh scratch. `RasterCache.scratch` is
passed `&cache.scratch` at the nine call sites, each for one call. Pins: `RasterScratchTests` P1-P4 (MetalUIPathTests and MetalUITests).
