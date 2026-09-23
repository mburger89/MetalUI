# Portable font metrics and multi-line emission — design

**Status: implemented** on `feat/portable-lines-emit` (record §31); roadmap
item 2 of `plans/2026-09-23-cross-platform-roadmap.md`. Rulings continue the
line-breaking spec's `LB-` prefix: `LB-F` (reserved there for this item),
then `LB-H`…`LB-K` (next unused: `LB-L`).

## Goal

`PortableText.lines` says where a paragraph wraps; nothing portable yet says
how tall a line is or draws more than one line. The Apple path does both in
`ShapedText.placedGlyphs(at:font:scaleFactor:)`: line *i*'s baseline is
`top + i × lineHeight + ascent`, rounded once at device scale, and every
glyph comes from that line's `CTLine`. This item gives the portable path the
same two things, measured equal.

## Rulings

### LB-F — Line metrics are the face's `hhea` numbers, scaled as CoreText scales them

`PortableFont.metrics` is a `PortableFontMetrics(ascent:descent:leading:)`
with `lineHeight = ceil(ascent + descent + leading)` — `FontMetrics`'
formula, for `FontMetrics`' reason (whole-point baselines; `FontKey.swift`).

- **The numbers are `hhea`'s** ascender, −descender and line gap, read with
  `FT_Get_Sfnt_Table` (`FreeTypeFont.horizontalHeader`). **Not
  `FT_Face.ascender`/`descender`/`height`**: FreeType fills those from OS/2's
  typographic metrics when a face sets `USE_TYPO_METRICS`, and CoreText
  ignores that flag. Both Noto faces set it with typo numbers equal to
  `hhea`'s, so only faces patched to disagree separate the two (measured:
  patching OS/2's `sTypoLineGap` to 200 moves FreeType's `height` and not
  CoreText's leading; patching `hhea`'s moves CoreText's and not FreeType's).
- **A TrueType face's metric is rounded to a 16.16 fraction of the em**, back
  in design units, then scaled `units × (size / unitsPerEm)` — the same
  association as an advance (LB-I). That spelling is **exact to the bit**
  against `CTFontGetAscent`/`Descent`/`Leading` on both Noto faces at eleven
  sizes and on five patched variants of each; three other orderings of the
  same arithmetic miss by one ulp on Noto Sans Arabic.
- **A CFF face's metric is scaled unrounded.** CoreText's runs a further
  1 + 17·2⁻²³ high (a Float32 value whose origin was searched for and not
  found), so Source Sans 3 agrees within 6.4e-5 pt. `lineHeight` still agrees
  at every measured size; it differs by one point only when the exact sum is
  a whole number, which no bundled face reaches — pinned wrong on purpose on
  a patched face (`aCFFFaceWhoseLineSumIsWholeIsOnePointTallerOnCoreText`).

### LB-H — `PortableText.emitLines` draws a wrapped paragraph

`emitLines(_:font:origin:wrappingAt:scaleFactor:color:contentMask:
maskCornerRadii:order:layer:into:atlas:) -> PortableParagraph`, where
`origin` is the text box's **top-left** (as `placedGlyphs(at:)`), not a
baseline (as `emit`). It returns the lines (`PortableLine`s, as `lines`
returns them) and `height = lines.count × lineHeight` (`ShapedText.totalHeight`).

Line *i*'s baseline is `origin.y + i × lineHeight + ascent`, rounded once at
device scale. Each line's glyphs are the ones `lines` measured
(`PortableText.layOut` returns both): the **paragraph's** shaping sliced by
the line's range, pen restarting at `origin.x`; a tab advances to the next
28 pt stop from the line's start; a line starting inside a cluster uses the
shaping from that start (LB-D). Slicing is chosen so that what is drawn is
what was measured, **not** because re-shaping a line alone would place its
glyphs differently: it would not, on this corpus (mutation M7b is green —
the kerning a re-shaped line loses is its last glyph's advance, and nothing
follows that glyph on its line). A contextual script whose joining crosses a
break could differ; unmeasured until bidi (roadmap item 12).

The per-glyph arithmetic is `emit`'s, not copied: both call one internal
`emitGlyph`.

### LB-I — Oracle: placement equal to `ShapedText.placedGlyphs`, and what it took

Over LB-E's wrap corpus at scale 1 and 2 — 26,928 cases, 784,294 glyphs —
each placed glyph's id, device pixel x, subpixel variant and device baseline
equal `Shaper.shape(_:font:wrappingAt:).placedGlyphs(at:font:scaleFactor:)`'s
**exactly**. The first version differed in 9,548 cases; three rules, each
from a measured disagreement, took that to 0:

1. **Glyph substitutions** (`PortableText.drawnGlyph`, shared with `emit`): a
   default-ignorable character (a soft hyphen, a zero-width joiner) draws
   nothing, where HarfBuzz gives it a zero-width space glyph; a control or
   hard-break character the face has no glyph for (a newline, a tab, U+2028 in
   Source Sans 3) draws the space glyph, where HarfBuzz gives it `.notdef` —
   which has ink in both Latin faces, so a newline would draw a box.
2. **Design units scale as `units × (size / unitsPerEm)`** in
   `HarfBuzzFont.points`, the ratio taken first. The other association differs
   in the last bit, and a pen summed from those advances landed on the other
   side of a subpixel boundary from CoreText's in 44 cases (Noto Sans 13 pt,
   "non breaking…", 3.3 + 26.325). This moved the last bit of one `PT-H` pin's
   advance and of `LB-G`'s wrap advances; they were re-recorded.
3. CoreText reports glyph **0xFFFF** for a line that is nothing but a soft
   hyphen; the oracle drops it, and `coreTextDrawsNothingForItsDeletedGlyph`
   shows the Apple path rasterizes nothing for it.

Coverage is not re-compared per case: it is `emit`'s atlas path, compared by
PT-F. `aWrappedParagraphLandsWhereMetalUIsApplePathDrawsIt` carries the
placement through both atlases for six paragraphs.

### LB-J — SDL frame 4 draws a wrapped paragraph

A paragraph wrapped at 262 pt through `emitLines` joins frame 4 (239 glyphs,
from 137), so the replay's parity check covers multi-line emission on Metal,
Vulkan and Direct3D 12. Measured locally: 0 px against Metal on SDL Metal and
on Vulkan (MoltenVK).

### LB-K — Pins

`Tests/PortableTests`' third target gains `LineEmissionDeterminismTests`:
the three faces' metrics at 13 pt (bit patterns, one checksum) and two
wrapped paragraphs through `emitLines` (rects, height, dirty rect, coverage)
— one with a newline and soft hyphens, one with tabs and U+2028.

## Not handled

- **Vertical shaping offsets** in `emitLines` are applied as `placedGlyphs`
  applies a run position's y, and no corpus glyph carries one: dropping the
  term reddens nothing (M15), as for `emit` on macOS (`PT-H`'s note).
- **CFF metrics' residual factor** (LB-F).
- **Alignment**: every line starts at `origin.x`, as on the Apple path.
