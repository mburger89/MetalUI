# 42 — Portable bidi and script itemization, 2026-09-23

Branch `feat/bidi`, from `feat/font-fallback` (PR #23, record §41). Written
as §41 and renumbered 41→42 when stage 6a took §38. Spec:
`docs/superpowers/specs/2026-09-23-bidi-design.md`, rulings `BD-A`…`BD-D`
(next `BD-E`). Roadmap item 12.

## Measured, step by step

| Step | Line diffs | Placement diffs | What they were |
|---|---|---|---|
| first version (320 cases) | 0 | 74 | RTL paragraphs: trailing whitespace at the left, inside the line |
| hang it off the left edge | 0 | 1 | an alef starting a line after a split lam-alef: CoreText unjoined |
| re-shape every RTL line start | 0 | 2 | a mim after lam: CoreText keeps the joined form |
| re-shape only a split lam-alef | 0 | **0** | — |

Found on the way: SheenBidi's paragraph ends at a paragraph separator, so the
first wrapper (one paragraph for the whole text) trapped on every line after a
newline — each paragraph now gets its own direction, which is also UAX #9's
and CoreText's rule. Tests registering fonts with CoreText process-wide
(`FontResolverOracleTests`, `TextSystemSeamTests`) race under a parallel
filtered run; the suite's `--no-parallel` rule covers it.

Linux container: root 486 + 22 + 3 and `Tests/PortableTests` 18 + 6 + 5 pass,
the bidi pins equal to macOS.

## Mutations

| # | Mutant | Reddens |
|---|---|---|
| B1 | no visual reordering | `bidiParagraphsPlaceEveryGlyphAsCoreTextDoes`, `logicalOrderDiffersFromCoreTextForMixedText` |
| B2 | every run shaped left to right | those two and `aSplitLamAlefIsReshapedAndAnyOtherSplitJoinIsNot` |
| B3 | RTL trailing whitespace not hung | `bidiParagraphsPlace…` |
| B4 | split lam-alef not re-shaped | `bidiParagraphsPlace…`, `aSplitLamAlef…` |
| B5 | runs not split by script | **none** — unreached by the corpus |
| B6 | an RTL level run's shaping runs in logical order | `bidiParagraphsPlace…`, `logicalOrderDiffers…` |

## Counts

Root 1693 + 4 (one gated) = **1697** before the stage-6a merge, **1699**
(1695 + 4) after it; `Tests/PortableTests` 18 + 6 + 5.
