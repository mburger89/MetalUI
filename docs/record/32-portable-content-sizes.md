# 32 — Portable min- and max-content, 2026-09-23

Branch `feat/portable-content-sizes`, from `feat/portable-lines-emit` (PR
#13, record §31). Spec: `docs/superpowers/specs/2026-09-23-portable-content-sizes-design.md`,
rulings `LB-L`…`LB-O` (next `LB-P`). Roadmap item 3.

## What changed

- `PortableText.unbreakableRuns(of:)`, `minContentWidth(_:font:)`,
  `maxContentWidth(_:font:)` (`LB-N`), in `ContentSizes.swift`.
- **`lineBreaks(in:)` asks libunibreak for `"en-strict"`** (`LB-L`) — a
  change to item 1's opportunities for curly quotes and small kana, which no
  earlier corpus string contained, so no earlier oracle or pin moved.
- Pins: `ContentSizeDeterminismTests` (`LB-O`).

## How LB-L was found (measured)

The first run compared runs over 35 strings: 2 differed (Thai; `«quoted»
„quoted“ “quoted”`). Wrapping the quote string showed `lines` disagreeing
with CoreText at 21 widths, so the quote was not a runs-only matter. A
probe over 26 quote contexts showed CoreText treating U+201C/U+2018 as
opening and U+201D as closing punctuation but «, ‹ and „ per the standard —
libunibreak's own `lb_prop_English` table. The class-pair probe then took
the question from samples to the whole table:

| language | differing pairs of 4,418 |
|---|---|
| none | 347 |
| `"en"` | 123 (all CJ) |
| `"en-strict"` | **0** |

What remained is `LB-M`'s two pinned divergences: Thai (dictionary) and a
German-quote typesetter heuristic that contradicts CoreText's own tokenizer.

Widths: with `"en-strict"`, min- and max-content differed only for the four
strings a Latin face cannot draw (fallback fonts on the Apple path), in both
faces at every size; the oracle skips those four by name and compares 248
cases at 1e-9.

## Mutations

Each applied to one spelling, `--filter MetalUIPortableTextTests`, reverted:

| # | Mutant | Reddens |
|---|---|---|
| N1 | no language | `englishCurlyQuotesWrapAsCoreTextDoes`, `everyClassPairBreaksAsCoreTextDoes`, `everyCorpusStringButThaiSplitsIntoCoreTextsRuns`, `germanQuotesWrap…`, `minAndMaxContentMatch…` |
| N2 | `"en"` without `-strict` | `everyClassPairBreaksAsCoreTextDoes` |
| N3 | runs keep trailing whitespace | `everyClassPair…`, `everyCorpusStringButThai…`, `germanQuotesWrap…`, `maxContentIsTheWidestHardLineAndRunsCarryNoTrailingSpace`, `minAndMaxContentMatch…`, `thaiBreaksOnlyAtSpaces…` |
| N4 | runs cut at allowed opportunities only | `everyClassPair…`, `everyCorpusStringButThai…` |
| N5 | min-content sums the runs | `maxContentIsTheWidest…`, `minAndMaxContentMatch…` |
| N6 | max-content sums the lines | `maxContentIsTheWidest…`, `minAndMaxContentMatch…` |
| N7 | min-content is the whole text's max-content | `maxContentIsTheWidest…`, `minAndMaxContentMatch…` |

**The runner used for item 2 (record §31) matched only `recorded an issue`
lines** and so would miss a test whose only output is `failed after`; found
here when N1 appeared not to redden `everyClassPairBreaksAsCoreTextDoes`
(it does — run alone). Item 2's seventeen mutations were re-run with the
fixed matcher on `feat/portable-lines-emit` and read identically, M7b and
M15 still green.

## Counts

1665 + 10 (nine oracle and contract tests, one gated measurement) =
**1675**; see `CLAUDE.md`. `Tests/PortableTests`: 14 + 6 + 5.

## Open

- Whether CoreText's quote tailoring follows the system language.
- Thai/Lao/Khmer/Myanmar dictionary breaking.
- The German-quote typesetter heuristic.
