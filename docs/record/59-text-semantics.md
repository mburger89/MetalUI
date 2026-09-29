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

### 2.7 Fix round (review findings)

Commits: `3f3048e` (red), `42e990d` (fix), and the docs commit carrying this
section. Six findings (two major, four minor), each disposed:

1. **Major — an empty last paragraph in tail mode**: fixed, **`TE-V`**. Probe
   `swiftui-truncation-edges.swift` gained arm E5 ("A\n\nB" at
   `lineLimit(2)`, "\nB\nC" at `lineLimit(1)`; positive control: the token's
   reading 54 px off, the untruncated text 185/349 px off): SwiftUI draws **no
   token** in any mode — the portable path was right, CoreText's forced token
   wrong; `Shaper.truncatedLine` fixed. Adding the two strings to
   `TruncationOracleTests`' corpus exposed a second, pre-existing difference
   in BASE wrapping (a line of one over-wide cluster ending at a hard break
   takes the next paragraph break when an empty paragraph follows, in
   CoreText, not in the portable breaker) at 4, 8 and 10.5 pt; fixed on the
   portable side (`TE-V` item 2), pinned by a literal arm in
   `bothSystemsBreakLinesAtTheSameRanges`. `TE-U`'s scope sentence corrected
   (a claim about its corpus). Corpus 9,660 cases, 7,701 truncated, 38
   differences, the same class.
2. **Major — the portable cache key unpinned**: 1.10 gained an arm measuring
   one string and width on a fresh system under default options then
   `maxLines: 1`, and the reverse, each required to equal CoreText's; the
   CoreText side is run the same way.
3. **Minor — alignment pinned only by agreement**: new test **1.7b**
   `aLineIsAlignedByItsWidthWithoutItsTrailingWhitespace` against a `CTLine`
   built in the test (A5's trailing whitespace included), exact at scale 64
   where a 1/256 pt offset step is one quarter-pixel variant.
4. **Minor — displaced doc comments**: `Shaper.shape(_:font:wrappingAt:options:)`
   and `PortableText.layOut(_:font:wrappingAt:options:)` now sit above the
   old functions' doc comments, which again attach to their own
   declarations.
5. **Minor — probe header**: re-recorded with E5 on an idle machine
   (compiled twice, interpreted once, 39 lines byte-identical, every pre-E5
   line identical to the first recording); the header now says the non-zero
   counts move under load, citing the reviewer's run.
6. **Minor — the seam's clamp unpinned**: 1.6 gained an arm, maxLines 0 and
   −1 equal 1 on both systems (glyphs, ranges, `measure`).

Red at `3f3048e` (filtered to the touched tests): 1.5 (differences 306, one
outside `TE-U`'s class), 1.6b's E5 arm (CoreText drew `[36, 3, 526]` and
`[526]`, measured 10.283 where 8.307 and 0), and 1.6's first clamp arm
(its cross-system `measure` equality was a wrong instrument — the two systems
agree to ~1e-13, not bit for bit — replaced before the commit by each
system's own maxLines-1 answer); 1.10's cache arm and 1.7b pass on the
unmutated code by design (they pin, and V1/V2/V3 below redden them).
`bothSystemsBreakLinesAtTheSameRanges`' literal arm was red (4 portable
issues) against the fix commit with only `LineBreaking.swift` restored.

Close: `swift build --build-system native --build-tests` 0 `error:`, the
one deprecation `warning:`; the default build system 0 `error:`/`warning:`;
unfiltered `swift test --build-system native --no-parallel` **`Test run with
1657 tests in 3 suites passed`** (1656 + 1.7b), the `FR-J` line present;
`Tests/PortableTests` 20 + 6 + 5 on macOS (unedited pins green over the
portable wrapping change); `MetalUILayout` imports only `MetalUICore`;
`compare.sh` 169d166 → 42e990d, controls as recorded, **0 differing pixels,
scene identical, in all fourteen**. The lock probe read
`CGSSessionScreenIsLocked = 1`, `displayAsleep main: 1`: real-window capture
still owed. Backends/SDL and the container were not re-run (no source they
build changed beyond `MetalUIPortableText`'s narrow wrap case and
`MetalUIText`, which they do not run; the portable package, which runs the
portable pins, was).

Mutations (committed at `42e990d`, applied from a copy, the whole suite
unfiltered, `git status --short` empty after each restore):

| # | mutation | reddened |
|---|---|---|
| ME5 | CoreText: an empty `P` takes the tail token (`TE-V` item 1 reverted) | 1.6b (6 issues), 1.5 (2) |
| MTEV | portable: no empty-paragraph absorb (`TE-V` item 2 reverted) | `bothSystemsBreakLinesAtTheSameRanges` (4), 1.5 (2) |
| V2 | portable `MeasureKey` built with default options | 1.10 (2) |
| V1 | centre and trailing factors swapped on both systems | 1.7b (4) |
| V3 | trailing whitespace counted in the line's width on both systems | 1.7b (6) |
| MCLAMP | the `max(1, …)` clamp dropped on both systems | the run traps in 1.6 (`Index out of range`), no summary line |

Next unused `TE-W`.

## 3. Lane 2 — font selection on both systems; baselines in the kernel; the legacy `baseline` fields

Commits: `a0acce8` (red, font selection), `d5a2b3f` (font selection),
`666d88b` (red, baselines), `4bd1092` (baselines), `02eb735` (the NaN fix, red
first), `baf1420` and `6574330` (2.1b's two arms after M2x), and the docs commit carrying this
section.

### 3.1 What landed

- `MetalUITextSystem`: `FontDesign`, `FontDescriptor`, the requirement
  `resolveFont(_:)`; `resolveFont(family:size:)` is now a protocol extension.
- CoreText: `FontResolver.resolve(_:)` and a descriptor-keyed
  `ShapingCache.resolveFont(_:)` memo (`TE-W` items 1, 5).
- Portable: `FreeTypeFont.styleName`/`weightAndWidthClass`,
  `FreeTypeFaceNames.weightClass`/`widthClass` (read without the bytes),
  `FaceTraits`, `PortableFontResolver.resolve(_:)` and
  `register(design:family:)` (`TE-W` items 2–3). A family name now means the
  family's regular face, not the first registered.
- Kernel: `ProposalTextBaseline`; `firstBaseline`/`lastBaseline` for every
  node kind; `newNativeLinearStack(…, baseline:)` (a vertical stack with one
  traps); `LayoutPass`/`Frame.requestNativeLinearStack(…, baseline:)`.
- `MetalUI`: `VerticalAlignment.firstTextBaseline`/`.lastTextBaseline`;
  `HStack` passes them; `GridRow` traps on them (divergence 88); a legacy
  row's `alignItems(.baseline)` lowers to `.first`, a column's to `flexStart`,
  a `display: .stack` container's stays reported; `alignSelf.baseline` is
  consumed under a baseline container; `UnlowerableField.owner` is always
  `nil` (`TE-L`, `TE-X`).
- Probe `docs/probes/swiftui-font-selection.swift` (new): P0, W 144/144, N 7/7,
  S 32/32.

### 3.2 Rulings

`TE-W` (font selection as measured; ten portable rows pinned) and `TE-X` (a
custom node's own baselines; a grid's from its solve; the third T row, spec
2.13; no NaN from an infinite answer, spec 2.1b). Next unused `TE-Y`.

The two CoreText measurements `TE-W` cites (scratch, not probes — they read
CoreText, not SwiftUI): over 2 755 installed faces, CoreText's weight trait
against the OS/2 class (many disagree — class 400 carries every weight among
variable-font named instances, 275/900/800 carry −0.8/0.56/0.62 among Avenir's
statics) and against the style word (2 566 agree); its italic trait against
the style name (2 753), `macStyle` (2 737), `fsSelection` (2 731). CoreText's
selection over 68 static families: the portable rule, fed CoreText's own
traits, agreed on 1 329 of 1 360 rows, the misses variable fonts (which
FreeType lists as one face) and the classes `TE-W` item 4 pins.

### 3.3 Red first

Font selection, at `a0acce8` (skeleton: both systems ignore weight, slope and
design), filtered: 1.3 `theSystemDescriptorIsNSFontsSystemFontAtEveryWeightAndDesign`
156 issues (`FontResolver.resolve(descriptor).key == expected`), 1.4
`aCustomFamilysWeightSelectsItsNearestFace` 30 issues, 1.1 1 issue (then only
Sukhumvit Set's family-name face, both skeletons ignoring weight alike); with
CoreText implemented, 1.1 read **474 differences** of 600 (`differences ==
pinned`) — the portable resolver ignoring the weight. 1.2 and G1.2 passed on
the skeleton, as their rows say (a pin; an API that existed). 1.12
(`Tests/PortableTests`) passed on the skeleton too: a regular-only resolver
has nothing else to choose — its mutation is M1b's.

Baselines, at `666d88b`, filtered to the 15 touched tests, 62 issues: 2.1 10
(`baselines(measured { … ZStack … }) == [25, 25]` …), 2.2 2 (`answer.size ==
SizeD(width: 80, height: 44)`), 2.3 2, 2.5 2, 2.6 2 (exit status success), 2.7
2, 2.8 4 (exit status success), 2.9 1 (`row.unlowerable.isEmpty`), 2.10 30
(`field.owner == owner`), 2.11 4, 2.12 2, 2.13 1; green by design: 2.4 (the
control), the work pin, G2.1. 2.1b was red (SIGTRAP) against `4bd1092`.

### 3.4 Close

After `swift package clean`-free rebuilds (no stored property on a public type
crossing a module boundary changed layout: `FreeTypeFaceNames` gained two, a
stale `SystemFontsTests` object was rebuilt by touching it — the link error
`Undefined symbols … FreeTypeFaceNames.init(faceIndex:postScript:family:full:style:)`):
`swift build --build-system native --build-tests` 0 `error:`, the one
deprecation `warning:`; `swift build --build-tests` 0/0; unfiltered
`swift test --build-system native --no-parallel` **`Test run with 1675 tests
in 3 suites passed`**, the `FR-J` line present. **1675 = 1657 + 18**: 1.1,
1.2, 1.3, 1.4, G1.2 (5); 2.1, 2.1b, 2.2–2.6, the work pin (8); 2.7, 2.9, 2.11
(3); 2.8 (1); G2.1 (1). Guards **101 → 103** (G1.2, G2.1, both
`typecheckFile`). T rows 2.10, 2.12, 2.13 re-answered, none removed.
`MetalUILayout` imports only `MetalUICore`. `Tests/PortableTests` 21 + 6 + 5
(1.12). `Backends/SDL` (`PKG_CONFIG_PATH=Backends/SDL/.accesskit`) 21 + 23. A
`swift:6.4-noble` (aarch64) container builds the root package with 0
`error:`/`warning:` and runs **196 + 22 + 10** (`MetalUILayoutTests` + 8,
`BaselineMeasurementTests`), `Tests/PortableTests` **21 + 6 + 5**, 1.12
confirmed on Linux.

`compare.sh` 169d166 → `4bd1092` and → `6574330`: controls as recorded since
stage 6b (1048576, 1031003, 454895, 0, 1048576, 0, 544, 216, 491221, 529, 0);
**0 differing pixels, scene identical, in all fourteen**. No demo tree writes
a font weight, a design, a baseline alignment or `alignItems(.baseline)`, and
no production leaf reports a baseline before lane 3. The lock probe read
`CGSSessionScreenIsLocked = 1`, `displayAsleep main: 1`: the real-window
capture is still owed.

`SA-M`: every work-literal test green unedited; `baselineAlignmentAddsNoMeasurementWork`
pins that baseline alignment and baseline-reporting leaves add no measure
call, hit or miss. The 1 MB every-kind depth test green; the ceiling was not
re-bisected (the maximum is unchanged; new per-level work sits in
`@inline(never)` helpers).

### 3.5 Mutations

Committed first, each applied from a copy, the whole suite unfiltered, `git
status --short` empty after every restore:

| # | mutation | reddened |
|---|---|---|
| M1a | portable nearest → the pool's first face | 1.1 (2) |
| M1b | a one-face family's weight/slope falls to the cascade's first face | 1.2 (114) |
| M1c | CoreText system path drops the weight | 1.3 (117) |
| M1d | CoreText family path keeps the named face (no weight descriptor) | 1.4 (26), 1.1 (2) |
| M1q | portable italic tie → heavier | 1.1 (1: Avenir Next light italic) |
| M1r | portable weight word ignored when a class exists | 1.1 (2) |
| M1s | the memo's `==` ignores the weight (hash kept) | 1.3, then the run traps (duplicate `FontRequest` keys), no summary line |
| M1s2 | `==` and hash both ignore the weight | 1.3 (58), 1.4 (13) |
| MG1c | `FontDescriptor.init` `package` | G1.2 |
| M2a | a stack's baselines from its first child only | 2.1 (5), 2.5 (2) |
| M2b | an attachment takes its overlay's baselines | 2.1 (2) |
| M2c | a text-less child counted as its height | the run traps at checkpoint 2 in `theDemoFrameDrawsRectsAndText`/`theDemoFrameMatchesTheValuesRecordedOnMacOS` (∞ − ∞ in the demo's spacer rows — the finding behind `TE-X` item 6); filtered to the baseline files, 2.1 (4) |
| M2d | baseline stack height = tallest child | 2.2, 2.3 |
| M2e | a text-less guide read as 0 | 2.2, 2.3 (2), 2.7 (2), 2.9, 2.11 |
| M2f | `.last` reads the first baseline | 2.3 (2), 2.5, 2.7 |
| M2g | baseline placement whenever a child reports one | 2.4 (3), 2.7 |
| M2h | a stack's last = its first | 2.1 (5), 2.5 (2) |
| M2i | `textBaseline` always nil | 2.7 (2), 2.8 (4: no trap) |
| M2j | a baseline column lowers as centre | 2.9 |
| M2k | `"plan task 11"` owner restored | 2.10 (30), 2.11 |
| M2l | `alignSelf.baseline` consumed everywhere | 2.11, `everyStageOneUnlowerableNodeFieldIsReportedByNameOnALeaf` (2) |
| M2m | a flex container reports `alignItems.baseline` again | 2.12 (2), 2.13, 2.9, 2.11 (3) |
| M2n | the stack branch's `alignItems.baseline` row deleted | 2.12, `aLoweredStackPlacesFixedChildrenAtAllNineAlignments` |
| MG2 | `firstTextBaseline` added to `HorizontalAlignment` | does not build (exhaustive switch) |
| MG2b | MG2 plus the switch arm | G2.1 |
| M2t1 | the vertical-stack precondition off | 2.6 (2) |
| M2t2 | the `GridRow` precondition off | 2.8 (4) |
| M2w | a baseline stack re-measures its children | the work pin (2) |
| M2x | the combination's finite guard dropped (first) | 2.1b (after its infinite-probe assertion was added; before, green — `Swift.min` keeps a non-NaN first argument) |
| M2y | the frame's NaN guard dropped | 2.1b |

### 3.6 Deferrals

- `TE-W` item 4's ten rows (Hoefler Text, Futura, Sukhumvit Set): pinned,
  owner none.
- `TE-X` item 2: a grid cell that answers its slot differently from its solve
  answer reports the solve's baseline; reachable only under a baseline
  `HStack`; the offsets themselves are pinned by 2.1c since the fix round
  (§3.7), the slot-versus-solve re-measure still is not.
- The depth ceiling is not re-bisected (`SA-L` asks it only before raising
  `maxDepth`).
- `TE-W` item 6: the OS/2 class fallback in `FaceTraits` decides one face
  with a class on this install (Marker Felt Wide), and reading it as 0 moves
  no answer (V9, §3.7) — pinned by synthetic rows, not by the oracle.
- Nothing element-facing: `Text`/`ProposalText` report no baseline and pass
  no descriptor until lane 3 (`Font`, `fontWeight`, `italic`).

### 3.7 Fix round (review findings)

Four findings (one major, three minor), each disposed below; commit
`561462a` (code and tests), then the docs commit carrying this section.

1. **Major — a non-baseline `alignSelf` under a baseline row laid out
   silently wrong** (`TE-L` item 5, new). Fixed: `planLegacyItems` reports
   `alignSelf.flexStart`/`.center`/`.flexEnd`/`.stretch` under a baseline
   **row**, a permanent refusal. `.stretch` was measured here, not only the
   three the review named: a scratch arm read the row 110 tall at a 100
   proposal with the text at y 80, the same failure as `.center`. Red first:
   **2.11b** `aNonBaselineAlignSelfUnderABaselineRowIsRefusedByName`, 4
   issues (`refused.unlowerable == [entry]`, one per arm) before the fix.
   2.10's table 265 → **305** (the four names at the ten recording sites; the
   design's "16 rows, 11 item sites" corrected to 15 and 10 in the test's doc,
   `TE-L` item 5 and spec row 2.10).
2. **Minor — the vertical-stack cursor's gaps were unpinned.** Fixed: a new
   probe, `docs/probes/swiftui-baseline-offsets.swift` (headless, compiled
   once; arms O1c/O1/O2/O3/O4, each prediction matched on the first run —
   O1 13/49, O1c 13/41), and **2.1c**
   `aStacksGapsAndAGridsOffsetsMoveTheBaselinesItReports` (green on arrival:
   it pins landed code). V4 reddens it.
3. **Minor — a grid's baseline offsets were unpinned.** Fixed by 2.1c's
   three grid arms (O2 25/73, O3 13/73, O4 37). V5 reddens all three.
4. **Minor — the class fallback on the lazy path was unpinned.** Measuring
   it found a real disagreement first: the install's faces with no weight
   word and a class other than ~400 are 43, of which 41 are Hiragino's
   `W0`…`W9` styles, and CoreText weighs those by the number, not the class
   (a scratch `CTFontCopyTraits` read: Hiragino Sans W0…W9 → −0.8, −0.6,
   −0.4, 0, 0.23, 0.3, 0.4, 0.56, 0.62, 0.62; classes 100, 200, 250, 300,
   400 … 900). Hiragino Sans added to 1.1's corpus read **20 unpinned
   differences** (red), 0 after the number rule (`TE-W` item 6). The
   remaining class-decided face, Marker Felt Wide (class 700, CoreText 0.4),
   is not separated by V9 — its weight read as 0 still wins every request it
   won — so V9 stays green **by equivalence over this install**, recorded,
   and the fallback itself is pinned by **1.1b**'s synthetic `FaceTraits`
   rows (MC below). 1.1b also pins one Marker Felt difference: CoreText
   weighs "Thin" 0 (class 400) against its word and picks it at weight 0.
   1.1's corpus: 31 families, 213 faces, 620 requests, the same ten pinned
   rows.

Suite: **`Test run with 1678 tests in 3 suites passed`** (1675 + 2.11b, 2.1c,
1.1b); 0 `error:`, the one deprecation `warning:` under native, 0/0 under the
default build system; the `FR-J` line present. Guards unmoved (103).

Mutations (committed first, restored from a copy, whole suite unfiltered,
`git status --short` empty after each):

| # | mutation | reddened |
|---|---|---|
| ML5 | the baseline-row `alignSelf` refusal disabled | 2.11b (4) |
| V4 | the vertical cursor in `measureLinearStack` drops its gaps | 2.1c (1) |
| V5 | every `nativeGridCellOffsetsY` offset 0 | 2.1c (3) |
| V9 | `FreeTypeFaceNames.read` passes `weightClass: 0` | none — equivalent over this install (item 4) |
| MW | the `W0`…`W9` rule dropped | 1.1, 1.1b (9 issues) |
| MC | the class fallback reads 0 | 1.1b (2: the synthetic `Wide`/700 and `Chancery`/300 rows) |

Next unused `TE-Y`.

## 4. Lane 3 — the element surface

### 4.1 The height census (`TE-R` item 2), before any source change

Instrument `docs/probes/text-semantics-height-census.patch` (committed under
`docs/probes/`, never to `Sources/`): a `censusLeafPlacementHook` in
`LayoutTree.placeNative`'s leaf case, a `censusTextLeaves` registry filled by
`Text.requestLayout` (the native leaf inside `lowerLegacyLeaf`, not the
element's node) and `ProposalText.requestProposalLayout`, and a gated test
(`METALUI_TEXT_CENSUS=1`) that renders every tree at every size the fourteen
offscreen images use, plus the 920×560 window in each demo state and the
controls demo. A row is a text leaf whose **placement** proposal has a finite
height below its natural height at that proposal's width (`measure` with no
options) — the leaves `TE-H` item 2 would give fewer lines. Applied to this
worktree at `35eb357` (lanes 1–2), run, and reverted (`git status --short`
clean afterwards but for the patch).

| capture | size | text placements | rows |
|---|---|---|---|
| default light/dark f0 | 1024² | 507 | 0 |
| default light/dark f3 | 1024² | 594 | 0 |
| modal | 1024² | 509 | 0 |
| modal (prod) | 920×560 | 509 | 0 |
| animation | 1024² | 507 | 0 |
| **animation** | **920×560** | 507 | **1** |
| default (prod) | 920×560 | 507 | 0 |
| preview | 1024², 920×560 | 2 | 0 |
| controls demo | 920×560, 1024² | 81 | 0 |
| chrome (`CounterPanel`) | 560² | 3 | 0 |

**The one row**: `demoMainPane()`'s wrapping paragraph ("CoreText shapes this
paragraph, a shelf packer…") under the **A** state at the demo's own 920×560
window, placed at proposal (524, 68.5) against a natural 80 (five 16 pt
lines). It is **not one of the fourteen images** (`animation-light`/`-dark`
are 1024², where the row is absent), so the census predicts **0 px in all
fourteen**; the row is a real-window look, named by a ruling after the
implementation re-runs the census (§4.3).
