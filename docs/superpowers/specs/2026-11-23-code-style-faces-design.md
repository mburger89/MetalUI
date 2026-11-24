# CodeStyle italic and weight (Sift gap G15) — design

**Why:** a `CodeStyle` can set only a foreground, a background and an underline, so a `CodeView` cannot draw comments in italic or keywords in bold. Sift's SQL editor wants "comments `.secondary` italic"; Alloy will want bold keywords. Class M (MetalUI-only API), no divergence (labels stay 236 live, next 244). New ruling `CV-BY`, amending `CV-L` and `CV-M`.

## Why `CV-L`'s reason no longer holds

`CV-L` excluded weight and slope because "a different face would change where glyphs go". Today:

- **The line cache already depends on style runs.** The `CV-M` key includes `styleDigest` (`CodeLineLayout.swift:17`), built from each run's byte length and `CodeStyleID` (`CodeDecorations.swift:1459-1467`). Shaping is already split at run boundaries, with one `TextRunStyle(font:)` per run (`CodeLineLayout.swift:260, 284-310`).
- **Caret, hit testing, selection, backgrounds and underlines read the shaped line** (`CodeLineLayout.x(ofByte:)` and `byte(atX:)`), not a fixed grid. CodeView never wraps lines.
- **A grid is assumed only in fast paths and estimates:** multi-caret `columnX` and `offsetInRow` for ASCII lines (`CodeEditSession.swift:672-695`), off-screen column selection (`CodeViewPlan.swift:411-419`), the long-line column window (`CodeViewPlan.swift:1110-1123`), and the extent estimate (`CV-O`). These are exact whenever bold and italic keep the regular width.
- **Common monospaced families keep one width in every face.** Measured from the `hmtx` tables: SF Mono 1266/2048 for upright and italic, with no width change along the weight axis; Menlo 1233 for regular, bold, italic and bold italic; Courier New 1229 for regular, bold and italic. Not measured, from documentation: Consolas, Cascadia Mono, DejaVu Sans Mono, Liberation Mono and Noto Sans Mono are also constant within each family. The portable text system shapes unhinted (`FT_LOAD_NO_HINTING`), so equal widths in the font file give equal positions on screen.

## Approaches

| | Approach | Verdict |
|---|---|---|
| **(a)** | **Real faces.** Each run carries a face code; the text system resolves the weight and slope; a run is shaped in its own face. | **Chosen.** Same on every platform. Zero cost for apps that use no faces. |
| (b) | Faked italic (slanted at draw time) and faked bold (stroked or drawn twice), keeping positions. | Rejected. Breaks MetalUI's no-faking rule (`Font.swift:114`, `PortableFontResolver.swift:146`). Needs rasteriser changes on both text systems and a fake-bold `FontKey` part, which breaks PS-D. Renders differently per platform. Needs a divergence. |
| (c) | Real faces, placed on the regular face's widths. | Rejected. Needs a cluster index in `StyledGlyph` on both platforms, and only helps families with uneven widths; none measured has them. |

## Design

- **API:** `CodeStyle(foreground:background:underline:italic: Bool? = nil, weight: Font.Weight? = nil)`.
  - `nil` keeps the lower layer's value; `false` and `.regular` turn the face off.
  - Names follow `Text.italic(_:)` and `Text.fontWeight(_:)`.
  - No `font:` field: a different family or size would break the fixed row height.
  - `CodePaintedRun.style` reports the face that wins.
- **Layering:** for each stretch of text, the highest layer that sets `italic` wins it, and likewise `weight`, independently of `foreground`.
- **Face code:** a `UInt8` per run (a weight index plus an italic bit; 0 means the view's own face), stored in the run partition.
  - It goes into `digest(of:)` only when it is not 0, so a view with no faces keeps the same digests and cache keys as master.
  - An `anyLayerHasFaces` flag, like `anyLayerHasUnderlines`, skips all face work and all font resolution until some layer sets a face.
- **Resolution:** the view's font descriptor with that weight and slope, resolved by the text system and cached by (base `FontKey`, code). Nothing is faked: a family without the face keeps its upright or regular face, as `Font.italic()` does (probe F4b).
- **Layout:**
  - A line with faces takes its caret offsets per run, shifted to each run's start (`laid.segments[i].minX`).
  - Its glyphs sit on the view font's baseline; the baseline value is already cached in `underlineMetrics`.
  - Positions always come from shaping.
- **Named limit:** for a family whose faces have different widths, the column fast paths, off-screen column selection and the long-line window are approximate.
- **Out of scope:** a colour-only restyle that reshapes nothing (a digest made of run lengths plus face only). It is a possible follow-up, not part of this change.

## Tests

1. `aStyleCarriesItalicAndWeightAndInternsThem`
2. `theHighestLayerThatSetsAFaceWinsPerStretch`: italic and weight each win independently of `foreground`; a higher `italic: false` turns italic off.
3. `aFaceFreePartitionDigestsAsBefore`: the digest equals a literal value taken from master.
4. `colourOnlyHighlightsCostWhatMasterCosts`, the steady-frame test: 5 idle frames shape 0 lines and resolve 0 faces; the request costs equal `changeBarsCostWhatNoneCost`'s; the warm-scroll allocation ceiling of 910 is kept.
5. `aFaceRestyleReshapesOnlyTheRowsItChanges`: adding italic to one visible row shapes exactly 1 line.
6. `anIdleRepaintWithFacesRecomputesNothing`
7. `anItalicRunShapesInTheItalicFace`
8. `aBoldRunKeepsCaretHitAndSelectionOnItsShapedAdvances`, using proportional Noto Sans Bold.
9. `aFacedLineSitsOnTheViewFacesBaseline`
10. `aFamilyWithoutAnItalicKeepsItsUprightFace`
11. `paintedRunsReportTheWinningFace`
12. `aVirtualRowRunCanBeItalic`
13. `monospacedFacesKeepOneAdvance`:
    - On macOS, with CoreText: SF Mono and Menlo in regular, bold, italic and bold italic give equal caret offsets over 40 ASCII characters.
    - A portable-text arm over DejaVu Sans Mono, Consolas or Cascadia Mono, skipped when the font is not installed.

Tests 7–10 use a separate resolver that adds `NotoSans-Bold.ttf` and `NotoSans-Italic.ttf` (OFL). Keep them out of `harnessTextSystem`, so other tests' `.bold()` results do not change.

## Tasks

- **T1, API:** the fields and doc comments, plus the inventory-map row (`closeout-inventory-map.tsv:305`). Test 1.
- **T2, run styling:**
  - add `face` to the run tuple at all 9 declarations;
  - add `anyLayerHasFaces`, set beside `anyLayerHasUnderlines` and reset on resync;
  - pick the face per field in `computeForeground`;
  - add the conditional face term to the digest;
  - carry the face through `slice`, `splittingParts`, virtual-row styling and `paintedRuns`.
  - Tests 2, 3, 11, 12.
- **T3, layout and fonts:**
  - add `CodeLineCache.face(_:base:request:system:) -> FontKey` and a `faceResolutions` counter;
  - resolve faces in `makePlan` only when the decorations have faces;
  - `buildCodeLine` takes `faceFonts: [FontKey]`, and uses per-run caret offsets and the baseline shift;
  - thread these through `lineLayout` and its three callers.
  - Tests 7–10.
- **T4, cost tests:** tests 4–6.
- **T5, platform check:** the Noto Bold and Italic test fonts, an update to `SOURCES.md`, and test 13.
- **T6, docs:**
  - append `CV-BY`, and add "Amended by `CV-BY`" under `CV-L` and `CV-M`;
  - move the next unused id to `CV-BZ`, keeping `CV-BX` reserved;
  - write the record, the rules-shard sentence, `api-overview`, the CLAUDE.md counts, and `cp` to AGENTS.md.
