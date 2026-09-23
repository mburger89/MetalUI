# Portable font fallback — design

**Status: implemented** on `feat/font-fallback` (record §42; written as §40); roadmap item 11
of `plans/2026-09-23-cross-platform-roadmap.md`. **Ruling prefix:** `FB-`
(`FB-A`…`FB-C`, next `FB-D`; rulings here).

## Rulings

### FB-A — Graphemes go to the first face that covers them

`PortableFont.fallbacks` is an ordered cascade. `PortableText.shapeCascading`
walks the text by grapheme (Swift's `Character`, UAX #29): each goes to the
first face — the requested one, then its fallbacks — with a glyph for every
scalar of it that draws (default ignorables, controls and whitespace need
none), or to the requested face when none covers it (`.notdef`, as before).
Consecutive graphemes in one face are shaped as one HarfBuzz run, clusters
offset back into the paragraph. Everything that shaped with HarfBuzz directly
— `layOut` (and so `lines`, `emitLines`, min- and max-content), `emit`, the
re-shape of a line ending inside a cluster — goes through it, and every glyph
carries its face to placement and rasterization (`LinePlacedGlyph.font`,
`GlyphPlacement.font`; a control character's space glyph is its own face's).
Line metrics stay the requested face's, as the Apple path's do.

### FB-B — The resolver's cascade is every other registered face

`PortableFontResolver.resolve` sets a resolved font's fallbacks to every other
registered face, in registration order, at the same size. `PortableTextSystem`
registers the fallback faces under their own `FontKey`, so a fallback glyph is
keyed on — and rasterized from — its own face.

### FB-C — Oracle: CoreText with the same cascade

CoreText is given Source Sans 3 with `kCTFontCascadeListAttribute` = [Noto
Sans]; the portable resolver has Source Sans 3 as default and Noto Sans
registered. Over six strings mixing Latin text with characters only Noto Sans
draws (1,018 such in U+0020…U+2FFF, measured), 4 sizes and 41 widths at scale
2 — 1,008 cases, 7,728 glyphs from the fallback — every glyph's **face**, id,
device pixel, subpixel variant and baseline are equal. A control shows the
arms disagree without the cascade.

## Not handled

- **Right-to-left fallback** (Noto Sans Arabic behind a Latin face): an
  Arabic run is shaped right to left, and ordering runs is bidi — roadmap
  item 12.
- **CoreText's system cascade**: the portable cascade is exactly the faces
  registered; an app on Linux or Windows registers what it wants to fall back
  to (system discovery is roadmap item 8b).
- A face that lacks a whitespace character the requested face also lacks —
  unmeasured (mutation F5 is green: every corpus whitespace is in the
  requested face).
