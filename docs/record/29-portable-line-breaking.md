# 29 — Portable line breaking (libunibreak), 2026-09-23

Branch `feat/portable-linebreak`, from `feat/portable-text-mask-order` (PR
#11, `PT-J`). Spec: `docs/superpowers/specs/2026-09-23-portable-line-breaking-design.md`,
rulings `LB-A`…`LB-G` (`LB-F` reserved for roadmap item 2; next `LB-H`).
Roadmap item 1 of `docs/superpowers/plans/2026-09-23-cross-platform-roadmap.md`,
which this branch also adds.

## Why

`PortableText.emit` is one run on one line. A wrapping `Text` off Apple
platforms needs what `Shaper.shape(_:font:wrappingAt:)` gives the Apple path:
display lines at an offered width. The user chose libunibreak over writing
UAX #14 or vendoring ICU.

## What changed

- **`CUnibreak`** (`LB-A`) — libunibreak 8.0, zlib, UAX #14 revision 55
  (Unicode 17.0), tarball SHA-256 `9c4fad6e…ceba4`. Only the six line-breaking
  translation units compile; `linebreakauxdata.c` and `eastasianwidthdata.c`
  are `#include`d by them and excluded (compiling them separately duplicates
  `ub_is_op_east_asian`, measured); emoji and grapheme sources are not needed
  (the set links without them, measured). `linebreak.h` and `unibreakbase.h`
  are the public headers. Unedited; warning-free on both build systems.
- **`PortableText.lineBreaks(in:)`** (`LB-B`) — per UTF-16 unit, the unit
  HarfBuzz clusters and CoreText's string indices use.
  `LINEBREAK_INDETERMINATE` (end of text on a non-newline) maps to mandatory
  (UAX #14 LB3).
- **`PortableText.lines(_:font:wrappingAt:)`** (`LB-C`, `LB-D`) —
  `PortableLine(range:advance:)` per display line, with `Shaper.shape`'s
  contract.
- **Oracle** (`LB-E`) — `LineBreakingOracleTests.swift`: 13,464 cases
  against `Shaper.shape(wrappingAt:)`, both bundled Latin faces, 11/13/17/26
  pt, no width plus 98 widths from 4 to 320 pt, seventeen strings (plain,
  hard breaks, CR LF, U+2028/9, trailing and leading spaces, NBSP, soft
  hyphen, combining marks, ligatures, kerning pairs, tabs, numbers, a URL).
- **Pins** (`LB-G`) — `Tests/PortableTests`' `LineBreakingDeterminismTests`:
  break opportunities over an 82-unit Latin/CJK/Thai/Arabic/emoji string, and
  four wrapped cases' line ranges and advance bit patterns.

## How the fitting rule was found (LB-D, measured)

The first greedy version ("last opportunity whose line fits") already agreed
on every **boundary** over the first 192-case corpus; the advances and the
wider corpus found five rules, in this order:

| Step | Cases | Boundary diffs | Advance diffs | What the diffs were |
|---|---|---|---|---|
| first version, 192 cases | 192 | 0 | 70 | hard breaks: HarfBuzz gives `\n` a 7.8 pt advance, CoreText 0; a line ending mid-word re-shaped alone lost the kerning into the next line (0.26 pt on "bro" before "w") |
| advance = share of the paragraph's shaping, hard breaks zero | 192 | 0 | 0 | — |
| corpus widened to 13,464 | 13,464 | 277 | 746 | whitespace starting a line at narrow widths; ligature splitting; tabs |
| whitespace hangs; grapheme emergency breaks | 13,464 | 148 | 757 | `Affix`: the rest of a split ligature measured 0 wide (the whole ligature's advance sits on its first unit); CoreText prefers a cluster boundary over a grapheme one |
| re-shape from a start inside a cluster; cluster-first emergency | 13,464 | 29 | 763 | tabs only |
| tabs to 28 pt stops | 13,464 | **0** | **0** | — |

CoreText's tab stops are every **28 pt at every size** (28, 56, 84, 112 at
11, 13, 17, 26 pt).

## Mutations

Each applied to one line, `--filter MetalUIPortableTextTests`, reverted:

| # | Mutant | Reddens |
|---|---|---|
| M1 | whitespace does not hang | `everyCorpusCaseWrapsExactlyAsMetalUIsApplePath` |
| M2 | line advance re-shaped alone | `everyCorpusCaseWraps…` |
| M3 | hard break counted | `everyCorpusCaseWraps…` |
| M4 | no cluster-first emergency break | `everyCorpusCaseWraps…`, `theWrapCorpusReachesEveryRule` |
| M5 | no re-shape from a start inside a cluster | `everyCorpusCaseWraps…`, `theWrapCorpusReachesEveryRule` |
| M6 | no tab stops | `everyCorpusCaseWraps…`, `theWrapCorpusReachesEveryRule` |
| M7 | grapheme break keeps the whole cluster | `everyCorpusCaseWraps…`, `theWrapCorpusReachesEveryRule` |
| M8 | end of text not mandatory | `breakOpportunitiesAreUAX14sAfterEachUTF16Unit` |

## Counts

After `swift package clean`, `swift build --build-system native
--build-tests`, unfiltered `swift test --build-system native --no-parallel`:
**`Test run with 1636 tests in 3 suites passed`** (1630 + 6: the oracle, the
corpus-reach test, the gated measurement, three contract tests), guards ran,
97 goldens unmoved, 0 `error:`/`warning:` on the default build system.
`Tests/PortableTests`: 8 + 6 + 5 (the portable text target's 4 plus
`LineBreakingDeterminismTests`' 4, one of them the gated recorder).

## Open

- **Emission** — `emitLines`, font metrics and line height (`LB-F`),
  roadmap item 2.
- **Not compared**: RTL and mixed-direction paragraphs (no bidi yet, roadmap
  item 12), CJK and Thai wrapping (the bundled fonts have no CJK or Thai
  glyphs, so CoreText would fall back to another font; roadmap item 11).
  The pins cover their break **opportunities**, not their wrapping.
- **libunibreak's own conformance file** (`LineBreakTest.txt`, 3.1 MB) is not
  vendored; libunibreak 8.0 passes it upstream with no skips.
