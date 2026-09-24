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
issues), **Mb 52** (336), **Mc 6** (40), **Md 2** (57), **Me 8** (106). This is
the stage's base set, which lanes 2 and 3 re-read (`LR-FH` item 2).

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

Ma–Me at `1148ccb` (probe file, `## head`): **every base test reddens at the
head or is its renamed self**, except two Mb dropouts —
`aStretchedUnsizedSpaceDistributionContainerIsReported` and
`aGrownUnsizedSpaceDistributionContainerIsReported`, whose controls' agreement
alone saw the grown/stretched row's own rect. Each gained that rect as a literal
(`e710e4b`: 200×10, 260×10), and **Mb re-run at `e710e4b` reddens both** (2
issues each; 56 tests, 264 issues). No base test is a retired row of this lane.
Head-only reds (tests the literals now make each mutation see) are listed in the
probe file; they are additions, not a requirement.

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
  values. `RootFieldLoweringTests`' root-margin arm names its field's owner as
  stage 9 in its doc ("a root **margin** (owner 9)") — no row of spec §5 names it;
  its trap stands (`box.margin.unconsumed`), and its owner needs a ruling.
- **Exit-criterion grep survivors in this lane's files**, all historical doc
  text: `LayoutAuthorityTests.swift:76` (`layoutAuthority`), `:177`
  (`customElement`), `ListLoweringTests.swift:72`, `ListTests.swift:25, 847`,
  `LoweringCorpusTests.swift:172`, `ScrollRoutingTests.swift:515, 775`
  (`customElement`), `LoweringLeafTests.swift:497` (`textMeasure`), `:502`
  (`minContentWidth`).
