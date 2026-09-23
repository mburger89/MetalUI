# Portable bidi and script itemization — design

**Status: implemented** on `feat/bidi` (record §42; written as §41); roadmap item 12 of
`plans/2026-09-23-cross-platform-roadmap.md`. **Ruling prefix:** `BD-`
(`BD-A`…`BD-D`, next `BD-E`; rulings here).

## Rulings

### BD-A — SheenBidi 3.0.0, vendored

`CSheenBidi`: SheenBidi (Apache-2.0) unedited, `Headers/` and `Source/`,
compiled through upstream's unity file (`SB_CONFIG_UNITY`); tarball SHA-256
in `VENDORED.md`. Warning-free on both build systems and on Linux.
`BidiParagraph` (in `MetalUIPortableText`) runs UAX #9 over a text split into
UAX #9 paragraphs at every paragraph separator — a newline starts a new
paragraph, with its own direction — each paragraph's direction from its first
strong character, left to right when there is none (CoreText's "natural"). It
also gives each unit's script (SheenBidi's script locator).

### BD-B — Runs split by face, level and script, shaped in their direction

`shapeCascading` (`FB-A`) now starts a new HarfBuzz run wherever the face,
the bidi level or the script changes, and shapes each in its level's
direction (odd: right to left). Glyphs remember their run and level. Line
breaking is unchanged: logical, over the paragraph's per-unit advances.

### BD-C — Lines in visual order, as CoreText lays them out

Each line's glyphs are laid out left to right in UAX #9 visual order: the
line's level runs as SheenBidi orders them (L1 and L2), a right-to-left
run's shaping runs reversed, each shaping run's glyphs in HarfBuzz's order
(already visual). Two CoreText behaviours were measured and matched:

- **In a right-to-left paragraph a line's trailing whitespace hangs off its
  left edge** — L1 puts it at the visual left, and CoreText starts the line's
  text at the origin with the whitespace at negative x (74 of 320 cases
  differed until this).
- **A line starting inside lam-alef is re-shaped**, its alef unjoined — the
  split-ligature rule (`LB-D`) for Arabic's mandatory ligature, which Noto
  Sans Arabic draws as two glyphs in two clusters. At any other break between
  joined letters CoreText keeps the paragraph's joined form (measured: a mim).

`emit` (one line) is laid out in visual order too.

### BD-D — Oracle and pins

CoreText with Noto Sans and `kCTFontCascadeListAttribute` = [Noto Sans
Arabic]; the portable resolver with the same two faces. Ten strings mixing
Latin and Arabic in both paragraph directions — digits both Western and
Arabic-Indic, brackets, a hard break between paragraphs of opposite
direction, the Arabic alphabet spaced — at 13 and 17 pt and 15 widths:
**320 cases, 4,608 Arabic glyphs, line boundaries and every glyph's face,
id, device pixel, variant and baseline equal**. A control shows logical order
differs for a right-to-left paragraph. `Tests/PortableTests` pins two mixed
paragraphs through `emitLines` (rects, height, atlas) — measured equal on
Linux aarch64.

This also closes item 11's gap: an Arabic fallback behind a Latin face is
right to left, and draws as CoreText's.

## Not handled

- Explicit embeddings and isolates from the API (only the characters' own
  bidi classes and any explicit formatting characters in the text).
- Alignment: every line starts at the origin (the Apple path's rule), so a
  right-to-left paragraph is flush left, as it is on macOS here.
- Script splitting (mutation B5 green): every corpus script change already
  coincides with a level or face change.
