# 118 — Pan path rasters (P3)

Branch `perf/pan-rasters` from `34491ff4`. Not a plan task: item P3 of the gpui-gap list (user request 2026-10-02), from the
2026-10-13 release profile and record §111 §8 "carried". Spec `docs/superpowers/specs/2026-10-14-pan-rasters-design.md`; rulings
`PN-A`…`PN-J` in `docs/superpowers/2026-10-14-pan-rasters-decisions.md` (next unused `PN-K`). Divergence labels reserved 485–494:
none taken. No public declaration (inventory and undocumented scripts print nothing).

**Status: LANDED (both lanes verified `ok`; Record phase merged master `d3ebfa18`, no record number collided: master's last was 117).**

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
ms/frame and allocations: §7 (dated measurements, not pins).

## §7 Measurements (lane 2, dated 2026-10-14, never pins)

Probes `docs/probes/pan-rasters/` (`ab.sh`, `counters.sh`, `README.md`, raw `measurements-2026-10-14.txt`): release Prof harness, A/B
alternated per round, five rounds, 34491ff4 against 29830625. The Mac was shared: 1-minute load 4.4 to 28.8, rounds 1 and 2 noisy,
so read ratios. Median over rounds of each run's median ms/frame (bracket-value: mean ms per loop iteration):

| scenario | 34491ff4 | HEAD | delta |
|---|---|---|---|
| bracket-pan | 7.56 | 6.53 | -14 % |
| bracket-pan-panels | 7.42 | 6.60 | -11 % |
| bracket-value (drag) | 5.16 | 4.58 | -11 % |
| shadows | 1.238 | 1.242 | noise (shadow keys unchanged, `PN-C`) |

HEAD was faster in every paired round for the three bracket scenarios. Allocations, bracket-pan, 400 frames after warm-up: 18,981
allocs and 7.97 MB per frame before, 16,342 and 5.84 MB after (-2,639, -14 %; the profile's estimate for the rasterizer was about
2,400). Work, 88 steps (debug): pan 11,791,732 rasterized pixels before, 134,688 after (the cold frames; 0 in steady state), 7,904 tinted,
2 textures made; drag 82,353 rasterized per drawn frame before, 87,450 after (+6 %: the extent over the clip-cut bounds, plus
overscan), tinted 5,361 per drawn frame (6 % of rasterized). Reading for P3c: what remains in the drag is `CoverageRasterizer`
itself, which R8 does not reduce; R8 would quarter the texture bytes and drop 450 K tinted pixels per 84 frames. Not justified.

## §8 Record phase

Merged master `d3ebfa18` (clean, no conflict). The suite and counts were re-taken on the merged tree after `swift package clean`
(screen locked: `--skip AppKitPresentationTests`, `PN-J`):
**3862 tests in 3 suites passed** (`--skip AppKitPresentationTests`, 9 tests, locked screen; unlocked expected 3871 = master's 3864 + 7 new `PanRasterTests`/pin tests), `FR-J no-argument frame: succeeded=true`, 0 `error:`, 0 `warning:` lines in the log, 244 typecheck guards (master's, no new guard).

Docs: no divergence, no public declaration, no human check owed (the draw-time cut is pixel-identical, §4, and the fourteen images
read 0 px; nothing here is a look), no migration note (no requirement added). Open at merge: an unlocked run (expect 3810 + master's
growth) and `swift build --build-tests` 0 `warning:` on the default build system.
