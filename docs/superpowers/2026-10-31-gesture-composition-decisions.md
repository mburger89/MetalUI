# Gesture composition - decisions

Rulings for round-3 item R3-5: `sequenced(before:)`, a custom `Gesture` with a `body`, `updating`/`onChanged`/`onEnded` on composed gestures, and
`DragGesture.Value`'s `time`/`velocity`/`predictedEnd*`. Prefix `GE-`. Branch `feat/gesture-composition` from master `28a819e9`.
Evidence: `docs/probes/swiftui-gesture-composition.swift` (compiled form, screen unlocked, output in its header; arms `S1`-`S7b`, `X1`-`X2b`,
`C1`-`C5`, `D0`-`D15`, the instrument of `swiftui-gesture-state.swift`). **Nothing is published** (`BS-H`). Divergence labels **925-934 reserved**;
**925 taken** (`GE-G`), the rest unused. Record: `../record/178-gesture-composition.md`. **Next unused: `GE-J`.**

**Carried.** `IX-B` (a gesture's callbacks are returned by value from the pure arena and run under `StateDispatch`), `IX-D` (the arena's order and
blocking), `IF-E`/`GC-` (cancel paths), `GS-A`...`GS-G` (the state a gesture writes is a `$state<n>` slot reset by a finish hook), `CI-A` (its "not offered"
rows for `sequenced`, `GestureMask`, a custom `body`, `updating` on a composite, `time`/`velocity`/`predictedEnd*` are lifted here except `GestureMask`).

## GE-A - A custom gesture is a struct with a `body`; the recognizer requirement leaves the protocol

**Ruling.** `Gesture` gains `associatedtype Body: Gesture` and `var body: Body { get }` as SwiftUI declares them; `associatedtype Value = Body.Value`
(an opaque `some Gesture` body makes `Value` unspellable, as in SwiftUI - name the body's type when the value is needed). `Never: Gesture`; every
recognizer MetalUI provides has `Body == Never` and the default `body` traps. **`_recognizers()` is no longer a protocol requirement.** The arena's description of a gesture
is `recognizerNode(of:)`: an internal `PrimitiveGesture` (conformed by every MetalUI recognizer, composite and wrapper) answers with its own node, anything else
recurses into its `body`. The `@_spi(MetalUIGesture)` requirement and `_GestureRecognizers` became internal: a default implementation in an SPI extension is not
visible to an outside conformer, so a witness could not be found (measured: "protocol requires function `_recognizers()`" from a plain-import-like module).
`Gesture.body`'s default for `Body == Never` is public (a public type's witness of a public requirement must be), so - as in SwiftUI - `struct Mine: Gesture {}` compiles and traps when evaluated; a `Body` that is not a gesture does not compile (guard `GE.1`'s negative arm). **`WD-B` amended:** `WindowDragGesture` reports no value, and the generic `onChanged`/`onEnded`/`updating` now compile on it and never run (an `unavailable` shadow does not work: Swift ranks an unavailable overload below an available generic one, measured); guard `3.2`'s callbacks arm became a positive control, its value arm still separates.
**Reasoning.** SwiftUI's own split between primitive and composed gestures; `IX-B`'s "an outside module cannot conform" was a deferral ("additive: opening the
protocol later breaks no caller"). **Cost if wrong.** A third-party gesture can only be composed from MetalUI's, never describe recognizers (stated in the doc comment).
**Pins.** `aCustomGestureRunsItsBodyAndTakesOnEnded`, `updatingOnACustomGestureWrapsItsBodyAndResets`, `aCustomGestureWhoseBodyIsASequenceReportsTheSequenceValue`,
`aCustomGestureComposesWithTheCombinators`; guards `anOutsideTypeCanConformToGestureThroughABody` (G `GE.1`), `anOutsideTypeCannotDescribeRecognizersItself` (G1.1 amended).

## GE-B - `sequenced(before:)`: the second member waits for the first and starts from the first event after it

**Ruling.** `Gesture.sequenced(before:)` returns `SequenceGesture<First, Second>`, `Value` = `.first(First.Value)` / `.second(First.Value, Second.Value?)`
(SwiftUI's). The arena has a `.sequence(first, second)` node: the second member's leaves are **gated** (`ArenaLeaf.gates`) - they record nothing and act on
nothing - until the first node has ended; a failed first fails the whole sequence (the cascade is in `cancelBehindEndedMembers`); the sequence ends when the second
ends. When the gate opens (`openGates()`, in `resolve()`'s loop) each second leaf is rebased: a drag **starts at the first pointer event after the gate** (probes
`S1`, `S2`, `S5b`: the first move, not the press, not the pointer where the first ended), a long press restarts its timer from the next tick, a tap measures from the pointer's
position; **the event being resolved is replayed to them as their first** when it is a move or a release (probe `S7`: a tap ends at its release and a minimum-0 drag
ends with that same release). A drag whose first event is the release and whose minimum is 0 **ends with no change before it** (`endOnRelease`, probe `S4`); with a minimum it fails (`S4b`).
`TapGesture`-first and a LongPress/Tap **second** member are MetalUI's reading of the same rule and **unprobed** (the second member's timers and slop restart at the gate; click counting is
not re-based). A nested `a.sequenced(before: b).sequenced(before: c)` nests gates (one entry per enclosing first member).
**Cost if wrong.** A second tap/long press would need re-basing of `baseClickCount`; carried below.
**Pins.** `aLongPressThenDragReportsFirstThenSecondWithTheDragStartingAtTheFirstEventAfter`, `theDragMinimumIsMeasuredFromTheFirstEventAfterTheLongPress`,
`aReleaseRightAfterTheLongPressEndsOnlyADragWithNoMinimum`, `aFailedFirstGestureFailsTheSequence`, `aTapThenADragEndsOnTheReleaseThatEndedTheTap`.

## GE-C - A composite reports its value once per event, through hooks on its node

**Ruling.** A composite gesture's `_recognizers()` returns `.hooked(node, CompositeHooks)`. Each member node is *tapped* (`GestureNode.tap(changed:ended:)`): a leaf's typed
callbacks (`dragChanged`, `longPressEnded`...) are wrapped so the tap runs after the leaf's own, in declaration order (`GS-E`); a composite child adds to its own hooks.
Values travel as `Any` and are cast back by the typed composite that made the node. The composite keeps its latest value and a dirty flag in a small state box; the arena queues
**one `flush` callback per composite after the event's leaf callbacks** (when any were queued), so a composite reports once per event (probe `X1`: the press's drag change and
long-press `true` arrive as one update, not two). When a composite node's status leaves `.possible` the arena queues, in this order, its updating resets (`finishes`), its `ended`
(if it ended: `onEnded` taps) and its state `reset` - so `onEnded` reads a reset `GestureState` (`GS-C`, `G8`) and a failing composite resets too; a dropped arena settles through
`cancel()`. Simultaneous: each member's latest, a member's end replaces its slot without a report, one `ended`
when the node ends (probe `X1`); exclusive: the winner's value; sequence: GE-B. The helper classes are `@unchecked Sendable` (all access is on the main actor; the `_recognizers()`
construction site is not isolated).
**Pins.** `aSimultaneousCompositeReportsBothLatestValuesOncePerEvent`, `anExclusiveCompositeReportsTheWinningMembersValue`, `updatingOnASequenceRunsForEachValueAndResetsAtTheEnd`,
`aSequenceThatFailsOrEndsWithoutMovingStillResetsItsState`.

## GE-D - A pointer event carries its timestamp

**Ruling.** `MouseEvent.timestamp: Double?` (`ScrollEvent.timestamp`'s clock: `NSEvent.timestamp`, SDL's event time; `nil` for an event built without one). AppKit and SDL stamp press, release
and drag events; `MetalUITesting` stamps `now`. `Window` passes `mouse.timestamp ?? lastGestureTime` (the display link's last tick) to the arena; `GestureArena.press/move/release` take
`timestamp: Double? = nil`. `DragGesture.Value.time` is `Date(timeIntervalSinceReferenceDate: stamp)` - the exact relation the probe measured (`D0`) - never the wall clock (`D2`, `D3`).
A value built without a stamp has the reference date.
**Pins.** `timeFollowsTheEventTimestampsNotTheWallClock`, `anUnstampedPointerEventStillProducesAValue`.

## GE-E - `onChanged`, `onEnded` and `updating` are on every gesture

**Ruling.** Protocol-extension `onChanged`, `onEnded` and `updating(_:body:)` return `_ChangedGesture`, `_EndedGesture`, `GestureStateGesture` (SwiftUI's spellings), tapping the base's node
(and, for `updating`, adding the state's reset as a finish hook). The recognizers' own concrete methods are unchanged and win overload resolution (they return the receiver's own type
and keep `GS-E`'s ordering inside one leaf); a composite or a custom gesture uses the wrappers. `onChanged` does not require `Value: Equatable` (SwiftUI does; a superset, no row).
`TapGesture`/`SpatialTapGesture` `updating` still never runs. **Not offered**: a composite's `onCancelled` (a dropped composite resets its states and reports nothing).
**Pins.** every composite test above; guard `GE.1`.

## GE-F - Velocity is a 3:1 blend of the last two intervals; the prediction is a quarter second of it

**Ruling.** Probe lines `D1`-`D15`. `DragGesture.Value.velocity` (`Size<Pixels>`, points per second, y down, in the gesture's space) = `0.75 *` the previous interval's speed `+ 0.25 *` this
interval's, intervals being consecutive pointer samples and speeds distance over the difference of the **event stamps**; with one interval its speed alone, with none zero. The press is the
first sample; moves before `minimumDistance` feed it (`D13`); the release is one more sample (`D8`: a release 0.3 s after the last move reads `0.75 * 500`, **no time decay**); an event stamped
at or before the last sample's instant replaces that sample (`D14`, `D15`; no division by zero). `predictedEndLocation = location + velocity / 4`, `predictedEndTranslation = translation + velocity / 4`
(computed). The estimator is per drag leaf (`ArenaLeaf.samples`, three entries). `DragGesture.Value` gained `time` and `velocity` (stored; `Equatable` compares them) and an extended
`init(startLocation:location:modifiers:clickCount:time:velocity:)`. `MagnifyGesture.Value`/`RotateGesture.Value` stay without them (CI-A's row narrows).
**Pins.** `aSteadyDragReportsItsVelocityAndAQuarterSecondPrediction`, `theVelocityIsAThreeToOneBlendOfTheLastTwoIntervals`, `aLateReleaseBlendsAZeroIntervalAndDoesNotDecay`,
`movesBeforeTheMinimumDistanceFeedTheEstimator`, `anEventAtTheSameInstantReplacesTheLastSample`, `theVelocityIsPerAxisAndSigned`.

## GE-G - What is not replicated (divergence 925)

**Ruling.** Probe `X2` shows an exclusive composite's `updating` running a second time with the same `.first(true)` at the first pointer move while the long press is still undecided. The cause is not
established and a faithful reproduction would need a reason; MetalUI reports a composite only when a member reports. Divergence **925**; `anExclusiveCompositeReportsTheWinningMembersValue` pins MetalUI's
answer (one update). The same probe's `X1` (once per event) is reproduced, not a divergence.

## GE-H - `GestureMask` is carried

**Ruling.** `.gesture(_:including:)`, `.highPriorityGesture(_:including:)`, `.simultaneousGesture(_:including:)` and `GestureMask` are **not built** this round. They are not cheap: the mask must reach
the arena as a per-attachment filter on members at other depths (`.subviews` drops the attachment's own, `.gesture` drops every inner member), the semantics at the same depth, with `onClick` and a
draggable (`DN-E`) and with a high-priority attachment are unprobed, and a wrong guess changes which gestures run silently. Owner: the gpui-gap list (round 4). The `Not offered` row in
`docs/divergences.md` stays, narrowed to `GestureMask`.

## GE-I - No new handler-registering site

**Ruling.** Gestures still register through `GestureModifier` / `StyledElement.gesture` -> `registerHandlers`; `sequenced` and the wrappers only change the node a `Gesture` describes. The D2 guard
(`everyHandlerRegisteringSiteIsGuarded`-class tests) needs no new arm, and no `StateTable` write site is added (a `GestureState` write is `GS-A`'s). Windows' 1 MB stacks and the asserts compiler: the
composites add no loop-in-`Component` shape; `recognizerNode(of:)` recurses only through `body`.

## Mutations

See `../record/178-gesture-composition.md`.
