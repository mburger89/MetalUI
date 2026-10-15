# Pan rasters — design (P3)

Item P3 of the gpui-gap list (user request 2026-10-02; not a plan task). Source: the 2026-10-13 release profile
(`/private/tmp/claude-501/profiling/REPORT.md`) and record §111 §8 "carried". A bracket-canvas pan frame is 9.4 ms against 6.6–6.9
for a drag; paint is 43 % of it: `CoverageRasterizer.rasterize` 7.6 % (about 2,400 allocations a frame), `RasterCache.tint` 5.8 %,
`pathImage` 15 % inclusive. Branch `perf/pan-rasters` from `34491ff4`; divergence labels reserved 485–494 (none taken); decisions
`docs/superpowers/2026-10-14-pan-rasters-decisions.md` (`PN-`). Record `docs/record/118-pan-rasters.md` (landed, 2026-10-14).

**Status: landed** (record 118; rulings `PN-A`…`PN-J`).

## 1. Cause (read from the source at 34491ff4)

`Frame.pathImage` (`RasterCache.swift`) builds `RasterPlacement`, whose `clip` is `enclosing(contentMask) ∩ target`. A wire that
crosses the canvas's `.clipped()` edge has an extent `E ⊄ clip`, so `RasterAnchor` picks `.cut` (`PF-B`, `PF-J`): the key holds
`clip − S`, and any pan changes `S` against the clip: a miss, a rasterization of the cut bbox, a tint of the whole mask (a
diagonal cubic's bbox is mostly alpha 0, but `tint` multiplies every byte), a new `ImageTexture`.

The coverage itself does not depend on the clip: `CoverageRasterizer` is an exact-area accumulator whose output inside a rectangle
is the same whatever the rectangle (edges left of it are folded onto its first column, so a row's running sum differs only by
floating rounding at the 1e-16 level), and the primitive's image already carries `imageMask` (the clip, fractional, rounded
corners), which the GPU applies exactly (`RasterPlacement` comment). The CPU cut is therefore redundant for pixels.

## 2. API

None. No public declaration, no inventory row, no divergence label. Internal additions: `RasterCache.lastTintedPixels`
(a work counter beside `lastTexturesMade`, read by T1/T5 through `@testable`; `SB-E` classifies `StateTable`/`AnimationStore` channels only, so it owes no row, PN-F), `RasterAnchor.Mode`'s doc comment, one
constant `RasterAnchor.overscanLimit`.

## 3. Changes (two parts, both value-identical in intent)

**(b) Tint only what is covered** (`RasterCache.tint`). Zero-fill the RGBA buffer, then per row walk the alpha bytes in 8-byte
words and run the multiply loop only for words with a nonzero byte (a zero alpha gives `(r·0+127)/255 = 0` in all four lanes, so the
bytes equal the full loop). `lastTintedPixels` counts the pixels that went through the multiply. No change to the mask, the
texture size or the image quad.

**(a) Overscan instead of a cut key** (`Frame.pathImage`, `RasterAnchor`). When `placement.localMask == nil`, the anchor would
be `.cut`, and `E` (the existing conservative extent, miter pad included, grown 1) has `area ≤ overscanLimit` and lies inside
`1.5×` of the target on each axis, the path is rasterized over `E` instead of `placement.clip` and keyed `.uncut` (no clip in
the key). The image still carries `contentMask`/`outerMask`, so the GPU cuts it exactly. A whole-device-pixel pan of a wire that
crosses the clip edge then hits (`texture(for:)` returns the same identity). A mask-local raster (mode 3), an extent over the
limit, and every shadow, blur and gradient site keep today's behaviour (PN-C; shadows and gradients carried as P3b).
`overscanLimit` = 1,048,576 device pixels (PN-B).

**(c) R8 coverage with a shader tint** — not built (PN-D): after (a) and (b) the tint runs only on a miss, and the measured
residual decides; owner P3c, which needs `shaders.metal` + `replay.hlsl` + `ReplayFixture` version + replay parity (`TE-AD`).

## 4. The drag (the 78,312 px of two moving wires)

A wire whose one endpoint moves changes its control points: its outline is not a translation of the cached one, so the key
differs by value and a miss is correct (a cubic is not reusable under an endpoint move; resampling is rejected by `PF-D`). A wire
whose both ends move by whole device pixels is a translation and hits already (mode 1, `PF-A`) and, after (a), also when cut. A
sub-pixel translation keeps its fraction `f` in the key and misses (`PF-A`, `PF-D`), unchanged. The drag's gain is (b) only.
The pins state this by a separating arm (T7).

## 5. Pixels

0 px is the goal and the claim to measure: the fourteen offscreen images against `34491ff4` (`docs/probes/demo-pixels/compare.sh`),
and T2 below, a byte comparison of a cut raster against an overscanned raster inside the clip. If a byte differs at the clip edge
the lane quantifies it (count, max delta) and stops for a ruling (PN-A cost); it does not re-take pins.

## 6. Lanes (two, disjoint files)

- **Lane 1 (implementation, Opus):** `Sources/MetalUI/RasterCache.swift`, `Sources/MetalUI/RasterAnchor.swift`,
  `Tests/MetalUITests/PanRasterTests.swift` (new), `Tests/MetalUITests/RasterMathReferenceTests.swift` (T6 arm). All mutations.
- **Lane 2 (measurement, Sonnet):** `docs/probes/pan-rasters/` (a copy of the Prof `bracket-pan`, `bracket-pan-panels`,
  `bracket-value`, `shadows` scenarios pointed at this worktree, an A/B script alternating `34491ff4` and HEAD, load average and
  allocations per frame recorded). Produces ms/frame and allocation tables for the record; never pins.

## 7. Tests (every one red before the change; mutation that must redden it)

All in `PanRasterTests.swift` unless named; work counters only, no sleep; fixture `BracketFixture` where noted (it lives in
`MetalUITestingTests`; the lane copies the minimal wire-in-clipped-canvas tree into `MetalUITests`, as `RasterAnchorTests` does).

| # | Test | Red before | Mutation that reddens it |
|---|------|-----------|--------------------------|
| T1 | `aWirePannedByWholePixelsAcrossTheClipEdgeRasterizesNothing` : after warm-up, 5 whole-pixel pans: `lastRasterizedPixels == 0`, `lastTexturesMade == 0` | rasterized > 0 (cut key) | `overscanLimit = 0` (all cut) |
| T2 | `anOverscannedRasterEqualsTheCutOneInsideTheClip` : bytes of `PathRaster` over `E` vs over `clip`, compared on `clip`, fill and stroke, miter joins, wire cubic | n/a (new equivalence; red-first by running it against a mutant) | extent without the miter pad: stroke tip cut inside the clip |
| T3 | `aRasterOverTheLimitKeepsTheCutKey` : a path with `E` over the limit misses on a pan | green only after (a) exists with a limit; the arm that proves the limit binds | remove the area test |
| T4 | `aPathUnderALocalMaskKeepsItsAbsoluteKey` : rotation + inner clip: pixels rasterized equal the 34491ff4 literal | green on arrival (separating arm of T1) | route mode 3 through overscan |
| T5 | `aDiagonalCubicsTintWorkIsItsCoveredWords` : `lastTintedPixels < ⅓` of the mask area and `≥` the nonzero count | tinted = whole area | tint the whole row |
| T6 | `tintSkippingZeroWordsIsByteForByteTheReferenceLoop` (extends `RasterMathReferenceTests`): masks with zero runs, tails of 1–7 bytes, alpha 1 and 255 | n/a (equivalence) | off-by-one in the tail; treat alpha 1 as zero |
| T7 | `aDragRastersOnlyTheMovingWires` : static wires 0 px, moving wire > 0 each frame, sub-pixel pan misses | green on arrival (the instrument for T1) | n/a, a characterization |

The existing pins that name a cut (`aShadowCutByItsClipIsRasterizedOnEveryMove`, `aBlurOrNestedShadowCutOnlyByItsPaddingIsRasterizedOnEveryMove`,
3.12 `aDiagonalOrClippedGradientRastersInFull`) concern shadows, blurs and gradients and must stay green unmoved; any path pin that
fails is read before it is edited (a reddening pin may be a fix).

Lane order: lane 2's A/B needs lane 1's HEAD; agents run one at a time, so lane 1 commits first (its own record numbers come from the pins, not from lane 2).

## 8. Demo expectation

`METALUI_CANVAS_DEMO=1` pans a canvas of paths: the picture is unchanged (0 px); `FrameWork` shows no path rasterized on a
whole-pixel pan. No new demo section (no 1 MB stack work).

## 9. Human checks

None owed: no look changes. If lane 1 finds a clip-edge byte, a human look at a pan at 2× is added as group PN.

## 10. Deferred

- Overscan for shadows, blurs, gradient rasters (`ShadowPaint`/`BlurPaint`/`GradientPaint` sites): **P3b**, a measured follow-up (their `E` includes `BoxBlur.padding`, so the limit binds earlier).
- R8 coverage, shader tint: **P3c**, only if the residual after (a)+(b) is large; shader change on both renderers.
- Per-frame allocation of the rasterizer's `cells`/`alpha` arrays (a pooled scratch buffer): **P3d**, `MetalUIPath` imports nothing, so a pool must be a plain struct passed in.
