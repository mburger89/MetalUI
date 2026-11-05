# Record 212: DS2 Finding B is divergence 86 (round 4 item R4-3b)

Branch `docs/r4-3b-line-height`, stacked on `feat/r4-3c-replayed-leaver` (2aa665dc); records 210 (PR #206) and 211 assumed. Ruling: a dated erratum to `TE-G` item 3 in `docs/superpowers/2026-09-28-text-semantics-decisions.md` (no new id). Divergences: **none added, retired or narrowed; row 86 amended** (209 live, next label 217). No `Sources/` change. `Tasks.md` R4-3b ticked.

## 1. What was found

Human check DS2 Finding B: MetalUI text boxes are 31 and 57 tall at SF 26 and 48 pt where SwiftUI's are 30 and 56; 13 pt is 16 in both; a mixed stack stores 230 against 226. It is row 86, not a new divergence.

- [CODE] `FontKey.swift` and `PortableText.swift` give `lineHeight = ceil(a + d + l)`. CoreText's sums are 15.311, 30.621 and 56.531, so 16, 31 and 57.
- [MEASURED] (`docs/probes/swiftui-line-height.swift`, layout only, run twice, byte-identical, in a locked session): SwiftUI's line is 16, 30 and 56.
- [MEASURED] The stack difference is exactly three line heights: MetalUI 229.43 (16 + 31 + 16.302 + 30 + 16.125 + 57 + 16 + 31 + 16, stored 230), SwiftUI 226.43. The gaps agree, so no spacing bug is hidden here.
- [MEASURED] `TE-G` item 3 was wrong that nothing fits. `NSLayoutManager.defaultLineHeight` equals `round(a) + round(d) + round(l)` at all 28 SF sizes. Agreement with SwiftUI:

| Family | `ceil` | round sum |
|---|---|---|
| SF (28 sizes) | 16 | 21 |
| Noto Sans, Menlo, Georgia, Courier New (12 each) | 7 | 12 |
| Avenir Next (12) | 6 | 12 |
| Helvetica Neue (12) | 1 | 5 |
| Times New Roman (12) | 1 | 2 |

At SF 10, 11, 15, 16, 19, 20 and 21 SwiftUI reads the round sum + 1; unexplained.

## 2. Decision: amend the row, keep the metric

Changing the formula would fix SF 17, 18, 24, 26, 30, 34, 40, 48 and 96, but regress SF 16, 19, 20 and 21, leave 10, 11 and 15 wrong and leave Helvetica Neue and Times New Roman mostly wrong. It would not retire the row, and it moves every non-13 pt text, each line of multi-line text, `floor(h / lineHeight)` line caps, fields, editors and menu panels. Kept, owner none. If wanted later it is one PR of its own, starting from the probe's table. [CODE, PREDICTED] The R4-2 gap rule reads raw ascent and descent and would not move; no `DS` test reddened under the mutation below.

## 3. What changed

- `docs/probes/swiftui-line-height.swift` (`SA-O` header, recording).
- `FontTests.swift`: `aSystemLineIsThirtyOneAtTwentySixAndFiftySevenAtFortyEight` (`lineHeight` 16, 31, 57; the DS2 stack's text heights 16, 31, 57, 16, 31, 16; outer stored height 230).
- Row 86 (48 pt, the measured fit, the stack difference, second pin), `TE-G` erratum dated 2026-11-04, `record/04-divergences.md` section, human check DS2 Finding B answered (look again only for whether 1 px per large line shows), `Tasks.md`, `record/README.md`.
- `CLAUDE.md` (and `AGENTS.md`, byte-identical): 208 live / next label 215 -> 209 / 217, and the reserved-range clause (215 and 216 used by `VA-F`, item 8's reservation released from 217).

## 4. Mutation

**M3n** (spelling `ascent.rounded() + descent.rounded() + leading.rounded()` on **both** `FontKey.swift` and `PortableText.swift`), applied to the committed tree (51f5927a), `swift test --no-parallel` (default build system, whole suite), restored with `git checkout -- Sources`, `git status` clean afterwards. Reddened exactly five tests: `aSystemLineIsThirtyOneAtTwentySixAndFiftySevenAtFortyEight` (all three expectations: 16/31/57 became 16/30/56, texts, outer), `aNotoSansLineIsTwentyFourPointsWhereSwiftUIsIsTwentyThree`, `aMixedTextCapsLinesByTheirSummedHeights`, `facesWithPatchedMetricsMatchCoreText`, `portableMetricsMatchCoreTextsAndTheLineHeightExactly`. The four named by the plan plus the new pin; nothing else. Only the both-spellings mutant was run; a one-system mutant was not.

## 5. Counts and checks

Native, after `swift package clean`, unfiltered, `--no-parallel`: **5155 tests in 14 suites passed** (record 211's 5154 plus the new pin); `FR-J no-argument frame: succeeded=true`. `record-05-check.sh`, `closeout-inventory-check.sh` and `closeout-undocumented.sh` printed nothing. `cmp CLAUDE.md AGENTS.md` identical.

## 6. Not verified

No pixels were read (the session was locked; the probe reads layout through `NSHostingView`, which worked locked). Not run: `METALUI_VERIFY_*` modes (no source change), guard re-take beyond the `FR-J` line, `Backends/SDL`, Linux, Windows. Whether 1 px per large line is noticeable is a human look (DS2).
