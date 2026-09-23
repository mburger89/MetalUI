# 31 — Portable font metrics and multi-line emission, 2026-09-23

Branch `feat/portable-lines-emit`, from `feat/portable-linebreak` (PR #12,
record §30). Spec: `docs/superpowers/specs/2026-09-23-portable-lines-emit-design.md`,
rulings `LB-F` and `LB-H`…`LB-K` (next `LB-L`). Roadmap item 2 of
`docs/superpowers/plans/2026-09-23-cross-platform-roadmap.md`.

## What changed

- **`FreeTypeFont.horizontalHeader`** — the face's `hhea` ascender,
  descender and line gap (`FT_Get_Sfnt_Table`), and **`FreeTypeFont.format`**
  (`FT_Get_Font_Format`). `CFreeType`'s own umbrella header (not a vendored
  file) gains `FT_TRUETYPE_TABLES_H` and `FT_FONT_FORMATS_H`.
- **`PortableFontMetrics` / `PortableFont.metrics`** (`LB-F`), with
  `FontMetrics`' `lineHeight = ceil(ascent + descent + leading)`.
- **`PortableText.emitLines`** → `PortableParagraph(lines:height:)` (`LB-H`):
  a wrapped paragraph from the text box's top-left, line *i*'s baseline at
  `top + i × lineHeight + ascent`. `PortableText.lines` is now a view of an
  internal `layOut` that also keeps each line's glyphs, so what is drawn is
  what was measured.
- **One per-glyph path**: `emit` and `emitLines` both call the internal
  `emitGlyph`, and both apply `drawnGlyph` (`LB-I` rule 1) — so **`emit` no
  longer draws `.notdef` for a newline**, a behaviour change to `PT-D`'s API
  that no pin saw (none of `PT-H`'s strings has a control character).
- **`HarfBuzzFont.points`** scales `units × (size / unitsPerEm)` (`LB-I` rule
  2) — a last-bit change to every portable advance.
- **SDL frame 4** (`LB-J`) draws a paragraph wrapped at 262 pt: 239 glyphs,
  0 px against Metal on SDL Metal and Vulkan (MoltenVK), locally.
- **Pins** (`LB-K`): `LineEmissionDeterminismTests` in `Tests/PortableTests`
  (metrics checksum, two paragraphs); `PT-H`'s third case's advance
  (`…0c49` → `…0c48`) and `LB-G`'s four wrap checksums re-recorded for rule 2.

## How the metrics were found (LB-F, measured)

| Step | What was compared | Result |
|---|---|---|
| `FT_Face` ascender/descender/height × `size / upem` | 3 faces × 11 sizes | within 2.24e-4 pt, `lineHeight` equal everywhere |
| five patched variants per face (`hhea` / OS/2 ascender, descender, line gap) | 15 faces | Noto faces wrong by whole design units: FreeType follows OS/2 under `USE_TYPO_METRICS`, CoreText reads `hhea` |
| `hhea` via `FT_Get_Sfnt_Table` | 15 + 33 | within 7.1e-5 pt |
| TrueType: 16.16 fraction of the em, `size × f / 65536` | 9 sampled values | 6 of 9 exact; three one-ulp misses on Noto Sans Arabic |
| TrueType: `(f × upem / 65536) × (size / upem)` | all | **exact to the bit**; CFF within 6.4e-5 pt |

CoreText's CFF values are `units × (size / upem) × (1 + 17·2⁻²³)` on every
measured value; that factor is a Float32 number, and no Float32 or
fixed-point spelling of 0.001 tried (seven) produced it. Left unmodelled:
the difference changes `lineHeight` only when the exact sum is a whole
number, which is pinned on one patched face.

## How placement was found (LB-I, measured)

26,928 cases (LB-E's corpus at scale 1 and 2):

| Step | Differing cases | What they were |
|---|---|---|
| first version | 9,548 | `\n`/`\t`/`\r` drawn `.notdef` (CoreText: space glyph); soft hyphens drawn as a zero-width space glyph (CoreText: no glyph) |
| substitutions for control characters and default ignorables | 872 | one subpixel variant off on a later line — CoreText at 29.624999…, portable at 29.625 |
| `units × (size / upem)` | 828 | U+2028/2029 in Source Sans 3, which has no glyph for them |
| hard-break characters substituted too | 36 | CoreText's 0xFFFF on a soft-hyphen-only line |
| oracle drops 0xFFFF (Apple rasterizes nothing for it) | **0** | — |

## Mutations

Each applied to one spelling, `--filter MetalUIPortableTextTests`, reverted
(runner in the session scratchpad):

| # | Mutant | Reddens |
|---|---|---|
| M1 | `horizontalHeader` falls back to `FT_Face` always | `facesWithPatchedMetricsMatchCoreText` |
| M2 | leading dropped | `facesWithPatchedMetricsMatchCoreText` |
| M3 | no 16.16 rounding | `facesWithPatchedMetrics…`, `portableMetricsMatchCoreTextsAndTheLineHeightExactly` |
| M4 | 16.16 scaled as `size × f / 65536` | `portableMetricsMatch…` |
| M5 | `lineHeight` not ceiled | `aWrappedParagraphLands…`, `emitLinesReturnsTheLinesAndTheirTotalHeight`, `everyWrapCorpusCasePlaces…`, `facesWithPatchedMetrics…`, `portableMetricsMatch…` |
| M6 | baseline without ascent | `aWrappedParagraphLands…`, `everyWrapCorpusCasePlaces…` |
| M7 | every line re-shaped alone (advance and glyphs) | `everyCorpusCaseWrapsExactlyAsMetalUIsApplePath` |
| M7b | line glyphs re-shaped alone, advance kept | **none** — see below |
| M8 | default ignorables drawn | `everyWrapCorpusCasePlaces…` |
| M9 | controls not substituted | `aWrappedParagraphLands…`, `emitDrawsNoGlyphForANewline`, `everyWrapCorpusCasePlaces…` |
| M10 | hard breaks not substituted | `everyWrapCorpusCasePlaces…` |
| M11 | `units × size / upem` | `everyWrapCorpusCasePlaces…` |
| M12 | glyph pen ignores tab stops | `everyWrapCorpusCasePlaces…` |
| M13 | `emitLines` drops order and layer | `emitLinesStampsItsMaskOrderAndLayerOnEveryGlyph` |
| M14 | `emit` draws the shaped id | `emitDrawsNoGlyphForANewline` |
| M15 | `emitLines` drops the vertical shaping offset | **none** — no corpus glyph has one |
| M16 | paragraph height spaced by ascent | `emitLinesReturnsTheLinesAndTheirTotalHeight` |
| M17 | pen not restarted per line | `aWrappedParagraphLands…`, `everyWrapCorpusCasePlaces…` |

**M7b is a green mutant that is not a defect**: re-shaping a line alone
loses only its last glyph's kerning into the next line, which moves the
line's advance and no glyph on it. The spec's draft said slicing was needed
"because re-shaping loses kerning"; that was true of the advance (M7) and
not of placement, and the spec was corrected before commit. **M15** is the
`PT-H` blind spot again: only a script with vertical offsets sees it, and
the portable package's Arabic `emit` pin does not go through `emitLines`.

## Counts

After `swift package clean`, `swift build --build-system native
--build-tests`, unfiltered `swift test --build-system native --no-parallel`:
see `CLAUDE.md`'s Build and test (1651 + 14: ten oracle tests, two of them gated measurements, and four `EmitLinesTests`). `Tests/PortableTests`: 12 + 6 +
5 (the portable text target's 8 plus `LineEmissionDeterminismTests`' 4, one
the gated recorder).

## Open

- **CFF metrics' residual factor** — unexplained; pinned where it shows.
- **Vertical offsets** through `emitLines` — unpinned until a script that has
  them wraps (bidi, roadmap item 12).
- **Contextual joining across a line break** — whether CoreText keeps a
  paragraph's joining forms at a break is unmeasured (M7b's caveat).
