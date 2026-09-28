# 59 — Text semantics (plan task 11, part 1)

Branch `feat/text-semantics` from `169d166`. Spec
`docs/superpowers/specs/2026-09-28-text-semantics-design.md`; rulings
`TE-A`…`TE-U` in `docs/superpowers/2026-09-28-text-semantics-decisions.md`;
probe `docs/probes/swiftui-text-semantics.swift`. Written by the design
session, the lanes and the Record phase.

## 1. Design

### 1.1 Baseline

At `169d166`, in this worktree's own `.build`: `swift build --build-system
native --build-tests` — 0 `error:`, one `warning:` (SwiftPM's deprecation
notice); unfiltered `swift test --build-system native --no-parallel` —
`Test run with 1644 tests in 3 suites passed after 95.662 seconds`, one
`FR-J no-argument frame: succeeded=` line (guards ran).

### 1.2 The probe

`docs/probes/swiftui-text-semantics.swift`, new: 294 recorded lines, compiled
form run twice and interpreted form once, all byte-identical; the screen was
locked (lock probe `CGSSessionScreenIsLocked = 1`, `displayAsleep main: 1`),
which no arm depends on — every measurement is a custom `Layout` inside an
`NSHostingView`'s `fittingSize` or an `ImageRenderer` render. The first run
(G0–C9) raised questions the same session answered with the X arms (X1–X13),
appended to the same file and re-recorded whole.

Findings that changed the design while it was being written:

- **The height proposal limits a text's lines** (L5, X9), refuting the
  unprobed sentence in `ProposalText.swift`'s doc comment ("the height
  proposal does not truncate or scale text, matching the measured SwiftUI
  custom-Layout behavior"). `TE-H` item 2.
- **`Text.bold()` fits no rule** (X1, X1b, F2e, X12), so it is not offered
  (`TE-B` item 4).
- **SwiftUI's line height is not a function of CoreText's metrics** (X13), so
  MetalUI's `ceil(ascent + descent + leading)` stays and the difference is
  divergence 86 (`TE-G`).
- **Truncation is CoreText's truncated line** except one middle arm (X5),
  divergence 87 (`TE-I`).
- **A `GridRow`'s baseline alignment overflows its cells** (X11), which the
  stack rule (B2) does not produce; it traps, divergence 88 (`TE-K`).

### 1.3 Plan

Three lanes in order: 1 the seam and both text systems, 2 the kernel's
baselines and the legacy `baseline` fields, 3 the element surface (spec §8).
Expected demo change: none (spec §7).

### 1.4 Critic round

One agent attacked the committed design (`0abcfcf`) and revised it in the same
commit; rulings `TE-Q`…`TE-S` (next unused `TE-T`).

- **The probe reproduces.** `swiftui-text-semantics.swift` compiled and run by
  the critic: all 294 lines byte-identical to the header (exit 0, stderr
  empty).
- **F8's render field was a broken instrument** — `ImageRenderer` ignores
  `controlSize` (new probe `swiftui-controlsize-text-render.swift`, R1: 13 pt
  at every size against a 2404 px 9-vs-13 control), while layout identifies
  9 / 11 / 13 uniquely (R2). `TE-F` stands on layout; the drawn font joins the
  owed real-window capture (`TE-Q`). An `NSHostingView.cacheDisplay`
  instrument drew blank with the screen locked and was dropped.
- **`TE-H` makes wrapping text vertically flexible in stacks**, which the
  design's 0 px claim had not considered. New probe
  `swiftui-text-in-stacks.swift` (K0–K4): SwiftUI serves the text its equal
  share before a spacer and keeps only the lines that share holds (one line at
  60 beside a `Spacer`, three at 100, six at 200). Adopted as SwiftUI's
  answer; lane 3 takes a height census before implementing and a ruling names
  any moved image; pin 3.23 (`TE-R`).
- **Amended** (`TE-S`): lanes rebalanced (font selection to lane 2, so the two
  oracle-heavy pieces are in different lanes); `TE-L`'s `display: .stack`
  branch ruled a permanent refusal, and the report table keeps 265 entries
  with 16 owners flipping to `nil` (the design read 265 → 260); divergence
  60's pin gains an 11 pt arm that separates at the stored rect; divergence
  86's "not a function" softened to the fits tried; `VerticalAlignment`'s new
  cases carry a source-break migration note; the truncation token is shaped
  through `shapeCascading`, and an unmatched oracle case stops the lane for a
  ruling; the Windows stack budget is measured before and after.
- **Rejected** attacks are listed in `TE-S` (baseline `Alignment`s
  unreachable, no `foregroundColor` collision, no out-of-tree conformer,
  `FontKey` reads variations, no part-2 creep, `SA-M` unmoved by
  construction).

Expected suite after the three lanes: ≈ 1690 (spec §9).

## 2. Lane 1 — the seam's layout options and metrics, on both text systems

Commits: `532336b` (red), `2737835` (implementation), and the docs/mutation
commit that carries this section.

### 2.1 What landed

- `MetalUITextSystem`: `TextFontMetrics`, `TextTruncation`,
  `TextLineAlignment`, `TextLayoutOptions`; `fontMetrics(_:)` and the
  `options:` forms of `measure`, `placeGlyphs` and `lineRanges` as protocol
  requirements; the three old spellings as a protocol extension passing
  `TextLayoutOptions()`. No conformer exists outside the two systems.
- CoreText (`MetalUIText`): `Shaper.shape(_:font:wrappingAt:options:)` —
  the kept lines, the last built by `Shaper.truncatedLine` (a line of the
  rest's first paragraph; `CTLineCreateTruncatedLine` with a `…` token line in
  the resolved font; the forced tail token through one overflowing glyph;
  `CTTypesetterSuggestClusterBreak` narrower than the token), per-line
  `lineOffsets`; `ShapedLine` gains stored `sourceRange` and
  `trailingWhitespace`; `ShapingCache`'s key gains the options (a default-
  options entry is still built by the old `shape`, byte for byte).
- Portable (`MetalUIPortableText`): new `Truncation.swift`
  (`PortableText.truncatedLine`, the token through `shapeCascading`);
  `layOut(_:font:wrappingAt:options:)`; `LaidOutLine.trailingWhitespace`;
  alignment in `placements`; `emitLines(options:)`; the measurement cache
  keyed by options; the emergency line break keeps a base with its marks
  (`TE-U` item 8).
- `Tests/PortableTests`: `PortableTextDeterminismTests` depends on the
  `MetalUITextSystem` product; `TruncationDeterminismTests` (1.11) pins six
  emissions recorded on macOS — the package now runs 20 + 6 + 5.

### 2.2 Rulings

`TE-T` (probe `swiftui-truncation-edges.swift`, new: a hard break ends the
truncated line at its paragraph; narrower than the token, the longest prefix
that fits; amends `TE-C` item 3) and `TE-U` (the truncation rule as measured;
one right-to-left class pinned, not matched; a variant tie). Spec rows 1.6b
and 1.6c added. Next unused `TE-V`.

### 2.3 Red first

At `532336b` against the compiling skeleton (options accepted and ignored,
`fontMetrics` zero), filtered to the ten new root tests: 9 failed, 33 issues;
G1.1 passed (the API existed, as its "red before —" row says). The failure
lines:

- `thePortableTruncationKeepsCoreTextsStringInEveryMode` (TruncationOracleTests.swift:189): Expectation failed: differences.isEmpty
- `theTruncationCorpusReachesEveryRule` (TruncationOracleTests.swift:204): Expectation failed: shaped.lines.count == 1
- `theTruncationCorpusReachesEveryRule` (TruncationOracleTests.swift:205): Expectation failed: glyphs.contains { $0.key.glyph == ellipsis }
- `theTruncationCorpusReachesEveryRule` (TruncationOracleTests.swift:206): Expectation failed: glyphs.count < 15
- `theTruncationCorpusReachesEveryRule` (TruncationOracleTests.swift:212): Expectation failed: placed.contains { $0.key.font.postScriptName == "NotoSans-Regular" }
- `theDroppedLinesAreTruncatedAsOneLineAfterTheKeptOnes` (TextSystemSeamTests.swift:247): Expectation failed: baselines.count == 2
- `aHardBreakEndsTheTruncatedLineAtItsParagraph` (TextSystemSeamTests.swift:282): Expectation failed: lastLine("Ready\nSet\nGo", two) == (mode == .tail ? set + ellipsis : set)
- `aHardBreakEndsTheTruncatedLineAtItsParagraph` (TextSystemSeamTests.swift:284): Expectation failed: lastLine("Alpha beta \(para)\nmore", two) == (try coreTextGlyphIDs(para, truncatedAt: 100, mode: ct))
- `aHardBreakEndsTheTruncatedLineAtItsParagraph` (TextSystemSeamTests.swift:287): Expectation failed: lastLine("Ready\nSet\nGo", TextLayoutOptions(maxLines: 1)) == (try coreTextGlyphIDs("Ready")) + ellipsis
- `aWidthNarrowerThanTheTokenKeepsTheLongestPrefixThatFits` (TextSystemSeamTests.swift:307): Expectation failed: a.map(\.key.glyph) == h
- `theSeamsLayoutOptionsPlaceTheSameGlyphsOnBothSystems` (TextSystemSeamTests.swift:355): Expectation failed: moved > compared / 3
- `theSeamsLayoutOptionsPlaceTheSameGlyphsOnBothSystems` (TextSystemSeamTests.swift:356): Expectation failed: limited > compared / 10
- `theSeamsMetricsAgreeOnBothSystems` (TextSystemSeamTests.swift:371): Expectation failed: a == TextFontMetrics(ascent: direct.ascent, descent: direct.descent, leading: direct.leading,
- `theSeamsMetricsAgreeOnBothSystems` (TextSystemSeamTests.swift:377): Expectation failed: a.lineHeight > size
- `anUnspecifiedWidthCutsKeptLinesWithoutAnEllipsis` (TextSystemSeamTests.swift:394): Expectation failed: a == cut
- `anUnspecifiedWidthCutsKeptLinesWithoutAnEllipsis` (TextSystemSeamTests.swift:398): Expectation failed: apple.lineRanges("A\nB\nC", font: appleFont, wrappingAt: nil, options: options) == [0..<2, 2..<4]
- `anUnspecifiedWidthCutsKeptLinesWithoutAnEllipsis` (TextSystemSeamTests.swift:399): Expectation failed: portable.lineRanges("A\nB\nC", font: portableFont, wrappingAt: nil, options: options) == [0..<2, 2..<4]
- `measureAnswersTheWidestKeptLine` (TextSystemSeamTests.swift:412): Expectation failed: lineHeight > 13

`Tests/PortableTests`: `truncatedAndAlignedEmissionIsByteIdentical` —
`Expectation failed: expectedTruncations.count == truncationCorpus.count`.

### 2.4 The oracle

See `TE-U`: 156 differences at the first implementation, 38 at the end, all in
its item 7 class; Latin in every mode, the combining marks, CJK, and Arabic in
tail mode match exactly.

### 2.5 Close

After `swift package clean` (stored properties added to `ShapedLine` and
`ShapedText`, public types crossing a module boundary):
`swift build --build-system native --build-tests` — 0 `error:`, the one
`warning:` SwiftPM's deprecation notice; unfiltered `swift test --build-system
native --no-parallel` — **`Test run with 1656 tests in 3 suites passed`**, the
`FR-J no-argument frame: succeeded=` line present. **1656 = 1644 + 12**:
`TruncationOracleTests` 4 (1.5, 1.5b, the corpus-reach check, and the gated
`measureTruncationDifferences`, `METALUI_TRUNCATION_MEASURE=1` — so **twelve**
gated tests now skip), `TextSystemSeamTests` +7 (1.6, 1.6b, 1.6c, 1.7–1.10),
`TextSystemCompileGuards` 1 (G1.1; guards **100 → 101**, `typecheckFile`).
No test removed or edited in its answer; every pre-existing seam, oracle and
portable pin green unedited. Default build system (`swift build
--build-tests`): 0 `error:`, 0 `warning:`. `MetalUILayout` imports only
`MetalUICore`. `Backends/SDL` (`PKG_CONFIG_PATH=.accesskit`): 21 + 23 passed.
A `swift:6.4-noble` (aarch64) container: the root package builds with 0
`error:`/`warning:` and runs **188 + 10 + 22**; `Tests/PortableTests` runs
**20 + 6 + 5** there (18 + 6 + 5 before: 1.11 and its recorder), the six
truncation pins recorded on macOS confirmed on Linux.

Mutations (each committed first at `2737835`, applied from a copy, the whole
suite unfiltered, `git status --short` empty after every restore; every test
reddened named):

| # | mutation | reddened |
|---|---|---|
| M1e | portable tail keeps the whitespace before the token | 1.5, 1.6, 1.6b, 1.7 |
| M1f | portable middle prefix one boundary short | 1.5, 1.6, 1.6b, 1.7 |
| M1g | CoreText truncates line n−1's own text only | 1.5, 1.5b, 1.6, 1.6b, 1.7, 1.10, the corpus-reach check |
| M1h | portable alignment factor 0 | 1.5, 1.7 |
| M1i | portable `lineHeight` rounded to nearest | 1.8 |
| M1j | a token at a `nil` width (portable) | 1.5, 1.7, 1.9, 1.10 |
| M1k | CoreText `measure` answers the widest of every line | 1.10, `aProposalTextInAStackIsShapedOncePerDistinctWidth` (the mutant shapes twice) |
| M1l | CoreText truncates the whole rest, ignoring hard breaks | 1.5, 1.6b, 1.7 |
| M1m | CoreText draws nothing when the token does not fit | 1.5, 1.6c |
| M1n | the emergency line break may split a base from its mark (`TE-U` item 8 reverted) | 1.5 |
| M1o | portable alignment offset unrounded (`TE-U` item 6 reverted) | 1.5, 1.7 |
| MG1 | `TextLayoutOptions.init` `package` | does not build (a public default argument references it) |
| MG1b | old `measure(_:font:wrappingAt:)` extension `package` | G1.1 alone |

1.11 is a recorded pin: its red is the empty table, and Linux confirmed it.

`docs/probes/demo-pixels/compare.sh` 169d166 → 2737835: controls as recorded
since stage 6b (light/dark 1048576, default/modal 1031003, default/animation
454895, f0/f3 0, chrome pair 0, distinct 544/216/529, indicator rects 0);
**0 differing pixels, scene identical, in all fourteen images**. No demo tree
passes options, so nothing could move. Real-window capture **owed**: the lock
probe read `CGSSessionScreenIsLocked = 1`, `displayAsleep main: 1` at design,
at the probe run and at this close.

### 2.6 Deferrals

- `TE-U` item 7: right-to-left head/middle truncation on the portable path
  keeps one cluster fewer than CoreText in 38 corpus cases — pinned, owner
  none.
- `TE-T` item 4: narrower than the token MetalUI draws the one kept grapheme
  unclipped where SwiftUI clips it; no number.
- E3's head arm at width 20 (SwiftUI matches no candidate) is observed, not
  ruled.
- Nothing element-facing lands here: `Text`/`ProposalText` still call the old
  spellings (default options) until lane 3.
