# §49 — Engine replacement, stage 7b: the non-golden CSS-engine tests retired

Plan task 7, stage 7b (parent design
`docs/superpowers/specs/2026-09-17-engine-replacement-design.md` §4.1 row 7b,
`LR-U`, §8). Design: `docs/superpowers/specs/2026-09-23-engine-stage-7b-design.md`.
Rulings `LR-EC`…`LR-EK` (critic round 1: `LR-EL`) in
`docs/superpowers/2026-09-17-engine-replacement-decisions.md`. Branch
`feat/engine-stage-7b` from `41344e5`, worktree
`/Users/maxburger/Developer/worktrees/MetalUI/stage-7b`. Instrument:
`docs/probes/stage-7b-css-engine-instrument.patch`; its census:
`docs/probes/stage-7b-css-engine-census.txt`. No new SwiftUI probe (`LR-EI`).

**Numbering hazard.** Written as §49, the next free number at `41344e5`
(§48 is stage 7a). If another line reaches `master` first with a §49, this file
is renumbered at merge by the precedent of record §23 §8 and the
§25/§27/§29/§38/§41/§48 headers.

**Status, 2026-09-24 (PDT): delivered.** §6.1–§6.3 are the three lanes and §7
the stage's close (1445 tests; the census reads section A exactly; 0 px). The
design-time status below is kept as written.

**Status, 2026-09-24 (PDT): design.** §1–§5 were written with no file under
`Sources/`, `Tests/` or `Package.swift` changed in a commit: the instrument was
applied to the working tree, built, run once unfiltered, captured as the patch
above and reverted (`git status --short` showed only the two new
`docs/probes/` files afterwards). The lanes append §6 onward.

## 1. Baseline at `41344e5`

`swift build --build-system native --build-tests` → `Build complete!`, 0
`error:`, the one `warning:` SwiftPM's deprecation notice; unfiltered `swift
test --build-system native --no-parallel` → **`Test run with 1670 tests in 3
suites passed after 90.277 seconds`**, the log carrying `FR-J no-argument
frame: succeeded=true` (the guards ran). 0 goldens, 78 guards.

**What is left of spec §2.6's 24 files.** Stage 7a removed six whole
(`StackFixtureTests`, `FitContentFixtureTests`, `AbsoluteFixtureTests`,
`GeneratorTests`, `ContentSizingFixtureTests`, `OracleTests`) and every golden
consumer from the rest. The eighteen still present hold **191** `@Test`s,
counted by a scanner that pairs each `@Test` attribute (not a comment) with the
next `func` (a plain `grep -c '@Test'` miscounts `@Test @MainActor func` and
`@Test(.enabled(if: …)` on two lines):

| file | tests | `computeLayout(` sites |
|---|---|---|
| `BoxModelTests` | 26 | 26 |
| `StackLayoutTests` | 22 | 11 |
| `FreezeLoopTests` | 20 | 20 |
| `FlexEngineTests` | 19 | 18 |
| `WrappingTests` | 18 | 9 |
| `AbsolutePositioningTests` | 17 | 15 |
| `AlignmentTests` | 15 | 7 |
| `LayoutContextTests` | 10 | 7 |
| `MeasureNodeTests` | 10 | 0 |
| `FlexBaseSizeTests` | 8 | 0 |
| `MeasureCacheTests` | 6 | 0 |
| `ResolveTests` | 6 | 0 |
| `IntrinsicModeTests` | 4 | 0 |
| `StyleTests` | 4 | 0 |
| `FreezeLoopAllocationTests` | 2 | 0 |
| `LeafProbeShortcutTests` | 2 | 2 |
| `SizingFixtureTests` | 1 | 1 (7a's trimmed `minZero` arm, `LR-DT`) |
| `ScrollLayoutTests` | 1 | 1 |
| **total** | **191** | **117** |

**`grep -rn "computeLayout(" Tests`** (swift files, `.build` excluded) reads
**121** lines: the 117 above, `NativeBoundaryTrapTests` 3
(`computeLayoutRejectsANativeRoot`,
`computeLayoutCalledFromANativeMeasureClosureTraps`,
`registeringANodeDuringLegacyLayoutTraps`) and `ElementLayoutTests` 1
(`aNestedLayoutMatchesTheEngineRunDirectly`). No doc comment in a kept file
spells `computeLayout(`.

**The `.legacy` pins with a 7b owner: 50 tests.** Read off every doc line
`Pinned to the legacy authority by stage 6a (<class>…)` / `P-CSS, owner 7b` in
`Tests/MetalUITests`, and reconciled against records §38 and §41:

- **33 from stage 6a** (record §38 §10.1, §10.7): lane 3's 30 —
  `ComponentTests` 13 (8 CSS-structure, 5 CSS-d48), `FrameSizingTests` 11 (10
  CSS-frame and `LR-DE`'s test 2.10), `ElementLayoutTests` 3 (1
  CSS-structure, 2 CSS-box), `ModifiedElementTests` 2 and
  `ModifierCompositionProofTests` 1 (CSS-structure) — and lane 2's 3 CSS-pin
  rows in `ContainerIntegrationTests`.
- **15 from stage 6b** (`LR-DQ` item 2: §5.4's 16 less the 3 N9 rows, plus
  item 2's two): `AnimationTests.everyRegisteringSiteAnimatesItsStyle`,
  `EnvironmentTests` 2, `StackElementTests` 3, `TextMeasureTests` 4,
  `FrameDecorationInteractionTests` 2, `OuterModifierMatrixTests` 1,
  `ElementLayoutTests.alignItemsAndAlignSelfBothReachTheEngine`,
  `FrameSizingTests.hiddenAfterASingleChildLegacyFrameStillHidesTheElement`.
- **2 kept pinned by stage 6b from 6a's CE+RP rows**, each doc-marked `P-CSS,
  owner 7b` (`LR-DI`): `ElementLayoutTests.aNestedLayoutMatchesTheEngineRunDirectly`
  and `ElementLayoutTests.aHiddenChildTakesNoSpace`.

Record §38 §4's 43 CSS reds are all among these 50 (CSS-structure 14,
CSS-style 7, CSS-text 3, CSS-frame 10, CSS-d48 5, CSS-pin 2, CSS-box 2); the
other 7 are `aLegacyRowAndColumnDefault…` (6a lane 2), test 2.10 (`LR-DE`),
`aContentShapeOnAFrameLayer…` (RP+CSS-frame), `LR-DQ` item 2's two and
`LR-DI`'s two. Stage 6b's other five pins (the 3 N9 rows, the 2 tokenizer
tests) are stage 9's and are not touched.

## 2. The entry measurement: who reaches the CSS engine at `41344e5`

**Method.** `docs/probes/stage-7b-css-engine-instrument.patch` adds one line
to `computeLayout` — `print("SEVENB-CSS-ENGINE")`, after the `SA-G` check — so
every test that runs the CSS engine in-process prints a marker between its
`started.` line and the next test's (`--no-parallel` serializes; the stream
was checked by eye to interleave as expected). Applied, built, one unfiltered
run (`Test run with 1670 tests in 3 suites passed`, 3 294 markers), reverted.
Attribution: the last `started.` line before a marker — a plain test, or
`Test case passing … to NAME(…) started.` for a parameterised one. **Exit-test
child processes print to their own streams and are not seen** (the 12 X, the
N9 traps and 3.1's trap halves).

**Result: 357 tests reach `computeLayout`** (the census file lists them):

- **111** in §2.6's eighteen files (the other 80 call `measureNode`,
  `LayoutContext`, `collectLines`, `resolveLength` or `Style` directly, or
  reach `computeLayout` only inside an exit test's child process);
- **47** in the retirement set's element files: 46 of the 50 7b-owned pins
  (the other four — `everyRegisteringSiteAnimatesItsStyle` and the three
  `StackElementTests` — register a `Style` on a `.legacy` `Frame` without
  laying it out) and `RootSwitchTests.aHuggingLegacyRootIsCentredInAProductionWindow`,
  whose `.legacy` arm is divergence 4's last pin (a T row);
- **199** elsewhere — **stage 9's, not 7b's** (`LR-EC`): every
  `AuthorityCoverage`-parameterised scenario's `.legacy` arm (`ListTests` 21,
  `ScrollRoutingTests` 16, `ScrollIndicatorTests` 14, `PresentationWindowTests`
  6, `AccessibilityDefaultsTests` 6, `DeferredTests` 5, `AccessibilityTreeTests`
  5, `ScrollViewTests` 4, `AXNodeTests` 3, …), every differential lowering test
  (`LoweringItemTests` 27, `LoweringStackAndLayerTests` 11,
  `LoweringDistributionTests` 9, `LoweringComponentTests` 9,
  `LoweringContainerTests` 7, `LoweringBoxModelTests` 7, `LoweringLeafTests` 6,
  `LoweringScrollTests` 6, `PresentationLoweringTests` 4, `ListLoweringTests`
  3, `LoweringCorpusTests` 3, `LoweringPipelineParityTests` 3,
  `HiddenLoweringTests` 2, `RootFieldLoweringTests` 1), the harness's own tests
  and 3.1's legacy half (`LayoutAuthorityTests` 5), the three loops over both
  authorities (`FrameSizingTests` 2, `ModifierCompositionProofTests` 1),
  `ProposalNodeIDTests`' N9 row, `noProductionFrameReachesTheLegacyEngine`'s
  control, and single rows in `AbsoluteOverlayTests`, `DecorationPaintTests`,
  `EnvironmentTests`, `FocusTests`, `TextFieldTests`, `TextSystemSeamTests`
  and `TombstoneTests`, and `MeasurePerformanceTests`' four (below).

**Correction, stage-7b critic round 1 (`LR-EL` finding 1).** The design
first read 115 / 195 and filed `MeasurePerformanceTests`' four markers
(`aListsWorkIsTheSameFor160RowsAsFor40`, `theResidentEntrySetStaysBoundedWhileScrolling10kRows`,
`aColdFrameCreatesAtMostOneLineBreakTokenizer`,
`aWarmFrameTokenizesEachDistinctStringAtMostOnce`) under section C, "§2.6's
files" — but that file is not one of §2.6's 24, and `LR-EC` item 3 keeps all
of its tests. Left there, exit criterion 3 (the census equals section A
exactly) could never pass. The critic re-read the census against the table
by script (every B/C name must be an R/D/N/T row; every A name must be in no
row): those four were the only exceptions. They move to A (199), C reads 111;
the total 357 is unchanged.

**What this says.** A retirement stage cannot empty the legacy authority's
reach: 199 tests use it as the other arm of a comparison (or, for
`MeasurePerformanceTests`' two tokenizer rows, as a `.legacy` pin stage 9
owns), and every one of
those dies or is re-spelled with the authority at stage 9. What 7b *can*
empty is the CSS engine's use **as a subject**: after 7b the same instrument
must read exactly the 199 of section A — no test of §2.6's files, no 7b pin
(exit criterion, spec §8).

**`MeasurePerformanceTests`** (named by `LR-U` for its 17 494 legacy nodes,
record §18) retires nothing, though four of its tests reach the CSS engine
(section A): its rows were re-spelled through the lowering
by stage 4 (`LR-BW`), its native work literal (`demoLikeRowsWarmWork`,
**17 / 103 / 120**, derived before it was read) is asserted by
`aListsWorkIsTheSameFor160RowsAsFor40`'s proposal arm and by the gated 100k
twin, `aListsWorkIsTheSameFor160RowsAsFor40` and
`theResidentEntrySetStaysBoundedWhileScrolling10kRows` run both authorities
(their `.legacy` arms are census A), and the two tests still pinned `.legacy`
there are stage 9's own (tokenizer min-content). **No test is retired from it** (`LR-EC`).

## 3. SwiftUI evidence (re-run 2026-09-24)

No new probe (`LR-EI`). Every SwiftUI claim below is an arm of an existing
probe, re-run today under `/usr/bin/swift` (Apple Swift 6.4, macOS 27.0),
exit 0, **every output line found verbatim in the probe's recorded header**:

| probe | lines | arms cited |
|---|---|---|
| `swiftui-engine-stage-7a.swift` | 17 / 17 | W0–W2 (a stack does not wrap), G0–G1 (equal shares; priority, not weight), S0–S1 (a fixed frame is not shrunk), A0–A1 (content does not floor a fixed frame), B0–B1 (padding does not floor a fixed frame) |
| `swiftui-engine-replacement-stage1.swift` | 79 / 79 | H0–H2 (`hidden()` keeps its space; an absent `if` does not) |
| `swiftui-stack-algorithms.swift` | 787 / 787 | G9 (two fixed 80s overflow a 100 row), A5 (a `ZStack` offers its proposal), R1/R2 (root centring) |
| `swiftui-component-distribution.swift` | 25 / 25 | G2 (`Pair().padding(8)` 120×26), G7/G8 (`.frame(width: 70)` frames each member) |
| `swiftui-frame-semantics.swift` | 291 / 291 | D4 (`frame(maxWidth: 80)` 80), D7 (`frame(minWidth: 40)` 40) |

Every other D row makes **no SwiftUI claim**: it names the CSS-only concept
and the native test pinning what the proposal authority does instead.

## 4. The retirement table (245 rows)

Verdicts (`LR-ED`):

- **R** — retired; the named test **exists at `41344e5`** (checked by script:
  every backticked test name in the column below resolves to a `func` in
  `Tests/`, except the ten N names, which are new) and asserts the same fact
  under the proposal engine. The owning lane confirms each R row by reading the
  replacement's arm before any removal, and samples at least one per family by
  mutation (spec §6); an R row it cannot confirm becomes an N row with a
  finding.
- **D** — retired; the concept is CSS-only and dies with the legacy engine
  (named in bold), with the native test pinning what the proposal authority
  does with that shape instead (a report by name, or the native answer).
- **N** — retired; its non-CSS fact gets a **new** proposal-authority test
  (spec §6 names it, its file, and the mutation that must redden it), written
  and green before the removal. Eleven rows, **ten** new tests
  (`anEmptyStackMeasuresZero` and `measuringAnEmptyContainerIsZeroNotATrap`
  share N1.1).
- **T** — kept, **trimmed** or re-spelled: a named CSS arm removed, or a
  helper re-pointed, with every kept assertion byte-identical (checked by
  script). Not a removal.
- **K** — kept untouched, owner reassigned (`LR-EE`). Not a removal.

Families (F) are the mutation-sampling unit (spec §6): F1 layout guards, F2
stacks, F3 distribution and cross alignment, F4 flex basics, F5 box model, F6
wrap, F7 flex resolution, measure and cache, F8 absolute, F9 `Resolve.swift`,
F10 legacy frame, F11 component, F12 element containers, F13 modifier chains,
F14 text, F15 style readers and animation, F16 decorations and the matrix, F17
divergence 4.

| # | file | test | fact it pins (legacy engine) | verdict | F | replacement / deleted concept |
|---|---|---|---|---|---|---|
| 1 | LayoutContextTests | `aStyleWrittenDuringLayoutTraps` | `setStyle` during layout traps | R | F1 | `setStyleOnALegacyNodeDuringNativeLayoutTraps` (the same `setStyle called while` precondition, reached from native layout) |
| 2 | LayoutContextTests | `aStyleWrittenOutsideLayoutDoesNotTrap` | positive control: `setStyle` outside layout does not trap | R | F1 | `nativeLayoutHoldsTheLayingOutFlagOnlyWhileItRuns` (the flag is false before and after a run); every `.legacy` differential test registers and styles outside layout |
| 3 | LayoutContextTests | `layoutClearsTheGuardWhenItFinishes` | `endLayout` clears the flag | R | F1 | `nativeLayoutHoldsTheLayingOutFlagOnlyWhileItRuns` |
| 4 | LayoutContextTests | `setStyleAfterLayoutFinishesDoesNotTrap` | `setStyle` after a finished layout does not trap | R | F1 | `nativeLayoutHoldsTheLayingOutFlagOnlyWhileItRuns` |
| 5 | LayoutContextTests | `computeLayoutReenteredFromAMeasureFunctionTraps` | re-entering layout from a measure function traps (CS-C) | R | F1 | `computeNativeLayoutReenteredFromAMeasureClosureTraps` |
| 6 | LayoutContextTests | `layingOutTheSameTreeTwiceInSequenceDoesNotTrap` | laying out one tree twice in sequence is ordinary | R | F1 | `aSecondComputeNativeLayoutCallReMeasuresEveryLeaf` |
| 7 | LayoutContextTests | `aCycleInTheChildListTrapsRatherThanHanging` | `LayoutContext`'s depth guard, entered by hand, traps | R | F1 | `layingOutANativeTreeDeeperThanTheLimitTraps` (the kernel's guard, reached by real recursion); `aNativeRegistrarWithChildrenRejectsANodeThatAlreadyHasAParent` (children form a tree, `CN-L`) |
| 8 | LayoutContextTests | `layingOutATreeDeeperThanTheLimitTraps` | a real layout deeper than the limit traps with the guard's message | R | F1 | `layingOutANativeTreeDeeperThanTheLimitTraps` (named up front by `LR-U`) |
| 9 | LayoutContextTests | `measureNodeConsultsTheDepthGuard` | measurement consults the depth guard | R | F1 | `measuringANativeTreeDeeperThanTheLimitTraps` |
| 10 | LayoutContextTests | `nestingBelowTheDepthLimitDoesNotTrap` | nesting at the limit does not trap | R | F1 | `aNativeTreeAtTheDepthLimitDoesNotTrap`; `aChainOfMaxDepthNodesOfEveryKindSurvivesAOneMegabyteThread` |
| 11 | StackLayoutTests | `aStackSizesToItsLargestChildOnEachAxisIndependently` | a stack is as wide as its widest child and as tall as its tallest, independently | R | F2 | `aNativeOverlayForwardsOneProposalMeasuresTheLargestChildAndCentresEachChild`; `aStackHugsItsLargestChildInsideARowAndAroundOne` (`stack_sizes_to_largest`: 90×70) |
| 12 | StackLayoutTests | `aStackDoesNotResizeItsChildren` | a stack keeps each child at its own size | R | F2 | `aStackPlacesAFixedChildAtItsAlignment`; `aZStackPlacesEachChildWithItsOwnSizeAsTheProposal` |
| 13 | StackLayoutTests | `aStackIgnoresFlexGrowOnItsChildren` | a stack ignores its children's `flexGrow` | R | F2 | `aStackStretchesByItsItemsAlignmentAndIgnoresTheirFlexFields` |
| 14 | StackLayoutTests | `anEmptyStackMeasuresZero` | an empty stack measures 0×0 | N | F2 | **N1.1** `anEmptyLoweredStackOrContainerAnswersZeroOnItsAutoAxes` |
| 15 | StackLayoutTests | `aStacksPaddingIsAddedToItsMeasuredSize` | a stack's padding is added to its measured size | R | F2 | `aLoweredStackLaysOutItsAnimatedWidthAndPadding` (the `Stack` branch's own `paddedAndSized`); `aNativePaddingInsetsConcreteProposalsExpandsMeasurementsAndOffsetsBaselines` |
| 16 | StackLayoutTests | `aNoneDisplayChildDoesNotContributeToAStacksSize` | a `display: none` child does not size a stack | D | F2 | **`display: none` takes no space** (CSS): under the proposal authority `hidden()` keeps its space and paints nothing (`aHiddenChildKeepsItsSpaceUnderTheProposalAuthority`, `LR-DH`; stage-1 probe H1 vs H0/H2, re-run 2026-09-24) |
| 17 | StackLayoutTests | `aStackSizesAnAutoChildFromItsOwnContent` | an auto stack child is sized from its own content | R | F2 | `aStackHugsItsLargestChildInsideARowAndAroundOne` (`flex_in_stack`: a row centred in a stack at its content size 90×25) |
| 18 | StackLayoutTests | `aStackChildsMinWidthClampsItsDeclaredSize` | a stack child's `minWidth` floors its declared width | R | F2 | `aStretchedStackChildFillsOnlyItsAutoAxesWithinItsOwnBounds` (`stack_stretch_min`: 340×260 past the cell); `aMinimumFloorsAnItemAndLetsAGrowerGoBelowItsContent` (the fold on a declared size) |
| 19 | StackLayoutTests | `aStackChildsMinWidthClampsItsContentMeasuredSize` | a stack child's `minWidth` floors its content-measured width | R | F2 | `aMinimumFloorsAnItemAndLetsAGrowerGoBelowItsContent` (a declared minimum on an `auto` axis is W's minimum) |
| 20 | StackLayoutTests | `allNineAlignmentsPlaceTheChildAtNineDistinctPositions` | nine alignments give nine distinct positions | R | F2 | `aLoweredStackPlacesFixedChildrenAtAllNineAlignmentsAsTheLegacyStackDoes` (stage 1's 4.1, named up front by `LR-U`); `everyProposalAlignmentPlacesAnOverlayChildAtItsNamedPosition` |
| 21 | StackLayoutTests | `stretchFillsTheContainerOnThatAxis` | stretch fills an auto axis | R | F2 | `aStretchedStackChildFillsOnlyItsAutoAxesWithinItsOwnBounds` (`stack_stretch`: 300×200) |
| 22 | StackLayoutTests | `stretchDoesNotOverrideADeclaredChildSize` | stretch keeps a declared size at the start | R | F2 | `aStretchedStackChildFillsOnlyItsAutoAxesWithinItsOwnBounds` (`stack_stretch_declared_size`: 20×10 at the start) |
| 23 | StackLayoutTests | `twoOverlappingChildrenAreCentredIndependentlyNotSequenced` | each child is centred on its own, not sequenced | R | F2 | `aNativeOverlayForwardsOneProposalMeasuresTheLargestChildAndCentresEachChild`; `aZStackPlacesItsChildrenAtItsOwnSizeWithinTheirUnion` |
| 24 | StackLayoutTests | `alignmentIsMeasuredInsideTheContentBox` | a stack's alignment is measured inside its content box | R | F2 | `aLoweredStackLaysOutItsAnimatedWidthAndPadding` (a `.topLeading` padded `Stack`: the child at the padding inset); `paddingAndBorderInsetTheContentBoxEdgeByEdge` |
| 25 | StackLayoutTests | `aStackChildsMaxWidthClampsItsDeclaredSize` | a stack child's `maxWidth` caps its declared width | R | F2 | `aStretchedStackChildFillsOnlyItsAutoAxesWithinItsOwnBounds` (`stack_stretch_max` h: 300×50); `aStretchedItemIsClampedByItsOwnMinimumAndMaximum` |
| 26 | StackLayoutTests | `aStackChildsMaxAndMinClampItsContentMeasuredSizeOnBothAxes` | min and max clamp a content-measured stack child on both axes | D | F2 | **a maximum on a content-sized axis** (CSS's clamp of a measured size): a non-greedy `maxSize` is reported by name (`aMaximumLowersOnAGreedyOrSizedAxisAndIsReportedElsewhere`, owner stage 8, `LR-AO`); the minimum half is W's minimum (`aMinimumFloorsAnItemAndLetsAGrowerGoBelowItsContent`) |
| 27 | StackLayoutTests | `aStackChildsMinHeightClampsItsContentMeasuredSize` | `minHeight` alone floors a 0-measuring child | R | F2 | `aMinimumFloorsAnItemAndLetsAGrowerGoBelowItsContent` (a minimum on an `auto` axis); `aStretchedItemIsClampedByItsOwnMinimumAndMaximum` (b `.minHeight`) |
| 28 | StackLayoutTests | `aStackChildWithAKnownWidthIsMeasuredAtThatWidthNotMaxContent` | a child with a known width is measured (wrapped) at it | R | F2 | `aLoweredTextWithADeclaredWidthKeepsItsBoundsAndGlyphOrigin`; `aNativeFrameProposesItsFixedAxesAndCentresTheChildResponse` |
| 29 | StackLayoutTests | `aStackChildsPercentagePaddingResolvesAgainstTheStackWhenMeasured` | a stack child's percentage padding resolves against the stack (measure) | D | F2 | **percentages**: reported by name (`percentagesStillReportByNameWithTheirOwner`), owned by stage 8's recipe (`LR-AI`); no SwiftUI claim |
| 30 | StackLayoutTests | `aStackChildsPercentagePaddingResolvesAgainstTheStackWhenPlaced` | the same, on placement | D | F2 | **percentages**: reported by name (`percentagesStillReportByNameWithTheirOwner`), owned by stage 8's recipe (`LR-AI`); no SwiftUI claim |
| 31 | StackLayoutTests | `aStacksNilAlignmentFieldsReadAsStretch` | a `display: .stack` `Style` with nil alignment fields stretches | R | F2 | `aStackStretchesByItsItemsAlignmentAndIgnoresTheirFlexFields` ("Box with display: .stack", a bare `Style`); `stackDefaultsToCentreNotStretch` (the element's default is `.center`, kept by §6 lane 3) |
| 32 | StackLayoutTests | `baselineOnAStackFallsBackToTheStartEdge` | `.baseline` on a stack falls back to the start edge (inert row) | D | F2 | **baselines** (task 11; CLAUDE.md "Declared but inert"): `alignItems.baseline` is reported by name under the proposal authority (`everyContainerFieldEitherLowersAndAgreesOrIsReportedByName`, "baseline" arm) |
| 33 | AlignmentTests | `lineContentSizeCountsGapsBetweenItemsOnly` | a line's content size counts gaps between items only | R | F3 | `fixedItemsPackFromTheMainStartAtTheirOwnSizesAndGap` (`flex_row_gap`: 174, no trailing gap); `spaceBetweenLowersToSpacersAtTheGap` |
| 34 | AlignmentTests | `spaceAroundAndSpaceEvenlyDifferAtTheEdges` | space-around and space-evenly differ at the edges | R | F3 | `spaceAroundAndSpaceEvenlyLowerToSpacersWhileTheyFit`; `justifyContentDistributesADeclaredMainSizesFreeSpace` (`flex_row_justify_around` 40/160/310, `flex_row_justify_evenly` 60/160/290) |
| 35 | AlignmentTests | `flexStartEndAndCentrePlaceTheWholeLine` | flex-start, flex-end and centre place the whole line | R | F3 | `aLoweredSizedContainerPlacesItsContentByJustifyContentAndAlignItems` (3 × 3 arms, row and column) |
| 36 | AlignmentTests | `distributionWithOneItemCollapsesToTheCssDegenerateCases` | one item: space-between → start, around/evenly → centre | D | F3 | **`justify-content` distribution's degenerate cases** (CSS Box Alignment's fallback, named up front by `LR-U`): the lowering spaces pairs with native spacers (`spaceBetweenLowersToSpacersAtTheGap`, `spaceAroundAndSpaceEvenlyLowerToSpacersWhileTheyFit`); no SwiftUI claim |
| 37 | AlignmentTests | `negativeFreeSpaceNeverDistributesBackwards` | negative free space packs from the start, never backwards | R | F3 | `spaceAroundAndSpaceEvenlyOverflowFromTheStartOnBothPaths` |
| 38 | AlignmentTests | `crossAxisOffsetPlacesAnItemWithinTheLine` | each cross alignment offsets an item within the line | R | F3 | `alignItemsAndAlignSelfPlaceEachItemOnTheCrossAxis` (`flex_row_align_center` 40/20/30, `flex_row_align_end_with_self` 80/20/60) |
| 39 | AlignmentTests | `anItemLargerThanItsLineOverhangsRatherThanClamping` | an item larger than its line overhangs, never clamped | R | F3 | `aLoweredFixedFrameLayerAgreesWithTheLegacyFrameOverAFixedChild` (the 80×60 child in a 60×40 frame at (−20h, −20v), overflowing at every alignment); `aLoweredRowOverflowsWhereTheLegacyRowShrinksItsChildren` |
| 40 | AlignmentTests | `alignSelfOverridesAlignItemsAndTheDefaultIsStretch` | `alignSelf` overrides `alignItems`; a bare `Style`'s default is stretch | R | F3 | `alignSelfPlacesOneChildOnTheCrossAxisOfADefiniteContainer`; `alignItemsAndAlignSelfPlaceEachItemOnTheCrossAxis`; `aStretchedChildFillsTheLineOnItsCrossAxis` (a `Box`'s default stretches) |
| 41 | AlignmentTests | `stretchFillsTheCrossAxisOnlyForAutoSizedItems` | stretch fills only an auto cross size; a declared one stays; a max caps | R | F3 | `alignItemsAndAlignSelfPlaceEachItemOnTheCrossAxis` (`flex_row_stretch_mixed`: 100 / 30 / 0 / 60) |
| 42 | AlignmentTests | `stretchFillsTheWidthInAColumn` | a column stretches the width, not the height | R | F3 | `aStretchedChildFillsTheLineOnItsCrossAxis` (its `Column {…}.alignItems(.stretch)` arm); `paddingAndBorderInsetTheContentBoxEdgeByEdge` (`flex_column_padding_asymmetric`) |
| 43 | AlignmentTests | `aStretchedSizeIsFlooredByTheCrossMinAsWellAsCappedByTheMax` | a stretched size is floored by the min and capped by the max | R | F3 | `aStretchedItemIsClampedByItsOwnMinimumAndMaximum` |
| 44 | AlignmentTests | `aNonStretchAlignmentLeavesAnAutoSizedItemUnstretched` | a non-stretch alignment leaves an auto item at its own size | R | F3 | `alignItemsAndAlignSelfPlaceEachItemOnTheCrossAxis` (`flex_row_stretch_mixed`'s flex-start item: 0); `theCentringDefaultOfRowAndColumnStretchesNothing` |
| 45 | AlignmentTests | `aPercentageCrossBoundResolvesAgainstTheCrossExtentNotTheMain` | a percentage cross bound resolves against the cross extent | D | F3 | **percentages**: reported by name (`percentagesStillReportByNameWithTheirOwner`), owned by stage 8's recipe (`LR-AI`); no SwiftUI claim |
| 46 | AlignmentTests | `rowReversePacksFromTheEndAndFlipsJustifyContent` | row-reverse packs from the end and flips `justifyContent` | R | F3 | `aReverseContainerPlacesItsChildrenFromTheMainEnd`; `aReverseDirectionPacksItemsFromTheMainEnd` (`flex_row_reverse` 360/290/240) |
| 47 | AlignmentTests | `reverseDoesNotFlipTheCrossAxis` | reversal leaves the cross axis alone | R | F3 | `aReverseDirectionPacksItemsFromTheMainEnd` (`flex_column_reverse_justify_end`: auto width stretched, cross untouched); `reversingKeepsIdentityPaintOrderHitOrderAndAccessibilityOrder` |
| 48 | FlexEngineTests | `rowPacksFixedChildrenLeftToRight` | fixed items pack left to right at their own sizes | R | F4 | `fixedItemsPackFromTheMainStartAtTheirOwnSizesAndGap` (row arm); `aLoweredRowAndColumnAgreeWithTheLegacyContainersOverFixedChildren` |
| 49 | FlexEngineTests | `columnPacksFixedChildrenTopToBottom` | the column case, top to bottom | R | F4 | `fixedItemsPackFromTheMainStartAtTheirOwnSizesAndGap` (column arm) |
| 50 | FlexEngineTests | `gapSeparatesAdjacentItemsButNotTheEnds` | a gap between adjacent items, never at the ends | R | F4 | `fixedItemsPackFromTheMainStartAtTheirOwnSizesAndGap` (`flex_row_gap` arm: x 0/72/174); `aLoweredRowOrColumnSpacesByItsDeclaredGapNotTheStackDefault` |
| 51 | FlexEngineTests | `gapUsesTheMainAxisOfTheContainer` | a column takes its gap from the vertical axis | R | F4 | `aLoweredContainerSpacesItsChildrenByTheGapOnItsMainAxis` (`gap(horizontal: 4, vertical: 20)`: row 4, column 20) |
| 52 | FlexEngineTests | `displayNoneChildrenAreSkippedAndConsumeNoSpace` | a `display: none` item takes no main-axis space | D | F4 | **`display: none` takes no space** (CSS): under the proposal authority `hidden()` keeps its space and paints nothing (`aHiddenChildKeepsItsSpaceUnderTheProposalAuthority`, `LR-DH`; stage-1 probe H1 vs H0/H2, re-run 2026-09-24) |
| 53 | FlexEngineTests | `nestedContainersStoreAbsoluteNotRelativeCoordinates` | stored rects are absolute to the root, not parent-relative | R | F4 | `paddingAndBorderInsetTheContentBoxEdgeByEdge` (`flex_nested_padding` arm: g2 at (58, 38) through two padded levels); `aNativePaddingInsetsConcreteProposalsExpandsMeasurementsAndOffsetsBaselines` |
| 54 | FlexEngineTests | `computeLayoutRoundsEveryStoredRect` | rounding walks every stored rect so 100/3 thirds close the parent | R | F4 | `nativeLayoutRoundsStoredRectanglesAfterFractionalPlacement`; `equalGrowersShareTheLineAndAMaximumCapsItsGrower` (`flex_row_seven_equal` arm: 14/15/14/14/14/15/14 close 100) |
| 55 | FlexEngineTests | `autoSizedChildTakesNoMainSizeButStretchesOnTheCross` | an auto item's main size is its content (0), its cross axis stretched | R | F4 | `aStretchedChildFillsTheLineOnItsCrossAxis`; `theCentringDefaultOfRowAndColumnStretchesNothing` (auto child 20×0) |
| 56 | FlexEngineTests | `autoSizedRootTakesTheAvailableSpaceButAnAutoItemDoesNot` | an auto root fills the offered extent at (0, 0); an auto item does not | D | F4 | **divergence 4** (`CS-I`: an `auto` root axis fills the offered extent at (0, 0)), retired here (`LR-DG`, `LR-EH`): production root placement is `CN-J` (`aNativeRootIsCentredAtItsAnswer`; `aHuggingLegacyRootIsCentredInAProductionWindow`, trimmed to its production arm; stack-algorithms R1/R2) |
| 57 | FlexEngineTests | `anAutoRootWithNoOfferedExtentMeasuresItsContent` | an auto root offered max-content measures its content (`resolveRootSize`) | D | F4 | **divergence 4** (`CS-I`: an `auto` root axis fills the offered extent at (0, 0)), retired here (`LR-DG`, `LR-EH`): production root placement is `CN-J` (`aNativeRootIsCentredAtItsAnswer`; `aHuggingLegacyRootIsCentredInAProductionWindow`, trimmed to its production arm; stack-algorithms R1/R2); a native root at a nil proposal answers its content (`aStackAtANilOrInfiniteMainProposalOffersItToEveryChild`) |
| 58 | FlexEngineTests | `aContainerItemIsFlooredByItsChildrensWidth` | §4.5: a container item is floored by its children's min-content | D | F4 | **automatic minimum** (flex §4.5): a declared main size is neither shrunk nor floored by content (`aDeclaredMainSizeIsNeitherShrunkNorFlooredByContentOrPadding`; 7a probe A1 vs A0); a non-greedy `maxSize` is reported (`aMaximumLowersOnAGreedyOrSizedAxisAndIsReportedElsewhere`) |
| 59 | FlexEngineTests | `anItemsAutomaticMinimumIsTheSmallerOfItsSpecifiedAndContentSizes` | FS-3: the automatic minimum is min(specified, content) suggestion | D | F4 | **automatic minimum** (flex §4.5): a declared main size is neither shrunk nor floored by content (`aDeclaredMainSizeIsNeitherShrunkNorFlooredByContentOrPadding`; 7a probe A1 vs A0); a non-greedy `maxSize` is reported (`aMaximumLowersOnAGreedyOrSizedAxisAndIsReportedElsewhere`) |
| 60 | FlexEngineTests | `minAndMaxSizeClampAChildAndMinWinsOnConflict` | `minSize`/`maxSize` clamp a declared size; min wins a conflict | R | F4 | `aMinimumFloorsAnItemAndLetsAGrowerGoBelowItsContent` (the fold `max(min, min(size, max))` on a declared size); `aRootsMinimumAndMaximumFoldIntoItsDeclaredSize`; `aStretchedItemIsClampedByItsOwnMinimumAndMaximum` |
| 61 | FlexEngineTests | `columnAlignFlexEndOffsetsEachChildByItsOwnWidth` | a column's cross axis is horizontal: flex-end offsets each child by its own width | R | F4 | `aLoweredSizedContainerPlacesItsContentByJustifyContentAndAlignItems` (column arms, `alignItems` 3 × 3); `alignSelfPlacesOneChildOnTheCrossAxisOfADefiniteContainer` (a 300-wide column) |
| 62 | FlexEngineTests | `anAutoCrossSizeInAColumnIsFitContentLikeWebKit` | TX-H: a column's auto cross size is fit-content (WebKit) | D | F4 | **fit-content** (TX-H: CSS Sizing's shrink-to-fit for an auto cross size; 7a's "wrap, as content"): under the proposal authority a lowered `Text` hugs its widest line at its proposal (`aLoweredTextHugsItsWidestLineWhereTheLegacyTextFillsItsContainingBlock`); no SwiftUI claim |
| 63 | FlexEngineTests | `anItemsCrossSizeIsMeasuredFromItsUsedMainSizeMatchingWebKit` | TX-H: an item's cross size is measured at its used (flexed) main size | D | F4 | **cross size after §9.7 flexing** (flex §9.4 step 7): no flex resolution on the proposal path; a stretched item's text wraps at the aliased item frame's width (`theBoundsAliasReachesDecorationHitboxesAccessibilityAndTextWrap`) and a grower's frame proposes its share (`aGrowingChildTakesTheRemainingMainSpace`) |
| 64 | FlexEngineTests | `crossSizeAfterFlexPropagatesToAnAutoContainer` | SZ-O: an auto-cross container reports its flexed child's height | D | F4 | **cross size after §9.7 flexing**: as the row above; a hugging native stack answers its children's answers (`aStackAnswersTheSumOfItsChildrensAnswers`, `aStackMeasuresItsCrossSizeAtItsAllocations`) |
| 65 | FlexEngineTests | `crossSizeAfterFlexPropagatesToTheLine` | SZ-O: a wrapped second line starts below a first line that grew after flexing | D | F4 | **wrap** (`flex-wrap`/`align-content`): `box.flexWrap` reported by name (`everyContainerFieldEitherLowersAndAgreesOrIsReportedByName`, "wrap" arm; `aWrapReverseContainerIsReportedByNameAsAWrappingOneIs` for `wrapReverse`); SwiftUI stacks lay out one line (7a probe W1, W2 vs W0, re-run 2026-09-24) |
| 66 | FlexEngineTests | `aColumnsContentSuggestionProbeOffersTheClampedWidthOrMaxContent` | §4.5's probe in a column offers the clamped used width or max-content | D | F4 | **automatic minimum** (flex §4.5): a declared main size is neither shrunk nor floored by content (`aDeclaredMainSizeIsNeitherShrunkNorFlooredByContentOrPadding`; 7a probe A1 vs A0); a non-greedy `maxSize` is reported (`aMaximumLowersOnAGreedyOrSizedAxisAndIsReportedElsewhere`) |
| 67 | BoxModelTests | `paddingAndBorderInsetTheOriginOfEachChild` | padding and border inset each child's origin, edge by edge | R | F5 | `paddingAndBorderInsetTheContentBoxEdgeByEdge`; `aStyleBorderLowersAsInsetsInsideTheDeclaredSize` |
| 68 | BoxModelTests | `stretchFillsTheContentBoxNotTheBorderBox` | a stretched item fills the content box, not the border box | R | F5 | `paddingAndBorderInsetTheContentBoxEdgeByEdge` (`flex_column_padding_asymmetric` arm: stretched items 64 wide at x 24) |
| 69 | BoxModelTests | `growDistributesTheContentBoxNotTheBorderBox` | a grower's free space is the content box's | R | F5 | `paddingAndBorderInsetTheContentBoxEdgeByEdge` (`flex_row_padding_border` arm: the grower takes the remaining 256) |
| 70 | BoxModelTests | `anOverConstrainedBoxGrowsToFitItsPaddingAndBorder` | BM-4: padding + border past a declared size grow the box | D | F5 | **border-box floor** (`BM-4`): the declared size is kept (`aDeclaredSizeBelowThePaddingKeepsTheFrameWhereCSSFloorsTheBox`, `aStretchedStackChildIsNotFlooredByItsPaddingAndBorder`; 7a probe B1 vs B0) |
| 71 | BoxModelTests | `aShrunkContainerNeverHandsItsChildANegativeContentBox` | `contentBox`'s max(0, …): no negative size reaches a child | R | F5 | `aFrameNeverAnswersANegativeSize`; `negativePaddingIsAcceptedAndItsResponseClampsPerAxis`; `aDeclaredSizeBelowThePaddingKeepsTheFrameWhereCSSFloorsTheBox` (padding larger than the declared size: no negative child) — **amended by lane 1 (`LR-EM` item 1): N, not R** — no named replacement reddens under the kernel clamp's removal; new test **N1.2** `aPaddingWiderThanItsProposalOffersItsChildZeroNeverANegativeSize` |
| 72 | BoxModelTests | `anItemsCrossSizeGrowsToFitItsPaddingAndBorderEvenPastItsMax` | BM-4 at `resolveNodeSize`, after the min/max clamp | D | F5 | **border-box floor** (`BM-4`): the declared size is kept (`aDeclaredSizeBelowThePaddingKeepsTheFrameWhereCSSFloorsTheBox`, `aStretchedStackChildIsNotFlooredByItsPaddingAndBorder`; 7a probe B1 vs B0) |
| 73 | BoxModelTests | `anItemWithMinZeroStillGrowsToFitItsPaddingAndBorder` | BM-4 at `flexBaseSize` (a declared main size) | D | F5 | **border-box floor** (`BM-4`): the declared size is kept (`aDeclaredSizeBelowThePaddingKeepsTheFrameWhereCSSFloorsTheBox`, `aStretchedStackChildIsNotFlooredByItsPaddingAndBorder`; 7a probe B1 vs B0) |
| 74 | BoxModelTests | `aDefiniteFlexBasisIsFlooredByPaddingAndBorderToo` | BM-4 reaches a definite `flex-basis` | D | F5 | **border-box floor** (`BM-4`): the declared size is kept (`aDeclaredSizeBelowThePaddingKeepsTheFrameWhereCSSFloorsTheBox`, `aStretchedStackChildIsNotFlooredByItsPaddingAndBorder`; 7a probe B1 vs B0); **length `flex-basis`**: reported by name (`aZeroBasisGrowerTakesItsShareDownToItsContent`, its 40px arm), owner stage 8/10 (`LR-AO`) |
| 75 | BoxModelTests | `aStackChildGrowsToFitItsPaddingAndBorder` | BM-4 at `layOutStack` | D | F5 | **border-box floor** (`BM-4`): the declared size is kept (`aDeclaredSizeBelowThePaddingKeepsTheFrameWhereCSSFloorsTheBox`, `aStretchedStackChildIsNotFlooredByItsPaddingAndBorder`; 7a probe B1 vs B0) |
| 76 | BoxModelTests | `anAbsoluteBoxGrowsToFitItsPaddingAndBorder` | BM-4 at `placeAbsolute`, on the declared and the stretched branch | D | F5 | **border-box floor** (`BM-4`): the declared size is kept (`aDeclaredSizeBelowThePaddingKeepsTheFrameWhereCSSFloorsTheBox`, `aStretchedStackChildIsNotFlooredByItsPaddingAndBorder`; 7a probe B1 vs B0); the absolute case is `anAbsoluteBoxStretchedBelowItsPaddingKeepsItsInsetBoxWhereTheLegacyEngineFloorsIt` |
| 77 | BoxModelTests | `marginsConsumeMainAxisSpaceAndOffsetTheItem` | margins consume main-axis space and offset each item | R | F5 | `marginsOffsetEachItemOutsideItsBorderBox` (`flex_row_margins`); `aMarginLowersAsPaddingOutsideTheItem` |
| 78 | BoxModelTests | `marginsReduceTheSpaceAvailableToGrow` | a margin reduces what a grower can grow into | R | F5 | `marginsOffsetEachItemOutsideItsBorderBox` (`flex_row_margin_with_grow` arm: 274 at x 9) |
| 79 | BoxModelTests | `crossMarginsOffsetAlignment` | cross margins offset cross placement, flex-end included | R | F5 | `marginsOffsetEachItemOutsideItsBorderBox` (`flex_row_margins` and `flex_row_reverse_stretch` arms: per-edge cross margins); `aMarginLowersAsPaddingOutsideTheItem` |
| 80 | BoxModelTests | `autoMarginsResolveToZeroForNow` | `margin: auto` resolves to 0 (inert row, legacy-only) | R | F5 | `anAutoMarginLowersAsZero` |
| 81 | BoxModelTests | `reverseContainersApplyMarginsToThePhysicalEdge` | row-reverse applies each margin to its physical edge | R | F5 | `marginsOffsetEachItemOutsideItsBorderBox` (`flex_row_reverse_margins` arm: 320/246/168) |
| 82 | BoxModelTests | `columnReverseContainersApplyMarginsToThePhysicalEdge` | the column-reverse case | R | F5 | `marginsOffsetEachItemOutsideItsBorderBox` (`flex_column_reverse_margins` arm: y 320/246/168) |
| 83 | BoxModelTests | `stretchSubtractsCrossMarginsBeforeClamping` | a stretched size is the line minus the cross margins | R | F5 | `marginsOffsetEachItemOutsideItsBorderBox` (`flex_row_stretch_with_margins` arm: 65) |
| 84 | BoxModelTests | `stretchWithMaxHeightClampsTheBorderBoxNotTheMarginBox` | the max clamps the border box after the margins come off | R | F5 | `marginsOffsetEachItemOutsideItsBorderBox` (`flex_row_stretch_with_margins` arm: capped at 50); `flex_row_stretch_min_height_margins` arm (70, 75) |
| 85 | BoxModelTests | `percentagePaddingResolvesAgainstTheContainingBlockWidthOnEveryEdge` | percentage padding resolves against the width on every edge | D | F5 | **percentages**: reported by name (`percentagesStillReportByNameWithTheirOwner`), owned by stage 8's recipe (`LR-AI`); no SwiftUI claim |
| 86 | BoxModelTests | `nestedPercentagePaddingResolvesAgainstTheParentsContentBox` | nested percentage padding resolves against the parent's content box | D | F5 | **percentages**: reported by name (`percentagesStillReportByNameWithTheirOwner`), owned by stage 8's recipe (`LR-AI`); no SwiftUI claim |
| 87 | BoxModelTests | `nestedContainersComposeTheirInsetsExactlyOnce` | insets compose down the tree exactly once | R | F5 | `paddingAndBorderInsetTheContentBoxEdgeByEdge` (`flex_nested_padding` arm: two padded, bordered levels, g2 at (58, 38)) |
| 88 | BoxModelTests | `percentageChildSizesResolveAgainstTheParentsContentBox` | BM-3: a percentage size resolves against the parent's content box | D | F5 | **percentages**: reported by name (`percentagesStillReportByNameWithTheirOwner`), owned by stage 8's recipe (`LR-AI`); no SwiftUI claim |
| 89 | BoxModelTests | `percentageMarginsResolveAgainstTheContainingBlockWidth` | percentage margins resolve against the width | D | F5 | **percentages**: reported by name (`percentagesStillReportByNameWithTheirOwner`), owned by stage 8's recipe (`LR-AI`); no SwiftUI claim |
| 90 | BoxModelTests | `aColumnsClampedAutomaticMinimumIsFlooredByItsVerticalPadding` | the floor after §4.5's clamp is the main axis's padding + border | D | F5 | **automatic minimum** (flex §4.5): a declared main size is neither shrunk nor floored by content (`aDeclaredMainSizeIsNeitherShrunkNorFlooredByContentOrPadding`; 7a probe A1 vs A0); a non-greedy `maxSize` is reported (`aMaximumLowersOnAGreedyOrSizedAxisAndIsReportedElsewhere`); **border-box floor** (`BM-4`): the declared size is kept (`aDeclaredSizeBelowThePaddingKeepsTheFrameWhereCSSFloorsTheBox`, `aStretchedStackChildIsNotFlooredByItsPaddingAndBorder`; 7a probe B1 vs B0) |
| 91 | BoxModelTests | `aMeasuredLeafsContentSizeSuggestionIsClampedByItsMaxWidth` | a measured leaf's content suggestion is clamped by its max main size | D | F5 | **automatic minimum** (flex §4.5): a declared main size is neither shrunk nor floored by content (`aDeclaredMainSizeIsNeitherShrunkNorFlooredByContentOrPadding`; 7a probe A1 vs A0); a non-greedy `maxSize` is reported (`aMaximumLowersOnAGreedyOrSizedAxisAndIsReportedElsewhere`) |
| 92 | BoxModelTests | `aClampedMeasuredLeafIsNotFlooredByItsInertPadding` | a content-sized measured leaf's clamp is not floored by its inert padding | D | F5 | **automatic minimum** (flex §4.5): a declared main size is neither shrunk nor floored by content (`aDeclaredMainSizeIsNeitherShrunkNorFlooredByContentOrPadding`; 7a probe A1 vs A0); a non-greedy `maxSize` is reported (`aMaximumLowersOnAGreedyOrSizedAxisAndIsReportedElsewhere`); a `Text`'s `Style.padding` lowers around its leaf (`paddingOnALoweredTextPadsItWhereTheLegacyLeafIgnoresIt`) |
| 93 | WrappingTests | `linesBreakWhenTheNextItemWouldOverflow` | items break onto a new line when the next would overflow | D | F6 | **wrap** (`flex-wrap`/`align-content`): `box.flexWrap` reported by name (`everyContainerFieldEitherLowersAndAgreesOrIsReportedByName`, "wrap" arm; `aWrapReverseContainerIsReportedByNameAsAWrappingOneIs` for `wrapReverse`); SwiftUI stacks lay out one line (7a probe W1, W2 vs W0, re-run 2026-09-24) |
| 94 | WrappingTests | `gapsCountTowardTheBreakDecision` | gaps count toward the break decision | D | F6 | **wrap** (`flex-wrap`/`align-content`): `box.flexWrap` reported by name (`everyContainerFieldEitherLowersAndAgreesOrIsReportedByName`, "wrap" arm; `aWrapReverseContainerIsReportedByNameAsAWrappingOneIs` for `wrapReverse`); SwiftUI stacks lay out one line (7a probe W1, W2 vs W0, re-run 2026-09-24) |
| 95 | WrappingTests | `nowrapNeverBreaks` | `nowrap` keeps one line however much it overflows | R | F6 | `aLoweredRowOverflowsWhereTheLegacyRowShrinksItsChildren` (one line, overflowing); `aReverseContainerOverflowsTowardItsMainStart`; 7a probe W1 (SwiftUI's stack is one line) |
| 96 | WrappingTests | `anOversizedItemGetsItsOwnLineRatherThanAnEmptyOne` | an oversized item takes a line alone | D | F6 | **wrap** (`flex-wrap`/`align-content`): `box.flexWrap` reported by name (`everyContainerFieldEitherLowersAndAgreesOrIsReportedByName`, "wrap" arm; `aWrapReverseContainerIsReportedByNameAsAWrappingOneIs` for `wrapReverse`); SwiftUI stacks lay out one line (7a probe W1, W2 vs W0, re-run 2026-09-24) |
| 97 | WrappingTests | `aLinesCrossSizeIsTheLargestOuterCrossSizeOnIt` | a line's cross size is its largest outer cross size | D | F6 | **wrap** (`flex-wrap`/`align-content`): `box.flexWrap` reported by name (`everyContainerFieldEitherLowersAndAgreesOrIsReportedByName`, "wrap" arm; `aWrapReverseContainerIsReportedByNameAsAWrappingOneIs` for `wrapReverse`); SwiftUI stacks lay out one line (7a probe W1, W2 vs W0, re-run 2026-09-24) |
| 98 | WrappingTests | `stretchFillsTheItemsOwnLineNotTheContainer` | stretch fills the item's line, not the container | D | F6 | **wrap** (`flex-wrap`/`align-content`): `box.flexWrap` reported by name (`everyContainerFieldEitherLowersAndAgreesOrIsReportedByName`, "wrap" arm; `aWrapReverseContainerIsReportedByNameAsAWrappingOneIs` for `wrapReverse`); SwiftUI stacks lay out one line (7a probe W1, W2 vs W0, re-run 2026-09-24) |
| 99 | WrappingTests | `rowGapSeparatesLinesAndColumnGapSeparatesItems` | row-gap separates lines, column-gap items | D | F6 | **wrap** (`flex-wrap`/`align-content`): `box.flexWrap` reported by name (`everyContainerFieldEitherLowersAndAgreesOrIsReportedByName`, "wrap" arm; `aWrapReverseContainerIsReportedByNameAsAWrappingOneIs` for `wrapReverse`); SwiftUI stacks lay out one line (7a probe W1, W2 vs W0, re-run 2026-09-24) |
| 100 | WrappingTests | `wrapReverseStacksLinesFromTheCrossEnd` | wrap-reverse stacks lines from the cross end | D | F6 | **wrap** (`flex-wrap`/`align-content`): `box.flexWrap` reported by name (`everyContainerFieldEitherLowersAndAgreesOrIsReportedByName`, "wrap" arm; `aWrapReverseContainerIsReportedByNameAsAWrappingOneIs` for `wrapReverse`); SwiftUI stacks lay out one line (7a probe W1, W2 vs W0, re-run 2026-09-24) |
| 101 | WrappingTests | `wrapReverseUnderAlignContentStretch` | wrap-reverse under align-content stretch | D | F6 | **wrap** (`flex-wrap`/`align-content`): `box.flexWrap` reported by name (`everyContainerFieldEitherLowersAndAgreesOrIsReportedByName`, "wrap" arm; `aWrapReverseContainerIsReportedByNameAsAWrappingOneIs` for `wrapReverse`); SwiftUI stacks lay out one line (7a probe W1, W2 vs W0, re-run 2026-09-24) |
| 102 | WrappingTests | `wrapReverseFlipsWhatAlignItemsFlexStartMeans` | wrap-reverse flips flex-start/flex-end | D | F6 | **wrap** (`flex-wrap`/`align-content`): `box.flexWrap` reported by name (`everyContainerFieldEitherLowersAndAgreesOrIsReportedByName`, "wrap" arm; `aWrapReverseContainerIsReportedByNameAsAWrappingOneIs` for `wrapReverse`); SwiftUI stacks lay out one line (7a probe W1, W2 vs W0, re-run 2026-09-24) |
| 103 | WrappingTests | `rowReverseComposesWithWrapReverseToFillFromTheBottomRight` | row-reverse + wrap-reverse fill from the bottom right | D | F6 | **wrap** (`flex-wrap`/`align-content`): `box.flexWrap` reported by name (`everyContainerFieldEitherLowersAndAgreesOrIsReportedByName`, "wrap" arm; `aWrapReverseContainerIsReportedByNameAsAWrappingOneIs` for `wrapReverse`); SwiftUI stacks lay out one line (7a probe W1, W2 vs W0, re-run 2026-09-24) |
| 104 | WrappingTests | `wrapReverseBreaksLinesInDocumentOrder` | wrap-reverse breaks lines in document order (`collectLines`) | D | F6 | **wrap** (`flex-wrap`/`align-content`): `box.flexWrap` reported by name (`everyContainerFieldEitherLowersAndAgreesOrIsReportedByName`, "wrap" arm; `aWrapReverseContainerIsReportedByNameAsAWrappingOneIs` for `wrapReverse`); SwiftUI stacks lay out one line (7a probe W1, W2 vs W0, re-run 2026-09-24) |
| 105 | WrappingTests | `alignContentDistributesLeftoverCrossSpaceAmongLines` | align-content distributes leftover cross space among lines | D | F6 | **wrap** (`flex-wrap`/`align-content`): `box.flexWrap` reported by name (`everyContainerFieldEitherLowersAndAgreesOrIsReportedByName`, "wrap" arm; `aWrapReverseContainerIsReportedByNameAsAWrappingOneIs` for `wrapReverse`); SwiftUI stacks lay out one line (7a probe W1, W2 vs W0, re-run 2026-09-24) |
| 106 | WrappingTests | `alignContentStretchGrowsEveryLineEqually` | align-content stretch grows every line equally | D | F6 | **wrap** (`flex-wrap`/`align-content`): `box.flexWrap` reported by name (`everyContainerFieldEitherLowersAndAgreesOrIsReportedByName`, "wrap" arm; `aWrapReverseContainerIsReportedByNameAsAWrappingOneIs` for `wrapReverse`); SwiftUI stacks lay out one line (7a probe W1, W2 vs W0, re-run 2026-09-24) |
| 107 | WrappingTests | `lineStretchNeverShrinksAnOverflowingContainer` | §9.6.15 never shrinks an overflowing line | D | F6 | **wrap** (`flex-wrap`/`align-content`): `box.flexWrap` reported by name (`everyContainerFieldEitherLowersAndAgreesOrIsReportedByName`, "wrap" arm; `aWrapReverseContainerIsReportedByNameAsAWrappingOneIs` for `wrapReverse`); SwiftUI stacks lay out one line (7a probe W1, W2 vs W0, re-run 2026-09-24) |
| 108 | WrappingTests | `aStretchedLineChangesWhatItsStretchedItemsFill` | a stretched line changes what its items fill | D | F6 | **wrap** (`flex-wrap`/`align-content`): `box.flexWrap` reported by name (`everyContainerFieldEitherLowersAndAgreesOrIsReportedByName`, "wrap" arm; `aWrapReverseContainerIsReportedByNameAsAWrappingOneIs` for `wrapReverse`); SwiftUI stacks lay out one line (7a probe W1, W2 vs W0, re-run 2026-09-24) |
| 109 | WrappingTests | `alignContentIsANoOpForNowrap` | align-content cannot move a nowrap line | D | F6 | **`align-content`**: reported by name on any container (`everyContainerFieldEitherLowersAndAgreesOrIsReportedByName`, "alignContent" arm, a nowrap `Row`); 7a probe W |
| 110 | WrappingTests | `autoCrossNestedContainerMeasuresItsLineLikeWebKit` | a line whose tallest item is an auto-cross container measures it | D | F6 | **wrap** (`flex-wrap`/`align-content`): `box.flexWrap` reported by name (`everyContainerFieldEitherLowersAndAgreesOrIsReportedByName`, "wrap" arm; `aWrapReverseContainerIsReportedByNameAsAWrappingOneIs` for `wrapReverse`); SwiftUI stacks lay out one line (7a probe W1, W2 vs W0, re-run 2026-09-24) |
| 111 | FreezeLoopTests | `growDistributesFreeSpaceInProportionToFlexGrow` | grow shares free space in proportion to the factors | D | F7 | **unequal grow weights**: `box.flexGrow.weights` reported (`unequalGrowWeightsAreReportedOnTheParent`); SwiftUI shares a surplus equally and `layoutPriority` is a priority (7a probe G0, G1) |
| 112 | FreezeLoopTests | `shrinkIsWeightedByBaseSize` | shrink is weighted by base size | D | F7 | **weighted shrink** (flex §9.7.4.c): every positive shrink lowers as compression whatever its weight (`aPositiveShrinkLowersAsSwiftUIsCompressionWhateverItsWeight`, divergence 55); a fixed frame is not shrunk (7a probe S1 vs S0) |
| 113 | FreezeLoopTests | `shrinkWeightingDistinguishesItemsWithDifferentBaseSizes` | the weighting on unequal base sizes | D | F7 | **weighted shrink** (flex §9.7.4.c): every positive shrink lowers as compression whatever its weight (`aPositiveShrinkLowersAsSwiftUIsCompressionWhateverItsWeight`, divergence 55); a fixed frame is not shrunk (7a probe S1 vs S0) |
| 114 | FreezeLoopTests | `gapIsRemovedFromFreeSpaceBeforeDistribution` | a gap comes off the free space before growers share it | R | F7 | `aGrowingChildTakesTheRemainingMainSpace`; `aLoweredContainerSpacesItsChildrenByTheGapOnItsMainAxis` (the gap is a native stack spacing, which a stack subtracts before serving flexible children, `aStackServesItsLeastFlexibleChildFirst`) |
| 115 | FreezeLoopTests | `flexFactorsSummingBelowOneLeaveFreeSpaceUnfilled` | §9.7.4.b: a factor sum below one leaves space unfilled | D | F7 | **sub-one grow sum** (flex §9.7.4.b): lowers as an equal greedy share (`aGrowFactorSumBelowOneStillFillsTheLine`; 7a probe G0) |
| 116 | FreezeLoopTests | `aLoneSubOneGrowFactorTakesOnlyItsFraction` | a lone sub-one factor takes only its fraction | D | F7 | **sub-one grow sum** (flex §9.7.4.b): lowers as an equal greedy share (`aGrowFactorSumBelowOneStillFillsTheLine`; 7a probe G0) |
| 117 | FreezeLoopTests | `subOneClauseScalesTheInitialFreeSpaceNotTheRemaining` | §9.7.4.b scales the initial free space | D | F7 | **sub-one grow sum** (flex §9.7.4.b): lowers as an equal greedy share (`aGrowFactorSumBelowOneStillFillsTheLine`; 7a probe G0) |
| 118 | FreezeLoopTests | `subOneScalingNeverExceedsTheRemainingFreeSpace` | §9.7.4.b only ever reduces the free space | D | F7 | **sub-one grow sum** (flex §9.7.4.b): lowers as an equal greedy share (`aGrowFactorSumBelowOneStillFillsTheLine`; 7a probe G0) |
| 119 | FreezeLoopTests | `clampingOneItemRedistributesTheFreedSpaceToTheRest` | §9.7.4.e: space a clamp frees goes to the unfrozen items | R | F7 | `equalGrowersShareTheLineAndAMaximumCapsItsGrower` (`flex_row_grow_with_max` arm: a capped grower at 50, the rest 175/175); `aMaximumLowersOnAGreedyOrSizedAxisAndIsReportedElsewhere` (the grower arm); 7a probe G2 recorded, not relied on |
| 120 | FreezeLoopTests | `growAddsItsShareOnTopOfANonZeroBasis` | a grower's share is added to its base size | D | F7 | **`flex-basis: auto` growth from the base** (§9.7): growers share the surplus equally, not added to bases (`growingSiblingsShareTheSurplusEquallyWhereCSSAddsItToTheirBases`, stage-2 probes F2, F3); **length `flex-basis`**: reported by name (`aZeroBasisGrowerTakesItsShareDownToItsContent`, its 40px arm), owner stage 8/10 (`LR-AO`) |
| 121 | FreezeLoopTests | `fractionalShrinkScalesByRawFactorsNotWeightedOnes` | the sub-one clause on the shrink side | D | F7 | **weighted shrink** (flex §9.7.4.c): every positive shrink lowers as compression whatever its weight (`aPositiveShrinkLowersAsSwiftUIsCompressionWhateverItsWeight`, divergence 55); a fixed frame is not shrunk (7a probe S1 vs S0) |
| 122 | FreezeLoopTests | `columnFlexClampsAgainstTheHeightNotTheWidth` | a column's flex clamps against height | R | F7 | `equalGrowersShareTheLineAndAMaximumCapsItsGrower` (`flex_column_grow_with_max` arm: 50/175/175 on the vertical axis) |
| 123 | FreezeLoopTests | `automaticMinimumSizeUsesContentSizeNotFlexBasis` | `min-width: auto` is the min-content size | D | F7 | **automatic minimum** (flex §4.5): a declared main size is neither shrunk nor floored by content (`aDeclaredMainSizeIsNeitherShrunkNorFlooredByContentOrPadding`; 7a probe A1 vs A0); a non-greedy `maxSize` is reported (`aMaximumLowersOnAGreedyOrSizedAxisAndIsReportedElsewhere`) |
| 124 | FreezeLoopTests | `anItemWithNoContentHasNoAutomaticMinimum` | an item with no content has no automatic minimum | D | F7 | **automatic minimum** (flex §4.5): a declared main size is neither shrunk nor floored by content (`aDeclaredMainSizeIsNeitherShrunkNorFlooredByContentOrPadding`; 7a probe A1 vs A0); a non-greedy `maxSize` is reported (`aMaximumLowersOnAGreedyOrSizedAxisAndIsReportedElsewhere`) |
| 125 | FreezeLoopTests | `anExplicitMinSizeOverridesTheAutomaticOne` | an explicit min replaces the automatic one | D | F7 | **automatic minimum** (flex §4.5): a declared main size is neither shrunk nor floored by content (`aDeclaredMainSizeIsNeitherShrunkNorFlooredByContentOrPadding`; 7a probe A1 vs A0); a non-greedy `maxSize` is reported (`aMaximumLowersOnAGreedyOrSizedAxisAndIsReportedElsewhere`); an explicit minimum lowers as W's minimum (`aMinimumFloorsAnItemAndLetsAGrowerGoBelowItsContent`) |
| 126 | FreezeLoopTests | `shrinkWeightSubtractsMainAxisEdgesResolvedAgainstTheContainingBlockWidth` | the shrink weight subtracts main-axis edges (percent against width) | D | F7 | **weighted shrink** (flex §9.7.4.c): every positive shrink lowers as compression whatever its weight (`aPositiveShrinkLowersAsSwiftUIsCompressionWhateverItsWeight`, divergence 55); a fixed frame is not shrunk (7a probe S1 vs S0); **percentages**: reported by name (`percentagesStillReportByNameWithTheirOwner`), owned by stage 8's recipe (`LR-AI`); no SwiftUI claim |
| 127 | FreezeLoopTests | `aLineWhoseItemsHaveNoInnerBaseSizeOverflowsInsteadOfShrinking` | no inner base size: the line overflows | D | F7 | **weighted shrink** (flex §9.7.4.c): every positive shrink lowers as compression whatever its weight (`aPositiveShrinkLowersAsSwiftUIsCompressionWhateverItsWeight`, divergence 55); a fixed frame is not shrunk (7a probe S1 vs S0) |
| 128 | FreezeLoopTests | `aContentSizedMeasuredLeafsPaddingDoesNotComeOffItsShrinkWeight` | a content-sized leaf's padding is not in its shrink weight | D | F7 | **weighted shrink** (flex §9.7.4.c): every positive shrink lowers as compression whatever its weight (`aPositiveShrinkLowersAsSwiftUIsCompressionWhateverItsWeight`, divergence 55); a fixed frame is not shrunk (7a probe S1 vs S0) |
| 129 | FreezeLoopTests | `aMeasuredLeafWithADeclaredSizeIsWeightedByItsInnerBaseSize` | a declared leaf is weighted by its inner base size | D | F7 | **weighted shrink** (flex §9.7.4.c): every positive shrink lowers as compression whatever its weight (`aPositiveShrinkLowersAsSwiftUIsCompressionWhateverItsWeight`, divergence 55); a fixed frame is not shrunk (7a probe S1 vs S0); **border-box floor** (`BM-4`): the declared size is kept (`aDeclaredSizeBelowThePaddingKeepsTheFrameWhereCSSFloorsTheBox`, `aStretchedStackChildIsNotFlooredByItsPaddingAndBorder`; 7a probe B1 vs B0) |
| 130 | FreezeLoopTests | `aContentSizedContainersShrinkWeightExcludesTheEdgesItsBaseAddedBack` | a content-sized container's weight excludes its re-added edges | D | F7 | **weighted shrink** (flex §9.7.4.c): every positive shrink lowers as compression whatever its weight (`aPositiveShrinkLowersAsSwiftUIsCompressionWhateverItsWeight`, divergence 55); a fixed frame is not shrunk (7a probe S1 vs S0) |
| 131 | AbsolutePositioningTests | `anAbsoluteChildDoesNotContributeToItsContainersSize` | an absolute child contributes nothing to its container's size | R | F8 | `aDeferredAbsoluteBoxResolvesItsInsetsAgainstTheWindowAndLeavesTheFlow` (`abs_removed_from_flow` arm: the container stays 40×20); `aPresentationPlaceholderIsDroppedByEveryLoweredContainer` |
| 132 | AbsolutePositioningTests | `anAbsoluteChildDoesNotContributeToAStacksSize` | the same, for a stack | R | F8 | `aPresentationPlaceholderIsDroppedByEveryLoweredContainer` (its `Stack` arm) |
| 133 | AbsolutePositioningTests | `anAbsoluteChildDoesNotShiftItsInFlowSiblings` | an absolute child occupies no main-axis space | R | F8 | `aPresentationPlaceholderIsDroppedByEveryLoweredContainer`; `aDeferredAbsoluteBoxResolvesItsInsetsAgainstTheWindowAndLeavesTheFlow` |
| 134 | AbsolutePositioningTests | `anAbsoluteChildIsPlacedAgainstTheNearestNonStaticAncestor` | the containing block is the nearest non-static ancestor | D | F8 | **a containing block other than the window**: reported by name (`aPresentationWhoseContainingBlockIsNotTheWindowIsReportedByName`, owner stage 9); an absolute box outside a `Deferred` traps a production frame (`anAbsoluteBoxOutsideADeferredTrapsAProductionProposalFrame`, owner stage 10) |
| 135 | AbsolutePositioningTests | `withNoPositionedAncestorTheRootIsTheContainingBlock` | with no positioned ancestor the root is the containing block | R | F8 | `aDeferredAbsoluteBoxResolvesItsInsetsAgainstTheWindowAndLeavesTheFlow` (the window stands for the root, `abs_containing_block_skips_static`); `aDeferredAbsoluteBoxLowersAgainstTheWindowOnEveryInsetShape` |
| 136 | AbsolutePositioningTests | `theContainingBlockIsThePaddingBoxNotTheBorderBox` | the containing block is the padding box | D | F8 | **a containing block other than the window**: reported by name (`aPresentationWhoseContainingBlockIsNotTheWindowIsReportedByName`, owner stage 9); an absolute box outside a `Deferred` traps a production frame (`anAbsoluteBoxOutsideADeferredTrapsAProductionProposalFrame`, owner stage 10) (a window has no border: the padding-box distinction exists only for a non-window block) |
| 137 | AbsolutePositioningTests | `aSingleInsetPositionsFromThatEdge` | a single inset positions from its edge | R | F8 | `aDeferredAbsoluteBoxLowersAgainstTheWindowOnEveryInsetShape` ("top/left px", "right/bottom px, declared size") |
| 138 | AbsolutePositioningTests | `oppositeInsetsWithAnAutoSizeStretchTheBox` | opposite insets with an auto size stretch the box | R | F8 | `aDeferredAbsoluteBoxLowersAgainstTheWindowOnEveryInsetShape` ("all four, auto size", "left/right, auto width") |
| 139 | AbsolutePositioningTests | `anOverConstrainedBoxIgnoresItsRightInset` | left + right + width: right is dropped | R | F8 | `aDeferredAbsoluteBoxLowersAgainstTheWindowOnEveryInsetShape` ("all four, declared size (the leading insets win)"); `aDeferredAbsoluteBoxResolvesItsInsetsAgainstTheWindowAndLeavesTheFlow` (`abs_over_constrained`) |
| 140 | AbsolutePositioningTests | `percentageInsetsResolveAgainstWidthForXAndHeightForY` | percentage insets resolve per axis | R | F8 | `aDeferredAbsoluteBoxLowersAgainstTheWindowOnEveryInsetShape` ("percent: top against the height, left against the width"); `abs_percent_insets_nonsquare` arm |
| 141 | AbsolutePositioningTests | `allAutoInsetsPlaceAtTheContainingBlockOriginNotTheStaticPosition` | all-auto insets place at the block's origin, not the static position (divergence 9) | R | F8 | `aDeferredAbsoluteBoxLowersAgainstTheWindowOnEveryInsetShape` ("no insets, after an in-flow sibling (divergence 9)") |
| 142 | AbsolutePositioningTests | `anAbsoluteChildWithNoChildrenResolvesToItsDeclaredSize` | a childless absolute box takes its declared size, not 0×0 | R | F8 | `aDeferredAbsoluteBoxLowersAgainstTheWindowOnEveryInsetShape` ("top/left px": 30×20); `abs_removed_from_flow`/`abs_over_constrained` arms |
| 143 | AbsolutePositioningTests | `anAbsoluteBoxesDeclaredSizeIsClampedByItsOwnMinAndMax` | a declared absolute size is clamped by its own min/max (AP-E) | R | F8 | `aDeferredAbsoluteBoxLowersAgainstTheWindowOnEveryInsetShape` ("declared width 40, minWidth 50 (clamped on a declared axis, AP-E)"); a min/max on an `auto` axis reports `…absolute` (owner stage 8) |
| 144 | AbsolutePositioningTests | `withNoPositionedAncestorTheContainingBlockIsTheRootsPaddingBox` | with no positioned ancestor the block is the root's padding box | D | F8 | **a containing block other than the window**: reported by name (`aPresentationWhoseContainingBlockIsNotTheWindowIsReportedByName`, owner stage 9); an absolute box outside a `Deferred` traps a production frame (`anAbsoluteBoxOutsideADeferredTrapsAProductionProposalFrame`, owner stage 10) (the root's border and padding exist only for a non-window block) |
| 145 | AbsolutePositioningTests | `aDisplayNoneAbsoluteChildIsNotPlaced` | a `display: none` absolute box stays unplaced | D | F8 | **`display: none` takes no space** (CSS): under the proposal authority `hidden()` keeps its space and paints nothing (`aHiddenChildKeepsItsSpaceUnderTheProposalAuthority`, `LR-DH`; stage-1 probe H1 vs H0/H2, re-run 2026-09-24) |
| 146 | AbsolutePositioningTests | `anAutoSizedAbsoluteBoxIsMeasuredAgainstItsContainingBlockNotMaxContent` | an auto absolute box is measured against its block, not max-content | R | F8 | `anAbsoluteTextWrapsAtTheWindowMinusItsInsetWhereTheLegacyEngineWrapsAtTheWindow` |
| 147 | AbsolutePositioningTests | `percentagePaddingInsideAnAbsoluteBoxResolvesAgainstItsContainingBlocksWidth` | percentage padding in an absolute box resolves against its block's width | D | F8 | **percentages**: reported by name (`percentagesStillReportByNameWithTheirOwner`), owned by stage 8's recipe (`LR-AI`); no SwiftUI claim |
| 148 | MeasureNodeTests | `measuringARowContainerReturnsItsContentSize` | `measureNode` answers a container's content size | D | F7 | **the CSS measure cache and `measureNode`** (`LayoutContext`, deleted at stage 9): the kernel's one-call cache is pinned by `aBranchingNativeTreeMeasuresEachLeafOncePerDistinctProposal` and `nativeLayoutWorkIsPerCall`; a hugging native stack answers its children's sum (`aStackAnswersTheSumOfItsChildrensAnswers`) |
| 149 | MeasureNodeTests | `measuringWritesNoLayout` | measurement writes no rect (purity) | R | F7 | `measuringANativeTreeWritesNoRect`; `writingARectDuringNativeMeasurementTraps` |
| 150 | MeasureNodeTests | `aKnownSizeOverridesTheMeasuredOne` | §5.5: a known size wins over the measured one | D | F7 | **the CSS measure cache and `measureNode`** (`LayoutContext`, deleted at stage 9): the kernel's one-call cache is pinned by `aBranchingNativeTreeMeasuresEachLeafOncePerDistinctProposal` and `nativeLayoutWorkIsPerCall`; a fixed native frame proposes and answers its fixed axes (`aNativeFrameProposesItsFixedAxesAndCentresTheChildResponse`) |
| 151 | MeasureNodeTests | `measuringALeafUsesItsMeasureFunction` | a leaf answers from its `MeasureFunction` | D | F7 | **the legacy `MeasureFunction`** (stage 9): a native leaf answers from its closure (`aBranchingNativeTreeMeasuresEachLeafOncePerDistinctProposal`) |
| 152 | MeasureNodeTests | `measuringAnEmptyContainerIsZeroNotATrap` | an empty container measures 0, not a trap | N | F7 | **N1.1** `anEmptyLoweredStackOrContainerAnswersZeroOnItsAutoAxes` |
| 153 | MeasureNodeTests | `measuringAContainerReportsItsBorderBoxNotItsContentBox` | a measured container reports its border box | R | F7 | `aNativePaddingInsetsConcreteProposalsExpandsMeasurementsAndOffsetsBaselines`; `aLoweredContainerPaddingSitsInsideItsDeclaredSize` |
| 154 | MeasureNodeTests | `measuringAWrappedContainerCountsGapsAndMargins` | a multi-line container's measure counts gaps and margins | D | F7 | **wrap** (`flex-wrap`/`align-content`): `box.flexWrap` reported by name (`everyContainerFieldEitherLowersAndAgreesOrIsReportedByName`, "wrap" arm; `aWrapReverseContainerIsReportedByNameAsAWrappingOneIs` for `wrapReverse`); SwiftUI stacks lay out one line (7a probe W1, W2 vs W0, re-run 2026-09-24) |
| 155 | MeasureNodeTests | `aGrowingItemUnderMaxContentKeepsItsHypotheticalMainSize` | grow does not apply under an indefinite (max-content) axis | D | F7 | **intrinsic min-/max-content queries** (`AvailableSpace`, CSS Sizing §5): the kernel's nil proposal is the ideal size (`aStackAtANilOrInfiniteMainProposalOffersItToEveryChild`); a greedy frame at a nil proposal answers its child (`aFrameWithNoMaximumAnswersItsChildRatherThanItsProposal`, `anInfiniteProposalIsAnsweredWithInfinity`) |
| 156 | MeasureNodeTests | `aPercentageSizedItemUnderMaxContentContributesNothing` | a percentage size against an indefinite basis contributes nothing | D | F7 | **percentages**: reported by name (`percentagesStillReportByNameWithTheirOwner`), owned by stage 8's recipe (`LR-AI`); no SwiftUI claim |
| 157 | MeasureNodeTests | `aPercentageGapUnderMaxContentResolvesToZero` | a percentage gap against an indefinite basis is 0 | D | F7 | **percentages**: reported by name (`percentagesStillReportByNameWithTheirOwner`), owned by stage 8's recipe (`LR-AI`); no SwiftUI claim (`gap.percent` reported, `aContainersReportListsItsContainerRowsBeforeItsEveryNodeRowsAndTrapsOnTheFirst`) |
| 158 | SizingFixtureTests | `theClampedAutomaticMinimumIsStillFlooredByPaddingAndBorderMatchesWebKit` | the `minZero` arm: `c` at x 80, 40 wide, `b` at x 120 (7a's `LR-DT` remainder) | D | F7 | **automatic minimum** (flex §4.5): a declared main size is neither shrunk nor floored by content (`aDeclaredMainSizeIsNeitherShrunkNorFlooredByContentOrPadding`; 7a probe A1 vs A0); a non-greedy `maxSize` is reported (`aMaximumLowersOnAGreedyOrSizedAxisAndIsReportedElsewhere`); **border-box floor** (`BM-4`): the declared size is kept (`aDeclaredSizeBelowThePaddingKeepsTheFrameWhereCSSFloorsTheBox`, `aStretchedStackChildIsNotFlooredByItsPaddingAndBorder`; 7a probe B1 vs B0) |
| 159 | FlexBaseSizeTests | `definiteFlexBasisWins` | §9.2 step A: a definite basis wins | D | F7 | **length `flex-basis`**: reported by name (`aZeroBasisGrowerTakesItsShareDownToItsContent`, its 40px arm), owner stage 8/10 (`LR-AO`) |
| 160 | FlexBaseSizeTests | `autoBasisFallsBackToTheDefiniteMainSize` | §9.2: an auto basis falls back to the main size | D | F7 | **flex base size** (flex §9.2): a declared main size is the item's own frame (`aLoweredFixedSizeBoxAgreesWithTheLegacyBoxInEveryObservation`) |
| 161 | FlexBaseSizeTests | `autoBasisPercentageMainSizeResolvesAgainstContainerMainNotCross` | a percentage main size resolves against the container's main axis | D | F7 | **percentages**: reported by name (`percentagesStillReportByNameWithTheirOwner`), owned by stage 8's recipe (`LR-AI`); no SwiftUI claim |
| 162 | FlexBaseSizeTests | `autoBasisWithNoDefiniteSizeMeasuresContent` | §9.2 step E: content sizing offers max-content on the main axis | D | F7 | **flex base size**: **intrinsic min-/max-content queries** (`AvailableSpace`, CSS Sizing §5): the kernel's nil proposal is the ideal size (`aStackAtANilOrInfiniteMainProposalOffersItToEveryChild`) |
| 163 | FlexBaseSizeTests | `autoBasisWithNoMeasureFunctionOrChildrenIsZero` | a childless node with no measure function has base 0 | D | F7 | **flex base size**; the empty case is **N1.1** |
| 164 | FlexBaseSizeTests | `columnContentSizeOffersKnownCrossAndMaxContentMain` | column content sizing offers the known cross and max-content main | D | F7 | **flex base size**: **intrinsic min-/max-content queries** (`AvailableSpace`, CSS Sizing §5): the kernel's nil proposal is the ideal size (`aStackAtANilOrInfiniteMainProposalOffersItToEveryChild`) |
| 165 | FlexBaseSizeTests | `aContainerItemsBaseSizeComesFromItsChildren` | a container item's base size comes from its children | D | F7 | **flex base size**; a hugging native stack answers its children (`aStackAnswersTheSumOfItsChildrensAnswers`) |
| 166 | FlexBaseSizeTests | `percentageBasisResolvesAgainstTheContainerMainAxis` | a percentage basis resolves against the main axis | D | F7 | **percentages**: reported by name (`percentagesStillReportByNameWithTheirOwner`), owned by stage 8's recipe (`LR-AI`); no SwiftUI claim |
| 167 | MeasureCacheTests | `theCacheIsActuallyConsulted` | the measure cache is consulted (a repeated query hits) | R | F7 | `aBranchingNativeTreeMeasuresEachLeafOncePerDistinctProposal`; `aSubviewMeasuresOncePerDistinctProposalWithinOneRun` |
| 168 | MeasureCacheTests | `aRepeatedLeafQueryIsCached` | a repeated leaf query is a hit | R | F7 | `aBranchingNativeTreeMeasuresEachLeafOncePerDistinctProposal` (leaf closures once per distinct proposal) |
| 169 | MeasureCacheTests | `aCachedAnswerMatchesAFreshOne` | a cached answer equals a fresh one | R | F7 | `aSecondComputeNativeLayoutCallReMeasuresEveryLeaf`; `aDifferentRootProposalReMeasuresAndMovesTheRects` |
| 170 | MeasureCacheTests | `aCacheHitRespectsTheContainingBlockWidth` | a cache hit respects `containingBlockWidth` (percentage basis) | D | F7 | **the CSS measure cache and `measureNode`** (`LayoutContext`, deleted at stage 9): the kernel's one-call cache is pinned by `aBranchingNativeTreeMeasuresEachLeafOncePerDistinctProposal` and `nativeLayoutWorkIsPerCall`; **percentages**: reported by name (`percentagesStillReportByNameWithTheirOwner`), owned by stage 8's recipe (`LR-AI`); no SwiftUI claim |
| 171 | MeasureCacheTests | `minContentAndMaxContentDoNotShareACacheEntry` | distinct queries never share an entry | R | F7 | `aBranchingNativeTreeMeasuresEachLeafOncePerDistinctProposal` (one entry per distinct proposal) |
| 172 | MeasureCacheTests | `eachRunStartsWithAnEmptyCache` | a new run starts cold (the cache does not outlive its context) | R | F7 | `nativeLayoutWorkIsPerCall`; `aSecondComputeNativeLayoutCallReMeasuresEveryLeaf` (`SA-H`: the cache lives for one call) |
| 173 | ResolveTests | `lengthsResolveByKind` | `resolveLength`: px, rem and percent by kind | D | F9 | **`Resolve.swift`** (the CSS engine's resolver; no production caller outside the engine files, measured by grep): px and rem reach the lowering through `Length`'s own resolution, pinned by `aLoweredFixedSizeBoxAgreesWithTheLegacyBoxInEveryObservation` (px and rem) and the "rem" arm of `aDeferredAbsoluteBoxLowersAgainstTheWindowOnEveryInsetShape` |
| 174 | ResolveTests | `percentagesAgainstAnIndefiniteParentAreUnresolvable` | a percentage against an indefinite parent is unresolvable | D | F9 | **`Resolve.swift`**; **percentages**: reported by name (`percentagesStillReportByNameWithTheirOwner`), owned by stage 8's recipe (`LR-AI`); no SwiftUI claim |
| 175 | ResolveTests | `autoDimensionIsUnresolvable` | `auto` resolves to nil | D | F9 | **`Resolve.swift`**; an `auto` axis lowers to 0 on a leaf (`aFrameOverNoNodeFixedOnOneAxisOrMinOnlyIsZeroOnTheOther`) |
| 176 | ResolveTests | `edgesResolveAndSumPerAxis` | `resolveEdges` sums per axis | D | F9 | **`Resolve.swift`**; padding and border insets per edge are pinned by `paddingAndBorderInsetTheContentBoxEdgeByEdge` |
| 177 | ResolveTests | `edgePercentagesResolveAgainstTheInlineAxisOnly` | edge percentages resolve against the inline axis | D | F9 | **percentages**: reported by name (`percentagesStillReportByNameWithTheirOwner`), owned by stage 8's recipe (`LR-AI`); no SwiftUI claim |
| 178 | ResolveTests | `clampRespectsBothBounds` | `clamp(_:min:max:)` respects both bounds | D | F9 | **`Resolve.swift`**; the lowering's fold `max(min, min(size, max))` is pinned by `aMinimumFloorsAnItemAndLetsAGrowerGoBelowItsContent` and `aRootsMinimumAndMaximumFoldIntoItsDeclaredSize`; the kernel's frame clamp by `aNativeFrameClampsItsProposalAndResponseToMinimumAndMaximum` |
| 179 | IntrinsicModeTests | `aContainersIntrinsicQueryReachesItsChildren` | a min-content query reaches the children | D | F7 | **intrinsic min-/max-content queries** (`AvailableSpace`, CSS Sizing §5): the kernel's nil proposal is the ideal size (`aStackAtANilOrInfiniteMainProposalOffersItToEveryChild`) |
| 180 | IntrinsicModeTests | `aWrapContainerUnderMinContentPutsEachItemOnItsOwnLine` | §9.9.1.1: under min-content each item lines alone | D | F7 | **wrap** (`flex-wrap`/`align-content`): `box.flexWrap` reported by name (`everyContainerFieldEitherLowersAndAgreesOrIsReportedByName`, "wrap" arm; `aWrapReverseContainerIsReportedByNameAsAWrappingOneIs` for `wrapReverse`); SwiftUI stacks lay out one line (7a probe W1, W2 vs W0, re-run 2026-09-24) |
| 181 | IntrinsicModeTests | `theCrossAxisOfTheQueryReachesTheChildToo` | the query's cross axis reaches the child | D | F7 | **intrinsic min-/max-content queries** (`AvailableSpace`, CSS Sizing §5): the kernel's nil proposal is the ideal size (`aStackAtANilOrInfiniteMainProposalOffersItToEveryChild`) |
| 182 | IntrinsicModeTests | `theCrossAxisQueryReachesAnAutoCrossItem` | the fourth propagation site (`collectItems`' `ownCross`) | D | F7 | **intrinsic min-/max-content queries** (`AvailableSpace`, CSS Sizing §5): the kernel's nil proposal is the ideal size (`aStackAtANilOrInfiniteMainProposalOffersItToEveryChild`) |
| 183 | FreezeLoopAllocationTests | `freezeLoopAllocationsDoNotGrowWithTheItemsOnTheLine` | the freeze loop allocates at most one buffer per pass | D | F7 | **the flex §9.7 freeze loop**: a native stack serves its least flexible child first (`aStackServesItsLeastFlexibleChildFirst`, `CN-B`); the kernel's work pin is `NativeLayoutWorkTests` (`LR-U`); CLAUDE.md's `FREEZE-ALLOC` CI hazard retires with this test (`LR-U`) |
| 184 | FreezeLoopAllocationTests | `freezeLoopMatchesItsAllocatingReferenceBitForBit` | §9.7 agrees bit for bit with its allocating reference | D | F7 | **the flex §9.7 freeze loop**: a native stack serves its least flexible child first (`aStackServesItsLeastFlexibleChildFirst`, `CN-B`); the kernel's work pin is `NativeLayoutWorkTests` (`LR-U`) |
| 185 | LeafProbeShortcutTests | `aChildlessNodeWithNoMeasureFunctionIsNeverACacheMiss` | a childless, measure-less node is never a cache miss | D | F7 | **the CSS measure cache and `measureNode`** (`LayoutContext`, deleted at stage 9): the kernel's one-call cache is pinned by `aBranchingNativeTreeMeasuresEachLeafOncePerDistinctProposal` and `nativeLayoutWorkIsPerCall` |
| 186 | LeafProbeShortcutTests | `theLeafShortcutMovesNoRectOnSeededRandomTrees` | the leaf shortcut moves no rect on 150 random trees | D | F7 | **the CSS measure cache and `measureNode`** (`LayoutContext`, deleted at stage 9): the kernel's one-call cache is pinned by `aBranchingNativeTreeMeasuresEachLeafOncePerDistinctProposal` and `nativeLayoutWorkIsPerCall` |
| 187 | ScrollLayoutTests | `flexShrinkHoldsAContentNodeOpenOnceItsAutomaticMinimumIsRemoved` | `flexShrink: 0` holds a node open once a zero minimum removed the automatic one | D | F7 | **automatic minimum** (flex §4.5): a declared main size is neither shrunk nor floored by content (`aDeclaredMainSizeIsNeitherShrunkNorFlooredByContentOrPadding`; 7a probe A1 vs A0); a non-greedy `maxSize` is reported (`aMaximumLowersOnAGreedyOrSizedAxisAndIsReportedElsewhere`); `flexShrink(0)` lowers to `fixedSize` on the main axis (`aZeroShrinkKeepsItsNaturalMainSizeAndOverflows`) |
| 188 | NativeBoundaryTrapTests | `computeLayoutRejectsANativeRoot` | `computeLayout` on a native root traps (SA-G's legacy entry) | D | F1 | **the CSS engine's entry** (`computeLayout`, stage 9): production never hands it a root — `Frame.computeRootLayout` branches on `isNativeLayoutNode(root)` first and `noProductionFrameReachesTheLegacyEngine` counts zero legacy root layouts; the rest of `SA-G` stays pinned (`aNativeNodeRegisteredUnderALegacyNodeTraps`, `aLegacyNodeRegisteredUnderANativeStackTraps`, `aStyleWrittenOntoANativeNodeTraps`) |
| 189 | NativeBoundaryTrapTests | `computeLayoutCalledFromANativeMeasureClosureTraps` | one `isLayingOut` flag covers both engines (SA-I) | R | F1 | `setStyleOnALegacyNodeDuringNativeLayoutTraps` and `registeringALegacyLeafDuringNativeLayoutTraps` (legacy API sees the native run's flag); `computeNativeLayoutReenteredFromAMeasureClosureTraps` |
| 190 | NativeBoundaryTrapTests | `registeringANodeDuringLegacyLayoutTraps` | registering during legacy layout traps (the check is not native-only) | R | F1 | `registeringALegacyLeafDuringNativeLayoutTraps`; `registeringANativeNodeDuringNativeLayoutTraps` (one storage append, one check) |
| 191 | StyleTests | `defaultStyleMatchesCSSInitialValues` | `Style()` defaults are CSS initial values | K | — | **kept** (`LR-EE`): `Style` is the lowering's input in production until stage 10 deletes its CSS fields |
| 192 | StyleTests | `defaultStaticIsExactlyTheMemberwiseDefault` | `Style.default == Style()` | K | — | **kept** (`LR-EE`): native nodes' placeholder rows read `Style.default` (`everyNativeRegistrarAcceptsNativeChildrenWithoutTrapping`) |
| 193 | StyleTests | `flexDirectionKnowsItsAxis` | `FlexDirection` knows its axis | K | — | **kept** (`LR-EE`): the lowering reads it for every `Row`/`Column` |
| 194 | StyleTests | `styleIsValueSemantic` | `Style` is a value type | K | — | **kept** (`LR-EE`) |
| 195 | FrameSizingTests | `aLegacyFixedFrameDoesNotShrinkAsAFlexItem` | a fixed legacy frame keeps its declared size in an over-constrained row (FR-P's axis-named `minSize`) | R | F10 | `aLoweredFixedFrameLayerAgreesWithTheLegacyFrameOverAFixedChild` (a fixed frame lowers to a native fixed frame); `aDeclaredMainSizeIsNeitherShrunkNorFlooredByContentOrPadding`; `theDemosBodyRowKeepsTheSidebarAtItsDeclaredWidthWhereCSSShrinksIt`; 7a probe S1 vs S0 |
| 196 | FrameSizingTests | `aLegacyFrameClampsToItsMinimumAndMaximumWithoutGrowingIntoTheProposal` | FR-E: a legacy flexible frame clamps and never grows into the proposal (third arm pinned wrong on purpose) | D | F10 | **FR-E's legacy clamp** (divergence 35's legacy side): under the proposal authority the flexible frame is greedy (`aLoweredFlexibleFrameLayerTakesSwiftUIsAnswerWhereTheLegacyFrameClamps`; frame-semantics probe D4, D7, re-run 2026-09-24) |
| 197 | FrameSizingTests | `aLegacyFrameAroundAListStillBuildsEveryRow` | a legacy frame around a `List` builds exactly the rows the unframed list builds | N | F10 | **N2.3** `aFramedListBuildsTheRowsTheUnframedListBuildsUnderTheProposalAuthority` (no `ListLoweringTests` arm frames a `List`: grep) |
| 198 | FrameSizingTests | `aSingleChildLegacyFrameOverflowsAnOversizedChildOnBothAxes` | CN-N: an oversized child keeps its size and overflows both axes, placed by the frame's alignment | R | F10 | `aLoweredFixedFrameLayerAgreesWithTheLegacyFrameOverAFixedChild` (the 80×60 child in a 60×40 frame, all nine alignments, overflowing) |
| 199 | FrameSizingTests | `aSingleChildLegacyFrameIgnoresItsChildsFlexGrowAndAlignSelf` | CN-N's cost: a one-cell `display: .stack` frame ignores its child's `flexGrow`/`alignSelf` | D | F10 | **`CN-N`'s one-cell stack** (the legacy `.frame`'s CSS lowering, `FR-C`): a native frame proposes its own size to its child whatever the child's flex fields; a stack parent consumes and ignores them (`aStackStretchesByItsItemsAlignmentAndIgnoresTheirFlexFields`); no SwiftUI claim (neither field has a SwiftUI spelling) |
| 200 | FrameSizingTests | `hiddenAfterASingleChildLegacyFrameStillHidesTheElement` | `hidden()` after a one-node frame hides the element (takes no space) | D | F10 | **`display: none` takes no space** (CSS): under the proposal authority `hidden()` keeps its space and paints nothing (`aHiddenChildKeepsItsSpaceUnderTheProposalAuthority`, `LR-DH`; stage-1 probe H1 vs H0/H2, re-run 2026-09-24); the frame-layer case is `aHiddenFrameLayerLowersAsIfShown` (named by `LR-DQ` item 2) |
| 201 | FrameSizingTests | `anInfiniteMaximumFillsOnlyWhenBothAxesAreInfinite` | FR-O: a legacy infinite maximum fills only when both axes are infinite | D | F10 | **`FR-O`'s both-axes rule** (the CSS lowering's `flexGrow` + `stretch` pair): under the proposal authority a single-axis infinite maximum is greedy on that axis (`aNativeFrameWithInfiniteMaximumExpandsToItsFiniteProposal`; `aLoweredFlexibleFrameLayerTakesSwiftUIsAnswerWhereTheLegacyFrameClamps`, its `FR-O` arm) |
| 202 | FrameSizingTests | `aSingleAxisFixedFrameDoesNotPinTheAxisItDidNotDeclare` | FR-P: a single-axis fixed frame leaves the other axis to its child | R | F10 | `aNativeFrameForwardsAnOptionalAxisAndAdoptsThatChildResponse`; `aFrameOverNoNodeFixedOnOneAxisOrMinOnlyIsZeroOnTheOther` |
| 203 | FrameSizingTests | `aFractionSizeResolvesAgainstItsContainingBlock` | CN-O: `width(fraction:)` takes a fraction of the containing block | D | F10 | **percentages**: reported by name (`percentagesStillReportByNameWithTheirOwner`), owned by stage 8's recipe (`LR-AI`); no SwiftUI claim |
| 204 | FrameSizingTests | `theSizingModifiersWriteTheirOwnElementsBoxRatherThanWrappingIt` | FR-F/FR-G: sizing modifiers add no node (`.frame` adds one); `.minHeight(0)` cancels the automatic minimum | D | F10 | the node-count half is **the legacy tree's shape** (CSS-structure); the type-level fact stays pinned by `legacyModifierChainsInferOneConcreteType` (trimmed, kept: a `Self`-returning modifier after a wrapper configures the outermost layer, `layerCount`) and `FrameSizingCompileGuards`; the FR-G half is **automatic minimum** (flex §4.5): a declared main size is neither shrunk nor floored by content (`aDeclaredMainSizeIsNeitherShrunkNorFlooredByContentOrPadding`; 7a probe A1 vs A0); a non-greedy `maxSize` is reported (`aMaximumLowersOnAGreedyOrSizedAxisAndIsReportedElsewhere`) |
| 205 | FrameSizingTests | `anAbsolutelyPositionedChildInsideASingleChildLegacyFrameKeepsItsPlacement` | an absolute child of a single-child frame keeps its placement | D | F10 | **a containing block other than the window**: reported by name (`aPresentationWhoseContainingBlockIsNotTheWindowIsReportedByName`, owner stage 9); an absolute box outside a `Deferred` traps a production frame (`anAbsoluteBoxOutsideADeferredTrapsAProductionProposalFrame`, owner stage 10) |
| 206 | FrameSizingTests | `aScrollViewInsideASingleChildLegacyFrameKeepsItsViewportAndWheel` | a `ScrollView` inside a single-child frame keeps its viewport, content rect and wheel | N | F10 | **N2.4** `aScrollViewInsideAFrameKeepsItsViewportAndWheelUnderTheProposalAuthority` (no `LoweringScrollTests` arm frames a `ScrollView`: grep) |
| 207 | ComponentTests | `aModifierOnAComponentDistributesToEachTopLevelChild` | a component's `.padding` applies to each top-level node; no node added (G2) | R | F11 | `aComponentsPaddingLowersAsAnOrdinaryOneChildContainer` (4.2, its proposal arm; component-distribution probe G2, re-run 2026-09-24) |
| 208 | ComponentTests | `aFrameWrapsAComponentsBodyWithoutOverwritingItsChildren` | a `.frame` wraps a component's body and leaves its members' sizes | R | F11 | `aFrameOverOneMemberIsUnchanged` (5.2); `aFrameOverAMultiMemberComponentFramesEachMemberWhereTheLegacyLayerSqueezesThem` (5.1, members keep their sizes; component-distribution G7) |
| 209 | ComponentTests | `chainedFramesRemainConcreteAndNestTheirLayoutNodes` | two chained frames nest (MC-A), the type stays flat | R | F11 | `chainedLegacyFramesAgreeWithSwiftUIsOrderingRules` (both authorities); `legacyModifierChainsInferOneConcreteType` (trimmed: `Row<ModifiedElement<…>>` stored, `layerCount`); the node count is CSS-structure |
| 210 | ComponentTests | `paddingWrapsAnElementAndExpandsItsOuterFootprint` | `.padding` on an element wraps it and offsets it by the inset | R | F11 | `aLoweredPaddingLayerAgreesWithTheLegacyWrapper` (4.3); `legacyPaddingAccumulatesAcrossAChainAsSwiftUIDoes` |
| 211 | ComponentTests | `chainedPaddingCreatesNestedWrappers` | chained padding nests: 4 + 8 = 12 | R | F11 | `legacyPaddingAccumulatesAcrossAChainAsSwiftUIDoes`; `aLoweredPaddingLayerAgreesWithTheLegacyWrapper` (`fixed(20, 10).padding(4).padding(…)`) |
| 212 | ComponentTests | `widthAndHeightComposeOnAChainedModifier` | `.width(_:).height(_:)` compose on a component | R | F11 | `chainedComponentAmendsComposeTheSameWayUnderBothAuthorities` (4.5) |
| 213 | ComponentTests | `widthAloneDistributesToEachTopLevelChild` | a bare `.width` reaches each member | R | F11 | `aComponentsWidthFramesEachMemberWhereTheLegacyAmendOverwritesIt` (4.1, proposal arm: one frame per member); `aComponentAmendsFrameIsCentredOnlyOnTheAxisItDeclares` (4.3, width-only) |
| 214 | ComponentTests | `heightAloneDistributesToEachTopLevelChild` | a bare `.height` reaches each member | R | F11 | `aComponentAmendsFrameIsCentredOnlyOnTheAxisItDeclares` (4.3, its height arm) |
| 215 | ComponentTests | `chainedPaddingAccumulatesOnAComponentAsItDoesOnAnElement` | chained padding on a component accumulates (OM-E, G4) | R | F11 | `aComponentsPaddingLowersAsAnOrdinaryOneChildContainer` (4.2); `theOrderOfAComponentsDistributingModifiersIsObservableUnderBothAuthorities` (4.4) |
| 216 | ComponentTests | `aComponentsPaddingWrapsEachTopLevelNode` | OM-D: component padding wraps each top-level node (G10/G11: 53×56) | R | F11 | `aComponentsPaddingLowersAsAnOrdinaryOneChildContainer` (4.2) |
| 217 | ComponentTests | `aTwoMemberComponentsPaddingIsAppliedToEachMember` | G2's shape: 120×26, a (8, 8), b (62, 8) | R | F11 | `aComponentsPaddingLowersAsAnOrdinaryOneChildContainer` (4.2, prototype arm C3, probe G2) |
| 218 | ComponentTests | `aModifierOnAComponentAppliesInTheOrderItIsWritten` | OM-E: `.padding(4).width(70)` ≠ `.width(70).padding(4)` | R | F11 | `theOrderOfAComponentsDistributingModifiersIsObservableUnderBothAuthorities` (4.4, arms C4/C5) |
| 219 | ComponentTests | `aComponentsWidthStillOverwritesItsMembersDeclaredWidth` | divergence 48, pinned wrong on purpose: `.width` OVERWRITES each member | D | F11 | **divergence 48's legacy answer** (a `Component`'s `.width` overwrites its members): under the proposal authority it frames each member (`aComponentsWidthFramesEachMemberWhereTheLegacyAmendOverwritesIt`, 4.1; component-distribution G7/G8). Divergence 48 keeps 4.1's legacy arm as its pin until stage 9 |
| 220 | ElementLayoutTests | `theBuilderContributesNoNodesOfItsOwn` | the builder invents no layout node (five nodes for five boxes) | R | F12 | `fixedItemsPackFromTheMainStartAtTheirOwnSizesAndGap` (its column arm's literals: a builder node would be a row inside the column); `aLoweredRowAndColumnAgreeWithTheLegacyContainersOverFixedChildren` |
| 221 | ElementLayoutTests | `paddingEdgesAreNotTransposed` | each `.padding(Edges)` edge lands on the edge it names | R | F12 | `aLoweredPaddingLayerAgreesWithTheLegacyWrapper`; `aNativePaddingInsetsConcreteProposalsExpandsMeasurementsAndOffsetsBaselines` (four distinct insets); the modifier's storage by `ModifierTests` |
| 222 | ElementLayoutTests | `marginEdgesAreNotTransposed` | each `.margin(Edges)` edge lands on its edge | R | F12 | `aMarginLowersAsPaddingOutsideTheItem`; `marginsOffsetEachItemOutsideItsBorderBox` (distinct per-edge margins); the modifier's storage by `ModifierTests` |
| 223 | ElementLayoutTests | `aHiddenChildTakesNoSpace` | a `hidden()` child takes no space | D | F12 | **`display: none` takes no space** (CSS): under the proposal authority `hidden()` keeps its space and paints nothing (`aHiddenChildKeepsItsSpaceUnderTheProposalAuthority`, `LR-DH`; stage-1 probe H1 vs H0/H2, re-run 2026-09-24) |
| 224 | ElementLayoutTests | `alignItemsAndAlignSelfBothReachTheEngine` | `alignItems` and `alignSelf` reach layout; `alignSelf` wins | R | F12 | `alignSelfPlacesOneChildOnTheCrossAxisOfADefiniteContainer` (named as its twin by `LR-DQ` item 2); `alignItemsAndAlignSelfPlaceEachItemOnTheCrossAxis` |
| 225 | ElementLayoutTests | `aNestedLayoutMatchesTheEngineRunDirectly` | the element tree resolves to the rects `computeLayout` gives directly (EP-8) | D | F12 | **the CSS engine as its own oracle** (the last `computeLayout(` call in `Tests/MetalUITests`): the element-to-kernel agreement is `theStageOneCorpusLowersWithNoDiagnosticAndAgreesElementByElement` until stage 9 |
| 226 | ContainerIntegrationTests | `aLegacyRowAndColumnDefaultToNoSpacingWhereHStackAndVStackDefaultToEight` | CN-P 1: legacy `Row`/`Column` gap 0 where `HStack`/`VStack` put 8 | R | F12 | `aLoweredRowOrColumnSpacesByItsDeclaredGapNotTheStackDefault` (divergence 52's proposal side); `aSpacerDefaultsToEightAndAnswersZeroOnItsStacksCrossAxis` |
| 227 | ContainerIntegrationTests | `aLegacyStackOffersFitContentWhereAZStackOffersItsProposal` | CN-P 2: legacy `Stack` offers fit-content where `ZStack` offers its proposal | R | F12 | `aLoweredStackOffersItsProposalWhereTheLegacyStackOffersFitContent` (4.2; stack-algorithms A5, re-run 2026-09-24) |
| 228 | ContainerIntegrationTests | `aLegacyScrollViewTakesItsCrossAxisFromItsParentWhereAProposalScrollViewTakesItsContents` | CN-P 3: legacy viewport takes its parent's cross axis | R | F12 | `divergence54SurvivesTheLoweringBecauseOnlyAScrollViewRecordsAnItem`; `aLoweredScrollViewFillsItsProposalOnTheScrollingAxisWhereTheLegacyViewportHugs` |
| 229 | ModifiedElementTests | `legacyModifierChainsInferOneConcreteType` | MC-L: one concrete `ModifiedElement<Base>`, no `AnyElement`; plus a legacy node count of 4 | T | F13 | **trimmed**: the last four lines (the `.legacy` `Frame`, its render and `nodeCount == 4`, CSS-structure) removed; the type, `layerCount` and outermost-layer assertions stay, authority-free |
| 230 | ModifiedElementTests | `aGenericWrapOverAChainIsIdenticalToTheFlatChain` | MC-B: a generic `.padding` over a chain is observationally the flat chain and the hand-built nested boxes | N | F13 | **N2.1** `aGenericWrapOverAChainIsIdenticalToTheFlatChainUnderTheProposalAuthority` |
| 231 | ModifierCompositionProofTests | `aModifierChainIsIdenticalToHandBuiltNestedBoxes` | MC-B's oracle: a chain is observationally hand-built nested `Box`es | N | F13 | **N2.2** `aModifierChainIsIdenticalToHandBuiltNestedBoxesUnderTheProposalAuthority` |
| 232 | TextMeasureTests | `aTextLeafCarriesAMeasureFunctionWhereABoxDoesNot` | a `Text` leaf carries a CSS `MeasureFunction`, a `Box` does not | D | F14 | **the legacy `MeasureFunction` on a leaf** (stage 9): a lowered `Text` measures through its native leaf closure (`aLoweredTextAgreesWithTheLegacyTextAtItsNaturalWidth`, `aProposalTextBelowItsWidestBrokenLineAnswersTheProposal`) |
| 233 | TextMeasureTests | `aLongLabelInAStretchedColumnWrapsRatherThanOverflowing` | a long label in a narrow stretched column wraps (3 × 16 = 48) | R | F14 | `theBoundsAliasReachesDecorationHitboxesAccessibilityAndTextWrap` (a stretched item's text wraps at the item frame's width); `aProposalTextBreaksInsideAWordAndAnswersItsWidestLineUpToTheProposal` |
| 234 | TextMeasureTests | `aCentringColumnShrinkWrapsItsTextLikeWebKit` | TX-H: a centring column shrink-wraps its text | R | F14 | `aLoweredTextHugsItsWidestLineWhereTheLegacyTextFillsItsContainingBlock`; the "like WebKit" half is **fit-content** (TX-H), as `anAutoCrossSizeInAColumnIsFitContentLikeWebKit`'s row |
| 235 | TextMeasureTests | `aTextPaintsItsBackgroundAndItsGlyphs` | a `Text` paints its background and its glyphs | R | F14 | `aHiddenElementPaintsNothingUnderTheProposalAuthority` (its shown control paints the `Text`'s rect and glyphs); `spriteDestinationsAreThePenPositionPlusTheRasterizersBearings`; `everyBackgroundPaintingSiteHonoursHoverAndFocus` (its `Text` site) |
| 236 | EnvironmentTests | `dynamicTypeSizeChangesNoTextMeasurement` | E16 (EV-I): `dynamicTypeSize` changes no text measurement; positive control a 26pt font | N | F14 | **N3.1** `dynamicTypeSizeChangesNoTextMeasurementUnderTheProposalAuthority` |
| 237 | EnvironmentTests | `aLocaleChangesNoTextMeasurement` | E21 (EV-H): a locale reaches no text measurement; positive control a 26pt font | N | F14 | **N3.2** `aLocaleChangesNoTextMeasurementUnderTheProposalAuthority` |
| 238 | StackElementTests | `stackWritesDisplayAndBothAlignmentFields` | `Stack.init` writes `display: .stack`, `alignItems`, `justifyItems` | T | F15 | **helper re-spelled, assertions unchanged**: `styleOfRoot` reads the element's own `style` (the `StyledElement` requirement `Stack.init` writes) instead of registering it on a `.legacy` `Frame` |
| 239 | StackElementTests | `allNineAlignmentsMapToTheirPairAndTheNineAreDistinct` | the nine `Alignment` cases map to nine distinct (`alignItems`, `justifyItems`) pairs | T | F15 | **helper re-spelled**, as above; the observable twin is `aLoweredStackPlacesFixedChildrenAtAllNineAlignmentsAsTheLegacyStackDoes` |
| 240 | StackElementTests | `stackDefaultsToCentreNotStretch` | a `Stack`'s default alignment is `.center` | T | F15 | **helper re-spelled**, as above |
| 241 | AnimationTests | `everyRegisteringSiteAnimatesItsStyle` | every legacy registering site routes its style through `animated(_:_:for:pass:)` | R | F15 | `everyRegisteringSiteAnimatesItsLoweredRectUnderTheProposalAuthority` (stage 6b's 2.1, carrying the site map; `LR-DQ` item 7: `Box`, `Stack`, a `Component` member, the outermost and inner layers and the lowered `ScrollView` content each pinned under the proposal authority) |
| 242 | FrameDecorationInteractionTests | `aContentShapeOnAFrameLayerInsetsTheFrameBoxAndBeforeItTheChildBox` | OM-J × FR-C: an inset after a frame insets the frame's box, before it the child's; the flexible arm is FR-E's clamp | N | F16 | **N3.3** `aContentShapeOnAFrameLayerInsetsTheFrameBoxAndBeforeItTheChildBoxUnderTheProposalAuthority` (the control, after and before arms and the clicks; the flexible arm is **FR-E's legacy clamp**, deleted as `aLegacyFrameClampsToItsMinimumAndMaximumWithoutGrowingIntoTheProposal`'s row) |
| 243 | FrameDecorationInteractionTests | `aComponentsFrameCarriesTheNewDecorationsAndScopesItsMembers` | CO-U side door: a component's frame carries opacity, clip and border to its members; legacy node counts | N | F16 | **N3.4** `aComponentsFrameCarriesTheNewDecorationsAndScopesItsMembersUnderTheProposalAuthority` (the scopes; the node counts are CSS-structure) |
| 244 | OuterModifierMatrixTests | `everyOuterModifierIsWrapsOrPaintOnlyOrDistributesAsTheMatrixSays` | every outer modifier is the kind the matrix says, each kind by its own witness | N | F16 | **N3.5** `everyOuterModifierIsTheKindTheMatrixSaysUnderTheProposalAuthority` |
| 245 | RootSwitchTests | `aHuggingLegacyRootIsCentredInAProductionWindow` | 3.2: a hugging legacy root is centred in a production window (21, 40); the `.legacy` arm reads divergence 4's (0, 40) | T | F17 | **trimmed**: the `.legacy` arm (its `boxRect(.legacy)` read and `#expect`) removed with divergence 4 (`LR-DG`); the production arm stays, still reddened by M2a/M2b |

**Tally.** 245 rows: **R 112, D 113, N 11, T 5, K 4.** Removed: R + D + N =
**236** `@Test`s — lane 1 **190** (the eighteen files' 191 less `StyleTests`'
4 K, plus `NativeBoundaryTrapTests`' 3), lane 2 **36**, lane 3 **10**. Kept
and edited: 5 T (`legacyModifierChainsInferOneConcreteType`, the three
`StackElementTests`, `aHuggingLegacyRootIsCentredInAProductionWindow`). Added:
**10** (N1.1, N2.1–N2.4, N3.1–N3.5). Files deleted whole: the seventeen of
§1's table other than `StyleTests`.

D by the concept its row leads with (counted by script from the table's
source; a row naming two concepts counts under the first): wrap 19,
percentages 14, automatic minimum 11, weighted shrink 8, border-box floor 6,
`display: none` 5, flex base size 5, the CSS measure cache 5,
`Resolve.swift` 5, sub-one grow 4, intrinsic queries 4, a non-window
containing block 4, the freeze loop 2, divergence 4 2, cross size after
flexing 2, and one each: unequal weights, length `flex-basis`, growth from the
base, `align-content`, `justify-content`'s degenerate cases, baselines, a
maximum on a content-sized axis, TX-H fit-content, the legacy tree's shape,
FR-E's clamp, FR-O's both-axes rule, `CN-N`'s one-cell stack, divergence 48's
legacy answer, the legacy `MeasureFunction` (two rows), the CSS engine as its
own oracle, the CSS engine's entry — 113.

## 5. The count

**1670 − 236 + 10 = 1444** `Test run with 1444 tests in 3 suites passed` at
the stage's close, lane by lane:

| after | tests | derivation |
|---|---|---|
| `41344e5` | 1670 | measured, §1 |
| lane 1 | 1481 | 1670 + 1 (N1.1) − 190 |
| lane 2 | 1449 | 1481 + 4 (N2.1–N2.4) − 36 |
| lane 3 | 1444 | 1449 + 5 (N3.1–N3.5) − 10 |

**Amended by lane 1 (`LR-EM`).** Row 71 became N with a new test (N1.2), so
lane 1 ends at **1482** (1670 + 2 − 190, measured), lane 2 at **1450** and lane 3
at **1445**: **1670 − 236 + 11 = 1445**. The table above is the design's.

Guards stay **78** (no guard is added or removed: none of the retired files
holds `canTypecheck`, checked by grep). Gated tests stay **nine** (none of the
retired tests is `.enabled(if:)`). `AuthorityCoverage.expected` stays **82**
(no retired or trimmed test calls `AuthorityCoverage.record`).

**Name collision.** `theCacheIsActuallyConsulted` is retired from
`MeasureCacheTests`; `MetalUITextTests/ShapingCacheTests.swift` has a test of
the same name, which stays (and `Sources/MetalUIText/ShapingCache.swift:140`
names that one). Every removal check keys on file **and** name.

### 5.1 `Sources/` comments that name a retired test (grep, 2026-09-24)

`LR-EG`. In CSS-only files — **listed, left** for stage 9: `Sources/MetalUILayout/Alignment.swift:193` (`alignContentDistributesLeftoverCrossSpaceAmongLines`); `Sources/MetalUILayout/Alignment.swift:230` (`aStretchedLineChangesWhatItsStretchedItemsFill`); `Sources/MetalUILayout/FlexBaseSize.swift:128` (`anItemWithMinZeroStillGrowsToFitItsPaddingAndBorder`); `Sources/MetalUILayout/FlexBaseSize.swift:53` (`aContentSizedMeasuredLeafsPaddingDoesNotComeOffItsShrinkWeight`); `Sources/MetalUILayout/FlexEngine.swift:1061` (`crossSizeAfterFlexPropagatesToTheLine`); `Sources/MetalUILayout/FlexEngine.swift:1062` (`crossSizeAfterFlexPropagatesToAnAutoContainer`); `Sources/MetalUILayout/FlexEngine.swift:1188` (`crossSizeAfterFlexPropagatesToAnAutoContainer`); `Sources/MetalUILayout/FlexEngine.swift:1230` (`aStretchedLineChangesWhatItsStretchedItemsFill`); `Sources/MetalUILayout/FlexEngine.swift:1824` (`measuringWritesNoLayout`); `Sources/MetalUILayout/FlexEngine.swift:1833` (`measuringWritesNoLayout`); `Sources/MetalUILayout/FlexEngine.swift:1862` (`theCrossAxisQueryReachesAnAutoCrossItem`); `Sources/MetalUILayout/FlexEngine.swift:1930` (`theLeafShortcutMovesNoRectOnSeededRandomTrees`); `Sources/MetalUILayout/FlexEngine.swift:1932` (`measureNodeConsultsTheDepthGuard`); `Sources/MetalUILayout/FlexEngine.swift:1939` (`aChildlessNodeWithNoMeasureFunctionIsNeverACacheMiss`); `Sources/MetalUILayout/FlexEngine.swift:2182` (`aContentSizedMeasuredLeafsPaddingDoesNotComeOffItsShrinkWeight`); `Sources/MetalUILayout/FlexEngine.swift:2211` (`anItemWithNoContentHasNoAutomaticMinimum`); `Sources/MetalUILayout/FlexEngine.swift:2212` (`shrinkIsWeightedByBaseSize`); `Sources/MetalUILayout/FlexEngine.swift:2234` (`automaticMinimumSizeUsesContentSizeNotFlexBasis`); `Sources/MetalUILayout/FlexEngine.swift:2310` (`stretchSubtractsCrossMarginsBeforeClamping`); `Sources/MetalUILayout/FlexEngine.swift:237` (`aContentSizedMeasuredLeafsPaddingDoesNotComeOffItsShrinkWeight`); `Sources/MetalUILayout/FlexEngine.swift:2378` (`theCrossAxisOfTheQueryReachesTheChildToo`); `Sources/MetalUILayout/FlexEngine.swift:2454` (`aClampedMeasuredLeafIsNotFlooredByItsInertPadding`); `Sources/MetalUILayout/FlexEngine.swift:2510` (`stretchWithMaxHeightClampsTheBorderBoxNotTheMarginBox`); `Sources/MetalUILayout/FlexEngine.swift:2527` (`autoCrossNestedContainerMeasuresItsLineLikeWebKit`); `Sources/MetalUILayout/FlexEngine.swift:2650` (`theCrossAxisQueryReachesAnAutoCrossItem`); `Sources/MetalUILayout/FlexEngine.swift:2848` (`reverseContainersApplyMarginsToThePhysicalEdge`); `Sources/MetalUILayout/FlexEngine.swift:603` (`aLineWhoseItemsHaveNoInnerBaseSizeOverflowsInsteadOfShrinking`); `Sources/MetalUILayout/FlexEngine.swift:800` (`aShrunkContainerNeverHandsItsChildANegativeContentBox`); `Sources/MetalUILayout/FlexEngine.swift:824` (`theContainingBlockIsThePaddingBoxNotTheBorderBox`); `Sources/MetalUILayout/FlexEngine.swift:893` (`measuringWritesNoLayout`); `Sources/MetalUILayout/FlexEngine.swift:990` (`gapUsesTheMainAxisOfTheContainer`); `Sources/MetalUILayout/FlexLines.swift:65` (`wrapReverseBreaksLinesInDocumentOrder`); `Sources/MetalUILayout/FlexLines.swift:67` (`wrapReverseStacksLinesFromTheCrossEnd`); `Sources/MetalUILayout/LayoutContext.swift:105` (`aCacheHitRespectsTheContainingBlockWidth`); `Sources/MetalUILayout/LayoutContext.swift:148` (`theCacheIsActuallyConsulted`); `Sources/MetalUILayout/LayoutContext.swift:154` (`aChildlessNodeWithNoMeasureFunctionIsNeverACacheMiss`); `Sources/MetalUILayout/LayoutContext.swift:63` (`layingOutATreeDeeperThanTheLimitTraps`); `Sources/MetalUILayout/LayoutContext.swift:8` (`theCacheIsActuallyConsulted`); `Sources/MetalUILayout/ResolveFlexibleLengths.swift:187` (`freezeLoopAllocationsDoNotGrowWithTheItemsOnTheLine`); `Sources/MetalUILayout/ResolveFlexibleLengths.swift:188` (`freezeLoopMatchesItsAllocatingReferenceBitForBit`); `Sources/MetalUILayout/ResolveFlexibleLengths.swift:218` (`subOneScalingNeverExceedsTheRemainingFreeSpace`); `Sources/MetalUILayout/ResolveFlexibleLengths.swift:252` (`aLineWhoseItemsHaveNoInnerBaseSizeOverflowsInsteadOfShrinking`); `Sources/MetalUILayout/ResolveFlexibleLengths.swift:78` (`fractionalShrinkScalesByRawFactorsNotWeightedOnes`).

In files that outlive stage 9 — **re-pointed by the owning lane** where the
comment states the retired test as a present pin (comment lines only): `Sources/MetalUI/Box.swift:791` (`theSizingModifiersWriteTheirOwnElementsBoxRatherThanWrappingIt`); `Sources/MetalUI/Box.swift:840` (`aFractionSizeResolvesAgainstItsContainingBlock`); `Sources/MetalUI/Box.swift:903` (`theSizingModifiersWriteTheirOwnElementsBoxRatherThanWrappingIt`); `Sources/MetalUI/Component.swift:277` (`aModifierOnAComponentAppliesInTheOrderItIsWritten`); `Sources/MetalUI/Component.swift:321` (`aModifierOnAComponentDistributesToEachTopLevelChild`); `Sources/MetalUI/Component.swift:345` (`aComponentsWidthStillOverwritesItsMembersDeclaredWidth`); `Sources/MetalUI/Component.swift:389` (`everyRegisteringSiteAnimatesItsStyle`); `Sources/MetalUI/Component.swift:416` (`aComponentsFrameCarriesTheNewDecorationsAndScopesItsMembers`); `Sources/MetalUI/Component.swift:563` (`chainedPaddingAccumulatesOnAComponentAsItDoesOnAnElement`); `Sources/MetalUI/EnvironmentValues.swift:94` (`aLocaleChangesNoTextMeasurement`); `Sources/MetalUI/EnvironmentValues.swift:98` (`dynamicTypeSizeChangesNoTextMeasurement`); `Sources/MetalUI/ModifiedElement.swift:176` (`aGenericWrapOverAChainIsIdenticalToTheFlatChain`); `Sources/MetalUI/ModifiedElement.swift:22` (`aModifierChainIsIdenticalToHandBuiltNestedBoxes`); `Sources/MetalUI/ModifiedElement.swift:24` (`aGenericWrapOverAChainIsIdenticalToTheFlatChain`); `Sources/MetalUI/ModifiedElement.swift:78` (`aSingleChildLegacyFrameOverflowsAnOversizedChildOnBothAxes`); `Sources/MetalUI/ModifiedElement.swift:94` (`hiddenAfterASingleChildLegacyFrameStillHidesTheElement`); `Sources/MetalUI/ScrollView.swift:154` (`flexShrinkHoldsAContentNodeOpenOnceItsAutomaticMinimumIsRemoved`); `Sources/MetalUICore/Units.swift:59` (`aFractionSizeResolvesAgainstItsContainingBlock`); `Sources/MetalUILayout/Rounding.swift:43` (`computeLayoutRoundsEveryStoredRect`); `Sources/MetalUILayout/Rounding.swift:44` (`shrinkIsWeightedByBaseSize`).
`Sources/MetalUIText/ShapingCache.swift:140` names `ShapingCacheTests`'
`theCacheIsActuallyConsulted`, which stays, and is not a hit.

## 6. Lanes

Appended by the lanes (spec §6). Lane 1 owns the eighteen files of §1,
`NativeBoundaryTrapTests.swift` and `LoweringLeafTests.swift` (N1.1); lane 2
`FrameSizingTests`, `ComponentTests`, `ElementLayoutTests`,
`ContainerIntegrationTests`, `ModifiedElementTests`,
`ModifierCompositionProofTests`; lane 3 `TextMeasureTests`,
`EnvironmentTests`, `StackElementTests`, `AnimationTests`,
`FrameDecorationInteractionTests`, `OuterModifierMatrixTests`,
`RootSwitchTests`.

### 6.1 Lane 1 — the engine files (2026-09-24, PDT)

**Commits.** `c3dd61b` — N1.1 `anEmptyLoweredStackOrContainerAnswersZeroOnItsAutoAxes`
(`LoweringLeafTests.swift`) and N1.2 `aPaddingWiderThanItsProposalOffersItsChildZeroNeverANegativeSize`
(`NativeLayoutTests.swift`, `LR-EM` item 1), green; `6e2b3c0` — the removal:
seventeen files deleted whole (187 tests; every helper in them was
file-private, so none was moved and none needed a new home — grep for each
top-level declaration found no caller outside its file) and
`NativeBoundaryTrapTests`' three `computeLayout(` tests with the `space`
constant only they used; the commit after it — `Sources/` comment re-points
(`LR-EM` item 6), `LR-EM`, the spec's amendments and this section.
`StyleTests` untouched (K rows 191–194).

**R confirmation.** Every R row's replacement was located (all exist) and its
arm read against the retired test's body — the golden-replacement arms (7a),
the `Lowering*` suites, the kernel suites. **One failed: row 71**
(`aShrunkContainerNeverHandsItsChildANegativeContentBox`, the CSS engine's
`contentBox` `max(0, …)`). Its native analogue, `LayoutTree.paddingProposal`'s
per-axis `max(0, proposal − insets)`, was deleted on `41344e5` and the full
unfiltered suite read **`Test run with 1670 tests in 3 suites passed`** — no
named replacement offers a child a proposal its insets exceed. Row 71 became
N (`LR-EM` item 1) with N1.2.

**Red-before (N tests), on `c3dd61b`**, full unfiltered suite, restored from a
copy, `git status --short` empty after each:

- **M1.1** — `lowerShownLegacyNode`'s empty-container leaf `SizeD(width: 0,
  height: 0)` → `SizeD(width: 1, height: 1)`: `Test run with 1672 tests in 3
  suites failed … with 71 issues`. N1.1's lines: `LoweringLeafTests.swift:666:9:
  Expectation failed: arm.empty == bounds(0, 5, 0, 0)` and `:667:9 … arm.sibling
  == bounds(0, 0, 10, 10)` (8 issues over its four arms; the 30×20 control
  unmoved). Reddened, all 14: `aDeferredAbsoluteBoxLowersAgainstTheWindowOnEveryInsetShape`, `alignItemsAndAlignSelfPlaceEachItemOnTheCrossAxis`, `aLoweredBoxPaddingSitsInsideItsDeclaredSize`, `aLoweredListAgreesWithTheLegacyEngineOnEveryWindowedShape`, `aMinimumFloorsAnItemAndLetsAGrowerGoBelowItsContent`, `anAnimatedItemFieldSnapsItsStructureAndInterpolatesItsValues`, `anEmptyLoweredStackOrContainerAnswersZeroOnItsAutoAxes`, `aPresentationPlaceholderIsDroppedByEveryLoweredContainer`, `aStretchedBranchingTreeRegistersAHandDerivedAmountOfNativeWork`, `aStretchedSingleChildContainerDoesNotStretchItsChild`, `aStyleBorderLowersAsInsetsInsideTheDeclaredSize`, `aZeroBasisGrowerTakesItsShareDownToItsContent`, `aZeroRowHeightLowersWithoutTrappingOrProducingNaN`, `theCentringDefaultOfRowAndColumnStretchesNothing`.
- **M1.2** — `paddingProposal` without its two `Swift.max(0, …)`: **6 issues,
  N1.2 alone** — `NativeLayoutTests.swift:502:5: Expectation failed:
  overflowing.proposals == [ProposedSize(width: 0, height: 0)]`, then `:503`
  (child rect), `:504` (answer), `:507`–`:509` (the one-axis arm). The
  control arm unmoved. The same mutant on `41344e5` reddened nothing (above).

Both N tests render `.proposal` only, so the CSS-engine census's section A is
unchanged by them.

**The removal.** `6e2b3c0`: `swift build --build-system native --build-tests`
0 `error:`, one `warning:` (SwiftPM's deprecation notice); unfiltered `swift test
--build-system native --no-parallel` → **`Test run with 1482 tests in 3 suites
passed`**, `FR-J no-argument frame: succeeded=true` in the log. **1670 + 2 −
190 = 1482.** Removal check by script: for all 190 rows, the name existed in
its file at `41344e5` and no `func <name>(` remains in that file at HEAD (the
seventeen files are gone; `ShapingCacheTests`' own `theCacheIsActuallyConsulted`
is untouched, the check keying on file and name); `NativeBoundaryTrapTests`: 15
tests at `41344e5`, 12 now, the three removed exactly the three rows, and the
twelve survivors' bodies (doc comment through closing brace) byte-identical to
`41344e5`. The file's one comment edit is outside every test body (its
file-scope note now says "the retired `LayoutContextTests`'").
`grep -rn "computeLayout(" Tests --include='*.swift'` now prints one line,
`ElementLayoutTests.swift:309` — lane 2's
`aNestedLayoutMatchesTheEngineRunDirectly`.

**Family mutations**, each on the committed removal (`6e2b3c0`), the file
copied to the scratchpad, edited, full unfiltered `swift test --build-system
native --no-parallel`, restored from the copy, `git status --short` empty after
every one. Every required replacement reddened **except M1j's** (below). The
full reddened set of each is listed; issue counts are the summary line's.

| id | F | spelling applied | issues | required replacement | every test reddened |
|---|---|---|---|---|---|
| M1a | F1 | `LayoutTree.beginLayout`: `precondition(!isLayingOut, "computeLayout re-entered on the same tree")` deleted | 1 | `computeNativeLayoutReenteredFromAMeasureClosureTraps` | `computeNativeLayoutReenteredFromAMeasureClosureTraps` (1) |
| M1b | F1 | `setStyle`: `precondition(!isLayingOut, …)` → `let splitFlag = false; precondition(!splitFlag, …)` | 2 | `setStyleOnALegacyNodeDuringNativeLayoutTraps` | `setStyleOnALegacyNodeDuringNativeLayoutTraps` (1) |
| M1c | F1 | `NativeLayoutRun.enter`: `depth <= NativeLayoutRun.maxDepth` → `depth <= NativeLayoutRun.maxDepth + 1` | 12 | `layingOutANativeTreeDeeperThanTheLimitTraps` | `aChainOf72GridsTraps`, `aLoweredItemChainWithFourWrappersPerLevelOnePastTheNativeDepthLimitTraps`, `aLoweredItemChainWithThreeWrappersPerLevelOnePastTheNativeDepthLimitTraps`, `aPlacementOnlyChainOfCustomLayoutsDeeperThanTheLimitTraps`, `layingOutANativeTreeDeeperThanTheLimitTraps`, `measuringANativeTreeDeeperThanTheLimitTraps` (6) |
| M1d | F2 | `lowerShownLegacyNode`'s `display == .stack` branch: `horizontal: alignmentFactor(style.justifyItems)` → `1 - alignmentFactor(…)` | 42 | `aLoweredStackPlacesFixedChildrenAtAllNineAlignmentsAsTheLegacyStackDoes`, `aStackPlacesAFixedChildAtItsAlignment` | `aHiddenChildKeepsItsSpaceUnderTheProposalAuthority`, `aLoweredStackLaysOutItsAnimatedWidthAndPadding`, `aLoweredStackPlacesFixedChildrenAtAllNineAlignmentsAsTheLegacyStackDoes`, `aStackPlacesAFixedChildAtItsAlignment`, `aStackStretchesByItsItemsAlignmentAndIgnoresTheirFlexFields`, `aStretchedStackChildFillsOnlyItsAutoAxesWithinItsOwnBounds`, `aStretchedStackChildIsNotFlooredByItsPaddingAndBorder`, `theElementBoundsLogRecordsTheRootEveryGroupMemberAndEveryInnerModifierLayer` (8) |
| M1e | F3 | `distributedLegacyItems`: `betweenCount = distribution == .spaceAround ? 2 : 1` → `? 1 : 1` | 11 | `spaceAroundAndSpaceEvenlyLowerToSpacersWhileTheyFit`, `justifyContentDistributesADeclaredMainSizesFreeSpace` | `everyContainerFieldEitherLowersAndAgreesOrIsReportedByName`, `justifyContentDistributesADeclaredMainSizesFreeSpace`, `spaceAroundAndSpaceEvenlyLowerToSpacersWhileTheyFit` (3) |
| M1f | F4 | `arrangeLegacyMainAxis`: `var spacing = gap` → `var spacing = 0.0` | 123 | `fixedItemsPackFromTheMainStartAtTheirOwnSizesAndGap`, `aLoweredContainerSpacesItsChildrenByTheGapOnItsMainAxis` | `aGrowingChildTakesTheRemainingMainSpace`, `aLoweredContainerLaysOutItsAnimatedWidthPaddingAndGap`, `aLoweredContainerPaddingSitsInsideItsDeclaredSize`, `aLoweredContainerSpacesItsChildrenByTheGapOnItsMainAxis`, `aLoweredRowAndColumnAgreeWithTheLegacyContainersOverFixedChildren`, `aLoweredRowOrColumnSpacesByItsDeclaredGapNotTheStackDefault`, `aLoweredTreeMintsTheSameStateSlotsAndAnimatesTheSameWidths`, `aLoweredWindowDispatchesClicksFocusAndKeysToTheSameElements`, `aLoweredWindowPublishesTheSameAccessibilityTree`, `aPresentationPlaceholderIsDroppedByEveryLoweredContainer`, `aProposalElementInsideALoweredContainerLaysOutUnderTheProposalAuthorityAndTrapsUnderTheLegacyOne`, `aReverseContainerPlacesItsChildrenFromTheMainEnd`, `fixedItemsPackFromTheMainStartAtTheirOwnSizesAndGap`, `gapIsPerAxisAndTheRowReadsTheHorizontalOne`, `theDemoFrameMatchesTheValuesRecordedOnMacOS`, `theDemosBodyRowKeepsTheSidebarAtItsDeclaredWidthWhereCSSShrinksIt`, `theStageOneCorpusLowersWithNoDiagnosticAndAgreesElementByElement`, `theWholeDemoReportsExactlyTheFieldsAndSitesLaterStagesOwn` (18) |
| M1g | F5 | `registerLegacyItems`: the `marginInsets` padding registered right after `fixedSize`, inside the aliased item frame, and removed from its last-registered place | 13 | `marginsOffsetEachItemOutsideItsBorderBox`, `aMarginLowersAsPaddingOutsideTheItem` | `aMarginLowersAsPaddingOutsideTheItem`, `marginsOffsetEachItemOutsideItsBorderBox` (2) |
| M1h | F6 | `legacyContainerDiagnostics`: the `flexWrap != .noWrap` line deleted | 5 | `everyContainerFieldEitherLowersAndAgreesOrIsReportedByName`, `aWrapReverseContainerIsReportedByNameAsAWrappingOneIs` | `aContainersReportListsItsContainerRowsBeforeItsEveryNodeRowsAndTrapsOnTheFirst`, `aWrapReverseContainerIsReportedByNameAsAWrappingOneIs`, `everyContainerFieldEitherLowersAndAgreesOrIsReportedByName` (3) |
| M1i | F7 | `measureNative`: `if let cached = run.cache[key]` → `if let cached = (run.cache.isEmpty ? run.cache[key] : nil)` (never hits) | 50 | `aBranchingNativeTreeMeasuresEachLeafOncePerDistinctProposal` | `aBranchingNativeTreeMeasuresEachLeafOncePerDistinctProposal`, `aChainOfMaxDepthNodesOfEveryKindSurvivesAOneMegabyteThread`, `aDifferentRootProposalReMeasuresAndMovesTheRects`, `aGridsWorkAtFiniteProposalsIsOneLeafCallPerDistinctProposal`, `aGridsWorkAtNilIsOneLeafCallPerDistinctProposal`, `aLargeColumnCountCostsTheKernelOnePassPerColumn`, `aListsWorkIsTheSameFor160RowsAsFor40`, `aLoweredBranchingTreeRegistersAndMeasuresAHandDerivedAmountOfNativeWork`, `aLoweredScrollViewRegistersAHandDerivedAmountOfNativeWork`, `aNativeHorizontalScrollViewportLeavesItsWidthUnspecifiedForContent`, `aNativeScrollViewportLeavesItsScrollingAxisUnspecifiedForContent`, `aPaddingWiderThanItsProposalOffersItsChildZeroNeverANegativeSize`, `aProposalTextInAStackIsShapedOncePerDistinctWidth`, `aResetTreeMeasuresItsNewRegistrationsFromScratch`, `aSecondComputeNativeLayoutCallReMeasuresEveryLeaf`, `aStretchedBranchingTreeRegistersAHandDerivedAmountOfNativeWork`, `aSubviewMeasuresOncePerDistinctProposalWithinOneRun`, `fixedSizeModifierWithholdsOnlyItsSelectedAxisFromTheChildProposal`, `nestedStacksUnderAnUnspecifiedCrossProposalDoBoundedWork` (19) |
| M1j | F7 (D) | `planLegacyItems`: `d.flexShrink == 0 && mainAuto` → `d.flexShrink >= 0 && mainAuto` (the design's spelling) | 60 | `aPositiveShrinkLowersAsSwiftUIsCompressionWhateverItsWeight` — **not reddened** (`LR-EM` item 3) | `aFieldLaysOutAndEditsUnderBothAuthorities`, `aGrowInsideAOneChildPaddingFillsTheWrapperWhereCSSLeavesItUngrown`, `aListInTheDifferentialHarnessReachesABoundedWindow`, `aListsWorkIsTheSameFor160RowsAsFor40`, `aLongTextScrollsToKeepTheCaretVisible`, `aLoweredBranchingTreeRegistersAndMeasuresAHandDerivedAmountOfNativeWork`, `aLoweredHorizontalScrollViewIsBoundedByItsParentWhereTheLegacyOneOverflows`, `aLoweredListAgreesWithTheLegacyEngineOnEveryWindowedShape`, `aLoweredScrollViewAgreesWithTheLegacyEngineOnEveryBoundedShape`, `aLoweredScrollViewFillsItsProposalOnTheScrollingAxisWhereTheLegacyViewportHugs`, `aLoweredScrollViewRecordsItsViewportAsItsItemAndKeepsItsSiteReachable`, `aLoweredScrollViewRegistersAHandDerivedAmountOfNativeWork`, `anAlignSelfInsideAOneChildWrapperFillsTheWrapperWhereCSSIgnoresIt`, `anAlignSelfWrapperFillsAnIndefiniteContainerWhereCSSHugs`, `anAppsKeymapBindingWinsOverEditingAndUnclaimedKeysBubble`, `aStackStretchesByItsItemsAlignmentAndIgnoresTheirFlexFields`, `aStretchedBranchingTreeRegistersAHandDerivedAmountOfNativeWork`, `aStretchedItemInsideAHuggingItemFillsItsProposal`, `aTextShrunkByFlexStillWrapsAtItsShrunkWidth`, `aWindowedRowIsPlacedAtItsAbsoluteIndexTimesRowHeight`, `aZeroBasisGrowerTakesItsShareDownToItsContent`, `clickingAFieldFocusesItAndTypingEditsItsText`, `copyCutAndPasteGoThroughThePlatformClipboard`, `divergence54SurvivesTheLoweringBecauseOnlyAScrollViewRecordsAnItem`, `everyProductionRootsDeepestNativeLevelIsMeasured`, `textGoesOnlyToAFocusedField`, `theDemoFrameMatchesTheValuesRecordedOnMacOS`, `theDemoModalDismissesOnAScrimClickAndSwallowsTheWheelUnderBothAuthorities`, `theDemosBodyRowKeepsTheSidebarAtItsDeclaredWidthWhereCSSShrinksIt`, `theWholeDemoReportsExactlyTheFieldsAndSitesLaterStagesOwn` (30) |
| M1j (all sizes) | F7 (D) | the same on every main size: `d.flexShrink >= 0` (no `mainAuto`) | 68 | the same — **not reddened** | `aFieldLaysOutAndEditsUnderBothAuthorities`, `aFrameOverAMultiMemberComponentFramesEachMemberWhereTheLegacyLayerSqueezesThem`, `aFrameOverOneMemberIsUnchanged`, `aGrowInsideAOneChildPaddingFillsTheWrapperWhereCSSLeavesItUngrown`, `aListInTheDifferentialHarnessReachesABoundedWindow`, `aListsWorkIsTheSameFor160RowsAsFor40`, `aLongTextScrollsToKeepTheCaretVisible`, `aLoweredBranchingTreeRegistersAndMeasuresAHandDerivedAmountOfNativeWork`, `aLoweredChainAtTheNativeDepthLimitLaysOut`, `aLoweredHorizontalScrollViewIsBoundedByItsParentWhereTheLegacyOneOverflows`, `aLoweredItemChainWithFourWrappersPerLevelAtTheNativeDepthLimitLaysOut`, `aLoweredItemChainWithThreeWrappersPerLevelAtTheNativeDepthLimitLaysOut`, `aLoweredListAgreesWithTheLegacyEngineOnEveryWindowedShape`, `aLoweredScrollViewAgreesWithTheLegacyEngineOnEveryBoundedShape`, `aLoweredScrollViewFillsItsProposalOnTheScrollingAxisWhereTheLegacyViewportHugs`, `aLoweredScrollViewRecordsItsViewportAsItsItemAndKeepsItsSiteReachable`, `aLoweredScrollViewRegistersAHandDerivedAmountOfNativeWork`, `anAlignSelfInsideAOneChildWrapperFillsTheWrapperWhereCSSIgnoresIt`, `anAlignSelfWrapperFillsAnIndefiniteContainerWhereCSSHugs`, `anAppsKeymapBindingWinsOverEditingAndUnclaimedKeysBubble`, `aStackStretchesByItsItemsAlignmentAndIgnoresTheirFlexFields`, `aStretchedBranchingTreeRegistersAHandDerivedAmountOfNativeWork`, `aStretchedItemInsideAHuggingItemFillsItsProposal`, `aTextShrunkByFlexStillWrapsAtItsShrunkWidth`, `aWindowedRowIsPlacedAtItsAbsoluteIndexTimesRowHeight`, `aZeroBasisGrowerTakesItsShareDownToItsContent`, `clickingAFieldFocusesItAndTypingEditsItsText`, `copyCutAndPasteGoThroughThePlatformClipboard`, `divergence54SurvivesTheLoweringBecauseOnlyAScrollViewRecordsAnItem`, `everyProductionRootsDeepestNativeLevelIsMeasured`, `textGoesOnlyToAFocusedField`, `theCentringDefaultOfRowAndColumnStretchesNothing`, `theDemoFrameMatchesTheValuesRecordedOnMacOS`, `theDemoModalDismissesOnAScrimClickAndSwallowsTheWheelUnderBothAuthorities`, `theDemosBodyRowKeepsTheSidebarAtItsDeclaredWidthWhereCSSShrinksIt`, `theWholeDemoReportsExactlyTheFieldsAndSitesLaterStagesOwn` (36) |
| M1j′ | F7 (D) | **M1j′**: `if d.flexShrink < 0` → `if d.flexShrink < 0 \|\| (d.flexShrink > 0 && d.flexShrink != 1)` (a weight other than 1 reported) | 2 | `aPositiveShrinkLowersAsSwiftUIsCompressionWhateverItsWeight` | `aPositiveShrinkLowersAsSwiftUIsCompressionWhateverItsWeight` (1) |
| M1k | F8 | `lowerPresentation.axis`: `hasTrailing = trailing != .auto` → `hasTrailing = false` | 28 | `aDeferredAbsoluteBoxLowersAgainstTheWindowOnEveryInsetShape` | `aDeferredAbsoluteBoxLowersAgainstTheWindowOnEveryInsetShape`, `aDeferredAbsoluteBoxResolvesItsInsetsAgainstTheWindowAndLeavesTheFlow`, `aDeferredAbsoluteScrimCoversTheWindowAndEscapesTheScrollUnderBothAuthorities`, `anAbsoluteBoxStretchedBelowItsPaddingKeepsItsInsetBoxWhereTheLegacyEngineFloorsIt`, `aPresentationsAccessibilityRecordAndFocusMatchUnderBothAuthorities`, `nestedPresentationsLandOnOneLayerUnderBothAuthorities`, `theDemoModalDismissesOnAScrimClickAndSwallowsTheWheelUnderBothAuthorities`, `theWholeDemoReportsExactlyTheFieldsAndSitesLaterStagesOwn` (8) |
| M1l | F9 | `resolvedLength`: `.rems(let r): Double(r.value) * frame.rootFontSize` → `* 10` | 15 | `aLoweredFixedSizeBoxAgreesWithTheLegacyBoxInEveryObservation` (its `remReport` arm, line 93) | `aDeferredAbsoluteBoxLowersAgainstTheWindowOnEveryInsetShape`, `aLoweredContainerSpacesItsChildrenByTheGapOnItsMainAxis`, `aLoweredFixedSizeBoxAgreesWithTheLegacyBoxInEveryObservation`, `aMarginLowersAsPaddingOutsideTheItem` (4) |

Notes on the table:

- **M1c** reddens every depth-trap test one level past the limit, including
  the grid and lowered-chain ones; the "at the limit" tests stay green.
- **M1i** hung `aChainOfMaxDepthNodesOfEveryKindSurvivesAOneMegabyteThread`'s
  exit-test child: without the cache a 72-level chain is re-measured
  exponentially. The child ran 30 minutes at 99% CPU (`sample` placed it in
  that test's closure) and was killed with `kill`; the run then finished
  (`failed after 1943 seconds with 50 issues`) and counts the test as reddened.
  `aBranchingNativeTreeMeasuresEachLeafOncePerDistinctProposal` reddened on
  (1) `log.calls == log.proposals.count` (all ten leaves) and on
  `measureCalls == 64`, `cacheHits == 51` and `cacheMisses == 90`; the spec's
  "only the `cacheHits` literal" named the test, not its assertions.
  `nativeLayoutWorkIsPerCall` stayed green, as `LR-EL` finding 3 predicted.
  N1.2 is among the reddened (its proposal list is per call, not per distinct
  proposal, once the cache never hits).
- **M1j** as the design spelled it cannot redden
  `aPositiveShrinkLowersAsSwiftUIsCompressionWhateverItsWeight`, measured in
  two spellings (`LR-EM` item 3); **M1j′** reddens it alone. It is F7's D
  sample.
- **M1l** reddened the two rem arms named in `Box.swift`'s re-pointed comment
  (`remReport`, and `PresentationLoweringTests.swift:180`'s `rem` arm).

**MR1 — `Rounding.swift`'s comment re-measured.** `roundStoredRects(tree,
root)` deleted from `computeLayout`, full suite: **2675 issues, 26 tests** —
28 at 1616 (record §48) less exactly the two retired tests the comment named
(`computeLayoutRoundsEveryStoredRect`, `shrinkIsWeightedByBaseSize`), every one
a lowering differential: `aCentringColumnShrinkWrapsItsTextLikeWebKit`, `aComponentsPaddingWrapsEachTopLevelNode`, `aFrameOverAMultiMemberComponentFramesEachMemberWhereTheLegacyLayerSqueezesThem`, `aGrowingChildTakesTheRemainingMainSpace`, `aLoweredContainerPaddingSitsInsideItsDeclaredSize`, `aLoweredPaddingLayerAgreesWithTheLegacyWrapper`, `aLoweredScrollViewsContentKeepsItsNaturalExtent`, `aLoweredTextAgreesWithTheLegacyTextAtItsNaturalWidth`, `aLoweredTextWithADeclaredWidthKeepsItsBoundsAndGlyphOrigin`, `aLoweredWindowDispatchesClicksFocusAndKeysToTheSameElements`, `aLoweredWindowPublishesTheSameAccessibilityTree`, `anAbsoluteTextWrapsAtTheWindowMinusItsInsetWhereTheLegacyEngineWrapsAtTheWindow`, `aPresentationPlaceholderIsDroppedByEveryLoweredContainer`, `aSingleChildLegacyFrameOverflowsAnOversizedChildOnBothAxes`, `aStretchedChildFillsTheLineOnItsCrossAxis`, `aStretchedSingleChildContainerDoesNotStretchItsChild`, `aZeroBasisGrowerTakesItsShareDownToItsContent`, `aZeroShrinkKeepsItsNaturalMainSizeAndOverflows`, `everyContainerFieldEitherLowersAndAgreesOrIsReportedByName`, `everyContainerFieldIsIgnoredOnALoweredLeaf`, `paddingOnALoweredTextPadsItWhereTheLegacyLeafIgnoresIt`, `spaceAroundAndSpaceEvenlyLowerToSpacersWhileTheyFit`, `theBoundsAliasReachesDecorationHitboxesAccessibilityAndTextWrap`, `theDemosBodyRowKeepsTheSidebarAtItsDeclaredWidthWhereCSSShrinksIt`, `theStageOneCorpusLowersWithNoDiagnosticAndAgreesElementByElement`, `theWholeDemoReportsExactlyTheFieldsAndSitesLaterStagesOwn`. The comment is re-pointed to this
figure; MR2 (57 at 1616) names no retired test and was not re-run.

**Comments** (`LR-EM` item 6; `LR-EG`). Re-pointed, comment lines only:
`Rounding.swift` (MR1), `ScrollView.swift` (row 187 → `aZeroShrinkKeepsItsNaturalMainSizeAndOverflows`),
`Box.swift` (`ResolveTests` → the two M1l rem arms; `SizingFixtureTests`
retired), `List.swift` (`SizingFixtureTests` retired). `git diff 41344e5 --
Sources | grep -E '^[-+]' | grep -vE '^(\+\+\+|---)' | grep -vE '^[-+]\s*//'`
prints nothing. Listed, not edited: `FlexEngine.swift` 386, 801, 1851, 1902
(CSS-only, name a deleted file — beyond §5.1's list, which grepped test names);
test-file comments in files lane 1 does not own — `NativeDepthGuardTests` 20,
23; `ScrollViewTests` 53–55 (states the retired row 187 as a present pin);
`ElementGroupTrapTests` 419; `InputDispatchTests` 439; `TextMeasureTests` 318,
342–343 (lane 3); `ModifiedElementTests` 723, 832, 840 (lane 2: the
`malloc_logger` collision with the deleted `FreezeLoopAllocationTests` is now
one-sided). For the Record phase.

**Portable CI figure** (`LR-EM` item 5). `git archive 6e2b3c0` built and run in
`swift:6.4-noble` (`swift build --build-tests`, then `swift test
--no-parallel`): 0 `error:`, 0 `warning:`; summary lines `200 tests`
(`MetalUILayoutTests`), `22` (`MetalUICoreTests`), `3`
(`MetalUICrossPlatformTests`), and `6` (`MetalUISystemFontsTests`, outside
CLAUDE.md's figure). **200 = 388 − 189 + 1**: 190 removed, of which
`freezeLoopAllocationsDoNotGrowWithTheItemsOnTheLine` was already
`#if canImport(Darwin)` (its twin `freezeLoopMatchesItsAllocatingReferenceBitForBit`
was not), plus N1.2. CLAUDE.md's **388 + 22 + 3 → 200 + 22 + 3** at the Record
phase.

**Suite, build systems, guards.** At this section's tree (the removal plus
comment-only `Sources/` edits): native build 0 `error:`, one `warning:`
(SwiftPM's deprecation notice); **`Test run with 1482 tests in 3 suites
passed`**, `FR-J no-argument frame: succeeded=true`; default build system
`swift build --build-tests` 0 `error:`, 0 `warning:`. Guards 78 (no guard file
touched), gated nine (none retired was gated), `AuthorityCoverage.expected` 82.

**Pixels.** `docs/probes/demo-pixels/compare.sh <scratch> 41344e5 6e2b3c0`:
**0 differing and scene identical in all fourteen images**. Controls at
`41344e5`: light vs dark 1048576; default vs modal 1031003; default vs
animation 454895; f0 vs f3 0; preview light vs dark 1048576; chrome legacy vs
proposal 0; distinct 544 / 216; prod default vs modal 491221, distinct
`prod-default-light` 529; indicator rects 0 — record §48 §6.1's `2cc763d`
values, as expected (7a moved no pixel). Re-run against the lane's last code commit, `compare.sh <scratch> 41344e5 a924bcb` (the comment-only `Sources/` edits included): **0 differing, scene identical, all fourteen**. `DemoFrameDeterminismTests` unedited
(`git diff 41344e5 -- Tests/MetalUICrossPlatformTests` empty); it reddened only
under M1f and M1j/M1j (all sizes), as a sibling of the demo's gap and shrink.

**Deferrals.** None of lane 1's rows. Handed on: the listed test-file
comments (Record phase; lanes 2 and 3 for their own files), the portable
figure, and the counts 1450 / 1445 for lanes 2 and 3 (`LR-EM` item 2).

### 6.2 Lane 2 — frames, components, containers, modifier chains (2026-09-24, PDT)

**Commits.** `1448c8e` — N2.1–N2.4 and the T row: N2.1
`aGenericWrapOverAChainIsIdenticalToTheFlatChainUnderTheProposalAuthority`
(`ModifiedElementTests`, beside `observe`), N2.2
`aModifierChainIsIdenticalToHandBuiltNestedBoxesUnderTheProposalAuthority`
(`ModifierCompositionProofTests`, beside its `observe`; `BoxWithoutAnimated`
made Dual), N2.3 `aFramedListBuildsTheRowsTheUnframedListBuildsUnderTheProposalAuthority`
and N2.4 `aScrollViewInsideAFrameKeepsItsViewportAndWheelUnderTheProposalAuthority`
(`FrameSizingTests`), and `legacyModifierChainsInferOneConcreteType` trimmed
(row 229); `983ca74` — the removal of rows 195–231's 36 R/D/N tests, with every
helper only they used; the commit after it — `Sources/` and test-file comment
re-points (comment lines only), `LR-EN`, the spec's amendments and this
section.

**R confirmation.** All twenty R rows' replacements exist and were read
against the retired test's body — the `Lowering*` suites
(`LoweringStackAndLayerTests`, `LoweringComponentTests`, `LoweringItemTests`,
`LoweringBoxModelTests`, `LoweringContainerTests`, `LoweringDistributionTests`,
`LoweringScrollTests`), 7a's golden-replacement arms, `NativeLayoutTests`,
`OuterModifierMatrixTests.legacyPaddingAccumulatesAcrossAChainAsSwiftUIDoes`
and `FrameSizingTests.chainedLegacyFramesAgreeWithSwiftUIsOrderingRules`. None
failed. Two readings worth recording: row 216's content-sized body (G10/G11,
`SoloText().padding(20)` 53×56) has no proposal arm of its own — the fact
(`.padding` wraps each member) is C3/C3a's, on a fixed-size pair; and row 226's
proposal half (`HStack`/`VStack` default 8) is pinned by
`aStackWithoutSpacingPutsEightBetweenViewsAndNothingBesideASpacer` (kept in
`ContainerIntegrationTests`), `aSpacerDefaultsToEightAndAnswersZeroOnItsStacksCrossAxis`
being the `Spacer`'s own minimum.

**The N tests, written green, first run** (at the tree that became `1448c8e`,
filtered to the four, then the full suite): N2.3 and N2.4 passed on their
hand-derived literals. N2.1 and N2.2 read every disagreeing oracle disagreeing
and every observation agreeing **except the node count** —
`ModifiedElementTests.swift:621:9: Expectation failed: chain.nodeCount ==
oracle.nodeCount` (generic: nodes 7 vs 8; flat: nodes 7 vs 8) and
`ModifierCompositionProofTests.swift:861:5: … chain.nodeCount →  7, oracle.nodeCount
→ 8`. The frame layer lowers to one native frame, the oracle's
`Box(style: frameStyle(…))` to an overlay inside a fixed frame; the comparison
and its disagreeing `#require` are dropped (`LR-EN` item 1). Then **`Test run
with 1486 tests in 3 suites passed`** (1482 + 4), `FR-J no-argument frame:
succeeded=true`.

- **N2.3's literal**, derived from `List.visibleRange` before the run: the
  lowered viewport fills its proposal on the scrolling axis (600), offset 0,
  `rowHeight` 40, `overscan` 2 → `⌊0/40⌋ − 2 … ⌈600/40⌉ + 2` clamped into
  `0..<40` → rows **0…16**. The control is the cold frame, which builds all
  forty (`MP-I`).
- **N2.4's literals**, derived by hand (the doc comment carries the
  arithmetic): A region (75, 50) 80×100, c (75, 50) 80×400, offset **37**; F
  the same; H (85, 70) 80×100, c (85, 70), 37; G (65, 80) 100×40, c (65, 80)
  400×40, 37. A scrolls where the legacy frame's viewport hugged its content
  and did not, so the retired A-vs-F control is replaced by a 50pt content
  that fits (`LR-EN` item 5). Each arm's diagnostics pre-flight read an empty
  report.

**Red-before (N tests and the T row), on `1448c8e`**, full unfiltered suite,
restored from a copy, `git status --short` empty after each:

- **M2.1** — `ModifiedElement._wrap` (chain receiver): `copy.inner.append(copy.outermost)` deleted (replace, not append): 70 issues. Reddened: `aChainsOuterLayerScopesContainTheLayersInsideIt`, `aDeclaredAXNodeIsEmittedByEveryConformerThatRegistersHandlers`, `aDisabledElementPublishesDisabledWithTheGatedActionsAndRefusesEveryRequest`, `aGenericWrapOverAChainIsIdenticalToTheFlatChain`, `aGenericWrapOverAChainIsIdenticalToTheFlatChainUnderTheProposalAuthority`, `aHiddenInnerModifierLayerSkipsPaintAndHitsPerLayer`, `aHiddenInnerModifierLayerSuppressesEverythingInsideIt`, `aHiddenOneNodeFrameLayerPublishesNothingToAnAccessibilityClient`, `aLayerAddedAtRunTimeIsAdoptedByTheNewOutermostLayer`, `aLayerAddedAtRunTimeKeepsTheOutermostAccessibilityNodeAndRepublishesTheWrappedOne`, `aLegacyChainsBackgroundCoversTheBoxAtThePointItWasWritten`, `aLoweredPaddingLayerAgreesWithTheLegacyWrapper`, `aModifierChainIsIdenticalToHandBuiltNestedBoxes`, `aModifierChainIsIdenticalToHandBuiltNestedBoxesUnderTheProposalAuthority`, `aPaddedClickTargetIsHittableInItsPaddingWhereSwiftUIIsNot`, `aSingleChildLegacyFrameOverflowsAnOversizedChildOnBothAxes`, `aSizingModifierWrittenAfterAFrameIsReportedOnTheFrameLayer`, `addingALayerAtRunTimeResetsTheWrappedElementsState`, `anIDAfterAChainsLastWrapperNamesTheOutermostLayer`, `chainedFramesRemainConcreteAndNestTheirLayoutNodes`, `chainedLegacyFramesAgreeWithSwiftUIsOrderingRules`, `chainedPaddingCreatesNestedWrappers`, `decorationSubstitutionReachesTheElementOnBoxAndStack`, `everyBackgroundPaintingSiteAnimatesItsColour`, `everyBackgroundPaintingSiteFadesItsResolvedHoverAndFocusColour`, `everyBackgroundPaintingSiteHonoursHoverAndFocus`, `everyDecorationPaintingSiteDrawsItsBorder`, `everyDecorationPaintingSiteHonoursTheBorderHoverAndFocusChain`, `everyHandlerRegisteringSiteHonoursAllowsHitTesting`, `everyHandlerRegisteringSiteSuppressesItsClickWhenDisabled`, `everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn`, `everyRegisteringSiteAnimatesItsLoweredRectUnderTheProposalAuthority`, `everyRegisteringSiteAnimatesItsStyle`, `hiddenAfterASingleChildLegacyFrameStillHidesTheElement`, `legacyModifierChainsInferOneConcreteType`, `legacyPaddingAccumulatesAcrossAChainAsSwiftUIDoes`, `modifierOrderChangesSizeAndPlacementAsSwiftUIDoes`, `onClickIsLiveOnEveryConformerThatCanRegisterOne`, `stateSurvivesFramesUnderALegacyModifierChain`, `theElementBoundsLogRecordsTheRootEveryGroupMemberAndEveryInnerModifierLayer`, `theStageOneCorpusLowersWithNoDiagnosticAndAgreesElementByElement` (41).
- **M2.2** — `ModifiedElement.paintLayer`: an inner layer at recursion depth `d` paints layer `inner.count − 1 − d`'s decoration at that layer's bounds and id (inner fills innermost-first): 6 issues. Reddened: `aGenericWrapOverAChainIsIdenticalToTheFlatChain`, `aGenericWrapOverAChainIsIdenticalToTheFlatChainUnderTheProposalAuthority`, `aModifierChainIsIdenticalToHandBuiltNestedBoxes`, `aModifierChainIsIdenticalToHandBuiltNestedBoxesUnderTheProposalAuthority` (4).
- **M2.3** — `List.visibleRange`: `return first..<last` → `return 0..<count` (windowing off): 65 issues. Reddened: `aFocusedListRowSurvivesABoundedExcursionButNotALongerOne`, `aFractionalOffsetRoundsFirstDownAndLastUp`, `aFramedListBuildsTheRowsTheUnframedListBuildsUnderTheProposalAuthority`, `aListBuildsOnlyTheRowsIntersectingTheViewportPlusOverscan`, `aListInTheDifferentialHarnessReachesABoundedWindow`, `aListInsideADeferredIgnoresTheEscapedScrollersOffset`, `aListNotAtTheScrollersContentOriginWindowsAgainstTheWrongRows`, `aListRowsStateSurvivesABoundedExcursionButNotALongerOne`, `aListsSceneAndHitboxesAreUnchangedByTheGroup`, `aListsWorkIsTheSameFor160RowsAsFor40`, `aLoweredListAgreesWithTheLegacyEngineOnEveryWindowedShape`, `aScrolledListPublishesItsLogicalCountAndItsRealizedRowsWithTheirIndices`, `aScrolledListsSpacerDoesNotShrinkUnderPadding`, `aVerticalListInsideAHorizontalScrollViewBuildsEveryRow`, `aVirtualizedListsLogicalCountDiffersFromItsRealizedRowCount`, `aWindowedListStillReportsItsFullContentHeight`, `aWindowedRowIsPlacedAtItsAbsoluteIndexTimesRowHeight`, `activatingBeforeTheFirstFramePublishesNoRowsUntilTheWindowIsBounded`, `anOffScreenListRowsModelReadIsNotTracked`, `anOffsetPastTheEndClampsToTheTailInsteadOfRenderingNothing`, `combinationReachesButtonsInsideAListAndAClickableListKeepsItsRows`, `scrollingAListPostsBoundedNotificationsAndBuildsOncePerFrame`, `theListsSpacerIsANodeNotAnElement`, `theResidentEntrySetStaysBoundedWhileScrolling10kRows` (24).
- **M2.4** — `ScrollChrome.clamp(offset:content:viewport:)` returns 0: 82 issues. Reddened: `aClippedBoxInsideAScrolledScrollViewClipsWhereItPaints`, `aDeferredAbsoluteScrimCoversTheWindowAndEscapesTheScrollUnderBothAuthorities`, `aDeferredBoxInsideARealScrolledScrollViewDoesNotSlideWithTheScroll`, `aDisabledScrollViewStillScrollsOnTheWheel`, `aLoweredListAgreesWithTheLegacyEngineOnEveryWindowedShape`, `aNestedScrollViewInsideAScrolledOneGetsAnEmptyContentMask`, `aNestedScrollViewInsideAScrolledOneReceivesTheWheelWhereItPaints`, `aNodeInsideAScrolledScrollViewReportsItsOnScreenFrame`, `aProposalScrollViewClampsAStoredOffsetPastTheEndAndWritesItBack`, `aProposalScrollViewClampsAnOffsetPastItsContentEndOnPrepaint`, `aProposalScrollViewsIndicatorFadesOnTheSameRampAndIsClippedLikeTheContent`, `aScrollRegionInsideAllowsHitTestingFalseIsStillRegistered`, `aScrollViewInsideAFrameKeepsItsViewportAndWheelUnderTheProposalAuthority`, `aScrollViewInsideASingleChildLegacyFrameKeepsItsViewportAndWheel`, `aStoredOffsetPastTheEndIsClampedWhenItIsRead`, `aWindowedRowIsPlacedAtItsAbsoluteIndexTimesRowHeight`, `anAbsoluteBoxInsideAScrollViewIsStillClippedAndScrolledByIt`, `rawOffsetPublishedDuringRequestLayoutCanExceedTheClampedRange`, `scrollingAListPostsBoundedNotificationsAndBuildsOncePerFrame`, `scrollingPastTheEndDoesNotBankAnOffsetTheUserMustUnwind`, `theHorizontalIndicatorLiesAlongTheBottomOfItsViewport`, `theIndicatorIsClippedByTheViewportsRoundedCornerWithoutScrollingWithIt`, `theIndicatorIsTheLastPrimitiveInTheScene`, `theOffsetClampsToTheScrollableRange`, `theThumbReachesTheEndOfItsTrackAtMaximumOffset`, `theTwoScrollElementsShareOneChromeImplementation`, `twoProposalScrollViewsInOneOverlayKeepSeparateOffsets` (27).
- **T (both halves)** — `ModifiedElement.style`: getter and setter both on `inner[0]` when `inner` is non-empty: 7 issues. Reddened: `aDeclaredAXNodeIsEmittedByEveryConformerThatRegistersHandlers`, `everyBackgroundPaintingSiteFadesItsResolvedHoverAndFocusColour`, `everyBackgroundPaintingSiteHonoursHoverAndFocus`, `everyDecorationPaintingSiteDrawsItsBorder`, `hiddenAfterASingleChildLegacyFrameStillHidesTheElement` (5).
- **T (setter only)** — `ModifiedElement.style`: setter on `inner[0]` when `inner` is non-empty, getter on `outermost`: 9 issues. Reddened: `aDeclaredAXNodeIsEmittedByEveryConformerThatRegistersHandlers`, `everyBackgroundPaintingSiteFadesItsResolvedHoverAndFocusColour`, `everyBackgroundPaintingSiteHonoursHoverAndFocus`, `everyDecorationPaintingSiteDrawsItsBorder`, `everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn`, `hiddenAfterASingleChildLegacyFrameStillHidesTheElement`, `legacyModifierChainsInferOneConcreteType` (7).

N2.1's red line under M2.1: `ModifiedElementTests.swift:529:9: Expectation
failed: flatValue.layerCount == 3 && genericValue.layerCount == 3` (the
`#require` before any observation). N2.2's: `ModifierCompositionProofTests.swift:865:5:
Expectation failed: chain.leafID == oracle.leafID`, then `:867` (hitboxes),
`:868` (rects). Under M2.2: `ModifiedElementTests.swift:630:9: Expectation
failed: chain.rects == oracle.rects` (generic and flat) and
`ModifierCompositionProofTests.swift:868:5: … chain.rects == oracle.rects`.
Under M2.3: `FrameSizingTests.swift:565:5: Expectation failed: bare.warm ==
window` and `:566:5 … framed.warm == window`. Under M2.4:
`FrameSizingTests.swift:1503:9: Expectation failed: a.offset != fits.offset`
(the control `#require`). The T row under the setter-only spelling:
`ModifiedElementTests.swift:316:5: Expectation failed: leafChain.style.size.width
== .length(.pixels(70))`; the both-halves spelling leaves it green (`LR-EN`
item 3). M2.3 ran 515 s (the 10 000-row `List` tests build every row).

**The removal.** `983ca74`: `FrameSizingTests` 12, `ComponentTests` 13,
`ElementLayoutTests` 6, `ContainerIntegrationTests` 3, `ModifiedElementTests` 1,
`ModifierCompositionProofTests` 1 — **36**. Helpers whose only callers were
retired tests went with them (grep of every top-level declaration in the six
files): `widthInRow`, `nodeCount`, `TwoMarks`, `GrowingPair`, `StretchingPair`,
`DeprecatedPercentSpellings` and its three wrappers, `insets` (`FrameSizingTests`);
`TwoAutoLeaves`, `SoloText`, `SoloLeaf`, `PairLeaves`, `outerFootprint`
(`ComponentTests`); `Fixture`, which held the last `computeLayout(` call
(`ElementLayoutTests`); `LegacyMark`, `gap` (`ContainerIntegrationTests`).
Each Dual fixture's legacy branch stays (spec §6). `swift build --build-system
native --build-tests` 0 `error:`, one `warning:` (SwiftPM's deprecation
notice); **`Test run with 1450 tests in 3 suites passed`**, `FR-J no-argument
frame: succeeded=true`. **1482 + 4 − 36 = 1450**, `LR-EM` item 2's figure.

**Removal check by script** (record §49 §4 rows 195–231 read by script): for
each of the 36 R/D/N rows the name existed in its file at `41344e5` and no
`func <name>(` remains there; the T row exists and its seven kept
`#expect`/`#require` lines are byte-identical to `41344e5`, the one dropped
line being `#expect(frame.tree.nodeCount == 4, …)`; every surviving `@Test`
body in the six files other than the T row and the four N tests equals its
`41344e5` text (`grep -cE '^\s*@Test'`: `ComponentTests` 26 → 13,
`ContainerIntegrationTests` 25 → 22, `ElementLayoutTests` 18 → 12,
`FrameSizingTests` 16 → 6 with N2.3/N2.4, `ModifiedElementTests` 7 → 7 and
`ModifierCompositionProofTests` 11 → 11, one retired and one N each). **`grep -rn "computeLayout(" Tests --include='*.swift'`** (`.build`
excluded) **prints nothing** — exit criterion 2 holds from this lane on.

**Family mutations**, each on the committed removal (`983ca74`), the file
copied to the scratchpad, edited, full unfiltered `swift test --build-system
native --no-parallel`, restored from the copy, `git status --short` empty after
every one. Every required replacement reddened; the full reddened set of each
is listed (issue counts are the summary line's):

| id | F | spelling applied | issues | required replacement | every test reddened |
|---|---|---|---|---|---|
| M2a | F10 | `LayoutTree.placeNative`, `.frame` case: both `* alignment.horizontalFactor` / `* alignment.verticalFactor` → `* 0` | 1385 | `aLoweredFixedFrameLayerAgreesWithTheLegacyFrameOverAFixedChild` | `aBackgroundBeforeOrAfterALegacyFrameFillsTheBoxItWasWrittenOnAsSwiftUIDoes`, `aCellWhoseSlotEqualsItsAnswerIsPlacedAtTheProposalItWasMeasuredAt`, `aClickNeedsTheTargetEnabledAtPressAndAtRelease`, `aComponentAmendsFrameIsCentredOnlyOnTheAxisItDeclares`, `aComponentInsideAComponentFlattensThroughBothLevels`, `aComponentsContentFlattensIntoItsParent`, `aComponentsWidthFramesEachMemberWhereTheLegacyAmendOverwritesIt`, `aDeclaredSizeBelowThePaddingKeepsTheFrameWhereCSSFloorsTheBox`, `aDefaultSpacerAndAGreedyFrameThroughTheElementAPI`, `aDeferredAbsoluteBoxLowersAgainstTheWindowOnEveryInsetShape`, `aDeferredAbsoluteScrimCoversTheWindowAndEscapesTheScrollUnderBothAuthorities`, `aDisabledClickTargetPassesTheClickToWhatIsUnderIt`, `aDisabledTargetIsNeitherHoveredNorPressed`, `aFiniteProposalServesGroupsWithSharesAndCommits`, `aFlexibleFrameElementGrowsToItsProposalThroughTheElementAPI`, `aFocusRingAndHoverBorderDrawOnTheLayerTheyAreWrittenOnAroundAFrame`, `aFrameLayerLowersFromItsAnimatedStyleForWhatStyleCarries`, `aFrameLayersClipAndBorderBoundTheChildTheFrameCannotShrink`, `aFrameOverAMultiMemberComponentFramesEachMemberWhereTheLegacyLayerSqueezesThem`, `aFrameOverOneMemberIsUnchanged`, `aFrameOverSeveralMembersStillPlansEachMembersItemFields`, `aGrowingChildTakesTheRemainingMainSpace`, `aGrownReverseContainerPlacesFromTheMainEndOfItsItemFrame`, `aGrownUnsizedSpaceDistributionContainerIsReported`, `aHiddenClickTargetPassesTheClickToWhatIsUnderIt`, `aHiddenElementInsideAnyElementIsHiddenUnderTheProposalAuthority`, `aHiddenFrameLayerLowersAsIfShown`, `aHiddenInnerModifierLayerSkipsPaintAndHitsPerLayer`, `aHoveredBoxPaintsItsHoverBackground`, `aLabelledClickTargetOnAFrameLayerPublishesTheFrameBoxWhileItsHitRegionIsInset`, `aLegacyFramePlacesItsChildAtEachOfTheNineAlignments`, `aLoweredContainerPaddingSitsInsideItsDeclaredSize`, `aLoweredFixedFrameLayerAgreesWithTheLegacyFrameOverAFixedChild`, `aLoweredFlexibleFrameLayerTakesSwiftUIsAnswerWhereTheLegacyFrameClamps`, `aLoweredScrollViewAgreesWithTheLegacyEngineOnEveryBoundedShape`, `aLoweredScrollViewFillsItsProposalOnTheScrollingAxisWhereTheLegacyViewportHugs`, `aLoweredSizedContainerPlacesItsContentByJustifyContentAndAlignItems`, `aLoweredStackPlacesFixedChildrenAtAllNineAlignmentsAsTheLegacyStackDoes`, `aLoweredWindowDispatchesClicksFocusAndKeysToTheSameElements`, `aLoweredWindowPublishesTheSameAccessibilityTree`, `aMarginLowersAsPaddingOutsideTheItem`, `aMouseMovedEventMakesTheBoxUnderItHoveredOnTheNextFrame`, `aNativeFrameClampsItsProposalAndResponseToMinimumAndMaximum`, `aNativeFrameForwardsAnOptionalAxisAndAdoptsThatChildResponse`, `aNativeFramePlacesItsChildAtTheRequestedAlignment`, `aNativeFrameProposesItsFixedAxesAndCentresTheChildResponse`, `aNativeFrameUsesIdealDimensionsOnlyForUnspecifiedAxes`, `aNativeFrameWithInfiniteMaximumExpandsToItsFiniteProposal`, `aNativeNodeRegisteredTwiceTraps`, `aNestedHandlerWinsOverItsContainingStackToo`, `aNestedTextEmitsItsDeclaredAXNodeAtItsAbsoluteBounds`, `aNilAxisFrameLayerUnderAStretchingContainerIsStretched`, `aPresentationPlaceholderIsDroppedByEveryLoweredContainer`, `aPresentationsAccessibilityRecordAndFocusMatchUnderBothAuthorities`, `aReverseContainerOverflowsTowardItsMainStart`, `aReverseContainerPlacesItsChildrenFromTheMainEnd`, `aReverseDirectionPacksItemsFromTheMainEnd`, `aScrollViewInsideAFrameKeepsItsViewportAndWheelUnderTheProposalAuthority`, `aSizingModifierWrittenAfterAFrameIsReportedOnTheFrameLayer`, `aStackCentresOnTheCrossAxisWhereABoxStretches`, `aStackHugsItsLargestChildInsideARowAndAroundOne`, `aStackPlacesAFixedChildAtItsAlignment`, `aStretchedChildFillsTheLineOnItsCrossAxis`, `aStretchedContainersContentSitsByItsOwnAlignment`, `aStretchedUnsizedSpaceDistributionContainerIsReported`, `aVanishingIfBetweenPressAndReleaseClicksTheTrailingSibling`, `activeSurvivesAFrameBoundary`, `alignItemsAndAlignSelfPlaceEachItemOnTheCrossAxis`, `alignSelfPlacesOneChildOnTheCrossAxisOfADefiniteContainer`, `anAlignSelfInsideAOneChildWrapperFillsTheWrapperWhereCSSIgnoresIt`, `anAmendedComponentsMemberItemFieldsAreConsumedAndPlanned`, `anExplicitAnyElementIsStillAcceptedAsAChild`, `anIdealFrameLowersUnderTheProposalAuthorityAndStillTrapsUnderTheLegacyOne`, `anInfiniteProposalIsAnsweredWithInfinity`, `builderFixedSizeWithholdsOnlyItsSelectedAxisFromTheChildProposal`, `chainedComponentAmendsComposeTheSameWayUnderBothAuthorities`, `chainedLegacyFramesAgreeWithSwiftUIsOrderingRules`, `chainedNativeFramesPreserveTheirDeclarationOrder`, `changingADisabledOrEnvironmentValueKeepsTheStateBelowTheWriter`, `childrenAreRegisteredAndLaidOutInSourceOrder`, `clippedAlsoClipsTheHitboxesInsideIt`, `columnStacksOnTheAxisRowDoesNot`, `everyHandlerRegisteringSiteSuppressesItsClickWhenDisabled`, `focusOutranksHoverWhenAnElementIsBoth`, `gapIsPerAxisAndTheRowReadsTheHorizontalOne`, `gridAndGridRowLayOutAsTheProbeReadsThroughTheElementAPI`, `justifyContentDistributesADeclaredMainSizesFreeSpace`, `marginsOffsetEachItemOutsideItsBorderBox`, `modifierOrderChangesSizeAndPlacementAsSwiftUIDoes`, `nativeClipMasksOverflowingContentToItsOuterFrame`, `nativeCompositionUsesColumnFrameAndPaddingProposals`, `nativeModifierChainsRemainConcreteAndWrapInDeclarationOrder`, `overlayAndBackgroundContentIsPlacedAtThePrimarysSize`, `proposalLayoutFrameUsesTheTypedProposalWrapper`, `theCentringDefaultOfRowAndColumnStretchesNothing`, `theDemoFrameMatchesTheValuesRecordedOnMacOS`, `theDemoModalDismissesOnAScrimClickAndSwallowsTheWheelUnderBothAuthorities`, `theGateReadsTheEnvironmentValueNotTheModifier`, `theOrderOfAComponentsDistributingModifiersIsObservableUnderBothAuthorities`, `theStageOneCorpusLowersWithNoDiagnosticAndAgreesElementByElement`, `theStageOneCorpusPinsEveryKnownDisagreementWithItsProbeArm`, `theWholeDemoReportsExactlyTheFieldsAndSitesLaterStagesOwn` (102) |
| M2b | F10 (D) | `lowerLegacyLayer`'s `framed`: `maxWidth:`/`maxHeight:` → `nil` (the greedy maximum dropped: the frame clamps as the legacy one) | 12 | `aLoweredFlexibleFrameLayerTakesSwiftUIsAnswerWhereTheLegacyFrameClamps` | `aFrameLayerLowersItsMinimaAndFiniteMaximaFromItsAnimatedStyle`, `aLoweredFlexibleFrameLayerTakesSwiftUIsAnswerWhereTheLegacyFrameClamps`, `aRealAppKitResizeDirtiesTheWindowAndTheNextFrameReflows`, `resizingTheWindowDirtiesItAndTheNextFrameLaysOutAtTheNewSize`, `theStageOneCorpusPinsEveryKnownDisagreementWithItsProbeArm` (5) |
| M2c′ | F11 | `loweredComponentFrame`: `let framed = frame.requestNativeFrame(child: child, …)` → `let framed = child` (no frame per member; the design spelling traps, `LR-EN` item 2) | 20 | `aComponentsWidthFramesEachMemberWhereTheLegacyAmendOverwritesIt` | `aComponentAmendsFrameIsCentredOnlyOnTheAxisItDeclares`, `aComponentsWidthFramesEachMemberWhereTheLegacyAmendOverwritesIt`, `anAmendedComponentsMemberItemFieldsAreConsumedAndPlanned`, `chainedComponentAmendsComposeTheSameWayUnderBothAuthorities`, `everyRegisteringSiteAnimatesItsLoweredRectUnderTheProposalAuthority`, `theOrderOfAComponentsDistributingModifiersIsObservableUnderBothAuthorities` (6) |
| M2d | F11 | `StyledComponent.requestGroupLayout`: under `.proposal` the per-member `.wrap` skipped and every wrap applied once around the whole body (`lowerLegacyNode(style, …, children: body, site: .component)`) | 5 | `aComponentsPaddingLowersAsAnOrdinaryOneChildContainer` | `aComponentsPaddingLowersAsAnOrdinaryOneChildContainer`, `theOrderOfAComponentsDistributingModifiersIsObservableUnderBothAuthorities` (2) |
| M2e | F12 | `lowerShownLegacyNode`: `spacing: arrangement.spacing` → `spacing: isRow ? nil : arrangement.spacing` | 356 | `aLoweredRowOrColumnSpacesByItsDeclaredGapNotTheStackDefault` | `aComponentAmendsFrameIsCentredOnlyOnTheAxisItDeclares`, `aComponentInsideAComponentFlattensThroughBothLevels`, `aComponentsContentFlattensIntoItsParent`, `aComponentsPaddingLowersAsAnOrdinaryOneChildContainer`, `aComponentsWidthFramesEachMemberWhereTheLegacyAmendOverwritesIt`, `aDeclaredMainSizeIsNeitherShrunkNorFlooredByContentOrPadding`, `aDeferredScrollViewNestedInAnotherEscapesItsClipForHitTesting`, `aGridInsideALoweredContainerIsNeverStretchedWhereItsRecordedSiblingIs`, `aGridsColumnWidthReachesAGrowingChildInsideALoweredCell`, `aGrowFactorSumBelowOneStillFillsTheLine`, `aGrowInsideAOneChildPaddingFillsTheWrapperWhereCSSLeavesItUngrown`, `aGrowingChildTakesTheRemainingMainSpace`, `aGrownReverseContainerPlacesFromTheMainEndOfItsItemFrame`, `aGrownUnsizedSpaceDistributionContainerIsReported`, `aLoweredBranchingTreeRegistersAndMeasuresAHandDerivedAmountOfNativeWork`, `aLoweredContainerLaysOutItsAnimatedWidthPaddingAndGap`, `aLoweredContainerPaddingSitsInsideItsDeclaredSize`, `aLoweredContainerSpacesItsChildrenByTheGapOnItsMainAxis`, `aLoweredHorizontalScrollViewIsBoundedByItsParentWhereTheLegacyOneOverflows`, `aLoweredRowAndColumnAgreeWithTheLegacyContainersOverFixedChildren`, `aLoweredRowOrColumnSpacesByItsDeclaredGapNotTheStackDefault`, `aLoweredRowOverflowsWhereTheLegacyRowShrinksItsChildren`, `aLoweredSizedContainerPlacesItsContentByJustifyContentAndAlignItems`, `aLoweredWindowDispatchesClicksFocusAndKeysToTheSameElements`, `aLoweredWindowPublishesTheSameAccessibilityTree`, `aMarginLowersAsPaddingOutsideTheItem`, `aMaximumLowersOnAGreedyOrSizedAxisAndIsReportedElsewhere`, `aMinimumFloorsAnItemAndLetsAGrowerGoBelowItsContent`, `aNegativeMarginOverlapsItsSibling`, `aNestedTextEmitsItsDeclaredAXNodeAtItsAbsoluteBounds`, `aNilAxisFrameLayerUnderAStretchingContainerIsStretched`, `aPositiveShrinkLowersAsSwiftUIsCompressionWhateverItsWeight`, `aReverseContainerOverflowsTowardItsMainStart`, `aReverseContainerPlacesItsChildrenFromTheMainEnd`, `aReverseDirectionPacksItemsFromTheMainEnd`, `aScrollViewInsideAFrameKeepsItsViewportAndWheelUnderTheProposalAuthority`, `aScrollViewOfTextDoesNotShrinkItsContentToTheViewport`, `aStackHugsItsLargestChildInsideARowAndAroundOne`, `aStretchedChildFillsTheLineOnItsCrossAxis`, `aStretchedContainersContentSitsByItsOwnAlignment`, `aStretchedItemIsClampedByItsOwnMinimumAndMaximum`, `aStretchedUnsizedSpaceDistributionContainerIsReported`, `aStyleBorderLowersAsInsetsInsideTheDeclaredSize`, `aZeroBasisGrowerTakesItsShareDownToItsContent`, `aZeroShrinkKeepsItsNaturalMainSizeAndOverflows`, `alignItemsAndAlignSelfPlaceEachItemOnTheCrossAxis`, `anAnimatedItemFieldSnapsItsStructureAndInterpolatesItsValues`, `anAutoMarginLowersAsZero`, `anEmptyLoweredStackOrContainerAnswersZeroOnItsAutoAxes`, `anExplicitAnyElementIsStillAcceptedAsAChild`, `autoMainSizesSumTheirContentAndAGrowerIsFlooredByIt`, `chainedComponentAmendsComposeTheSameWayUnderBothAuthorities`, `chainedLegacyFramesAgreeWithSwiftUIsOrderingRules`, `childrenAreRegisteredAndLaidOutInSourceOrder`, `columnStacksOnTheAxisRowDoesNot`, `divergence54SurvivesTheLoweringBecauseOnlyAScrollViewRecordsAnItem`, `equalGrowersShareTheLineAndAMaximumCapsItsGrower`, `everyContainerFieldEitherLowersAndAgreesOrIsReportedByName`, `everyRegisteringSiteAnimatesItsLoweredRectUnderTheProposalAuthority`, `fixedItemsPackFromTheMainStartAtTheirOwnSizesAndGap`, `gapIsPerAxisAndTheRowReadsTheHorizontalOne`, `growingSiblingsShareTheSurplusEquallyWhereCSSAddsItToTheirBases`, `legacyPaddingAccumulatesAcrossAChainAsSwiftUIDoes`, `marginsOffsetEachItemOutsideItsBorderBox`, `modifierOrderChangesSizeAndPlacementAsSwiftUIDoes`, `paddingAndBorderInsetTheContentBoxEdgeByEdge`, `reversingKeepsIdentityPaintOrderHitOrderAndAccessibilityOrder`, `spaceAroundAndSpaceEvenlyLowerToSpacersWhileTheyFit`, `theCentringDefaultOfRowAndColumnStretchesNothing`, `theDemoFrameMatchesTheValuesRecordedOnMacOS`, `theDemosBodyRowKeepsTheSidebarAtItsDeclaredWidthWhereCSSShrinksIt`, `theOrderOfAComponentsDistributingModifiersIsObservableUnderBothAuthorities`, `theStageOneCorpusLowersWithNoDiagnosticAndAgreesElementByElement`, `theStageOneCorpusPinsEveryKnownDisagreementWithItsProbeArm`, `theWholeDemoReportsExactlyTheFieldsAndSitesLaterStagesOwn`, `unequalGrowWeightsAreReportedOnTheParent` (76) |
| M2f | F12 | `planLegacyItems`: `let childFactor = d.alignSelf.map(alignmentFactor) ?? parentFactor` → `let childFactor = parentFactor` | 35 | `alignSelfPlacesOneChildOnTheCrossAxisOfADefiniteContainer` | `aLoweredItemChainWithFourWrappersPerLevelAtTheNativeDepthLimitLaysOut`, `aLoweredItemChainWithFourWrappersPerLevelOnePastTheNativeDepthLimitTraps`, `aLoweredItemChainWithThreeWrappersPerLevelAtTheNativeDepthLimitLaysOut`, `aLoweredItemChainWithThreeWrappersPerLevelOnePastTheNativeDepthLimitTraps`, `aLoweredScrollViewAgreesWithTheLegacyEngineOnEveryBoundedShape`, `aLoweredTreeMintsTheSameStateSlotsAndAnimatesTheSameWidths`, `aLoweredWindowDispatchesClicksFocusAndKeysToTheSameElements`, `aLoweredWindowPublishesTheSameAccessibilityTree`, `alignItemsAndAlignSelfPlaceEachItemOnTheCrossAxis`, `alignSelfPlacesOneChildOnTheCrossAxisOfADefiniteContainer`, `anAlignSelfInsideAOneChildWrapperFillsTheWrapperWhereCSSIgnoresIt`, `anAlignSelfWrapperFillsAnIndefiniteContainerWhereCSSHugs`, `marginsOffsetEachItemOutsideItsBorderBox` (13) |
| M2g (M2.1) | F13 | M2.1 again, after the removal | 56 | N2.1 | `aChainsOuterLayerScopesContainTheLayersInsideIt`, `aDeclaredAXNodeIsEmittedByEveryConformerThatRegistersHandlers`, `aDisabledElementPublishesDisabledWithTheGatedActionsAndRefusesEveryRequest`, `aGenericWrapOverAChainIsIdenticalToTheFlatChainUnderTheProposalAuthority`, `aHiddenInnerModifierLayerSkipsPaintAndHitsPerLayer`, `aHiddenInnerModifierLayerSuppressesEverythingInsideIt`, `aHiddenOneNodeFrameLayerPublishesNothingToAnAccessibilityClient`, `aLayerAddedAtRunTimeIsAdoptedByTheNewOutermostLayer`, `aLayerAddedAtRunTimeKeepsTheOutermostAccessibilityNodeAndRepublishesTheWrappedOne`, `aLegacyChainsBackgroundCoversTheBoxAtThePointItWasWritten`, `aLoweredPaddingLayerAgreesWithTheLegacyWrapper`, `aModifierChainIsIdenticalToHandBuiltNestedBoxesUnderTheProposalAuthority`, `aPaddedClickTargetIsHittableInItsPaddingWhereSwiftUIIsNot`, `aSizingModifierWrittenAfterAFrameIsReportedOnTheFrameLayer`, `addingALayerAtRunTimeResetsTheWrappedElementsState`, `anIDAfterAChainsLastWrapperNamesTheOutermostLayer`, `chainedLegacyFramesAgreeWithSwiftUIsOrderingRules`, `decorationSubstitutionReachesTheElementOnBoxAndStack`, `everyBackgroundPaintingSiteAnimatesItsColour`, `everyBackgroundPaintingSiteFadesItsResolvedHoverAndFocusColour`, `everyBackgroundPaintingSiteHonoursHoverAndFocus`, `everyDecorationPaintingSiteDrawsItsBorder`, `everyDecorationPaintingSiteHonoursTheBorderHoverAndFocusChain`, `everyHandlerRegisteringSiteHonoursAllowsHitTesting`, `everyHandlerRegisteringSiteSuppressesItsClickWhenDisabled`, `everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn`, `everyRegisteringSiteAnimatesItsLoweredRectUnderTheProposalAuthority`, `everyRegisteringSiteAnimatesItsStyle`, `legacyModifierChainsInferOneConcreteType`, `legacyPaddingAccumulatesAcrossAChainAsSwiftUIDoes`, `modifierOrderChangesSizeAndPlacementAsSwiftUIDoes`, `onClickIsLiveOnEveryConformerThatCanRegisterOne`, `stateSurvivesFramesUnderALegacyModifierChain`, `theElementBoundsLogRecordsTheRootEveryGroupMemberAndEveryInnerModifierLayer`, `theStageOneCorpusLowersWithNoDiagnosticAndAgreesElementByElement` (35) |
| M2g (M2.2) | F13 | M2.2 again, after the removal | 3 | N2.1, N2.2 | `aGenericWrapOverAChainIsIdenticalToTheFlatChainUnderTheProposalAuthority`, `aModifierChainIsIdenticalToHandBuiltNestedBoxesUnderTheProposalAuthority` (2) |

Notes on the table:

- **M2c** as the spec spelled it traps (`LR-EN` item 2); **M2c′** is F11's
  amend sample.
- **M2e** reddens N2.4 too: its `Row` of a pad and a frame gains the platform
  default's 8 between them.
- **M2g (M2.2)**: after the removal only N2.1 and N2.2 see the inner fills'
  order — the retired twins were its only other pins (`LR-EN` item 4).
- The design's M2c spelling was measured with a **filtered** run only, to show
  the trap (`LayoutTree.swift:636: Precondition failed: setStyle on a native
  layout node — the proposal engine never reads Style (SA-G)`); it is not
  counted as a mutation result.

**Comments** (`LR-EN` item 6; `LR-EG`). Re-pointed, comment lines only:
`ModifiedElement.swift` (the MC-B oracle names → N2.1/N2.2; `lowered(_:childCount:)`'s
two pins; `_wrap`'s pin → N2.1), `Box.swift` (three: the sizing-modifier and
fraction pins, retired), `Units.swift` (the fraction pin), `Component.swift`
(four: order → 4.4, node count → 4.2, divergence 48 → 4.1's legacy arm,
chained padding → retired). `git diff 41344e5 -- Sources | grep -E '^[-+]' |
grep -vE '^(\+\+\+|---)' | grep -vE '^[-+]\s*//'` prints nothing. Lane 2's own
test files: the Dual fixtures' docs, the `FrameSizingTests`/`ComponentTests`/
`ElementLayoutTests` headers, `ElementLayoutTests`' historical EP-8 table (marked
historical, not re-measured) and `ModifiedElementTests`' two `malloc_logger`
notes (the collision with the deleted `FreezeLoopAllocationTests` is gone; this
file is now the suite's only `malloc_logger` installer, grep). Listed, not
edited (not lane 2's files): `AnimationTests` 1007–1011, `FrameDecorationInteractionTests`
379, `OuterModifierMatrixTests` 854 (lane 3), `LoweringComponentTests` 120,
`LoweringCorpusTests` 170 — for the Record phase.

**Portable CI figure.** Unchanged: every lane-2 file is in `MetalUITests`,
which Linux and Windows CI do not run; **200 + 22 + 3** stands (`LR-EM` item 5).

**Suite, build systems, guards.** At this section's tree: native build 0
`error:`, one `warning:` (SwiftPM's deprecation notice); **`Test run with 1450
tests in 3 suites passed`**, `FR-J no-argument frame: succeeded=true`; default
build system `swift build --build-tests` 0 `error:`, 0 `warning:`. Guards 78
(no guard file touched), gated nine (none retired was gated),
`AuthorityCoverage.expected` 82 (no retired or new test records coverage).
`Tests/PortableTests`, `Backends/`, `Tests/MetalUICrossPlatformTests` and
`Package.swift` untouched (`git diff --stat 41344e5` over them is empty).

**Pixels.** `docs/probes/demo-pixels/compare.sh <scratch> 41344e5 983ca74`:
**0 differing and scene identical in all fourteen images**. Controls at
`41344e5`: light vs dark 1048576; default vs modal 1031003; default vs
animation 454895; f0 vs f3 0; preview light vs dark 1048576; chrome legacy vs
proposal 0; distinct 544 / 216; prod default vs modal 491221, distinct
`prod-default-light` 529; indicator rects 0 — §6.1's values. Re-run against
the lane's last code commit, `compare.sh <scratch> 41344e5 bf6488a` (the
comment-only `Sources/` edits included): **0 differing, scene identical, all
fourteen**. `DemoFrameDeterminismTests` unedited; its `theDemoFrameMatchesTheValuesRecordedOnMacOS` reddened under M2a and M2e only, as a
sibling of the frame's alignment and the row's spacing.

**Deferrals.** None of lane 2's rows. Handed on: the listed test-file
comments (Record phase; lane 3 for its own files); the count **1445** for lane
3 (`LR-EM` item 2); the census re-run (exit criterion 3) at the stage's close.

### 6.3 Lane 3 — text, style readers, decorations, the matrix, divergence 4 (2026-09-24, PDT)

**Commits.** `00c8c73` — N3.1–N3.5 and the four T rows; `4f71a25` — the removal
of rows 232–244's ten R/D/N tests, with the helpers only they used, and the
`Sources/` comments naming them re-pointed (comment lines only); the commit
after it — one more test-file comment, `LR-EO`, the spec's status, this section
and §7.

**R confirmation.** The four R rows' replacements exist and were read against
the retired bodies. Row 233 (a stretched column's label wraps, 3 × 16): the
lowered stretch's aliased item frame wraps its `Text` at the item's width
(`theBoundsAliasReachesDecorationHitboxesAccessibilityAndTextWrap`, both its
120-wide arm and its narrower-than-a-glyph arm), and
`aProposalTextBreaksInsideAWordAndAnswersItsWidestLineUpToTheProposal` pins the
leaf's wrapped answer. Row 234 (TX-H: a centring column shrink-wraps its text):
`aLoweredTextHugsItsWidestLineWhereTheLegacyTextFillsItsContainingBlock` pins
the proposal side (the leaf hugs its widest line at 60); the "like WebKit" half
is fit-content, a CSS concept. Row 235 (a `Text` paints its background and its
glyphs): `aHiddenElementPaintsNothingUnderTheProposalAuthority`'s shown control
requires the `Text`'s glyphs, `spriteDestinationsAreThePenPositionPlusTheRasterizersBearings`
where each lands, and `everyBackgroundPaintingSiteHonoursHoverAndFocus`'s `Text`
site (a `makeFakeWindow` window, production's authority) its background. Row 241: 2.1's table maps
every arm of the retired guard to a proposal-side pin — **but see M3c below**:
2.1 itself carries only the inner/outer layer, `ScrollView`-content and
`Component`-snap arms; its `Box` row is pinned by the three tests the table
names. None failed.

**The N tests and the T rows, written green, first run** (at the tree that
became `00c8c73`, filtered, then the full suite): every hand-derived literal
held on the first run — N3.3's three regions and five clicks, N3.4's member
positions (a (25, 15), b (95, 10)), 160×40 border and clip, N3.5's twenty-one
rows' outer widths and both `Component` rows' gaps ((20, 40, 20) and
(20, 30, 10)). Each window arm pre-flighted under diagnostics and read an empty
report. **`Test run with 1455 tests in 3 suites passed`** (1450 + 5),
`FR-J no-argument frame: succeeded=true`.

- **N3.1 / N3.2** (`EnvironmentTests`, beside `proposalTextMeasure`): the
  `Text`'s `Frame.elementBounds` rect under `.proposal` at a 4000-wide frame
  (its one-line answer — the leaf answers `min(ideal, proposal)`, so a frame
  wider than every string here is its nil-width answer; a root cannot propose
  nil) and at a 20-wide one (narrower than every word: the proposal's width,
  the broken lines' height). The 26pt control differs at both, `#require`d
  first.
- **N3.4's difference from the retired legacy arm** (`LR-BH`, derived before
  the run): there the frame was ONE 100×40 flex row around the body — members
  packed and centred as a unit (a at 10, b at 40), border and clip 100×40, one
  frame node; here each member is framed on its own (divergence 56's proposal
  answer) and the layer's rect, which carries its decoration, is the row of
  frames. The fixture frame is 80×40 (not 100×40) so the 160-wide row and the
  1pt marker fit `inFilledRow`'s 200.
- **N3.5**: `LR-EO` items 1–2 (the witnesses, and the `Component` `width(_:)`
  row's kind).
- **T rows 238–240**: `styleOfRoot` reads `element.style` (and returns its
  `decoration` as the tuple's second half, so the three bodies' `let (style, _)
  = try styleOfRoot(&element)` lines are unchanged). **T row 245**: the
  `.legacy` arm's two lines removed; the doc now derives (21, 40) from R1/R2's
  arithmetic, not from the other arm.

**Red-before (N tests and the T rows), on `00c8c73`**, full unfiltered suite,
restored from a copy, `git status --short` empty after each:

| id | spelling applied | issues | every test reddened |
|---|---|---|---|
| M3.1 | `Text.requestLayout`'s lowered branch: the measurement's size × 2 when `pass.environment.dynamicTypeSize != .large` | 2 | `dynamicTypeSizeChangesNoTextMeasurementUnderTheProposalAuthority` (1) |
| M3.2 | the same, keyed on `pass.environment.locale.identifier == "th_TH"` | 2 | `aLocaleChangesNoTextMeasurementUnderTheProposalAuthority` (1) |
| M3.3 | `Frame.registerHandlers`: `hitRegion(bounds, inset: handlers.contentShapeInset)` → `inset: nil` | 10 | `aContentShapeInsetShrinksTheHitRegionAndChangesNoLayout`, `aContentShapeMovesNeitherTheAccessibilityFrameNorTheFocusRegistration`, `aContentShapeOnAFrameLayerInsetsTheFrameBoxAndBeforeItTheChildBox`, `aContentShapeOnAFrameLayerInsetsTheFrameBoxAndBeforeItTheChildBoxUnderTheProposalAuthority`, `aContentShapeWithoutAClickHandlerRegistersNothing`, `aContentShapeWrittenBeforeAWrappingModifierDoesNotReachAClickWrittenAfterIt`, `aLabelledClickTargetOnAFrameLayerPublishesTheFrameBoxWhileItsHitRegionIsInset`, `aNegativeContentShapeInsetGrowsTheHitRegionAndIsStillClippedByAnAncestor`, `everyOuterModifierIsTheKindTheMatrixSaysUnderTheProposalAuthority`, `everyOuterModifierIsWrapsOrPaintOnlyOrDistributesAsTheMatrixSays` (10) |
| M3.4 | `ModifiedElement.paintLayer`: a frame layer (`frameSpec != nil`) with opacity below 1 paints its content and border at opacity 1, its own fill (if any) alone under the opacity | 5 | `aComponentsFrameCarriesTheNewDecorationsAndScopesItsMembers`, `aComponentsFrameCarriesTheNewDecorationsAndScopesItsMembersUnderTheProposalAuthority`, `everyDecorationScopingSiteContainsItsOwnContent` (3) |
| M3.5′ | `padding(_ edges:)` on a non-chain receiver (`LayerBase.self == Self.self`): `Style.padding` written on the receiver, the wrapper layer empty (`LR-EO` item 3) | 2169 | `aChainsOuterLayerScopesContainTheLayersInsideIt`, `aContentShapeWrittenBeforeAWrappingModifierDoesNotReachAClickWrittenAfterIt`, `aDeclaredAXNodeIsEmittedByEveryConformerThatRegistersHandlers`, `aGenericWrapOverAChainIsIdenticalToTheFlatChainUnderTheProposalAuthority`, `aGrowInsideAOneChildPaddingFillsTheWrapperWhereCSSLeavesItUngrown`, `aLayerAddedAtRunTimeIsAdoptedByTheNewOutermostLayer`, `aLegacyChainsBackgroundCoversTheBoxAtThePointItWasWritten`, `aLoweredPaddingLayerAgreesWithTheLegacyWrapper`, `aModifierChainAllocatesABoundedAmountOverNestedBoxes`, `aModifierChainIsIdenticalToHandBuiltNestedBoxesUnderTheProposalAuthority`, `aModifierChainRegistersAndPaintsOuterLayersFirst`, `anAlignSelfInsideAOneChildWrapperFillsTheWrapperWhereCSSIgnoresIt`, `anIDAfterAChainsLastWrapperNamesTheOutermostLayer`, `anInnerLayersAllowsHitTestingDoesNotReachAClickOnALayerWrittenAfterIt`, `aPaddedClickTargetIsHittableInItsPaddingWhereSwiftUIIsNot`, `everyBackgroundPaintingSiteFadesItsResolvedHoverAndFocusColour`, `everyBackgroundPaintingSiteHonoursHoverAndFocus`, `everyDecorationPaintingSiteDrawsItsBorder`, `everyOuterModifierIsTheKindTheMatrixSaysUnderTheProposalAuthority`, `everyOuterModifierIsWrapsOrPaintOnlyOrDistributesAsTheMatrixSays`, `everyRegisteringSiteAnimatesItsLoweredRectUnderTheProposalAuthority`, `everyRegisteringSiteAnimatesItsStyle`, `legacyPaddingAccumulatesAcrossAChainAsSwiftUIDoes`, `modifierOrderChangesSizeAndPlacementAsSwiftUIDoes`, `theDemosBodyRowKeepsTheSidebarAtItsDeclaredWidthWhereCSSShrinksIt`, `theElementBoundsLogRecordsTheRootEveryGroupMemberAndEveryInnerModifierLayer`, `theStageOneCorpusLowersWithNoDiagnosticAndAgreesElementByElement`, `theWholeDemoReportsExactlyTheFieldsAndSitesLaterStagesOwn` (28) |
| T (238–240) | `Stack.init`: `style.alignItems = alignment == .center ? .stretch : alignment.blockAxis` | 34 | `aDeferredAbsoluteScrimCoversTheWindowAndEscapesTheScrollUnderBothAuthorities`, `aHiddenClickTargetPassesTheClickToWhatIsUnderIt`, `aHiddenElementInsideAnyElementIsHiddenUnderTheProposalAuthority`, `allNineAlignmentsMapToTheirPairAndTheNineAreDistinct`, `aLoweredStackPlacesFixedChildrenAtAllNineAlignmentsAsTheLegacyStackDoes`, `aMarginLowersAsPaddingOutsideTheItem`, `aNestedHandlerWinsOverItsContainingStackToo`, `aPresentationsAccessibilityRecordAndFocusMatchUnderBothAuthorities`, `aPressReleasedOverSomethingCoveringItIsNotAClick`, `aStackStretchesByItsItemsAlignmentAndIgnoresTheirFlexFields`, `clippedAlsoClipsTheHitboxesInsideIt`, `stackDefaultsToCentreNotStretch`, `theDemoFrameMatchesTheValuesRecordedOnMacOS`, `theDemoModalDismissesOnAScrimClickAndSwallowsTheWheelUnderBothAuthorities`, `theStageOneCorpusLowersWithNoDiagnosticAndAgreesElementByElement`, `theTopmostOfTwoOverlappingHandlersRuns`, `theWholeDemoReportsExactlyTheFieldsAndSitesLaterStagesOwn` (17) |

N3.1 and N3.2 redden at their two `#expect`s each (`EnvironmentTests.swift:1128`/`1129`,
`1152`/`1153`: `large.ideal` 240×32 against 120×16 under M3.1); N3.3 at its
disagreeing-arms `#require` (`:364`); N3.4 at its two fade `#expect`s; N3.5 under
M3.5′ at the `padding(_:)` row's outer-width literal and its `wraps` outer-size
witness (the empty layer still records an element rect, so the element-count
witness holds — the outer box is what a self-storing padding cannot grow). T row
245's red is M3e below (6b's M2a).

**The removal.** `4f71a25`: `TextMeasureTests` 4, `EnvironmentTests` 2,
`AnimationTests` 1, `FrameDecorationInteractionTests` 2,
`OuterModifierMatrixTests` 1 — **10**. Helpers whose only callers were retired
tests went with them: `EnvironmentTests.textMeasure`;
`FrameDecorationInteractionTests.inRow` and `render`'s `authority:` parameter;
the legacy matrix's `observe`, `Observation` and `MatrixRow`
(`OuterModifierMatrixTests`); `laidOut`'s (`TextMeasureTests`) and
`animFrame`'s (`AnimationTests`) `authority:` parameters, with the three
`TextMeasureTests` `MARK`s left empty. `swift build --build-system native
--build-tests` 0 `error:`, one `warning:` (SwiftPM's deprecation notice);
**`Test run with 1445 tests in 3 suites passed`**, `FR-J no-argument frame:
succeeded=true`. **1450 + 5 − 10 = 1445**, `LR-EM` item 2's figure.

**Removal check by script** (record §49 §4 rows 232–245 read by script): each
of the ten R/D/N names existed in its file at `41344e5` and no `func <name>`
remains there; the four T rows exist and every kept `#expect`/`#require` line
is byte-identical to `41344e5` (238: 5 of 5, 239: 3 of 3, 240: 2 of 2; 245: 3
of 5, the two dropped being `let legacy = try #require(try boxRect(.legacy))`
and its `#expect(legacy == …)`); every other surviving top-level `@Test` body
in the seven files equals its `41344e5` text (`grep -cE '^\s*@Test'`:
`AnimationTests` 42 → 41, `EnvironmentTests` 24 → 24, `FrameDecorationInteractionTests`
8 → 8, `OuterModifierMatrixTests` 5 → 5, `RootSwitchTests` 3 → 3,
`StackElementTests` 3 → 3, `TextMeasureTests` 9 → 5).

**Family mutations**, each on the committed removal (`4f71a25`), the file
copied to the scratchpad, edited, full unfiltered suite, restored from the
copy, `git status --short` empty after every one. Every required replacement
reddened — M3c's only in its `′` spelling (`LR-EO` item 4):

| id | F | spelling applied | issues | every test reddened |
|---|---|---|---|---|
| M3a | F14 | `Text.requestLayout`'s lowered measure: `proposal: ProposedSize(width: nil, height: proposal.height)` | 2046 | `aLegacyFrameProposesItsWidthToAMeasuredLeaf`, `aLoweredStackOffersItsProposalWhereTheLegacyStackOffersFitContent`, `aLoweredTextAndAProposalTextSizeOneGridColumnIdentically`, `aLoweredTextHugsItsWidestLineWhereTheLegacyTextFillsItsContainingBlock`, `aLoweredTextWithADeclaredWidthKeepsItsBoundsAndGlyphOrigin`, `anAbsoluteTextWrapsAtTheWindowMinusItsInsetWhereTheLegacyEngineWrapsAtTheWindow`, `anExplicitKnownSizeWinsOverTheMeasuredOne`, `aTextShrunkByFlexStillWrapsAtItsShrunkWidth`, `aZeroBasisGrowerTakesItsShareDownToItsContent`, `aZeroShrinkKeepsItsNaturalMainSizeAndOverflows`, `everyWrappedLineEmitsItsGlyphs`, `paddingOnALoweredTextPadsItWhereTheLegacyLeafIgnoresIt`, `theBoundsAliasReachesDecorationHitboxesAccessibilityAndTextWrap`, `theDemoFrameMatchesTheValuesRecordedOnMacOS`, `theStageOneCorpusLowersWithNoDiagnosticAndAgreesElementByElement`, `theStageOneCorpusPinsEveryKnownDisagreementWithItsProbeArm`, `theWholeDemoReportsExactlyTheFieldsAndSitesLaterStagesOwn` (17) |
| M3b | F14 | `Text.paint`: `paintDecoration`'s content closure emptied (no `paintGlyphs`) | 45 | `aCentredShrinkWrappedLabelNeverWrapsAtAnyValue`, `aHiddenElementPaintsNothingUnderTheProposalAuthority`, `aHiddenTextIsHiddenUnderTheProposalAuthority`, `aLoweredPaddingLayerAgreesWithTheLegacyWrapper`, `aLoweredTextAgreesWithTheLegacyTextAtItsNaturalWidth`, `aPortableFrameNeverShapesThroughCoreText`, `aTextShrunkByFlexStillWrapsAtItsShrunkWidth`, `aWindowUploadsTheAtlasBeforeEncodingSoTheFirstFrameOfTextIsNotBlank`, `everyDecorationScopingSiteContainsItsOwnContent`, `everyWrappedLineEmitsItsGlyphs`, `glyphsAreTintedByTheThemeAndDefaultToTextPrimary`, `paddingOnALoweredTextPadsItWhereTheLegacyLeafIgnoresIt`, `paintWrapsAtTheWidthLayoutMeasuredAtNotTheRoundedBox`, `spacesGetNoSprite`, `spriteDestinationsAreThePenPositionPlusTheRasterizersBearings`, `theAtlasSurvivesTheFrameThatFilledIt`, `theBoundsAliasReachesDecorationHitboxesAccessibilityAndTextWrap`, `theCoreTextAndPortableSystemsDrawTheSameSprites`, `theDemoFrameDrawsRectsAndText`, `theDemoFrameMatchesTheValuesRecordedOnMacOS`, `theIndicatorIsTheLastPrimitiveInTheScene`, `theLegacyHiddenPathPaintsAndHitTestsExactlyAsBefore`, `thePortableSystemIsTheOneThatDraws`, `theSecondFrameOfTheSameTextPlacesItsSpritesIdentically`, `theWindowsPixelsAreExactlyTheGlyphBitmapsItsSpritesStandFor` (25) |
| M3c | F15 | `Box.requestLayout`: `lowerLegacyNode(declared, declared: declared, …)` (the lowered `Box` from its declared style) | 19 | `aLoweredBoxRegistersItsAnimatedWidth`, `aLoweredContainerLaysOutItsAnimatedWidthPaddingAndGap`, `aLoweredMarginRegistersItsAnimatedValue`, `aLoweredTreeMintsTheSameStateSlotsAndAnimatesTheSameWidths`, `anAnimatedInsetInterpolatesItsValueUnderBothAuthorities`, `anAnimatedItemFieldSnapsItsStructureAndInterpolatesItsValues`, `anAnimatedWriteThatIsNotTheFirstObservableWriteOfItsIntervalStillAnimates`, `anAnimatingElementThatVanishesAndReturnsResumesRatherThanRestarting`, `aParkedTransactionIsConsumedByExactlyOneBuild`, `aTransactionParkedOutsideTheBuildAnimatesTheNextFrameEndToEnd`, `aTransactionWhoseBodyDirtiesNothingIsNeverParkedAndCannotAnimateALaterChange`, `theDisplayLinkStaysRunningWhileAnimatingAndPausesOnTheFrameAfterTheLastEnds` (12) |
| M3c′ | F15 | `ModifiedElement.requestLayout`: an inner layer lowered from its declared style (`mutantLayer.style = declared`) | 2 | `everyRegisteringSiteAnimatesItsLoweredRectUnderTheProposalAuthority` (1) |
| M3d (M3.3) | F16 | M3.3 again | 8 | `aContentShapeInsetShrinksTheHitRegionAndChangesNoLayout`, `aContentShapeMovesNeitherTheAccessibilityFrameNorTheFocusRegistration`, `aContentShapeOnAFrameLayerInsetsTheFrameBoxAndBeforeItTheChildBoxUnderTheProposalAuthority`, `aContentShapeWithoutAClickHandlerRegistersNothing`, `aContentShapeWrittenBeforeAWrappingModifierDoesNotReachAClickWrittenAfterIt`, `aLabelledClickTargetOnAFrameLayerPublishesTheFrameBoxWhileItsHitRegionIsInset`, `aNegativeContentShapeInsetGrowsTheHitRegionAndIsStillClippedByAnAncestor`, `everyOuterModifierIsTheKindTheMatrixSaysUnderTheProposalAuthority` (8) |
| M3d (M3.4) | F16 | M3.4 again | 3 | `aComponentsFrameCarriesTheNewDecorationsAndScopesItsMembersUnderTheProposalAuthority`, `everyDecorationScopingSiteContainsItsOwnContent` (2) |
| M3d (M3.5′), `wraps` | F16 | M3.5′ again | 2167 | `aChainsOuterLayerScopesContainTheLayersInsideIt`, `aContentShapeWrittenBeforeAWrappingModifierDoesNotReachAClickWrittenAfterIt`, `aDeclaredAXNodeIsEmittedByEveryConformerThatRegistersHandlers`, `aGenericWrapOverAChainIsIdenticalToTheFlatChainUnderTheProposalAuthority`, `aGrowInsideAOneChildPaddingFillsTheWrapperWhereCSSLeavesItUngrown`, `aLayerAddedAtRunTimeIsAdoptedByTheNewOutermostLayer`, `aLegacyChainsBackgroundCoversTheBoxAtThePointItWasWritten`, `aLoweredPaddingLayerAgreesWithTheLegacyWrapper`, `aModifierChainAllocatesABoundedAmountOverNestedBoxes`, `aModifierChainIsIdenticalToHandBuiltNestedBoxesUnderTheProposalAuthority`, `aModifierChainRegistersAndPaintsOuterLayersFirst`, `anAlignSelfInsideAOneChildWrapperFillsTheWrapperWhereCSSIgnoresIt`, `anIDAfterAChainsLastWrapperNamesTheOutermostLayer`, `anInnerLayersAllowsHitTestingDoesNotReachAClickOnALayerWrittenAfterIt`, `aPaddedClickTargetIsHittableInItsPaddingWhereSwiftUIIsNot`, `everyBackgroundPaintingSiteFadesItsResolvedHoverAndFocusColour`, `everyBackgroundPaintingSiteHonoursHoverAndFocus`, `everyDecorationPaintingSiteDrawsItsBorder`, `everyOuterModifierIsTheKindTheMatrixSaysUnderTheProposalAuthority`, `everyRegisteringSiteAnimatesItsLoweredRectUnderTheProposalAuthority`, `legacyPaddingAccumulatesAcrossAChainAsSwiftUIDoes`, `modifierOrderChangesSizeAndPlacementAsSwiftUIDoes`, `theDemosBodyRowKeepsTheSidebarAtItsDeclaredWidthWhereCSSShrinksIt`, `theElementBoundsLogRecordsTheRootEveryGroupMemberAndEveryInnerModifierLayer`, `theStageOneCorpusLowersWithNoDiagnosticAndAgreesElementByElement`, `theWholeDemoReportsExactlyTheFieldsAndSitesLaterStagesOwn` (26) |
| M3d `selfStorage` | F16 | `margin(_ points:)`: `modifying { _ in }` (stores nothing) | 19 | `aComponentsPaddingLowersAsAnOrdinaryOneChildContainer`, `aFrameOverSeveralMembersStillPlansEachMembersItemFields`, `aLoweredItemChainWithFourWrappersPerLevelAtTheNativeDepthLimitLaysOut`, `aLoweredItemChainWithFourWrappersPerLevelOnePastTheNativeDepthLimitTraps`, `aLoweredMarginRegistersItsAnimatedValue`, `aLoweredStackPlacesFixedChildrenAtAllNineAlignmentsAsTheLegacyStackDoes`, `anAmendedComponentsMemberItemFieldsAreConsumedAndPlanned`, `aNegativeMarginOverlapsItsSibling`, `anItemFieldNoLoweredContainerConsumesIsReportedByName`, `anItemFieldOnAGridCellIsReportedUnconsumed`, `aRootFieldWithNoLoweringTrapsInAProductionWindow`, `everyContainerFieldEitherLowersAndAgreesOrIsReportedByName`, `everyOuterModifierIsTheKindTheMatrixSaysUnderTheProposalAuthority`, `everyPublicModifierWritesItsOwnFieldAndOnlyThatField` (14) |
| M3d `paintOnly` | F16 | `border(_:width:)` on a non-chain receiver also writes `Style.border` (`LR-EO` item 3) | 3 | `everyOuterModifierIsTheKindTheMatrixSaysUnderTheProposalAuthority`, `everyPublicModifierWritesItsOwnFieldAndOnlyThatField` (2) |
| M3d `prepaintOnly` | F16 | M3.3 (above): N3.5's `contentShape(inset:)` row reddens at `hitRegionsMoved \|\| hitCountDelta != 0` | — | (the M3d (M3.3) row) |
| M3d `distributes` | F16 | `StyledComponent.requestGroupLayout`: under `.proposal` a `.wrap` lowered around the first member only | 7 | `aComponentsPaddingLowersAsAnOrdinaryOneChildContainer`, `everyOuterModifierIsTheKindTheMatrixSaysUnderTheProposalAuthority`, `theOrderOfAComponentsDistributingModifiersIsObservableUnderBothAuthorities` (3) |
| M3e | F17 | `computeRootLayout`: the native root run again centred in a container of its own answer's size at the origin (6b's M2a) | 231 | `aBackgroundsContentKeepsItsStateWhenThePrimaryChangesShape`, `aBoxWithADeclaredAXNodeEmitsItAtItsOwnResolvedBounds`, `aClickInsideTheBoundsRunsTheHandler`, `aClickOutsideTheBoundsDoesNotRunTheHandler`, `aClickOverABackgroundAndItsPrimaryReachesThePrimary`, `aClippedBoxInsideAScrolledScrollViewClipsWhereItPaints`, `aContentShapeInsetShrinksTheHitRegionAndChangesNoLayout`, `aContentShapeMovesNeitherTheAccessibilityFrameNorTheFocusRegistration`, `aContentShapeWithoutAClickHandlerRegistersNothing`, `activeIsSetOnMouseDownAndHeldUntilMouseUp`, `aDeclaredAXNodeIsEmittedByEveryConformerThatRegistersHandlers`, `aDefaultSpacerAndAGreedyFrameThroughTheElementAPI`, `aDispatchedClickDoesNotAlsoReachTheWindowsRawHandler`, `aFocusRingOutranksAHoverBorderAndABorder`, `aGridRootIsCentredAtItsAnswer`, `aHandlerRegisteredOnFrameNRunsForAnEventBeforeFrameNPlusOne`, `aHoverBackgroundNeverPaintsUnderAllowsHitTestingFalse`, `aHuggingLegacyRootIsCentredInAProductionWindow`, `aLabelWithHardBreaksMeasuresItsWidestLineAtMaxContent`, `aLegacyFramePlacesItsChildAtEachOfTheNineAlignments`, `aNativeRootIsCentredAtItsAnswer`, `aNativeRootRunsThroughTheFramePipelineWithoutInvokingFlexLayout`, `aNegativeContentShapeInsetGrowsTheHitRegionAndIsStillClippedByAnAncestor`, `aNestedHandlerWinsOverItsContainerWhichDoesNotAlsoFire`, `aNestedHandlerWinsOverItsContainingStackToo`, `aNestedTextEmitsItsDeclaredAXNodeAtItsAbsoluteBounds`, `anIdealFrameHeightBecomesItsOuterHeightWhenTheAxisIsUnspecified`, `anIdealFrameLowersUnderTheProposalAuthorityAndStillTrapsUnderTheLegacyOne`, `anIdealFrameWidthBecomesItsOuterWidthWhenTheAxisIsUnspecified`, `aNodeInsideAScrolledScrollViewReportsItsOnScreenFrame`, `anOverlaysIdentityDoesNotDependOnTheIndicesItsPrimaryConsumed`, `aPressOnOneElementReleasedOnAnotherIsNotAClick`, `aPressReleasedOverSomethingCoveringItIsNotAClick`, `aPressThatLeavesTheElementAndReturnsStillClicks`, `aPressThatLeavesTheHitboxAndReturnsStaysActive`, `aProposalLayoutContainerRendersThroughTheFramePipeline`, `aProposalScrollViewAnswersItsContentOnItsNonScrollingAxis`, `aProposalScrollViewsDirectChildrenAreACentredDefaultSpacedVStackOnEitherAxis`, `aProposalScrollViewsIndicatorFadesOnTheSameRampAndIsClippedLikeTheContent`, `aProposalTextInAStackIsShapedOncePerDistinctWidth`, `aPublicHStackFormsAnAllProposalLayoutSubtreeAndPlacesItsSpacer`, `aScrollViewInsideAFrameKeepsItsViewportAndWheelUnderTheProposalAuthority`, `aspectRatioFillCircumscribesTheParentProposalBeforeMeasuringItsChild`, `aspectRatioFitInscribesTheParentProposalBeforeMeasuringItsChild`, `aStackWithoutSpacingPutsEightBetweenViewsAndNothingBesideASpacer`, `aTapOnAnOverlaysPrimaryWritesOnlyThePrimarysState`, `aZStackRootPlacesItsChildrenAtItsOwnSizeWithinTheirUnion`, `chainedNativeFramesPreserveTheirDeclarationOrder`, `everyBackgroundPaintingSiteFadesItsResolvedHoverAndFocusColour`, `everyBackgroundPaintingSiteHonoursHoverAndFocus`, `everyDecorationPaintingSiteHonoursTheBorderHoverAndFocusChain`, `everyHandlerRegisteringSiteHonoursAllowsHitTesting`, `everyZStackAndOverlayAlignmentPlacesAndSizesAsTheProbeReads`, `explicitStackSpacingIsUsedForEveryGapIncludingBesideASpacer`, `fixedSizeModifierWithholdsOnlyItsSelectedAxisFromTheChildProposal`, `hoverAndFocusFadeThroughTheSameEffectiveColourPath`, `hoveringAnOverlaysPrimaryDoesNotHoverTheOverlay`, `hoveringOneClickTargetDoesNotHoverItsSibling`, `hoverResolvedThroughARealRenderHasNoLag`, `hStackAndVStackDistributeAsTheProbeReadsThroughTheElementAPI`, `hStackUsesThePlatformDefaultSpacingUnlessTheCallerOverridesIt`, `layoutPriorityPreservesASpacersFlexibleExpansion`, `nativeBackgroundWrapsTheResolvedOuterBoundsAndPaintsBeforeItsContent`, `nativeClipMasksOverflowingContentToItsOuterFrame`, `nativeModifierChainsRemainConcreteAndWrapInDeclarationOrder`, `nativeOverlayIsMeasuredAgainstItsPrimaryAndDoesNotEnlargeIt`, `onClickIsLiveOnEveryConformerThatCanRegisterOne`, `onlyABoxWithAHandlerRegistersAHitbox`, `onTapPaintsItsHoverOverlayOnlyWhenThePointerIsOverItsResolvedBounds`, `onTapRegistersTheResolvedNativeBoundsAsAHittableTarget`, `proposalLayoutFrameUsesTheTypedProposalWrapper`, `spacerMinimumLengthSurvivesAConstrainedStackProposal`, `theProposalModifiersAcceptWhatTheKernelAccepts`, `theTopmostOfTwoOverlappingHandlersRuns`, `vStackUsesThePlatformDefaultSpacingUnlessTheCallerOverridesIt` (75) |

Notes on the table:

- **Where N3.5 reddens, by row**: M3.3 the `contentShape(inset:)` row; M3.5′
  the `padding(_:)` (Element) row; M3d `selfStorage` the `margin(_:)` row, at
  the broken-instrument `#require` (the two arms observe identically and store
  identically, so the `self` claim cannot be proved); M3d `paintOnly` the
  content-sized `border` row (outer 30 → 38, element rects moved); M3d
  `distributes` the `Component` `padding(_:)` row (outer 120, gaps (20, 20, 0):
  the trailing gap stays closed).
- **M3d `distributes`** reddens N3.5 at three `#expect`s, and
  `aComponentsPaddingLowersAsAnOrdinaryOneChildContainer` and
  `theOrderOfAComponentsDistributingModifiersIsObservableUnderBothAuthorities`
  beside it — N3.5 is one of three pins of per-member distribution.
- **M3e** reads 75 tests and 231 issues, the figure of 6b's §12.5; the set
  differs from that one only by lane 2's retirement of
  `aLegacyScrollViewTakesItsCrossAxisFromItsParentWhereAProposalScrollViewTakesItsContents`
  and lane 2's N2.4 (`aScrollViewInsideAFrameKeepsItsViewportAndWheelUnderTheProposalAuthority`)
  reddening in its place.
- `DemoFrameDeterminismTests`' `theDemoFrameMatchesTheValuesRecordedOnMacOS`
  reddened under M3a, M3b and the T-row mutation (not under M3e — read, not
  explained), as a
  sibling of the demo's text measure, its glyphs and its `Stack` alignment; it
  is unedited.

**Comments** (`LR-EG`, `LR-EO` item 6). Re-pointed in `Sources/`, comment lines
only: `EnvironmentValues.swift` (two: the locale and `dynamicTypeSize` pins →
N3.2, N3.1), `Component.swift` (two: B-7's readings → 2.1's arm (c), the side
door → N3.4). In lane 3's test files: 2.1's doc (it is the registering-site
guard now) and three `AnimationTests` notes naming the retired guard, the matrix
file's header and its `legacyPaddingAccumulatesAcrossAChainAsSwiftUIDoes` note
(row 215's component half, listed by `LR-EN` item 6 as line 854), the
`FrameDecorationInteractionTests` fixture docs. `LR-EN`'s `AnimationTests`
1007–1011 and `FrameDecorationInteractionTests` 379 were inside tests this lane
retired and went with them. `git diff 41344e5 -- Sources | grep -E '^[-+]' |
grep -vE '^(\+\+\+|---)' | grep -vE '^[-+]\s*//'` prints nothing.

**Portable CI figure.** Unchanged: every lane-3 file is in `MetalUITests`;
**200 + 22 + 3** stands (`LR-EM` item 5).

**Pixels.** `docs/probes/demo-pixels/compare.sh <scratch> 41344e5 4f71a25`:
**0 differing and scene identical in all fourteen images**. Controls at
`41344e5`: light vs dark 1048576; default vs modal 1031003; default vs
animation 454895; f0 vs f3 0; preview light vs dark 1048576; chrome legacy vs
proposal 0; distinct 544 / 216; prod default vs modal 491221, distinct
`prod-default-light` 529; indicator rects 0 — §6.1's values. The commit after
`4f71a25` changes one test-file comment only.

**Deferrals.** None of lane 3's rows.

## 7. The stage's close (lane 3, 2026-09-24, PDT)

Spec §8's exit criteria, each read at the tree after `4f71a25` (whose only
further change is comment lines):

1. **`grep -rn "computeLayout(" Tests --include='*.swift'`** (`.build`
   excluded) **prints nothing** (since lane 2, §6.2).
2. **1670 − 236 + 11 = 1445**: `Test run with 1445 tests in 3 suites passed`,
   one summary line, `FR-J no-argument frame: succeeded=true`. Lane by lane:
   1670 → 1482 (lane 1, + 2 − 190) → 1450 (lane 2, + 4 − 36) → 1445 (lane 3,
   + 5 − 10); 236 removed = 190 + 36 + 10, 11 added = 2 + 4 + 5. The removal
   check by script is green over all 245 rows: rows 1–190 (§6.1), 195–231
   (§6.2), 232–245 (§6.3); rows 191–194 are `StyleTests`' four K rows, kept
   (`LR-EE`).
3. **The census**: `docs/probes/stage-7b-css-engine-instrument.patch` applied
   at `4f71a25`, native build, one unfiltered run (`Test run with 1445 tests in
   3 suites passed`, **1075 markers**), reverted (`git status --short` clean).
   Attributed by the census file's rule (the preceding `started.` line), the
   markers fall in **199 tests, exactly section A** — none outside it, none of
   B or C, no A test silent, none unattributed.
4. **0 px** in all fourteen images against `41344e5` (§6.3 "Pixels"; §6.1 and
   §6.2 read the same at their lanes). **0 `warning:`**: native `swift build
   --build-system native --build-tests` one `warning:`, SwiftPM's deprecation
   notice; default `swift build --build-tests` 0 `error:`, 0 `warning:`.
   **`Sources/` diff comment-only** (the check above prints nothing).
5. **Every N test's named mutation is recorded** — N1.1/N1.2 (§6.1), N2.1–N2.4
   (§6.2), N3.1–N3.5 (§6.3) — and **every family F1–F17 has at least one
   mutation with its replacement among the reddened tests**: F1–F9 §6.1,
   F10–F13 §6.2, F14–F17 §6.3 (F15's by M3c′, `LR-EO` item 4).

Also held: guards **78** (no guard file touched, `grep -c canTypecheck`
unchanged), gated tests **nine**, `AuthorityCoverage.expected` **82** (no
retired, trimmed or new test records coverage); `git diff --stat 41344e5 --
Tests/MetalUICrossPlatformTests Tests/PortableTests Backends Package.swift`
empty, so `DemoFrameDeterminismTests` is unedited and green. **Divergence 4
has no pin left** (`LR-EH`: its two CSS-engine pins were D rows of lane 1, and
3.2's `.legacy` arm was removed here).

Handed on (spec §9): to the Record phase, the counts **1445 / 0 / 78**, the
portable figure **200 + 22 + 3**, divergence 4 retired (58 → 57 live), the
freeze-loop CI hazard deleted with its test, and the listed Sources comments
in CSS-only files (§5.1); to stage 9, the 199 census-A tests and every
differential replacement's proposal arm (`LR-EK`).
