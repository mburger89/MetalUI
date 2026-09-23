# Engine replacement, stage 6a — custom elements, and tests that are about CSS answers (plan task 7)

**Status, 2026-09-23 (PDT): DESIGNED — no lane has run.** Every measurement
below was taken on `feat/engine-stage-6a` from `b3c29b9` in
`/Users/maxburger/Developer/worktrees/MetalUI/stage-6a`, on scratch commits
`9ccc0d8`…`59b63ad` that `a1b6edf` reverts to `b3c29b9`'s tree exactly; the
measurements, the arms and the full classification table are in
`docs/record/30-engine-replacement-stage-6a.md` §1–§6. Rulings `LR-CT`…`LR-CZ`
in [`../2026-09-17-engine-replacement-decisions.md`](../2026-09-17-engine-replacement-decisions.md).
Probe: `docs/probes/swift-deprecated-witness-silence.sh` (compiler, not SwiftUI;
no SwiftUI claim is made anywhere in this stage).

Parent design: [`2026-09-17-engine-replacement-design.md`](2026-09-17-engine-replacement-design.md)
§4.1 row 6a, `LR-R`, `FR-I`, §8. Stage 1 is record §18, stage 2 §21, stage 3
§25, stage 4 §27, stage 5 §29.

**What §4.1 row 6a asks for.** *"The public `LayoutPass.requestNode`/`requestLeaf`
deprecated **and** every in-repo caller moved in the same change (`FR-I`): each
custom test element re-spelled onto `requestNativeLeaf`/`ProposalLayout`, or —
where the test is about a CSS answer — pinned to the internal `.legacy`
authority through the internal, undeprecated `Frame.requestNode`; the list of
such tests produced by running the suite with the default authority flipped and
diagnostics on, each red test classified (lowering gap owned by a stage / CSS
answer to retire in 7b). Exit: **0 `warning:`** with the deprecation in place,
and `aDeprecatedRegistrarStillLaysOutUnderTheLegacyAuthorityAndTrapsUnderTheProposalOne`;
the flipped-default classification table recorded as the stage's entry
measurement."*

**The sentence this design turns on.** The deprecation is a **test-suite**
change: at `b3c29b9` no line of `Sources/` calls the public pair (every site checks
the authority and calls `Frame`'s internal registrars; `LR-R`'s "Sources' own sites call
the public forwarders today" is stale — record §30 §1), so the attribute warns
only where 58 compiled test call sites use it. Each of those moves one of six
ways (§5), chosen by what the test asserts under the flipped default, which the
entry measurement (§2) read per test through five arms. Production does not
move by a byte.

## Contents

1. [Baseline](#1-baseline)
2. [The entry measurement](#2-the-entry-measurement)
3. [Decisions](#3-decisions)
4. [API and files](#4-api-and-files)
5. [Every caller, with its disposition](#5-every-caller-with-its-disposition)
6. [What must not move, and what does](#6-what-must-not-move-and-what-does)
7. [Lanes](#7-lanes)
8. [The exit test](#8-the-exit-test)
9. [Demo, pixels and captures](#9-demo-pixels-and-captures)
10. [Handed on, each with an owner](#10-handed-on-each-with-an-owner)

---

## 1. Baseline

At `b3c29b9`, measured 2026-09-23:

| measure | value | how |
|---|---|---|
| suite | **1640 tests in 3 suites**, passed; 0 `error:`; the only `warning:` is SwiftPM's deprecation notice; `FR-J no-argument frame: succeeded=` present | `swift build --build-system native --build-tests`, then `swift test --build-system native --no-parallel`, unfiltered |
| goldens | **97** | `find Tests/MetalUILayoutTests -name "*.json" \| wc -l` |
| guards | **77** (`LayoutAuthorityCompileGuards` 1) | CLAUDE.md's per-file `grep -c canTypecheck` |
| callers of the public pair | **66 test call sites in 35 files** (58 compiled, 8 in typecheck fixture strings); **0 in `Sources/`** | record §30 §1 |

**No golden moves and none may**: nothing here touches `Sources/MetalUILayout/`.
Check: `git diff --name-only b3c29b9 HEAD -- 'Tests/**/*.json'` empty.

## 2. The entry measurement

Record §30 §2 and §4 in full; the summary that decides §5:

- **The instrument.** `Frame.init`'s and `Window`'s default authority flipped to
  `.proposal` with diagnostics on — **and the eight test helpers that pass
  `.legacy` explicitly as a parameter default** (`makeFakeWindow` and seven
  file-local render helpers), which the first spelling missed: it reached 88
  reds, the full flip **153**. Traps made non-fatal so the run completes
  (production windows trap on an unlowerable field; five tests would have).
- **Five arms** separate the reds: A2 (the flipped default), B2 (custom elements
  lowered as a `Box` instead of reported), C2/C3/B3 (the native root placed as the
  legacy root is — at the window rect, or top-leading at its answer).
- **153 red, classified**: X 13 (exit tests of production traps; instrument
  artefact), D 2 (the default itself), N9 5 (legacy-authority boundaries), **RP 54
  and CE+RP 23 (root placement, 6b)**, CE 6 (custom element only), AV 5
  (`hidden()`, no owner), RT 1, **CSS 43** (structure 14, style 7, text 3, legacy
  frame 10, divergence 48 ×5, legacy-vs-proposal pins 2, stretched box model 2),
  unattributed 1.

## 3. Decisions

| # | decision | ruling |
|---|---|---|
| 1 | The entry measurement is the flipped default **including the helper defaults**, read through five arms; its table is the stage's record and 6b's and 7b's input | `LR-CT` |
| 2 | Six dispositions for a caller, chosen per **test** from the arms: **R** re-spelled onto `requestNativeLeaf` (its test runs `.proposal`); **P-CSS** / **P-6b** / **P-9** pinned to `.legacy` through `pass.frame.requestNode`; **L** a dual-branch fixture's legacy branch onto `pass.frame`; **Dep** deprecated on purpose; **G** a typecheck fixture onto `requestNativeLeaf`. An element whose tests split between R and P takes both branches (`pass.lowersToProposal`) | `LR-CU` |
| 3 | A fixture whose subject **is** the public registrar keeps it, its `requestLayout` marked `@available(*, deprecated, message:)` — measured silent (probe) | `LR-CV` |
| 4 | `UnlowerableField.owningStage` for `.customElement` becomes **"9"**: a custom element is removed from the proposal authority, not lowered, and stage 9 deletes the pair (`LR-CK`'s precedent) | `LR-CW` |
| 5 | The exit test and one new plain-import guard; the deprecation lands **last**, in lane 3, in the commit that moves the last caller | `LR-CX` |
| 6 | Three lanes by file; lane 3 closes the gate | `LR-CY` |
| 7 | What 6b and 7b inherit | `LR-CZ` |

## 4. API and files

**Public API change: two attributes.** Nothing else public moves.

```swift
// Sources/MetalUI/Passes.swift — on both `requestNode(style:children:)` and
// `requestLeaf(style:measure:)`, bodies unchanged:
@available(*, deprecated, message: "a custom element registers through requestNativeLeaf(measure:) or a ProposalLayout; this legacy registrar traps under the proposal layout authority and is deleted by plan task 7's stage 9 (ruling LR-R)")
```

Their doc comments gain one paragraph each ("**Deprecated in stage 6a** …
production still runs the legacy authority, where this still registers exactly
`Frame.requestNode`/`requestLeaf`; under the proposal authority it reports
`customElement.<name>`, owned by stage 9"). `Frame.requestNode`/`requestLeaf`
stay internal and **undeprecated** (their doc comment already says so).

| file | change | lane |
|---|---|---|
| `Sources/MetalUI/Passes.swift` | the two attributes, two doc paragraphs | 3 |
| `Sources/MetalUI/LayoutAuthority.swift` | `owningStage`: `.customElement` → `"9"`, with a comment citing `LR-CW`; `UnlowerableField`'s doc line on `customElement` | 3 |
| `Tests/MetalUITests/LayoutAuthorityTests.swift` | `CustomNodeElement`/`CustomLeafElement` → **Dep**; **new** exit test 3.1 and its fixtures | 3 |
| `Tests/MetalUITests/LayoutAuthorityCompileGuards.swift` | **new** guard 3.2 (`typecheckFile`) | 3 |
| the 34 other caller files | §5 | 1, 2, 3 |

**`swift package clean` is not owed**: no stored property or case is added to a
public type (an `@available` attribute changes no layout). Take it anyway if the
impossible happens (CLAUDE.md).

**Counts after the stage: 1642 tests** (1640 + 3.1 + 3.2), **97 goldens, 78
guards** (`LayoutAuthorityCompileGuards` 1 → 2). No test is removed; a test
re-spelled or pinned is the same `@Test`.

## 5. Every caller, with its disposition

The spellings:

- **R** — the element registers `pass.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: w, height: h)) }`
  (`w`×`h` its declared `style.size`, 0×0 for `Style()`), returning
  `.layoutNodeID` from an untyped `requestLayout`; a custom **container**
  registers `pass.frame.requestNativeOverlay(children:)` over its children
  (a native linear stack or frame where the test reads geometry — named per row).
  Its test's `Frame`/window/helper gets `layoutAuthority: .proposal` **unless the
  whole tree is native** (then the authority is irrelevant: `computeRootLayout`
  chooses the kernel by the root). Every assertion unchanged.
- **P-CSS** (7b retires), **P-6b** (6b re-spells after ruling root placement),
  **P-9** (deleted with the legacy authority) — the element registers
  `pass.frame.requestNode`/`requestLeaf` with the same arguments; its test passes
  `layoutAuthority: .legacy` explicitly (a no-op today: `.legacy` is the default
  until 6b; the point is that 6b's flip cannot reach it). Every assertion
  unchanged. Each such test's doc comment gains one line: `Pinned to the legacy
  authority by stage 6a (<class>, record §30 §4).`
- **Dual** — an element whose tests split: `if pass.lowersToProposal { R's
  registration } else { P's }`.
- **L** — an existing dual-branch fixture (stages 3–5): its legacy branch's
  `pass.requestNode(`/`pass.requestLeaf(` becomes `pass.frame.requestNode(`/
  `pass.frame.requestLeaf(`. **Identical by construction** under the legacy
  authority (`Passes.swift:43–48`, `66–72`: the forwarder is exactly that call
  when `lowersToProposal` is false) and unreachable under the proposal one.
- **Dep** — body byte-identical; `requestLayout` marked
  `@available(*, deprecated, message: "spelled with the deprecated legacy registrar on purpose: <why> (stage 6a, LR-CV)")`.
- **G** — a typecheck fixture string: the call becomes
  `pass.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 10, height: 10)) }.layoutNodeID`
  (or `pass.requestNativeSpacer().layoutNodeID` where the fixture needs any node);
  the guard's own assertions unchanged except where the table says.

Arms per test are record §30 §4's (A2 / B2 / C2 / C3 / B3). "green" means
green in A2.

### Lane 1 — fixtures whose disposition is mechanical (L, Dep, G)

| file | element / fixture (line at `b3c29b9`) | disp. | tests reached |
|---|---|---|---|
| `AXNodeTests` | `AXListLeaf` (603) | L | the three `List` AX tests, parameterised |
| `AXNodeTests` | `LegacySpelledAXListLeaf` (627) | Dep | `aLegacySpelledAXListRowAbortsAProductionProposalFrame` |
| `ListTests` | `Row` (78, 94) | L | the 21 `List` scenarios |
| `ListTests` | `LegacySpelledRow` (896, 899) | Dep | `aLegacySpelledListRowAbortsAProductionProposalFrame` |
| `TombstoneTests` | `ExcursionRow` (117) | L | `theColdFrameSpikeIsReapedRatherThanRetainedForever`, `aListRowsStateSurvivesABoundedExcursionButNotALongerOne` |
| `TombstoneTests` | `LegacySpelledExcursionRow` (143) | Dep | `aLegacySpelledExcursionRowAbortsAProductionProposalFrame` |
| `MeasurePerformanceTests` | `StatefulListRow` (764) | L | the parameterised `List` work tests |
| `MeasurePerformanceTests` | `LegacySpelledStatefulListRow` (787) | Dep | `aLegacySpelledStatefulListRowAbortsAProductionProposalFrame` |
| `ListLoweringTests` | `LoweredProbeLeaf` (88) | L | `aLoweredListAgreesWithTheLegacyEngineOnEveryWindowedShape` |
| `LoweringScrollTests` | `ContextProbe` (1086) | L | `aLoweredScrollViewRegistersAHandDerivedAmountOfNativeWork`, `aScrollContextSurvivesALoweredViewportAcrossTwoFrames` |
| `ScrollRoutingTests` | `ScrollContextRecorder` (556), `HitboxProbe` (810) | L | the parameterised scroll-routing scenarios |
| `LayoutDifferential` | `ProbeLeaf` (120) | L | every differential harness caller |
| `PhaseSeparationTests` | `registeringALayoutNodeDuringPaintDoesNotCompile` (87), `…DuringLayoutCompiles` (100) | G | both; the negative's `messages.contains("requestNode")` becomes `"requestNativeLeaf"` (`LR-CU` item 6: the claim — `PaintPass` cannot register a node — is unchanged; the name follows the registrar that survives stage 9) |
| `ErasureCompileGuards` | `ValueBox` (160) | G | `aStructCanConformToElementObject` |
| `ProposalNodeIDCompileGuards` | `Liar` (59), `mint` (81), `disagreeingGroupSource` (245) | G | `aMarkerConformerThatRegistersALegacyNodeDoesNotCompile` (its doc's "registers a legacy node" becomes "registers a node through the untyped entry"; the rejection message is the typed requirement's either way), `aProposalNodeIDCannotBeMintedOutsideMetalUI` (`ProposalNodeID(pass.requestNativeSpacer().layoutNodeID)`: still the internal initializer's error), `aProposalGroupWhoseEntryPointsDisagreeStillCompiles` (one node against zero: still disagreeing) |
| `FrameSizingCompileGuards` | `LegacyLeaf` in `bothLeavesSource` (46) | G | `theNoArgumentFrameIsADeprecatedNoOpOnBothPaths`, `everyFrameSpellingOnAProposalElementResolvesToTheProposalOverload` |
| `ModifiedElementCompileGuards` | `Leaf` in `leafSource` (37) | G | every guard in the file that splices `leafSource`, including the 24-modifier solver-budget guard |

### Lane 2 — authority-independent tests (R, one Dual)

Every test here is green in A2 unless marked **CE** (green in B2: needs the
element's size). The two `PipelineTests` CE rows need geometry equal to the
legacy row's, spelled natively.

| file | element (line) | disp. | tests |
|---|---|---|---|
| `StateTests` | `CounterElement` (84), `ConditionalReadElement` (108), `ReflectOnceElement` (128), `TwoOrdinalElement` (235) — 10×10 | R | `stateSurvivesAcrossFramesForTheSameElement`, `aRootElementsStateIsSeededAndSurvives`, `aStateWriteWakesAPausedDisplayLinkThroughTheOnWriteHook`, `aStateWriteDuringTheFramesOwnRenderIsNotSwallowedByClearingAfterward`, `aStateThatIsNeverReadInAFrameIsStillNotSwept`, `reflectionRunsOncePerTypeNotOncePerElement`, `stateOrdinalsAreTheMirrorIndexNotThePositionAmongStateChildren`; `aSlotIDCannotCollideWithAPositionalChild` renders nothing (no authority argument) |
| `StateTableTests` | `CountingElement` (175) | R | `childrenOfDistinctUnnamedParentsDoNotCollide`, `aSharedTableCarriesStateAcrossFramesWhileAPerFrameTableWouldNot`, `anElementThatStopsBeingProducedLosesLivenessButKeepsItsValue` |
| `IdentityTests` | `StampedStateProbe` (547), `ClickableStateProbe` (606) | R | `twoErasedSiblingsDoNotShareOneStateEntry`, `oneElementValuePlacedTwiceDoesNotShareItsState`, `aHandlerWritesTheStateOfTheOccurrenceThatRegisteredIt` |
| `EnvironmentTests` | `EnvRecorder` (72), `PropertyRecorder` (131) | R | `theNearestWriterWinsAndAScopeEndsWithItsSubtree`, `aTransformComposesWithTheInheritedValueAndAWriteBelowItReplacesIt`, `anEnvironmentValueReadsIdenticallyInAllThreePhases`, `anEnvironmentScopeContributesNoLayoutNodeAndConsumesNoIndex`, `theFramesRootEnvironmentCarriesItsThemeAndScale`, `aWholeValueWriteCannotResetTheThemeOrThePixelLength`, `theWindowsEnvironmentReachesTheFrameAndASetRepaints`, `aBareEnvironmentValuesHoldsTheRootLocaleAndAWindowStampsTheCurrentOne`, `eachScopesTransformRunsOncePerFrame`, `anEnvironmentPropertyIsBoundToTheNearestScopeInEveryPhaseAndRereadEachFrame`, `oneElementValuePlacedTwiceUnderTwoScopesReadsEachScopeInPaint`, `anEnvironmentPropertyInsideAnyElementIsInertAndReadsTheDefault`, `environmentWorkScalesWithWritersAndReadersNotWithTheirDescendants` |
| `EnvironmentTests` | `ClickCounter` (297) — 20×20 | **Dual** | R: `anEnvironmentScopeContributesNoLayoutNodeAndConsumesNoIndex`; **P-6b**: `changingADisabledOrEnvironmentValueKeepsTheStateBelowTheWriter` (CE+RP: red in A2, B2, B3; green in C2) |
| `EnvironmentTrapTests` | `RootWriter` (43), `ScopedReader` (104) | R | `aRootEnvironmentWriteDuringARenderTraps`, `aRootEnvironmentWriteBeforeAndBetweenRendersDoesNotTrap` (exit tests: the child's `Frame` gets `.proposal`) |
| `DisabledTests` | `EnabledRecorder` (123) | R | `disabledComposesAsAnAndAndARawWriteOverridesIt` |
| `FocusTests` | `FocusReader` (763), `SelfFocuser` (887) | R | `isFocusedDuringPaintTracksTheWindowsFocus`, `focusingFromInsideAFrameIsStillValidatedByTheNextFrame`, `focusingFromInsideAFrameSurvivesThatFrame` |
| `FrameClockTests` | `RequestingBox` (19), `TimestampRecorder` (48) | R | `anElementThatRequestsAnotherFrameKeepsTheWindowDirty`, `everyElementInOneFrameSeesTheSameTimestamp` |
| `FrameLoopTests` | `FrameCounter` (185) | R | `crossFrameStateSurvivesFromOneWindowFrameToTheNext` |
| `GlyphEmitterTests` | `Probe` (462) | R | `theAtlasFrameBracketsWrapThePaintPhase` |
| `ElementGroupTrapTests` | `ContentSwapper` (175, a container: `requestNativeOverlay` over its children), `StateProbe` (363) | R | the six `renderSwapper` exit tests (`flippingAnEitherBranchBetweenPhasesTraps`, `anUnflippedEitherBranchDoesNotTrap`, `droppingAnOptionalChildBetweenPhasesTraps`, `anOptionalChildThatIsAbsentInBothPhasesDoesNotTrap`, `changingAnArrayGroupsCountBetweenPhasesTraps` and the array group's `.success` control — the helper's `Frame` gets `.proposal`), `twoSiblingsWithTheSameIDShareOneStateEntry`, `twoSiblingsWithDifferentIDsDoNotShareState` |
| `PipelineTests` | `ProbeRow` (65: a 400×100 row over 100×40 and 60×20) | R | `theThreePhasesRunInOrder`, `eachFrameOwnsItsOwnStateSoNothingLeaksBetweenFrames`, **CE** `prepaintSeesBoundsTheEngineResolvedBetweenTheFirstTwoPhases`, **CE** `paintReceivesTheRootBoundsAndEmitsIntoTheFramesScene` — re-spelled as a native fixed 400×100 `.topLeading` frame over a native horizontal linear stack, `.top`, spacing 0, over two sized leaves (the legacy answer (0, 0) and (100, 0) at their sizes; all-native, so no authority argument) |
| `PipelineTests` | `StampedProbe` (232), `MutatingProbe` (343), `IdentifiedProbe` (439) — 30×10; the hand-built root row in `twoCopiesOfOneElementDoNotShareLayoutState` (295) | R | `twoCopiesOfOneElementDoNotShareLayoutState` (root → a native horizontal linear stack, spacing 0), `theBoxCarriesEveryPhasesMutationForwardToTheNextPhase`, `theErasureForwardsTheElementsIdentity`, `paintWritesItsStatesBackSoASecondPaintSeesTheFirst` |

### Lane 3 — layout-answer tests (P, R, Dual) and the gate

| file | element (line) | disp. | tests |
|---|---|---|---|
| `ElementLayoutTests` | `Probe` (75) | **Dual** | R: `aContainerGivesItsChildrenPathsBuiltFromItsOwn`, `anIdentifiedChildOfAnUnnamedContainerHasAnIdentityThroughItsPosition`, **CE** `aNodeIDDoesNotSilentlyResolveAgainstAnotherFramesTree`. **P-6b** (CE+RP): `anExplicitAnyElementIsStillAcceptedAsAChild`, `childrenAreRegisteredAndLaidOutInSourceOrder`, `columnStacksOnTheAxisRowDoesNot`, `aStackCentresOnTheCrossAxisWhereABoxStretches`, `gapIsPerAxisAndTheRowReadsTheHorizontalOne`, `aHiddenChildTakesNoSpace`, `alignItemsAndAlignSelfBothReachTheEngine`, `aNestedLayoutMatchesTheEngineRunDirectly`. **P-CSS**: `theBuilderContributesNoNodesOfItsOwn` (structure), `marginEdgesAreNotTransposed`, `paddingEdgesAreNotTransposed` (box: the probe is stretched, record §30 §5) |
| `ComponentTests` | `Leaf` (73) | **Dual** | R: `aComponentContributesNoLayoutNodeOfItsOwn`, `aNamedComponentsContentKeepsItsStateWhenASiblingIsInsertedBeforeIt`, `contentIsMaterializedExactlyOncePerFrame`. **P-6b**: `aComponentsContentFlattensIntoItsParent`, `aComponentInsideAComponentFlattensThroughBothLevels`. **P-CSS**: structure — `aFrameWrapsAComponentsBodyWithoutOverwritingItsChildren`, `aModifierOnAComponentDistributesToEachTopLevelChild`, `chainedFramesRemainConcreteAndNestTheirLayoutNodes`, `paddingWrapsAnElementAndExpandsItsOuterFootprint`, `chainedPaddingCreatesNestedWrappers`, `chainedPaddingAccumulatesOnAComponentAsItDoesOnAnElement`, `aTwoMemberComponentsPaddingIsAppliedToEachMember`, `aComponentsPaddingWrapsEachTopLevelNode`; divergence 48 — `aComponentsWidthStillOverwritesItsMembersDeclaredWidth`, `widthAloneDistributesToEachTopLevelChild`, `heightAloneDistributesToEachTopLevelChild`, `widthAndHeightComposeOnAChainedModifier`, `aModifierOnAComponentAppliesInTheOrderItIsWritten` |
| `ComponentTests` | `CounterLeaf` (280) | R | `anEmptyComponentContributesNoNodes`, `stateInsideAComponentsContentIsAlsoSeeded`, `aNamedComponentsContentKeepsItsStateWhenASiblingIsInsertedBeforeIt` |
| `FrameSizingTests` | `Mark` (58) | **Dual** | R: `aSingleAxisFixedFrameDoesNotPinTheAxisItDidNotDeclare`. **P-6b**: `aLegacyFramePlacesItsChildAtEachOfTheNineAlignments`, `aLegacyFrameProposesItsWidthToAMeasuredLeaf`, `chainedLegacyFramesAgreeWithSwiftUIsOrderingRules`, `hiddenAfterASingleChildLegacyFrameStillHidesTheElement`. **P-CSS** (legacy frame): `aLegacyFixedFrameDoesNotShrinkAsAFlexItem`, `aLegacyFrameClampsToItsMinimumAndMaximumWithoutGrowingIntoTheProposal`, `aLegacyFrameAroundAListStillBuildsEveryRow`, `aSingleChildLegacyFrameOverflowsAnOversizedChildOnBothAxes`, `aSingleChildLegacyFrameIgnoresItsChildsFlexGrowAndAlignSelf`, `anInfiniteMaximumFillsOnlyWhenBothAxesAreInfinite`, `aFractionSizeResolvesAgainstItsContainingBlock`, `theSizingModifiersWriteTheirOwnElementsBoxRatherThanWrappingIt`, `anAbsolutelyPositionedChildInsideASingleChildLegacyFrameKeepsItsPlacement`, `aScrollViewInsideASingleChildLegacyFrameKeepsItsViewportAndWheel` |
| `ModifiedElementTests` | `LayerLeaf` (84) | **Dual** | R: `anIDAfterAChainsLastWrapperNamesTheOutermostLayer`, **CE** `addingALayerAtRunTimeResetsTheWrappedElementsState`. **P-6b**: `changingALayersValueKeepsTheWrappedElementsState`, `aLayerAddedAtRunTimeIsAdoptedByTheNewOutermostLayer`. **P-CSS**: `aGenericWrapOverAChainIsIdenticalToTheFlatChain` |
| `ModifiedElementTests` | `ChainLeaf` (117) | P-CSS | `legacyModifierChainsInferOneConcreteType` (`nodeCount == 4`) |
| `ModifierCompositionProofTests` | `CountingLeaf` (119) | **Dual** | R: `everyModifierWrapperDelegatesEachPhaseExactlyOnce`, **CE** `stateSurvivesFramesUnderALegacyModifierChain`, **CE** `aModifierChainRegistersAndPaintsOuterLayersFirst`. **P-6b**: `modifierOrderChangesSizeAndPlacementAsSwiftUIDoes`. **P-CSS**: `aModifierChainIsIdenticalToHandBuiltNestedBoxes` |
| `ModifierCompositionProofTests` | `BoxWithoutAnimated` (482; a copy of `Box`'s phases, the disagreeing oracle) | P-CSS | `aModifierChainIsIdenticalToHandBuiltNestedBoxes` |
| `ContainerIntegrationTests` | `LegacyMark` (1420) | P-CSS | the **legacy arm** of `aLegacyRowAndColumnDefaultToNoSpacingWhereHStackAndVStackDefaultToEight`, `aLegacyStackOffersFitContentWhereAZStackOffersItsProposal`, `aLegacyScrollViewTakesItsCrossAxisFromItsParentWhereAProposalScrollViewTakesItsContents` (the proposal arms are native already) |
| `HitboxTests` | `HitboxProbe` (370) | P-6b | `hoverResolvedThroughARealRenderHasNoLag`, `aMouseMovedEventMakesTheBoxUnderItHoveredOnTheNextFrame`, `aPressThatLeavesTheHitboxAndReturnsStaysActive`, `activeIsSetOnMouseDownAndHeldUntilMouseUp`, `activeSurvivesAFrameBoundary` (all CE+RP) |
| `ProposalNodeIDTests` | `OrphanLegacyNode` (44), `StatefulLegacyLeaf` (66) | P-9 | `anOrphanLegacyRegistrationBesideATypedLeafIsNotRejected` (`MC-G` holes 2 and 6: the subject is a legacy registration) |
| `NativeBoundaryIntegrationTests` | `LegacyNodeUnderAProposalMarker` (35) | P-9 | `aProposalMarkedElementThatRegistersALegacyNodeTrapsInsideAProposalContainer` (`MC-G` hole 3; the child's `Frame` gets `.legacy`) |
| `LayoutAuthorityTests` | `CustomNodeElement` (34), `CustomLeafElement` (45) | Dep | `aCustomElementsLegacyRegistrationTrapsUnderTheProposalAuthority`, `everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn` |

Totals: **R 66 tests** (lane 2: 52, lane 3: 14); **P 57** — 32 P-CSS, 23 P-6b (one
of them lane 2's), 2 P-9; **Dual** 6 elements; **L** 10 fixtures; **Dep** 6
(+ 3.1's); **G** 8 sites.

## 6. What must not move, and what does

### 6.1 Must not move — each with its pin

| property | pin |
|---|---|
| production layout (legacy authority) | the twelve `CN-R` images at 0 (§9); no `Sources/` line but two attributes, one `owningStage` literal and doc comments |
| every existing assertion | each lane's diff touches no `#expect`/`#require` line of an existing test except (a) PhaseSeparation's negative message literal (`LR-CU` item 6) and (b) authority arguments; a reviewer greps the diff for `#expect` |
| the suite count | 1640 + 2 = **1642**, one summary line |
| goldens | 97, `git diff --name-only b3c29b9 HEAD -- 'Tests/**/*.json'` empty |
| identity, hit testing, accessibility, animation | unchanged sources; their tests re-spelled R keep their assertions and now run under the proposal authority (`LR-CU`) |
| 0 `warning:` on both build systems | the gate itself, at every lane's commit (the deprecation lands last) |

### 6.2 What moves

- **Under the legacy authority: nothing.** The Dep/L/P spellings register
  exactly what the forwarder registered.
- **Under the proposal authority**: an external custom element's trap message
  names **stage 9** instead of 6a (`LR-CW`). 66 existing tests now run under the
  proposal authority (R), none with a changed assertion.
- **At build time**: a caller of the public pair outside the repository is
  warned, pointed at `requestNativeLeaf`/`ProposalLayout`.

## 7. Lanes

Three, sequential in one worktree, disjoint files. Each lane commits its change
first (green, 0 `warning:`), then runs its mutations (commit, restore from a
`cp` copy, full unfiltered suite, `git status --short` after each, every
reddened test named), appends its section to record §30 and its corrections
ruling (the next unused `LR-` letter after `LR-CZ`), and re-takes the twelve
`CN-R` images. **A lane that finds a re-spelled (R) test red records it — arm,
failing assertion — and pins it P with the measured cause rather than editing
the assertion**; the design's per-test prediction is the entry measurement, not a
promise.

**Instrument I0** (for mutations that would otherwise truncate the run): in a
scratch, `git cherry-pick 0d02538` (noteUnlowerable and the backstop non-fatal,
printing `SIXA-WOULD-TRAP:`); reverted with the mutation.

### Lane 1 — fixtures (L, Dep, G) (`LR-CU`, `LR-CV`)

Files: lane 1's rows of §5. **No deprecation yet**, so the Dep attributes warn
nothing and nothing else can.

| # | check | mutation that must redden it |
|---|---|---|
| 1.1 | the L fixtures: identical under legacy by construction; the parameterised suites green | **none possible** — a green mutant is the correct spelling (`LR-X`): swapping the legacy branch back to `pass.requestNode` is the same call under legacy; recorded as such |
| 1.2 | `registeringALayoutNodeDuringPaintDoesNotCompile` re-spelled | **M1a** `PaintPass` gains an internal-forwarding `public func requestNativeLeaf(measure:) -> ProposalNodeID` (the negative compiles) |
| 1.3 | `registeringALayoutNodeDuringLayoutCompiles` re-spelled | **M1b** `LayoutPass.requestNativeLeaf` made `internal` (the positive fails) |
| 1.4 | `aStructCanConformToElementObject` re-spelled | **M1c** its named mutation: `ElementObject: AnyObject` |
| 1.5 | the three `ProposalNodeIDCompileGuards` re-spelled | **M1d**/**M1e**/**M1f** each guard's own named mutation (guard 1: a trapping default `requestProposalGroupLayout` on every `ProposalElementGroup`; guard 2: `ProposalNodeID.init(_:)` `public`; guard 6: its doc comment's) |
| 1.6 | `FrameSizingCompileGuards`' two and `ModifiedElementCompileGuards`' leaf-splicing guards re-spelled; **the solver-budget guard's in-test negative still fails and its positive passes at 1000** | **M1g**/**M1h** each guard's own named mutation, re-run (the practice: a mutation a doc comment names is re-run when the code under it changes) |

### Lane 2 — authority-independent tests (R) (`LR-CU`)

Files: lane 2's rows of §5. Tests only.

| # | check | mutation |
|---|---|---|
| 2.1 | every lane-2 R test green under `.proposal`, assertions unchanged | **M2a** every lane-2 native leaf's measure answers 0×0 (in one scratch): reddens **exactly** the two CE rows (`prepaintSeesBoundsTheEngineResolvedBetweenTheFirstTwoPhases`, `paintReceivesTheRootBoundsAndEmitsIntoTheFramesScene`) plus whatever else reads a lane-2 element's size — the lane names the set; a non-CE test in it is a finding about §5's A2 reading |
| 2.2 | `ProbeRow`'s native spelling places (0, 0) 100×40 and (100, 0) 60×20 | **M2b** the stack's alignment `.center` (second child y 10: the two CE rows redden) |
| 2.3 | `ClickCounter`'s dual branch: its P-6b test still green under `.legacy`, its R test under `.proposal` | covered by lane 3's **M3g** shape, run here over this file's one `.legacy` pin (I0): `changingADisabledOrEnvironmentValueKeepsTheStateBelowTheWriter` alone reddens |

**No mutation of an R test's authority is taken** (record §30 §6): putting a
re-spelled element back on `pass.frame.requestNode` under `.proposal` traps at the
backstop, and putting its test back on `.legacy` traps at `SA-G` — both loud,
both already pinned by exit tests (`aSiteThatSkipsItsOwnCheckIsStoppedByFramesBackstop`,
`aProposalElementInsideALegacyContainerTrapsAtRegistration`), neither takeable
in-process without truncating the suite.

### Lane 3 — layout-answer tests (P, R, Dual), the deprecation, the exit test (`LR-CU`, `LR-CW`, `LR-CX`)

Files: lane 3's rows of §5, `Passes.swift`, `LayoutAuthority.swift`,
`LayoutAuthorityCompileGuards.swift`. **Order inside the lane**: the callers
first (green, 0 warnings); then **3.1 and 3.2 written red-first** in their own
commit; then the attributes and `owningStage` — the commit that closes the gate.
Then pixels, captures, the record's closing sections.

| # | test | what it asserts | red-before (at the lane's red-first commit) | mutation that must redden it |
|---|---|---|---|---|
| 3.1 | **new** `aDeprecatedRegistrarStillLaysOutUnderTheLegacyAuthorityAndTrapsUnderTheProposalOne` (`LayoutAuthorityTests`) | §8 | the trap half's `(plan task 7, stage 9)` substring: the message says **stage 6a** until `owningStage` moves; the legacy half passes (says so at its declaration) | **M3c** the legacy `requestNode` forwarder registers `Style()` in place of `style` (legacy half); **M3d** the legacy `requestLeaf` forwarder passes a 0×0 measure (legacy half); **M3e** the proposal forwarder skips its report and calls `frame.requestNode` (trap half — and 1.3's `aCustomElementsLegacyRegistrationTrapsUnderTheProposalAuthority` and the four `aLegacySpelled…Aborts…` exit tests, which read the same message); **M3f** `owningStage` for `.customElement` back to `"6a"` (trap half only) |
| 3.2 | **new** `aPlainImportCallerOfTheLegacyRegistrarsIsWarnedTowardTheNativeOnes` (`LayoutAuthorityCompileGuards`, `typecheckFile`) | a plain-import fixture calling `pass.requestNode` and `pass.requestLeaf` **still compiles** (`succeeded`), and its `messages` contain `'requestNode(style:children:)' is deprecated`, `'requestLeaf(style:measure:)' is deprecated` and `requestNativeLeaf`; a control fixture calling only `requestNativeLeaf` contains no `is deprecated`; `try #require` that the two disagree on `contains("is deprecated")` | no deprecation: both fixtures' messages are empty | **M3a** the attribute removed from `requestNode`; **M3b** removed from `requestLeaf` |
| 3.3 | the pins | every lane-3 `.legacy` pin is load-bearing | — | **M3g** over I0, every `.legacy` pin lane 3 wrote flipped to `.proposal`: the reddened set must equal the P tests of lane 3 that are red in A2 — all 55 of them (22 P-6b, 31 P-CSS, 2 P-9) except `aLegacyRowAndColumnDefaultToNoSpacingWhereHStackAndVStackDefaultToEight` (green in A2, pinned by its name, `LR-CU`) — the lane names the set and records any difference as a finding about the classification |
| 3.4 | the R and CE rows of lane 3 | green under `.proposal`, assertions unchanged | — | **M3h** every lane-3 native leaf's measure answers 0×0: must redden the four CE rows (`aNodeIDDoesNotSilentlyResolveAgainstAnotherFramesTree`, `addingALayerAtRunTimeResetsTheWrappedElementsState`, `stateSurvivesFramesUnderALegacyModifierChain`, `aModifierChainRegistersAndPaintsOuterLayersFirst`; the lane names the whole reddened set) |
| 3.5 | the gate | `swift build --build-system native --build-tests` and the default build system: 0 `error:`, the only `warning:` SwiftPM's notice; `grep -rn 'pass\.requestNode(\|pass\.requestLeaf(\|layoutPass\.requestNode(' Tests` returns only Dep fixtures' lines | the deprecation with one caller left behind (a scratch revert of one lane-3 re-spelling): exactly one `warning: 'requestNode(style:children:)' is deprecated` | — |

## 8. The exit test

`aDeprecatedRegistrarStillLaysOutUnderTheLegacyAuthorityAndTrapsUnderTheProposalOne`,
in `LayoutAuthorityTests`, one `@Test`, `async`:

- **Fixture** `DeprecatedRegistrarRow: Element`, its `requestLayout` marked
  `@available(*, deprecated, message: "…exercises the deprecated registrars on purpose (stage 6a, LR-CV)")`:
  a leaf through `pass.requestLeaf(style: Style()) { _, _ in SizeD(width: 30, height: 20) }`,
  a node through `pass.requestNode(style:)` sized 40×10, and a root through
  `pass.requestNode(style:children:)` — `flexDirection: .row`, `alignItems:
  .flexStart`, sized 200×100. `leafFirst: Bool` picks which child registers
  first. And its **oracle** `InternalRegistrarRow`, the same three registrations
  through `pass.frame.requestLeaf`/`requestNode`.
- **Legacy half.** Rendered in a 200×100 `.legacy` frame: the two children's
  rects equal the oracle's, and `try #require` that they are not 0×0 and differ
  from each other (so equality is not vacuous). Hand-derived: (0, 0) 30×20 and
  (30, 0) 40×10; the lane confirms by running before relying on the literals.
- **Trap half.** Two exit children, production `.proposal` frame, no
  diagnostics: `leafFirst: true` exits with failure and stderr contains
  `MetalUI: customElement.requestLeaf has no proposal lowering (plan task 7, stage 9)`;
  `leafFirst: false` likewise names `customElement.requestNode`.
- The declaration's doc comment names M3c–M3f and says the legacy half has no
  red-before (it passes at `b3c29b9`; the stage's change there is the
  attribute, which only 3.2 can see).

Green in one unfiltered run with 0 `warning:` — **the gate is the exit's other
half**.

## 9. Demo, pixels and captures

**Production runs the legacy authority until 6b, and no legacy path changes.**
Every lane's twelve-image offscreen comparison
(`docs/probes/demo-pixels/compare.sh`, against `b3c29b9`) must read **0
differing pixels in all twelve**, the two-authority chrome pair included;
non-zero is a finding. When the lock probe
(`xcrun swiftc -O docs/probes/appkit-screen-lock-state.swift -o /tmp/lockstate && /tmp/lockstate`)
shows no `CGSSessionScreenIsLocked` line and `displayAsleep main: 0`, lane 3 also
runs `docs/probes/window-capture/capture.sh <scratch> b3c29b9 <HEAD>` and records
each capture's reading. **No demo look is owed.**

## 10. Handed on, each with an owner

| item | owner |
|---|---|
| root placement (divergence 4 vs `CN-J`): **78** of the flip's reds (RP 54, CE+RP 23, RT 1), including the 23 P-6b tests this stage pins | 6b |
| the eight test helpers' `.legacy` parameter defaults, flipped with `Window`'s | 6b |
| `hidden()` / `display: none` under the proposal authority (5 AV rows; `LR-AV` names no stage and `owningStage` says 2) | 6b assigns |
| the two default-asserting tests (D) and the three non-caller N9 exit tests at the default authority | 6b pins or rewrites |
| `aContentShapeOnAFrameLayerInsetsTheFrameBoxAndBeforeItTheChildBox` — red in every arm, unattributed | 6b measures |
| the 32 P-CSS element tests, plus the 12 non-caller CSS rows (`StackElementTests` ×3, `TextMeasureTests` ×4, `EnvironmentTests` ×2, `AnimationTests` ×1, `FrameDecorationInteractionTests` ×1, `OuterModifierMatrixTests` ×1) | 7b |
| the two P-9 tests, the Dep fixtures, the L fixtures' legacy branches, the Dual elements' legacy branches, `LoweringSite.customElement`, the public pair | 9 |
| CLAUDE.md, AGENTS.md, records §03/§04/§05/README, the plan's 6a row, the parent spec's status | the Record phase |
