# 178 - Gesture composition: `sequenced(before:)`, a custom `Gesture` body, composed `updating`, drag velocity (`GE-`)

2026-10-31, branch `feat/gesture-composition` from master `28a819e9`; round-3 item R3-5. Decisions:
[`superpowers/2026-10-31-gesture-composition-decisions.md`](../superpowers/2026-10-31-gesture-composition-decisions.md) (`GE-A`...`GE-I`, next `GE-J`).
Probe: `docs/probes/swiftui-gesture-composition.swift` (arms `S1`-`S7b`, `X1`-`X2b`, `C1`-`C5`, `D0`-`D15`, output in its header, screen unlocked).

## What was built

- `Gesture.sequenced(before:)` -> `SequenceGesture<First, Second>` with `Value` = `.first(First.Value)` / `.second(First.Value, Second.Value?)`. The arena has a `.sequence` node:
  the second member's leaves are gated until the first ended, a failed first fails the sequence, and a drag in the second member starts at the **first pointer event after the gate**
  (probes `S1`, `S2`, `S5b`), the gate-opening event being replayed to it (a tap that ends at its release lets a minimum-0 drag end with that release, `S7`). `GE-B`.
- A custom `Gesture` is a struct with `var body: some Gesture` (`GE-A`): `Gesture` gained `Body`/`body` (`Never: Gesture`, default `Value = Body.Value`); `_recognizers()` left the
  protocol (an SPI default is invisible to an outside conformer), the arena asks `recognizerNode(of:)`, which dispatches on an internal `PrimitiveGesture` and otherwise recurses into
  `body`. The old guard `anOutsideTypeCannotConformToGesture` is replaced by `anOutsideTypeCanConformToGestureThroughABody` and `anOutsideTypeCannotDescribeRecognizersItself`.
- `onChanged`, `onEnded` and `updating(_:body:)` on every gesture (`GE-E`): `_ChangedGesture`, `_EndedGesture`, `GestureStateGesture`, tapping the base's node. The composites
  (`SequenceGesture`, `ExclusiveGesture`, `SimultaneousGesture`) are `.hooked(node, CompositeHooks)`; they report their value **once per event** (an arena `flush` callback after the event's leaf
  callbacks), then on the node's end run the updating resets, `onEnded` and the state reset (`GE-C`).
- `MouseEvent.timestamp: Double?` (AppKit `NSEvent.timestamp`, SDL's event time, the harness `now`; `GE-D`) and `DragGesture.Value.time` (`Date(timeIntervalSinceReferenceDate:)` of it), `velocity`,
  `predictedEndLocation`, `predictedEndTranslation` (`GE-F`): velocity = 0.75 x the previous interval's speed + 0.25 x this one's over event stamps, prediction = a quarter second of it.
- Carried: `GestureMask`/`including:` (`GE-H`), a composite's `onCancelled`, velocity on `MagnifyGesture`/`RotateGesture`, a Tap/LongPress **second** member's click counting (unprobed).

## Divergences

**925** (new, 179 live): an exclusive composite's `updating` ran once more at the first move in the probe (`X2`); MetalUI runs it once. The `CI-A` "not offered" rows narrowed:
`sequenced`, a custom body, composed `updating`, drag `time`/`velocity`/`predictedEnd*` are built; `GestureMask` stays.

## Tests (`Tests/MetalUITestingTests/GestureCompositionTests.swift`, 22; guards in `Tests/MetalUITests/GestureCompileGuards.swift`)

Written before the implementation: the first `swift build --build-tests` failed on `cannot find type 'SequenceGesture' in scope` and `type 'HoldGesture' does not conform to protocol 'Gesture'`
(log kept in the lane's scratch, not in the repo). The first run of the finished implementation passed all 22; the mutation table below is therefore the evidence the tests can fail.

## Mutations (each applied to the committed source `d3d5aac2`, `GestureCompositionTests` run, restored from a backup copy)

| # | mutation (declaration, spelling) | tests reddened |
|---|---|---|
| M1 | `DragGesture.Value.predictedEnd*`: `velocity / 4` -> `/ 5` | `aSteadyDragReportsItsVelocityAndAQuarterSecondPrediction` |
| M2 | `ArenaLeaf.velocity`: the 0.75/0.25 weights swapped | `theVelocityIsAThreeToOneBlendOfTheLastTwoIntervals`, `aLateReleaseBlendsAZeroIntervalAndDoesNotDecay`, `movesBeforeTheMinimumDistanceFeedTheEstimator`, `anEventAtTheSameInstantReplacesTheLastSample` |
| M3 | `ArenaLeaf.sample`: `time <= last.time` -> `<` (append instead of replace) | `anEventAtTheSameInstantReplacesTheLastSample` |
| M4 | `ArenaLeaf.isGated` always `false` | `aLongPressThenDragReportsFirstThenSecond...`, `aReleaseRightAfterTheLongPressEndsOnlyADragWithNoMinimum`, `aTapThenADragEndsOnTheReleaseThatEndedTheTap`, `updatingOnASequenceRunsForEachValueAndResetsAtTheEnd`, `aCustomGestureWhoseBodyIsASequenceReportsTheSequenceValue` |
| M5 | `rebase`: a gated drag no longer awaits its first event | the five above + `theDragMinimumIsMeasuredFromTheFirstEventAfterTheLongPress`, `aSequenceThatFailsOrEndsWithoutMovingStillResetsItsState` |
| M6 | `openGates`: the opening event is not replayed (`switch Optional.none`) | `aTapThenADragEndsOnTheReleaseThatEndedTheTap` only |
| M7 | `settleComposites`: `hooks.finishes` not queued | `updatingOnASequenceRunsForEachValueAndResetsAtTheEnd`, `aSequenceThatFailsOrEndsWithoutMovingStillResetsItsState`, `aSimultaneousCompositeReportsBothLatestValuesOncePerEvent`, `anExclusiveCompositeReportsTheWinningMembersValue` |
| M8 | `SimultaneousGesture` flush never clears `dirty` | `aSimultaneousCompositeReportsBothLatestValuesOncePerEvent` |
| M9 | `recognizerNode(of:)`: a non-primitive's `body` ignored | `aCustomGestureRunsItsBodyAndTakesOnEnded`, `updatingOnACustomGestureWrapsItsBodyAndResets`, `aCustomGestureWhoseBodyIsASequenceReportsTheSequenceValue`, `aCustomGestureComposesWithTheCombinators` |
| M10 | `Window`: the move's `mouse.timestamp` ignored (`lastGestureTime`) | `timeFollowsTheEventTimestampsNotTheWallClock`, `aSteadyDragReportsItsVelocityAndAQuarterSecondPrediction`, `theVelocityIsAThreeToOneBlendOfTheLastTwoIntervals`, `theVelocityIsPerAxisAndSigned`, `aLateReleaseBlendsAZeroIntervalAndDoesNotDecay`, `movesBeforeTheMinimumDistanceFeedTheEstimator`, `anEventAtTheSameInstantReplacesTheLastSample` |
| M11 | `applyRelease`: `endOnRelease = true` -> `false` | `aReleaseRightAfterTheLongPressEndsOnlyADragWithNoMinimum`, `aTapThenADragEndsOnTheReleaseThatEndedTheTap`, `aSequenceThatFailsOrEndsWithoutMovingStillResetsItsState` |
| M12 | `ArenaLeaf.velocity`: vertical axis negated | `theVelocityIsPerAxisAndSigned` |
| M13 | `cancelBehindEndedMembers`: a failed first member no longer fails the second's leaves | **green on arrival** (the sequence node is `.failed` through its first member, the leaves are only left `.possible`, so the arena outlives the press and the next press is read as continuing); `aFailedFirstGestureFailsTheSequence` gained a second attempt on the same chip and now reddens |
| M14 | `settleComposites`: the node's `ended` hook not queued | `aLongPressThenDragReportsFirstThenSecond...`, `theDragMinimumIsMeasuredFromTheFirstEventAfterTheLongPress`, `aReleaseRightAfterTheLongPressEndsOnlyADragWithNoMinimum`, `aSequenceThatFailsOrEndsWithoutMovingStillResetsItsState`, `aTapThenADragEndsOnTheReleaseThatEndedTheTap`, `aSimultaneousCompositeReportsBothLatestValuesOncePerEvent`, `anExclusiveCompositeReportsTheWinningMembersValue`, `aCustomGestureWhoseBodyIsASequenceReportsTheSequenceValue` |
| M15 | `applyMove`: a drag samples only once started | `movesBeforeTheMinimumDistanceFeedTheEstimator` |
| M16 | resetting each composite's state box at arena formation | **green, and the line was removed** (a composite settles on end, failure and cancel, and its flush is queued in the same batch as the callbacks that dirty it, so nothing stale can reach a later press); `GE-C` no longer claims it |

Mutations M1-M15 ran as one sequence over the committed source `d3d5aac2` (`swift test --no-parallel --skip AppKitPresentationTests --filter GestureCompositionTests`, default build system), each file
restored from a backup copy; M13 was re-run after its test was strengthened. Guard `anOutsideTypeCanConformToGestureThroughABody`: `Gesture.sequenced(before:)` made internal -> positive arm fails (`'sequenced' is inaccessible`), both arms false, the guard's separating `#require` reddens (native build, then restored). `GestureStateGesture` made internal does not build (a public method returns it), so that spelling is not a mutation.


## Counts

2026-10-31, `feat/gesture-composition` at the commit below, `--build-system native`: `swift package clean`, native build, then `swift test --build-system native --no-parallel --skip AppKitPresentationTests`.
The clean run read **4657 tests in 12 suites, 3 issues** (all three were guards the change legitimately moved, fixed in the follow-up commit: `GE.1`'s negative arm compiled because a conformance with an unrelated `body: Int` falls back to the
default `Body == Never`; `GS.2`'s negative arm used `updating` on a composite, now offered; `WD 3.2`'s callbacks arm used the generic `onChanged` on `WindowDragGesture`, now accepted). After the fixes, an incremental
native rebuild and run read **`Test run with 4657 tests in 12 suites passed`** (22 of them `GestureCompositionTests`; the root count before this lane was ~4635 by CLAUDE.md's line, 4657 includes it and the two replaced guards), and
`FR-J no-argument frame: succeeded=true` printed; `GESTURE GUARD GE.1 positive: succeeded=true / negative: succeeded=false`. `AppKitPresentationTests` skipped (locked screen). The default build system ran the same suite green earlier (no guards run there).
`closeout-inventory-check.sh` and `closeout-undocumented.sh` print nothing; `Backends/SDL` `swift build` completes.

## Windows / Linux

The composites add no loop-in-`Component` shape and no new protocol-heavy generic recursion beyond `recognizerNode(of:)` (recursion through `body` only). `Backends/SDL` builds with the `timestamp:` arguments.
Human checks: group `GE` in `docs/verification/human-checks.md`.
