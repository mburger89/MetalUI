# Portable line breaking — design

**Status:** implemented on `feat/portable-linebreak`, 2026-09-23 (record
§30); roadmap item 1 of `plans/2026-09-23-cross-platform-roadmap.md`. Decided with the user: vendor libunibreak
for UAX #14 rather than write it or vendor ICU.
**Ruling prefix:** `LB-` (lettered; `LB-F` and `LB-H`…`LB-K` are in
`2026-09-23-portable-lines-emit-design.md`, roadmap item 2; next `LB-L`).
**Builds on:** `MetalUIPortableText` (`PT-`), `MetalUIHarfBuzz` (`SH-`).

## Goal

`PortableText` emits one run on one line (`PT-E`); a wrapping `Text` needs
lines. This step gives the portable pipeline what `Shaper.shape(_:font:
wrappingAt:)` gives the Apple one — a string split into display lines at an
offered width, one line per hard break when no width is offered — and emits
those lines' ranges and advances, with CoreText's own answers as the oracle.
Emitting them (`LB-F`, `LB-H`) is roadmap item 2, in
`2026-09-23-portable-lines-emit-design.md`.

**Not in this step:** bidi across lines, script itemization, font fallback,
hyphenation, justification, `Text`/`Shaper` changes.

## Rulings

- **LB-A — libunibreak 8.0, vendored as `CUnibreak`.** zlib licence, UAX #14
  revision 55 (Unicode 17.0), its own conformance suite passing with no skips.
  Only the line-breaking sources compile: `linebreak.c`, `linebreakdata.c`,
  `linebreakdef.c`, `unibreakbase.c`, `unibreakdef.c`,
  `eastasianwidthdef.c` (the `*data.c` files they `#include` are excluded
  from compilation). No edits.
- **LB-B — break opportunities are in UTF-16 units**, from
  `set_linebreaks_utf16`, the unit HarfBuzz clusters (`SH-`) and CoreText's
  string indices already use, so no index is ever converted.
  `MetalUIPortableText` depends on `CUnibreak` and still imports no Apple
  framework (`PT-A` extends to it). **Amended by `LB-L`** (roadmap item 3):
  the call now passes language `"en-strict"`, not `nil`, which matches
  CoreText on curly quotes and small kana.
- **LB-C — `PortableText.lines(_:font:wrappingAt:)`** returns the display
  lines (UTF-16 range, advance in points) with `Shaper.shape`'s contract:
  `nil` is an infinite width, so one line per hard break; a trailing hard
  break opens no empty line; an empty string is one empty line; a
  non-positive width traps.
- **LB-D — greedy, and the fitting rule is measured, not assumed.** Each line
  ends at the last break opportunity whose line fits the width. The rules,
  each set from a measured disagreement with CoreText (LB-E, record §30):
  1. **Whitespace hangs** — a space, tab or hard break never makes a line
     overflow, so a line ends after its trailing whitespace.
  2. **A line's advance is its share of the paragraph's shaping** — the
     kerning its last glyph had against the next line's first is kept, and a
     hard break is zero wide (HarfBuzz gives it a glyph advance).
  3. **A word too wide breaks before its overflowing cluster; a cluster too
     wide (a ligature) between graphemes** (Swift `Character`, UAX #29),
     keeping at least one; a line that ends inside a cluster is re-shaped
     alone, and **shaping restarts at a line start inside a cluster**.
  4. **Tabs go to stops every 28 pt** from the line's start, at every size
     (CoreText's default interval, measured at 11–26 pt).
- **LB-E — the oracle is `Shaper.shape(wrappingAt:)`.** For a corpus of
  strings, fonts, sizes and widths, line boundaries (`CTLineGetStringRange`)
  and advances are compared. Boundaries must be equal; a disagreement is
  investigated and either fixed or pinned with its measurement, never
  absorbed. Measured: 13,464 cases (2 fonts × 4 sizes × 99 widths × 17
  strings), 0 boundary and 0 advance differences at 1e-9 pt.
- **LB-F — line metrics** — ruled in `2026-09-23-portable-lines-emit-design.md`
  (roadmap item 2), with `LB-H`…`LB-K`.
- **LB-G — cross-platform pins** in `Tests/PortableTests`
  (`LineBreakingDeterminismTests`): the break opportunities over an
  82-unit multi-script string, and four wrapped cases' line ranges and
  advance bits, recorded on macOS.

## Verification

- Clean native build and full suite; counts from the summary lines.
- Mutations, each reddening a named test.
- Linux and Windows CI green.
