# Lifecycle modifiers — decisions

Rulings for `onAppear`, `onDisappear` and `onChange` (user request
2026-10-02, an item of the gpui-gap priority list; **not a plan task**). Spec:
[`specs/2026-10-03-lifecycle-design.md`](specs/2026-10-03-lifecycle-design.md).
Record: `../record/76-lifecycle.md`. Evidence:
[`../probes/swiftui-lifecycle.swift`](../probes/swiftui-lifecycle.swift)
(**new**; arm ids `L…` controls, `A…` order, `F…` the first frame, `C…`
`onChange`, `E…` disappearance, `D…` state read in `onDisappear`, `S…`
scrolling, `T…` transitions, `W…` the window, `K…` `.task`; its header carries
the recorded output, run three times, and the reading) and the runtime probe
[`../probes/swift-main-actor-task-loop.swift`](../probes/swift-main-actor-task-loop.swift)
(arms `P0`, `B1`, `B2`; run on macOS and in `swift:6.4-noble`). Where SwiftUI
has no answer (headless rendering, a window close with no host, a frame's
settle bound) the ruling says so and names gpui's approach as the comparison,
not as evidence.

Prefix **`LC-`**, lettered. **Next unused: `LC-U`.** (This line moves in the
commit that appends a ruling; read the last `## LC-` heading.)

Branch `feat/lifecycle` from `047f0ab` (master: colour and colour scheme
merged, PR #45). Baseline at `047f0ab`: spec §0. `docs/divergences.md` line 4
and 12: **86 live, next label 120** (CLAUDE.md's "70 live, next label 104" is
stale; the file is the authority).

**Carried items.** `@State`'s "write from input, never from a phase" (CLAUDE.md
`@State`; `RX-K`/`RX-S` — an `@Observable` write inside the tracked build is a
lost dirty) — the reason `LC-E` runs actions after the build, outside
`withObservationTracking`. `ID-B`/`ID-C`/`ID-R`/`DD-C` (structural identity,
evaluated-removal resets) and `TB-AH` (an unevaluated `List` row keeps its
state) — `LC-C` defines presence against them and moves none. `AN-Y`/`AN-AB`
(`.animation(_:value:)`'s transparent `TransactionScope`, its previous value
in the window-owned `AnimationStore`, dropped when untouched one frame) — the
shape `LC-B` and `LC-D` copy. `AN-AE`/`AN-AK` (transitions, the removal
ghost) — `LC-H` reads the ghost's lifetime. `ID-F`/`ID-O`
(`StateDispatch`) — `LC-E` dispatches each action to its element. `MV-E`/
`MV-H` (a window-owned registry, nothing run by a headless `renderFrame`) —
the pattern `LC-D`/`LC-J` follow. `MC-B`/`LR-AA` (a hook added to `Element`'s
group defaults is mirrored per layer and in `AnyElement`) — not triggered
(`LC-B`). `CR-Q` (a second build inside one `beginFrame()`) — the precedent
`LC-E`'s settle build follows. No decisions doc's "Carried…" section names an
appearance, a disappearance or a value-change callback; the plan's gap 10
(the SDL loop never drains the main queue) is `LC-L`'s owner.

---

## LC-A — Scope: what this branch builds, what it defers

**Ruling.** Build, SwiftUI-spelled and probe-backed, on **both vocabularies**
(every `ElementGroup`; the typed `ProposalElementGroup` entry is a pinned copy):

1. `.onAppear(perform:)` and `.onDisappear(perform:)` (`LC-B`), with presence
   defined by identity (`LC-C`), run after the frame under `StateDispatch`
   (`LC-E`) in SwiftUI's order (`LC-F`), deferred to the end of a removal
   transition (`LC-H`), reading the departed element's own state (`LC-I`),
   and run at window close (`LC-J`).
2. `.onChange(of:initial:_:)` with both closure forms, `Equatable` values,
   the previous value stored per identity in a window-owned store, not a
   `StateTable` slot (`LC-D`, `LC-G`).
3. A looks-demo section and human-checks group T (`LC-N`).

**Deferred, each named in spec §9 with a reason and an owner:**
`.task(perform:)`/`.task(id:priority:_:)` (`LC-L`: the SDL loop starves
main-actor tasks — owner: the plan's gap 10, the SDL run-loop drain);
`onChange(of:perform:)` (the single-parameter form SwiftUI deprecated in
macOS 14 — not offered, owner none); `onReceive`, `scenePhase` and app-level
lifecycle (owner none); lifecycle modifiers on menu content (`MenuContent` is
data, not an `ElementGroup` — owner none); a legacy `Self`-returning
decoration written after a lifecycle modifier (divergence 120, owner none —
the same constraint every transparent scope has).

**Reasoning.** The port this serves (SMK) needs exactly three things: start
and stop a device monitor with a pane (`onAppear`/`onDisappear`) and turn a
changed error into an alert (`onChange(of:)`). `.task` would be the natural
fourth, but it is only honest where a main-actor task progresses on every
platform, and `LC-L` measured that it does not.

**Cost if wrong.** Each deferral is additive over the scope `LC-B` builds: a
`.task` scope is one more `LifecycleWrite` case whose appear starts a `Task`
and whose disappear cancels it.

## LC-B — API and shape: one transparent `LifecycleScope`

**Ruling.**

1. **Spelling** (SwiftUI's, macOS 14+):
   `onAppear(perform action: (() -> Void)? = nil)`,
   `onDisappear(perform action: (() -> Void)? = nil)`,
   `onChange<V: Equatable>(of value: V, initial: Bool = false, _ action:
   @escaping (_ oldValue: V, _ newValue: V) -> Void)` and
   `onChange<V: Equatable>(of value: V, initial: Bool = false, _ action:
   @escaping () -> Void)`, all on `extension ElementGroup`, all returning
   `LifecycleScope<Self>`. The closures are plain (not `@Sendable`, not
   annotated `@MainActor`): written in a `@MainActor` element they inherit its
   isolation, are stored in a `@MainActor` value and are called on the main
   actor only; a guard (`theLifecycleSpellingsTypecheckFromAnExternalModule`,
   `typecheckFile`, plain import, `SA-P`) proves an external module can call
   a `@MainActor` model from each.
2. **Shape.** `LifecycleScope<Content: ElementGroup>: ElementGroup`, with
   `extension LifecycleScope: ProposalElementGroup where Content:
   ProposalElementGroup`, is **layout- and identity-transparent** —
   `TransactionScope`'s shape (`AN-Y`): `parent` and `cursor` forwarded
   unchanged, no layout node, no `ModifiedContent` layer, no cursor index.
   SwiftUI's modifiers carry no identity, and neither does this one: adding or
   removing a lifecycle modifier moves no `@State`, focus or `$anim`
   baseline, and `MC-A`/`MC-C`/`MC-P` numbering is untouched.
3. **No `Element` group-default hook is added**, so `MC-B`/`LR-AA`'s
   mirroring (per layer in `ModifiedContent`, in `AnyElement`'s group entry)
   is not triggered, and `Handlers` does not grow (`HandlerShape`/
   `HandlerFingerprint` unchanged).
4. **A legacy `Self`-returning decoration written after a lifecycle modifier
   does not compile** (`Text("a").onAppear {}.onClick {}`; measured against
   `TransactionScope` at `047f0ab`: "value of type 'TransactionScope<Text>'
   has no member 'onClick'", and `.padding(4)` likewise; `.frame` compiles).
   SwiftUI accepts any order — divergence **120**, pinned by the negative
   guard `aLegacyDecorationAfterALifecycleModifierDoesNotCompile`. Write the
   decoration first; the typed vocabulary's modifiers and every
   `ElementGroup` wrapper (`.frame`, `.background(alignment:content:)`,
   `.overlay`, `.id`) compile after it. **Amended by `LC-S` item 7:** for
   the same reason a lifecycle modifier cannot be a window's root —
   `App.openWindow<Root: Element>` takes an `Element` — so wrap the root in a
   container (`openWindow(…) { Column { content.onAppear { … } } }`); pinned
   by `aLifecycleModifierOnAWindowRootNeedsAContainer` (guard 9.4), recorded
   in divergence 120's row.

**Reasoning.** The transparent scope is the one shape the codebase already
pins for a modifier with no layout and no identity (`TransactionScope`,
`EnvironmentScope`); a `ModifiedContent` layer would add an id level SwiftUI
does not have and reset state when the modifier is added. Making the scope a
`StyledElement` forwarder to admit decorations after it would make it an
`Element`, with the group-default and lowering hazards `MC-B` names.

**Cost if wrong.** If a port needs a decoration after a lifecycle modifier
often, the fix is the same one `.animation(_:value:)` and `.environment` owe
— a forwarding conformance for all three scopes at once, not a change here.

## LC-C — Presence: built in this frame's layout, by identity

**Ruling.**

1. **An element is present in a build when its `LifecycleScope` reaches
   `requestGroupLayout` (or the typed entry) in that build** — **and its
   content registers at least one node there** (amended by `LC-P` item 1:
   a modifier on an empty `ForEach` is absent, `A6`). `appear` =
   present this build, absent the last completed build; `disappear` = the
   reverse. Nothing about pixels: a `.hidden()`, opacity-0, zero-size or
   clipped-out element is present (probe `E3`, `E4`, `E5`), and toggling its
   opacity fires nothing (`E4`).
2. **The key** is the scope's position — `GlobalElementID.child(of: parent,
   at: cursor, name: nil)` — with a `.named("$lifecycle<depth>")` child
   (`depth` = the number of enclosing lifecycle scopes, so two stacked at one
   position keep two entries; `A3`), plus an **occurrence** counting earlier
   scopes with that key in the build (`SurfaceRegistry`'s rule, `MV-M` item
   5) so two siblings sharing one `.id` (divergence 72) are two elements. The
   key is a store key, never a `StateTable` id: no `noteNamed` is owed (the
   precedent is `AN-Y`'s `$anim-value<depth>` and `TransitionStore`'s
   `$transition`), and the seven reserved names do not move.
3. **Agreement with `@State` resets.** Every evaluated reset changes presence
   at the same build: an `if` that goes false (`ID-C`) — absent; a renamed
   `.id` (`ID-R`) — the old key absent, the new present (`E2`, `C10`); a loop
   that drops an element (`DD-C`) — absent. **The one place they part is a
   `List` row scrolled out of its window**: it is not built, so it
   **disappears**, and returns as an appearance — while its `@State` is kept
   for `TB-AH`'s two generations. That is SwiftUI's answer for a lazy
   container (`S1` List, `S2` LazyVStack: rows that leave the viewport run
   onDisappear; `S3`, a plain `VStack`, runs nothing), and `TB-AH` is
   unchanged.

**Reasoning.** Presence by build is the only definition the frame can compute
in O(scopes) with no new walk, and the probe's separating arms (`E3`–`E5`
against `E1`; `S1`/`S2` against `S3`) show SwiftUI's own definition is
hierarchy membership, not visibility.

**Cost if wrong.** A caller that wanted "visible" (a row inside a
non-windowed `ScrollView` scrolled away) gets nothing — as in SwiftUI (`S3`).

## LC-D — The store: `LifecycleStore`, window-owned, not `StateTable`

**Ruling.** A new `LifecycleStore` (`Sources/MetalUI/Lifecycle.swift`), held
by the window's `AnimationStore` beside `transitions` and `rasters` — so a
`Window`'s frames share one and a headless `renderFrame` or a test-built
`Frame` gets a fresh one with no `Frame` initialiser change. It holds this
build's and the last completed build's entries (each: the key, its
registration order, its owner id, its latest `onAppear`/`onDisappear`
closure, its `onChange` record — the previous value and `isEqual`), the
parked disappearances (`LC-H`) and the events the window has not yet run.
**Every entry a build does not touch is dropped at the end of that build**
(`AN-AB`'s rule): content that leaves and returns compares against nothing
(`C10`), a `List` row out of its window drops its previous value. Nothing here
is a `StateTable` entry, a `$`-slot or a reserved name
(`theSevenRetentionSlotsAreMutuallyDistinct` untouched).

**Reasoning.** `onChange`'s previous value and the presence sets are exactly
`AnimationStore`'s kind of state: per identity, one frame of memory, wrong
under `TB-AH`'s two-generation retention (a value kept while a row is out
would fire a stale change on return, which `S1`'s re-created row does not).

**Cost if wrong.** If retention past one frame is ever wanted, the store is
the one place to change, and no `StateTable` rule moves either way.

## LC-E — When actions run: after the build, outside every phase; one settle build

**Ruling.**

1. **Collected during the build, run after it.** Layout notes presence and
   compares `onChange` values; `Frame.render` closes the build into events
   **after `stateTable.sweep()`** (`LC-I` needs the sweep's departed values,
   `LC-H` the ghosts `paintGhosts` dropped). The window runs them in
   `drawFrameIfNeeded`, **after `buildAndAdoptFrame` returns** — outside every
   phase, outside `Frame.render` and **outside `withObservationTracking`'s
   apply closure**, so an `@Observable` write reaches the armed session and
   is never the lost dirty `RX-S` describes. Each action runs under
   `StateDispatch.dispatching(to: owner)` (`owner` = the scope's position),
   so `@State`/`Binding`/`@Observable` writes are legal as in an input
   handler and resolve the right occurrence (`ID-F`).
2. **One settle build.** If running the events dirtied the window (the drain
   saves `needsRedraw`, clears it, runs, reads it, and restores the or of
   both), the window builds once more inside the same `beginFrame()` — after
   `CR-Q`'s block — and runs that build's events too; that second drain's
   writes schedule the next frame. So an `onAppear` that writes is presented
   in the **first** frame, as SwiftUI's is (`F1`, `F2b`: the first draw shows
   `v=1`), and an action that writes nothing costs no second build.
3. **Bounded.** At most one settle build per drawn frame (plus `CR-Q`'s on
   the first frame). SwiftUI settles a chain to a fixed point inside one turn
   (`F3`, `C9`); MetalUI runs two levels of actions per drawn frame and
   presents the first level's writes — each later level's writes are
   presented one frame later. Divergence **121**. An action cannot make one
   frame loop forever; a chain that never settles redraws every frame, as
   any write from input does.
4. **Not re-entrant.** A drain in progress (`isDrainingLifecycle`) does not
   start another: a frame an action draws synchronously builds normally and
   leaves its events queued for the outer drain's next pass or the next frame.
5. `finishFrame` failing leaves nothing lost: events are taken only by a
   drain, and a drain runs only after a build.

**Reasoning.** The phase-write rule exists for two measured reasons — a write
from a phase keeps the display link awake, and an `@Observable` write inside
the tracked build is lost — and running after `buildAndAdoptFrame` avoids
both. The settle build is `CR-Q`'s precedent (a second build inside one
`beginFrame()` to avoid presenting a frame SwiftUI never draws), applied only
when an action actually wrote. gpui's comparison (not evidence):
`Window::on_next_frame`/`defer` run callbacks after the frame and schedule a
redraw — the one-frame-late answer MetalUI would give without the settle.

**Cost if wrong.** If the double build shows in a profile, dropping the settle
build is one deletion: actions then present one frame late (a one-frame flash
of the pre-action state) and divergence 121 widens to the first level.

## LC-F — Order: changes, then appears, then disappears; each in reverse pre-order

**Ruling.** One build's events run in three buckets, in this order:

1. **`onChange`** actions of elements present in both builds (`C12`: the
   existing view's change runs before the inserted view's appear);
2. **appearances** — `onAppear` actions and `onChange(initial: true)` first
   firings, together (`C3`/`C3b`: they interleave in modifier order);
3. **disappearances** — `onDisappear` actions of the last build's elements
   (`A4`, `A5`, `E2`, `C10`: the new content appears before the old
   disappears).

Within a bucket, **reverse registration order** — registration is the build's
pre-order walk (a scope notes itself before its content), so reversed it is
children before parents, later siblings before earlier ones, inner modifier
before outer (`A1`, `A2` and `A3` insertion; `A1`, `A3` removal; `C8` child
before parent; `C11` b before a). Disappearances use the last build's order.

**Where SwiftUI differs** — divergence **122**: three siblings removed by
three separate `if`s disappear in forward order in SwiftUI (`A2`: s1, s2, s3;
MetalUI s3, s2, s1), and a lazy container's scroll runs its rows in an order
that changes from run to run (`S1`/`S2`, disappears mostly first); MetalUI's
one rule gives appear-then-disappear, reverse pre-order, every time.

**Reasoning.** One deterministic rule that matches eight of the probe's arms
beats copying an order SwiftUI itself does not hold stable (`S2`'s three runs
disagree).

**Cost if wrong.** An app depending on sibling disappearance order is
depending on something SwiftUI does not keep either.

## LC-G — `onChange` semantics

**Ruling.** Compared once per build against the value the same key stored in
the last completed build, with the `isEqual` closure `.animation(_:value:)`
uses (`{ ($0 as? V) == value }`):

1. A change fires the action with (old, new) (`C1`) — the zero-parameter form
   calls its closure (`C2`). The closure fired is this build's.
2. A first sighting stores and does not fire (`C4`), unless `initial: true`,
   which fires (value, value) in the appearance bucket (`C3`: 5, 5).
3. Builds coalesce writes: two writes between frames fire once with the first
   old and the last new (`C5`: 0 → 2); a change undone, or a write of the same
   value, fires nothing (`C6`, `C7`).
4. A new identity compares against nothing (`C10`); an element inserted by the
   change does not fire (`C12`); an element removed by it is not built and
   does not fire (`C13`).
5. `Equatable` only; a non-`Equatable` value does not compile (guard
   `aNonEquatableOnChangeValueDoesNotCompile`).

**Reasoning.** Each clause is a probe arm; per-build comparison is SwiftUI's
per-update comparison at MetalUI's granularity.

**Cost if wrong.** None beyond the probe's coverage: a value type whose `==`
is expensive is compared once per build per scope, as in SwiftUI.

## LC-H — Transitions: a disappearance waits for its removal ghost

**Ruling.** When a disappearing key's position equals or descends from the
position of a removal ghost alive at the end of the build (`TransitionStore`,
`AN-AE`), its `onDisappear` is **parked** on that ghost and runs in the first
build after the ghost ends (`T1`, `T3` — onDisappear outside the transition —
and `T5` — an untransitioned child of a fading parent, child first). **If the
content returns while parked** (the ghost is removed by the insertion,
`TransitionStore.afterLayout`), the parked disappearance and the returning
appearance are **both cancelled** (`T4`: SwiftUI runs neither). A removal with
no animation makes no ghost and disappears at once (`T0`); an insertion
appears at once, whatever its animation (`T2`).

**Amended by `LC-P` item 7:** a removed group that painted nothing makes no
ghost (`TransitionStore.afterLayout` needs captures), so its `onDisappear`
runs at once.

**Not moved:** the re-inserted content's `@State` is fresh (`ID-C` reset it at
the removal), where SwiftUI keeps the view (`T4`) — a pre-existing difference
this branch records as divergence **123** and does not change.

**Reasoning.** `T1`/`T3`/`T5` are unambiguous; the ghost is the one thing in
MetalUI whose lifetime is the transition's.

**Cost if wrong.** A monitor stopped in `onDisappear` runs until the fade
ends (`.default` is a 0.5 s spring) — SwiftUI's own behaviour (`T1`).

## LC-I — `onDisappear` reads the departed element's state as it was

**Ruling.** SwiftUI's `onDisappear` reads its view's `@State` as it was and a
write there is lost (`D1`: reads 7; the content inserted again reads 0).
MetalUI's `sweep()` has already reset the departed subtree (`ID-C`/`ID-R`/
`DD-C`) by the time the drain runs, so:

1. **`StateTable` keeps the values its sweep's resets delete**, as a
   `DepartedState { values; roots }`, only when the last build held at least
   one `onDisappear` (a `Bool` the store sets before the sweep), handed to
   the store right after the sweep and attached to that build's
   disappearance events (a parked event keeps its own).
2. **While a disappearance runs**, `StateTable` reads through that overlay
   (`peek` answers an overlay value first) and a write to an id at or under
   one of its `roots` lands in the overlay only — never in `storage`, never
   firing `onWrite` — so the departed identity's state is never resurrected
   and content that returns starts fresh, as `ID-C` promises.
3. **No retention rule moves.** Entries are deleted at the same sweep as
   before; no live read changes outside a disappearance; a `List` row out of
   its window has nothing departed and reads its live, retained state.

**Reasoning.** Without it, an `onDisappear` would read the reset (initial)
values of state its element wrote — `D1`'s `n = 7` would read 0.

**Corrected by `LC-S` item 1** (this paragraph said the overlay fixes
`@State var monitor = Monitor(); .onAppear { monitor.start() }; .onDisappear
{ monitor.stop() }`, the SMK shape; refuted by measurement): a `@State`
default that is **never written** is not in the table at all — `peek` answers
`nil` and every build re-seeds it from the new default — so the overlay has
nothing to keep, and `onAppear` (build 1) and `onDisappear` (the last present
build) reach different instances (`["start 1", "stop 4"]` after four builds).
SwiftUI keeps the default's first evaluation (`D2`). Divergence **125**; the
working spelling assigns the instance in `onAppear` (`monitor = Monitor();
monitor?.start()`), which writes the slot, so it is kept while present and
read here at the disappearance — or holds it in an `@Observable` model.

**Cost if wrong.** Memory for one build's departed values (more only while a
ghost holds a parked event), paid only when an `onDisappear` exists.

## LC-J — Window close, app quit, headless frames

**Ruling.**

1. **Closing a window runs every present element's `onDisappear` once**, and
   every parked one, in reverse pre-order, under `StateDispatch`, then
   nothing more (`W3`: the content leaving its host runs onDisappear).
   `App`'s `onClose` closure calls the window's
   `runDisappearancesForClose()` before AppKit's terminate; both platforms
   already call `onClose` (`AppKitPlatform.swift:792`, `SDLPlatform.swift:528`).
   A `Window` built without `App` runs nothing at close (nothing calls it).
2. **Ordering a window out runs nothing** (`W1`); MetalUI has no such call.
   **`NSWindow.close()` with the host retained runs nothing in SwiftUI**
   (`W2`) — MetalUI's closed window discards its content, which is `W3`'s
   case, not `W2`'s.
3. **App quit runs nothing**: terminate (AppKit) and `SDL_EVENT_QUIT`'s
   `stop()` close no window. SwiftUI's app-scene quit was not probed.
4. **A headless `renderFrame` runs no action** — no window, no drain; its
   events are dropped with its fresh store (`MV-H`'s rule for draw requests).

**Reasoning.** The SMK monitor must stop when its window closes; `W3` is the
probe arm whose shape matches a MetalUI close.

**Cost if wrong.** An app that expected no callback at close sees one more
`onDisappear` — harmless for a stop/cleanup action, which is what it is for.

## LC-K — Headless driving

**Ruling.** Tests drive lifecycle through `makeFakeWindow` and
`drawFrameIfNeeded()` (writes from input closures or a test's direct write
before the frame), transitions through `FakePlatformWindow.simulateTick
(timestamp:)` with `startsDisplayLink: true`, close through `App` over
`FakePlatform` invoking the fake window's `onClose`. Observables: action
counters in the test; `Window.lastDrawBuildCount` (internal: builds in the
last `drawFrameIfNeeded`, 1 or 2, `CR-Q` 3); `LifecycleStore.count`,
`.lastFrameWork`, `.parkedCount`; `StateTable.lastDepartedValueCount`. **No
test sleeps.**

## LC-L — `.task` is deferred: the SDL loop starves main-actor tasks

**Ruling.** `.task(perform:)` and `.task(id:priority:_:)` are **not built**.
A main-actor `Task` created while the main thread spins a loop that never
enters the run loop does not run at all (probe
`swift-main-actor-task-loop.swift` `B1`, macOS and `swift:6.4-noble`: `task
ran=false`; `P0`, the run-loop shape AppKit's `NSApp.run` gives, runs it).
`SDLPlatform.run()` is that loop on Linux (and, by the same Swift code, on
Windows — not measured). Building `.task` would ship a modifier that works on
macOS and silently never starts on Linux/Windows. **Owner: the plan's gap 10**
(the SDL run loop draining the main queue); `B2` measured the candidate repair
(one `RunLoop.main.run(mode: .default, before: .distantPast)` per iteration
runs the task) for that owner to build and test in `SDLPlatform.run()` itself.
SwiftUI's answers for the owner: `.task` starts after `onAppear` and is
cancelled after `onDisappear` (`K1`); `.task(id:)` starts the new task, then
cancels the old (`K2`).

**Cost if wrong.** None to this branch; the port starts its monitor from
`onAppear` (a synchronous start of its own async work) until the owner lands.

## LC-M — Performance: counted, O(lifecycle scopes), zero without them

**Ruling.** `LifecycleStore.lastFrameWork` counts, per completed build,
**registrations + entries visited by the end-of-build diff** (one pass over
this build's entries for appearances, one over the last build's for
disappearances). A steady build with K scopes does **3K**; a tree with no
lifecycle modifier does **0** and skips the diff (both sets empty), and no
element without a lifecycle modifier is touched — the store is reached only
from `LifecycleScope`. `StateTable` retains departed values only when an
`onDisappear` exists (`LC-I`). Pinned on a branching tree with literals
derived before the run (`SA-M`).

## LC-N — Demo and human checks

**Ruling.** A looks-demo section, `looksLifecycleSection()`, its own function
passed to `looksRoot` (the 1 MB stack rule): a toggle that inserts and removes
a tile (`onAppear`/`onDisappear` counters), the same tile under a 0.8 s
`.opacity` transition (the disappear counter moves when the fade ends), and a
stepper whose value an `onChange` counts. Counters are drawn as text and as a
bar 8 pt per count, so a test reads them. Not in the default demo: the
fourteen offscreen images and `Expected.swift` do not move. **Human-checks
group T** — T1: the transitioned tile's disappear counter increments when
the fade ends, not on the click (a look: timing on a real display link).

## LC-O — Lanes

**Ruling.** Two lanes, disjoint files, run in order (lane 2 needs lane 1's
API). **Lane 1** (Opus): `Sources/MetalUI/Lifecycle.swift` (new),
`AnimationStore.swift`, `Frame.swift`, `TransitionStore.swift`,
`StateTable.swift`, `Window.swift`, `App.swift`, `Tests/MetalUITests/
LifecycleTests.swift`, `LifecycleCompileGuards.swift` (new),
`docs/divergences.md` (rows 120–123),
`docs/probes/closeout-inventory-map.tsv`, `closeout-public-api.tsv`. **Lane 2**
(Sonnet for docs, Opus for the SDL test): `Sources/MetalUIDemoContent/
LooksDemo.swift`, `Tests/MetalUITests/LooksLifecycleDemoTests.swift` (new),
`Backends/SDL/Tests/MetalUISDLTests/SDLLifecycleTests.swift` (new),
`docs/api-overview.md`, `docs/migration.md`,
`docs/verification/human-checks.md` (group T). The Record phase
(CLAUDE.md/AGENTS.md, README, record §76, record index, and record §04's
sections for divergences 120–123 — an existing record file) follows both.

## LC-P — The critic pass: two probe arms added, presence needs content, counts and pins corrected

**Ruling.** The committed design (`98703df`) was attacked against the
branch's rules. The SwiftUI probe was re-run unchanged (one run): every arm
outside `S1`/`S2` byte-identical to the design's reading, `S1`/`S2`'s row
sets equal per step with a different order, as its header says; the runtime
probe was re-run on macOS and in `swift:6.4-noble`: its three recorded lines
byte for byte. Findings, each fixed here or in the spec:

1. **Presence needs content (new arms `A6`, `A6b`).** `LC-C` left open what a
   modifier on a group of several views does. SwiftUI fires it **once per
   group, not per child**, and **only while the group produces at least one
   view**: `ForEach(0..<n).onAppear/.onDisappear`, n 0 → 3 → 1 → 0 → 2, logs
   `appear` at 3, nothing at 1, `disappear` at 0, `appear` at 2, and nothing
   for the empty first build; a two-view `Group` under an `if` logs one
   appear and one disappear. The design would have fired an empty
   `ForEach`'s `onAppear` on the first build (`ID-B`: a loop takes its slot
   whether or not it produces content). **Amended:** the scope reserves its
   registration order before recursing and notes its entry only when its
   content returned a non-empty node list (spec §3.1); an empty group has no
   entry, so it does not appear, its `onChange` compares nothing, and the
   content's return compares against nothing (`LC-D`). Test 1.12.
2. **A lifecycle modifier outside `.id` (new arm `E2b`).** CLAUDE.md's
   "`.id()` outermost" governs `ModifiedContent` layers; a transparent scope
   outside an `IdentifiedGroup` compiles (as `TransactionScope` does) and the
   design's key is the position without the name. SwiftUI agrees: `Text("x")
   .id(k).onAppear{}.onDisappear{}.onChange(of: v){}`, `k` and `v` changed
   together, logs only `change old=0 new=1` — no appear, no disappear. Not a
   divergence; pinned by test 1.11.
3. **The probe header did not carry the recorded output** (`SA-O`), only a
   reading. The second of the critic's two final runs (the design's arms plus
   `A6`, `A6b`, `E2b`; the two byte-identical outside `S1`/`S2`) is now in
   the header verbatim, with the comparison above.
4. **The expected count double-counted `Backends/SDL`.** Tests 10.2 and 10.3
   are in the separate `MetalUISDL` package, which the 2376 does not count;
   corrected in spec §5.3 (lane 1 now 43 tests + 3 guards with 1.11 and 1.12;
   main package 2423, SDL + 2).
5. **Test 5.4 had no mutation of its own** — its red rested on others'. It now
   has one: `peek` under the overlay answers only from the overlay, which
   turns a `List` row's retained live read into the initial value. (Test 1.9
   stays a composition test reddened by 1.1's mutation, as the spec says — a
   per-container mutation would be a mutation of `Component`,
   `EnvironmentScope` or `Deferred`, files outside both lanes.)
6. **A write in an `onDisappear` run at window close** dirties a closed
   window: AppKit's `windowWillClose` invalidates the display link before
   `onClose`, SDL sets `closed` (so `linkRunning` is false) before it, and
   App quit follows on AppKit. Nothing draws; the write is lost with the
   window. Stated, not a new rule.
7. **A removed transitioned group that painted nothing** (no captures: an
   empty or fully clipped group) makes no ghost, so its disappearance is not
   parked. Unprobed against SwiftUI; recorded on `LC-H`, no divergence until a
   probe shows one; owner none.
8. **`T4`'s `onChange`.** Content re-inserted mid-ghost compares its next
   change against nothing (its entry was dropped at the removal build), where
   SwiftUI's kept view compares against its old value — folded into
   divergence 123's row (spec §4) rather than a new label.
9. **Observation sessions under the settle build.** When only a `@State`
   write dirtied (the first build's session unconsumed), the settle build arms
   a second session; both read the sentinel and are flushed by the next
   frame's tick, so outstanding sessions stay bounded at two — exactly what
   `CR-Q`'s second build already does. Not a defect.
10. **Rejected: splitting lane 1.** Lane 1 is large (the store, the scope,
    `StateTable`'s overlay, the window drain, transitions parking, close, 46
    pinned declarations), but every piece meets in `LifecycleStore.endFrame`
    and `drainLifecycle`; any split shares `Lifecycle.swift` or
    `LifecycleTests.swift` between lanes, which `LC-O` and CLAUDE.md's
    disjoint-files rule forbid. Lanes stay as `LC-O` gives them.

Checked and found sound (no change): no new `Platform`/`PlatformWindow`/
`WindowRenderer` requirement, no Apple type in a portable surface, no
primitive or shader change, no C enum, no `Handlers` growth, no
`StateTable` slot (`theSevenRetentionSlotsAreMutuallyDistinct` untouched),
`MC-A`/`MC-C`/`MC-P` untouched; the looks demo is outside the fourteen images
and `Expected.swift`; `StateDispatch.resolve` walks the owner's ancestors, so
an action written in a `Component`'s body and dispatched to a scope inside it
reaches the `Component`'s `@State` (`ID-F`); every `Element` returns exactly
one node (`Deferred` included), so item 1 changes nothing for a single
element. `.task` stays deferred (`LC-L`): its probe re-ran identically on
both platforms.

## LC-Q — Lane 1's implementation findings: a List's first frame, cancellation under a ghost, the drain loop

**Ruling.** Lane 1 implemented the design (`LifecycleTests` 1.1–8.2,
`LifecycleCompileGuards` 9.1–9.3) and measured four places where it was
incomplete or wrong. Each is fixed here and in the spec.

1. **A `List`'s first frame appears every row — divergence 124.** `List`'s
   cold-frame rule builds every row while its scroller has no measured viewport
   (`List.visibleRange`, "building everything on that first frame costs one slow
   frame instead of a flash"). Presence is membership in a build (`LC-C`), so
   every row's `onAppear` runs on the first build and the rows outside the
   window the next build measures run `onDisappear`. Measured: a 12-row list in
   a 20-point viewport logs twelve appearances and nine disappearances (rows
   3…11); when the rows' `onAppear` writes `@State`, both halves run inside the
   first `drawFrameIfNeeded` (the settle build is the windowed one), else the
   disappearances run on frame two. SwiftUI's lazy `List` creates only the rows
   in view (`S1`). Not fixed here — the cold-frame rule is `List`'s, outside
   `LC-O`'s files, and changing it re-opens the flash it exists to prevent;
   recorded as divergence **124**, pinned by
   `aListsFirstFrameAppearsEveryRowAndTheNextBuildDisappearsTheRowsOutsideItsWindow`
   (test 1.5b, a forty-fourth lane-1 test). Tests 1.5 and 5.4 read the visit
   count the row last wrote instead of a literal, because the cold frame adds
   one appearance before the scroll.
2. **`LC-H`'s cancellation must cover every key under the ghost, not only the
   parked ones.** The design parked only disappearances that have an
   `onDisappear`; a returning element's `onAppear` sits in a different scope
   (another depth, or a descendant) whose key was never parked, so it ran on
   re-insertion — measured by test 6.4: `log == ["appear"]` and the tile's
   nested `@State` re-grown to 60 by its own `onAppear`. **Amended:** a live
   ghost holds every key that left under it (`ParkedGhost.keys`, with or without
   an `onDisappear`) plus its parked events; a held key present again cancels
   its appearance (and `initial: true` firing) and its parked event. Kept only
   while a ghost is live, so a tree with no transition holds nothing.
3. **The drain loops until no events are left** (`LC-E` item 4). The design
   took the events once; an action that draws a frame synchronously leaves that
   build's events in the store, and a drain that took once would leave them for
   a next frame that a clean window never draws (test 4.6). Each pass's events
   come from a build that already happened, so the loop is bounded by the builds
   the actions drew; the re-entrancy guard keeps the nested build's events for
   the outer pass, after the action that drew it (test 4.6's order `[first
   begin, first end, inserted]`).
4. **`onChange` compares in `endFrame`, not in `note`.** One place builds all
   three buckets, so an `initial: true` firing is subject to the same `LC-H`
   cancellation as an appearance; the counted work is unchanged (`LC-M`: K
   registrations, one visit per entry of each build).

Also measured: the control arm of test 5.3 (an `if` removing a counter beside an
`onDisappear`) keeps **4** departed values, not the 1 the design assumed — the
subtree's other entries are kept too; the test asserts `> 0` there and `== 0`
for the arm the ruling is about.

**Cost if wrong.** Item 1 is a recorded divergence with an owner; items 2–4 are
internal to `Lifecycle.swift` and `Window.drainLifecycle`.

## LC-R — Lane 1's measured mutation table

**Ruling.** Every mutation in spec §5 was applied on `feat/lifecycle` after the
implementation commit (`047a0fa`, docs `001ceb1`), one at a time, by a script
that edits the source, runs `swift build --build-system native --build-tests`
and the **full unfiltered** `swift test --build-system native --no-parallel`
(6-minute hang limit — none hung), restores the file from a copy and checks
`git status --short` (clean after every one). Unmutated baseline: **2423 tests
in 3 suites passed**. Every row below printed `Test run with 2423 tests in 3
suites`; the count is the tests reddened, each named.

| # | spelling mutated | result | tests reddened |
|---|---|---|---|
| M1.1 | `endFrame`: `} else if !cancelled.contains(key) {` → `}` + `if !cancelled.contains(key) {` (every current key appears) | 17 tests | `aChainOfAppearancesSettlesOneLevelOfWritesPerPresentedFrame`, `aFirstSightingFiresOnlyWithInitialTrue`, `aGroupModifierFiresOncePerGroupAndOnlyWhileItHasContent`, `aLifecycleModifierWrittenOutsideIdKeysOnThePosition`, `aListRowScrolledOutDisappearsReturnsAsAnAppearanceAndKeepsItsState`, `aListsFirstFrameAppearsEveryRowAndTheNextBuildDisappearsTheRowsOutsideItsWindow`, `aSettledWindowGoesIdle`, `aWriteInOnDisappearIsLostAndReturningContentStartsFresh`, `anActionThatDrawsAFrameDoesNotDrainReentrantly`, `anIfThatInsertsContentRunsItsOnAppearOnce`, `hiddenTransparentZeroSizedAndClippedElementsAppear`, `initialTrueFiresWithAppearInModifierOrder`, `insertionRunsChildrenBeforeParentsAndLaterSiblingsFirst`, `lifecycleModifiersFireInsideAComponentAnEnvironmentScopeAndADeferred`, `onDisappearReadsItsOwnStateAsItWasLastFrame`, `reinsertingDuringTheGhostRunsNeitherCallbackAndStartsWithFreshState`, `removalRunsInReversePreOrderEvenForSeparatelyRemovedSiblings` |
| M1.2 | previous loop: `guard current[key] == nil, false else { continue }` (no disappearance) | 16 tests | `aChangedIdRunsTheNewAppearBeforeTheOldDisappear`, `aGroupModifierFiresOncePerGroupAndOnlyWhileItHasContent`, `aListRowScrolledOutDisappearsReturnsAsAnAppearanceAndKeepsItsState`, `aListRowsOnDisappearReadsItsRetainedLiveState`, `aListsFirstFrameAppearsEveryRowAndTheNextBuildDisappearsTheRowsOutsideItsWindow`, `aParentAndItsChildUnderOneGhostDisappearTogetherChildFirst`, `anAnimatedRemovalDisappearsWhenItsGhostEnds`, `anIfThatRemovesContentRunsItsOnDisappearOnce`, `anOnDisappearOutsideTheTransitionAlsoWaits`, `anUnanimatedRemovalDisappearsAtOnceAndAnAnimatedInsertionAppearsAtOnce`, `changesRunBeforeAppearsAndAppearsBeforeDisappears`, `closingTheWindowAlsoRunsParkedDisappearances`, `onDisappearReadsItsOwnStateAsItWasLastFrame`, `reinsertingDuringTheGhostRunsNeitherCallbackAndStartsWithFreshState`, `removalRunsInReversePreOrderEvenForSeparatelyRemovedSiblings`, `stackedLifecycleModifiersKeepSeparateEntriesInnerFirst` |
| M1.3 | appearances appended after the disappearances (buckets 2 and 3 swapped) | 2 tests | `aChangedIdRunsTheNewAppearBeforeTheOldDisappear`, `changesRunBeforeAppearsAndAppearsBeforeDisappears` |
| M1.4 | both entries: note only when `!nodes.allSatisfy(pass.frame.isHidden)` (paint's gate: hidden nodes skip) | 1 tests | `hiddenTransparentZeroSizedAndClippedElementsAppear` |
| M1.5 | previous loop: skip an `onDisappear` when `departed == nil` (a List row's scroll resets nothing) | 3 tests | `aListRowScrolledOutDisappearsReturnsAsAnAppearanceAndKeepsItsState`, `aListRowsOnDisappearReadsItsRetainedLiveState`, `aListsFirstFrameAppearsEveryRowAndTheNextBuildDisappearsTheRowsOutsideItsWindow` |
| M1.6 | `Key(scope:occurrence: 0)` | 1 tests | `twoSiblingsSharingOneIdAppearTwice` |
| M1.7 | `"$lifecycle"` (depth dropped) | green | — |
| M1.8 | untyped entry: `cursor += 1` after `let start = cursor` | 4 tests | `aParentAndItsChildUnderOneGhostDisappearTogetherChildFirst`, `addingALifecycleModifierMovesNoIdentity`, `anOnDisappearOutsideTheTransitionAlsoWaits`, `reinsertingDuringTheGhostRunsNeitherCallbackAndStartsWithFreshState` |
| M1.10 | typed entry's `noteLifecycle` block deleted | 1 tests | `theTypedProposalScopeNotesLikeTheUntypedOne` |
| M1.11 | owner and key named by the content's `elementID` (`(content as? any Element)?.elementID`) | 1 tests | `aLifecycleModifierWrittenOutsideIdKeysOnThePosition` |
| M1.12 | both entries: `if let write {` (noted when empty) | 1 tests | `aGroupModifierFiresOncePerGroupAndOnlyWhileItHasContent` |
| M2.1 | `appearances.sort { $0.order < $1.order }` | 3 tests | `initialTrueFiresWithAppearInModifierOrder`, `insertionRunsChildrenBeforeParentsAndLaterSiblingsFirst`, `stackedLifecycleModifiersKeepSeparateEntriesInnerFirst` |
| M2.2 | `disappearances.sort { $0.order < $1.order }` | 3 tests | `aParentAndItsChildUnderOneGhostDisappearTogetherChildFirst`, `removalRunsInReversePreOrderEvenForSeparatelyRemovedSiblings`, `stackedLifecycleModifiersKeepSeparateEntriesInnerFirst` |
| M2.3 | appearances appended before changes | 1 tests | `changesRunBeforeAppearsAndAppearsBeforeDisappears` |
| M2.4 | `initial: true` firing appended to `changes` | 1 tests | `initialTrueFiresWithAppearInModifierOrder` |
| M3.1 | `{ action(newValue, oldValue) }` | 3 tests | `aLifecycleModifierWrittenOutsideIdKeysOnThePosition`, `onChangePassesTheOldAndNewValues`, `writesBetweenFramesCoalesceAndAnUndoneChangeFiresNothing` |
| M3.2 | zero-parameter overload's action `{ _, _ in }` | 2 tests | `changesRunBeforeAppearsAndAppearsBeforeDisappears`, `theZeroParameterFormFires` |
| M3.3 | `if let change = entry.change {` (first sighting fires regardless; also 3.6's spelling) | 8 tests | `aFirstSightingFiresOnlyWithInitialTrue`, `aLifecycleModifierWrittenOutsideIdKeysOnThePosition`, `changesRunBeforeAppearsAndAppearsBeforeDisappears`, `contentThatReturnsComparesAgainstNothing`, `insertedAndRemovedElementsDoNotSeeTheChangeThatMovedThem`, `onChangePassesTheOldAndNewValues`, `theZeroParameterFormFires`, `writesBetweenFramesCoalesceAndAnUndoneChangeFiresNothing` |
| M3.4 | `true || !change.isEqual(before.value)` (every build after a write — or any — is a change) | 4 tests | `aFirstSightingFiresOnlyWithInitialTrue`, `contentThatReturnsComparesAgainstNothing`, `initialTrueFiresWithAppearInModifierOrder`, `writesBetweenFramesCoalesceAndAnUndoneChangeFiresNothing` |
| M3.5 | untouched `previous` entries copied into `current` before the swap (kept) | 13 tests | `aGroupModifierFiresOncePerGroupAndOnlyWhileItHasContent`, `aListRowScrolledOutDisappearsReturnsAsAnAppearanceAndKeepsItsState`, `aListsFirstFrameAppearsEveryRowAndTheNextBuildDisappearsTheRowsOutsideItsWindow`, `aParentAndItsChildUnderOneGhostDisappearTogetherChildFirst`, `aSteadyFrameDoesThreeUnitsOfLifecycleWorkPerScope`, `aWriteInOnDisappearIsLostAndReturningContentStartsFresh`, `anAnimatedRemovalDisappearsWhenItsGhostEnds`, `anIfThatRemovesContentRunsItsOnDisappearOnce`, `anOnDisappearOutsideTheTransitionAlsoWaits`, `anUnanimatedRemovalDisappearsAtOnceAndAnAnimatedInsertionAppearsAtOnce`, `closingTheWindowAlsoRunsParkedDisappearances`, `contentThatReturnsComparesAgainstNothing`, `removalRunsInReversePreOrderEvenForSeparatelyRemovedSiblings` |
| M4.1 | `if drainLifecycle() && false {` (no settle build) | 6 tests | `aChainOfAppearancesSettlesOneLevelOfWritesPerPresentedFrame`, `aListsFirstFrameAppearsEveryRowAndTheNextBuildDisappearsTheRowsOutsideItsWindow`, `actionsRunOutsideEveryPhaseUnderTheirElementsDispatch`, `anObservableWriteInOnAppearIsPresentedAndNotLost`, `anOnAppearWriteIsPresentedInTheFirstFrame`, `reinsertingDuringTheGhostRunsNeitherCallbackAndStartsWithFreshState` |
| M4.2 | `if drainLifecycle() || true {` (settle unconditionally) | 47 tests | `aCustomPreviewReplacesTheSnapshot`, `aFocusStateNeverWritesFromAPhase`, `aForEachThatDropsItsFocusedElementDropsFocus`, `aGrownViewportIsFilledOnTheNextFrameWithoutInput`, `aLaterPreferenceChangeAppliesOnTheNextFrame`, `aListBelowAHeaderWindowsTheRowsOnScreen`, `aListInADeferredInsideAScrollViewMeasuresNoScrollerOrigin`, `aListWhoseOriginChangesIsReWindowedOnTheNextFrame`, `aMainThreadMutationMarksTheWindowDirtySynchronously`, `aNilWrittenToAnOptionalStateReadsNilNotItsInitialValue`, `aPopoverFollowsItsAnchorWithinOneFrame`, `aPresentationKeepsItsDeclaringScopesEnvironment`, `aProposalPathPopoverPresentsPlacesAndDismisses`, `aScrollContextSurvivesALoweredViewportAcrossTwoFrames`, `aScrollViewReaderIsOneSlotWithItsOwnIdentityLevel`, `aSelfResetBelowADarkScopeReadsLightAndTheLightVariant`, `aSiblingAfterAScrollViewSeesNoScrollContext`, `aStateProjectionWritesTheOwnersStateThroughTwoLevels`, `aSteadyFrameDoesThreeUnitsOfLifecycleWorkPerScope`, `aWindowKeepsOneAtlasAcrossFrames`, `activatingBeforeTheFirstFramePublishesNoRowsUntilTheWindowIsBounded`, `anActionThatWritesNothingCostsNoSecondBuild`, `anAnimationModifierReachesOnlyItsContent`, `anExplicitThemeScopePinsTokensButNotTheScheme`, `anInitiallyPresentedPopoverAppearsOnTheSecondFrame`, `anOffScreenListRowsModelReadIsNotTracked`, `anOffThreadMutationMarksTheWindowDirtyAfterAHop`, `anOptionalStateWithANonNilInitialValueReadsItBeforeItsFirstWrite`, `anUnboundedListFrameAsksForNoExtraFrame`, `anUnboundedSelectableListPublishesButtonRowsAndABoundedOneTableRows`, `crossFrameStateSurvivesFromOneWindowFrameToTheNext`, `everyElementInOneFrameSeesTheSameTimestamp`, `focusDropsWhenItsElementIsRenamedAndDoesNotReturn`, `focusingFromInsideAFrameIsStillValidatedByTheNextFrame`, `focusingFromInsideAFrameSurvivesThatFrame`, `isFocusedDuringPaintTracksTheWindowsFocus`, `mutatingAnObservedModelMarksTheWindowDirty`, `nestedScrollViewsInnermostWinsAndPoppingRestoresTheOuterContext`, `noDepartedValuesAreKeptWithoutAnOnDisappear`, `rawOffsetPublishedDuringRequestLayoutCanExceedTheClampedRange`, `readingTheColorSchemeInEveryPhaseLetsTheDisplayLinkPause`, `scrollToReachesAnUnrealisedListRow`, `scrollViewPublishesTheCurrentOffsetAndLastFramesViewportDuringRequestLayout`, `stateAndObservableAreIndependentDirtySources`, `theObserverSetIsBoundedRegardlessOfFramesDrawn`, `thePublicWithStateHandsAnOptionalStateItsInitialValueOnFirstAccess`, `theWindowStampsItsPlatformsAppearanceAsTheColorScheme` |
| M4.3 | end of `Frame.render`: run `takeEvents()` there (inside `renderRoot`) | 10 tests | `aChainOfAppearancesSettlesOneLevelOfWritesPerPresentedFrame`, `aHeadlessRenderFrameRunsNoAction`, `aListsFirstFrameAppearsEveryRowAndTheNextBuildDisappearsTheRowsOutsideItsWindow`, `aWriteInOnDisappearIsLostAndReturningContentStartsFresh`, `actionsRunOutsideEveryPhaseUnderTheirElementsDispatch`, `anActionThatDrawsAFrameDoesNotDrainReentrantly`, `anObservableWriteInOnAppearIsPresentedAndNotLost`, `anOnAppearWriteIsPresentedInTheFirstFrame`, `onDisappearReadsItsOwnStateAsItWasLastFrame`, `reinsertingDuringTheGhostRunsNeitherCallbackAndStartsWithFreshState` |
| M4.4 | `self.drainLifecycle()` after `renderRoot(frame)` inside `withObservationTracking` | 7 tests | `aChainOfAppearancesSettlesOneLevelOfWritesPerPresentedFrame`, `aListsFirstFrameAppearsEveryRowAndTheNextBuildDisappearsTheRowsOutsideItsWindow`, `actionsRunOutsideEveryPhaseUnderTheirElementsDispatch`, `anActionThatDrawsAFrameDoesNotDrainReentrantly`, `anObservableWriteInOnAppearIsPresentedAndNotLost`, `anOnAppearWriteIsPresentedInTheFirstFrame`, `reinsertingDuringTheGhostRunsNeitherCallbackAndStartsWithFreshState` |
| M4.5 | `needsRedraw = true; return true || dirtied` | 96 tests | `aBackingScaleChangeReachesTheDisplayScaleOnTheNextFrame`, `aColourFadeOnAStyleStaticElementKeepsTheDisplayLinkRunning`, `aContinuousSurfaceKeepsTheWindowAnimatingOnlyWhilePainted`, `aCustomPreviewReplacesTheSnapshot`, `aDisablingTransactionReachesExactlyOneBuildAndRollsBack`, `aFocusStateNeverWritesFromAPhase`, `aForEachThatDropsItsFocusedElementDropsFocus`, `aGrownViewportIsFilledOnTheNextFrameWithoutInput`, `aHostAppearanceChangeSwapsTheThemeAndRepaints`, `aLaterPreferenceChangeAppliesOnTheNextFrame`, `aListBelowAHeaderWindowsTheRowsOnScreen`, `aListInADeferredInsideAScrollViewMeasuresNoScrollerOrigin`, `aListWhoseOriginChangesIsReWindowedOnTheNextFrame`, `aMainThreadMutationMarksTheWindowDirtySynchronously`, `aNaNColourSettlesAndLetsTheDisplayLinkPause`, `aNeverScrolledScrollViewPaintsNoIndicatorOnTheWindowsPreTickFirstFrame`, `aNilWrittenToAnOptionalStateReadsNilNotItsInitialValue`, `aPaletteOverrideOnTheWindowsVariantRepaints`, `aPendingGestureKeepsFramesComingOnlyWhilePending`, `aPopoverFollowsItsAnchorWithinOneFrame`, `aPresentationKeepsItsDeclaringScopesEnvironment`, `aPressRequestRunsOnClickThroughTheLastFramesHitboxes`, `aProposalAnimationKeepsTheDisplayLinkAwakeUntilItSettles`, `aProposalPathPopoverPresentsPlacesAndDismisses`, `aRealAppKitResizeDirtiesTheWindowAndTheNextFrameReflows`, `aRealAppKitWindowPublishesItsFrameAndAPressRunsOnClick`, `aReportOfTheCurrentSchemeDoesNotWakeTheDisplay`, `aRootPreferenceIsInTheFirstPresentedFrame`, `aSchemeChangeRepaintsEvenWhenBothVariantsAreTheSameTheme`, `aScrollContextSurvivesALoweredViewportAcrossTwoFrames`, `aScrollFollowingAnIdleThatPausedTheDisplayLinkStillShowsTheIndicator`, `aScrollViewReaderIsOneSlotWithItsOwnIdentityLevel`, `aSelfResetBelowADarkScopeReadsLightAndTheLightVariant`, `aSettledWindowGoesIdle`, `aSiblingAfterAScrollViewSeesNoScrollContext`, `aStateProjectionWritesTheOwnersStateThroughTwoLevels`, `aStateWriteWakesAPausedDisplayLinkThroughTheOnWriteHook`, `aSteadyFrameDoesThreeUnitsOfLifecycleWorkPerScope`, `aTransactionWhoseBodyDirtiesNothingIsNeverParkedAndCannotAnimateALaterChange`, `aTransitionKeepsTheDisplayLinkAwakeThenLeavesNothing`, `aWindowKeepsOneAtlasAcrossFrames`, `aWindowWithNoInputHandlerReportsUnhandledAndStillRepaints`, `activatingBeforeTheFirstFramePublishesNoRowsUntilTheWindowIsBounded`, `anActionThatWritesNothingCostsNoSecondBuild`, `anActivationRequestDirtiesACleanWindowAndItsNextFramePublishes`, `anAnimationModifierReachesOnlyItsContent`, `anAnimationWithAClientActivePostsNothingAndTouchesNoElement`, `anAppearanceChangeRebuildsWithTheNewScheme`, `anElementThatAsksForNothingLeavesTheWindowClean`, `anExplicitThemeScopePinsTokensButNotTheScheme`, `anIncrementRequestRunsTheAdjustmentHandler`, `anInitiallyPresentedPopoverAppearsOnTheSecondFrame`, `anObservableWriteInOnAppearIsPresentedAndNotLost`, `anObservableWriteWakesAPausedWindowAndDrawsExactlyOneFrame`, `anOffScreenListRowsModelReadIsNotTracked`, `anOffThreadMutationMarksTheWindowDirtyAfterAHop`, `anOptionalStateWithANonNilInitialValueReadsItBeforeItsFirstWrite`, `anUnboundedListFrameAsksForNoExtraFrame`, `anUnboundedSelectableListPublishesButtonRowsAndABoundedOneTableRows`, `crossFrameStateSurvivesFromOneWindowFrameToTheNext`, `everyElementInOneFrameSeesTheSameTimestamp`, `focusDropsWhenItsElementIsRenamedAndDoesNotReturn`, `focusingFromInsideAFrameIsStillValidatedByTheNextFrame`, `focusingFromInsideAFrameSurvivesThatFrame`, `hiddenIndicatorDoesNotKeepTheWindowDirtyOrTheLinkAwake`, `idleWindowPausesTheDisplayLinkAndDirtyingResumesIt`, `inputReachesTheHandlerAndTheAnswerReachesTheHost`, `isFocusedDuringPaintTracksTheWindowsFocus`, `movingFocusAndClaimingAKeyBothRedrawTheWindow`, `multipleDirtyMarksCoalesceIntoOneFrame`, `mutatingAnObservedModelMarksTheWindowDirty`, `mutatingAnUnreadPropertyDoesNotDirtyTheWindow`, `nestedScrollViewsInnermostWinsAndPoppingRestoresTheOuterContext`, `noDepartedValuesAreKeptWithoutAnOnDisappear`, `rawOffsetPublishedDuringRequestLayoutCanExceedTheClampedRange`, `readingTheColorSchemeInEveryPhaseLetsTheDisplayLinkPause`, `resizingTheWindowDirtiesItAndTheNextFrameLaysOutAtTheNewSize`, `scrollToAnAnchorLandsTheTargetAtTheAnchor`, `scrollToReachesAnUnrealisedListRow`, `scrollViewPublishesTheCurrentOffsetAndLastFramesViewportDuringRequestLayout`, `scrollingAListPostsBoundedNotificationsAndBuildsOncePerFrame`, `settingTheThemeToItsCurrentValueDoesNotWakeTheDisplay`, `skippedFrameKeepsDirtyStateAndRetriesSuccessfully`, `stateAndObservableAreIndependentDirtySources`, `theDisplayLinkStaysRunningWhileAnimatingAndPausesOnTheFrameAfterTheLastEnds`, `theFirstFrameRebuildStartsNoAnimationFromTheFirstBuild`, `theIndicatorRequestsFramesWhileFadingAndStopsWhenDone`, `theIndicatorStillFadesAndTheWindowReturnsIdleAfterWakingFromAPausedLink`, `theObserverSetIsBoundedRegardlessOfFramesDrawn`, `thePendingTooltipKeepsTheLinkAwakeOnlyWhilePending`, `thePublicWithStateHandsAnOptionalStateItsInitialValueOnFirstAccess`, `theWindowStampsItsPlatformsAppearanceAsTheColorScheme`, `theWindowStampsItsPlatformsControlActiveStateAndAChangeRepaints`, `theWindowStampsReduceMotionFromItsPlatformWindow`, `theWindowsEnvironmentReachesTheFrameAndASetRepaints`, `windowDrawsOnlyWhenDirty` |
| M4.6 | `guard !isDrainingLifecycle` deleted | 1 tests | `anActionThatDrawsAFrameDoesNotDrainReentrantly` |
| M4.7 | `while drainLifecycle() { … build … }` (settle to a fixed point) | 1 tests | `aChainOfAppearancesSettlesOneLevelOfWritesPerPresentedFrame` |
| M5.1 | `departedOverlay = nil` in `withDepartedOverlay` | 2 tests | `aWriteInOnDisappearIsLostAndReturningContentStartsFresh`, `onDisappearReadsItsOwnStateAsItWasLastFrame` |
| M5.2 | `if false, departedOverlay != nil, …` in `write` (falls through to storage) | 1 tests | `aWriteInOnDisappearIsLostAndReturningContentStartsFresh` |
| M5.3 | `retainsDepartedValues = true` | 1 tests | `noDepartedValuesAreKeptWithoutAnOnDisappear` |
| M5.4 | `withDepartedOverlay` installs an empty overlay for `nil` and `peek` answers only from the overlay | 3 tests | `aListRowScrolledOutDisappearsReturnsAsAnAppearanceAndKeepsItsState`, `aListRowsOnDisappearReadsItsRetainedLiveState`, `aListsFirstFrameAppearsEveryRowAndTheNextBuildDisappearsTheRowsOutsideItsWindow` |
| M6.1 | `if false, let ghost = liveGhosts.first(…)` (never park) | 5 tests | `aParentAndItsChildUnderOneGhostDisappearTogetherChildFirst`, `anAnimatedRemovalDisappearsWhenItsGhostEnds`, `anOnDisappearOutsideTheTransitionAlsoWaits`, `closingTheWindowAlsoRunsParkedDisappearances`, `reinsertingDuringTheGhostRunsNeitherCallbackAndStartsWithFreshState` |
| M6.2 | park only when `item.owner != position` (strict descent) | 5 tests | `aParentAndItsChildUnderOneGhostDisappearTogetherChildFirst`, `anAnimatedRemovalDisappearsWhenItsGhostEnds`, `anOnDisappearOutsideTheTransitionAlsoWaits`, `closingTheWindowAlsoRunsParkedDisappearances`, `reinsertingDuringTheGhostRunsNeitherCallbackAndStartsWithFreshState` |
| M6.3 | `held.events.map(\.event).reversed()` | 1 tests | `aParentAndItsChildUnderOneGhostDisappearTogetherChildFirst` |
| M6.4 | the held-key cancellation loop deleted | 1 tests | `reinsertingDuringTheGhostRunsNeitherCallbackAndStartsWithFreshState` |
| M6.5 | an unghosted disappearance parked under its owner (released one build later) | 9 tests | `aChangedIdRunsTheNewAppearBeforeTheOldDisappear`, `aGroupModifierFiresOncePerGroupAndOnlyWhileItHasContent`, `aListsFirstFrameAppearsEveryRowAndTheNextBuildDisappearsTheRowsOutsideItsWindow`, `aWriteInOnDisappearIsLostAndReturningContentStartsFresh`, `anUnanimatedRemovalDisappearsAtOnceAndAnAnimatedInsertionAppearsAtOnce`, `changesRunBeforeAppearsAndAppearsBeforeDisappears`, `onDisappearReadsItsOwnStateAsItWasLastFrame`, `removalRunsInReversePreOrderEvenForSeparatelyRemovedSiblings`, `stackedLifecycleModifiersKeepSeparateEntriesInnerFirst` |
| M7.1 | `window?.runDisappearancesForClose()` deleted from `App`'s `onClose` | 2 tests | `closingTheWindowAlsoRunsParkedDisappearances`, `closingTheWindowRunsEveryPresentOnDisappearOnce` |
| M7.2 | `closeAll`'s parked loop deleted | 1 tests | `closingTheWindowAlsoRunsParkedDisappearances` |
| M7.3 | `renderFrame` runs `takeEvents()` after `render` | 1 tests | `aHeadlessRenderFrameRunsNoAction` |
| M8.1 | `Element`'s default `requestGroupLayout` notes an `.appear({})` entry | 2 tests | `aSteadyFrameDoesThreeUnitsOfLifecycleWorkPerScope`, `aTreeWithNoLifecycleModifierDoesNoLifecycleWork` |
| M8.2 | `previous[key]` → `previous.first(where:)` counting each visit (a nested-loop diff) | 1 tests | `aSteadyFrameDoesThreeUnitsOfLifecycleWorkPerScope` |
| MG9.1 | zero-parameter `onChange` made internal (the plain-import guard fails; `@testable` tests still compile) | 1 tests | `theLifecycleSpellingsTypecheckFromAnExternalModule` |
| MG9.2 | an unconstrained `onChange<V>` overload added | 1 tests | `aNonEquatableOnChangeValueDoesNotCompile` |
| MG9.3 | guard fixture: `.onClick {}` moved before `.onAppear {}` in the negative | 1 tests | `aLegacyDecorationAfterALifecycleModifierDoesNotCompile` |
| M1.7b | depth dropped and `occurrence: 0` | 16 tests | `aChangedIdRunsTheNewAppearBeforeTheOldDisappear`, `aGroupModifierFiresOncePerGroupAndOnlyWhileItHasContent`, `aLifecycleModifierWrittenOutsideIdKeysOnThePosition`, `aListRowScrolledOutDisappearsReturnsAsAnAppearanceAndKeepsItsState`, `aListRowsOnDisappearReadsItsRetainedLiveState`, `aListsFirstFrameAppearsEveryRowAndTheNextBuildDisappearsTheRowsOutsideItsWindow`, `aWriteInOnDisappearIsLostAndReturningContentStartsFresh`, `anUnanimatedRemovalDisappearsAtOnceAndAnAnimatedInsertionAppearsAtOnce`, `hiddenTransparentZeroSizedAndClippedElementsAppear`, `initialTrueFiresWithAppearInModifierOrder`, `insertionRunsChildrenBeforeParentsAndLaterSiblingsFirst`, `lifecycleModifiersFireInsideAComponentAnEnvironmentScopeAndADeferred`, `onDisappearReadsItsOwnStateAsItWasLastFrame`, `reinsertingDuringTheGhostRunsNeitherCallbackAndStartsWithFreshState`, `stackedLifecycleModifiersKeepSeparateEntriesInnerFirst`, `twoSiblingsSharingOneIdAppearTwice` |

**Findings.**

1. **M1.7 is green: the depth in the key is redundant with the occurrence.**
   Two stacked scopes at one position share the scope id without the depth, and
   the occurrence (assigned in note order, inner first) keeps them two entries
   in the same order every build; no structure can change how many scopes are
   stacked at a position without changing their content's presence too. Kept
   anyway — it is the `$anim-value<depth>` precedent (`AN-Y`) and costs
   nothing — and test 1.7's mutation is **M1.7b** (depth and occurrence both
   dropped), which reddens it. A green mutant may be the correct spelling
   (`LR-X`).
2. **3.6 has no mutation of its own**: "compare an absent key against the last
   value under its owner" needs a store the design deliberately does not have
   (`LC-D`); M3.3 (fire a first sighting) reddens it, recorded as its spelling.
3. **M4.2 and M4.5 redden far outside the lane** (47 and 96 tests, each
   named in its row; an earlier draft of this item said 65 and 145, which are
   not test counts — `LC-S` item 6): an
   unconditional settle build or an always-dirty drain changes every window
   test's build count, pause and animation timing — the reason `LC-E` item 2
   settles only on a write.
4. Every guard reddened once under its mutation (MG9.1–MG9.3), each the one
   guard.

## LC-S — The fix pass: divergence 125, four pins owed, a window root

**Ruling.** The review of lane 1 found one design claim refuted, four
rulings whose clause no test pinned (each mutation green on the full suite)
and two documentation errors. Each is fixed here; nothing in
`Sources/` changes.

1. **A never-written `@State` default is re-seeded every build — divergence
   125.** `LC-I`'s reasoning is corrected (above): the SMK shape written with
   a default (`@State var monitor = Monitor()`) starts one instance and stops
   another. SwiftUI keeps the first evaluation (probe arm **`D2`**, added and
   run: `made Mon 1` … `made Mon 4`, `appear start Mon 1`, `disappear stop
   Mon 1`; the `made` lines are the separating arm — the default *is*
   re-evaluated, and discarded). Making `@State` keep its first value would
   move state retention (a never-written slot would become a stored entry,
   with every `TB-AH`/`ID-C` count that implies), which this item's
   "MUST NOT MOVE" forbids without a ruling of its own — **not done**; owner:
   none scheduled. The documented spelling is to write the instance in
   `onAppear` (`@State var monitor: Monitor? = nil; .onAppear { monitor =
   Monitor(); monitor?.start() } .onDisappear { monitor?.stop() }`) or hold it
   in an `@Observable` model. Pins: test 5.5
   `aNeverWrittenStateDefaultIsReseededSoOnAppearAndOnDisappearSeeDifferentInstances`
   (the divergence, green on arrival — it pins MetalUI's answer) and its
   separating arm 5.6 `aMonitorAssignedInOnAppearIsTheOneOnDisappearStops`
   (one instance, `["start 1"]` then `["stop 1"]`).
2. **A ghost-parked disappearance keeps its own departed state** (`LC-I`
   item 1's "a parked event keeps its own") — pinned by test 6.6
   `aGhostParkedOnDisappearReadsTheStateItsElementHad`: an `LCHolder` removed
   under a 0.6 s fade reads `a = 7` in the `onDisappear` that runs after the
   ghost ends. Mutation V1 (the parked event built with `departed: nil`).
3. **`takeDepartedState()` empties what it hands over** — pinned by test 5.7
   `eachRemovalCountsOnlyTheDepartedValuesItsOwnSweepKept`: a build that
   resets nothing counts 0, a second removal of the same shape counts the
   first's number. Mutation V3 (the clearing `defer` deleted).
4. **Close-time disappearances run under `StateDispatch`** (`LC-J` item 1) —
   test 7.1 now records `StateDispatch.owner` in a close-time `onDisappear`
   and expects the owner the same scope's `onAppear` saw. Mutation V5
   (`runDisappearancesForClose` calls `event.action()` directly).
5. **An `initial: true` firing is cancelled under a live ghost like an
   appearance** (`LC-Q` item 4) — test 6.4 gains an `.onChange(of: 5,
   initial: true)` that fires with the first appearance and not on the
   re-insertion. Mutation V14 (the initial firing outside the `!cancelled`
   check).
6. **`LC-R` finding 3's counts** read 65 and 145; the table's rows name 47
   and 96 tests. Corrected to the table.
7. **A lifecycle modifier cannot be a window's root** (`LifecycleScope` is an
   `ElementGroup`; `App.openWindow` takes an `Element`). `LC-B` item 4 and
   divergence 120 now say "wrap the root in a container"; new negative guard
   9.4 `aLifecycleModifierOnAWindowRootNeedsAContainer` (positive control:
   the same root inside `Column { }`). Mutation MG9.4 (the negative's root
   wrapped).

**Measured.** On `feat/lifecycle` at `e4f8f1d` (the fix pass's tests
committed first), each mutation applied by a script, `swift build
--build-system native --build-tests`, the **full unfiltered** `swift test
--build-system native --no-parallel` (6-minute hang limit, none hung), the
file restored with `git checkout` and `git status --short` clean after each.
Unmutated baseline: **2428 tests in 3 suites passed** (2423 + tests 5.5, 5.6,
5.7, 6.6 and guard 9.4); `FR-J no-argument frame: succeeded=true`;
`LC-B window root: positive succeeded=true; negative succeeded=false`. Every
row printed `Test run with 2428 tests in 3 suites`.

| # | spelling mutated | result | tests reddened |
|---|---|---|---|
| V1 | parked event: `Parked(key:, event: LifecycleEvent(owner: event.owner, action: event.action, departed: nil))` | 1 test | `aGhostParkedOnDisappearReadsTheStateItsElementHad` |
| V3 | `takeDepartedState()`'s `defer { departedValues.removeAll(); departedRootsKept.removeAll() }` deleted | 1 test (2 issues) | `eachRemovalCountsOnlyTheDepartedValuesItsOwnSweepKept` |
| V5 | `runDisappearancesForClose`: `event.action()` without `StateDispatch.dispatching` | 1 test | `closingTheWindowRunsEveryPresentOnDisappearOnce` |
| V14 | `} else {` with only the `onAppear` under `!cancelled.contains(key)` (the `initial: true` firing outside it) | 1 test | `reinsertingDuringTheGhostRunsNeitherCallbackAndStartsWithFreshState` |
| M5.1 | `departedOverlay = nil` in `withDepartedOverlay` (re-run for 5.6) | 5 tests | `aGhostParkedOnDisappearReadsTheStateItsElementHad`, `aMonitorAssignedInOnAppearIsTheOneOnDisappearStops`, `aWriteInOnDisappearIsLostAndReturningContentStartsFresh`, `eachRemovalCountsOnlyTheDepartedValuesItsOwnSweepKept`, `onDisappearReadsItsOwnStateAsItWasLastFrame` |
| MG9.4 | guard 9.4's negative fixture: root wrapped in `Column { }` | 1 test | `aLifecycleModifierOnAWindowRootNeedsAContainer` |

Test 5.5 pins divergence 125 and is green by design; its separating arm is
5.6 (one instance, where 5.5 reaches two).

**Cost if wrong.** Item 1 is a recorded divergence with a working spelling;
items 2–5 and 7 add pins only.

## LC-T — Lane 2's findings: a demo census, the 1 MB stack twice, the SDL test target, the count

**Ruling.** Lane 2 built the looks demo's lifecycle section (`LC-N`), tests
10.1–10.3, the API overview's Lifecycle section, the migration subsection and
human-checks group T, and measured five places the design did not foresee.

1. **`CloseoutTests` F1.3 counts the looks demo's clickable hitboxes** (ten
   since colour: nine transition buttons and the scheme toggle). The section
   adds four — its two buttons and its stepper's two halves — so the pin reads
   **fourteen**, and since the section sits above the transitions (item 2) the
   test finds the first transition button as the topmost of the nine sharing
   one left edge, not the topmost of all. An edited existing test, owed by the
   demo, not a moved rule.
2. **Placement: beside H1, not under the transitions.** Under the transitions
   the looks content measured **1000** points tall (804 at `047f0ab`), past
   the 1180 × 880 window `MetalUIDemo` opens it in; at the foot of the left
   column, 968. Beside H1's narrow column, compacted (counters two by two), it
   measures **817** — the window still holds it. Measured headless
   (`looksDemoContent()` in a 1400-point fake window, the extent of every rect
   narrower than the window).
3. **The 1 MB thread overflowed twice** (`everyProductionTreeBuildsOnAOneMegabyteThread`,
   the Windows stack rule). Composing the `Row { text; lifecycle }` inline in
   `looksRoot` failed on macOS arm64 (`.signal(SIGBUS)`, two runs out of two);
   moving it into its own `looksBesideH1(text:lifecycle:)` passed on macOS but
   failed in `swift:6.4-noble` aarch64 (`.signal(SIGSEGV)`; green at lane 1's
   head `8cefc01`). The section is now `LooksLifecycle()` alone, its title
   inside the component's body (built lazily, not as part of the tree value):
   green on both. **Windows' own 1 MB thread is not measured here** — CI
   confirms on push.
4. **`Backends/SDL`'s test target gains `MetalUI`** (`Package.swift`, outside
   `LC-O`'s file list): tests 10.2 and 10.3 drive an `App` over a hidden-window
   `SDLPlatform`. The SDL window `App` opened is reached through a forwarding
   `Platform` in the test file (`SDLPlatform.windows` is private), so nothing
   in `Sources/` changes.
5. **The expected count.** Spec §5.3's 2424 predates `LC-S`'s five
   (2428 at `8cefc01`); with test 10.1 the main package reads **2429 tests in
   3 suites**. `Backends/SDL` reads **24 + 65** (63 + tests 10.2, 10.3).

Also: `docs/divergences.md`'s "Not offered" table has no row for `.task`
(`LC-L` defers it with an owner); the API overview and the migration page say
so and link `LC-L`'s reason. Adding the row belongs to the Record phase
(`divergences.md` is lane 1's file).

**Measured.** On `feat/lifecycle`, each mutation applied by a script to the
spelling at `e3394e8`, the full unfiltered suites run (native `swift test
--no-parallel`, 6-minute hang limit, none hung; and `Backends/SDL`'s `swift
test` with `PKG_CONFIG_PATH=$PWD/.accesskit` where named), the file restored
from a copy, `git status --short` clean after each:

| # | spelling mutated | main package | `Backends/SDL` |
|---|---|---|---|
| M10.1 | `LooksDemo.swift`: `.onDisappear { disappeared += 1 }` → `.onDisappear { appeared += 1 }` | 1 test: `theLooksLifecycleSectionCountsAppearancesDisappearancesAndChanges` | not run (the demo is not in it) |
| M10.2 | `Window.drawFrameIfNeeded`: the whole `if drainLifecycle() { … drainLifecycle() }` block deleted | 39 tests, 58 issues: every `LifecycleTests` test that runs an action (1.1–1.12 but 1.8, 2.1–2.4, 3.1–3.4, 4.1–4.4, 4.6, 4.7, 5.1, 5.2, 5.4–5.6, 6.1–6.6, 7.1) and `theLooksLifecycleSectionCountsAppearancesDisappearancesAndChanges` | 2 tests: `anOnAppearRunsInAnSDLWindowsFirstFrame`, `closingAnSDLWindowRunsItsOnDisappear` (its `try #require` that the first frame appeared) |
| M10.3 | `App.openWindow`'s `onClose`: `window?.runDisappearancesForClose()` deleted | 2 tests: `closingTheWindowRunsEveryPresentOnDisappearOnce`, `closingTheWindowAlsoRunsParkedDisappearances` | 1 test: `closingAnSDLWindowRunsItsOnDisappear` |

Red before the section existed (test 10.1, `5a0a6cc`):
`LooksLifecycleDemoTests.swift:56:9: Expectation failed: halves.count == 2 —
the stepper's two halves: []`. Tests 10.2 and 10.3 passed on arrival (lane 1
committed); their red is M10.2 and M10.3.

**Gate, at `d294515`.** Native: `Test run with 2429 tests in 3 suites
passed`, `FR-J no-argument frame: succeeded=true`, 0 `error:`, the only
`warning:` SwiftPM's deprecation notice; `swift build --build-tests` 0
`warning:`. Pixels: `compare.sh <scratch> 047f0ab HEAD` — controls as recorded
in record §75 (1048576, 1031003, 454895, 0, 1048576, 0; 544 and 216 distinct),
all fourteen images `differing=0`, `scene identical`; `Expected.swift`
unedited. `swift:6.4-noble` (OrbStack, already running, left running; `git
archive` plus the fixed file): 0 `warning:`/`error:`, 199 + 22 + 36 passed.
`Backends/SDL`: 0 `error:`, 24 + 65 passed. Both closeout scripts print
nothing (no public declaration added). Lock probe:
`CGSSessionScreenIsLocked = 1`, `displayAsleep main: 1` — no real-window
capture, no demo launch; group T stays owed.

**Cost if wrong.** Items 1–3 are the demo's; item 4 is a test-target
dependency; item 5 is a count.
