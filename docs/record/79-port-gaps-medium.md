# 79 — Port gaps, medium: field chrome, `layoutPriority`, environment objects, window toolbar (lanes 1–3 landed)

Branch `feat/port-gaps-medium` from `d48b26d` (master: proposal controls merged,
PR #49). **Not a plan task**: user request 2026-10-02, an item of the gpui-gap
priority list — the SMK configurator port's four medium gaps MG-20, MG-14, MG-2
and MG-3. Spec `docs/superpowers/specs/2026-10-07-port-gaps-medium-design.md`;
rulings `MD-A`…`MD-W` in `docs/superpowers/2026-10-07-port-gaps-medium-decisions.md`
(next unused `MD-X`); probes `docs/probes/swiftui-field-chrome.swift`,
`swiftui-environment-object.swift`, `swiftui-toolbar.swift`,
`swiftui-toolbar-nested.swift`.

**Status: lanes 1, 2 and 3 landed (2026-10-07, §1, §2, §3).** The Record
phase completes this record.

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
  when disabled (bordered styles only, `MD-W`) — `FieldChrome` and `PaintPass.paintFieldChrome` in
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

M2.10 is not a mutation specific to environment objects: this design has no
"cached at bind" spelling (the reader holds the object, never a property), so
test 2.10 pins `RX-K` through `@Environment` and has no mutation site of its own
— the observation no-op reddens it among every observation-dirtied window test.

### 1.4a Review fixes (`MD-W`)

The lane 1 review found six unpinned spellings (V1, V2, V3, V5, V8, V9 — each
green across the whole suite at `cec9c42`). Fixed in `464a657` (tests, the
`.plain` dim restriction, comments) and `MD-W`: a disabled `.plain` field
takes no dim, so `.textFieldStyle(.plain)` restores the previous field exactly
(the migration row and `MD-C` item 2 now hold); a `layoutPriority` on a
`Deferred` keeps the layer in flow, as at `d48b26d`. Suite after: **2605 tests
in 3 suites** passed (native, unfiltered, `--no-parallel`, `FR-J … succeeded=true`;
0 `error:`; the only `warning:` SwiftPM's deprecation notice; `swift build
--build-tests` 0 warnings). Each mutation on the committed tree, restored from
the commit, full unfiltered suite, `git status` clean after each:

| # | Mutation (file) | Reddened |
|---|---|---|
| V1 | `callerRing: decoration.focusBorder != nil` → `false` (`TextField.swift`) | `aFocusedBorderedFieldDrawsTheControlRingAndAPlainOneDoesNot` (its new `focusBorder` arm) |
| V2 | the editor's `focused: pass.isFocused(id)` → `false` (`TextEditor.swift`) | `aFocusedTextEditorDrawsTheSquareControlRingAndAPlainOneDoesNot` (1.12) |
| V3 | `editorStyle ?? pass.environment.textEditorStyle` → `?? .automatic` (`TextEditor.swift`) | `aContainerTextEditorStyleReachesItsEditorAndTheInnermostWins` (1.11) |
| V5 | the text clip → the content rect (`TextField.swift`) | `aBorderedFieldClipsItsTextToTheContentWidthAndTheWholeHeight` (1.13, the vertical arm) |
| V8 | `forward`'s `item.kind != .presentation` removed (`LoweringState.swift`) | `aPriorityOnADeferredKeepsTheLayerInFlowAndPresents` (2.13: the third child at 22, not 34) |
| V9 | the dim for every style (`TextField.swift`; the pre-review spelling) | `aDisabledFieldKeepsItsChromeAndDimsItsText` (its new `.plain` arm) |

Demo pixels `compare.sh <scratch> d48b26d 810fa27`: controls as recorded, **0
differing in all fourteen images, scene identical**.

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

### §1.4b Lane 1's review mutations re-run to completion (coordinating session, 2026-10-07)

The re-verifier hit its deadline before any mutation finished, so the
coordinating session re-ran its own script (`mut.sh`) on `963d325`: unmutated
baseline `Test run with 2618 tests in 3 suites passed`; each mutation applied
to the committed tree, native build, full unfiltered `--no-parallel` suite,
restored with `git checkout`, `git status --short` empty after each.

| Mutation | Spelling | Reddened (only) |
| --- | --- | --- |
| V1 | `TextField.swift`: `callerRing: decoration.focusBorder != nil` → `false` | `aFocusedBorderedFieldDrawsTheControlRingAndAPlainOneDoesNot` (1 issue) |
| V2 | `TextEditor.swift`: `focused: pass.isFocused(id)` → `false` | `aFocusedTextEditorDrawsTheSquareControlRingAndAPlainOneDoesNot` (2) |
| V3 | `TextEditor.swift`: `editorStyle ?? pass.environment.textEditorStyle` → `?? .automatic` | `aContainerTextEditorStyleReachesItsEditorAndTheInnermostWins` (1) |
| V5 | `TextField.swift`: `pass.clipped(to: clip, …)` → `to: bounds` | `aBorderedFieldClipsItsTextToTheContentWidthAndTheWholeHeight` (5) |
| V8 | `LoweringState.swift` `forward()`: drop `item.kind != .presentation` | `aPriorityOnADeferredKeepsTheLayerInFlowAndPresents` (1) |
| V9 | `TextField.swift`: drop `&& resolvedStyle(in:).isBordered` from the dim | `aDisabledFieldKeepsItsChromeAndDimsItsText` (2) |

§1.4a's claims are reproduced; lane 1's review is resolved.

## 2. Lane 2 — the toolbar, native (`MD-I`, `MD-J`, `MD-N`, `MD-S`, `MD-U` items 1–3, `MD-X`, `MD-Y`)

| Step | Commit | Suite after |
|---|---|---|
| Red — tests 3.1–3.5, 3.11, 3.12, 3.18, guards 3.13, 3.14, 3.17, SDL 3.15 | `58fd855` | does not compile |
| Green | `963d325` | **2618 tests in 3 suites** passed |
| Test 3.5's proposal arm made able to fail (`MD-Y`) | `c3475bb` | 2618 passed (after `swift package clean`, native, `FR-J … succeeded=true`, 0 `error:`) |

Thirteen tests on the main package (2605 → 2618: six in `ToolbarTests`, four in
`AppKitToolbarTests`, three guards in `ToolbarCompileGuards`), one in
`Backends/SDL` (`theSDLWindowAsksTheFrameworkToDrawItsToolbar`).

### 2.1 Red lines

- `ToolbarTests.swift:66: cannot find type 'PlatformToolbar' in scope`
- `AppKitToolbarTests.swift:28: cannot find type 'ToolbarActionEvent' in scope`
- `SDLToolbarTests.swift:20: value of type 'SDLWindow' has no member 'toolbar'`
- The guards' fixtures name `ToolbarItem`/`PlatformToolbar`, absent at `34f68c3`.

### 2.2 What landed

- **Public API** (`Sources/MetalUI/Toolbar.swift`): `.toolbar { }` and
  `.searchable(text:prompt:)` on every `ElementGroup`, both returning a
  transparent `ToolbarScope` (no node, no id level, typed and untyped entries).
  `ToolbarScope` is **not an `Element`**, so a window root cannot carry it
  (`MD-S`, divergence 120 amended, guard 3.17). `ToolbarItem(placement:id:)`,
  `ToolbarItemGroup`, `ToolbarItemPlacement` (`navigation`, `principal`,
  `primaryAction`, `automatic`, `status`), the closed `ToolbarContent`/
  `ToolbarItemContent` (`Button` with a `ToolbarButtonLabel` — `Text` or
  `Image` only, `MD-X` item 1 — `Toggle`, `Picker` menu or segmented,
  `TextField`, `Text`) through SPI requirements (divergence 135, guard 3.13).
- **Collection** (`Frame.swift`): toolbars merge window-wide in build pre-order;
  one under a popover or a `Deferred` presentation root is dropped. Ids per
  `MD-X` item 3.
- **Neutral types** (`Sources/MetalUIPlatform/Toolbar.swift`): `PlatformToolbar`,
  its items and controls, `==` written by hand, images compared by texture
  identity (`MD-U` item 1); `InputEvent.toolbarAction(ToolbarActionEvent)`.
- **Window** (`Window.swift`): sends `setToolbar` only when the description
  changes (and never for a window that has had none); a `toolbarAction` runs
  its item's closure under `StateDispatch`, a disabled item ignored.
- **Platform**: `PlatformWindow.setToolbar(_:) -> Bool`, **defaultless**
  (guard 3.14). AppKit (`Sources/MetalUIAppKit/AppKitToolbar.swift`): a real
  `NSToolbar` of native controls (`NSButton`, a checkbox `NSButton` for a
  toggle, `NSPopUpButton`/`NSSegmentedControl`, `NSTextField`, a label field,
  and `.searchable` as an `NSSearchToolbarItem` last),
  updated in place when only values change, rebuilt when the shape changes;
  the content size restored explicitly after each change (`MD-X` item 2,
  measured 900 × 200 → 900 × 232 without it); a toolbar field taking first
  responder leaves MetalUI's focus alone (test 3.18). SDL records the
  toolbar on `SDLWindow.toolbar` and answers `false` (lane 3 draws it; interim
  per `MD-R`: an SDL window shows no toolbar until then). Every test fake and
  guard fixture implements the requirement; migration note in
  `docs/migration.md` Part 2.
- Inventory family `toolbar` (class D, 135); census re-recorded (2532 lines);
  `closeout-inventory-check.sh` and `closeout-undocumented.sh` print nothing.
  Divergences: 102 live, next label 136.

### 2.3 Mutations (committed tree, applied by script, restored from a copy, full unfiltered native `--no-parallel` suite, `git status --short` empty after each)

| # | Spelling | Reddened |
|---|---|---|
| M3.1 | `ToolbarItemPlacement.status = …(kind: .automatic)` | `aToolbarReachesThePlatformAsOneNeutralDescription`, `theToolbarIsSentOnlyWhenItChanges`, `aToolbarActionRunsItsItemUnderStateDispatch` (5 issues) |
| M3.2 | `Window`: drop `guard toolbar != sentToolbar else { return }` | `theToolbarIsSentOnlyWhenItChanges`, `aWindowWithNoToolbarNeverCallsSetToolbar`, `aToolbarActionRunsItsItemUnderStateDispatch` (5) |
| M3.3 | `Window`: run the item without `StateDispatch.dispatching(to:)` | `aToolbarActionRunsItsItemUnderStateDispatch` (1) |
| M3.4 | `Frame`: `if isPresentation, …` → `if false, …` (presentation toolbars kept) | `toolbarsMergeInTreeOrderAndIgnorePresentationRoots` (1) |
| M3.5 | untyped entry: `cursor += 1` after the content | `aToolbarScopeIsTransparentToLayoutAndIdentity` (2) |
| M3.5b | typed entry: the same, at `963d325` | **none — suite passed**: the proposal arm's `Text` members record no element bounds (`MD-Y`) |
| M3.5c | M3.5b re-applied at `c3475bb` | `aToolbarScopeIsTransparentToLayoutAndIdentity` (1) |
| M3.11 | `AppKitWindow`: never update in place (`if false, let toolbar, …`) | `theAppKitToolbarBuildsNativeItemsAndUpdatesThemInPlace` (2) |
| M3.12 | toggle target sends `.press` | `anAppKitToolbarControlSendsItsActionAsAnInputEvent` (1) |
| M3.13 | `_ToolbarItemContext`, `_ToolbarControls`, `_ToolbarContext`, `_ToolbarEntries` and their requirements made plain `public` (SPI dropped) | guard `onlyTheClosedSetIsToolbarContent` (2) |
| M3.14 | `extension PlatformWindow { public func setToolbar(_:) -> Bool { false } }` | guard `setToolbarHasNoDefault` (1) |
| M3.17 | `extension ToolbarScope: Element where Content: Element` (trapping stubs) | guard `aToolbarOnAWindowRootNeedsAContainer` (1) |
| M3.18 | the window clears MetalUI focus on a toolbar text action | `aNativeToolbarFieldTakingFirstResponderLeavesMetalUIFocusAlone` (1) |

SDL test 3.15 was not mutated (it reads one recorded property).

### 2.3a Review fixes (lane 2 review: `.disabled`, picker style, `.help`, three documented rules)

The review found eight mutations along documented toolbar paths that left
the suite green (2618). Two tests were added to `ToolbarTests.swift`,
numbered past the spec's 3.18 so they do not collide with lane 3's 3.6–3.10:
**3.19** `aDisabledToolbarItemReachesThePlatformDisabledAndRunsNothing` (a
`.disabled(true)` control and a toolbar under a `.disabled(true)` container
reach the platform as `isEnabled == false`, and a queued `.toolbarAction` for
either runs nothing while the enabled sibling's runs), and **3.20**
`theToolbarItemMappingRulesReachThePlatform` (`.menu` → `.menu`, default and
`.radioGroup` → `.segmented`; `.help` → `PlatformToolbarItem.help`; a group
of one → `automatic.4.0`; an `EmptyGroup` scope contributes nothing, on the
untyped entry and on the typed entry inside a `VStack`; `onClick` replaces a
toolbar button's action). The unmutated suite at `1bfde3b`: **2620 tests in 3
suites passed**. Every mutation below was applied by script to
`Sources/MetalUI/Toolbar.swift` at `f5852d2`, restored from a copy, full
unfiltered native `--no-parallel` suite, `git status --short` empty after each:

| # | Spelling | Reddened (2620 run) |
|---|---|---|
| V1 | `Window.handleToolbarAction`: `, target.isEnabled` dropped from the guard | `aDisabledToolbarItemReachesThePlatformDisabledAndRunsNothing` (2 issues) |
| V2 | `EnvironmentScope`'s conformance: `if case .transform(let transform) = write { transform(&values) }` → `_ = write` | `aDisabledToolbarItemReachesThePlatformDisabledAndRunsNothing` (3) |
| V3 | `Button`'s conformance: `help: nil` | `theToolbarItemMappingRulesReachThePlatform` (1) |
| V4 | `Picker`'s conformance: `style: .segmented` unconditionally | `theToolbarItemMappingRulesReachThePlatform` (1) |
| V5 | `AssembledToolbar`: `let numbered = entry.controls.count > 1` | `theToolbarItemMappingRulesReachThePlatform` (1) |
| V6 | untyped entry: `if !nodes.isEmpty {` → `if true {` | `theToolbarItemMappingRulesReachThePlatform` (1) |
| V6b | typed entry: the same | `theToolbarItemMappingRulesReachThePlatform` (1) |
| V7 | `noteToolbar`: `declaration.entries(isEnabled: true)` | `aDisabledToolbarItemReachesThePlatformDisabledAndRunsNothing` (2) |
| V8 | `Button`'s conformance: `let run = action` (ignoring `onClick`) | `theToolbarItemMappingRulesReachThePlatform` (1) |

### 2.4 Must-not-move

- Demo pixels: `docs/probes/demo-pixels/compare.sh <scratch> d48b26d HEAD` at
  `963d325`: **0 differing in all fourteen images, scene identical**
  (`c3475bb` changes a test only).
- `Tests/MetalUICrossPlatformTests/Expected.swift`, `MetalUILayout`,
  `MetalUIScene`: untouched. `Backends/SDL`: `SDLPlatform.swift` and the new
  test only.
- `Backends/SDL` on macOS: **24 + 78** passed (24 + 77 at `d48b26d`). Linux image
  (`Backends/SDL/linux/Dockerfile`, offscreen driver): **24 + 75** passed
  (24 + 74). The one compiler warning there,
  `AccessKitControlsParityTests.swift:83` (`no calls to throwing functions occur
  within 'try'`), is in a file this branch does not touch.
- `swift build --build-tests` (default build system): 0 `warning:`.
- Identity, hit testing, accessibility, animation, focus, `List`, `Deferred`,
  text input: unchanged (the scope is transparent, test 3.5; AppKit focus test
  3.18).

### 2.5 CI hazard (`MD-X` item 4)

`NSButtonCell.performClick(_:)` spins a nested run loop; in a test it ran a
`CFRunLoopStop` an earlier test had queued and the process **exited 0 with no
summary line**. AppKit tests fire a control by setting its state and calling
`sendAction(_:to:)`.

### 2.6 Deferred by lane 2

Lane 3's items (`MD-R`): the drawn strip on SDL (tests 3.6–3.10, 3.16), the
demo section and the human checks for the native toolbar's look.


## 3. Lane 3 — the drawn strip and the demo (`MD-K`, `MD-M`, `MD-Z`)

| Step | Commit | Suite after |
|---|---|---|
| Red — tests 3.6–3.8, 3.10, 3.16 (`ToolbarStripTests`) and arm 3.9 (`everyNamingSiteStartsAReturningNameFresh`) | `fdc5508` | does not compile (`cannot find 'ToolbarStrip' in scope`; `Frame` has no member `drawsToolbarStrip`; no `portGapsModel`/`PortGapsDemoIDs`) |
| Green | `9f858ea` | **2625 tests in 3 suites** passed |
| Review fixes — tests 3.6b–3.6f | this section's commits | **2630 tests in 3 suites** passed (native, unfiltered, `--no-parallel`, `FR-J … succeeded=true`, 0 `error:`) |

### 3.1 What landed

- `Sources/MetalUI/ToolbarStrip.swift`: where `setToolbar` answers `false`
  (SDL; `FakePlatformWindow.toolbarIsNative = false` in tests), the window
  draws its toolbar as a 39-point strip (7 + 24 + 7, a 1-point `.separator`
  at y 38, filled `.surface`) under the named root `$toolbar` at `(nil, 1)`;
  items keyed by their platform ids; navigation leading, primary/automatic
  and search trailing, principal and status centred in an overlay. Each item
  carries its `isEnabled` as `.disabled(!isEnabled)` (`MD-Z` item 3).
- `Frame.swift`: the strip is requested after the root (the toolbar records
  are complete then), its run computed **before** the root's (`MD-Z` item 2),
  prepainted and painted after the root and its removal ghosts, below the
  drag preview, menu, tooltip and alert (`MD-Z` item 6). The root is offered
  and centred in the rect below the strip; measured content limits add 39
  (`MD-Z` item 4).
- `Window.swift`: one extra build when the strip's presence changes, placed
  after the lifecycle's settle build (`MD-Z` item 5).
- The controls demo's port-gaps section (`portGapsDemoSection()`, its own
  function) and the demo root's toolbar (`MD-M`, `MD-Z` item 7). Divergence
  136; human checks W1–W5.

### 3.2 Mutations (committed tree, applied by script, restored from a copy, full unfiltered native `--no-parallel` suite, `git status --short` clean of sources after each)

Spec mutations, run at `9f858ea` by the lane 3 review (2625-test suite):

| # | Spelling (file) | Reddened |
|---|---|---|
| M3.6 | `static let height: Float = 39` → `0` (`ToolbarStrip.swift`) | `aDrawnToolbarStripSitsAboveTheRootAndKeepsItsIds` (17 issues) |
| M3.7 | `if lastBuildDrewToolbarStrip != toolbarIsDrawn {` → `if false {` (`Window.swift`) | `aDrawnToolbarIsInTheFirstPresentedFrame`, `aDrawnToolbarControlIsAnOrdinaryControl`, `aDrawnToolbarStripSitsAboveTheRootAndKeepsItsIds` (4) |
| M3.8 (literal) | the strip's `prepaint` call removed, `paint` kept (`Frame.swift`) | **no summary line**: `AnyElement.swift:177: Fatal error: AnyElement.paint before prepaint` inside `everyNamingSiteStartsAReturningNameFresh`; the unmutated suite finishes, so the spelling is an instrument that cannot redden test 3.8 |
| M3.8 (as the spec now reads) | the strip's `prepaint` **and** `paint` calls removed | `aDrawnToolbarControlIsAnOrdinaryControl`, `aDrawnToolbarIsInTheFirstPresentedFrame`, `aDrawnToolbarStripSitsAboveTheRootAndKeepsItsIds`, `everyNamingSiteStartsAReturningNameFresh` (6) |
| M3.9 | the root's `stateTable.noteNamed(ToolbarStrip.rootID, …)` removed | **none** — expected (`MD-Z` item 1: one fixed name at its own position can depart nothing) |
| M3.9b | `ForEach(trailing, id: \.id)` → `id: \.placement` | `everyNamingSiteStartsAReturningNameFresh`, `aDrawnToolbarControlIsAnOrdinaryControl`, `aDrawnToolbarIsInTheFirstPresentedFrame` (3) |
| M3.10 | the extra-build condition → `if true {` | `aDrawnToolbarIsInTheFirstPresentedFrame` and every build-counting test (138 tests, 80 issues) |
| M3.16 | `.environment(portGapsModel)` → `.environment(nil as PortGapsModel?)` (`ControlsDemo.swift`) | `theControlsDemoShowsThePortGapsSection` (1) |
| X5 | the strip's prepaint moved before the root's | `aDrawnToolbarControlIsAnOrdinaryControl` (1) |

### 3.3 Review fixes

The review's mutations X1, X2, X3, X4, X6, X7 and X8 left the 2625-test
suite green. Five tests were added to `ToolbarStripTests.swift`: **3.6b**
`aGreedyRootIsOfferedOnlyTheRectBelowTheStrip` (a root filling a 400 × 400
drawn-strip window is exactly (0, 39, 400, 361); now a pin of divergence
136), **3.6c** `aDrawnToolbarStripPaintsAboveTheRoot` (`lastScene` holds the
`.surface` fill (0, 0, 400, 39) and the `.separator` line (0, 38, 400, 1),
both after the root's `.accent` fill, glyphs within y 0…39), **3.6d**
`aDisabledItemInTheDrawnStripRunsNothing` (an item under a `.disabled(true)`
scope: a click at its strip centre runs nothing; the enabled sibling runs),
**3.6e** `drawnStripItemsArePlacedByPlacement` (navigation at x 8, principal
centred at 200, the trailing field ending at 392), **3.6f**
`theStripsRunIsNotTheRootsAndItsHeightJoinsTheContentMinimum` (the deepest
level equals the native window's; under `.contentMinSize` the minimum height
is the native one + 39). Each mutation re-run on the review-fix commit,
2630-test suite:

| # | Spelling | Reddened |
|---|---|---|
| X1 | the strip's `computeNativeLayout` run moved after the root's (`Frame.computeRootLayout`) | `theStripsRunIsNotTheRootsAndItsHeightJoinsTheContentMinimum` (1) |
| X2 | `plus: top)` → `plus: 0)` (both measurements) | `theStripsRunIsNotTheRootsAndItsHeightJoinsTheContentMinimum` (1) |
| X3 | `element().disabled(!isEnabled)` → `.disabled(false)` (`ToolbarStripItem.body()`) | `aDisabledItemInTheDrawnStripRunsNothing` (1) |
| X4 | the strip's `paint` call removed from `Frame.render` | `aDrawnToolbarStripPaintsAboveTheRoot` (3) |
| X6 | navigation items moved into the trailing group | `drawnStripItemsArePlacedByPlacement` (1) |
| X7 | the root proposed `height: height` instead of `rootHeight` | `aGreedyRootIsOfferedOnlyTheRectBelowTheStrip`, `aDrawnToolbarStripPaintsAboveTheRoot` (2) |
| X8 | `.background(.surface)` removed from the strip | `aDrawnToolbarStripPaintsAboveTheRoot` (1) |

### 3.4 Must-not-move

- Demo pixels at `9f858ea` (`compare.sh <scratch> d48b26d HEAD`): **0
  differing in all fourteen images, scene identical**; the review fixes touch
  tests and docs only.
- `Backends/SDL` on macOS at `9f858ea`: **24 + 78** passed (unchanged by lane
  3, which touches no SDL file).
- `Tests/MetalUICrossPlatformTests/Expected.swift`, `MetalUILayout`,
  `MetalUIScene`: untouched.
