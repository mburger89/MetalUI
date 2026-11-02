# 192 - `DropDelegate` (`DE-A`..`DE-J`)

2026-11-02, branch `feat/drop-delegate` from master `4026f5ab`; round-3 item R3-10 item 5. Rulings:
`docs/superpowers/2026-11-01-drop-delegate-decisions.md`. Rule: `docs/rules/input-focus.md` ("Drag and drop"). Records 186-191 are held by open PRs
(191 by `feat/layout-direction`, prefix `LD`, divergence 1045).

## 1. What was there

`DN-A` item 2 left `DropDelegate` and `.onDrop(of:delegate:)` unbuilt because their payload is `NSItemProvider`, Apple-only. `PasteButton` had since stood
`DropItem` in for it (`CP-B`, `CP-D`), so the reason was gone. Nothing of `DropOperation`, `DropProposal` or `DropInfo` existed, and `PlatformWindow` had no way to
tell the platform what a drop would do (AppKit answered `.copy` or none).

## 2. The probe

`docs/probes/swiftui-drop-delegate.swift` (group R's fake `NSDraggingInfo`; run with `/usr/bin/swift`, twice, 27 lines byte-identical, exit 0, stderr empty). Every
value the plan recorded came out the same (D0 `[V,E,U]` then `[U]` then `[U,P]`; D1 none with only `V`; D3 move even for a copy-only mask; D4 and D5 none; D7
`perf=false`; D8 two providers; D9 copy; F1 none and silent against F1b copy; F2 `[V]` then `[X]`; F4 no update after cancel; F5 move then nil is copy; F6, F7; F8 only
`B`; F9 only the delegate; F10 only the `dropDestination`). One difference of form: D1 run with a drop step shows `[U,P]` after the refusal, the fake's artifact (it always
calls prepare and perform); MetalUI performs nothing there (`DE-E`). Two readings rest on the fake alone (F5, F2) and say so in `DE-B`, `DE-D`.

## 3. Design

`DropDelegate.swift` (the protocol with four defaults, `DropOperation`, `DropProposal`, `DropInfo` with an internal initialiser, both `onDrop(of:delegate:)` overloads).
`DropDestinationTarget` gains an optional `delegate` (class box, `IX-N`); `onDrop` writes the same `Handlers.dropDestination`. `DropTargetState` gains the last point and
items and a delegate record (validated, cancelled, operation); `Window.retarget`/`untarget`/`deliver` run the delegate (`DE-B`..`DE-E`). `PlatformWindow.setDropOperation(_:)`
(defaultless) and `PlatformDropOperation` carry the answer to the platform: AppKit's `MetalHostView` stores it and answers `.move`, `.copy` or none; SDL ignores it; the headless
window records it (`HT-X` 1). Demo: three delegate wells (copy, move, forbidden) in `DragAndDropDemo.swift`.

**1057 outcome: measured, fixed, not a divergence.** `theOuterOfTwoProposalDropWrappersWins` was red before the fix (the inner delegate `A` ran, `AV,AE,AU`; the inner
`dropDestination`'s `isTargeted` ran): wrappers register outermost-first and the later region ranks higher. A `DropDestinationModifier` now tells a `DropDestinationWrapping`
content directly inside it to register nothing; the fix serves `dropDestination` as well. A wrapper over a different element that registers its own destination at other bounds
is unaffected (deepest wins, `DN-F`).

## 4. Source breaks

Every `PlatformWindow` conformer outside the package adds `func setDropOperation(_ operation: PlatformDropOperation) {}` (`docs/migration.md`). New public enum crossing a module
boundary: `swift package clean` after pulling. No existing behaviour changed except 1057's (two chained drop wrappers).

## 5. Tests

`DropDelegateTests.swift` (16), `DropDelegateHeadlessTests.swift` (1), one AppKit test in `AppKitDragAndDropTests.swift`, three guards in `DragAndDropCompileGuards.swift`
(`aPlatformWindowWithoutSetDropOperationDoesNotCompile`, `aDropDelegateNeedsOnlyPerformDrop`, `dropInfoHasNoPublicInitializer`), a row in `OuterModifierMatrixTests.swift`. Every
`PlatformWindow` fake and compile-guard fixture gained `setDropOperation`. `Backends/SDL` builds (`swift build` with the AccessKit flags); its tests were not run.

**Counts** (2026-11-02, `feat/drop-delegate` after `swift package clean`, `--build-system native --build-tests` and an unfiltered `--no-parallel` run): **4885 tests in 14 suites passed** (`✔ Test run with 4885 tests in 14 suites passed after 270.519 seconds.`, exit 0, 0 failures, 0 issues; the log tail was read, not truncated). `FR-J no-argument frame: succeeded=true` printed. The three new guards printed `DE-H member required: without succeeded=false with succeeded=true`, `DE-A delegate: minimal succeeded=true missing succeeded=false`, `DE-F DropInfo: made succeeded=false read succeeded=true`. `closeout-inventory-check.sh` and `closeout-undocumented.sh` print nothing. The 14th suite is not this change's (no suite was added by it); the previous line read 13 at `b83efde2`.

## 6. Mutations

Each applied to the spelling named, run against the new tests plus the existing drag-and-drop suites (`--filter` over 25 names), restored with the file copy. Tests named, not counted.

| Mutation (spelling) | Reddened |
|---|---|
| same-id retarget skips updateDelegate (`DragSession.swift` `retarget`, same-id branch) | `aDelegateGetsValidateEnterUpdateThenUpdatePerMoveThenUpdatePerform`, `dropInfoLocationIsLocalInEveryCallback`, `eachProposalMapsToItsPlatformOperation` |
| updateDelegate before dropEntered (new target) (`retarget`, new-target branch) | `aDelegateGetsValidateEnterUpdateThenUpdatePerMoveThenUpdatePerform`, `cancelStopsUpdatesUntilExitAndReEntryResets`, `dropInfoLocationIsLocalInEveryCallback`, `leavingSendsOnlyDropExitedBeforeTheNextDestinationsValidate`, `theOuterOfTwoDropModifiersOnOneElementWins`, `theOuterOfTwoProposalDropWrappersWins` |
| untarget skips a delegate (`untarget`) | `aForbiddenCancelledOrInvalidReleasePerformsNothingAndExits`, `cancelStopsUpdatesUntilExitAndReEntryResets`, `leavingSendsOnlyDropExitedBeforeTheNextDestinationsValidate`, `validateFalseSuppressesEnterUpdateAndPerformButNotExit` |
| validateDrop result ignored (`retarget`, the validate result) | `aForbiddenCancelledOrInvalidReleasePerformsNothingAndExits`, `validateFalseSuppressesEnterUpdateAndPerformButNotExit` |
| dropExited gated on validated (`untarget`) | `aForbiddenCancelledOrInvalidReleasePerformsNothingAndExits`, `validateFalseSuppressesEnterUpdateAndPerformButNotExit` |
| accepts always true (`DropDestinationTarget.accepts` (`DragAndDrop.swift`)) | `aDelegateIgnoresItemsNotConformingToItsTypes` |
| nil proposal keeps the last operation (`updateDelegate`) | `eachProposalMapsToItsPlatformOperation` |
| forbidden maps to copy (`updateDelegate`) | `aForbiddenCancelledOrInvalidReleasePerformsNothingAndExits`, `aMoveProposalAnswersMoveFromEnteredAndUpdated`, `eachProposalMapsToItsPlatformOperation` |
| cancel does not set cancelled (`updateDelegate`) | `cancelStopsUpdatesUntilExitAndReEntryResets` |
| performDrop called regardless of state (`deliver`) | `aForbiddenCancelledOrInvalidReleasePerformsNothingAndExits`, `validateFalseSuppressesEnterUpdateAndPerformButNotExit` |
| performDrop answer replaced by true (`deliver`) | `performDropsBoolIsWhatThePlatformIsTold` |
| untarget before performDrop (`deliver`) | `aDelegateGetsValidateEnterUpdateThenUpdatePerMoveThenUpdatePerform`, `dropInfoLocationIsLocalInEveryCallback`, `performDropSendsNoDropExited` |
| DropInfo.location is the window point (`dropInfo(for:)`) | `dropInfoLocationIsLocalInEveryCallback` |
| itemProviders match by exact identifier (`DropInfo.itemProviders`) | `dropInfoMatchesByConformance`, `sdlHoverIsOptimisticAndPerformSeesItems` |
| hasItemsConforming false on nil items (`DropInfo.hasItemsConforming`) | `sdlHoverIsOptimisticAndPerformSeesItems` |
| onDrop(of:delegate:) does not replace an outer (StyledElement) (`StyledElement.onDrop(of:delegate:)`) | `theOuterOfTwoDropModifiersOnOneElementWins` |
| outer drop wrapper does not silence the inner (1057) (`DropDestinationModifier.prepaint`) | `theOuterOfTwoProposalDropWrappersWins` |
| delegate region registered outside the enabled/hidden gate (`Frame.registerHandlers` gate) | `aDisabledOrHiddenDelegateIsNeverValidated` |
| transferable destination starts as move (`DropTargetState.operation` default) | `transferableDestinationsStillReportCopyOrNone` |
| AppKit ignores the stored operation (`MetalHostView.operation(accepting:)`) | `aMoveProposalAnswersMoveFromEnteredAndUpdated` |
| headless setDropOperation does not append (`HeadlessPlatformWindow.setDropOperation`) | `theHeadlessWindowRecordsEachReportedOperation` |
| protocol-extension default for setDropOperation (`Platform.swift` (extension default)) | `aPlatformWindowWithoutSetDropOperationDoesNotCompile` |
| performDrop default in DropDelegate extension (`DropDelegate` extension (default)) | `aDropDelegateNeedsOnlyPerformDrop` |
| DropInfo init public (`DropInfo.init`) | `dropInfoHasNoPublicInitializer` |
| onDrop(of:delegate:) registers nothing (matrix row) (`StyledElement.onDrop(of:delegate:)`) | `aDelegateGetsValidateEnterUpdateThenUpdatePerMoveThenUpdatePerform`, `aDelegateIgnoresItemsNotConformingToItsTypes`, `aForbiddenCancelledOrInvalidReleasePerformsNothingAndExits`, `aMoveProposalAnswersMoveFromEnteredAndUpdated`, `cancelStopsUpdatesUntilExitAndReEntryResets`, `dropInfoLocationIsLocalInEveryCallback`, `dropInfoMatchesByConformance`, `eachProposalMapsToItsPlatformOperation`, `everyOuterModifierIsTheKindTheMatrixSaysUnderTheProposalAuthority`, `leavingSendsOnlyDropExitedBeforeTheNextDestinationsValidate`, `performDropsBoolIsWhatThePlatformIsTold`, `sdlHoverIsOptimisticAndPerformSeesItems`, `theOuterOfTwoDropModifiersOnOneElementWins`, `validateFalseSuppressesEnterUpdateAndPerformButNotExit` |

`M10` first ran as an inverted guard (it performed nothing) and reddened the wrong tests; the table is its re-run with the guard disabled. Tests written after the code, so "red before"
is shown by these mutations (and 1057's by the pre-fix run).

## 7. Carried

`dropUpdated` per `mouseDragged` and none while stationary (`wantsPeriodicDraggingUpdates` is false) is unmeasured for delegates; the delegate a callback runs is the one from the last
drawn frame; `F5` and `F2` rest on the fake harness; whether Finder honours `.move` (human check `DE1`); `AnyElement` around a `.hidden()` delegate well still registered a region in a
scratch test (not investigated, not part of this feature); human check group DE (unrun).
