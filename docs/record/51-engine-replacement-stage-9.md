# §51 — Engine replacement, stage 9: engine deletion

Plan task 7, stage 9 (`docs/superpowers/specs/2026-09-17-engine-replacement-design.md`
§4.1 row 9, §8). Spec `docs/superpowers/specs/2026-09-24-engine-stage-9-design.md`;
rulings `LR-FC`…`LR-FH` in `docs/superpowers/2026-09-17-engine-replacement-decisions.md`.
Branch `feat/engine-stage-9` from `b9a5d7f` (`master`, stage 8 merged), worktree
`/Users/maxburger/Developer/worktrees/MetalUI/stage-9`.

## 1. Baseline at `b9a5d7f` (2026-09-24, PDT)

`swift build --build-system native --build-tests` → `Build complete!`, 0
`error:`, one `warning:` (SwiftPM's `--build-system native` deprecation notice).
Unfiltered `swift test --build-system native --no-parallel` →
**`Test run with 1452 tests in 3 suites passed after 91.885 seconds`**, the log
carrying `FR-J no-argument frame: succeeded=true deprecations=2` (guards ran).

## 2. The entry measurement (design, 2026-09-24)

### 2.1 Runtime census — who reaches the legacy side

**Instrument**: `docs/probes/stage-9-legacy-reach-instrument.patch`, three
`print`s — `S9MARK-ENGINE` in `computeLayout` after its `SA-G` check,
`S9MARK-NEWNODE` at the top of `LayoutTree.newNode`, `S9MARK-LEGACYFRAME` in
`Frame.init` when the authority is `.legacy`. Applied at `b9a5d7f`, built, one
unfiltered run (`Test run with 1452 tests in 3 suites passed after 91.068
seconds`, 163 943 markers), reverted (`git checkout Sources`, `git status
--short` clean but for this design's files). Attribution: the last `Test …
started.` line before a marker (a plain test, or `Test case passing … to NAME(…)
started.` for a parameterised case); `--no-parallel` serializes. Exit-test
children print to their own streams and are not seen.

**Result: 206 tests** (`docs/probes/stage-9-legacy-reach-census.txt`, one line
per test with its file and markers):

- **200** carry all three markers — a `.legacy` frame that registered CSS
  nodes and ran the CSS engine. This is record §49 §2's census A (199) plus
  stage 8's `aFramedAbsoluteBoxIsAPresentationRootUnderBothAuthorities` (N1.2,
  `PresentationLoweringTests` reads 5 where §49 read 4); `ScrollRoutingTests`
  reads 15 where the roll call lists 16 scenarios (one scenario lays nothing
  out under `.legacy` in-process).
- **6** carry `NEWNODE` alone: `LayoutTreeTests`' six plain tests, which mint
  ids with `newNode` and never lay out.

By file: `LoweringItemTests` 27, `ListTests` 21, `ScrollRoutingTests` 15,
`ScrollIndicatorTests` 14, `LoweringStackAndLayerTests` 11,
`LoweringDistributionTests` 9, `LoweringComponentTests` 9,
`LoweringContainerTests` 7, `LoweringBoxModelTests` 7, `PresentationWindowTests`
6, `LoweringScrollTests` 6, `LoweringLeafTests` 6, `LayoutTreeTests` 6,
`AccessibilityDefaultsTests` 6, `PresentationLoweringTests` 5,
`LayoutAuthorityTests` 5, `DeferredTests` 5, `AccessibilityTreeTests` 5,
`ScrollViewTests` 4, `MeasurePerformanceTests` 4, `LoweringPipelineParityTests`
3, `LoweringCorpusTests` 3, `ListLoweringTests` 3, `AXNodeTests` 3,
`HiddenLoweringTests` 2, `FrameSizingTests` 2; one each in `TombstoneTests`,
`TextSystemSeamTests`, `TextFieldTests`, `RootSwitchTests`,
`RootFieldLoweringTests`, `ProposalNodeIDTests`, `ModifierCompositionProofTests`,
`FocusTests`, `EnvironmentTests`, `DecorationPaintTests`, `AbsoluteOverlayTests`.

### 2.2 Static census, and the scratch deletion

**Static census** (`docs/probes/stage-9-legacy-reference-census.tsv`): a script
split every test file into `@Test` blocks (a block runs to the next `@Test`,
comment lines dropped) and listed every block naming a symbol row 9 deletes
(`.legacy`, `LayoutAuthority`, `layoutAuthority`, `lowersToProposal`,
`legacyRootLayoutCounter`, `requestNode(`, `requestLeaf(`, `textMeasure(`,
`computeLayout(`, `newNode(`, `newLeaf(`, `setStyle(`, `tree.style(`,
`AvailableSpace`, `MeasureFunction`, `minContentWidth`, `unbreakableRuns`,
`runCallCounter`, `customElement`, the four `deferred.*` fields,
`AuthorityCoverage`, `LayoutDifferential`, `WindowPair`, `minContentCount`,
`isNativeLayoutNode`, `defaultLayoutAuthority`, `maxContentWidth`,
`expectFullAgreement`, `authorities`) or appearing in §2.1: **371 rows, 71
files** (columns: file, test, `C` if in §2.1, `EXIT` if an exit test, the
symbols hit). Blocks include trailing helpers, so a row can be a false positive
(a helper after the test); lanes read the test, not the row.

**Scratch deletion**, applied and reverted:

1. `git rm` of `FlexEngine.swift`, `ResolveFlexibleLengths.swift`,
   `FlexBaseSize.swift`, `FlexLines.swift`, `Alignment.swift`,
   `LayoutContext.swift`, `Resolve.swift`, and `MeasureFunction.swift` cut after
   `OptionalSizeD` → `swift build --build-system native`: errors in
   **`Sources/MetalUILayout/LayoutTree.swift` alone** (`MeasureFunction` in the
   `measures` row, `newLeaf` and `measure(_:)`).
2. `LayoutTree`'s `styles`/`measures` rows, `newNode`, `newLeaf`, `style`,
   `setStyle`, `measure` removed, `appendNode(style:)` → `appendNode(children:)`,
   `nodeCount` on `childLists` → `MetalUILayout` compiles; `MetalUI` fails in
   `Frame.swift` (7 distinct errors: `newNode`, `newLeaf`, `MeasureFunction`,
   `style`, `setStyle`, `computeLayout`, `AvailableSpaceSize`), `Passes.swift`
   (1) and `Text.swift` (3).
3. Also `LayoutAuthority.legacy`, `Frame.requestNode`/`requestLeaf`/`style`/
   `setStyle`, `LayoutPass.requestNode`/`requestLeaf`/`lowersToProposal`
   removed → the compiler's visible set: `Box` 2, `Component` 1, `Deferred` 1,
   `Frame` 3, `ListRows` 2, `ModifiedElement` 3, `Passes` 2, `ScrollView` 3,
   `Stack` 2, `Text` 5, `TextField` 2 — every one a legacy branch or a
   registrar call.

`resolveLength`/`resolveDimension`/`resolveEdges`/`resolveMargin`/`clamp`/
`ResolvedEdges` have no reference outside the engine files in `Sources`,
`Tests`, `Backends/SDL`, `Tests/PortableTests` or `Experiments` (the hits named
`clamp` elsewhere are `ScrollChrome.clamp` and comments). `OptionalSizeD` and
`AvailableSpace*` are referenced only by `textMeasure`, `computeRootLayout`'s
legacy branch and three retired tests (`LayoutTreeTests`' measure-function
test, `TextMeasureTests`). `minContentWidth` has one production caller,
`Text.swift:94` inside `textMeasure`. No file under `Backends/SDL`,
`Tests/PortableTests/Sources`, `Experiments` or a compiled probe names a
deleted symbol, except `docs/probes/demo-pixels/ZZDemoPixels.swift` (its chrome
pair under both authorities, via `makeFakeWindow(layoutAuthority:)`).
`Tests/PortableTests` calls `PortableText.unbreakableRuns`/`minContentWidth`/
`maxContentWidth`, which `LR-FD` keeps. `Tests/MetalUICrossPlatformTests/Expected.swift`
names `layoutAuthority: .legacy` in a comment only.

### 2.3 The differential tests

94 `@Test` blocks call `LayoutDifferential.compare` or build a `WindowPair`. A
heuristic for a hand-derived literal (`bounds(<digit>`, `Bounds(`,
`LayoutRect(`, `== [`, `.x ==`, `.width ==`, `width: Pixels(<digit>`) finds
none in 15: `DecorationPaintTests.aDeferredPortalInsideAFadedSubtreeIsStillFaded`;
`LayoutAuthorityTests.theDifferentialHarnessComparesPaintHitboxesAccessibilityAndState`;
`ListLoweringTests.aZeroRowHeightLowersWithoutTrappingOrProducingNaN`;
`LoweringComponentTests`' `aComponentsWidthFramesEachMemberWhereTheLegacyAmendOverwritesIt`,
`aComponentsPaddingLowersAsAnOrdinaryOneChildContainer`,
`aComponentAmendsFrameIsCentredOnlyOnTheAxisItDeclares`,
`theOrderOfAComponentsDistributingModifiersIsObservableUnderBothAuthorities`,
`chainedComponentAmendsComposeTheSameWayUnderBothAuthorities`,
`anAmendedComponentsMemberItemFieldsAreConsumedAndPlanned`,
`aFrameOverAMultiMemberComponentFramesEachMemberWhereTheLegacyLayerSqueezesThem`,
`aFrameOverSeveralMembersStillPlansEachMembersItemFields`,
`aFrameOverOneMemberIsUnchanged`;
`LoweringLeafTests.aLoweredTextAgreesWithTheLegacyTextAtItsNaturalWidth`;
`LoweringPipelineParityTests.aLoweredTreeMintsTheSameStateSlotsAndAnimatesTheSameWidths`;
`PresentationWindowTests.anAnimatedInsetInterpolatesItsValueUnderBothAuthorities`.
The heuristic misses literals asserted through helpers (the component file's
own helpers among them), so lane 1 reads each; these are the first place a
literal may be owed (`LR-FE` item 2).

The roll call requires **87** scenarios (16 routing, 14 indicator, 4
`ScrollViewTests`, 21 `ListTests`, 3 `AXNodeTests`, 6
`AccessibilityDefaultsTests`, 5 `AccessibilityTreeTests`, 1 `FocusTests`, 1
`TombstoneTests`, 2 `MeasurePerformanceTests`, 5 `DeferredTests`, 1
`AbsoluteOverlayTests`, 6 `PresentationWindowTests`, 1 `DecorationPaintTests`,
1 `EnvironmentTests`) — CLAUDE.md still reads 82 (stage 5's figure).

## 3. The containing block, measured (design, 2026-09-24)

A scratch build with `reportPresentationContainingBlock(root:)`'s call deleted
from `Frame.computeRootLayout` and `Deferred`'s `nested` `noteUnlowerable`
replaced by a no-op, plus a scratch test (`Tests/MetalUITests/ZZScratchS9.swift`,
deleted after) rendering each tree **as the root** of a plain 200×100 `Frame`
under `.proposal` with diagnostics on, printing the report and every hitbox.
The presented content is `PresentationLoweringTests`' `presented()` — a 10×10
`Box` with a background and an `onClick`, `.position(.absolute)`, right and
bottom insets 5 — inside a `Deferred`:

| arm (1.5's name) | report at `b9a5d7f` | report, reports removed | hitbox, reports removed |
|---|---|---|---|
| bordered root | `deferred.containingBlock` | `[]` | (185, 85) 10×10 |
| root width 100 in 200 | `deferred.containingBlock` | `[]` | (185, 85) 10×10 |
| auto root (control) | `[]` | `[]` | (185, 85) 10×10 |
| `Deferred` root | `deferred.root` | `[]` | (185, 85) 10×10 |
| inside a top/left-5 presentation | `deferred.nested` | `[]` | (185, 85) 10×10 |
| root `.frame(maxWidth: 100)` | `deferred.containingBlock` | `[]` | (185, 85) 10×10 |
| root `.frame(minWidth: 300)` | `deferred.containingBlock` | `[]` | (185, 85) 10×10 |
| inside a bordered `inset(0)` presentation | `deferred.nested` | `[]` | (185, 85) 10×10 |

(185, 85) is the window's width and height less the 5-point insets and the
box: the containing block is the window in every arm, as `LR-CL` constructs
it. The outer presentations in the two nested arms carry no `onClick`, so only
the inner box has a hitbox.

**The amended arm.** The same scratch plus `loweredComponentFrame`'s
`deferred.amended` `noteUnlowerable` deleted; `Box { PresentingSolo().width(70) }`
(a `Component` whose one member is a `Deferred` over a top/left-5 10×10
absolute box) and the same tree without `.width(70)`: both report `[]` and put
the hitbox at **(5, 5) 10×10** — the amend is dropped with nothing said. The
legacy amend overwrote the box's own width (divergence 48's mechanism). `LR-FF`
keeps the report and re-owns it to stage 11.

Everything was reverted (`git checkout Sources`, the scratch test removed;
`git status --short` showed only this design's files).

## 4. Critic round 1 (design, 2026-09-24)

Read against `caa331a`; ruling `LR-FH`, with amended paragraphs on `LR-FD`,
`LR-FF` and `LR-FG`. No `Sources/` or `Tests/` file changed.

- **Lane sizing, measured**: the old lane 1's 38 files are 24 985 lines with
  617 sites matching `compare(`/`WindowPair`/`AuthorityCoverage`/`.legacy`;
  the old lane 2's 35 files carry 252 sites of a deleted symbol. The
  `AuthorityCoverage` users and the differential-harness users overlap in five
  test files (49 of the 87 scenarios). Re-cut by harness: lane 1 −11 → 1441,
  lane 2 −32 → 1409, lane 3 +1 → 1410.
- **Labels**: thirteen retirements `LR-FF` marked "(R)" have no replacement
  test and are D (its amended paragraph lists them); the spec's §6 tables
  already read D for all but `noProductionFrameReachesTheLegacyEngine`, and
  §5 had two R rows. The stage total is unchanged.
- **M3a**: `reportPresentationContainingBlock(root:)` raises `deferred.root`
  as well as `deferred.containingBlock` (`Frame.swift:1833`), so restoring its
  call reddens five of N3.1's arms, not four.
- **SwiftUI**: one unprobed sentence (`LR-FD`'s "SwiftUI has no min-content
  concept for `Text`") struck; nothing else in the three documents claims
  SwiftUI behaviour, so no probe was re-run.
- **Coverage grep**: every test or probe file naming a deleted symbol is in a
  lane's list, or is `Fakes.swift`/the two guard files (lane 3),
  `Expected.swift` (comment), `ZZDemoPixels.swift` (lane 3's copy),
  `PortableTextDeterminismTests` (kept `PortableText` API) or the standalone
  modifier-composition kits.
- **Upheld**: the containing-block reports' deletion, `deferred.amended`'s
  re-ownership to 11, the plan's stale sentence waiting for the Record phase,
  lane 3 unsplit — reasons in `LR-FH` item 7.

## 5. Lane 1 — the differential harness and its users (2026-09-24)

Commits `1148ccb` (the collapse) and `e710e4b` (two site-coverage dropouts);
ruling `LR-FI`. Tests only: `git diff b9a5d7f e710e4b --stat -- Sources` is empty.
27 files: `LayoutDifferential.swift`, the 24 users spec §4 lists, and the
registry's two literals (`AuthorityCoverage.swift`, `ZZAuthorityRollCall.swift`).

### 5.1 The base set (before any edit)

Ma–Me (spec §6 lane 1, spelled in the probe file's header) each applied to
`3828612` (= `b9a5d7f` plus design docs; no `Sources/`/`Tests/` difference),
full unfiltered suite, restored from a copy, `git status --short` empty after
each. Every reddened test with its issue count is in
`docs/probes/stage-9-site-coverage.txt` (`## base`): **Ma 20** tests (134
issues), **Mb 56** (336), **Mc 7** (40), **Md 9** (57), **Me 13** (106). This is
the stage's base set, which lanes 2 and 3 re-read (`LR-FH` item 2), **with the
parsing rule the probe file's header states**: a reddened test is a `Test NAME(…)
failed after … with N issues.` line **or** a parameterised `Test NAME(_:) with K
test cases failed after … with N issues.` line, and the per-test issue counts
must sum to the summary line's total (all ten runs in the file pass that check).

*Corrected in lane 1's fix round.* The lane first published **Mb 52, Mc 6, Md 2,
Me 8**: its extraction matched only the first form and so dropped every
parameterised test — Mb's `aDeferredScrollViewNestedInAnotherEscapesItsClipForHitTesting`,
`aListsSceneAndHitboxesAreUnchangedByTheGroup`,
`aRowTallerThanRowHeightIsFlooredAtRowHeightNotContent` and
`paddingOnAListDoesNotShrinkItsRowsBelowRowHeight`; Mc's
`theIndicatorIsClippedByTheViewportsRoundedCornerWithoutScrollingWithIt`
(lane 2's); seven `ListTests` scenarios of Md; and five `PresentationWindowTests`/
`AbsoluteOverlayTests` scenarios of Me, among them lane 2's
`anAbsoluteBoxInsideAScrollViewIsStillClippedAndScrolledByIt`. Those are exactly
the scenarios lane 2 collapses, so the gap would have blinded its re-read. The
runs themselves stand (the issue totals reproduce); the lists were re-extracted
from the same logs.

### 5.2 The collapse, and the count

- `LayoutDifferential.swift` single-authority (`LR-FI` item 1).
- The five registry contributors' **49** scenarios collapsed (`ScrollRoutingTests`
  16, `ListTests` 21, `DeferredTests` 5, `PresentationWindowTests` 6,
  `DecorationPaintTests` 1): `arguments:`, the authority parameter,
  `AuthorityCoverage.record` and every per-authority branch removed.
  `AuthorityCoverage.expected` 87 → **38** names, the roll call's `#require`
  87 → 38 with its sum re-written (14 indicator + 4 `ScrollViewTests` + 3
  `AXNodeTests` + 6 `AccessibilityDefaultsTests` + 5 `AccessibilityTreeTests` + 1
  `FocusTests` + 1 `TombstoneTests` + 2 `MeasurePerformanceTests` + 1
  `AbsoluteOverlayTests` + 1 `EnvironmentTests`); the roll call stays green.
- Every differential test: literals kept, agreement assertions deleted, a
  literal added where only the agreement carried a named observation (§5.4).
- Loops over `[LayoutAuthority.legacy, .proposal]` collapsed to the proposal
  iteration (T); `layoutAuthority:` arguments, `lowersToProposal` branches,
  `pass.frame.requestNode`/`requestLeaf` and `site: .customElement` gone from
  every file of the lane.
- `PresentationLoweringTests` 1.5: the seven containing-block arms removed, the
  `ScrollView`-without-`Deferred` arm added (`[box.position, box.inset]`,
  divergence 11's proposal fact), `#require` 18 → **12**.
  `everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn`: the two `customElement`
  arms and the bordered-root `deferred.containingBlock` arm removed, 11 → 9
  (`LR-FI` item 4).

**Retirements, 11 rows** (spec §6 lane 1's table, numbers kept):

| # | test (file) | row | replacement / concept |
|---|---|---|---|
| 2 | `theDifferentialHarnessSeesAOnePointDisagreementAtExactlyThatElement` (`LayoutAuthorityTests`) | D | the two-engine comparison |
| 3 | `theDifferentialHarnessComparesPaintHitboxesAccessibilityAndState` (`LayoutAuthorityTests`) | D | the two-engine comparison |
| 4 | `aFrameAndAWindowDefaultToTheProposalAuthority` (`LayoutAuthorityTests`) | D | an authority default |
| 5 | `aWindowBuildsEveryFrameUnderItsLayoutAuthority` (`LayoutAuthorityTests`) | D | a window's authority |
| 6 | `aCustomElementsLegacyRegistrationTrapsUnderTheProposalAuthority` (`LayoutAuthorityTests`) | R | lane 3's G6a |
| 7 | `aDeprecatedRegistrarStillLaysOutUnderTheLegacyAuthorityAndTrapsUnderTheProposalOne` (`LayoutAuthorityTests`) | R | G6a |
| 8 | `aSiteThatSkipsItsOwnCheckIsStoppedByFramesBackstop` (`LayoutAuthorityTests`) | D | `Frame`'s legacy backstop |
| 10 | `aLegacySpelledListRowAbortsAProductionProposalFrame` (`ListTests`) | R | G6a |
| 16 | `theLegacyHiddenPathPaintsAndHitTestsExactlyAsBefore` (`HiddenLoweringTests`) | D | the legacy hidden path |
| 17 | `aPresentationTrapsAProductionProposalFrameNamingItsField` (`PresentationLoweringTests`) | R | N3.1 |
| 18 | `anIdealDimensionOnTheLegacyFrameTraps` (`FrameSizingTests`) | D | `LR-H`'s legacy ideal trap |

**Count**: unfiltered `swift test --build-system native --no-parallel` at
`1148ccb` and at `e710e4b` → **`Test run with 1441 tests in 3 suites passed`**
(1452 − 11 = 1441), the log carrying `FR-J no-argument frame: succeeded=`,
eleven gated tests skipped (unchanged), 0 `error:`, one `warning:` (SwiftPM's
notice); `swift build --build-tests` (default build system) at `e710e4b`: `Build
complete!`, 0 `error:`, 0 `warning:`.

### 5.3 T rows

**Renames, 46** (`LR-FE` item 6; old → new; each test's doc names its old name):
`aLoweredRowAndColumnAgreeWithTheLegacyContainersOverFixedChildren` →
`aLoweredRowAndColumnPlaceFixedChildrenByGapAndCrossAlignment`;
`everyContainerFieldEitherLowersAndAgreesOrIsReportedByName` →
`everyContainerFieldEitherLowersOrIsReportedByName`;
`aLoweredRowOverflowsWhereTheLegacyRowShrinksItsChildren` →
`aLoweredRowLetsItsFixedChildrenOverflowItsDeclaredWidth`;
`aProposalElementInsideALoweredContainerLaysOutUnderTheProposalAuthorityAndTrapsUnderTheLegacyOne` →
`aProposalElementInsideALoweredContainerLaysOut`;
`aLoweredFixedSizeBoxAgreesWithTheLegacyBoxInEveryObservation` →
`aLoweredFixedSizeBoxPaintsAndHitTestsAtItsDeclaredSize`;
`aLoweredTextAgreesWithTheLegacyTextAtItsNaturalWidth` →
`aLoweredTextLaysOutAndDrawsAtItsNaturalWidth`;
`aLoweredTextHugsItsWidestLineWhereTheLegacyTextFillsItsContainingBlock` →
`aLoweredTextHugsItsWidestLineRatherThanFillingItsOffer`;
`aLoweredStackPlacesFixedChildrenAtAllNineAlignmentsAsTheLegacyStackDoes` →
`aLoweredStackPlacesFixedChildrenAtAllNineAlignments`;
`aLoweredStackOffersItsProposalWhereTheLegacyStackOffersFitContent` →
`aLoweredStackOffersItsChildItsProposal` (the collapsed test no longer asserts
the legacy half); `aLoweredPaddingLayerAgreesWithTheLegacyWrapper` →
`aLoweredPaddingLayerInsetsItsContentByEachEdge`;
`aLoweredFixedFrameLayerAgreesWithTheLegacyFrameOverAFixedChild` →
`aLoweredFixedFrameLayerPlacesAFixedChildAtEachAlignment`;
`aLoweredFlexibleFrameLayerTakesSwiftUIsAnswerWhereTheLegacyFrameClamps` →
`aLoweredFlexibleFrameLayerTakesSwiftUIsAnswer`;
`anIdealFrameLowersUnderTheProposalAuthorityAndStillTrapsUnderTheLegacyOne` →
`anIdealFrameLowersAtANilProposal`;
`spaceAroundAndSpaceEvenlyOverflowFromTheStartOnBothPaths` →
`spaceAroundAndSpaceEvenlyOverflowFromTheStart`;
`aComponentsWidthFramesEachMemberWhereTheLegacyAmendOverwritesIt` →
`aComponentsWidthFramesEachMember`;
`theOrderOfAComponentsDistributingModifiersIsObservableUnderBothAuthorities` →
`theOrderOfAComponentsDistributingModifiersIsObservable`;
`chainedComponentAmendsComposeTheSameWayUnderBothAuthorities` →
`chainedComponentAmendsCompose`;
`aFrameOverAMultiMemberComponentFramesEachMemberWhereTheLegacyLayerSqueezesThem` →
`aFrameOverAMultiMemberComponentFramesEachMember`;
`paddingOnALoweredTextPadsItWhereTheLegacyLeafIgnoresIt` →
`paddingOnALoweredTextPadsItsLeaf`;
`aDeclaredSizeBelowThePaddingKeepsTheFrameWhereCSSFloorsTheBox` →
`aDeclaredSizeBelowThePaddingKeepsItsFixedFrame`;
`theStageOneCorpusLowersWithNoDiagnosticAndAgreesElementByElement` →
`theStageOneCorpusLowersWithNoDiagnostic`;
`theStageOneCorpusPinsEveryKnownDisagreementWithItsProbeArm` →
`theStageOneCorpusPinsEachSwiftUIAnswerWithItsProbeArm`;
`anAlignSelfWrapperFillsAnIndefiniteContainerWhereCSSHugs` →
`anAlignSelfWrapperFillsAnIndefiniteContainer`;
`anAlignSelfInsideAOneChildWrapperFillsTheWrapperWhereCSSIgnoresIt` →
`anAlignSelfInsideAOneChildWrapperFillsTheWrapper`;
`growingSiblingsShareTheSurplusEquallyWhereCSSAddsItToTheirBases` →
`growingSiblingsShareTheSurplusEqually`;
`theDemosBodyRowKeepsTheSidebarAtItsDeclaredWidthWhereCSSShrinksIt` →
`theDemosBodyRowKeepsTheSidebarAtItsDeclaredWidth`;
`aGrowInsideAOneChildPaddingFillsTheWrapperWhereCSSLeavesItUngrown` →
`aGrowInsideAOneChildPaddingFillsTheWrapper`;
`aLoweredScrollViewAgreesWithTheLegacyEngineOnEveryBoundedShape` →
`aLoweredScrollViewLaysOutEveryBoundedShape`;
`aLoweredScrollViewFillsItsProposalOnTheScrollingAxisWhereTheLegacyViewportHugs` →
`aLoweredScrollViewFillsItsProposalOnTheScrollingAxis`;
`aLoweredHorizontalScrollViewIsBoundedByItsParentWhereTheLegacyOneOverflows` →
`aLoweredHorizontalScrollViewIsBoundedByItsParent`;
`aLoweredWindowDispatchesClicksFocusAndKeysToTheSameElements` →
`aLoweredWindowDispatchesClicksFocusAndKeys`;
`aLoweredWindowPublishesTheSameAccessibilityTree` →
`aLoweredWindowPublishesItsAccessibilityTree`;
`aLoweredTreeMintsTheSameStateSlotsAndAnimatesTheSameWidths` →
`aLoweredTreeMintsItsStateSlotsAndAnimatesItsWidths`;
`anAbsoluteBoxStretchedBelowItsPaddingKeepsItsInsetBoxWhereTheLegacyEngineFloorsIt` →
`anAbsoluteBoxStretchedBelowItsPaddingKeepsItsInsetBox`;
`anAbsoluteTextWrapsAtTheWindowMinusItsInsetWhereTheLegacyEngineWrapsAtTheWindow` →
`anAbsoluteTextWrapsAtTheWindowMinusItsInset`;
`aFramedAbsoluteBoxIsAPresentationRootUnderBothAuthorities` →
`aFramedAbsoluteBoxIsAPresentationRoot`;
`aLoweredListAgreesWithTheLegacyEngineOnEveryWindowedShape` →
`aLoweredListLaysOutEveryWindowedShape`;
`aLoweredListsRowIdentitiesAreTheLegacyOnes` →
`aLoweredListsRowsAreNamedDirectlyUnderTheList`;
`theDifferentialRootPlacesItsContentTopLeadingAtItsSizeUnderBothAuthorities` →
`theDifferentialRootPlacesItsContentTopLeadingAtItsSize`;
`aDeferredAbsoluteScrimCoversTheWindowAndEscapesTheScrollUnderBothAuthorities` →
`aDeferredAbsoluteScrimCoversTheWindowAndEscapesTheScroll`; and
`PresentationWindowTests`' six (`theDemoModalDismissesOnAScrimClickAndSwallowsTheWheel`,
`aPresentationInsideAFadedSubtreeIsStillFaded`,
`aPresentationKeepsItsDeclaringScopesEnvironment`,
`aPresentationPublishesItsAccessibilityRecordAndTakesFocus` (from
`aPresentationsAccessibilityRecordAndFocusMatchUnderBothAuthorities`),
`anAnimatedInsetInterpolatesItsValue`, `nestedPresentationsLandOnOneLayer`,
each from its `…UnderBothAuthorities` spelling).

**Other T rows** (arms or spellings changed, no expected value re-valued):
1.5 and `everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn` (§5.2);
`aComponentAmendDoesNotTrapUnderTheProposalAuthority` loses its absence check of
`SA-G`'s `setStyle` message (lane 3 deletes the precondition; the `.success` exit
sees any trap); `aProposalTextBelowItsWidestBrokenLineAnswersTheProposal`'s
discriminator bound re-spelled off `ShapingCache.minContentWidth` (`LR-FI` item
6); `anItemFieldNoLoweredContainerConsumesIsReportedByName`'s four root arms
assert their recorded answer (all ignored by the legacy root) directly; every
collapsed loop and scenario; `ListLoweringTests.LoweredProbeLeaf` and
`ListTests.Row` at `site: .box`.

### 5.4 The literals the agreement carried

Derived by hand before the run; the two that read red on the first run are
recorded as found (`LR-FI` item 3):

- **First-run red lines** (unfiltered run on the uncommitted collapse, `Test run
  with 1441 tests in 3 suites failed … with 5 issues`):
  `aLoweredScrollViewLaysOutEveryBoundedShape() recorded an issue at
  LoweringScrollTests.swift:665:23: Expectation failed: r.bounds[id] == rect`
  and `… r.hitboxRects == regions` (A8: 160×60, derived 80×60);
  `reversingKeepsIdentityPaintOrderHitOrderAndAccessibilityOrder() recorded an
  issue at LoweringDistributionTests.swift:520:9: Expectation failed:
  reversed.frame.stateTable.ids.contains(slot)` ×3 (no `$state0` for an
  unwritten `@State`; `$ax` used).
- **Added**: container 3.4's chrome (8 glyphs, the two buttons' hitboxes and
  accessibility frames), 3.5's five lane-5 arms' rects; leaf 2.1 (scene rect,
  hitbox, accessibility frame, px and rem), 2.4's twelve `Text` arms (the natural
  rect), 2.5's eight arms (rect, glyph count, no hitbox, accessibility text and
  frame, tint reaches the glyphs), 2.6 and stack 4.2's separating `#require`
  (widest line < 60), 2.8's glyph rows per arm; stack 4.3's six glyphs;
  distribution 5.7's paint, hit and accessibility order and `$ax` slots; item
  1.10's decoration, hitbox, accessibility frame and wrap rows (120 and 4), 1.13's
  four root arms, 1.14's and 2.12's row rects (§5.5); scroll 2.1's A1/A5/A8/A9
  rects, scenes and scroll regions, 2.3's region (divergence pin, proposal-only),
  2.4's accessibility frame (divergence pin, proposal-only); parity 5.4's hitboxes
  and glyph count; presentation 1.1's hitbox and background, 1.4's hitbox in all
  six arms and the column's third child at y 22; list 2.1's B4 (layer, list,
  rows, window 3…16), 2.6's rows, 2.8's identity structure; the demo census's
  `Deferred` and scrim at 920×560.
- **Confirmed against the legacy arm** (`LR-FI` item 2): a scratch patch to
  `LayoutDifferential.report` (legacy root inlined, `ProbeLeaf` and
  `LoweredProbeLeaf` given back their legacy branch; reverted, `git status` then
  showing only the lane's files) printed `ORACLE AGREE` for every arm of the 14
  tests carrying an added literal through `report` (3.4, 3.5, 2.1, 2.4, 2.5, 4.3,
  5.7, 1.10, 1.1, 1.4, list 2.1's B1/B5/B6, list 2.6, scroll 2.1, stack 4.1), and `ORACLE
  DIFFER` exactly on the divergence pins (scroll 2.3, 2.4, stack 4.2, the demo
  census) where the added literal is proposal-only or was already compared on
  both sides. The windowed list arms and the parity windows are covered by
  `LR-FI` item 2(b).

### 5.5 The site-coverage re-run at the head

Ma–Me at `1148ccb`, then all five re-run at `669e487` (= `e710e4b`'s tests plus
docs) in lane 1's fix round, both extracted with §5.1's rule (probe file, the two
`## head` sections): at `669e487` **Ma 20** (96 issues), **Mb 56** (264), **Mc 7**
(24), **Md 9** (81), **Me 13** (62). **Every base test reddens at the head under
its own name or its renamed self** (`LR-FE` item 6). At `1148ccb` two Mb tests did
not — `aStretchedUnsizedSpaceDistributionContainerIsReported` and
`aGrownUnsizedSpaceDistributionContainerIsReported`, whose controls' agreement
alone saw the grown/stretched row's own rect (Mb 54 tests, 260 issues). Each gained
that rect as a literal (`e710e4b`: 200×10, 260×10), and both redden since (2 issues
each). No base test is a retired row of this lane. **There are no head-only reds
beyond the renames**: the "head-only" tests the lane first listed for Md and Me
were the same parameterised scenarios the base extraction dropped — collapsed,
they print as `NAME()` at the head and were therefore matched there only.

### 5.6 The demo

The fourteen-image comparison, `b9a5d7f` → `1148ccb`: **0 differing, scene
identical, in all fourteen**. The committed `ZZDemoPixels.swift` traps at
`1148ccb` (its `chrome-legacy` image puts the now native-only `DifferentialRoot`
under `.legacy`: `LayoutTree.swift:765: Fatal error: native layout subtree
contains a legacy node`), so the comparison ran `compare.sh` from a scratch copy
whose `ZZDemoPixels.swift` inlines the pre-stage-9 root as `PixelsLane1Root`
(both commits built with the same file). Controls at `b9a5d7f`: light vs dark
1048576, default vs modal 1031003, default vs animation 454895, f0 vs f3 0,
preview light vs dark 1048576, chrome legacy vs proposal 0, distinct 544 / 216,
prod default vs modal 491221, indicator rects 0. **Two controls differ from the
values `compare.sh`'s header quotes** (1030498, 210027) — those were recorded
before stage 6b moved the demo onto the proposal engine; the header's numbers,
not the harness, are stale (lane 3 owns the file).

### 5.7 Handed on

- **Lane 2**: stale citations of this lane's renamed tests in its files —
  `ComponentTests.swift:28`, `ElementGroupTrapTests.swift:422`,
  `OuterModifierMatrixTests.swift:857`, `ElementLayoutTests.swift:17`,
  `EnvironmentTests.swift:715`; `AuthorityCoverage.swift`'s docs (the registry
  it deletes).
- **Lane 3**: stale citations in `Sources/` doc comments — `Component.swift:277,
  349, 366`, `Passes.swift:49`, `Frame.swift:1542, 1568`, `ModifiedElement.swift:82`,
  `Box.swift:984`, `ListRows.swift:124`, `Rounding.swift:49–50`,
  `ElementGroup.swift:685`; the pixel harness (§5.6); `compare.sh`'s control
  values. `RootFieldLoweringTests`' root-margin arm named its field's owner as
  stage 9 in its doc ("a root **margin** (owner 9)") and no row of spec §5 names
  it. *Resolved in lane 1's fix round*: `LR-ER` item 4 (stage 8) already disposes
  `LR-DI` item 4's root min/max/**margin** — the report stays and dies with its
  field at **stage 10** — so the owner is 10, not 9; the doc now says so (`LR-FI`,
  amendment). Its trap stands (`box.margin.unconsumed`), unchanged.
- **Exit-criterion grep survivors in this lane's files**, all historical doc
  text: `LayoutAuthorityTests.swift:76` (`layoutAuthority`), `:177`
  (`customElement`), `ListLoweringTests.swift:72`, `ListTests.swift:25, 847`,
  `LoweringCorpusTests.swift:172`, `ScrollRoutingTests.swift:515, 775`
  (`customElement`), `LoweringLeafTests.swift:497` (`textMeasure`), `:502`
  (`minContentWidth`).

## 6. Lane 2 — the registry's other contributors, and every other test that names a deleted symbol (2026-09-24)

Commit `9786c37`; ruling `LR-FJ`. Tests only: `git diff 7de7ccd 9786c37 --stat --
Sources` is empty. The static census grep, re-run at the lane's base (`7de7ccd`),
found no test file outside spec §4's lane-1, lane-2 and lane-3 lists
(`Tests/MetalUICrossPlatformTests/Expected.swift` names `.legacy` in a comment,
left unedited; `Tests/PortableTests`' hits are `PortableText`'s kept content sizes).

### 6.1 The collapse, and the count

- The ten remaining registry contributors' **38** scenarios collapsed
  (`ScrollIndicatorTests` 14, `ScrollViewTests` 4, `AXNodeTests` 3,
  `AccessibilityDefaultsTests` 6, `AccessibilityTreeTests` 5, `FocusTests` 1,
  `TombstoneTests` 1, `MeasurePerformanceTests` 2 plus the gated 100k twin,
  `AbsoluteOverlayTests` 1 — retired, L1-15 — and `EnvironmentTests` 1);
  `AuthorityCoverage.swift` and `ZZAuthorityRollCall.swift` deleted.
- Every `layoutAuthority:`/`authority:` argument (all `.proposal` or the
  default; the `.legacy` ones were the retired N9 pins, the loops and the
  tokenizer pins), every helper's authority parameter, every `lowersToProposal`
  branch and `pass.frame.requestNode`, every `site: .customElement` (to `.box`)
  and every `window.layoutAuthority == .proposal` precondition removed from the
  lane's files; the one loop over both authorities outside the registry
  (`modifierOrderChangesSizeAndPlacementAsSwiftUIDoes`) keeps its proposal
  iteration.
- `MeasurePerformanceTests`' `aListsWorkIsTheSame…` pair lost their tokenizer
  half (the `runCallCounter` it counted is deleted, `LR-FD`); the native work
  literals and the cache-entry equality carry them. `theShapingCacheStaysNear…`
  lost its min-content dictionary bound (the dictionary is deleted).

**Retirements, 33 rows** (spec §6 lane 2's 32, plus row 26, `LR-FJ` item 1):

| # | test (file) | row | replacement / concept |
|---|---|---|---|
| 1–4 | `aProposalElementInsideALegacyContainerTrapsAtRegistration`, `aLegacyStyleModifierOnAProposalComponentTrapsAtRegistration`, `aPaddingModifierOnAProposalComponentTraps`, `aProposalMarkedElementThatRegistersALegacyNodeTrapsInsideAProposalContainer` (`NativeBoundaryIntegrationTests`, file deleted) | D | `SA-G`'s mixed tree |
| 5 | `anOrphanLegacyRegistrationBesideATypedLeafIsNotRejected` (`ProposalNodeIDTests`) | D | a legacy registration |
| 6 | `noProductionFrameReachesTheLegacyEngine` (`RootSwitchTests`) | D | the legacy root-layout counter and branch (stage 10's symbol check handed on) |
| 7–10 | `theThreeSizingModesAnswerWithCoreTextsOwnNumbers`, `minContentIsTheLongestRunNotTheWidestCharacter`, `anExplicitKnownSizeWinsOverTheMeasuredOne`, `aZeroAvailableExtentMeasuresRatherThanTraps` (`TextMeasureTests`) | D | the CSS measure function and its known/available pair |
| 11–12 | `unbreakableRunsAreLineBreakOpportunitiesNotWordBoundaries`, `runsAreTrimmedOfTrailingWhitespaceAndBlankOnesAreDropped` (`UnbreakableRunsTests`, file deleted) | R | `ContentSizeOracleTests`' `everyClassPairBreaksAsCoreTextDoes`, `maxContentIsTheWidestHardLineAndRunsCarryNoTrailingSpace` |
| 13–14 | `aMinContentMissReusesOneTokenizerRatherThanCreatingOnePerString`, `theReusedTokenizerAnswersExactlyAsAFreshOneDoes` (`TokenizerReuseTests`, file deleted) | D | tokenizer min-content |
| 15–17 | `aSecondMinContentQueryTokenizesNothing`, `theMemoizedWidthEqualsTheMaxOverIndependentlyShapedRuns`, `aCounterOnlyCountsCallsWithinItsOwnBinding` (`ShapingCacheTests`) | D | the min-content memo and its counter |
| 18 | `leavesCarryAMeasureFunctionAndBranchesDoNot` (`LayoutTreeTests`) | D | the CSS `MeasureFunction` |
| 19–24 | `aNativeNodeRegisteredUnderALegacyNodeTraps`, `aLegacyNodeRegisteredUnderANativeStackTraps`, `aLegacyNodeRegisteredUnderACustomLayoutTraps`, `aStyleWrittenOntoANativeNodeTraps`, `setStyleOnALegacyNodeDuringNativeLayoutTraps`, `registeringALegacyLeafDuringNativeLayoutTraps` (`NativeBoundaryTrapTests`) | D | `SA-G`'s legacy half, `setStyle`, `newLeaf` |
| 25 | `aLegacyNodeUnderAGridOrCarryingAGridMarkTraps` (`NativeGridTrapTests`) | D | a legacy node under a grid |
| 26 | `aMinContentHitReStampsSoItSurvivesASweepingLoad` (`ShapingCacheTests`) | R | `aSweepNeverDropsAnEntryTheCurrentFrameTouched` (Mr, §6.4) |
| L1-1 | `everyParameterisedScenarioRanUnderBothLayoutAuthorities` (`ZZAuthorityRollCall`, file deleted) | D | "both authorities ran" |
| L1-9 | `aLegacySpelledAXListRowAbortsAProductionProposalFrame` (`AXNodeTests`) | R | lane 3's G6a |
| L1-11 | `aLegacySpelledStatefulListRowAbortsAProductionProposalFrame` (`MeasurePerformanceTests`) | R | G6a |
| L1-12 | `aLegacySpelledExcursionRowAbortsAProductionProposalFrame` (`TombstoneTests`) | R | G6a |
| L1-13 | `aColdFrameCreatesAtMostOneLineBreakTokenizer` (`MeasurePerformanceTests`) | D | tokenizer min-content |
| L1-14 | `aWarmFrameTokenizesEachDistinctStringAtMostOnce` (`MeasurePerformanceTests`) | D | tokenizer min-content |
| L1-15 | `anAbsoluteBoxInsideAScrollViewIsStillClippedAndScrolledByIt` (`AbsoluteOverlayTests`) | R | 1.5's `ScrollView` arm (lane 1); its `Deferred` escape half is `DeferredTests`' `aDeferredAbsoluteScrimCoversTheWindowAndEscapesTheScroll` and the portal mask tests |

The two exit tests' positive controls stay as tests of their own fact
(`aBoxSpelledListRowDoesNotAbortAProductionProposalFrame`,
`aBoxSpelledRowInTheResidentSetFixtureDoesNotAbort`: a production frame over a
`Box`-spelled row completes).

**Count**: unfiltered `swift test --build-system native --no-parallel` at
`9786c37` → **`Test run with 1408 tests in 3 suites passed`** (**1441 − 33 =
1408**, read off the test-name sets of the two logs: 35 names gone, 2 of them
renames), the log carrying `FR-J no-argument frame: succeeded=`, eleven gated
tests (unchanged: `aListsWorkIsTheSameFor100kRowsAsFor500` and
`measureContentSizeDifferences` collapsed and stay gated), 0 `error:`, one
`warning:` (SwiftPM's notice); `swift build --build-tests` (default build
system): `Build complete!`, 0 `error:`, 0 `warning:`.

### 6.2 T rows

- **Renames**: `aFieldLaysOutAndEditsUnderBothAuthorities` →
  `aFieldLaysOutGreedilyAndEdits` (gains the centring control, §6.3);
  `treeStoresStyleAndChildren` → `treeStoresChildren` (the style half read the
  deleted rows).
- **Re-spelled native** (`LayoutTreeTests`): the six id/reset/adoption exit tests
  and three plain tests mint with `newNativeLeaf`, adopt with `newNativeOverlay`
  (the foreign child now traps at `nativeNode(_:)`'s `slot(_:)` with the same
  "outlived the tree" message); `everyNativeRegistrarAcceptsNativeChildrenWithoutTrapping`
  drops its `isNativeLayoutNode`/`style == .default` preconditions (keeps
  `nodeCount == 29`, adds `ids.count == 13`);
  `nativeLayoutHoldsTheLayingOutFlagOnlyWhileItRuns` probes the flag with a
  native registration after the call.
- `TextHardLineBreakTests.aLabelWithHardBreaksMeasuresItsWidestLineAtMaxContent`
  on `CoreTextTextSystem.measure(_:font:wrappingAt:)` (nil and 400), same
  CoreText oracles.
- `ShapingCacheTests.anEntrySurvivesExactlyTwoUntouchedSweptFrames` on
  `shaped(_:font:wrappingAt:)` and `misses`.
- `ContentSizeOracleTests`' seven Apple-arm tests: the reference moved
  (§6.5). `TextSystemSeamTests.aPortableFrameNeverShapesThroughCoreText`: the
  loop over both authorities and its min-content assertion gone, a control
  added (§6.3).
- `RootSwitchTests.aHuggingLegacyRootIsCentredInAProductionWindow` and
  `everyProductionRootsDeepestNativeLevelIsMeasured` unchanged apart from the
  helper's argument; `ModifiedElementTests.ChainLeaf` a declared-size native leaf;
  every collapsed scenario; lane 1's five stale citations (§5.7) and
  `StackElementTests`' one corrected.

### 6.3 The two positive controls, red once

- **C1** (`Sources/MetalUI/TextField.swift`, `geometry`'s `lineY` read as the
  bounds' top), full unfiltered suite: `Test run with 1408 tests in 3 suites
  failed … with 1 issue` — `aFieldLaysOutGreedilyAndEdits() recorded an issue at
  TextFieldTests.swift:280:5: Expectation failed:
  tallTarget.caretRect.origin.y.value == tallCentred`. The one-line arm stayed
  green, as §6.2 says it must.
- **C2** (the control frame given the portable system, test-side): `… failed …
  with 1 issue` — `aPortableFrameNeverShapesThroughCoreText() recorded an issue at
  TextSystemSeamTests.swift:133:5: Expectation failed: controlCache.storageCount > 0`.

Both restored from a copy, `git status --short` empty after.

### 6.4 Mutations

Each applied to `9786c37`, full unfiltered suite, restored from a copy,
`git status --short` empty after; reds read with §5.1's rule.

| mutation | reddened (issues) |
|---|---|
| **M2a** `slot(_:)`'s generation check deleted, at `9786c37` | `usingAnIdAgainstAnotherTreeTraps` (2), `adoptingAChildFromAnotherTreeTraps` (1), `aTypedNodeIDStoredFromAnEarlierFrameTraps` (1) — 4 |
| **M2a** at the lane's base (`7de7ccd`'s tests) | the same three names (2, 2, 1) — 5; `anIdFromBeforeAResetIsNotCurrentAfterIt` reads `isCurrent` directly and reddens at neither |
| **M2b** the oracle's trailing-whitespace trim dropped | `everyClassPairBreaksAsCoreTextDoes` (1), `everyCorpusStringButThaiSplitsIntoCoreTextsRuns` (27), `germanQuotesWrapWhereCoreTextsTypesetterLeavesItsTokenizer` (1), `minAndMaxContentMatchMetalUIsApplePathForEveryCoveredString` (136), `thaiBreaksOnlyAtSpacesWhereCoreTextUsesADictionary` (1) — 166 |
| **M2c** `appendNode`'s SA-I precondition deleted | `registeringANativeNodeDuringNativeLayoutTraps` (2) only (`LR-FJ` item 2) |
| **M2c′** `appendNode` refuses any registration after a completed native run | `nativeLayoutHoldsTheLayingOutFlagOnlyWhileItRuns` (1), `anInfiniteAxisSharesInfinityAfterAnInfiniteCommittedColumn` (1), then an in-process trap at `aResetTreeMeasuresItsNewRe…` truncates the run (signal 5): an incomplete set |
| **Mr** `shaped`'s hit branch stops re-stamping | `aSweepNeverDropsAnEntryTheCurrentFrameTouched` (1) only — row 26's replacement |
| **Ms1** `staleAfterGenerations` 2 → 1 | `anEntrySurvivesExactlyTwoUntouchedSweptFrames` (1) only |
| **Ms3** `staleAfterGenerations` 2 → 3 | `anEntrySurvivesExactlyTwoUntouchedSweptFrames` (1) only |

### 6.5 The oracle's moved reference

`measureContentSizeDifferences` (`METALUI_CONTENT_MEASURE=1`, filtered — a
measurement, not a count) at the lane's base, stashed, and at `9786c37`: the 62
lines from `RUNS …` to `SIZES …` are **byte-identical** (md5
`4696f1d2513fe815c5313e0bdb9cf4e9` both): `RUNS differing=1 of 35` (Thai),
`SIZES cases=280 minDiffs=24 maxDiffs=32` (the uncovered strings, `LB-N`).

### 6.6 The site-coverage re-run at the head

Ma–Me at `9786c37`, extracted with §5.1's rule, every run's per-test issues
summing to its summary line (probe file, lane 2's head section): **Ma 20** (96),
**Mb 56** (264), **Mc 7** (24), **Md 9** (81), **Me 12** (61). Against lane 1's
head every test reddens again under the same name — the scenarios lane 2
collapsed (Mc's indicator clip) now print as `NAME()` — and the one dropout is
Me's `anAbsoluteBoxInsideAScrollViewIsStillClippedAndScrolledByIt`, retired row
L1-15 (1 issue; 62 → 61). No head-only reds.

### 6.7 The demo

`compare.sh` from lane 1's scratch copy (§5.6), `b9a5d7f` → `9786c37`: **0
differing, scene identical, in all fourteen**; the controls read exactly §5.6's
values (1048576, 1031003, 454895, 0, 1048576, 0, 544, 216, 491221, 529, 0).

### 6.8 Handed on

- **Lane 3**: `Fakes.swift`'s `makeFakeWindow(layoutAuthority:)` has no test
  caller left (only the committed `ZZDemoPixels.swift`, lane 3's); the exit-criterion grep's survivors in lane 2's files
  are doc text only — `EnvironmentTests.swift:1084` (`MeasureFunction`),
  `ComponentTests.swift:112` (`requestNode(`), `MeasurePerformanceTests.swift:167`
  and `:573` (`unbreakableRuns`). Lane 3's count is **1408 + 1 = 1409**
  (`LR-FJ` item 1).

## 7. Lane 3 — the deletion (2026-09-24)

Commits: `4f43d8b` (N3.1, red), `4988ec7` (the deletion), `a801871` and
`35f1ffb` (the pixel harness). Ruling `LR-FK`.

### 7.1 N3.1, red first

`aPresentationsContainingBlockIsTheWindowWhateverSurroundsIt`
(`Tests/MetalUITests/PresentationContainingBlockTests.swift`), filtered at
`a84db27`: 8 issues — `bordered root`, `root width 100 in 200`,
`root .frame(maxWidth: 100)` and `root .frame(minWidth: 300)` reported
`["deferred.containingBlock"]`; `Deferred root` `["deferred.root"]`;
`inside a top/left-5 presentation` and `inside a bordered inset(0) presentation`
`["deferred.nested"]`; and `deferred.amended is owned by stage 9`. Every arm's
hitbox already read (185, 85) 10×10 — diagnostics mode reports and lays out, as
§3 measured. Green at `4988ec7`.

### 7.2 The count

Unfiltered, after `swift package clean`, `swift build --build-system native
--build-tests` (0 `error:`, the one `warning:` SwiftPM's notice) then `swift
test --build-system native --no-parallel`: **`Test run with 1409 tests in 3
suites passed`**, the log carrying `FR-J no-argument frame: succeeded=`.
**1408 + 1 = 1409** (N3.1; no test removed by this lane). `swift build
--build-tests` under the default build system: 0 `error:`, 0 `warning:`.
Guards **79** (G1, G6a, G5 re-spelled; G6a renamed
`aPlainImportCallerOfTheLegacyRegistrarsNoLongerCompiles`, a T row;
`typecheckFile`'s helper count unchanged); goldens 0; eleven gated tests.
`grep -h '^import' Sources/MetalUILayout/*.swift | sort -u` reads
`import MetalUICore` alone. `git ls-files Sources/MetalUILayout` lists none of
the seven engine files.

| row | test | label | note |
|---|---|---|---|
| L3-1 | `aPlainImportCannotChooseTheLayoutAuthority` (`LayoutAuthorityCompileGuards`) | T | reads `has no member 'layoutAuthority'` |
| L3-2 | `aPlainImportCallerOfTheLegacyRegistrarsIsWarnedTowardTheNativeOnes` → `aPlainImportCallerOfTheLegacyRegistrarsNoLongerCompiles` | T | renamed; reads both `has no member` messages |
| L3-3 | `layoutPassStyleAccessorsAreNotPublic` (`ErasureCompileGuards`) | T | reads `has no member 'style'` |
| L3-4 | `aPresentationsContainingBlockIsTheWindowWhateverSurroundsIt` | added | N3.1 |

### 7.3 Mutations

Each applied to the committed tree (`4988ec7`'s sources), full unfiltered
suite, restored from a copy, `git status --short` clean after; reds read with
§5.1's rule, per-test issues summing to the summary line's.

| mutation | reddened (issues) |
|---|---|
| **M3a** `reportPresentationContainingBlock(root:)` and its call restored | N3.1 (5) — the four `deferred.containingBlock` arms and the `Deferred`-root arm |
| **M3b** `Deferred`'s nested report restored (with `presentationsBefore`, `presentationCoversWindow`) | N3.1 (2) — the two nested arms |
| **M3c** `.deferred`'s `owningStage` back to `"9"` | N3.1 (1) — the amended arm |
| **M3d** internal `var layoutAuthority = 0` on `Window` | `aPlainImportCannotChooseTheLayoutAuthority` (1) |
| **M3e** public deprecated `requestNode(style:children:)` restored on `LayoutPass`, body `fatalError()` | `aPlainImportCallerOfTheLegacyRegistrarsNoLongerCompiles` (1) |
| **M3f** internal `func style(_:)` restored on `LayoutPass` | `layoutPassStyleAccessorsAreNotPublic` (1) |
| **M3g** `Frame.isHidden` returns `false` | `hiddenContentIsNotPublishedButAZeroHeightNodeIsAndADuplicatedIDIsPublishedOnce` (3), `aHiddenRootPublishesNothing` (2), `aHiddenInnerModifierLayerSuppressesEverythingInsideIt` (2), `aHiddenOneNodeFrameLayerPublishesNothingToAnAccessibilityClient` (8) — all `AccessibilityTreeTests`; `aListInsideHiddenContentIsNotPublishedEvenOnItsUnboundedFrame` (2, `AccessibilityDefaultsTests`); `aHiddenTextIsHiddenUnderTheProposalAuthority` (1, `HiddenLoweringTests`) — 18; no `AXNodeTests` test (`LR-FK` item 2) |
| **M3h** `computeRootLayout` skips the presentations loop | 17 tests, 86 issues: `aDeferredAbsoluteBoxLowersAgainstTheWindowOnEveryInsetShape` (40), `aPresentationPlaceholderIsDroppedByEveryLoweredContainer` (8), `theWholeDemoReportsExactlyTheFieldsAndSitesLaterStagesOwn` (7), N3.1 (7), `aDeferredAbsoluteBoxResolvesItsInsetsAgainstTheWindowAndLeavesTheFlow` (6), `aFramedAbsoluteBoxIsAPresentationRoot` (4), `anAbsoluteTextWrapsAtTheWindowMinusItsInset` (2), `theDemoModalDismissesOnAScrimClickAndSwallowsTheWheel` (2), `aPresentationPublishesItsAccessibilityRecordAndTakesFocus` (2), and one each: `aDeferredAbsoluteScrimCoversTheWindowAndEscapesTheScroll`, `anAbsoluteBoxStretchedBelowItsPaddingKeepsItsInsetBox`, `presentationsAreLaidOutBeforeTheRootSoTheRootsWorkRecordIsUnchanged`, `aFramesOwnBoundsOnAnAbsoluteAutoAxisAnswerAsSwiftUIsFrameDoes`, `aPresentationInsideAFadedSubtreeIsStillFaded`, `aPresentationKeepsItsDeclaringScopesEnvironment`, `anAnimatedInsetInterpolatesItsValue`, `nestedPresentationsLandOnOneLayer` |

The guards' red-before is M3d–M3f (`LR-FK` item 4): each re-spelling landed in
the deletion commit.

### 7.4 The site-coverage re-run at the head

Ma–Me at lane 3's head (probe file, lane 3's section; Md re-anchored to the
same line's current spelling): **Ma 20** (96), **Mb 56** (264), **Mc 7** (24),
**Md 9** (81), **Me 13** (68). Against lane 2's head every test reddens again
under the same name; the one head-only red is N3.1 under Me (7 issues). Head ⊇
base − retired holds.

### 7.5 The demo

The stage-9 harness copy (`docs/probes/demo-pixels/ZZDemoPixels-stage9.swift`)
renders the chrome pair twice under the one authority, under the old names;
`compare.sh` picks it for a commit whose `Fakes.swift` declares no
`layoutAuthority: LayoutAuthority` parameter. The first run selected on the
bare name `layoutAuthority:`, matched lane 3's own `Fakes.swift` comment, gave
the head the old harness and failed to compile (`cannot find type
'LayoutAuthority'`); `35f1ffb` selects on the declaration (`LR-FK` item 3).
`compare.sh <scratch> b9a5d7f 35f1ffb`: **0 differing, scene identical, in all
fourteen images**; controls at `b9a5d7f` 1048576, 1031003, 454895, 0,
1048576, 0, 544, 216, 491221, 529, 0 (§5.6's values); at the head
chrome-legacy vs chrome-proposal 0 (distinct 216). The header's two stale
controls (1030498, 210027) are corrected in a paragraph; the printed brackets
are kept.

### 7.6 Off the root package

- `Backends/SDL` (`fetch-accesskit.py`, then `PKG_CONFIG_PATH=.accesskit`):
  `swift build --build-tests` 0 `error:` (the only warnings are the host's
  SDL3 dylib deployment-target linker notes and SwiftPM's `-rpath` flag
  notice); `swift test` 21 + 19 passed. Fixtures re-recorded at the head
  (`Experiments/SDLGPU`, `Replay --portable --record`, all six frames 0 px
  against the Metal renderer, draw-order mutation detected); `PortableReplay …
  --expect 6` PASS (every frame 0 px); `DemoCapture` PASS (scene byte-for-byte
  the recorded frame 5, 0 px). The fixtures are untracked and
  self-consistent at one commit; the cross-commit pin of the demo frame is
  `DemoFrameDeterminismTests` against `Expected.swift`, green unedited in the
  suite.
- `Tests/PortableTests`: builds, 18 + 6 + 5 passed.
- `swift:6.4-noble` container (OrbStack), `git archive` of the head: `swift
  build --build-tests` complete, 0 `error:`; `--filter
  'MetalUICoreTests|MetalUILayoutTests|MetalUICrossPlatformTests'` 192 + 22 + 3
  passed (macOS reads 217 for the same filter). The portable CI figure moves
  200 + 22 + 3 → **192 + 22 + 3**, lane 2's eight `MetalUILayoutTests`
  retirements.

### 7.7 Doc comments, and the exit grep

Every `Sources/` comment that described the legacy authority, `computeLayout`,
`requestNode`, `textMeasure`, the min-content memo or a spacer as present was
rewritten as history or deleted (`Box`, `Component`, `Deferred`, `ElementGroup`,
`ElementID`, `Frame`, `FrameLayer`, `LayoutAuthority`, `LegacyLowering`, `List`,
`ListRows`, `LoweringState`, `ModifiedElement`, `NativeModifiedContent`,
`Passes`, `ProposalNodeID` — its holes 2, 5, 6 closed —, `ScrollView`, `Stack`,
`Text`, `TextField`, `Window`, `AnimatedStyle`, `Units`, `DemoContent`,
`LayoutTree`, `MeasureFunction`, `NativeLayoutRun`, `Rounding`, `Atlas`,
`ShapingCache`, `FontKey`, `FontResolver`, `ContentSizes`), and lane 1's
stale-citation list (§5.7) was fixed to the renamed tests. The exit-criterion
grep (spec §8 item 1) over `Sources`, `Tests/MetalUITests`,
`Tests/MetalUILayoutTests`, `Tests/MetalUITextTests` prints only:
`ProposalMeasureFunction` (the pattern's `MeasureFunction\b` has no leading
boundary); `PortableText.unbreakableRuns`/`minContentWidth` (kept API,
`LR-FD` item 2); the history comments naming a deleted symbol in
`LayoutAuthority.swift`, `Passes.swift`, `Frame.swift`, `Text.swift`,
`MeasureFunction.swift`, `ShapingCache.swift`, `ContentSizes.swift` and
`Fakes.swift`; the two guards' fixtures and docs, which name the deleted
symbols on purpose; and lanes 1–2's doc survivors (§5.7, §6.8).
**Survivors kept, with reasons**: `UnlowerableField.trapMessage`'s "proposal
layout authority" (`LR-FK` item 1); `DemoContent.swift`'s two historical
narratives of how the demo's scroll box was fixed "on the legacy engine"
(dated, scoped history); `LegacyLowering.swift`'s comparisons with what "the
legacy engine" answers — each the reason a lowering reads as it does, not a
claim that the engine runs; the file keeps its name (`LR-FC` item 4).

### 7.8 Handed on

- **Record phase**: the parent spec's "Stage 9 … is designed" sentence;
  CLAUDE.md's counts (1409; portable CI 192 + 22 + 3), the rules spec §9
  lists, and `compare.sh`'s stage-9 selector.
