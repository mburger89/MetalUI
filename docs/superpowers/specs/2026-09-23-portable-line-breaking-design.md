# Portable line breaking — design

**Status:** in progress, 2026-09-23. Decided with the user: vendor libunibreak
for UAX #14 rather than write it or vendor ICU.
**Ruling prefix:** `LB-` (lettered; next `LB-H`).
**Builds on:** `MetalUIPortableText` (`PT-`), `MetalUIHarfBuzz` (`SH-`).

## Goal

`PortableText` emits one run on one line (`PT-E`); a wrapping `Text` needs
lines. This step gives the portable pipeline what `Shaper.shape(_:font:
wrappingAt:)` gives the Apple one — a string split into display lines at an
offered width, one line per hard break when no width is offered — and emits
those lines, with CoreText's own answers as the oracle.

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
  framework (`PT-A` extends to it).
- **LB-C — `PortableText.lines(_:font:wrappingAt:)`** returns the display
  lines (UTF-16 range, advance in points) with `Shaper.shape`'s contract:
  `nil` is an infinite width, so one line per hard break; a trailing hard
  break opens no empty line; an empty string is one empty line; a
  non-positive width traps.
- **LB-D — greedy, and the fitting rule is measured, not assumed.** Each line
  ends at the last break opportunity whose line fits the width; what "fits"
  means (whether trailing whitespace counts, how a word wider than the line
  is broken) is set from the oracle's measurements (LB-E) and recorded here.
- **LB-E — the oracle is `Shaper.shape(wrappingAt:)`.** For a corpus of
  strings, fonts, sizes and widths, line boundaries (`CTLineGetStringRange`)
  and advances are compared. Boundaries must be equal; a disagreement is
  investigated and either fixed or pinned with its measurement, never
  absorbed.
- **LB-F — multi-line emission.** `PortableText.emitLines` emits each line
  with `emit`, baselines one line height apart; the line height's portable
  derivation is measured against `FontMetrics.lineHeight`.
- **LB-G — cross-platform pins** in `Tests/PortableTests` for break
  opportunities and wrapped lines; SDL frame 4 gains a wrapped paragraph.

## Verification

- Clean native build and full suite; counts from the summary lines.
- Mutations, each reddening a named test.
- Linux and Windows CI green.
