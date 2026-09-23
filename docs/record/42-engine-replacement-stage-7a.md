# §42 — Engine replacement, stage 7a: the goldens retired

Plan task 7, stage 7a (parent design
`docs/superpowers/specs/2026-09-17-engine-replacement-design.md` §4.1 row 7a,
§8). Design: `docs/superpowers/specs/2026-09-23-engine-stage-7a-design.md`.
Rulings `LR-DS`…`LR-DX` (critic round 1: `LR-DY`) in
`docs/superpowers/2026-09-17-engine-replacement-decisions.md`. Branch
`feat/engine-stage-7a` from `2cc763d`, worktree
`/Users/maxburger/Developer/worktrees/MetalUI/stage-7a`. Probe:
`docs/probes/swiftui-engine-stage-7a.swift` (arms W, G, S, A, B). Instrument:
`docs/probes/stage-7a-transcription-instrument.patch`.

**Numbering hazard.** Written as §42, the next free number at `2cc763d` (§41 is
stage 6b). If another line reaches `master` first with a §42, this file is
renumbered at merge by the precedent of record §23 §8 and the §25/§27/§29/§38/§41
headers.

**Status, 2026-09-23 (PDT): design (§1–§5).** No file under `Sources/`,
`Tests/` or `Package.swift` changed in a commit. The instrument was applied as an
uncommitted scratch test (`Tests/MetalUITests/ZZScratch7a.swift`), built, run
with `--filter scratch7aDump`/`scratch7aDump2`, captured as the patch above and
deleted; `git status --short` afterwards showed only this design's files. The
lanes append from §6.

## 1. Baseline at `2cc763d`

`swift build --build-system native --build-tests` (0 `error:`, the one
`warning:` SwiftPM's deprecation notice), then unfiltered `swift test
--build-system native --no-parallel`: **`Test run with 1704 tests in 3 suites
passed`**, the log carrying `FR-J no-argument frame: succeeded=true` (the
guards ran). Goldens: `find Tests/MetalUILayoutTests -name "*.json" | wc -l` →
**97** (`flex_` 69, `stack_` 14, `sizing_` 9, `abs_` 5). Guards 78, none added
by this stage.

The golden machinery, read in full:

- `Tests/MetalUILayoutTests/Fixtures/*.html` (97) — one CSS page per golden,
  every box of interest carrying a `data-id`;
- `Tests/MetalUILayoutTests/Oracle/` — `LayoutOracle.swift` (drives a
  `WKWebView`, returns `NodeBox`es), `GenerateGoldens.swift`
  (`generateGolden`, `writeGolden`), `GoldenFile.swift` (`GoldenFile`,
  `fixtureURL`, `goldenURL`, `loadGolden`, `roundBoxes`);
- `Tests/MetalUILayoutTests/Golden/*.json` (97) plus `.gitkeep` — WebKit's raw
  and `roundLayout`-rounded boxes;
- `GeneratorTests.swift` — 5 `@Test`s: `generatorProducesRawAndRoundedForAFixture`,
  `generatorRoundsWhenTheBrowserQuantizes`, `regenerateAllGoldens` (gated,
  `METALUI_REGENERATE_GOLDENS=1`), `committedGoldensMatchTheBrowser`,
  `everyFixtureFileIsListedInTheCorpus`; and the `allFixtures` list;
- `OracleTests.swift` — 3: `oracleMeasuresFlexboxFromAFixtureFile`,
  `oracleReportsSubPixelQuantization`, `goldenFileRoundTripsThroughJSON`;
- `FlexEngineTests.swift`'s `assertMatchesGolden` (tolerance 0.1 against
  `rounded`);
- `Package.swift`: `MetalUILayoutTests`' `resources: [.copy("Fixtures"),
  .copy("Golden")]`. No other `Bundle.module` use in that target (grep).

**The 97 consumers.** Every golden has exactly one assertion consumer, one
`@Test` each (a scan of every `loadGolden("…")` call site): `FlexEngineTests`
16, `WrappingTests` 17, `StackFixtureTests` 15, `FreezeLoopTests` 13,
`BoxModelTests` 12, `SizingFixtureTests` 9, `FitContentFixtureTests` 6,
`AbsoluteFixtureTests` 5, `ContentSizingFixtureTests` 4 — spec §2.6's figures.
91 assert nothing but `assertMatchesGolden`. Six assert more:
`percentageFlexBasisResolvesAgainstTheMainAxis`,
`aShrinkTargetBelowZeroClampsToZeroInsteadOfStoringANegativeWidth`,
`paddedShrinkWeightingMatchesWebKit`,
`aMaxMainSizeClampsTheContentSizeSuggestionMatchesWebKit` and
`aColumnItemsContentSuggestionIsMeasuredAtItsUsedWidthMatchesWebKit` restate the
golden's own numbers as literals (checked against the JSON, every one equal);
**`theClampedAutomaticMinimumIsStillFlooredByPaddingAndBorderMatchesWebKit`**
also asserts a second, non-golden tree (`cMinZero: true`: `c` at x 80, 40 wide,
`b` at x 120) — a legacy-engine fact that is 7b's, not 7a's (`LR-DT`).

## 2. The entry measurement: every golden's tree under the proposal authority

**Method.** Each fixture's CSS was transcribed into the element API as
`Box(style:)` trees carrying exactly the fixture's `Style` fields (flex
shorthand split into grow/shrink/basis, `gap: r c` as `Axes(horizontal: c,
vertical: r)`, margin/padding/border shorthands in CSS order, a CSS grid with
`grid-area: 1/1` as `display: .stack` with `justifyItems`/`alignItems`), every
golden id named with `.id("<data-id>")`, and rendered by
`LayoutDifferential.render(authority:width:height:)` at the fixture's viewport
(800×600; 400×200 for `flex_row_seven_equal`) — **once under each authority** —
reading `Frame.elementBounds` for every named id and
`Frame.unlowerableFields`. Absolute fixtures were transcribed with the
absolute box inside a `Deferred` and the render sized to the fixture's root
(200×100, or 800×600 for `abs_removed_from_flow`, whose containing block is the
initial one), so the window stands for the `position: relative` root.

**Result.** 74 of the 97 trees were transcribed (the other 23 each contain a
`flex-wrap` box: §2.2). **Under the legacy authority all 74 reproduce their
golden exactly** — the transcription check: a wrong transcription would
disagree on the engine the golden already pins. Under the proposal authority:

- **44 reproduce their golden's rounded boxes exactly, with an empty report**
  (43 whole trees, plus `stack_stretch_max` with its percentage child `p`
  removed: `h` 300×50, `w` 40×200 exactly). These are the **R** rows.
- **23 report by name** and lay out a 0×0 lowered leaf: `box.flexWrap` 7
  (with `box.alignContent` on 2 and `box.maxSize` on 1); `box.flexBasis` 8
  (with `box.flexGrow.weights` on 1 and `box.size.percent` on 1);
  `box.flexGrow.weights` alone 1; `box.maxSize` 2; `box.padding.percent` 2;
  `box.size.percent` alone 3. (Two further reports belong to transcription
  variants, not to D rows: the whole `stack_stretch_max` tree reports
  `box.maxSize.percent` for its child `p`, and `abs_over_constrained` written
  with its absolute box outside a `Deferred` reports `box.position`,
  `box.inset` — stage 5's rule; inside a `Deferred` it reproduces.)
- **7 lay out silently with a different answer** — the silent D shapes:

| golden | WebKit (golden) | proposal authority, measured |
|---|---|---|
| `flex_row_fractional_grow` | a 100, b 100 at 100, c 100 at 200 | a 133, b 134 at 133, c 133 at 267 |
| `flex_row_fractional_grow_clamped` | a 50, b 100 at 50 | a 50, b **350** at 50 |
| `flex_row_shrink_padded_weighting` | a 125, b 75 at 125 | a 200, b 200 at 200 (overflow) |
| `sizing_specified_suggestion` | a 130 (g1 130), b 20 at 130 | a 130 (g1 200), b 100 at 130 |
| `sizing_specified_suggestion_is_used_value` | a 120 (g1 0×20 at 60,10), b 30 at 120 | a 100 (g1 200×20 at 60,10), b 100 at 100 |
| `sizing_over_constrained_grows` | box 120×140, kid 0×10 at 60,70 | box 100×80, kid 10×10 at 60,70 |
| `stack_stretch_border_box_floor` | f 120×140, c 120×140 | f 100×100, c 40×50 |

The whole dump (152 lines, both authorities) is reproduced by applying the
instrument patch and running `swift test --build-system native --filter
scratch7aDump`.

### 2.1 What the 44 reproductions mean

Every R tree reproduces WebKit **through the stage-2/3/5 lowering** —
spacers for `space-*`, reversed node lists, native padding for padding +
border, outermost native padding for margins, cross-axis item frames for
stretch/`alignSelf`, greedy frames with the declared maximum for growers, a
native overlay for `display: .stack`, and the window-relative presentation for
`Deferred` absolute boxes. None of these facts is asserted today with the
golden's numbers under the proposal authority; the lowering suites assert the
same rules on other geometry (`LoweringDistributionTests`,
`LoweringItemTests`, `LoweringBoxModelTests`, `LoweringStackAndLayerTests`,
`PresentationLoweringTests`). So the replacement for each R golden is a **new
arm** that builds the golden's own tree under the proposal authority and
asserts its rounded boxes literally (`LR-DS`), not a citation of a test on
different numbers.

### 2.2 The 23 untranscribed trees

All 23 contain a box with `flex-wrap: wrap` or `wrap-reverse` (16 `flex_wrap_*` —
corrected from 18 by critic round 1, `LR-DY`: `flex_wrap_uneven` and
`flex_wrap_min_vs_max_content` were transcribed —
`flex_column_fit_content` ×4, `sizing_column_content_suggestion`,
`stack_fit_content_inline`, `stack_fit_content_min_content_contribution`).
`LegacyLowering.legacyContainerDiagnostics` reports `flexWrap` for **any**
`declared.flexWrap != .noWrap` (`LegacyLowering.swift:209`), pinned by
`everyContainerFieldEitherLowersAndAgreesOrIsReportedByName`'s "wrap" arm;
seven wrap-bearing trees were transcribed and each reported it (as the root, as
a column child, as a stack child, as a row child with a declared width, as a
capped child). Transcribing the other 23 would measure the same report
twenty-three more times — **except for the value `wrapReverse`**, which none of
the seven declares and no existing test lowers; critic round 1 found that gap and
added test 2.8 (`LR-DY`).

## 3. SwiftUI evidence (probe run 2026-09-23)

`/usr/bin/swift docs/probes/swiftui-engine-stage-7a.swift`, Apple Swift 6.4
(swiftlang-6.4.0.33.1), macOS 27.0 (26A428); exit 0, run twice, byte-identical,
17 lines (the design wrote 15; five group headers and twelve arms are 17 —
`LR-DY`; critic round 1 re-ran it twice more, both byte-identical to the header), recorded in its header with a reading. Every group has a positive
control that differs:

- **W** — the VStack control stacks four 50×20s at y 10/30/50/70; the HStack
  puts all four at y 40 on one overflowing line, with or without
  `.frame(width: 120)`. **A SwiftUI stack does not wrap.**
- **G** — two greedy frames beside a fixed 100 share 700 as 300/300 (G0);
  `layoutPriority(1)` on one gives it all 600 and the other 0 (G1). **Equal
  flexibility shares equally; the per-child knob is a priority, not a weight.**
  (G2 — a greedy frame capped at 50 beside two uncapped ones reads 50/175/175,
  `flex_row_grow_with_max`'s numbers — is recorded, not relied on.)
- **S** — flexible 0…200 frames compress to 100/100 in 200 (S0); two fixed
  200s stay 200 each and overflow (S1). **A fixed frame is not shrunk.**
- **A** — a 200 child in `.frame(width: 130)`: the frame answers 130 and the
  child overflows (A1; control A0 200). **Content does not floor a fixed
  frame.**
- **B** — `c.padding(60, 50)` answers 110×130 (B0); inside `.frame(width: 100,
  height: 80)` the frame answers 100×80 (B1). **Padding does not floor a fixed
  frame.** Where the overflowing child sits is not claimed: MetalUI's lowering
  places it at the leading inset (kid at 60,70), SwiftUI centres the padded view.

No SwiftUI claim is made about percentages, margins, reversal, absolute
positioning or stacks: every row on those rests on MetalUI's own measured
behaviour.

## 4. The retirement table (97 rows)

Verdicts (`LR-DS`): **R** — the golden's own tree, under the proposal
authority, reproduces its rounded boxes exactly with an empty report, and a new
arm named for the golden asserts those boxes literally; **D** — the concept the
golden pins is CSS-only and is deleted with it, named, with the native test
that pins what the proposal authority does with that shape instead (a report by
name, or — for the seven silent shapes — a new pin of the golden's own tree at
the native answer). Test numbers are spec §6's. **The R replacements and the D
pins 2.5–2.7 are owed by lanes 1 and 2**; lane 3 deletes nothing until each one
exists and is green (`LR-DX`).

| # | golden | consumer test removed | fact it pins (WebKit) | verdict | replacement / deleted concept |
|---|---|---|---|---|---|
| 1 | `flex_auto_height_two_levels` | `ContentSizingFixtureTests.autoHeightAtTwoLevelsMatchesWebKit` | auto heights sum their content through two column levels (48), the sibling after at y 48 | R | `GoldenReplacementFlexTests` 1.8 `autoMainSizesSumTheirContentAndAGrowerIsFlooredByIt` |
| 2 | `flex_column_fit_content` | `FitContentFixtureTests.columnFitContentMatchesWebKit` | a column item's auto width is fit-content (a wrapping child 120, a 50% one 60) | D | **wrap**, as content (a wrapping box's min-/max-content widths, TX-H fit-content) (`flex-wrap`/`align-content`) — `box.flexWrap` reported by name (`everyContainerFieldEitherLowersAndAgreesOrIsReportedByName`, "wrap" arm); SwiftUI stacks lay out one line (7a probe W1, W2 vs W0); its 50% child is **percentages** too |
| 3 | `flex_column_fit_content_floor` | `FitContentFixtureTests.columnFitContentFloorMatchesWebKit` | fit-content is floored by min-content (50 in a 30 column) at each alignment | D | **wrap**, as content (a wrapping box's min-/max-content widths, TX-H fit-content) (`flex-wrap`/`align-content`) — `box.flexWrap` reported by name (`everyContainerFieldEitherLowersAndAgreesOrIsReportedByName`, "wrap" arm); SwiftUI stacks lay out one line (7a probe W1, W2 vs W0) |
| 4 | `flex_column_fit_content_margins` | `FitContentFixtureTests.columnFitContentSubtractsCrossMarginsLikeWebKit` | fit-content subtracts the cross margins (104) | D | **wrap**, as content (a wrapping box's min-/max-content widths, TX-H fit-content) (`flex-wrap`/`align-content`) — `box.flexWrap` reported by name (`everyContainerFieldEitherLowersAndAgreesOrIsReportedByName`, "wrap" arm); SwiftUI stacks lay out one line (7a probe W1, W2 vs W0) |
| 5 | `flex_column_fit_content_nested` | `FitContentFixtureTests.nestedColumnFitContentMatchesWebKit` | fit-content inside a padded, centring column (120) | D | **wrap**, as content (a wrapping box's min-/max-content widths, TX-H fit-content) (`flex-wrap`/`align-content`) — `box.flexWrap` reported by name (`everyContainerFieldEitherLowersAndAgreesOrIsReportedByName`, "wrap" arm); SwiftUI stacks lay out one line (7a probe W1, W2 vs W0) |
| 6 | `flex_column_fit_content_nested_auto` | `FitContentFixtureTests.nestedAutoWidthColumnFitContentMatchesWebKit` | fit-content through an auto-width column (70) | D | **wrap**, as content (a wrapping box's min-/max-content widths, TX-H fit-content) (`flex-wrap`/`align-content`) — `box.flexWrap` reported by name (`everyContainerFieldEitherLowersAndAgreesOrIsReportedByName`, "wrap" arm); SwiftUI stacks lay out one line (7a probe W1, W2 vs W0) |
| 7 | `flex_column_grow_with_max` | `FreezeLoopTests.columnGrowWithAMaxHeightMatchesWebKit` | the column case: 50/175/175 | R | `GoldenReplacementFlexTests` 1.7 `equalGrowersShareTheLineAndAMaximumCapsItsGrower` |
| 8 | `flex_column_justify_center` | `FlexEngineTests.columnJustifyCenterMatchesWebKit` | justify center on a column: y 120/160/230 | R | `GoldenReplacementFlexTests` 1.2 `justifyContentDistributesADeclaredMainSizesFreeSpace` |
| 9 | `flex_column_padding_asymmetric` | `FlexEngineTests.columnPaddingAsymmetricMatchesWebKit` | the column case; stretched items 64 wide at x 24 | R | `GoldenReplacementFlexTests` 1.5 `paddingAndBorderInsetTheContentBoxEdgeByEdge` |
| 10 | `flex_column_reverse_justify_end` | `FlexEngineTests.columnReverseJustifyEndMatchesWebKit` | column-reverse + flex-end packs from the top, first item last: y 120/50/0; auto width stretched | R | `GoldenReplacementFlexTests` 1.4 `aReverseDirectionPacksItemsFromTheMainEnd` |
| 11 | `flex_column_reverse_margins` | `BoxModelTests.columnReverseMarginsMatchWebKit` | the column-reverse case: y 320/246/168 | R | `GoldenReplacementFlexTests` 1.6 `marginsOffsetEachItemOutsideItsBorderBox` |
| 12 | `flex_column_three_fixed` | `FlexEngineTests.columnOfFixedChildrenMatchesWebKit` | the column case: y 0/20/50 | R | `GoldenReplacementFlexTests` 1.1 `fixedItemsPackFromTheMainStartAtTheirOwnSizesAndGap` |
| 13 | `flex_in_stack` | `StackFixtureTests.flexInStackMatchesWebKit` | a row centred in a stack over a backdrop: row 90x25 at (105, 88) | R | `GoldenReplacementStackTests` 2.3 `aStackHugsItsLargestChildInsideARowAndAroundOne` |
| 14 | `flex_item_floored_by_content` | `ContentSizingFixtureTests.itemFlooredByItsContentMatchesWebKit` | a zero-basis grower with 80 of content keeps 80; its sibling gets 20 | R | `GoldenReplacementFlexTests` 1.8 `autoMainSizesSumTheirContentAndAGrowerIsFlooredByIt` |
| 15 | `flex_nested_auto_cross` | `ContentSizingFixtureTests.nestedAutoCrossMatchesWebKit` | an auto cross size is the content's, on a wrapping root | D | **wrap**, as content (a wrapping box's min-/max-content widths, TX-H fit-content) (`flex-wrap`/`align-content`) — `box.flexWrap` reported by name (`everyContainerFieldEitherLowersAndAgreesOrIsReportedByName`, "wrap" arm); SwiftUI stacks lay out one line (7a probe W1, W2 vs W0) |
| 16 | `flex_nested_padding` | `BoxModelTests.nestedPaddingMatchesWebKit` | a padded, bordered container inside another: g2 grows to 134 at (58, 38) | R | `GoldenReplacementFlexTests` 1.5 `paddingAndBorderInsetTheContentBoxEdgeByEdge` |
| 17 | `flex_nested_percent_padding` | `BoxModelTests.nestedPercentPaddingMatchesWebKit` | percentage padding on a nested container resolves against its parent's width | D | **percentages** — reported by name (`percentagesStillReportByNameWithTheirOwner`), owned by stage 8's recipe (`LR-AI`); no SwiftUI claim made |
| 18 | `flex_percent_child_in_padded` | `BoxModelTests.percentChildInPaddedParentMatchesWebKit` | a percentage size resolves against the parent's content box | D | **percentages** — reported by name (`percentagesStillReportByNameWithTheirOwner`), owned by stage 8's recipe (`LR-AI`); no SwiftUI claim made |
| 19 | `flex_percent_padding_nonsquare` | `BoxModelTests.percentPaddingNonSquareMatchesWebKit` | percentage padding resolves against the width on every edge | D | **percentages** — reported by name (`percentagesStillReportByNameWithTheirOwner`), owned by stage 8's recipe (`LR-AI`); no SwiftUI claim made |
| 20 | `flex_row_align_center` | `FlexEngineTests.rowAlignCenterMatchesWebKit` | align-items center: y 40/20/30 | R | `GoldenReplacementFlexTests` 1.3 `alignItemsAndAlignSelfPlaceEachItemOnTheCrossAxis` |
| 21 | `flex_row_align_end_with_self` | `FlexEngineTests.rowAlignEndWithSelfOverrideMatchesWebKit` | align-items flex-end, one align-self center: y 80/20/60 | R | `GoldenReplacementFlexTests` 1.3 `alignItemsAndAlignSelfPlaceEachItemOnTheCrossAxis` |
| 22 | `flex_row_block_axis_max_content` | `FitContentFixtureTests.rowBlockAxisIsMaxContentMatchesWebKit` | a row's cross axis is the block axis: max-content height (40) | D | **wrap**, as content (a wrapping box's min-/max-content widths, TX-H fit-content) (`flex-wrap`/`align-content`) — `box.flexWrap` reported by name (`everyContainerFieldEitherLowersAndAgreesOrIsReportedByName`, "wrap" arm); SwiftUI stacks lay out one line (7a probe W1, W2 vs W0) |
| 23 | `flex_row_explicit_min` | `FreezeLoopTests.explicitMinWidthMatchesWebKit` | a min-width floors a shrinking item: 150/150 | D | **length `flex-basis` and weighted shrink** (flex §9.7.4.c) — `box.flexBasis` reported (`aZeroBasisGrowerTakesItsShareDownToItsContent`, the 40px arm); positive shrink lowers as compression whatever its weight (`aPositiveShrinkLowersAsSwiftUIsCompressionWhateverItsWeight`, divergence 55); a fixed frame is not shrunk (7a probe S1 vs S0); the field is stage 8/10's to respell or delete (`LR-AO`, `LR-DY`) |
| 24 | `flex_row_fixed_and_grow` | `FreezeLoopTests.growMatchesWebKitOnTheUnusedGolden` | grow 1:2 beside a fixed 100: 200/400/100 | D | **unequal grow weights** — `box.flexGrow.weights` reported (`unequalGrowWeightsAreReportedOnTheParent`); SwiftUI shares a surplus equally and `layoutPriority` is a priority, not a weight (7a probe G0, G1); the field is stage 10's (`LR-AO`) |
| 25 | `flex_row_fractional_grow` | `FreezeLoopTests.fractionalGrowMatchesWebKit` | a grow-factor sum below 1 leaves space: three 0.25s take 100 each of 400 | D | **sub-one grow sum** (flex §9.7.4.b) — lowers silently as an equal greedy share (133/134/133), pinned by `GoldenReplacementStackTests` 2.5 `aGrowFactorSumBelowOneStillFillsTheLine`; SwiftUI shares equally (7a probe G0) |
| 26 | `flex_row_fractional_grow_clamped` | `FreezeLoopTests.clampedFractionalGrowMatchesWebKit` | the sub-one clause scales the initial free space: 50/100 | D | **sub-one grow sum** — native 50/350, pinned by `GoldenReplacementStackTests` 2.5 `aGrowFactorSumBelowOneStillFillsTheLine` |
| 27 | `flex_row_fractional_shrink` | `FreezeLoopTests.fractionalShrinkMatchesWebKit` | a shrink-factor sum below 1: 175/175 | D | **length `flex-basis` and weighted shrink** (flex §9.7.4.c) — `box.flexBasis` reported (`aZeroBasisGrowerTakesItsShareDownToItsContent`, the 40px arm); positive shrink lowers as compression whatever its weight (`aPositiveShrinkLowersAsSwiftUIsCompressionWhateverItsWeight`, divergence 55); a fixed frame is not shrunk (7a probe S1 vs S0); the field is stage 8/10's to respell or delete (`LR-AO`, `LR-DY`) |
| 28 | `flex_row_gap` | `FlexEngineTests.rowWithGapMatchesWebKit` | a 12 gap between each pair: x 0/72/174 | R | `GoldenReplacementFlexTests` 1.1 `fixedItemsPackFromTheMainStartAtTheirOwnSizesAndGap` |
| 29 | `flex_row_grow_nonzero_basis` | `FreezeLoopTests.growWithANonZeroBasisMatchesWebKit` | a 100px basis grows from its basis: 250/150 | D | **length `flex-basis` and weighted shrink** (flex §9.7.4.c) — `box.flexBasis` reported (`aZeroBasisGrowerTakesItsShareDownToItsContent`, the 40px arm); positive shrink lowers as compression whatever its weight (`aPositiveShrinkLowersAsSwiftUIsCompressionWhateverItsWeight`, divergence 55); a fixed frame is not shrunk (7a probe S1 vs S0); the field is stage 8/10's to respell or delete (`LR-AO`, `LR-DY`) |
| 30 | `flex_row_grow_space_between_margins` | `BoxModelTests.rowGrowSpaceBetweenWithMarginsMatchesWebKit` | a capped grower beside margins and space-between: a 150 at x 9, c at 346 | R | `GoldenReplacementFlexTests` 1.6 `marginsOffsetEachItemOutsideItsBorderBox` |
| 31 | `flex_row_grow_uneven` | `FreezeLoopTests.unevenGrowMatchesWebKit` | grow 1:3 beside a rigid 140 basis: 125/375/140 | D | **unequal grow weights** — `box.flexGrow.weights` reported (`unequalGrowWeightsAreReportedOnTheParent`); SwiftUI shares a surplus equally and `layoutPriority` is a priority, not a weight (7a probe G0, G1); the 140 basis also reports `box.flexBasis`; the fields are stage 10's and 8/10's (`LR-AO`) |
| 32 | `flex_row_grow_with_max` | `FreezeLoopTests.growWithAMaxWidthMatchesWebKit` | a capped grower freezes at 50, the rest share 175/175 | R | `GoldenReplacementFlexTests` 1.7 `equalGrowersShareTheLineAndAMaximumCapsItsGrower` (7a probe G2 reads the same numbers in SwiftUI; not a claim any ruling rests on) |
| 33 | `flex_row_justify_around` | `FlexEngineTests.rowJustifySpaceAroundMatchesWebKit` | space-around: half gaps at the edges, 40/160/310 | R | `GoldenReplacementFlexTests` 1.2 `justifyContentDistributesADeclaredMainSizesFreeSpace` |
| 34 | `flex_row_justify_between` | `FlexEngineTests.rowJustifySpaceBetweenMatchesWebKit` | space-between: 0/160/350 | R | `GoldenReplacementFlexTests` 1.2 `justifyContentDistributesADeclaredMainSizesFreeSpace` |
| 35 | `flex_row_justify_between_gap` | `FlexEngineTests.rowJustifySpaceBetweenWithGapMatchesWebKit` | the gap is the between-spacer minimum, not added to it: 0/160/350 | R | `GoldenReplacementFlexTests` 1.2 `justifyContentDistributesADeclaredMainSizesFreeSpace` |
| 36 | `flex_row_justify_evenly` | `FlexEngineTests.rowJustifySpaceEvenlyMatchesWebKit` | space-evenly: 60/160/290 | R | `GoldenReplacementFlexTests` 1.2 `justifyContentDistributesADeclaredMainSizesFreeSpace` |
| 37 | `flex_row_margin_with_grow` | `BoxModelTests.rowMarginWithGrowMatchesWebKit` | a grower's share excludes its margins: 274 at x 9 | R | `GoldenReplacementFlexTests` 1.6 `marginsOffsetEachItemOutsideItsBorderBox` |
| 38 | `flex_row_margins` | `BoxModelTests.rowMarginsMatchWebKit` | margins outside each box, with space-between: a (20,5) b (158,2) c (336,12) | R | `GoldenReplacementFlexTests` 1.6 `marginsOffsetEachItemOutsideItsBorderBox` |
| 39 | `flex_row_padding_border` | `FlexEngineTests.rowPaddingAndBorderMatchesWebKit` | asymmetric padding + border inset the content box; the grower takes the rest (256) | R | `GoldenReplacementFlexTests` 1.5 `paddingAndBorderInsetTheContentBoxEdgeByEdge` |
| 40 | `flex_row_percent_basis` | `FreezeLoopTests.percentageFlexBasisResolvesAgainstTheMainAxis` | a percentage basis resolves against the main size: 350/175/120 | D | **percentages** — reported by name (`box.flexBasis`) (`percentagesStillReportByNameWithTheirOwner`), owned by stage 8's recipe (`LR-AI`); no SwiftUI claim made |
| 41 | `flex_row_reverse` | `FlexEngineTests.rowReverseMatchesWebKit` | row-reverse packs from the main end: x 360/290/240 | R | `GoldenReplacementFlexTests` 1.4 `aReverseDirectionPacksItemsFromTheMainEnd` |
| 42 | `flex_row_reverse_margins` | `BoxModelTests.rowReverseMarginsMatchWebKit` | row-reverse mirrors which margin leads: 320/246/168 | R | `GoldenReplacementFlexTests` 1.6 `marginsOffsetEachItemOutsideItsBorderBox` |
| 43 | `flex_row_reverse_stretch` | `BoxModelTests.rowReverseStretchMatchesWebKit` | row-reverse with stretch, align-self flex-end and a capped stretch | R | `GoldenReplacementFlexTests` 1.6 `marginsOffsetEachItemOutsideItsBorderBox` |
| 44 | `flex_row_seven_equal` | `FlexEngineTests.sevenEqualChildrenMatchWebKit` | seven equal growers in 100 round to 14/15/14/14/14/15/14 and close the row | R | `GoldenReplacementFlexTests` 1.7 `equalGrowersShareTheLineAndAMaximumCapsItsGrower` |
| 45 | `flex_row_shrink` | `FreezeLoopTests.shrinkMatchesWebKit` | base-weighted shrink: 133/67 beside a rigid 100 | D | **length `flex-basis` and weighted shrink** (flex §9.7.4.c) — `box.flexBasis` reported (`aZeroBasisGrowerTakesItsShareDownToItsContent`, the 40px arm); positive shrink lowers as compression whatever its weight (`aPositiveShrinkLowersAsSwiftUIsCompressionWhateverItsWeight`, divergence 55); a fixed frame is not shrunk (7a probe S1 vs S0); the field is stage 8/10's to respell or delete (`LR-AO`, `LR-DY`) |
| 46 | `flex_row_shrink_padded_weighting` | `FreezeLoopTests.paddedShrinkWeightingMatchesWebKit` | the shrink weight is the inner base size: 125/75 | D | **weighted shrink** — native keeps both declared 200s and overflows, pinned by `GoldenReplacementStackTests` 2.7 `aDeclaredMainSizeIsNeitherShrunkNorFlooredByContentOrPadding` and `theDemosBodyRowKeepsTheSidebarAtItsDeclaredWidthWhereCSSShrinksIt`; 7a probe S1 vs S0 |
| 47 | `flex_row_shrink_to_zero` | `FreezeLoopTests.aShrinkTargetBelowZeroClampsToZeroInsteadOfStoringANegativeWidth` | a shrink target below zero clamps to 0: 0/50 | D | **length `flex-basis` and weighted shrink** (flex §9.7.4.c) — `box.flexBasis` reported (`aZeroBasisGrowerTakesItsShareDownToItsContent`, the 40px arm); positive shrink lowers as compression whatever its weight (`aPositiveShrinkLowersAsSwiftUIsCompressionWhateverItsWeight`, divergence 55); a fixed frame is not shrunk (7a probe S1 vs S0); the field is stage 8/10's to respell or delete (`LR-AO`, `LR-DY`) |
| 48 | `flex_row_stretch_min_height_margins` | `BoxModelTests.rowStretchWithMinHeightAndMarginsMatchesWebKit` | a minimum floors a stretched height past the line minus margins (70, 75) | R | `GoldenReplacementFlexTests` 1.6 `marginsOffsetEachItemOutsideItsBorderBox` |
| 49 | `flex_row_stretch_mixed` | `FlexEngineTests.rowStretchMixedMatchesWebKit` | stretch fills an auto cross axis (100), a declared one stays (30), align-self flex-start hugs (0), a max caps the stretch (60) | R | `GoldenReplacementFlexTests` 1.3 `alignItemsAndAlignSelfPlaceEachItemOnTheCrossAxis` |
| 50 | `flex_row_stretch_with_margins` | `BoxModelTests.rowStretchWithMarginsMatchesWebKit` | a stretched height is the line minus the cross margins (65), capped by a max (50) | R | `GoldenReplacementFlexTests` 1.6 `marginsOffsetEachItemOutsideItsBorderBox` |
| 51 | `flex_row_three_fixed` | `FlexEngineTests.rowOfFixedChildrenMatchesWebKit` | fixed items pack at their own sizes from x 0: 0/60/150; heights their own | R | `GoldenReplacementFlexTests` 1.1 `fixedItemsPackFromTheMainStartAtTheirOwnSizesAndGap` |
| 52 | `flex_wrap_align_content_around_evenly` | `WrappingTests.wrapAlignContentAroundAndEvenlyMatchWebKit` | align-content space-around/space-evenly | D | **wrap** (`flex-wrap`/`align-content`) — `box.flexWrap` reported by name (`everyContainerFieldEitherLowersAndAgreesOrIsReportedByName`, "wrap" arm); SwiftUI stacks lay out one line (7a probe W1, W2 vs W0) |
| 53 | `flex_wrap_align_content_between` | `WrappingTests.wrapAlignContentBetweenMatchesWebKit` | align-content space-between | D | **wrap** (`flex-wrap`/`align-content`) — `box.flexWrap` reported by name (`everyContainerFieldEitherLowersAndAgreesOrIsReportedByName`, "wrap" arm); SwiftUI stacks lay out one line (7a probe W1, W2 vs W0) |
| 54 | `flex_wrap_align_content_center` | `WrappingTests.wrapAlignContentCenterOnAColumnMatchesWebKit` | align-content center on a wrapping column | D | **wrap** (`flex-wrap`/`align-content`) — `box.flexWrap` reported by name (`everyContainerFieldEitherLowersAndAgreesOrIsReportedByName`, "wrap" arm); SwiftUI stacks lay out one line (7a probe W1, W2 vs W0) |
| 55 | `flex_wrap_align_content_stretch` | `WrappingTests.wrapAlignContentStretchMatchesWebKit` | align-content stretch grows the lines | D | **wrap** (`flex-wrap`/`align-content`) — `box.flexWrap` reported by name (`everyContainerFieldEitherLowersAndAgreesOrIsReportedByName`, "wrap" arm); SwiftUI stacks lay out one line (7a probe W1, W2 vs W0) |
| 56 | `flex_wrap_align_items_self` | `WrappingTests.wrapAlignItemsMeasuresTheLineMatchesWebKit` | align-items/align-self within each line | D | **wrap** (`flex-wrap`/`align-content`) — `box.flexWrap` reported by name (`everyContainerFieldEitherLowersAndAgreesOrIsReportedByName`, "wrap" arm); SwiftUI stacks lay out one line (7a probe W1, W2 vs W0) |
| 57 | `flex_wrap_column_reverse` | `WrappingTests.wrapColumnReverseMatchesWebKit` | column-reverse wrapping | D | **wrap** (`flex-wrap`/`align-content`) — `box.flexWrap` reported by name (`everyContainerFieldEitherLowersAndAgreesOrIsReportedByName`, "wrap" arm); SwiftUI stacks lay out one line (7a probe W1, W2 vs W0) |
| 58 | `flex_wrap_grow_and_shrink` | `WrappingTests.wrapGrowAndShrinkMatchesWebKit` | grow and shrink per line | D | **wrap** (`flex-wrap`/`align-content`) — `box.flexWrap` reported by name (`everyContainerFieldEitherLowersAndAgreesOrIsReportedByName`, "wrap" arm); SwiftUI stacks lay out one line (7a probe W1, W2 vs W0) |
| 59 | `flex_wrap_justify_between` | `WrappingTests.wrapJustifyContentIsPerLineMatchesWebKit` | justify-content per line | D | **wrap** (`flex-wrap`/`align-content`) — `box.flexWrap` reported by name (`everyContainerFieldEitherLowersAndAgreesOrIsReportedByName`, "wrap" arm); SwiftUI stacks lay out one line (7a probe W1, W2 vs W0) |
| 60 | `flex_wrap_main_sizing` | `WrappingTests.wrapMainSizingUsesResolvedAndClampedSizesMatchesWebKit` | line breaking by resolved, clamped (and percentage) sizes | D | **wrap** (`flex-wrap`/`align-content`) — `box.flexWrap` reported by name (`everyContainerFieldEitherLowersAndAgreesOrIsReportedByName`, "wrap" arm); SwiftUI stacks lay out one line (7a probe W1, W2 vs W0); its percentage widths are **percentages** too |
| 61 | `flex_wrap_min_vs_max_content` | `ContentSizingFixtureTests.wrapMinVersusMaxContentMatchesWebKit` | a capped wrapping item: min- vs max-content (100 wide, two lines) | D | **wrap** (`flex-wrap`/`align-content`) — `box.flexWrap` reported by name (`everyContainerFieldEitherLowersAndAgreesOrIsReportedByName`, "wrap" arm); SwiftUI stacks lay out one line (7a probe W1, W2 vs W0); its cap also reports `box.maxSize` |
| 62 | `flex_wrap_nested_percent_padding` | `WrappingTests.wrapNestedPercentPaddingMatchesWebKit` | a wrapping container with percentage padding inside another | D | **wrap** (`flex-wrap`/`align-content`) — `box.flexWrap` reported by name (`everyContainerFieldEitherLowersAndAgreesOrIsReportedByName`, "wrap" arm); SwiftUI stacks lay out one line (7a probe W1, W2 vs W0); its padding is **percentages** too |
| 63 | `flex_wrap_reverse` | `WrappingTests.wrapReverseAlignItemsMatchesWebKit` | wrap-reverse with align-self | D | **wrap** (`flex-wrap`/`align-content`) — `box.flexWrap` reported by name (`everyContainerFieldEitherLowersAndAgreesOrIsReportedByName`, "wrap" arm); SwiftUI stacks lay out one line (7a probe W1, W2 vs W0); the value `wrap-reverse` itself is pinned by `GoldenReplacementStackTests` 2.8 `aWrapReverseContainerIsReportedByNameAsAWrappingOneIs` (the \"wrap\" arm declares `.wrap` only, `LR-DY`) |
| 64 | `flex_wrap_reverse_align_content_end` | `WrappingTests.wrapReverseAlignContentEndMatchesWebKit` | wrap-reverse with align-content flex-end | D | **wrap** (`flex-wrap`/`align-content`) — `box.flexWrap` reported by name (`everyContainerFieldEitherLowersAndAgreesOrIsReportedByName`, "wrap" arm); SwiftUI stacks lay out one line (7a probe W1, W2 vs W0); the value `wrap-reverse` itself is pinned by `GoldenReplacementStackTests` 2.8 `aWrapReverseContainerIsReportedByNameAsAWrappingOneIs` (the \"wrap\" arm declares `.wrap` only, `LR-DY`) |
| 65 | `flex_wrap_reverse_row_reverse` | `WrappingTests.rowReverseWithWrapReverseMatchesWebKit` | wrap-reverse with row-reverse | D | **wrap** (`flex-wrap`/`align-content`) — `box.flexWrap` reported by name (`everyContainerFieldEitherLowersAndAgreesOrIsReportedByName`, "wrap" arm); SwiftUI stacks lay out one line (7a probe W1, W2 vs W0); the value `wrap-reverse` itself is pinned by `GoldenReplacementStackTests` 2.8 `aWrapReverseContainerIsReportedByNameAsAWrappingOneIs` (the \"wrap\" arm declares `.wrap` only, `LR-DY`) |
| 66 | `flex_wrap_row_reverse_gap_margin` | `WrappingTests.wrapRowReverseWithGapAndMarginsMatchesWebKit` | row-reverse wrapping with gaps and margins | D | **wrap** (`flex-wrap`/`align-content`) — `box.flexWrap` reported by name (`everyContainerFieldEitherLowersAndAgreesOrIsReportedByName`, "wrap" arm); SwiftUI stacks lay out one line (7a probe W1, W2 vs W0) |
| 67 | `flex_wrap_stretch_auto_cross` | `WrappingTests.wrapStretchAutoCrossMatchesWebKit` | stretch to each line's cross size | D | **wrap** (`flex-wrap`/`align-content`) — `box.flexWrap` reported by name (`everyContainerFieldEitherLowersAndAgreesOrIsReportedByName`, "wrap" arm); SwiftUI stacks lay out one line (7a probe W1, W2 vs W0) |
| 68 | `flex_wrap_uneven` | `WrappingTests.wrapUnevenMatchesWebKit` | line breaking with gaps | D | **wrap** (`flex-wrap`/`align-content`) — `box.flexWrap` reported by name (`everyContainerFieldEitherLowersAndAgreesOrIsReportedByName`, "wrap" arm); SwiftUI stacks lay out one line (7a probe W1, W2 vs W0) |
| 69 | `flex_wrap_with_margins_and_padding` | `WrappingTests.wrapWithMarginsAndPaddingMatchesWebKit` | line breaking by margin boxes inside padding + border | D | **wrap** (`flex-wrap`/`align-content`) — `box.flexWrap` reported by name (`everyContainerFieldEitherLowersAndAgreesOrIsReportedByName`, "wrap" arm); SwiftUI stacks lay out one line (7a probe W1, W2 vs W0) |
| 70 | `stack_alignment_bottomtrailing` | `StackFixtureTests.stackAlignmentBottomTrailingMatchesWebKit` | bottom-trailing: (280, 190) | R | `GoldenReplacementStackTests` 2.1 `aStackPlacesAFixedChildAtItsAlignment` |
| 71 | `stack_alignment_center` | `StackFixtureTests.stackAlignmentCenterMatchesWebKit` | a fixed child centred in a 300x200 stack: (140, 95) | R | `GoldenReplacementStackTests` 2.1 `aStackPlacesAFixedChildAtItsAlignment`; corroborated by `aLoweredStackPlacesFixedChildrenAtAllNineAlignmentsAsTheLegacyStackDoes` |
| 72 | `stack_alignment_topleading` | `StackFixtureTests.stackAlignmentTopLeadingMatchesWebKit` | top-leading: (0, 0) | R | `GoldenReplacementStackTests` 2.1 `aStackPlacesAFixedChildAtItsAlignment` |
| 73 | `stack_fit_content_floor` | `StackFixtureTests.stackFitContentFloorMatchesWebKit` | fit-content is floored by min-content: 50 in a 30 stack | D | **wrap**, as content (a wrapping box's min-/max-content widths, TX-H fit-content) (`flex-wrap`/`align-content`) — `box.flexWrap` reported by name (`everyContainerFieldEitherLowersAndAgreesOrIsReportedByName`, "wrap" arm); SwiftUI stacks lay out one line (7a probe W1, W2 vs W0) |
| 74 | `stack_fit_content_inline` | `StackFixtureTests.stackFitContentInlineMatchesWebKit` | a stack child's auto width is fit-content (wrapping content) | D | **wrap**, as content (a wrapping box's min-/max-content widths, TX-H fit-content) (`flex-wrap`/`align-content`) — `box.flexWrap` reported by name (`everyContainerFieldEitherLowersAndAgreesOrIsReportedByName`, "wrap" arm); SwiftUI stacks lay out one line (7a probe W1, W2 vs W0) |
| 75 | `stack_fit_content_min_content_contribution` | `StackFixtureTests.stackMinContentContributionMatchesWebKit` | a stack's min-content contribution through a wrapping child | D | **wrap**, as content (a wrapping box's min-/max-content widths, TX-H fit-content) (`flex-wrap`/`align-content`) — `box.flexWrap` reported by name (`everyContainerFieldEitherLowersAndAgreesOrIsReportedByName`, "wrap" arm); SwiftUI stacks lay out one line (7a probe W1, W2 vs W0) |
| 76 | `stack_in_flex` | `StackFixtureTests.stackInFlexMatchesWebKit` | a stack as a flex item: 90x70 at x 40, siblings before and after | R | `GoldenReplacementStackTests` 2.3 `aStackHugsItsLargestChildInsideARowAndAroundOne` |
| 77 | `stack_percent_child_with_content` | `StackFixtureTests.stackPercentChildWithContentMatchesWebKit` | a stack's percentage child contributes its content, then resolves: 80x30 / 40x30 | D | **percentages** — reported by name (`percentagesStillReportByNameWithTheirOwner`), owned by stage 8's recipe (`LR-AI`); no SwiftUI claim made |
| 78 | `stack_sizes_to_largest` | `StackFixtureTests.stackSizesToLargestChildMatchesWebKit` | an auto stack hugs the union of its children: 90x70, each centred | R | `GoldenReplacementStackTests` 2.3 `aStackHugsItsLargestChildInsideARowAndAroundOne` |
| 79 | `stack_stretch` | `StackFixtureTests.stackStretchMatchesWebKit` | an auto child stretches to the cell: 300x200 | R | `GoldenReplacementStackTests` 2.2 `aStretchedStackChildFillsOnlyItsAutoAxesWithinItsOwnBounds` |
| 80 | `stack_stretch_border_box_floor` | `StackFixtureTests.stackStretchBorderBoxFloorMatchesWebKit` | a stretched stack child is floored by padding + border (120x140), even past its max | D | **border-box floor** (`BM-4`: padding + border floor a declared or stretched size) — native 100x100 and 40x50, pinned by `GoldenReplacementStackTests` 2.6 `aStretchedStackChildIsNotFlooredByItsPaddingAndBorder`; 7a probe B1 vs B0 |
| 81 | `stack_stretch_declared_size` | `StackFixtureTests.stackStretchDeclaredSizeMatchesWebKit` | a declared child is not stretched: 20x10 at the start | R | `GoldenReplacementStackTests` 2.2 `aStretchedStackChildFillsOnlyItsAutoAxesWithinItsOwnBounds` |
| 82 | `stack_stretch_max` | `StackFixtureTests.stackStretchMaxMatchesWebKit` | a stretched child keeps its maximum: h 300x50, w 40x200, p (percent maxima) 60x20 | R (partial) + D | `GoldenReplacementStackTests` 2.2 `aStretchedStackChildFillsOnlyItsAutoAxesWithinItsOwnBounds` for h and w (the golden's tree minus p); p is **percentages**: `box.maxSize.percent` reported (`percentagesStillReportByNameWithTheirOwner`) |
| 83 | `stack_stretch_min` | `StackFixtureTests.stackStretchMinMatchesWebKit` | a stretched child keeps its minimum past the cell: 340x260 | R | `GoldenReplacementStackTests` 2.2 `aStretchedStackChildFillsOnlyItsAutoAxesWithinItsOwnBounds` |
| 84 | `sizing_column_content_suggestion` | `SizingFixtureTests.aColumnItemsContentSuggestionIsMeasuredAtItsUsedWidthMatchesWebKit` | a column item's content suggestion is measured at its used width | D | **wrap**, as content (a wrapping box's min-/max-content widths, TX-H fit-content) (`flex-wrap`/`align-content`) — `box.flexWrap` reported by name (`everyContainerFieldEitherLowersAndAgreesOrIsReportedByName`, "wrap" arm); SwiftUI stacks lay out one line (7a probe W1, W2 vs W0) |
| 85 | `sizing_cross_after_flex` | `SizingFixtureTests.crossSizeAfterFlexingMatchesWebKit` | a wrapping item's cross size is measured after flexing (40) | D | **wrap**, as content (a wrapping box's min-/max-content widths, TX-H fit-content) (`flex-wrap`/`align-content`) — `box.flexWrap` reported by name (`everyContainerFieldEitherLowersAndAgreesOrIsReportedByName`, "wrap" arm); SwiftUI stacks lay out one line (7a probe W1, W2 vs W0) |
| 86 | `sizing_max_below_floor_keeps_automatic_minimum` | `SizingFixtureTests.theClampedAutomaticMinimumIsStillFlooredByPaddingAndBorderMatchesWebKit` (**trimmed, not removed**: its `minZero` arm stays for 7b, `LR-DT`) | the clamped minimum is still floored by padding + border: p 80, c 120 | D | **automatic minimum** (flex §4.5 content/specified size suggestion) and **border-box floor** (`BM-4`: padding + border floor a declared or stretched size) — the non-greedy `box.maxSize` is reported (`theCentringDefaultOfRowAndColumnStretchesNothing`, last arm; `aMaximumLowersOnAGreedyOrSizedAxisAndIsReportedElsewhere`; row 86's citation corrected by `LR-DY`), the field owned by stage 8 (`LR-AO`) |
| 87 | `sizing_max_clamps_content_suggestion` | `SizingFixtureTests.aMaxMainSizeClampsTheContentSizeSuggestionMatchesWebKit` | a max-width clamps the content suggestion: a 50 | D | **automatic minimum** (flex §4.5 content/specified size suggestion) — the non-greedy `box.maxSize` is reported (`theCentringDefaultOfRowAndColumnStretchesNothing`, last arm; `aMaximumLowersOnAGreedyOrSizedAxisAndIsReportedElsewhere`), the field owned by stage 8 (`LR-AO`) |
| 88 | `sizing_over_constrained_grows` | `SizingFixtureTests.overConstrainedBoxGrowsLikeWebKit` | padding + border past a declared size grow the box: 120x140 | D | **border-box floor** (`BM-4`: padding + border floor a declared or stretched size) — native keeps 100x80, pinned by `GoldenReplacementStackTests` 2.7 `aDeclaredMainSizeIsNeitherShrunkNorFlooredByContentOrPadding` and `aDeclaredSizeBelowThePaddingKeepsTheFrameWhereCSSFloorsTheBox`; 7a probe B1 vs B0 |
| 89 | `sizing_percent_main_against_indefinite` | `SizingFixtureTests.percentageMainAgainstAnIndefiniteContainerMatchesWebKit` | a percentage main size against an indefinite container is auto | D | **percentages** — reported by name (`percentagesStillReportByNameWithTheirOwner`), owned by stage 8's recipe (`LR-AI`); no SwiftUI claim made; the zero basis beside it also reports `box.flexBasis` |
| 90 | `sizing_root_percent` | `SizingFixtureTests.rootPercentageMatchesWebKit` | a root percentage resolves against the viewport: 400x150 | D | **percentages** — reported by name (`percentagesStillReportByNameWithTheirOwner`), owned by stage 8's recipe (`LR-AI`); no SwiftUI claim made |
| 91 | `sizing_specified_suggestion` | `SizingFixtureTests.specifiedSizeSuggestionMatchesWebKit` | a declared width is the automatic minimum's specified suggestion: a 130, b shrinks to 20 | D | **automatic minimum** (flex §4.5 content/specified size suggestion) — native keeps both declared widths and overflows (130, 100), pinned by `GoldenReplacementStackTests` 2.7 `aDeclaredMainSizeIsNeitherShrunkNorFlooredByContentOrPadding`; 7a probe A1 vs A0 |
| 92 | `sizing_specified_suggestion_is_used_value` | `SizingFixtureTests.theSpecifiedSizeSuggestionIsTheUsedSizeMatchesWebKit` | the specified suggestion is the floored used size: a 120, b 30 | D | **border-box floor** (`BM-4`: padding + border floor a declared or stretched size) and **automatic minimum** (flex §4.5 content/specified size suggestion) — native a 100, b 100, pinned by `GoldenReplacementStackTests` 2.7 `aDeclaredMainSizeIsNeitherShrunkNorFlooredByContentOrPadding` |
| 93 | `abs_containing_block_skips_static` | `AbsoluteFixtureTests.absContainingBlockSkipsStaticMatchesWebKit` | an absolute box skips its static ancestors to the containing block's padding box: (0, 0) | R | `GoldenReplacementStackTests` 2.4 `aDeferredAbsoluteBoxResolvesItsInsetsAgainstTheWindowAndLeavesTheFlow` (the window stands for the `relative` root; a non-window containing block is reported, `aPresentationWhoseContainingBlockIsNotTheWindowIsReportedByName`) |
| 94 | `abs_over_constrained` | `AbsoluteFixtureTests.absOverConstrainedMatchesWebKit` | left + right + width: right dropped; top + bottom stretch the height: (40, 10) 50x70 | R | `GoldenReplacementStackTests` 2.4 `aDeferredAbsoluteBoxResolvesItsInsetsAgainstTheWindowAndLeavesTheFlow` |
| 95 | `abs_percent_insets_nonsquare` | `AbsoluteFixtureTests.absPercentInsetsNonsquareMatchesWebKit` | percentage insets resolve per axis: top 10% of 100, left 10% of 200 → (20, 10) | R | `GoldenReplacementStackTests` 2.4 `aDeferredAbsoluteBoxResolvesItsInsetsAgainstTheWindowAndLeavesTheFlow`; corroborated by `aDeferredAbsoluteBoxLowersAgainstTheWindowOnEveryInsetShape` (percent arm) |
| 96 | `abs_removed_from_flow` | `AbsoluteFixtureTests.absRemovedFromFlowMatchesWebKit` | an absolute box leaves the flow: its container stays 40x20 | R | `GoldenReplacementStackTests` 2.4 `aDeferredAbsoluteBoxResolvesItsInsetsAgainstTheWindowAndLeavesTheFlow` |
| 97 | `abs_single_inset_auto_size` | `AbsoluteFixtureTests.absSingleInsetAutoSizeMatchesWebKit` | one inset per axis with an auto size takes its content: 35x15 at (20, 10) | R | `GoldenReplacementStackTests` 2.4 `aDeferredAbsoluteBoxResolvesItsInsetsAgainstTheWindowAndLeavesTheFlow` |


**Tally.** R 44 (flex 29, stack 10 including `stack_stretch_max` partial,
abs 5); D 53 — wrap 30 (18 `flex_wrap_*` + 12 whose wrapping box is content),
percentages 7, length basis / weighted shrink 6, unequal weights 2, sub-one grow
2, automatic minimum 3, border-box floor 3.

## 5. Literals the lanes transcribe

### 5.1 The 44 R arms — each golden's `rounded` boxes (x,y,w×h)

Read from `Golden/*.json` at `2cc763d` before any file is deleted; the lane
asserts every listed box by its `data-id`, which the arm's tree names with
`.id(_:)`.

| golden | render (window) | boxes |
|---|---|---|
| `flex_row_three_fixed` | 800×600 | root:0,0,300x50 x:0,0,60x20 y:60,0,90x30 z:150,0,40x50 |
| `flex_column_three_fixed` | 800×600 | root:0,0,120x400 x:0,0,60x20 y:0,20,90x30 z:0,50,40x50 |
| `flex_row_gap` | 800×600 | root:0,0,300x50 x:0,0,60x20 y:72,0,90x30 z:174,0,40x50 |
| `flex_row_justify_between` | 800×600 | root:0,0,400x40 a:0,0,40x40 b:160,0,70x40 c:350,0,50x40 |
| `flex_row_justify_around` | 800×600 | root:0,0,400x40 a:40,0,40x40 b:160,0,70x40 c:310,0,50x40 |
| `flex_row_justify_evenly` | 800×600 | root:0,0,400x40 a:60,0,40x40 b:160,0,70x40 c:290,0,50x40 |
| `flex_row_justify_between_gap` | 800×600 | root:0,0,400x40 a:0,0,40x40 b:160,0,70x40 c:350,0,50x40 |
| `flex_column_justify_center` | 800×600 | root:0,0,60x400 a:0,120,60x40 b:0,160,60x70 c:0,230,60x50 |
| `flex_row_align_center` | 800×600 | root:0,0,400x100 a:0,40,40x20 b:40,20,70x60 c:110,30,50x40 |
| `flex_row_align_end_with_self` | 800×600 | root:0,0,400x100 a:0,80,40x20 b:40,20,70x60 c:110,60,50x40 |
| `flex_row_stretch_mixed` | 800×600 | root:0,0,400x100 a:0,0,60x100 b:60,0,70x30 c:130,0,50x0 d:180,0,80x60 |
| `flex_row_reverse` | 800×600 | root:0,0,400x40 a:360,0,40x40 b:290,0,70x40 c:240,0,50x40 |
| `flex_column_reverse_justify_end` | 800×600 | root:0,0,100x400 a:0,120,100x40 b:0,50,60x70 c:0,0,80x50 |
| `flex_row_padding_border` | 800×600 | root:0,0,400x100 a:23,25,50x30 b:73,25,60x30 c:133,25,256x30 |
| `flex_column_padding_asymmetric` | 800×600 | root:0,0,120x400 a:24,16,64x40 b:24,56,64x90 c:24,146,64x60 |
| `flex_nested_padding` | 800×600 | root:0,0,400x200 mid:15,15,200x80 g1:38,38,20x10 g2:58,38,134x10 sib:215,15,40x60 |
| `flex_row_margins` | 800×600 | root:0,0,400x100 a:20,5,40x30 b:158,2,50x40 c:336,12,60x20 |
| `flex_row_margin_with_grow` | 800×600 | root:0,0,400x60 a:9,4,274x40 b:318,10,80x40 |
| `flex_row_reverse_margins` | 800×600 | root:0,0,400x100 a:320,5,50x30 b:246,2,60x40 c:168,12,40x20 |
| `flex_column_reverse_margins` | 800×600 | root:0,0,100x400 a:5,320,30x50 b:2,246,40x60 c:12,168,20x40 |
| `flex_row_stretch_with_margins` | 800×600 | root:0,0,400x100 a:0,10,50x65 b:50,15,70x50 |
| `flex_row_grow_space_between_margins` | 800×600 | root:0,0,400x100 a:9,4,150x40 b:210,2,60x40 c:346,12,50x40 |
| `flex_row_stretch_min_height_margins` | 800×600 | root:0,0,400x100 a:0,20,50x70 b:50,10,60x75 |
| `flex_row_reverse_stretch` | 800×600 | root:0,0,400x100 a:350,0,50x100 b:290,70,60x30 c:220,0,70x40 |
| `flex_row_seven_equal` | 400×200 | root:0,0,100x20 c0:0,0,14x20 c1:14,0,15x20 c2:29,0,14x20 c3:43,0,14x20 c4:57,0,14x20 c5:71,0,15x20 c6:86,0,14x20 |
| `flex_row_grow_with_max` | 800×600 | root:0,0,400x40 a:0,0,50x40 b:50,0,175x40 c:225,0,175x40 |
| `flex_column_grow_with_max` | 800×600 | root:0,0,100x400 a:0,0,100x50 b:0,50,100x175 c:0,225,100x175 |
| `flex_auto_height_two_levels` | 800×600 | root:0,0,300x220 outer:0,0,240x48 inner:0,0,180x48 g1:0,0,60x24 g2:0,24,60x24 after:0,48,100x30 |
| `flex_item_floored_by_content` | 800×600 | root:0,0,100x60 squeezed:0,0,80x60 g1:0,0,80x20 other:80,0,20x60 |
| `stack_alignment_center` | 800×600 | root:0,0,300x200 child:140,95,20x10 |
| `stack_alignment_topleading` | 800×600 | root:0,0,300x200 child:0,0,20x10 |
| `stack_alignment_bottomtrailing` | 800×600 | root:0,0,300x200 child:280,190,20x10 |
| `stack_stretch` | 800×600 | root:0,0,300x200 child:0,0,300x200 |
| `stack_stretch_declared_size` | 800×600 | root:0,0,300x200 child:0,0,20x10 |
| `stack_stretch_min` | 800×600 | root:0,0,300x200 m:0,0,340x260 |
| `stack_stretch_max` | 800×600 | root:0,0,300x200 h:0,0,300x50 w:0,0,40x200   (p omitted: percentages) |
| `stack_sizes_to_largest` | 800×600 | root:0,0,400x300 stack:0,0,90x70 mid:20,15,50x40 wide:0,30,90x10 tall:35,0,20x70 |
| `stack_in_flex` | 800×600 | root:0,0,400x150 before:0,0,40x30 stack:40,0,90x70 mid:60,15,50x40 wide:40,30,90x10 tall:75,0,20x70 after:130,0,60x20 |
| `flex_in_stack` | 800×600 | root:0,0,300x200 backdrop:50,40,200x120 row:105,88,90x25 item0:105,88,30x25 item1:135,88,30x25 item2:165,88,30x25 |
| `abs_containing_block_skips_static` | 200×100 (window = root) | root:0,0,200x100 abs:0,0,20x10 |
| `abs_percent_insets_nonsquare` | 200×100 (window = root) | root:0,0,200x100 abs:20,10,20x10 |
| `abs_removed_from_flow` | 800×600 | root:0,0,400x300 container:0,0,40x20 inflow:0,0,40x20 abs:0,0,500x300 |
| `abs_over_constrained` | 200×100 (window = root) | root:0,0,200x100 abs:40,10,50x70 |
| `abs_single_inset_auto_size` | 200×100 (window = root) | root:0,0,200x100 abs:20,10,35x15 content:20,10,35x15 |

### 5.2 The D pins — native answers measured in §2

| test | arm (golden's tree) | render | boxes |
|---|---|---|---|
| 2.5 | `flex_row_fractional_grow` | 800×600 | root 0,0,400×40 a 0,0,133×40 b 133,0,134×40 c 267,0,133×40 |
| 2.5 | `flex_row_fractional_grow_clamped` | 800×600 | root 0,0,400×40 a 0,0,50×40 b 50,0,350×40 |
| 2.6 | `stack_stretch_border_box_floor` | 800×600 | root 0,0,100×100 f 0,0,100×100 c 0,0,40×50 |
| 2.7 | `flex_row_shrink_padded_weighting` | 800×600 | root 0,0,200×40 a 0,0,200×40 b 200,0,200×40 |
| 2.7 | `sizing_specified_suggestion` | 800×600 | root 0,0,150×60 a 0,0,130×60 g1 0,0,200×20 b 130,0,100×20 |
| 2.7 | `sizing_specified_suggestion_is_used_value` | 800×600 | root 0,0,150×60 a 0,0,100×60 g1 60,10,200×20 b 100,0,100×20 |
| 2.7 | `sizing_over_constrained_grows` | 800×600 | root 0,0,400×300 box 0,0,100×80 kid 60,70,10×10 |
| 2.8 | `flex_wrap_reverse`, `_align_content_end`, `_row_reverse` (`LR-DY`) | 800×600 | no boxes: `unlowerableFields` = `[box.flexWrap]`, `[box.flexWrap, box.alignContent]`, `[box.flexWrap]` (spec §6; read off `legacyContainerDiagnostics`, `LegacyLowering.swift:209`–210 — the lane measures it before committing) |

### 5.3 The count

| | tests |
|---|---|
| before (`2cc763d`) | 1704 |
| removed: golden consumers, whole (`LR-DT`) | − 96 |
| removed: `GeneratorTests` | − 5 |
| removed: `OracleTests` | − 3 |
| trimmed, not removed: `theClampedAutomaticMinimumIsStillFlooredByPaddingAndBorderMatchesWebKit` | 0 |
| added: lane 1 (1.1–1.8) | + 8 |
| added: lane 2 (2.1–2.8; 2.8 from critic round 1, `LR-DY`) | + 8 |
| **after** | **1616** |

The gated tests fall from five to four (`regenerateAllGoldens` goes with
`GeneratorTests`). Goldens 97 → **0**. Guards 78, unchanged.

## 6. Lanes

(appended by the lanes)
