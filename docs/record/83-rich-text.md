# 83 — Rich text, styled runs inside one `Text`

Branch `feat/rich-text` from `70ed000` (master: portable app merged, PR #51).
**Not a plan task**: item 6 of the gpui-gap priority list, requested by the
user on 2026-10-02. Spec `docs/superpowers/specs/2026-10-08-rich-text-design.md`;
rulings `RT-A`…`RT-T` in the new decisions doc
`docs/superpowers/2026-10-08-rich-text-decisions.md` (next unused `RT-U`);
probes `docs/probes/swiftui-rich-text.swift`, `foundation-markdown-inline.swift`,
`swift-attribute-scope-ambiguity/run.sh`, `swiftui-text-interpolation.swift`,
`swiftui-kerning-zero.swift`, `coretext-styled-spacing.swift`.

**Numbering.** Written as §83 from the start: §81 is the parallel
`feat/input-apis` (not yet merged), §82 (variable-height `List`) and §84 (`.task`
follow-ups) are on master. At the Record phase `git fetch` showed master past
`70ed000` (PR #53, the variable-height list, with §82 and §84); no record 83
existed there, so §83 stands. The merge (`ee857db`) conflicted in the two
demo `main.swift` files (both env switches kept: `METALUI_RICH_TEXT_DEMO`,
`METALUI_LIST_DEMO`), `DemoStackBudgetTests` (both trees kept), `docs/migration.md`,
`docs/divergences.md` (145–147 beside 150–158), `human-checks.md` (groups VL and
RT both kept) and the census (regenerated with `closeout-public-api.sh`). **The
human-checks group letter**: this branch's group is **RT**, not the next letter
Y — master's variable-height list took the two-letter provisional group VL
(record §82), and a single letter would collide with `feat/input-apis`; the
merge that lands the last of the three settles the letters.

**Status: LANDED — every agent-doable clause is built; the looks are owed to a
human** (`docs/verification/human-checks.md` group RT, §7). Three lanes, each
red first on stubs, each with a review round, all verified `ok: true`; the
Record phase (§8) merged master, re-took the suite and the counts.

## §0 Baseline and design (2026-10-08)

- **Baseline** at `70ed000`: **2672 tests in 3 suites**, 0 goldens, 175
  typecheck guards, census 2536, divergences 105 live (next label 139;
  150–159 reserved here).
- **Design session and critic pass** (`RT-A`…`RT-N`, then `RT-O`'s sixteen
  corrections): the probe `swiftui-rich-text.swift` (SwiftUI's answers
  headless, arms `P0a`–`P0c` positive controls, `M1`–`M35` Markdown, `C1`–`C19`
  concatenation, mixed lines, decorations, links, truncation, `F1`–`F4e`),
  `foundation-markdown-inline.swift` (Foundation's inline parser on macOS; it
  and `inlinePresentationIntent` do not exist in the `swift:6.4-noble`
  container, `L1`–`L3`), `swift-attribute-scope-ambiguity` (a generic dynamic
  member subscript is ambiguous on `.red` beside AppKit's scope; per-key
  subscripts are not). The critic pass re-ran the rich-text probe byte for byte
  and added the interpolation and kerning-zero probes.
- **Foundation availability, answered** (the task's question): the container
  has `FoundationEssentials` but no `AttributedString(markdown:)` and no
  inline Markdown parser; `AttributedString` itself exists (`L2`). So MetalUI
  ships **its own inline Markdown parser** (`RT-B`, `MarkdownInline.swift`) and
  converts `AttributedString` through MetalUI's own attribute scope
  (`RT-D`), which compiles everywhere.
- **Literal census** (`RT-M` item 2): `Sources/` 88 `Text` literals, one hit
  (the scaffold's generated name, an intraword `_` that stays literal); no
  rendered literal changes when literals start parsing. Plain literals with no
  trigger character skip the parser entirely (`RT-O` 14, test 3.16).

## §1 What landed

- **The seam** (lane 1, `RT-F`): `StyledText`/`TextRunStyle`
  (`MetalUITextSystem/StyledText.swift`, Foundation-free): text plus runs of
  family, size, weight, italic, design, kerning, tracking, baseline offset and
  paint indices; normalised (zero-length runs dropped, equal neighbours
  merged; a sum mismatch traps). **Three defaultless `TextSystem` requirements**
  (styled measure, styled layout, decoration metrics) with honest
  implementations on CoreText, the portable system and `CountingTextSystem`
  (a migration note owes third-party conformers).
- **CoreText** (`StyledShaping.swift`): one `CTTypesetter` over an attributed
  string, kern/tracking attributes omitted at 0 (`RT-O` 7, probe `K1`/`K2`),
  MetalUI's baseline offset and `RT-G` line boxes (per-line max ascent/descent,
  offset-grown), the ellipsis in two attempts (`RT-P` 1), a styled
  `ShapingCache` key.
- **The portable system** (`StyledLayout.swift`, `FontFallback.swift`,
  `LineBreaking.swift`, `Truncation.swift`): `shapeCascading` per run
  (`FB-A`), bidi/script splits intact (`BD-B`/`BD-C`), one break table across
  runs (a run boundary is not an opportunity), spacing once per grapheme
  with ligatures switched off for tracked units by **feature ranges** inside
  one HarfBuzz call (`ShapingFeature` gains a UTF-16 range; `[]` is still
  `SH-E`'s call), FreeType decoration metrics (underline position/thickness,
  strikethrough at x-height / 2).
- **The `Text` element** (lane 2, `RT-E`, `RT-G`, `RT-J`, `RT-K`, `RT-L`):
  `TextRuns.swift` (requests, resolution once per run through
  `resolveTextStyle`, the `Mirror` operand check), `RichTextPaint.swift`
  (backgrounds, glyphs, joined underlines and strikethroughs as ordinary rects
  inside **one shadow leaf**, visible-extent clip; no shader change), the
  fast path byte for byte (a one-run unstyled `Text` calls the plain seam),
  `Text`/`ProposalText` modifiers (`underline`, `strikethrough`, `background`
  of runs, `kerning`, `tracking`, `baselineOffset`, `monospaced`, `Text.bold()`),
  the deprecated `Text + Text`, links as accent-coloured **inert** runs
  (divergence 150), accessibility publishing the concatenated string. The
  rich `Text`-level fields are boxed (`TextRichBox`; stored inline they
  overflowed the 1 MB build, `RT-R` 4).
- **The front ends** (lane 3, `RT-B`…`RT-D`, `RT-T`): `LocalizedStringKey`
  with interpolation placeholders and a trigger scan (`LocalizedStringKey.swift`);
  `MarkdownInline.swift`, cmark-gfm's inline algorithm with the strikethrough
  and autolink extensions, `~` as a skip character, Foundation's link
  conversion and URL spelling — **0 disagreements with Foundation on 2498
  sources**; MetalUI's attribute scope and `Text(AttributedString)`
  (`TextAttributes.swift`, `inlinePresentationIntent` honoured on Darwin);
  a `String` value is never parsed, nor is `Text(verbatim:)`; `Image`
  interpolation is a deprecated overload that traps (`RT-T` 1).
- **Demo**: `Sources/MetalUIDemoContent/RichTextDemo.swift`
  (`METALUI_RICH_TEXT_DEMO=1` in `MetalUIDemo` and `MetalUISDLDemo`: Markdown,
  interpolation, mixed sizes, decorations, truncation, an attributed string),
  each section its own function, in `buildEveryProductionTree` through
  `buildTheRichTextDemo()`.
- **Out of scope, named**: `TextField`/`TextEditor` stay plain `String`
  editors (caret offsets and IME are plain-text APIs, `TI-E`/`TI-H`).
  Interactive links, line-style patterns, view-level `bold()`/`underline()`,
  Markdown control titles, localisation tables, `Text(Image)` and the rest are
  §6.

## §2 Lane 1 — the seam and both systems

Commits `547f92d` (1.19's literals recorded on `70ed000`'s sources before any
source change: first frame 1020 misses / 1544 lookups, warm 0 / 110),
`46e3fc0` (red), `37111ee` (implementation), `ee3374e`, `f31e459` (`RT-P`,
`RT-Q`). **Suite 2672 → 2692** (+20 tests).

- **Tests**, by file: `StyledTextSeamTests` (1.1–1.9, 1.12–1.15, 1.19, 1.20;
  CoreText and portable through the seam), `StyledTextOracleTests` (1.10, the
  CoreText oracle, a corpus over the three test faces: mixed sizes and faces,
  kerning, tracking, offsets, wraps, bidi, limits, scales 1 and 2; 1.11,
  decoration metrics), `StyledTextPortableTests` (1.16, 1.17, run on Linux),
  `ShapingFeatureTests` (1.18).
- **Red first** rests on the stubs and the category list in `46e3fc0`'s
  message (both systems measure zero, lay out `[]`, decoration metrics zero,
  HarfBuzz ignores `features`), not on captured failure lines; the verifier
  read the stubs and found every red claim consistent, but did not rebuild
  `46e3fc0`.
- **Probe** `coretext-styled-spacing.swift` (`P0`, `S1`–`S5`): compiled twice
  byte-identical; the verifier re-ran it and the output matches its header.
- **Measured amendments** (`RT-P`): the ellipsis's run found in two attempts;
  a tracked line's last glyph's tracking is trailing whitespace; a style
  boundary that keeps the face splits no shaping run; kerning/tracking once
  per grapheme (`S1`, `S2`); **CoreText fills tracked joined Arabic with
  kashidas, the portable system does not (divergence 157, pin 1.20)**.
- **Mutations** (`RT-Q`; each on the committed tree, restored from a copy,
  the full unfiltered native suite, `git status --short` clean after each
  and at the end). Verified by the lane 1 verifier:

| # | mutation (spelling) | reddened |
|---|---|---|
| M1.1a | CoreText `StyledShaper.shape`: line height = ceil of typographic ascent+descent+leading | `aBaselineOffsetGrowsTheLineAndMovesItsGlyphs`, `aOneRunStyledTextMeasuresAsThePlainCallsOnBothSystems`, `aOneRunStyledTextPlacesThePlainGlyphsOnBothSystems`, `everyStyledCorpusCasePlacesTheSameGlyphsAsTheApplePath` |
| M1.1b | CoreText `attributes`: always set the kern attribute | the 1.1/1.2 pair, `bidiRunsSplitIntoOneSegmentPerVisualPiece`, the oracle, `spacingIsOncePerGraphemeAndKeepsPairKerningAcrossRuns` |
| M1.2 | portable `StyledLayout`: round the baseline before scaling | `aBaselineOffsetGrowsTheLineAndMovesItsGlyphs`, `aOneRunStyledTextPlacesThePlainGlyphsOnBothSystems`, the oracle |
| M1.3 | portable `LineBreaking`: a run boundary sets `lastAllowed` | `aRunBoundaryIsNotABreakOpportunity`, the oracle |
| M1.4 | portable `shape(from:)`: re-shape from a line start other than 0 with `runs.fixed(0)` | the oracle alone (reached from 1.10's narrow arm, `RT-Q` 2) |
| M1.5 | `lineMetrics`: sum ascents instead of max | 1.6, `aMixedLineTakesTheLargestAscentAndDescent`, `theEllipsisTakesTheFirstRemovedCharactersRun`, `thePortableSystemLaysOutAStyledTextOnEveryPlatform` |
| M1.6a | `lineMetrics`: descent = max(descent, face.descent − offset) | `aBaselineOffsetGrowsTheLineAndMovesItsGlyphs` (the single-run arm, `RT-Q` 1) |
| M1.6b | portable (and CoreText) row = baselineY + offset | 1.6, the oracle, `thePortableSystemLaysOutAStyledTextOnEveryPlatform` (portable); 1.6 and the oracle (CoreText spelling) |
| M1.7 | portable `shapeCascading`: no spacing on a run's last glyph | six, incl. `kerningAddsAfterEveryGlyphAndKeepsLigatures`, `trackingBreaksLigaturesOnBothSystems`, `segmentsSpanTheirAdvanceAndLinesKnowTheirVisibleExtent` |
| M1.8 | `HarfBuzzShaper.shape` ignores `features` | `disablingLigaturesShapesTheLigatureAsSeparateGlyphs`, `trackingBreaksLigaturesOnBothSystems`, the oracle, 1.20 |
| M1.9 | portable `Truncation` (and CoreText `truncatedLine`): the last kept unit's run | `theEllipsisTakesTheFirstRemovedCharactersRun`, the oracle |
| M1.10 | portable `shapeCascading`: covering face from `runs.fonts[0]` | `aMixedLineTakesTheLargestAscentAndDescent`, the oracle |
| M1.11 | `FreeTypeFont.xHeight`: 2 × `yStrikeoutPosition` | `theDecorationMetricsAgreeOnBothSystems` |
| M1.12 | `visibleExtent`: whitespace pens count | `segmentsSpanTheirAdvanceAndLinesKnowTheirVisibleExtent` |
| M1.13 | `segments`: drop the sort by x — **reddened nothing** (both systems already hand it pens in visual order; the sort is defensive); the recorded spelling sorts **by run (logical order)** | `bidiRunsSplitIntoOneSegmentPerVisualPiece` |
| M1.14 | styled cache key on `text.string` only (CoreText, and the portable key) | `aWarmStyledFrameShapesNothing` (both), 1.20 (CoreText) |
| M1.15 | `StyledText.init`: precondition `|| true` | `aStyledTextWhoseLengthsDoNotSumTraps` |
| M1.16 | `StyledText.init`: no merge | `zeroLengthRunsAreDroppedAndEqualNeighboursMerge` |
| M1.19b | `ShapingCache.Key`: options out of `==` and `hash` | seventeen plain-text tests (every height-cap and truncation test) |
| M1.20a | portable: extra = spacing on every glyph | `bidiRunsSplitIntoOneSegmentPerVisualPiece`, the oracle, 1.20 |
| M1.20b | portable: split the shaping run where tracking turns on | the oracle, 1.20 |

- **Pixels**: `compare.sh <scratch> 70ed000 f31e459`: all fourteen images
  0 px, identical scenes, every control reading its recorded value
  (1048576 / 1031003 / 454895 / 0 / 1048576 / 0 / 544 / 216 / 491221 / 529 / 0).
- **Linux**: a `swift:6.4-noble` container over a `git archive` of `f31e459`
  passed 6 + 35 + 18 + 199 + 51 + 22, 0 warnings — **not a clean warning
  count** (the scratch volume pre-existed, a 23 s incremental build).
  `Backends/SDL` not run (not touched).
- **Owed, named**: divergence 157 and the `TextSystem` migration note (lane 3,
  done); the plain-path centring bug of `RT-Q` 3 (§6).

## §3 Lane 2 — the `Text` element

Commits `81032fc` (red on stubs: every text plain, run fields ignored, no
operand refused, neighbours merged), `54c5453` (implementation), `e6d1b28`,
`23fc9ce` (`RT-R`), `439ae58` + `7e9fe09` (review, `RT-S`). **Suite 2692 →
2717 → 2719** (+27 tests, one new typecheck-guard file `RichTextCompileGuards`
and edits to `TextCompileGuards`).

- **Tests**: `RichTextTests` (run model, resolution, measurement 2.14–2.16,
  accessibility 2.13, links 2.17/2.18, the operand check 2.19/2.20, modifiers
  2.1–2.8), `RichTextPaintTests` (one leaf 2.11, underline/strikethrough
  rects, backgrounds, joined decorations, animation snap 2.23),
  `RichTextPortableWindowTests` (a styled text drawn through the portable system
  at a `Window`), plus the `Text` arm of `everyDecorationScopingSiteContainsItsOwnContent`.
  Review additions: 2.1b `theRichFieldsReachTheSeamWithTheirValues`, 2.1c
  `underlineFalseIsANoneTheOuterUnderlineDoesNotReach`, 2.19's left-operand
  arm, 2.22's outer-rich and `ProposalText.underline` arms.
- **Measured amendments** (`RT-R`): equal neighbours that differ only in paint
  stay two runs at the seam; 2.19's style arm is `.margin` (`.padding` does not
  compile, SwiftUI's own answer); 2.9's second arm compares paint's `layOut`
  width with the text's answer (its first spelling was a broken instrument);
  the rich fields boxed (SIGBUS in the 1 MB build otherwise); `+` joins equal
  segments; **`Text.bold()` is the bold weight over whichever font resolves —
  divergence 158** (SwiftUI: semibold on the default font, heavy on
  `.headline`, nothing on `.light`).
- **Mutations** (`RT-R` 10, `RT-S`; each on a committed tree, the full
  unfiltered native suite, `git status --short` clean after each — 2717 tests
  unless noted):

| # | reddened |
|---|---|
| M2.1 | `concatenationPushesEachSidesTextFieldsIntoItsUnsetRuns` |
| M2.2 | `aBackgroundFillsTheRunByTheLineBox`, `aMixedTextCapsLinesByTheirSummedHeights`, `aMixedTextReportsBaselinesFromItsLines`, `aRunsColourSnapsUnderAnAnimation`, `aStyledTextMeasuresAsCoreTextsAttributedLine`, `sameColouredUnderlinesMergeAndOthersDoNot` |
| M2.3 | `aFrameWithoutATextSystemUsesCoreTextOverItsOwnCache`, `aPlainTextTakesThePlainCalls`, `aPortableFrameNeverShapesThroughCoreText` |
| M2.4 | `aLinkDrawsInTheAccentUnlessItsRunIsColoured`, `aStyledTextDrawsThroughThePortableSystem`, `aStyledTextPaintsEachRunsColour` |
| M2.5 / M2.6 | `anUnderlineIsARectAtTheFacesPosition` / `aStrikethroughSitsOnHalfTheXHeight` |
| M2.7a / M2.7b | `aStyledTextDrawsThroughThePortableSystem`, `aStyledTextIsOneShadowLeaf`, `sameColouredUnderlinesMergeAndOthersDoNot` / the last alone |
| M2.8 | `aBackgroundFillsTheRunByTheLineBox` |
| M2.9 (re-spelled) | eight, among them `aWarmFrameOfAStyledTextShapesNothing`, `aStyledTextIsOneShadowLeaf`, `proposalTextDrawsTheSameStyledSpritesAsText` (the first spelling trapped with no summary) |
| M2.10 | the route pins of M2.3 (not 1.19: `RT-R` 7) |
| M2.11 / M2.12 | `aStyledTextIsOneShadowLeaf` / that and `everyDecorationScopingSiteContainsItsOwnContent` |
| M2.13 | `aLinkRegistersNothingAPlainTextDoesNot`, `aStyledTextPublishesItsConcatenatedString` |
| M2.14a/b, M2.15, M2.16 | `aMixedTextCapsLinesByTheirSummedHeights`, `reservedSpaceUsesTheFirstRunsLineHeight`, `aMixedTextReportsBaselinesFromItsLines` |
| M2.17 / M2.18 | `aLinkDrawsInTheAccentUnlessItsRunIsColoured` / `aLinkRegistersNothingAPlainTextDoesNot` |
| M2.19 | `concatenatingADecoratedTextTraps` |
| M2.20a–c | `concatenatingADecoratedTextTraps` + `theOperandCheckSeesEveryHandlersMember`; the last alone for b and c |
| M2.21a / M2.21b | `aOneRunStyledTextDrawsThePlainSprites` / seven, across both lanes' tests |
| M2.22 | seven, among them `proposalTextDrawsTheSameStyledSpritesAsText` |
| M2.R1 | four (`aStyledTextPaintsEachRunsColour`, …) |
| MG2.24a–c, MG2.25 | `theTextModifiersComposeAsSwiftUIs` ×3, `theConcatenationOperatorIsDeprecated` |
| MG3b | reddens the build first; its compiling spelling (V11, `bold()` internal): `textBoldIsOfferedSinceRichText`, `theTextModifiersComposeAsSwiftUIs` |
| M2.23 | **not run** (it needs a new code path); stand-in V9, a stale module-level colour table: `aRunsColourSnapsUnderAnAnimation` |

  Review mutations V1, V3–V8, V10 (2719 tests) each redden one new instrument:
  V1 `concatenatingADecoratedTextTraps`; V3 and V10
  `proposalTextDrawsTheSameStyledSpritesAsText`; V4
  `underlineFalseIsANoneTheOuterUnderlineDoesNotReach`; V5–V8 (kerning,
  tracking, baseline offset, monospaced zeroed) `theRichFieldsReachTheSeamWithTheirValues`.
  The verifier re-ran all of them on `7e9fe09` after `swift package clean`.

## §4 Lane 3 — the front ends and the demo

Commits `62cf5f6` (red on stubs: no parse, no runs kept, no attribute read, no
operand check, no parse counter), `5d043d2` (implementation, ruling `RT-T`),
`a261c27`, `4133b72` (two missing instruments), `86c7f8f`. **Suite 2719 →
2738 → 2739** (+20 tests; guards 3.10, 3.12 and `everyAttributeKeyIsWritableWithAPlainImport`).

- **Tests**: `MarkdownInlineTests` (the grammar, entities), `MarkdownOracleTests`
  (Darwin: **the parser against Foundation's on 2498 sources**, the probe's 53, the
  extras, 7⁴ generated; wider corpora of about 650 000 sources were run live while
  building, 0 disagreements, not in the suite), `LocalizedStringKeyTests`,
  `AttributedTextTests`, `TextLiteralCompileGuards`, the demo's headless render
  `theRichTextDemoDrawsThroughThePortableSystem`, and the 1 MB harness arm.
- **Measured** (`RT-T`): an unavailable `appendInterpolation(Image)` loses to
  the generic one, so the overload is deprecated and traps (exit test 3.10b);
  `~` is a skip character for `*`/`_` runs (10 of 2498 disagreed without it, 68
  with half of it, 0 with it); the trigger list uses `://` (Foundation links
  `ftp://x.org` and `HTTP://x.org`); a `Text` literal builds off the main actor
  (a `@MainActor` getter trapped in the 1 MB harness); Foundation's link
  conversion and URL spelling were copied, not reasoned; MetalUI does not
  re-export Foundation. **A finding outside this lane, deferred**: `Text.font(_:
  Font?)` and `ProposalText.font(_:)` trap off the main thread at `70ed000`
  (§6).
- **Mutations** (`RT-T` 9; on `5d043d2`, 2738 tests, `git status` clean after
  each; no run hung): M3.1a–d, M3.2, M-RT-T2 (parser grammar and skip
  characters: `theInlineGrammarMatchesTheProbedRuns`,
  `theParserAgreesWithFoundationOnTheCorpus`, plus
  `aMarkdownLinkAndAnAttributedLinkBuildOneRunKind` for the autolinks); M3.3
  (`onlyTheEntitySubsetDecodes`); M3.4 and M3.15 (`aLiteralParsesAndAValueDoesNot`,
  `aControlTitleIsVerbatim`); M3.5–M3.9 (the interpolation tests); MG3.10a–c
  (`theInitialisersReachSwiftUIsOverloads`, thirteen tests for 3.10a); M3.11 and
  M3.13 (`inlinePresentationIntentIsHonouredOnDarwin`, `theCodeSpanIsMonospaced`);
  M3.14, M3.16 (`aLiteralWithNoMarkupRunsNoParser`), M3.17 (the demo test).
  **MG3.10d and MG3.12 redden the build first** (an ambiguous `init(_:)` at
  MetalUI's own literals; the demo's `$0.foregroundColor = .orange`); MG3.12b,
  the compiling spelling, reddens `everyAttributeKeyIsWritableWithAPlainImport`
  alone. **Two instruments a review found missing** (on `4133b72`, 2739 tests;
  before them both mutations left `a261c27` green): MT.trig (`://` replaced by
  `http`) reddens `aFormatTheTriggerScanSkipsParsesToItself` (3.2b) and
  `aMarkdownLinkAndAnAttributedLinkBuildOneRunKind`; MT.port (the non-digit-port
  `return nil` removed) reddens `theParserAgreesWithFoundationOnTheCorpus` alone
  (three oracle extras Foundation sets no link on, read live on macOS 27). The
  lane 3 verifier re-ran both on `86c7f8f`.
- **Registries written by lane 3**: divergences 150–158, human-checks group RT,
  `docs/migration.md` rows, `docs/api-overview.md`, inventory rows, the census.

## §5 Branch checks

Per-lane checks are in §2–§4; the Record phase's whole-branch checks after the
merge with master are §8.

**Adversarial branch check of `70ed000..b78e08d`** (2026-10-08, re-taken, not
copied from §8):

- **Suite**: `swift package clean`, native build (0 `error:`, the one
  `warning:` SwiftPM's `--build-system native` notice), unfiltered
  `--no-parallel`: "Test run with 2790 tests in 3 suites passed after 268.154
  seconds."; `FR-J no-argument frame: succeeded=true`. `swift build
  --build-tests` (default build system): 0 warnings, 0 errors.
- **Pixels**: `compare.sh <scratch> 70ed000 HEAD`: controls 1048576 / 1031003 /
  454895 / 0 / 1048576 / 0 / 544 / 216 / 491221 / 529 / 0 (as §8), all
  fourteen images `differing=0`, scene identical. `Expected.swift` unchanged
  since `70ed000`.
- **`Backends/SDL`**: macOS 24 + 84 passed; Linux image (rebuilt, volume
  `metalui-sdl-build-rich-text`) 24 + 81 passed.
- **Inventory**: `closeout-inventory-check.sh` and `closeout-undocumented.sh`
  print nothing. `cmp CLAUDE.md AGENTS.md`: identical. Imports as §8. Guard
  annotations (`enabled(if: canTypecheck`) 175 at `cd84b0c`, 179 at HEAD: +4,
  agreeing with §8's delta.
- **Unchanged areas**: no file under identity, hit testing, accessibility,
  focus, `Deferred`, `List` or text input changed on the rich-text side of the
  merge; `theSevenRetentionSlotsAreMutuallyDistinct`,
  `everyNamingSiteStartsAReturningNameFresh`,
  `everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn`,
  `everyRegisteringSiteAnimatesItsLoweredRectUnderTheProposalAuthority`,
  `everyBackgroundPaintingSiteAnimatesItsColour`,
  `theLegacyEngineSymbolsAreAbsentFromTheTestProcess` and
  `everyProductionTreeBuildsOnAOneMegabyteThread` passed unedited. Pre-existing
  test files edited: `AnimationTests` (a header bullet),
  `DecorationPaintTests` (a styled-`Text` arm added), `MenuPickerTests` (the
  fake's three new requirements), `TextCompileGuards` (G3.2 renamed
  `textBoldIsOfferedSinceRichText`, `RT-R` item 6).
- **Mutation C1** (`MarkdownInline.swift` `extendedLinkEnd`: the
  `data[linkEnd].scalar != nil` test removed, so an extended autolink runs
  through a placeholder): **reddens nothing** (2790 passed). Not an
  equivalent mutant: a temporary probe test (deleted) printed
  `Text("see www.a.com\(v) b")` with `v = "Q"` as runs `www.a.comQ` (link) /
  ` b` under the mutant and `www.a.com` (link) / `Q b` restored. This is the
  lane 3 verifier's mutation I, confirmed: `RT-T` item 3's termination clause
  is unpinned, and the ruling now says so (only the delimiter arm, 3.5, is
  pinned).
- **Mutation C2** (`StyledShaping.swift` `attributedString`: every run set in
  `fonts[0]`, the CoreText path's per-run font): reddens
  `aMixedLineTakesTheLargestAscentAndDescent`,
  `aStyledTextMeasuresAsCoreTextsAttributedLine`,
  `bidiRunsSplitIntoOneSegmentPerVisualPiece` and
  `everyStyledCorpusCasePlacesTheSameGlyphsAsTheApplePath` (5 issues).
- `git status --short` after each restore: only this check's doc edits.

## §6 Deferred, each with its owner

- **Interactive links** (`openURL`, click, keyboard, an accessibility link
  element): needs per-run hit regions in one leaf; hit testing and
  accessibility must not move. Divergence 150. Owner: none.
- Line-style patterns (`.dot`, `.dash`, …), view-level `bold()`/`underline()`/…
  on any group, Markdown in control titles (divergence 154), localisation
  tables, `Text(Image)`, `textCase`, `textScale`, `fontWidth`,
  `monospacedDigit`, formatter interpolation, descender-skipping underlines,
  named entities beyond the subset (divergence 153), animated run colours
  (they snap, as a plain `Text`'s glyph colour always has): owner none.
- **Rich `TextField`/`TextEditor`**: they stay plain; owner none.
- **A plain-path portable-text bug found by lane 1's fixture** (`RT-Q` 3, not
  rich text; the plain path must not move here): the portable system centres
  (or trails) a line that starts inside a cluster by the cluster's
  paragraph-shaped advance, not the re-shaped line's. Red case:
  `placeGlyphs("office")`, Source Sans 3 at 26 pt, width 8, `.center`: the
  second line's glyph at pixel −4 where CoreText draws it at 0. **Owner: a
  portable-text follow-up** (the `trailingWhitespace` of a re-shaped line in
  `LineBreaking.swift`), with this case as its first test. No red test is in
  the tree.
- **`Text.font(_: Font?)`/`ProposalText.font(_:)` trap off the main actor** (the
  `font.map { .explicit($0) }` closure in a main-actor method); only the 1 MB
  harness builds off the main thread. Owner: none (a one-line `if let`).
- A URL `URL(string:)` rejects that still links here (`RT-T` 6): no corpus row
  reaches it. Owner: none.
- **A placeholder ending a link destination, title, autolink, extended
  autolink, entity or raw HTML tag** (`RT-T` 3) is unpinned: mutation C1 (§5)
  reddens nothing. Owner: none (a test per arm).
- CI confirmation of `DemoFrameDeterminismTests`' `Expected.swift` (unedited) on
  Linux and Windows after the push: owner the push.

## §7 Human checks owed

`docs/verification/human-checks.md` group **RT** (RT1–RT6), none performed (an
agent cannot): RT1 the demo on macOS (every Markdown form styled, light and
dark); RT2 underline/strikethrough crispness at 1× and 2× (divergence 152);
RT3 the mixed-size paragraph's line spacing and the superscript; RT4 the same
demo on Linux and Windows through SDL; RT5 VoiceOver reads the sentence once
without markers; RT6 clicking a link does nothing. The demo was **not
launched** and no real-window capture was taken.

## §8 Record phase: merge, suite and counts

- **Merge**: `git fetch` showed master past `70ed000` (PR #53, variable-height
  `List`, §82; `fix/task-followups`, §84). `origin/master` merged as `ee857db`;
  conflicts were the two demo `main.swift` files, `DemoStackBudgetTests`,
  `migration.md`, `divergences.md`, `human-checks.md` and the census, all
  resolved by keeping both sides; §83 was free, no renumbering.
- **Suite** (`swift package clean`, `swift build --build-system native
  --build-tests`, `swift test --build-system native --no-parallel`, unfiltered):
  **`Test run with 2790 tests in 3 suites passed after 165.876 seconds`**
  (master's 2723 + 67; the branch's 2672 + 20 + 27 + 20 = 2739 before the merge),
  `FR-J no-argument frame: succeeded=true`, 0 `error:`, the only `warning:`
  SwiftPM's `--build-system native` deprecation notice. `swift build
  --build-tests` on the default build system: 0 warnings, 0 errors.
- **Guards: 180** (master's 176 + 4: five new — `theConcatenationOperatorIsDeprecated`,
  `theTextModifiersComposeAsSwiftUIs`, `textBoldIsOfferedSinceRichText`,
  `everyAttributeKeyIsWritableWithAPlainImport`, `theInitialisersReachSwiftUIsOverloads`
  — and `textBoldIsNotOffered` re-spelled; all five passed in the native log).
  The count is a delta on master's recorded 176 from a function-level scan of
  the `typecheck`/`typecheckFile` call sites, not a log tally (the log carries
  no per-guard counter).
- **Public census 2685** (`closeout-public-api.sh`, regenerated after the merge;
  master 2540, +145 for rich text); `closeout-inventory-check.sh` and
  `closeout-undocumented.sh` print nothing.
- **Pixels**: `compare.sh <scratch> 70ed000 HEAD` at `ee857db`: controls as
  recorded (1048576 / 1031003 / 454895 / 0 / 1048576 / 0 / 544 / 216 / 491221 /
  529 / 0) and **all fourteen images `differing=0`, scene identical**.
- **`Backends/SDL`** (`swift test $(python3 scripts/fetch-accesskit.py
  --print-flags)` from `Backends/SDL`, macOS; the demo's `main.swift` was a merge
  conflict): **24 + 84** passed. **Linux image** (`docker build -t metalui-portable`,
  volume `metalui-sdl-build-rich-text`): **24 + 81** passed. **Root package in
  `swift:6.4-noble`** (fresh volume, so a clean warning count: 0 warnings):
  **6 + 35 + 18 + 199 + 67 + 22** passed.
- **Imports**: `MetalUILayout` imports only `MetalUICore`, `MetalUIScene` only
  `MetalUIShaderTypes`, `MetalUITextSystem` and `MetalUIPortableText` no Foundation.
- **Documents**: `CLAUDE.md`/`AGENTS.md` (the `RT-` prefix, one rule paragraph, the
  three `TextSystem` requirements beside `PlatformWindow`'s, the demo switch,
  counts), `docs/divergences.md` 150–158 (the header's count and next label left
  for the final merge), `docs/migration.md`, `docs/api-overview.md`,
  `docs/verification/human-checks.md` group RT, `docs/record/README.md`, §03, §04
  (150–158), §05 (the inert link), the inventory map and census.
- **Not done**: the demo was not launched; no real-window capture; the
  Windows UTM VM was not used; CI confirms `Expected.swift` after the push.
