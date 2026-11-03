# Record 201: an `AnyElement` type swap resets (round 4 item R4-1a)

Branch `feat/r4-1a-anyelement-reset`, from master `f1eb7950`. Decisions: `docs/superpowers/2026-11-03-anyelement-reset-decisions.md` (`ER-A`..`ER-D`). Human checks: none (nothing here is a look; the one visual question is recorded as unmeasured, section 1). Divergences: **210 retired, 211 and 212 added** (208 live: 207 - 1 + 2; next label 213).

## 0. The machine (lock state)

`docs/probes/appkit-screen-lock-state.swift`, run first, 2026-11-03 (macOS 27.2 26B123): `CGSSessionScreenIsLocked = 1`, `displayAsleep main: 0`, `displayActive main: 1`, `preflightScreenCaptureAccess: false`. **The session was locked with no Screen Recording permission**, so no arm read pixels. The arms that need no pixels ran: every `AV` arm is a log of
`body`, `appear`, `disappear`, `task` and `Animatable` evaluations, and `AVF` posts its events to the probe's own `KeyWindow` through `NSApp.sendEvent`. **A stale reading cannot pass for a fresh one**: the controls were re-run in the same session before the `AV` arms and read as recorded (D5 `body B n=20`, `body A n=10`; D5b `body B n=20`; T1 `disappear x` only after the 1.0 s spin;
K0 `focused=true,k:x[down]`, FC1 `focused=true`, RS0 `focused=true,|start`), and the whole lifecycle file was run twice (2484 and 2381 lines, equal outside `AV6c`'s `slide` lines and the lazy rows).

## 1. What the probes showed (`swiftui-lifecycle.swift` `AV*`, `swiftui-key-focus.swift` `AVF`; headers hold the output)

| arm | reading | consequence |
|---|---|---|
| `D5`, `D5b` (re-run) | B reads 20; B reads 20 with A written 11 | gate held: no stop |
| `AV1` | A written 11, swapped to B, swapped back: A reads **10** | the `noteNamed` reset is right; no revival; M15 (keyed id alone) is insufficient |
| `AV1b` | one update setting the flag true then false: nothing evaluated, 11 kept | no swap |
| `AV2`, `AV3c`, `AV3c2` | same type from two `AnyView(...)` expressions, `padding 5/20`, `opacity 0.5/1`: 11 kept, nothing fires | the key is the wrapped type alone |
| `AV3a`, `AV3b` | `Gen<Int>`/`Gen<String>`, `VStack{A}`/`HStack{A}`: reset to 10 | `ObjectIdentifier(E.self)` is the right key |
| `AV3d`, `AV3e` | `+ .background(red)`, `.padding` to `.opacity`: **reset** | a modifier is part of the type; MetalUI's legacy `Self`-returning decoration is not: divergence **211** |
| `AV4a`, `AV4b` | inner swap resets inner (B 20), sibling keeps 31; an outer `VStack`/`HStack` change resets the inner `AnyView` | as the plan predicted |
| `AV5a` | `disappear A` **then** `appear B` | MetalUI's `LC-F` order is appears first: divergence **212** (recorded, not special-cased) |
| `AV5b` | `onDisappear` reads 11, writes 99; swap back reads 10 | overlay (`LC-I`), write lost |
| `AV5c`, `AV5d` | an outer modifier fires nothing; old task cancelled, new started | as predicted |
| `AV6a`, `AV6b` | under `withAnimation(0.6)`, with or without `.transition(.opacity)`, `disappear A` fires in the swap's own step (T1 control delays it) | no removal ghost, as MetalUI. **Whether the swap cross-fades on screen: unmeasured** (no pixels) |
| `AV6c` | A at x = 41.4 mid-flight; B appears at x = 100.0 (settled); A returns at 100.0 | consistent with "B starts settled, A starts fresh"; **"mid-flight on return" is not separated** (logging slows the clock): unmeasured |
| `AVF` | A focused hears `x`; after the swap nobody hears it and no `focused=false`; after the swap back A hears nothing and logs no `focused=true` | focus neither survives nor returns |

No stop condition of the plan's section 6 fired. `AVF` ran (the events go to the probe's own window), so `IX-I`'s analogy was not needed.

## 2. What changed

- `AnyElement.wrappedType` (internal `ObjectIdentifier`) and `contentID(under:)`; `GroupLayout.contentID`; `requestGroupLayout` mints the `$erased` level, calls `noteNamed(T, at: 0)` and lays out under it; `prepaintGroup` and `paintGroup` pass the level (the position keeps `recordElementBounds` and its own `noteNamed`). Two source files, no public declaration, no journal case, no `StateTable` write site.
- Divergence 210 retired, 211 and 212 added; `FV-C` item 3 overturned (forward note in the `FV-` decisions doc); `identity-state.md` (the `@State` clause and a bullet), `decision-prefixes.md`, `migration.md`, the guide's caution and divergence line, `closeout-inventory-map.tsv` (the `any-element` row), `Tasks.md`.
- **The refuted claim, corrected where it was copied:** "boxing every child moves no path" (`ElementBuilder.swift`, the `AnyElement.swift` header, `IdentityTests`).
- **Tests that moved** (path reads only, unfiltered run): `twoErasedSiblingsDoNotShareOneStateEntry`, `anOnOpenURLOnAnErasedElementIsOwnedByTheScopesOwnId`, and four the plan did not list, `aHiddenElementInsideAnyElementIsHiddenUnderTheProposalAuthority`, `aDeclaredSizeBelowThePaddingKeepsItsFixedFrame`, `reversingKeepsIdentityPaintOrderHitOrderAndAccessibilityOrder`,
  `aStretchedChildFillsTheLineOnItsCrossAxis`, `aGrowingChildTakesTheRemainingMainSpace` (lowering tests whose containers are `AnyElement`s; they read ids by hand). `everyCitedPinNamesATestThatExists` reddened for the retired pin's name in the guide, fixed by the new sentence. `anAnyElementSwapKeepsTheSlotOfTheTypeItReplaced` (the divergence-210 pin) is replaced by `anAnyElementSwapReadsTheNewTypesOwnValue`.
- **New:** `AnyElementResetTests` (`anAnyElementSwapReadsTheNewTypesOwnValue` x 2, `anAnyElementSwapBackStartsFresh` x 2, `theSameWrappedTypeKeepsItsState`, `differingGenericsAreDifferentTypes`, `aContainerOfAnotherTypeResetsItsDescendants`, `aNestedAnyElementResetsOnlyWhatChanged` x 2, `aSwapRunsDisappearAndAppearOnce`, `aSwapCancelsTheOldTaskAndStartsTheNew`, `aSwapResetsAScrollOffset`,
  `aFocusedElementLosesFocusInTheSwapFrameAndDoesNotGetItBack`, `aSwapUnderAnAnimationIsInstant`, `aScrollToReachesANamedElementInAnAnyElement`, `aDirectRequestLayoutMintsNoLevel`, `aSteadyErasedPositionCostsOneNameAndNoScan`, `aLegacyDecorationIsNotATypeChangeUnderAnAnyElement` x 2), `AnyElementResetRetainedTests` (`aSwapUnderAnEquatableParentDrawsTheNewType`,
  `aGraftedPositionStillResetsWhenItSwaps`, `aSameTypeRebuildKeepsItsInnerRecord`, `aSwappedBackEquatableChildStartsCold`, `anEqualShapeSwapMeasuresTheNewTypesText`), an arm of `everyNamingSiteStartsAReturningNameFresh`. Both new files are portable-safe (`import Observation`; the first is `#if canImport(Darwin)`).
- **A finding in the instruments:** the first run of the new file read `[20]` with the old code. A `@State` slot is named by its property's position (`$state<k>`), so two types with the state at different positions never shared a slot and could not show 210. The instruments declare their stored properties in one order.

## 3. For callers (MetalCreator, MetalFlow)

- Swapping `AnyElement(A)` for `AnyElement(B)` at one position now resets A's and B's state (written or not), focus, `.task`, lifecycle keys, animation baselines and memos, runs `onDisappear` for A and `onAppear` for B (new first, `LC-F`), and a swap back to A starts fresh. The same wrapped type changes nothing. A toolbar item or menu-bar title whose content type changes now resets.
- **Paths move one level** under a group-entered `AnyElement`: hitbox ids, accessibility record ids, `$state`/`$focus`/`$ax` slots and layout node ids of the wrapped element sit under a `$erased` component (keyed by the type). An element's recorded bounds (`scrollTo`, `frame(ofID:)`) stay at the position. Code that hand-builds a `GlobalElementID` under an `AnyElement` must go one level deeper (`AnyElement.contentID(under:)` is internal).
- A direct `AnyElement.requestLayout(_:pass:)` caller (a custom `Button`/`Toggle` style's label, the strips) still owns its id: no level, no key.
- A legacy `Self`-returning decoration (`Stack.background`) is not a type change (211); the swap's callback order is appear-then-disappear (212).

## 4. Mutations (applied from the committed tree by `scratchpad/mut/run.py`, restored from the saved original; names are the tests that reddened; the filter was `AnyElementReset|ExplicitIdentityTests|IdentityTests|StateFirstValue|PipelineTests|OpenURL|ConditionalIdentity|LifecycleTests|TaskModifier|ToolbarStrip|MenuBarStrip|ScopeForward|FocusState` under the default build system; a parameterised test's arm is shown in brackets where the log separates it)

| mutation (spelling) | reddened |
|---|---|
| M1 the level removed: `contentID(under:)` returns `id` (also the spelling of the plan's M7 focus, M9 task, M10 animation mutants) | `anAnyElementSwapReadsTheNewTypesOwnValue` [both], `anAnyElementSwapBackStartsFresh` [both], `differingGenericsAreDifferentTypes`, `aContainerOfAnotherTypeResetsItsDescendants`, `aNestedAnyElementResetsOnlyWhatChanged` [inner, outer], `aSwapRunsDisappearAndAppearOnce`, `aSwapCancelsTheOldTaskAndStartsTheNew`, `aSwapResetsAScrollOffset`, `aFocusedElementLosesFocusInTheSwapFrameAndDoesNotGetItBack`, `aSwapUnderAnAnimationIsInstant`, `aGraftedPositionStillResetsWhenItSwaps`, `aSwapUnderAnEquatableParentDrawsTheNewType`, `aSwappedBackEquatableChildStartsCold`, `aSteadyErasedPositionCostsOneNameAndNoScan`, `aDirectRequestLayoutMintsNoLevel` (its control arm), `anOnOpenURLOnAnErasedElementIsOwnedByTheScopesOwnId`, `everyNamingSiteStartsAReturningNameFresh` |
| M2 `noteNamed(contentID, at: 0)` deleted (**the M15 shape**, also the plan's M11 and M7) | `anAnyElementSwapBackStartsFresh` [a-written, b-written], `aFocusedElementLosesFocusInTheSwapFrameAndDoesNotGetItBack`, `aGraftedPositionStillResetsWhenItSwaps`, `aSwapRunsDisappearAndAppearOnce`, `aSteadyErasedPositionCostsOneNameAndNoScan`, `everyNamingSiteStartsAReturningNameFresh`. **Not reddened: `anAnyElementSwapReadsTheNewTypesOwnValue`**: the keyed level alone gives the first swap right, which is why the swap-back arm exists |
| M3 the key from a per-instance counter (also the plan's M16, and the "always departing" mutant M18) | `theSameWrappedTypeKeepsItsState`, `aSameTypeRebuildKeepsItsInnerRecord`, `aSteadyErasedPositionCostsOneNameAndNoScan`, `stateInsideAnAnyElementPersistsAcrossFrames`, `twoErasedSiblingsDoNotShareOneStateEntry`, `aFocusStateSurvivesInsideAComponentAndAnAnyElement`, `aDrawnToolbarControlIsAnOrdinaryControl` and most of M1's set |
| M4 the key from `String(describing: E.self)` cut at `<` | `differingGenericsAreDifferentTypes` (and every `Stack<..>` swap, all collapsing to `Stack`) |
| M5 the inner entry skips the level (the parent is already an `$erased` level) | `aNestedAnyElementResetsOnlyWhatChanged` [inner] only (the `outer` arm is the control that stays green) |
| M6 the `departedRoots.contains(id)` conjunct of `resetQueuedEntries` removed | `aSwapResetsAScrollOffset` (**first run green**: the test only swapped to a different type, whose level is a different id; the arm that swaps back was added, then this), `anIDThatReturnsToAnEarlierNameStartsFresh`, `aShrinkingForLoopLeavesTheTrailingSiblingsStateAlone` |
| M8b `retainsDepartedValues` forced false | `aSwapRunsDisappearAndAppearOnce`, `anAnyElementSwapBackStartsFresh` [a-written] and eight existing lifecycle tests (`aGhostParkedOnDisappearReadsTheSeededInstance`, `onDisappearReadsItsOwnStateAsItWasLastFrame`, ...) |
| M12 `recordElementBounds` taken under the level (the group entry's own line; the first spelling hit `Element`'s default and did not compile) | `aNamedElementKeepsItsNameThroughAScopeWhenErased` only: **`aScrollToReachesANamedElementInAnAnyElement` stays green**, a characterization (its comment says so) |
| M13b the level minted in `AnyElement`'s three direct methods (M13, in `requestLayout` alone, left `aDirectRequestLayoutMintsNoLevel` green: the hitboxes register in prepaint under the caller's id) | `aDirectRequestLayoutMintsNoLevel`, `anOnOpenURLOnAnErasedElementIsOwnedByTheScopesOwnId`, `twoErasedSiblingsDoNotShareOneStateEntry` (M13 alone: `aFocusStateSurvivesInsideAComponentAndAnAnyElement`, `aFocusedElementLosesFocusInTheSwapFrameAndDoesNotGetItBack`, `stateInsideAnAnyElementIsReboundForPrepaintAndPaint`, `anOnOpenURL...`, `twoErasedSiblings...`) |
| M14 `!entry.observedChange` removed from `graftRecord` | **nothing**, in the filter above and in `Retained|Graft|AnyElementReset|StateFirstValue|EquatableComponent|ContentMemo`: the conjunct is redundant behind `old.contentSerial == entry.serial` and the memo's `!entry.stale` (a pre-existing unpinned conjunct, not a gap of this change; no fixture of this branch separates it) |
| M14c `old.contentSerial == entry.serial, graft.contentSerial == entry.serial` removed from `graftRecord` | `aGraftedPositionStillResetsWhenItSwaps` |
| M14d `!entry.stale` removed from the memo's skip decision | `aGraftedPositionStillResetsWhenItSwaps`, `aSwapUnderAnEquatableParentDrawsTheNewType` |
| M15 `case .named` in `Frame.reapply` a no-op | `aGraftedPositionStillResetsWhenItSwaps` only (**the plan's stop condition for test 15 did not fire**) |
| M17 `ContentMemoStore.endFrame` keeps untouched entries | `aSwappedBackEquatableChildStartsCold` |
| M18 `previous != id` dropped from `noteNamed` | **nothing: an equivalent mutant**, because a re-noted id is in `producedNames` and the reset skips it; M3 is the spelling that makes the name depart every build |
| M19 `TextLeafKey` drops its string | `anEqualShapeSwapMeasuresTheNewTypesText` (**first fixture green**: `Stack`/`Row` differ in the tree's shape, so the signature differed; two layout-transparent components of one shape were used) |
| M20 the key also hashing `String(describing: box)` | `aLegacyDecorationIsNotATypeChangeUnderAnAnyElement` [background] (and, with the whole description in the key, most others) |

**The `ElementBuilder.swift` mutation, re-run** (`buildExpression<E: Element>(_:) -> AnyElement` and `buildExpression(_ e: AnyElement) -> AnyElement` added to `ElementBuilder`): it **no longer builds** (`Sources/MetalUI/PullDownMenu.swift:45: cannot convert value of type 'Label' to expected argument type 'AnyElement'`), so the three type-level tests are not reddened by it any more; the compiler is the guard. The comment's old measurement is marked stale at the line (`ElementBuilder.swift`, `AnyElement.swift` header).

## 5. Counts and checks

`swift package clean`, `swift build --build-system native --build-tests`, `swift test --build-system native --no-parallel`, unfiltered, 2026-11-03: **`Test run with 5017 tests in 14 suites passed after 285.198 seconds`** (0 failures; record 199 read 4997, this branch adds 20 test cases); `FR-J no-argument frame: succeeded=true` (guards ran). The first unfiltered run of this branch read 5017 with one failure,
`aBehaviourWordHasAPinOnItsLine`: the guide's new divergence-211 line had no pin; fixed by naming `aLegacyDecorationIsNotATypeChangeUnderAnAnyElement` on the line (the caution sentence carries `anAnyElementSwapBackStartsFresh`). The counts line of `CLAUDE.md` is not replaced (the batch re-takes it once). `zsh docs/probes/record-05-check.sh`, `closeout-inventory-check.sh` and
`closeout-undocumented.sh` print nothing.

**Verify modes**, filter `Retained|Graft|StateFirstValue|LifecycleTests|StateTableTests|TombstoneTests|OccurrenceIdentity|ContentMemo|Equatable|EnvironmentEpoch|EnvironmentReading|IdentityTests|ConditionalIdentity|AnyElementReset` under `--build-system native --no-parallel`: `METALUI_VERIFY_RETAINED=1` **441 tests in 9 suites passed (74.088 s)**; `METALUI_VERIFY_LAYOUT_MEMO=1` **441 tests in 9 suites passed (98.257 s)**.
`METALUI_RUN_100K_LIST_TEST=1 ... --filter aListsWorkIsTheSameFor100kRowsAsFor500` passed (16.351 s).

**Not run / not measured:** pixels (the session was locked, section 0): whether SwiftUI cross-fades a swap on screen (`AV6a`, `AV6b`) and a mid-flight animation separated on a swap back (`AV6c`); `Backends/SDL` tests and the Windows/Linux CI jobs (no source there changed; both new test files keep `import Observation` and the first is `#if canImport(Darwin)`); a human look (there is none). The plan's two carried sites (`PanelBackgroundContent`, a style body under an opened existential) were not probed (`ER-B`).
