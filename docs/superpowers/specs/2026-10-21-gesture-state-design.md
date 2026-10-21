# `@GestureState` and `phaseAnimator` — design

Item G1, branch `feat/gesture-state` from `1bdead8d`, record §135 (Record phase). Rulings: [`../2026-10-21-gesture-state-decisions.md`](../2026-10-21-gesture-state-decisions.md)
(`GS-A`…`GS-N`). Probe: `docs/probes/swiftui-gesture-state.swift` (output in its header). SwiftUI is the authority; gpui has no counterpart (decisions header).

## 1. Inventory — what the item touches today

- `Sources/MetalUI/Gesture.swift` (1316 lines): the closed `Gesture` protocol, `GestureLeaf` (callbacks by kind), `GestureArena` (pure; `fail(_:)` and `act(_:)` are the only
  places a leaf leaves `.possible`; `cancel()`/`abandon()` return callbacks), `TapGesture`/`LongPressGesture`/`DragGesture`; `SpatialGestures.swift`: `SpatialTapGesture`,
  `MagnifyGesture`, `RotateGesture`. Its header and `onCancelled`'s doc say `@GestureState` is "not offered".
- `Sources/MetalUI/Window.swift` `runGestureCallbacks` (2046) runs each callback under `StateDispatch.dispatching(to: owner)`; `cancelLiveArenas`, `cancelPinchArena`,
  `dispatchButtonArena`, `buttonPress` call `arena.cancel()`.
- `State.swift`/`StateReflection.swift`: `State.Box` (`resolvedSlot`, `occurrences`), `BindableState`, `StateBinder.bind` (`$state<n>` per `Mirror` ordinal; `stateOrdinals`
  feed the content memo); `StateTable.write/peek` (taint of the retained, prepaint and memo-journal logs).
- `KeyframeAnimator.swift` + `AnimationStore.swift` (`withKeyframeScope`, `keyframeDepth`, `value(at:as:)`/`set`) + `AnimationScope.swift` (`TransactionScope`,
  `Frame.withTransactionScope`) + `Animation.swift` (`Curve`, `.duration`/`.spring`): the machinery `phaseAnimator` reuses. `Animation` has no public duration accessor.
- Demos: `Sources/MetalUIDemoContent/InputFollowupsDemo.swift`, `LooksDemo.swift` (`KeyframesDemo`). Guides: `docs/guides/input.md`, `drawing-and-gpu.md`.
- Tests that must not move: `theSevenRetentionSlotsAreMutuallyDistinct`, `everyStateWriteSiteIsClassified`, `Handlers` nineteen members (`HandlerShape`,
  `HandlerFingerprint`: **no `Handlers` change**), the gesture arena pins (`H`, `IX`, `IF`, `GC`), `keyframeAnimator*`, the fourteen images.

## 2. Public API (class A unless noted; every declaration owes a doc comment and an inventory row)

```swift
@propertyWrapper @MainActor public struct GestureState<Value> {
    public init(wrappedValue: Value)
    public init(initialValue: Value)
    public init(wrappedValue: Value, resetTransaction: Transaction)
    public init(initialValue: Value, resetTransaction: Transaction)
    public init(wrappedValue: Value, reset: @escaping (Value, inout Transaction) -> Void)
    public init(initialValue: Value, reset: @escaping (Value, inout Transaction) -> Void)
    public var wrappedValue: Value { get }            // get-only
    public var projectedValue: GestureState<Value> { get }
}
extension GestureState where Value: ExpressibleByNilLiteral {
    public init(resetTransaction: Transaction = Transaction())
    public init(reset: @escaping (Value, inout Transaction) -> Void)
}
// on DragGesture, LongPressGesture, MagnifyGesture, RotateGesture, TapGesture, SpatialTapGesture (the two taps: stored, never run):
public func updating<State>(_ state: GestureState<State>,
                            body: @escaping @MainActor (Value, inout State, inout Transaction) -> Void) -> DragGesture // the receiver's type

extension ElementGroup {   // both vocabularies: ProposalElementGroup receivers keep proposal content (as keyframeAnimator)
    public func phaseAnimator<Phase: Equatable, Content: ElementGroup>(_ phases: some Sequence<Phase>, trigger: some Equatable,
        @ElementBuilder content: @escaping (Self, Phase) -> Content, animation: @escaping (Phase) -> Animation? = { _ in .default }) -> PhaseAnimator<Phase, Content>
    public func phaseAnimator<Phase: Equatable, Content: ElementGroup>(_ phases: some Sequence<Phase>,
        @ElementBuilder content: @escaping (Self, Phase) -> Content, animation: @escaping (Phase) -> Animation? = { _ in .default }) -> PhaseAnimator<Phase, Content>
}
public struct PhaseAnimator<Phase: Equatable, Content: ElementGroup>: ElementGroup {   // + ProposalElementGroup where Content: ProposalElementGroup
    public init(_ phases: some Sequence<Phase>, trigger: some Equatable, @ElementBuilder content: @escaping (Phase) -> Content, animation: ... = { _ in .default })
    public init(_ phases: some Sequence<Phase>, @ElementBuilder content: @escaping (Phase) -> Content, animation: ... = { _ in .default })
}
```

Internal (not public): `GestureLeaf.finished`/`updates`, `ArenaLeaf.owesFinish`, `GestureStateBox` (`dirty`, `batch`, `base`), `GestureStateBatch.current`, `Animation.nominalDuration`,
`PhaseRecord`. **Class and rows.** `GestureState`/`updating`: class A (SwiftUI spelling; the returned type is the receiver's, `GS-B`); `PhaseAnimator`/`phaseAnimator`: class A
with divergence 169's content-closure note. **Divergence 645** (`GS-D`) is the only new label. Migration note: none (no protocol requirement added; `GestureLeaf` is internal).

## 3. Lanes (two; disjoint files)

**Lane 1 — `@GestureState` (`GS-A`…`GS-F`).** Owns: new `Sources/MetalUI/GestureState.swift`; edits to `Gesture.swift`, `SpatialGestures.swift`, `Window.swift`
(`runGestureCallbacks` batch counter, arena-discard audit only); tests `Tests/MetalUITestingTests/GestureStateTests.swift` (portable, `TestWindow`), a macOS-only
`Tests/MetalUITests/GestureStateWindowTests.swift` for any arm the harness cannot drive (key loss, lost release: `TestWindow` first, fall back only with the reason
in the file header), `Tests/MetalUITests/GestureStateCompileGuards.swift`; demo in `InputFollowupsDemo.swift`; guide `input.md` + `GuideMirrorsGestureState.swift`;
inventory rows for its declarations (own block).
**Lane 2 — `phaseAnimator` (`GS-H`…`GS-K`).** Owns: new `Sources/MetalUI/PhaseAnimator.swift`; edits to `AnimationStore.swift` (none expected: the shared depth) and
`Animation.swift` (`nominalDuration`); tests `Tests/MetalUITestingTests/PhaseAnimatorTests.swift`, `Tests/MetalUITests/PhaseAnimatorCompileGuards.swift`; demo in
`LooksDemo.swift`; guide `drawing-and-gpu.md` + `GuideMirrorsPhase.swift`; inventory rows (own block).
**No shared source file.** Docs are the Record phase's. Lane 1 does not read lane 2's files and vice versa; the one shared surface is `Transaction`/`withTransaction` (read-only).

## 4. Implementation notes

**Lane 1.** (1) `GestureState.swift`: the wrapper over a box shaped as `State.Box` (copy `bind`'s occurrence bookkeeping; `extension GestureState: BindableState`), `wrappedValue`
= `peek ?? initialValue`; `GestureStateBox` as `GS-D`. Update application: `apply(value, body)`: base per batch, copy, `body(value, &copy, &transaction)`, `write(copy)` under `withTransaction`
only when `transaction.animation != nil`, `dirty = true`. Reset: `if dirty { dirty = false; var t = resetTransaction; reset?(current, &t); write(initial) under t if animated }`.
(2) `Gesture.swift`: `GestureLeaf.updates: [(run: @MainActor (Any) -> Void, afterChanged: Bool)]` is wrong-typed per leaf kind, so each concrete gesture stores
`[GestureUpdate<Value>]` (a struct of two closures) and composes it with its `changed` in `_recognizers()` per `GS-E`, plus `leaf.finished` (closure resetting every distinct
state of the leaf). Arena: `ArenaLeaf.owesFinish` set when a change-type callback carrying an update is queued (`act` drag/pinch change, `reportPressing(true)` with `longPressChanged`);
`fail(_:)` and the ended arms of `act` queue `finished` once; `cancel()`/`abandon()` drain `callbacks` after their loops and fail a leaf that `owesFinish`. (3) `Window.runGestureCallbacks`:
`GestureStateBatch.current &+= 1` before the loop. (4) Audit every `gestureArena = nil` / `buttonArena = nil` / `pinchArena = nil` and `endPressForDrag` site: each must come after `cancel()`/
`abandon()` or an end; add the missing call only with a pin naming the path.
**Lane 2.** `PhaseAnimator.swift` mirrors `KeyframeAnimator.swift` section for section: `PhaseRecord { trigger: Any?, index: Int, stepStart: Double, running: Bool }`,
`resolve(record, mode, phases, animation, now) -> (index, record, stepped: Bool, active: Bool)` as a pure static function (`KeyframeAnimator.resolve`'s shape, so the unit tests
call it with literal times), `requestGroupLayout` builds `content(phase)` inside `withKeyframeScope` and `withTransactionScope(txn)` (layout + paint, `TransactionScope`'s
pattern), `requestProposalGroupLayout` the line-for-line copy. `Animation.nominalDuration: Double` (internal): `.duration(_, seconds)` → `max(0, seconds)`, `.spring(duration:, _)` → `duration`.

## 5. Tests (name; red before; the mutation that must redden it)

Every pin counts work or values, never wall time; no test sleeps (`TestWindow.advance(by:)`/`tick()`/`simulateTick`). "Red before" for all of them is "does not compile / no such
symbol" unless a different reason is given. Mutations are run on the full unfiltered suite after a commit, restored from a copy, `git status --short` after each, reddened tests named in the record.

**Lane 1 (`GestureStateTests`, portable).**
1. `aDragUpdatingMovesAViewDuringTheDragAndSnapsBackAtTheRelease` (probe `G1`): the chip's `.offset` follows three moves, reads 0 at the release frame. Mutation: delete `finished`'s queue in `act` (drag arm) → stays dragged.
2. `theResetRunsBeforeOnEndedAndOnChangedReadsTheWrite` (`G8`): onEnded reads 0, onChanged (declared after) reads the new value. Mutation: queue `finished` after the ended callback.
3. `updatingOrderFollowsDeclarationAgainstOnChanged` (`G13`, `G6`): both orders and two updates. Mutation: always run updates first.
4. `aLongPressUpdatingIsTrueFromThePressAndResetsWhenItEndsWhileHeld` (`G3`, `G4`): reset at the matured tick, not the release. Mutation: remove `finished` from the long-press ended arm.
5. `aLongPressThatFailsResetsAtTheFailureNotTheRelease` (`G12`) and `…ReleasedBeforeTheMinimum…` (`G3`). Mutation: remove the queue from `fail(_:)`.
6. `aTapGestureUpdatingCompilesAndNeverRuns` (`G2`, `G5b`, tap and spatial tap). Mutation: wire the tap's ended callback to the update body.
7. `updatingBeginsWithTheFirstRecognizedChange` (`G5`, `minimumDistance: 10`, 3 pt then 20 pt). Mutation: run at the press.
8. `everyCancelPathResetsOnce` (one arm per `IF-F`/`GC-` path: replaced primary press (`abandon`), lost button release, stale button/pinch arena, window close (`cancelLiveArenas`),
   draggable takeover; the reset closure counts calls == 1 per path). Mutation: `cancel()` stops draining `callbacks`; second mutation: `abandon()` likewise.
9. `aDisabledOrRemovedOwnerResetsAtTheReleaseAndNotBefore` (`C2`/`C3`; disabled, then the owner removed while the state lives in a parent). Mutation: run the reset at the disable.
10. `theResetClosureAndTransactionApply` (`G9`–`G11`): default no animation, `resetTransaction` animation seen by a `.transaction` reader at the reset build, `reset:` closure once with the pre-reset value,
    an `updating` body's animation on each update. Mutation: ignore `resetTransaction`; second: park the update's transaction regardless of nil.
11. `twoStatesOnOneGestureAreWrittenInDeclarationOrderAndSeenTogether` (`G6`).
12. `simultaneousWritersStartFromTheEventsCommittedValueAndTheLastWins` (`G7`, `G7d`, `G7e`; **divergence 645 pinned wrong on purpose**: MetalUI's order, so the `G7` outcome is the long press's 100, the SwiftUI value 1 stated in the comment) and `anyWriterEndingResetsTheSharedState` (`G7b`, `G7c`). Mutation: take `base` from the live value every time (breaks 12); remove the dirty guard (breaks the single-reset count).
13. `aGestureStateIsAStateSlotNotAnEighth`: a component with one `@State`, one `@GestureState`: slot names `$state0`, `$state1`; `theSevenRetentionSlotsAreMutuallyDistinct` unmoved. Mutation: give the box its own name.
14. `aGestureStateWriteIsAStateWriteForTheMemoAndRetainedPaths`: an `.equatable()` component reading it re-evaluates per drag event (`contentEvaluations`), is skipped at rest, and the retained window under `METALUI_VERIFY_RETAINED=1`/`METALUI_VERIFY_LAYOUT_MEMO=1` does not trap. Mutation: write through a private store (no version bump) → the memo skips and the view is stale.
15. `anElementValuePlacedTwiceResetsItsOwnOccurrence` (`ID-F`): two chips from one value, each dragged. Mutation: resolve with `slotID` only.
16. Guards (`typecheck`/`typecheckFile` with a plain import; **each mutated red once**): the eight `GestureState` spellings compile for an outside module; `updating` chains with `onChanged`/`onEnded`; `wrappedValue` has no setter (`offset = 1` does not compile); `updating` on a composite does not compile (`GS-B`); `GestureStateBox`/`finished` unreachable.
17. `theGuideSnippetsMirrorGestureState` (the DG-C mirror and doc check).

**Lane 2 (`PhaseAnimatorTests`, portable; `resolve` unit tests on literal times plus window arms).**
1. `aPhaseAnimatorWithNoTriggerShowsTheFirstPhaseThenCyclesForever` (`P1`): phases 0, then 1, 2, 0, 1, 2 at 0.0, 0.4, 0.8 … on the simulated clock (linear 0.4). Mutation: drop the `% count`.
2. `aTriggerChangeRunsPhasesOneToNThenTheFirstAndStops` (`P2`): 1, 2, 0 then rest; `hasActiveAnimations` false and the window idle after. Mutation: end at `n-1` (never returning to `phases[0]`).
3. `noTriggerChangeRunsNothing` (`P3`, separating): no content call beyond the appear's, no active frames. Mutation: step on a build with an unchanged trigger.
4. `aTriggerChangeMidRunRestartsAtPhaseOne` (`P4`). Mutation: continue the old run.
5. `aNilAnimationSnapsItsPhaseAndTheNextStepFollowsOnTheNextFrame` (`P5`): the nil phase's content sees `animation == nil`, the next phase animates from the snapped values. Mutation: treat nil as `.default`.
6. `stepSpacingIsTheAnimationsDuration` (`P6`, `P9`): linear 1.0 → 1.0 s, spring(0.5) → 0.5 s, per-phase mix. Mutation: spacing constant 0.4.
7. `onePhaseRunsNothing` (`P7`), `equalNeighboursStepWithNoWait` (`P8`).
8. `eachPhasesContentIsBuiltUnderItsAnimation` (`GS-J`): the transaction read inside the content equals `animation(phase)` on the step's build and the inherited one on the next. Mutation: use the previous phase's animation.
9. `aScheduledStepDoesNotDriftAndAStalledFrameStepsOnce`: frames at 17 ms: step times 0.4, 0.8 exactly on the schedule; a 2 s gap takes one step. Mutation: `stepStart = now`.
10. `thePhaseAnimatorIsTransparentToIdentityAndStateTable`: adding/removing it moves no `@State` below it; the record is in `AnimationStore` (`$phase<depth>`), no `StateTable` slot. Mutation: allocate a `$state`.
11. `aRemovedPhaseAnimatorStartsAtTheFirstPhaseOnReturn` (sweep).
12. `aPhaseAnimatorKeepsTheDisplayLinkAwakeOnlyWhileRunning`: `noteActiveAnimation` raised while running, `requestAnotherFrame` count 0. Mutation: raise `requestAnotherFrame` instead.
13. `aPhaseAnimatorInsideAnEquatableComponentKeepsStepping` (and under the verify switches). If red today for `keyframeAnimator` too, pin it as is and carry it (`GS-P`: no `Retained*.swift` edit).
14. `aPhaseAnimatorKeepsProposalContentProposal`; guards: a `Self`-returning decoration after it does not compile (`LK-T` item 2), plain-import use compiles; each mutated red once.
15. `reduceMotionDoesNotChangeAPhaseAnimator` (`GS-K`, pinned as MetalUI's choice, unmeasured in SwiftUI).
16. `theGuideSnippetsMirrorPhaseAnimator`.

**Both, at close:** `closeout-inventory-check.sh` and `closeout-undocumented.sh` print nothing; census re-recorded; `swift package clean`, native build (0 `error:`, only SwiftPM's deprecation `warning:`),
unfiltered native run (one summary line, `FR-J no-argument frame: succeeded=true`), the verify-switch run, `swift build --build-tests` on the default build system 0 `warning:`, the fourteen images
0 px (`compare.sh <scratch> 1bdead8d HEAD`), the Linux image (`MetalUITestingTests`, `MetalUILayoutTests`, `MetalUICoreTests`; no `Backends/SDL` file changes, so no SDL package run).

## 6. Demo expectation

`InputFollowupsDemo` (lane 1): a "Drag chip" (`@GestureState var drag: Size`, `.offset`, `.updating($drag)`, a `resetTransaction` of `.easeOut(duration: 0.25)`) that follows the pointer and glides home, and a "Hold" chip
(`LongPressGesture` with `updating` into a `Bool` scaling the chip). `LooksDemo` keyframes row (lane 2): a three-phase pulse (no trigger: opacity 1, 0.4, 0.7 at `.easeInOut(duration: 0.5)`) and a triggered
one beside the existing "Shake" (the shake's counter as trigger, phases `[false, true]`): **no new click target**, so the looks demo's target-counting tests stand. Each section is its own function/`Component`
(`everyProductionTreeBuildsOnAOneMegabyteThread` run). Neither demo is in the default `demoContent()`.

## 7. Human checks to add (`docs/verification/human-checks.md`, new group `GS`, provisional letter, not run: an agent cannot)

GS1 drag the chip and release: it eases home over 0.25 s on macOS and on SDL; GS2 hold the chip past 0.5 s and release early: the pressed look turns off at the maturity and at the release; GS3 flip System Settings,
Reduce Motion, then re-run `swiftui-gesture-state.swift` `P1`/`P2` and the looks pulse: record whether SwiftUI and MetalUI stop or snap (`GS-K`); GS4 start a drag and Cmd-Tab away, return: the chip is home (key loss
is not a cancel, `C4`, the release still ends it); GS5 leave the looks demo's pulse running for a minute: CPU near 0 % when the window is occluded or the pulse is removed, one core's share while it runs (display link
only while running); GS6 the same on Linux with a real pointer.

## 8. Scope: deferred and why

`GS-N` is the list: composite `updating` and the `GestureStateGesture` type (no composite value in MetalUI; additive), `PlaceholderContentView`, the end-of-run content call and phase-independent content skip, Reduce
Motion semantics (unmeasurable by an agent, human check GS3), `@MainActor` on the `updating` closure. Owner for all: none, unless GS3 refutes `GS-K`, then the Record phase's follow-up.
