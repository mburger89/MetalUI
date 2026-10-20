# 124 — Raster overscan for shadows, blurs and gradients (P4, lane 1: P3b)

Branch `perf/raster-overscan` from `4d91f27f`. Not a plan task: item P4 of the gpui-gap list (user request 2026-10-02), the carried half
of record §118 (`PN-C`: "overscan for them is P3b"). Spec `docs/superpowers/specs/2026-10-20-raster-overscan-design.md`; rulings
`OS-A`…`OS-O` in `docs/superpowers/2026-10-20-raster-overscan-decisions.md` (next unused `OS-P`). Divergence labels 545–554 reserved:
none taken. No public declaration. **This record covers lane 1 only; lane 2 (P3d, pooled scratch) is gated by `OS-H` and is recorded by its own lane.**

## §1 What changed

- `shadowImage`, `blurImage` and `gradientImage`'s full raster call `RasterAnchor.overscanned` as `pathImage` does (`OS-A`): over the
  kind's conservative extent `E` (`RasterAnchor.shadowExtent`/`blurExtent`/`gradientExtent`, the expressions the keys already used,
  `OS-B`), keyed `.uncut`, the image's content mask cutting at draw time; mode 3 and the gradient strip are untouched (`OS-E`, `OS-G`).
  Same predicate and limit as `PN-B` (`OS-D`).
- `RGBALayer.init(mask:color:)` returns `.empty` for an empty mask (`OS-N`): a latent trap at 4d91f27f (`ImageTexture: 0×12 has a zero side`
  for a blurred line of text whose glyphs lie outside the clip), reached by S4.
- Pins amended because they read a cut raster's bounds (`OS-A`): `BlurTests` 3.20, `GradientRasterTests` 3.12, `ShadowTests` 3.20,
  `RasterAnchorTests` L1.6/L1.6b (renamed).

All three kinds landed: S4 read 0 differing clip bytes for each (spec's fallback unused).

## §2 Red first (commit `8b7e3707`, against the unchanged keys)

S1 (shadow), S2 (blur), S3 (full gradient, radial and diagonal; the vertical strip is the green separating arm) and S4's counter arms
failed at 4d91f27f with `rasterized/blurred/made > 0` and a different texture on each of five whole-pixel pans. S5, S6, S7, S8 are green
by design (equivalence, limit, mode 3, characterization).

## §3 Suite

Screen locked, so `--skip AppKitPresentationTests` (`PN-J`: `NSOpenPanel.init()` hangs; a first unfiltered run hung there and was killed by
pid). **3972 tests in 4 suites passed** with that suite skipped (4d91f27f's 3971 unfiltered plus the new tests of `RasterOverscanTests`, S1–S8, S10 and S11, less the skipped suite), also 3972 passed under `METALUI_VERIFY_RETAINED=1 METALUI_VERIFY_LAYOUT_MEMO=1` with no trap; `swift build --build-tests` (default build system) 0 `warning:`; inventory and undocumented scripts print nothing; the Linux image (`MetalUIPath` untouched) was not re-taken; `FR-J no-argument frame: succeeded=true`, 0 `error:`.

## §4 Mutations

Run on the committed tree, each restored with `git checkout -- Sources`, `git status --short` clean after each. **Filtered** to
`RasterOverscan|ShadowTests|BlurTests|GradientRasterTests|RasterAnchorTests|PanRasterTests|BracketNode` (83 tests; a full run per
mutation was not afforded: the unfiltered suite is the baseline above), so a test outside that set that a mutation reddens is not listed.

| Mutation | Reddened |
|---|---|
| M1 `overscanLimit = 0` | S3 (20), `aWirePanned…` (10), S1 (10), S2 (10), S5 (8), `aShadowCutByItsClipIsRasterizedOnceAndCutAtDrawTime` (6), `aBlurOrNestedShadowCutOnlyByItsPaddingIsRasterizedOnceAndCutAtDrawTime` (6), `aPannedWireDrawsTheColdRendersPixels` (2) |
| M2a shadow extent pad 0 | S5 (22), S6 (4) |
| M2b blur extent pad 0 | S5 (22) |
| M2c gradient extent not grown (`grownBy: 0`) | **nothing: survived** (the 1 px margin is conservative; as `PN-I`) |
| M3a call dropped, `shadowImage` | S1 (10), `aShadowCutByItsClip…` (6), `aBlurOrNestedShadow…` (3), S5 (2) |
| M3b call dropped, `blurImage` | S2 (10), `aBlurOrNestedShadow…` (3), S5 (2) |
| M3c call dropped, `gradientImage` | S3 (20), S5 (4), `aDiagonalOrClippedGradientRastersInFull` (2) |
| M4a/M4b outside-the-clip drop removed, shadow, blur | **nothing: survived** (`OS-O`: unreachable in a sweep of every pixel) |
| M4c outside-the-clip drop removed, gradient | survived the original nine; **S11 added, reddened (4 issues)**, green unmutated |
| M5 `rasterClip = placement.clip` while keyed `.uncut` (shadow) | S5 (22) |
| M6 mode 3 routed through overscan (`mode != .uncut`) | **S7 not reddened**; five others: `aShadowInsideARotationOrScaleHasItsOffsetTransformed`, `aPathUnderALocalMaskKeepsItsAbsoluteKey`, `aGradientUnderARotationFollowsTheTransform`, `aFadingTransitionScalesAGradientsAlpha`, `aFadingTransitionScalesABlursAlpha` (1 each). S7 is a characterization of the miss, not an instrument for mode 3 |
| M7 empty-mask guard dropped (`OS-N`) | trap, `ImageTexture: 0×12 has a zero side`, in S4 (the suite aborts; S10 is its named pin) |

The drop of the content mask at draw time is not a separate site (it is `RasterPlacement.quad`'s); M5 and S5's outside-the-canvas count
are its instrument. Survivors M2c, M4a, M4b are named, not hidden.

## §5 Pixels and bytes

`docs/probes/demo-pixels/compare.sh <scratch> 4d91f27f HEAD` (HEAD `10a9006a`; controls as recorded): all fourteen images 0 differing
pixels and scene identical. S4: 0 clip bytes differ between the raster over the clip and over `E`, for rect, rounded rect, path, glyph,
image and a scale effect, fill and stroke gradients, at 1× and 2×, the clip over the blur tail.

## §6 Measurements (dated 2026-10-20, shared Mac, load 6–9, release, `ab.sh 4d91f27f HEAD 3 3`)

Never pins. Work counters (`counters.sh`, debug, 88 steps; `shadow-pan` is the new 6×4 grid of shadow, blur and radial cards in a
420×260 clipped region panned by whole points; `shadow-drag` one card changing width):

| scenario | 4d91f27f rasterized / blurred / tinted px, textures | HEAD |
|---|---|---|
| shadow-pan | 11 285 304 / 35 241 984 / 9 565 752, 1207 | 0 / 0 / 0, 0 |
| shadow-drag | 8 477 120 / 21 522 816 / 6 816 784, 691 | 1 337 600 / 0 / 0, 85 |
| bracket-value, bracket-pan | unchanged (no shadow, blur or gradient in the fixture) | identical |

Release median ms/frame (rounds 1–3, base then head): shadow-pan 7.86 / 7.75 / 8.05 → 0.41 / 0.41 / 0.42; shadow-drag 7.48 / 7.57 /
7.83 → 0.64 / 0.64 / 0.67; bracket-pan 5.46 / 5.79 / 5.47 → 5.76 / 5.77 / 5.42 (noise); bracket-value median 0.000 both. Main-thread
allocations of 400 frames: shadow-pan 788 113 allocs, 4.53 GB → 601 074, 0.10 GB; shadow-drag 779 395, 3.27 GB → 670 564, 0.24 GB.
The bracket fixture holds no shadow, blur or gradient, so lane 1 has no win to claim there; the win is on the shadow scenarios.

## §7 Deferred

Mode 3 overscan (`OS-E`); the half-visible card's one larger first raster (`OS-F`, bounded by 2^20); lane 2 (`OS-H`).
Human check `RO1` (record phase): scroll a shadowed, blurred and gradient list across a panel edge on AppKit and SDL, no seam,
flicker or clipped glow.
