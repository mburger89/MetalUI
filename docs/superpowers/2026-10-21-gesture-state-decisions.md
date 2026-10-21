# `@GestureState` and `phaseAnimator` — decisions

Rulings for item G1 (user request 2026-10-02 on the gpui-gap priority list, round 2 started 2026-10-21; not a plan task). Spec:
[`specs/2026-10-21-gesture-state-design.md`](specs/2026-10-21-gesture-state-design.md). Record: `../record/135-gesture-state.md` (Record phase).
Branch `feat/gesture-state` from `1bdead8d`. Evidence: `docs/probes/swiftui-gesture-state.swift` (compiled form, screen unlocked,
output in its header; arms `G1`–`G13`, `P1`–`P10`, the instrument of `swiftui-input-followups.swift`), the earlier `swiftui-input-followups.swift`
`C1`–`C5`, and the SwiftUI interface census. **gpui has no counterpart** for either feature (a gpui view holds ordinary entity state and resets
it by hand in its own mouse-up handler; gpui animations are `with_animation` over an element id, no phases): nothing is claimed from gpui.
Divergence labels **645–654 reserved**; **645 taken** (`GS-G`), the rest unused.

Prefix **`GS-`**, lettered. **Next unused: `GS-Q`.** (Moves in the commit that appends a ruling.)

**Carried.** `IX-B` (a gesture's callbacks are returned by value from the pure arena and run under `StateDispatch`), `IF-E`/`IF-F`/`IF-K`/`GC-`
(every `onCancelled` path; divergence 236 amended at Record), `ID-F` (an aliased state box resolves its occurrence from the dispatch owner),
`LK-I` (`keyframeAnimator`: a transparent scope, its record in `AnimationStore`, never a `StateTable` slot), `AN-Y` (`TransactionScope`, the
transaction a build resolves is re-pushed in paint), `RW-`/`RK-F` (a framework state write owes a journal event, a read goes through
`readState`/`peek`), `theSevenRetentionSlotsAreMutuallyDistinct`.

## GS-A — Storage: a `GestureState` is a `$state<n>` slot, not an eighth reserved name

**Ruling.** `GestureState<Value>` is a `@MainActor` property-wrapper struct holding a `State<Value>.Box`-shaped box and conforming to
`BindableState`, so `StateBinder` seeds it with the very walk, the very `$state<slot>` name and the very `Box.occurrences`/`resolvedSlot`
aliasing machinery `@State` has. Reads are `StateTable.peek` (`?? initialValue`), writes `StateTable.write`. **No new reserved name**:
`theSevenRetentionSlotsAreMutuallyDistinct` is untouched, `StateTable.write` already taints the retained and prepaint logs and the
content-memo journal (`RK-F`), and the content memo already reads a `BindableState`'s version (`stateOrdinals`), so an `.equatable()`
component that reads a `GestureState` re-evaluates while a gesture writes it and is skipped again at rest, with no new code. **A new write
call site is `write(`, which `everyStateWriteSiteIsClassified` does not count** (it counts `withState`/`readState`); the row table needs
no entry. The wrapper is not a `FocusState` (the memo's `hasFocusState` refusal stays false). **Reasoning.** SwiftUI's own is a `State` plus a
reset closure (the interface census: `fileprivate var state: State<Value>`, `fileprivate let reset`). An `AnimationStore` record (the
`keyframeAnimator` shape) was weighed and rejected: it is swept per frame when no build touches it, and a gesture outlives a build; the
state the view's body reads must also be a version the memo and the retained paint record compare, which only a `StateTable` entry is.
**Cost if wrong:** a second-write path would need a journal event of its own; the lane-1 test `aGestureStateWriteIsAStateWriteForTheMemoAndRetainedPaths`
(memo skip, retained replay, `METALUI_VERIFY_RETAINED=1`) is the tripwire.

## GS-B — API: SwiftUI's wrapper, `updating` on the concrete gestures, returning the receiver's own type

**Ruling.** `GestureState<Value>`: `init(wrappedValue:)`, `init(initialValue:)`, `init(wrappedValue:resetTransaction:)`,
`init(initialValue:resetTransaction:)`, `init(wrappedValue:reset:)`, `init(initialValue:reset:)` and, `where Value: ExpressibleByNilLiteral`,
`init(resetTransaction:)`, `init(reset:)` (the interface census, probe header); `wrappedValue` **get-only**; `projectedValue` is the
`GestureState` itself (its box shared, so `$offset` passes the same state). `updating(_:body:)` is `(Value, inout State, inout Transaction) -> Void`
(`@MainActor`, like every gesture callback) on `DragGesture`, `LongPressGesture`, `MagnifyGesture`, `RotateGesture`, **and on `TapGesture`/
`SpatialTapGesture` where it compiles and never runs** (probe `G2`, `G5b`: SwiftUI's own never runs for a tap), and **returns the receiver's own type
with the update stored**, as `onChanged`/`onEnded` already do (`IX-B`: "the spelling is SwiftUI's; only a caller naming the wrapper type sees a
difference" — here `GestureStateGesture<Base, State>`). So `DragGesture().updating($s) { … }.onChanged { … }.onEnded { … }` compiles as SwiftUI's
chain does. **Not offered, named:** `updating` on an `ExclusiveGesture`/`SimultaneousGesture` (MetalUI reports no composite value; write the
`updating` on a member, which also reads better), on `WindowDragGesture` (no value), and `GestureStateGesture` as a type. Owner none; additive later
(a protocol extension over a `Value`-bearing composite would not break a caller). **Cost if wrong:** a caller who names `GestureStateGesture` or
updates a composite gets a compile error naming the missing member, never silent behaviour.

## GS-C — Lifecycle: one `finished` hook on the arena leaf; reset when the leaf ends, fails or is cancelled

**Evidence (probe).** The reset is applied: at the release for a drag (`G1`: `s=0` in the release event's body); **before `onEnded`** (`G8`: `ended s=0`);
at the moment a long press ENDS while still held (`G4`, 0.3 s); at the moment it FAILS, not at the release (`G12`: pointer left `maximumDistance`
at 0.15 s, `s=0` at 0.2 s, release at 0.5 s; `G3`: a release before the minimum); and for a gesture disabled or an owner removed mid-drag at the
next event (`swiftui-input-followups.swift` `C2`/`C3`), which is the release. **Ruling.** `GestureLeaf` gains one field,
`finished: (@MainActor () -> Void)?`, set by `updating` (all updates of one leaf in one closure). `GestureArena` queues it as an ordinary
`.gesture(owner:run:)` callback **in `fail(_:)`** (every failure, including those after `cancel()`, a draggable's or window drag's takeover and
`cancelBehindEndedMembers`), **in `act(_:)` just before the leaf's ended callback** for tap/long press/drag/pinch (so the state reads reset in
`onEnded`), and `cancel()`/`abandon()` hand back the callbacks `fail` queued (today `cancel()` drops `callbacks`: the hook owes it a drain, test
`everyCancelPathResetsOnce`), failing a leaf that `owesFinish` even when it never `activated` (a long press under a closing window). The hook
runs **once per leaf** (a flag cleared when queued) and the reset itself **only if the box is dirty** (`GS-D`), so a leaf that never wrote queues
nothing and a shared state is reset once, not once per writer. **Disabled / removed mid-drag:** the arena closures still run at the release (the
leaf ends or fails there), so the reset arrives at the release exactly as SwiftUI's does; no new path, **but every site that discards an arena
without `cancel()`/`abandon()` (`gestureArena = nil`, `endPressForDrag`) is audited and pinned** (lane 1, one arm per site). `onCancelled` (`IF-E`)
and the hook are independent: `onCancelled` runs for a leaf that reported; `finished` runs for every leaf that wrote. **Reasoning.** The arena is pure and
every termination already passes through two places (`fail`, `act`), so one hook there is exhaustive by construction, where a Window-side registry of
pending resets would have to be kept in step with every arena replacement. **Cost if wrong:** a path that skips both places leaves a state stuck at
its dragged value — the failure is loud (a view that does not snap back), and `everyCancelPathResetsOnce` has one arm per `IF-F`/`GC-` path.

## GS-D — Writes: one slot, a per-event base, last writer wins, a dirty flag

**Evidence.** Two gestures into one state (`G7`–`G7e`): every `updating` body of an event starts from the value committed before the event (the drag's
`+= 1` read 0 after the long press's `+= 100`), a body that does not touch its `inout` still writes its copy back (`G7e`: the no-op long press, run last,
left 0), the last body run wins, and ending any writer resets the whole slot (`G7b`, `G7c`). **Ruling.** `GestureStateBox` (a class beside `State.Box`)
holds `dirty` and a `(batch, base)` pair. `Window.runGestureCallbacks` increments a package-level `GestureStateBatch.current` once per call (one call is one
event's callbacks); an update takes `base` = the committed value the first time it runs in a batch, runs its body on a copy of `base`, writes the result
(`StateTable.write`, always, even unchanged) and sets `dirty`; the reset writes `initialValue` and clears `dirty`. A body run outside `Window` dispatch
(a unit test calling the closure) sees counter 0 and reads the committed value afresh. **Order of simultaneous writers is MetalUI's arena order**
(declaration order), while SwiftUI's first-run member of `simultaneously(with:)` is the **last declared** (`G7`, `G7d`): the arena's order is pinned by `H16`
and must not move, so a conflict resolves to the other writer — **divergence 645** (only when two simultaneously composed gestures write one
`GestureState` in one event). Pinned wrong on purpose. **Cost if wrong:** the per-event base is invisible when one gesture writes a state (every shipped idiom);
if SwiftUI's base proves to be per-gesture rather than per-event the `G7`/`G7e` pins are the two to re-read.

## GS-E — Order against `onChanged`, and what a callback reads

**Evidence.** `.updating($s).onChanged { read s }` reads the new value before the body re-renders (`G8`: `changed s=1`); `.onChanged.updating` runs `changed`
first (`G13`); `G6`: two `updating` on one gesture run in declaration order. **Ruling.** An `updating` records `runsAfterChanged = (changed != nil)` at the
moment it is applied; the leaf's change closure runs each update and the user's `onChanged` in **declaration order** (updates declared before the
`onChanged` run first, those after it follow). `onChanged` keeps today's replace-on-second-call semantics (`IX-B` precedent, not SwiftUI's chain; not changed
by this item). **Cost if wrong:** only a callback that reads the state it shares an `updating` with.

## GS-F — Transactions: the update's from the body, the reset's from the state

**Evidence.** The update's transaction has no animation unless the body sets one (`G9`, `G10`: every update carries it, the reset does not); the reset's is
`resetTransaction` (`G8`) or what the `reset:` closure writes (`G11`, the closure runs once at the reset with the value before it, `v=3`). **Ruling.** The
update runs under `withTransaction(t)` only when `t.animation != nil` after the body; the reset under `withTransaction(resetTransaction (then the closure))`
only when that has an animation, the same `parkTransaction` path `withAnimation` uses, so an animated reset is **divergence 99's one root transaction for
the next build** (every change of that build animates with it; unchanged otherwise, and a state-bound `.offset` snapping back is the one such change in
every shipped idiom). No new transaction field. **Cost if wrong:** two animated writes in one build share one animation (divergence 99, existing).

## GS-G — Divergence 645 (the only label this item takes) and the amendments

**Ruling.** 645 is `GS-D`'s writer-order difference. **Amended at Record, not here:** divergence 236's "`@GestureState`/`updating` are not offered" (now
built; `onCancelled` stays MetalUI-only for callers who want the event, not the reset), `Gesture.swift`'s header ("`@GestureState` is replaced by
`onCancelled`"), `IF-E`'s "no `@GestureState`", divergence-table row 247's "`@GestureState`" in its not-built list, `LK-I`'s "`phaseAnimator` is not built".
`updating` on a composite, `GestureStateGesture` the type, and `PlaceholderContentView` (`phaseAnimator`'s content receives the element itself, divergence
169's rule for `keyframeAnimator`) are **named not-built**, not labelled.

## GS-H — `phaseAnimator`: one more transparent scope beside `keyframeAnimator`

**Ruling.** `PhaseAnimator<Phase: Equatable, Content: ElementGroup>` is an `ElementGroup` (and, `where Content: ProposalElementGroup`, a
`ProposalElementGroup`, the `keyframeAnimator` pair line for line, `keyframeAnimatorKeepsProposalContentProposal`'s copy-of-a-pinned-implementation rule)
built by `ElementGroup.phaseAnimator(_:trigger:content:animation:)` and `phaseAnimator(_:content:animation:)` (`content: (Self, Phase) -> Content`,
`animation: (Phase) -> Animation? = { _ in .default }`) and by `PhaseAnimator(_:trigger:content:animation:)`/`(_:content:animation:)` (content `(Phase)`).
The phases are collected into an `Array` once at construction. **Transparent**: no node, no identity level, parent and cursor forwarded; **its record
is a `PhaseRecord` in the window's `AnimationStore`, keyed `$phase<depth>` under the position** (never a `StateTable` slot; the seven slots unmoved;
`LK-I` items 9-12's sweep: a record no build touches for a frame is dropped, so content that leaves and returns starts at `phases[0]`). **The depth counter
is `keyframeDepth`'s, shared** (`withKeyframeScope`): the names differ (`$phase1` against `$keyframes1`), so one counter cannot collide, and
`RetainedGraft`'s ambient `depths` tuple (C14-i's file) need not change. A `Self`-returning decoration written after it does not compile (divergence
120's rule, `LK-T` item 2; a typecheck guard). **Cost if wrong:** a nested pair sharing a counter is harmless; a retained graft that must key the phase
depth would be a one-line addition in `RetainedGraft.swift`, a file this item does not own.

## GS-I — Stepping: the probe's schedule, in the frame's clock

**Evidence (probe `P1`–`P9`).** At appear `phases[0]` is built with no `animation` call. **No trigger** (`P1`): a step to `phases[1]` at once, then
`1, 2, 0, 1, …` forever, one step each `d` where `d` is the duration of the animation of the phase just entered. **Trigger** (`P2`): a change runs `phases[1]`,
`phases[2]` … then `phases[0]` (with `animation(phases[0])`), each held for its animation's duration, and ends; no change runs nothing (`P3`); a change
mid-run restarts at once from `phases[1]` (`P4`); `d` is the animation's duration (a spring step lasts its `duration:`, `P6`; 1.0 s spaces 1.0 s, `P9`);
a nil animation snaps the phase and the next step follows at once (`P5`); one phase runs nothing (`P7`); equal neighbours step without wait (`P8`).
Every phase's content is built under a transaction whose animation is `animation(phase)` (`tx<p> anim=true`). **Ruling.** `PhaseRecord` holds `{trigger,
index, stepStart, running}`; a build takes **at most one step** and advances when `now - stepStart >= duration(animation(index))`, `duration` being
`Animation.nominalDuration` (internal: `seconds` of a duration curve, `duration:` of a spring) and **zero for nil or a zero duration**, so a zero step
takes the next build (`noteActiveAnimation()` keeps frames coming; a frame is the finest MetalUI can show, where SwiftUI's two builds share one instant
— the nil-phase snap is still built and drawn before the next, so the next animates from it as `P5` does). A step's start is its **scheduled** time
(`stepStart += duration`) unless the build is late by a whole step, then `now` (no cumulative drift at 60 Hz, no burst after a stall). A trigger change
restarts in the same build (`index = 1`, `animation(phases[1])`); `phases.count < 2` runs nothing. A trigger is compared with `==` (`keyframeAnimator`'s
`matches`). While running (no trigger: always, with two or more phases) the build calls `noteActiveAnimation()`, **never `requestAnotherFrame()`**; at rest
nothing is raised and the window idles. **Not reproduced** (counts, not values; unpinned): SwiftUI's one extra content call at the end of a run (`P2`
`c0@1.2`) and its not re-calling content that ignores the phase (`P10`, unexplained). **Cost if wrong:** a run that is one frame longer than SwiftUI's per
zero step; the pin counts steps and values, not times, except the explicit schedule pin at 0.4/0.5/1.0 s on the simulated clock.

## GS-J — The transaction a phase's content is built under, and where the content is built

**Ruling.** The scope resolves, once per layout, the transaction `inherited with animation = animation(phase)` **on the build that took the step** (and the
inherited one on every other build, so a value mid-flight keeps its animation, which lives in its own baseline), pushes it with `Frame.withTransactionScope`
around the content's layout and re-pushes the layout's resolved copy in paint (`TransactionScope`'s `AN-Y` shape: a value compared twice would read
"unchanged"); prepaint pushes nothing. `snapsEveryChange` (the first presented frame, `CR-Q`) and `disablesAnimations` apply as for any scope. The content closure is called
in layout, once per build, with the phase the record resolved (as `keyframeAnimator`'s with its value). **Cost if wrong:** an animation applied one build late
would show as a step that snaps; pin `eachPhasesContentIsBuiltUnderItsAnimation` reads the transaction inside the content.

## GS-K — Reduce Motion: not changed, not claimed

**Ruling.** `accessibilityReduceMotion` changes only transitions (`AN-`), and `phaseAnimator` keeps stepping and animating under it. **Not measured in SwiftUI**: the
key is read-only (`.environment(\.accessibilityReduceMotion, true)` does not typecheck) and the system setting is not flipped by an agent (probe header `R`). Human
check `GS3` flips it on a real Mac and re-runs the probe's `P1`/`P2`. **Cost if wrong:** a Reduce-Motion user sees an endless pulse where SwiftUI may stop or snap;
the counter-ruling is one `snaps` read in `PhaseRecord` resolution, so cheap.

## GS-L — Lanes, files and the cross-sibling edges

**Ruling.** Two lanes, disjoint source files (spec §3). **Edges with the three siblings:** C14-i owns `Retained*.swift` (this item edits none; `GS-H` keeps it that
way); L1 (lazy containers) owns layout files and `List`/stack sources (none touched); E1 adds an example target (none). `Window.swift` is shared by nobody
named here but is large and busy: lane 1's edit is `runGestureCallbacks` and the arena-discard sites only. The **inventory map and census** rows are appended
by each lane for its own declarations in separate blocks of `closeout-inventory-map.tsv`; the orchestrator re-records the census once after both merge.

## GS-M — The demo and the guides

**Ruling.** Demo coverage goes in two **existing env-gated** demos, each as its own function/`Component` (Windows 1 MB stack,
`everyProductionTreeBuildsOnAOneMegabyteThread`): a drag-and-snap-back chip and a press-and-hold chip in the input follow-ups demo (lane 1), a three-phase pulse
and a triggered phase row in the looks demo's keyframes row (lane 2, no tap targets: the looks demo's tests count its click targets). The default demo content is not
touched, so the fourteen images stay 0 px. Guide snippets: `docs/guides/input.md` (the `@GestureState` snap-back) and `docs/guides/drawing-and-gpu.md` (`phaseAnimator`),
each mirrored by hand into its own `GuideMirrors*.swift` file (`DG-C`, `DG-D`).

## GS-N — Scope: what is deferred, why, and who owns it

**Named, owner none unless stated.** `updating` on composed gestures and `GestureStateGesture` as a type (`GS-B`); `GestureState` write from a `Binding` (SwiftUI has
none: `wrappedValue` is get-only); a `@GestureState` reset on `onDisappear` of the owner distinct from the state's own sweep (the entry goes with the owner, `ID-C`);
`phaseAnimator`'s end-of-run content call and phase-independent content skip (`GS-I`, unobservable but by side effect); Reduce Motion for `phaseAnimator`
(`GS-K`, human check); `PlaceholderContentView`; SwiftUI's non-`@MainActor` `updating` closure (ours is `@MainActor`, like `onChanged`). `.sequenced(before:)`, `GestureMask`,
`including:` stay `IX-B`'s not-built list.

## GS-O — Critic round: the probe's recorded lines are re-taken before a pin rests on them

**Ruling.** The critic could not re-run the probe's arms (the screen was locked: `CGSSessionScreenIsLocked = 1`, `displayAsleep main: 1`; the instrument needs a key
window), so the header's lines stand as recorded and **unverified by the critic**. The lanes re-run `G7`/`G7e` (the one claim behind divergence 645) and `P5` (the
nil-animation step) byte for byte when the lock probe allows, **before writing the pin**; a line that differs is re-ruled, and the pin is written from the new line.
If the screen stays locked, those three pins and divergence 645's row carry "recorded 2026-10-21, not re-taken" in the test header and the record. **Cost if wrong:** one divergence
row or one stepping pin re-ruled.

## GS-P — Critic round: lane 2 never edits `Retained*.swift`; a red `.equatable()` arm is refused by name, not fixed here

**Ruling.** Spec §5 lane 2 item 13 said a fix shared with `keyframeAnimator` would be "named in the record". That would edit C14-i's files. **Rejected**: if
`aPhaseAnimatorInsideAnEquatableComponentKeepsStepping` is red for `keyframeAnimator` too, lane 2 pins the refusal as it is (a counted, named refusal or the
measured behaviour), records it as a carried item owned by C14-i, and edits no `Retained*.swift`, `ContentMemo*` or `StateTable` file. The same holds for lane 1's
retained/memo pin (`GS-A`): a gap there is carried, not patched in C14-i's files. Lane 1's `Window.swift` edit stays confined to `runGestureCallbacks` and the arena-discard
sites. **Cost if wrong:** a carried item instead of a fix in this branch.
