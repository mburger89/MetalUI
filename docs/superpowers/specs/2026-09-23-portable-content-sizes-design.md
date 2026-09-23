# Portable min- and max-content — design

**Status: implemented** on `feat/portable-content-sizes` (record §32);
roadmap item 3 of `plans/2026-09-23-cross-platform-roadmap.md`. Rulings
continue the `LB-` prefix: `LB-L`…`LB-O` (next unused: `LB-P`).

## Goal

A layout engine measures text at three widths: a definite one (`lines`,
item 1), min-content and max-content. On Apple platforms min-content is the
widest unbreakable run shaped on a line of its own
(`ShapingCache.minContentWidth`, TX-F: `CFStringTokenizer`'s runs) and
max-content the widest line at no width (TX-K). This item gives the portable
path the same two numbers and the runs under them, measured equal.

## Rulings

### LB-L — Break opportunities are libunibreak's under `"en-strict"`

`PortableText.lineBreaks(in:)` asks libunibreak for language `"en-strict"`:
its bundled English tailoring (U+2018 and U+201C as opening punctuation,
U+201D as closing) and the `-strict` suffix (small kana, class CJ, as
non-starters). That is CoreText's behaviour, measured over every ordered
pair of 47 class samples — one character per UAX #14 class plus every
quotation-mark variant — with and without a space between, between two
letters (4,418 strings):

| language | pairs differing from `CFStringTokenizer` |
|---|---|
| none (item 1's call) | 347 — curly quotes, small kana |
| `"en"` | 123 — all small kana |
| `"en-strict"` | **0** |

Item 1's 13,464-case wrap oracle and 26,928-case placement oracle are
unchanged by it (no corpus string has a curly quote or small kana), and so
are `LB-G`'s cross-platform pins.

**Not a locale.** `Shaper.unbreakableRuns` passes a `nil` locale; the English
tailoring is what CoreText does with it on this machine (macOS 27.0, en_US).
Whether CoreText's answer moves with the system language is unmeasured.

### LB-M — Two divergences, pinned wrong on purpose

- **Thai** (and by extension Lao, Khmer, Myanmar — UAX #14's SA class):
  CoreText breaks between words from a dictionary; libunibreak has none, so
  a Thai phrase is one run between spaces
  (`thaiBreaksOnlyAtSpacesWhereCoreTextUsesADictionary`). A dictionary is
  font fallback's and itemization's neighbour (roadmap items 11 and 12).
- **German-style quotes** (`„…“`, U+201C closing): CoreText's *typesetter*
  breaks after `„hi“ ` at 45 pt although its own tokenizer gives no
  opportunity there, and at 120 pt declines a break after `„quoted“ ` where
  that line would fit — a typesetter heuristic, not a class rule. `lines`
  follows the tokenizer
  (`germanQuotesWrapWhereCoreTextsTypesetterLeavesItsTokenizer`). English
  curly quotes wrap exactly as CoreText at every width tried
  (`englishCurlyQuotesWrapAsCoreTextDoes`).

### LB-N — `unbreakableRuns`, `minContentWidth`, `maxContentWidth`

- `PortableText.unbreakableRuns(of:) -> [String]`: the text cut after every
  allowed or mandatory opportunity, trailing whitespace trimmed, empty
  pieces dropped; an empty string has no runs — `Shaper.unbreakableRuns`'
  contract.
- `PortableText.minContentWidth(_:font:)`: the widest run, each measured as
  a line of its own (`maxContentWidth` of the run) — not the paragraph at a
  tiny width, for `Shaper.unbreakableRuns`' documented reason.
- `PortableText.maxContentWidth(_:font:)`: the widest of `lines(_, nil)`.

Oracle: both widths equal the Apple path's within 1e-9 pt over 31 strings ×
2 faces × 4 sizes (248 cases). The four corpus strings a bundled Latin face
cannot draw — CJK, Thai, Arabic, emoji — are skipped by name
(`theWidthCorpusSkipsOnlyWhatAFaceCannotDraw`): CoreText draws them from
fallback fonts (roadmap item 11). Runs are compared over all 35 strings but
Thai.

No cache: `ShapingCache` memoizes the Apple answers per frame; a portable
text system (roadmap item 6) owns caching.

### LB-O — Pins

`Tests/PortableTests`' `ContentSizeDeterminismTests`: the runs and both
widths of four strings (item 1's break corpus, curly quotes, small kana, a
hard break) in one checksum.
