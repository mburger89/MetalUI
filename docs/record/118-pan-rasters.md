# 118 — Pan path rasters (P3)

Branch `perf/pan-rasters` from `34491ff4`. Not a plan task: item P3 of the gpui-gap list (user request 2026-10-02), from the
2026-10-13 release profile and record §111 §8 "carried". Spec `docs/superpowers/specs/2026-10-14-pan-rasters-design.md`; rulings
`PN-A`…`PN-J` in `docs/superpowers/2026-10-14-pan-rasters-decisions.md` (next unused `PN-K`). Divergence labels reserved 485–494:
none taken. No public declaration (inventory and undocumented scripts print nothing).

**Status: lane 1 (implementation and pins) LANDED; lane 2's ms/frame and allocation tables are lane 2's section (not in this lane).**

## §1 What changed

- `RasterCache.tint` zero-fills its RGBA buffer and runs the multiply only for the 8-byte words of coverage holding a nonzero byte
  (tail bytes one by one), byte for byte the reference loop (T6); `RasterCache.lastTintedPixels` counts the pixels multiplied
  (`PN-D`).
- `Frame.pathImage`: a path with no local mask whose conservative extent `E` (`RasterAnchor.pathExtent`, bounds with the stroke
  pad, grown 1) meets the clip, has area at most `RasterAnchor.overscanLimit` (2^20) and lies within half its size of the window on
  every side is rasterized over `E` and keyed `.uncut`; the image's content mask cuts at draw time (`RasterAnchor.overscanned`,
  `PN-A`, `PN-B`). A placed mask wholly outside the clip draws no image (`PN-G`). Mode 3, shadows, blurs and gradients unchanged
  (`PN-C`).

## §2 Red first (commit `51c14251`, against the unchanged keys, counter added)

- T1 `aWirePannedByWholePixelsAcrossTheClipEdgeRasterizesNothing`: 10 issues (`w.rasterized == 0 && w.made == 0` and the same-texture
  expectation, each of five pans).
- T5 `aDiagonalCubicsTintWorkIsItsCoveredWords`: `w.tinted * 3 < area` failed.
- T3, T4 (literal 22736 px, 34491ff4's), T7 green on arrival by design (separating arms and a characterization).
- T2 and T6 are equivalences written after the implementation; their instruments are the mutations below.

## §3 Suite and mutations (every run the full unfiltered-but-for-one-suite native suite)

Screen locked: `--skip AppKitPresentationTests` (`PN-J`). Baseline with the change: **3801 tests in 3 suites passed**, `FR-J
no-argument frame: succeeded=true`, 0 `error:`; 34491ff4's 3803 plus seven new tests is 3810 unlocked. Two pins reddened by the
change were read before editing (`PN-G`, `PN-H`).

| Mutation (committed tree, restored from a copy, `git status` clean after) | Reddened |
|---|---|
| M1 `overscanLimit = 0` | T1 (10 issues), `theCacheKeyIncludesColourTransformAndClip` |
| M2 `pathExtent` grown by -3 | **nothing: survived** (`PN-I`) |
| M2b `PathPaint.bounds` stroke pad made 0 | T2 (2 issues), `theBracketNodeDragRebuildsTheWholeWindow` (3 arms) |
| M3a area test removed | T3 (2) |
| M3b window test removed | T3 (2) |
| M4 mode 3 routed through overscan | T4, `aRotatedPathIsRasterizedInDeviceSpace` |
| M5 tint every word | T5 |
| M6a tail off by one | `aCanonicalRasterEqualsTheAbsoluteOne` (4), `aResampledLeafAtAnIntegerCoincidenceMayGainItsBleedColumn`, `tintMatchesItsReferenceCopy`, T6 |
| M6b alpha 1 treated as zero | T6 |
| M7 outside-the-clip drop removed | `theBracketNodeDragRebuildsTheWholeWindow` (.value, .environment, .panels) |

T7 is a characterization and has no mutation (spec §7). A guard-type check is not owed: no new typecheck guard.

## §4 Pixels

`docs/probes/demo-pixels/compare.sh <scratch> 34491ff4 HEAD`, controls as recorded: all fourteen images 0 differing pixels and
scene identical. T2: 0 clip bytes differ between the raster over the clip and the raster over the extent, for a stroked cubic, a
mitred triangle and a filled blob, at 1× and 2×; so the clip-edge deviation feared by `PN-A` did not occur.

## §5 The drag (PN-E)

T7: with a static and a moving wire, frames 2–4 rasterize exactly what the moving wire alone does, and a half-pixel pan misses. A
cubic whose endpoint moves is a new function of its key; whole-pixel translations hit.

## §6 Carried

Overscan for shadows, blurs and gradients (P3b); R8 coverage with a shader tint (P3c, `TE-AD`); a pooled rasterizer scratch (P3d);
ms/frame and allocations per frame: lane 2.
