# 79 — Port gaps, medium: field chrome, `layoutPriority`, environment objects, window toolbar (lane 1 landed)

Branch `feat/port-gaps-medium` from `d48b26d` (master: proposal controls merged,
PR #49). **Not a plan task**: user request 2026-10-02, an item of the gpui-gap
priority list — the SMK configurator port's four medium gaps MG-20, MG-14, MG-2
and MG-3. Spec `docs/superpowers/specs/2026-10-07-port-gaps-medium-design.md`;
rulings `MD-A`…`MD-V` in `docs/superpowers/2026-10-07-port-gaps-medium-decisions.md`
(next unused `MD-W`); probes `docs/probes/swiftui-field-chrome.swift`,
`swiftui-environment-object.swift`, `swiftui-toolbar.swift`,
`swiftui-toolbar-nested.swift`.

**Status: lane 1 landed (2026-10-07); lanes 2 (the toolbar, native) and 3 (the
drawn strip and the demo) not started.** This section is lane 1's; the Record
phase completes it.

## 1. Lane 1 — field chrome, legacy priority, environment objects

Three parts in disjoint files, each red-first, committed and mutated on its own.

| Part | Red commit | Green commit | Suite after |
|---|---|---|---|
| 1 — MG-20 field chrome (`MD-B`…`MD-F`, `MD-T`, `MD-V`) | `00f2bae` | `48c6703` | **2589 tests in 3 suites** passed |
| 2 — MG-14 legacy `layoutPriority` (`MD-G`) | `306739a` | `cd29b3c` | **2594** passed |
| 3 — MG-2 environment objects (`MD-H`) | `6586719` | `0d745ea` | **2601** passed |

Baseline `d48b26d`: 2579. Each run native, unfiltered, `--no-parallel`, with the
`FR-J no-argument frame: succeeded=true` line present; 0 `error:`, the only
`warning:` SwiftPM's deprecation notice. `swift package clean` before parts 1
and 3 (new stored properties on `TextField`, `TextEditor`, `EnvironmentValues`,
`Environment`).

### 1.1 Red lines

- Part 1: `TextFieldChromeTests.swift:35:73: error: cannot find type 'TextFieldStyle' in scope` (tests 1.1–1.9 and guard 1.10 do not compile).
- Part 2: 2.1 `hi` 16 tall, not 100 (`aPrioritisedLegacyChildKeepsItsParentsStretch`); 2.2 `["text.flexGrow.unconsumed"]`; 2.3 `["box.flexGrow.unconsumed", "box.minSize.unconsumed", "box.maxSize.unconsumed"]`; 2.4 and 2.5 green before, as the spec states (pins).
- Part 3: `EnvironmentObjectTests.swift:48:18: error: cannot convert value of type 'Model.Type' to expected argument type 'KeyPath<EnvironmentValues, Model?>'` (tests 2.6–2.11 and guard 2.12 do not compile).

### 1.2 What landed

- **Part 1.** `TextFieldStyle` (`.automatic`, `.roundedBorder`, `.squareBorder`,
  `.plain`) and `TextEditorStyle` (`.automatic`, `.plain`), closed, in
  `Sources/MetalUI/TextFieldStyle.swift`, on the control (a value modifier) and
  on a container (an internal environment value, `EnvironmentValues.fieldStyles`).
  The bordered default: insets 6 × 4 (3.5 at `.small`), `.surface` fill,
  1-point `.separator` border, radius 6, the control ring while focused (not
  `.plain`; a caller's `focusBorder` wins), text/placeholder/caret alpha × 0.33
  when disabled — `FieldChrome` and `PaintPass.paintFieldChrome` in
  `ControlLook.swift`. `TextField.geometry` receives the inset content rect;
  no text-input logic changed. `TextEditor` gains the square `.surface` fill and
  the ring at radius 0; no size or placement change.
- **Part 2.** `LoweringState.forward(_:to:priority:)` moves a content record to
  the `layoutPriority` layer's node (origin and priority kept, report order and
  name kept); `ModifiedContent`'s `.layoutPriority` case calls it;
  `planLegacyItems` carries the origin and priority into `LegacyItemPlan`;
  `registerLegacyItems` aliases the origin to the item frame and registers the
  priority again outermost when any wrapper was registered.
- **Part 3.** `Environment.init(_:) where Value: AnyObject & Observable`,
  `Environment.init<T>(_:) where Value == T?`, `ElementGroup.environment(_ object:)`;
  `Environment` stores a reader closure in place of its key path;
  `EnvironmentValues` keeps an object table keyed by `ObjectIdentifier(T.self)`;
  a missing non-optional object traps with
  `No Observable object of type <T> found. An .environment(_:) for <T> may be missing as an ancestor of this element.`

### 1.3 Existing tests moved by the default flip (`MD-C` item 2)

The unfiltered suite after the flip reddened nine existing tests (42 issues):

| Test | Half of the rule |
|---|---|
| `aLongTextScrollsToKeepTheCaretVisible` | subject unchanged — `.textFieldStyle(.plain)` |
| `aTextFieldAndATextEditorTakeTheEnvironmentFont` | subject unchanged — `.plain` |
| `controlSizeReachesTheDefaultFontButNoControlsChrome` | font arm `.plain`; a new chrome arm (+7 at `.small`, +8 otherwise) — `MD-V`, divergence 76 amended |
| `aFieldLaysOutGreedilyAndEdits` | a size — 200 × line + 8 |
| `theGreedyControlsAnswerAnInfiniteProposalWithInfinity` | a size — ideal 43.95 × 24, ∞ × 24, 200 × 24 |
| `everyControlAnswersInSwiftUIsClassInsideAProposalContainer` | a size — 48.25 × 24 (divergence 131 amended, `MD-T`) |
| `aSwiftUIVocabularyFormLaysOutAsTheProbeArrangesIt` | a layout — row a 24 tall, every row below 8 lower, form 185 |
| `gridCellUnsizedAxesOnALegacyControlTakesItsColumnsWidth` | a size — 24 tall |
| `theControlsDemosSwiftUISectionLaysOutWithoutReports` | a layout — as test 1.5 |

Two test corrections against the spec, each before its green commit: test 1.1's
literals are 36 and 48 (recorded bounds round to whole points; the measured
ideals 36.25 and 48.25 are asserted unrounded in
`everyControlAnswersInSwiftUIsClassInsideAProposalContainer`); test 2.2's sibling
is a 40-point `Box`, not `Text("b")` — a prioritised greedy grower is served
first and leaves a `Text` sibling its zero-offer answer 0, which would not
separate a grown `a` from an ungrown one. Test 2.11 renders in a fake window over
two frames (a popover presents against the previous frame's anchor).

### 1.4 Mutations (each on the committed tree, restored from a copy, full unfiltered suite, `git status` clean after each)

| # | Mutation (file) | Reddened |
|---|---|---|
| M1.1 | inset table → `(0, 0)` (`ControlLook.swift`) | `theDefaultFieldIsTheBorderedOneAndSizesAsSwiftUI`, `aContainerTextFieldStyleReachesItsFieldsAndTheInnermostWins`, `theChromeFollowsControlSize`, `aBorderedFieldIsStillGreedy`, `theTextAndCaretSitInsideTheChrome`, `aFieldLaysOutGreedilyAndEdits`, `aSwiftUIVocabularyFormLaysOutAsTheProbeArrangesIt`, `controlSizeReachesTheDefaultFontButNoControlsChrome`, `everyControlAnswersInSwiftUIsClassInsideAProposalContainer`, `gridCellUnsizedAxesOnALegacyControlTakesItsColumnsWidth`, `theControlsDemosSwiftUISectionLaysOutWithoutReports`, `theGreedyControlsAnswerAnInfiniteProposalWithInfinity` |
| M1.2 | the field ignores the environment's style (`TextField.swift`) | `aContainerTextFieldStyleReachesItsFieldsAndTheInnermostWins` |
| M1.3 | radius 6 → 5 | `theBorderedChromePaintsTheThemesFillBorderAndRadius`, `aFocusedBorderedFieldDrawsTheControlRingAndAPlainOneDoesNot` |
| M1.4 | the chrome and ring drawn for a focused `.plain` field | `aFocusedBorderedFieldDrawsTheControlRingAndAPlainOneDoesNot` |
| M1.5 | disabled factor → 1 | `aDisabledFieldKeepsItsChromeAndDimsItsText` |
| M1.6 | `geometry` handed the outer bounds in prepaint | `theTextAndCaretSitInsideTheChrome`, `aFieldPaintsItsPlaceholderCaretSelectionAndComposition` |
| M1.7 | small inset 3.5 → 4 | `theChromeFollowsControlSize`, `controlSizeReachesTheDefaultFontButNoControlsChrome` |
| M1.8 | the chrome adds 12 to an offered width | `aBorderedFieldIsStillGreedy`, `aFocusedBorderedFieldDrawsTheControlRingAndAPlainOneDoesNot`, `aGridFormGivesItsFieldColumnTheRest`, `aSwiftUIVocabularyFormLaysOutAsTheProbeArrangesIt`, `everyControlAnswersInSwiftUIsClassInsideAProposalContainer`, `gridCellUnsizedAxesOnALegacyControlTakesItsColumnsWidth`, `theBorderedChromePaintsTheThemesFillBorderAndRadius`, `theControlsDemosSwiftUISectionLaysOutWithoutReports`, `theGreedyControlsAnswerAnInfiniteProposalWithInfinity`, `theProposalOnlyModifiersReachLegacyContent`, `theTextAndCaretSitInsideTheChrome` |
| M1.9 | the editor's fill skipped (`TextEditor.swift`) | `theTextEditorDrawsAnOpaqueFillAndPlainDrawsNone` |
| M1.10 | `TextFieldStyle.Kind` and `init(kind:)` public (guard) | `aTextFieldStyleIsWrittenOnTheFieldAndCannotBeMintedOutside` |
| M2.1a | no forwarding (`ModifiedContent.swift`) | `aPrioritisedLegacyChildKeepsItsParentsStretch`, `aLegacyItemFieldUnderALayoutPriorityIsLoweredNotReported`, `thePriorityIsLiftedAboveTheItemWrappers` |
| M2.1b | the origin not aliased, only the layer (`LegacyLowering.swift`) | `aPrioritisedLegacyChildKeepsItsParentsStretch`, `aLegacyItemFieldUnderALayoutPriorityIsLoweredNotReported`, `thePriorityIsLiftedAboveTheItemWrappers` |
| M2.3 | the lift not registered | `thePriorityIsLiftedAboveTheItemWrappers` (so the lift is needed: without it B and A split) |
| M2.4 | `PE-F`'s spelling passes priority 0 (`LegacyProposalModifiers.swift`; `PE-F`'s M1.20 analogue) | `theMG14DrawerReachesItsMaximum`, `thePriorityIsLiftedAboveTheItemWrappers`, `theProposalOnlyModifiersReachLegacyContent` |
| M2.5 | a forwarded record marked consumed on forwarding (`LoweringState.swift`) | `aPriorityLayerInAProposalStackStillReportsItsContentsItemField` |
| M2.6 | the scope's write keeps an existing entry (`EnvironmentValues.swift`) | `anEnvironmentObjectIsReadAtItsPositionAndTheNearestWriterWins` |
| M2.7 | key by `type(of: object)` | `anObjectIsKeyedByTheTypeItWasWrittenAs` |
| M2.8 | a nil write is a no-op | `writingNilClearsAnObject` |
| M2.9 | the trap's type name dropped (`EnvironmentProperty.swift`) | `aMissingObjectTrapsWithItsTypeInTheMessage` |
| M2.10 | the frame build's observation `onChange` a no-op (`Window.swift`, `RX-K` — the spec's "cached at bind" has no spelling in this design: the reader holds the object, never a property) | 80 tests, every one an observation- or lifecycle-dirtied window test: `aChainOfAppearancesSettlesOneLevelOfWritesPerPresentedFrame`, `aChangedIdRunsTheNewAppearBeforeTheOldDisappear`, `aClickOnADrawnAlertButtonPressesIt`, `aClosureBindingIgnoresItsTransaction`, `aColourFadeOnAStyleStaticElementKeepsTheDisplayLinkRunning`, `aDeclinedAlertIsDrawnAboveEverythingAndOwnsNoState`, `aDisablingTransactionReachesExactlyOneBuildAndRollsBack`, `aFocusRingAnimatesItsWidth`, `aGhostParkedOnDisappearReadsTheStateItsElementHad`, `aGroupModifierFiresOncePerGroupAndOnlyWhileItHasContent`, `aHoverBorderAnimatesItsWidth`, `aHoverBorderFadesItsResolvedColour`, `aLifecycleModifierWrittenOutsideIdKeysOnThePosition`, `aLoweredTreeMintsItsStateSlotsAndAnimatesItsWidths`, `aMainThreadMutationMarksTheWindowDirtySynchronously`, `aMonitorAssignedInOnAppearIsTheOneOnDisappearStops`, `aNeverWrittenStateDefaultIsReseededSoOnAppearAndOnDisappearSeeDifferentInstances`, `aParentAndItsChildUnderOneGhostDisappearTogetherChildFirst`, `aParkedTransactionIsConsumedByExactlyOneBuild`, `aProposalAnimationKeepsTheDisplayLinkAwakeUntilItSettles`, `aResizeIntoContentLimitsOnALifecycleFrameOwesTheNextFrame`, `aReturningAnimatingElementSnapsInsideAnIfAndInsideALoop`, `aScopeLeavingTheTreeWhilePresentedIsDismissedAndItsLateAnswerRunsNothing`, `aStaleAlertAnswerNeverReachesTheNextAlert`, `aStaleDialogAnswerNeverReachesTheNextRequest`, `aSteadyFrameDoesThreeUnitsOfLifecycleWorkPerScope`, `aTogglesIndicatorColourAnimatesUnderWithAnimation`, `aTransactionModifierRewritesItsSubtreesAnimation`, `aTransactionParkedOutsideTheBuildAnimatesTheNextFrameEndToEnd`, `aTransactionWhoseBodyDirtiesNothingIsNeverParkedAndCannotAnimateALaterChange`, `aTransactionWithNoAnimationSnaps`, `aTransitionKeepsTheDisplayLinkAwakeThenLeavesNothing`, `aWriteInOnDisappearIsLostAndReturningContentStartsFresh`, `actionsRunOutsideEveryPhaseUnderTheirElementsDispatch`, `anActionThatDrawsAFrameDoesNotDrainReentrantly`, `anAnimatedFrameWidthInterpolatesAsTheAnimatedWidthItReplacesDid`, `anAnimatedInsetInterpolatesItsValue`, `anAnimatedItemFieldSnapsItsStructureAndInterpolatesItsValues`, `anAnimatedRemovalDisappearsWhenItsGhostEnds`, `anAnimatedWriteThatIsNotTheFirstObservableWriteOfItsIntervalStillAnimates`, `anAnimationModifierAnimatesOnlyWhenItsValueChanges`, `anAnimationModifierOverridesTheExplicitTransaction`, `anAnimationModifierReachesOnlyItsContent`, `anAnimationScopeThatLeavesForAFrameLeavesTheStore`, `anAnimationScopesFirstSightingSnapsOverASurvivingBaseline`, `anAnimationWithAClientActivePostsNothingAndTouchesNoElement`, `anEnvironmentObjectsReadPropertyDirtiesTheWindowAndAnUnreadOneDoesNot`, `anObservableWriteInOnAppearIsPresentedAndNotLost`, `anObservableWriteWakesAPausedWindowAndDrawsExactlyOneFrame`, `anOffScreenListRowsModelReadIsNotTracked`, `anOffThreadMutationMarksTheWindowDirtyAfterAHop`, `anOnDisappearOutsideTheTransitionAlsoWaits`, `anUnanimatedRemovalDisappearsAtOnceAndAnAnimatedInsertionAppearsAtOnce`, `changesRunBeforeAppearsAndAppearsBeforeDisappears`, `contentMovingUnderAStillPointerUpdatesHoverAfterTheFrame`, `disablesAnimationsSuppressesOnlyTheAnimationModifier`, `eachRemovalCountsOnlyTheDepartedValuesItsOwnSweepKept`, `initialTrueFiresWithAppearInModifierOrder`, `insertionRunsChildrenBeforeParentsAndLaterSiblingsFirst`, `isPresentedFalseDismissesAndALateResultRunsNothing`, `isPresentedFalseDismissesTheAlert`, `mutatingAnObservedModelMarksTheWindowDirty`, `noDepartedValuesAreKeptWithoutAnOnDisappear`, `onChangePassesTheOldAndNewValues`, `onDisappearReadsItsOwnStateAsItWasLastFrame`, `propertyAnimationsRunUnchangedUnderReduceMotion`, `reinsertingDuringTheGhostRunsNeitherCallbackAndStartsWithFreshState`, `removalRunsInReversePreOrderEvenForSeparatelyRemovedSiblings`, `returnPressesTheDefaultAndEscapeTheCancelOnTheDrawnAlert`, `stackedLifecycleModifiersKeepSeparateEntriesInnerFirst`, `stateAndObservableAreIndependentDirtySources`, `tabAndArrowsMoveTheRingAndSpacePressesIt`, `theAnimationModifierAppliesInPaintAsInLayout`, `theDisplayLinkStaysRunningWhileAnimatingAndPausesOnTheFrameAfterTheLastEnds`, `theDrawnAlertPublishesAnAlertNodeWithButtonChildren`, `theObserverSetIsBoundedRegardlessOfFramesDrawn`, `thePaintOnlyDecorationFieldsAnimateAndClipSnaps`, `theZeroParameterFormFires`, `twoAnimationScopesAtOnePositionKeepSeparateValues`, `withTransactionAnimatesAChangeAsWithAnimationDoes` |
| M2.11 | `AnyElementBox`'s layout bind skipped (`AnyElement.swift`) | `anEnvironmentObjectReachesComponentAnyElementDeferredAndPopoverContent`, `anEnvironmentPropertyInsideAnyElementReadsItsScope`, `aFocusStateSurvivesInsideAComponentAndAnAnyElement`, `stateInsideAnAnyElementIsReboundForPrepaintAndPaint`, `stateInsideAnAnyElementPersistsAcrossFrames` |
| M2.12 | the `Observable` constraint dropped from both initialisers and the modifier (guard) | `onlyAnObservableClassIsAnEnvironmentObject` |

Both new guards (1.10, 2.12) mutated red once. No hang.

### 1.5 Must-not-move

- Demo pixels: `docs/probes/demo-pixels/compare.sh <scratch> d48b26d HEAD` at
  `48c6703`, `cd29b3c` and `0d745ea`: **0 differing in all fourteen images,
  scene identical**; every control at `d48b26d` reads its recorded value.
- `Tests/MetalUICrossPlatformTests/Expected.swift` unedited; no
  `Backends/SDL`, `MetalUILayout` or `MetalUIScene` file touched.
- Identity, hit testing, accessibility, animation, focus, `List`, `Deferred`,
  text-input logic: unchanged except as `MD-Q` names (a default field's size and
  text position, the ring and the disabled dim).
- Inventory: `closeout-inventory-check.sh` and `closeout-undocumented.sh` print
  nothing; families `field-style` (D: 131 132 133) and `environment-object`
  (D: 134); census re-recorded (2461 lines).
- Divergences: 101 live, next label 135 (132, 133, 134 added; 131 and 76
  amended). Migration note for the field default (`MD-C` item 3).

### 1.6 Deferred by lane 1

None of its items. `@Bindable` and `ObservableObject` are "Not offered" rows
(`MD-H` item 6). Human checks W1/W2 (the field and editor looks) are lane 3's
to write.
