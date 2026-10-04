# 76 — Lifecycle modifiers: onAppear, onDisappear, onChange

Branch `feat/lifecycle` from `047f0ab` (master: colour and colour scheme merged,
PR #45). **Not a plan task**: user request 2026-10-02, an item of the gpui-gap
priority list. The motivation is a port — the SMK keyboard configurator
(SwiftCrossUI): its device monitor starts and stops with the DEV pane
(`onAppear`/`onDisappear`) and a load error becomes an alert through
`onChange(of:)`; MetalUI had none of the three. Spec
`docs/superpowers/specs/2026-10-03-lifecycle-design.md`; rulings `LC-A`…`LC-U`
in the new decisions doc `docs/superpowers/2026-10-03-lifecycle-decisions.md`
(next unused `LC-V`); probes `docs/probes/swiftui-lifecycle.swift` (new) and
`docs/probes/swift-main-actor-task-loop.swift` (new).

**Numbering.** Written as §76 on the first try: master had published §75 (colour)
and no later number (`git fetch` at the Record phase: `origin/master` still
`047f0ab`), so no renumbering. **The human-checks group is `T`** (master's last
is `S`, colour).

**Status: LANDED — every agent-doable clause is built; the looks are owed to a
human** (`docs/verification/human-checks.md` group T, §7). Two lanes and a fix
pass, each red first, all verified `ok: true`; the Record phase's close (§9)
re-took the suite and the counts. **`.task` is deferred with an owner** (§10):
a main-actor `Task` never runs inside `SDLPlatform.run()`.

## §0 Baseline, design session and critic round (2026-10-03)

- **Baseline** at `047f0ab`: **2376 tests in 3 suites**, 0 goldens, 146
  `canTypecheck`-gated test declarations, 86 live divergences (next label 120),
  `Backends/SDL` 24 + 63, screen **locked** (`CGSSessionScreenIsLocked = 1`,
  `displayAsleep main: 1`) throughout the branch.
- **Carried items.** No decisions doc's "Carried…" section names an
  appearance, disappearance or value-change callback. The rules this branch
  reads and moves none of: `@State`'s "write from input, never from a phase"
  (the reason actions run after the build, `LC-E`); `ID-B`/`ID-C`/`ID-R`/`DD-C`
  and `TB-AH` (presence, `LC-C`); `AN-Y`/`AN-AB` (the transparent scope and the
  window-owned store, copied by `LC-B`/`LC-D`); `AN-AE`/`AN-AK` (the removal
  ghost, `LC-H`); `MV-E`/`MV-H` (a headless `renderFrame` runs nothing,
  `LC-J`); `CR-Q` (a second build inside one `beginFrame()`, the settle build's
  precedent). The plan's gap 10 (the SDL loop never drains the main queue) is
  `.task`'s owner (`LC-L`).
- **Probe** `swiftui-lifecycle.swift`: arms `L` controls, `A` order, `F` the
  first frame, `C` `onChange`, `E` disappearance, `D` state read in
  `onDisappear`, `S` scrolling, `T` transitions, `W` the window, `K` `.task`.
  Run three times by the design session on macOS 27.0.1 (byte-identical outside
  the lazy-container arms `S1`/`S2`, whose row sets agree per step and whose
  order does not); the critic round re-ran it whole and added `A6`, `A6b`,
  `E2b`; the fix pass added `D2`. Its header carries the recorded output
  verbatim (`SA-O`). `swift-main-actor-task-loop.swift` (arms `P0`, `B1`, `B2`)
  ran on macOS and in `swift:6.4-noble`: its three lines are byte for byte the
  same on both.
- **Critic round** (`LC-P`, ten items): a modifier fires **once per group and
  only while the group has content** (`A6`/`A6b`: an empty `ForEach` does not
  appear); a modifier written outside `.id` keys on the position (`E2b`); the
  probe header lacked the recorded output; the expected count double-counted
  `Backends/SDL`; test 5.4 had no mutation of its own; a write in an
  `onDisappear` run at close is lost with the window (stated); a removed group
  that painted nothing makes no ghost; `T4`'s `onChange` baseline folded into
  divergence 123; observation sessions stay bounded at two under the settle
  build. One finding rejected (splitting lane 1: every piece meets in
  `LifecycleStore.endFrame` and `drainLifecycle`).

## §1 What landed

- **The API** (`Sources/MetalUI/Lifecycle.swift`, `LC-B`, `LC-G`):
  `.onAppear(perform:)`, `.onDisappear(perform:)` and `.onChange(of:initial:_:)`
  with SwiftUI's two closure forms — `{ old, new in }` and `{ }` — on
  `extension ElementGroup`, so on both vocabularies; each returns
  `LifecycleScope<Self>`, a **layout- and identity-transparent** `ElementGroup`
  (`TransactionScope`'s shape: `parent` and `cursor` forwarded, no node, no
  `ModifiedContent` layer, no cursor index) with a typed
  `ProposalElementGroup` conformance that is a line-for-line, separately pinned
  copy. Adding or removing a lifecycle modifier moves no `@State`, focus,
  `$anim` baseline or `MC-A`/`MC-C`/`MC-P` number. No `Element` group-default
  hook was added (`MC-B`/`LR-AA` not triggered); `Handlers` did not grow.
- **Presence is membership in a build** (`LC-C`): an element appears when its
  scope reaches `requestGroupLayout` in a build (with content) and was absent
  the last completed build, and disappears on the reverse. `.hidden()`,
  opacity 0, zero size and clipped-out content are present (`E3`–`E5`); a
  `List` row outside its window is not built, so it **disappears** and returns
  as an appearance while its `@State` is kept for `TB-AH`'s generations
  (SwiftUI's lazy-container answer, `S1`/`S2`; a plain `VStack` in a
  `ScrollView` fires nothing, `S3`). The key is the scope's position plus a
  `$lifecycle<depth>` name plus an occurrence counter (`SurfaceRegistry`'s
  rule), a **store key, never a `StateTable` id** — no `noteNamed`, the seven
  reserved names unmoved.
- **`LifecycleStore`** (`LC-D`, held by the window's `AnimationStore`): this
  build's and the last completed build's entries, parked disappearances and the
  events not yet run. Every entry a build does not touch is dropped at that
  build's end (`AN-AB`'s rule), so content that leaves and returns compares
  against nothing. **Not a `StateTable` entry, not an eighth slot**
  (`theSevenRetentionSlotsAreMutuallyDistinct` untouched).
- **When actions run** (`LC-E`): collected in `Frame.render` after
  `stateTable.sweep()`, run by `Window.drainLifecycle()` in
  `drawFrameIfNeeded` **after `buildAndAdoptFrame` returns** — outside every
  phase and outside `withObservationTracking`'s apply closure, each under
  `StateDispatch.dispatching(to: owner)`, so `@State`/`Binding`/`@Observable`
  writes are legal as in an input handler. If the drain dirtied the window,
  **one settle build** runs inside the same `beginFrame()` and its events are
  drained too, so an `onAppear` write is presented in the **first** frame
  (`F1`, `F2b`) and an action that writes nothing costs no second build. The
  drain loops until no events are left and is not re-entrant
  (`isDrainingLifecycle`).
- **Order** (`LC-F`): changes, then appears (an `initial: true` firing
  interleaves with `onAppear` in modifier order), then disappears; each in
  reverse registration (pre-order) order — children before parents, later
  siblings first, inner modifier first.
- **`onChange`** (`LC-G`): compared once per build in `endFrame` against the
  value the same key stored last build with `{ ($0 as? V) == value }`; (old,
  new); a first sighting stores and fires only with `initial: true`; writes
  between frames coalesce; an undone change fires nothing; a new identity, an
  inserted element and a removed one compare against nothing.
- **Transitions** (`LC-H`, amended by `LC-P` item 7 and `LC-Q` item 2): a
  disappearance under a live removal ghost is **parked** until the ghost ends
  (`T1`/`T3`/`T5`, child first). A live ghost holds **every key that left
  under it**, so content re-inserted mid-fade cancels its parked disappearance
  *and* its appearance (and `initial: true` firing) — neither callback runs
  (`T4`). An unanimated removal and any insertion run at once (`T0`, `T2`).
- **`onDisappear` reads the departed element's state** (`LC-I`): `StateTable`
  keeps the values its sweep's resets delete, only when the last build held an
  `onDisappear`, as a `DepartedState`; while a disappearance runs `peek`
  reads through that overlay and a write to a departed id lands in the overlay
  only, so the identity is never resurrected. No retention rule moved. **Its
  reasoning was corrected by `LC-S` item 1** (divergence 125, §6).
- **Window close** (`LC-J`): `App`'s `onClose` calls
  `Window.runDisappearancesForClose()`, which runs every present and parked
  `onDisappear` once, in reverse pre-order, under `StateDispatch`; ordering a
  window out and app quit run nothing; a headless `renderFrame` runs nothing.
- **`.task` is not built** (`LC-L`). A main-actor `Task` created while the main
  thread spins a loop that never enters the run loop does not run (probe `B1`,
  macOS and `swift:6.4-noble`: `task ran=false`; `P0`, the `NSApp.run` shape,
  runs it). `SDLPlatform.run()` is that loop. `B2` measured the candidate
  repair (one `RunLoop.main.run(mode: .default, before: .distantPast)` per
  iteration) for the owner to build.
- **Performance** (`LC-M`): `LifecycleStore.lastFrameWork` counts registrations
  plus entries visited by the end-of-build diff — **3K** for K scopes, **0**
  with none; a tree with no lifecycle modifier skips the diff and retains no
  departed value. Pinned on a branching tree with literals derived first.
- **The demo** (`LC-N`, `LC-T`): `LooksLifecycle()` in the looks demo
  (`METALUI_LOOKS_DEMO=1`): a tile toggle, a tile under a 0.8 s `.opacity`
  transition, a stepper with an `onChange`, four counters as text and as
  8-point-per-count bars. Placed **beside H1** (`looksBesideH1(text:lifecycle:)`),
  its title inside the component's body; the default demo and the fourteen
  offscreen images are untouched.
- **Public documents**: divergences 120–125, API overview "Lifecycle — A / D",
  a migration subsection, human-checks group T, inventory family `lifecycle`,
  the "Not offered" row for `.task` (this phase), record §04's section.

## §2 Tests and guards, per file

Root **2376 → 2429 (+53)**: lane 1 +47 (44 tests with 1.5b, and 3 guards), the
fix pass +5 (5.5, 5.6, 5.7, 6.6 and guard 9.4), lane 2 +1 (10.1); `Backends/SDL`
**24 + 63 → 24 + 65** (+2, tests 10.2 and 10.3). `canTypecheck`-gated
declarations **146 → 150** (+4: guards 9.1–9.4); typecheck guards **147 → 151**.
Goldens 0. No existing test retired; one edited (`CloseoutTests` F1.3, below).

| file | tests | spec id |
|---|---|---|
| `Tests/MetalUITests/LifecycleTests.swift` (48 `@Test`s) | presence and identity 1.1–1.12 (incl. 1.5b, the List's cold frame; 1.11, outside `.id`; 1.12, once per group); order 2.1–2.4; `onChange` 3.1–3.6; timing, dispatch and settle 4.1–4.7; departed state 5.1–5.7; transitions 6.1–6.6; window and headless 7.1–7.3; performance 8.1–8.2 | 1.1–8.2 |
| `Tests/MetalUITests/LifecycleCompileGuards.swift` (4 guards, `typecheckFile`/plain import) | `theLifecycleSpellingsTypecheckFromAnExternalModule`, `aNonEquatableOnChangeValueDoesNotCompile`, `aLegacyDecorationAfterALifecycleModifierDoesNotCompile`, `aLifecycleModifierOnAWindowRootNeedsAContainer` | 9.1–9.4 |
| `Tests/MetalUITests/LooksLifecycleDemoTests.swift` | `theLooksLifecycleSectionCountsAppearancesDisappearancesAndChanges` (hitbox clicks; the bars read 8 and 8, the change bar 8; the fading tile's counter waits for the fade) | 10.1 |
| `Backends/SDL/Tests/MetalUISDLTests/SDLLifecycleTests.swift` | `anOnAppearRunsInAnSDLWindowsFirstFrame`, `closingAnSDLWindowRunsItsOnDisappear` (helper arms `armMainRunLoopExitCheck()`; reaches the window through a forwarding `Platform`, since `SDLPlatform.windows` is private) | 10.2, 10.3 |

Edited existing test (owed by the demo, not a moved rule): `CloseoutTests`
F1.3 counts the looks demo's clickable hitboxes — **ten → fourteen** (the
section adds two buttons and the stepper's two halves) and finds the first
transition button as the topmost of the nine sharing one left edge (`LC-T`
item 1). `Backends/SDL`'s test target gains the `MetalUI` dependency
(`Package.swift`, `LC-T` item 4); nothing in `Sources/` changed for it.

Sources touched: `Lifecycle.swift` (new, 438 lines), `AnimationStore.swift`
(+7), `Frame.swift` (+26), `StateTable.swift` (+75, the departed overlay only),
`TransitionStore.swift` (+7, `liveGhosts`), `Window.swift` (+70, the drain and
`runDisappearancesForClose`), `App.swift` (+5, `onClose`),
`LooksDemo.swift` (+126). No `Platform`/`PlatformWindow`/`WindowRenderer`
requirement, no shader, no primitive, no C enum.

## §3 Probes

`swiftui-lifecycle.swift` (new; macOS 27.0.1; headers carry the output).
**Read** (spec §1.2): presence is per modified group while it has content
(`A6`, `A6b`); presence is hierarchy membership, not visibility (`E3`–`E5`,
and a lazy `List`/`LazyVStack` row leaving the viewport disappears, `S1`/`S2`,
a plain `VStack` does not, `S3`); order is reverse pre-order, new content
appears before old disappears (`A1`–`A5`, `E2`, `C10`), existing views'
changes run before inserted views' appears (`C12`); `onAppear` runs after the
first body and before the first draw and its write reaches that draw (`F1`,
`F2b`), chains settle in one turn (`F3`, `C9`); `onChange` has both forms,
`initial: true` fires (v, v) with `onAppear` in modifier order (`C3`, `C3b`),
coalesces (`C5`–`C7`), is fresh per identity (`C10`); an animated removal's
`onDisappear` runs when the transition ends and re-insertion mid-removal runs
neither callback (`T1`, `T3`–`T5`); `onDisappear` reads its own `@State` as it
was and a write is lost (`D1`); a never-written `@State` default keeps its
first evaluation (`D2`, the separating arm: four `made` lines, `start Mon 1`,
`stop Mon 1`); order-out and `close()` with the host retained fire nothing, the
content leaving its host fires `onDisappear` (`W1`–`W3`); `.task` starts after
`onAppear` and cancels after `onDisappear`, `task(id:)` starts the new task
then cancels the old (`K1`, `K2`). **Not claimed**: SwiftUI's app-scene quit
(`LC-J` item 3), a transitioned group that painted nothing (`LC-P` item 7).
`swift-main-actor-task-loop.swift`: `P0` true, `B1` false, `B2` true, on
macOS and in `swift:6.4-noble`. Windows is not measured (no Windows host).

## §4 Red runs

Each lane committed its tests red first (the files do not compile at
`047f0ab`: no `onAppear`, `onDisappear`, `onChange`, `LifecycleStore`):

- **Lane 1** (`e41e4b1`): `LifecycleTests` 1.1–8.2 (43) and
  `LifecycleCompileGuards` 9.1–9.3 — compile errors against the absent API.
  Test 1.5b was added during implementation (`LC-Q` item 1); 1.5 and 5.4 read
  the visit count the row last wrote because the cold frame adds one
  appearance.
- **Lane 1's fix pass** (`e4f8f1d`): tests 5.5, 5.6, 5.7, 6.6 and guard 9.4 and
  the pins `LC-S` owed; 5.5 is green on arrival by design (it pins divergence
  125), the others pin existing behaviour whose mutations were green (§5).
- **Lane 2** (`5a0a6cc`): 10.1 red at `LooksLifecycleDemoTests.swift:56:9:
  Expectation failed: halves.count == 2 — the stepper's two halves: []`; 10.2
  and 10.3 passed on arrival (lane 1 committed) and are red under M10.2/M10.3.

## §5 Mutation tables

Every mutation from a copy of the committed file, a native rebuild, the full
unfiltered suite (`swift test --build-system native --no-parallel`, or
`Backends/SDL`'s own), `git status --short` clean after each, reddened tests
named. No mutation hung.

**Lane 1** (`LC-R`, on `047a0fa`/`001ceb1`, baseline **2423**): 45 mutations,
every one in spec §5, named per row in `LC-R`'s table with the tests each
reddened. Summary by group: presence (M1.1–M1.12) 1–17 tests each; order
(M2.1–M2.4) 1–3; `onChange` (M3.1–M3.5) 2–13; timing and dispatch (M4.1–M4.7)
1–96, **M4.2 (settle unconditionally) reddens 47 and M4.5 (an always-dirty
drain) reddens 96 tests outside the lane** — the reason `LC-E` item 2 settles
only on a write; departed state (M5.1–M5.4) 1–3; transitions (M6.1–M6.5) 1–9;
window (M7.1–M7.3) 1–2; performance (M8.1, M8.2) 1–2; guards (MG9.1–MG9.3) 1
each. **Green: M1.7** (the depth dropped from the key). Lane 1 read it as
redundant with the occurrence. **The branch check refuted that (`LC-U` item 1,
§11):** an inner action toggled to or from `nil` changes how many scopes are
noted at a position while the content stays present, and M1.7 then fires the
outer `onDisappear` on a present element. The depth is load-bearing, and no
committed test pins it; test 1.7's mutation is **M1.7b** (depth and occurrence dropped),
which reddens 16 tests, 1.7 among them (`LR-X`: a green mutant may be the
correct spelling). Test 3.6 has no mutation of its own (M3.3 reddens it).

**The fix pass** (`LC-S`, on `e4f8f1d`, baseline **2428**; re-run by the
verifier on `8cefc01`, every row reproduced):

| mutation | reddens |
|---|---|
| V1 parked event built with `departed: nil` (`LifecycleStore.endFrame`) | `aGhostParkedOnDisappearReadsTheStateItsElementHad` |
| V3 `takeDepartedState()`'s clearing `defer` deleted | `eachRemovalCountsOnlyTheDepartedValuesItsOwnSweepKept` |
| V5 `runDisappearancesForClose` calls `event.action()` without `StateDispatch` | `closingTheWindowRunsEveryPresentOnDisappearOnce` |
| V14 `} else {` with only the `onAppear` under `!cancelled.contains(key)` (the `initial: true` firing outside) | `reinsertingDuringTheGhostRunsNeitherCallbackAndStartsWithFreshState` |
| M5.1 `departedOverlay = nil` in `withDepartedOverlay` (re-run to separate 5.6 from 5.5) | `aGhostParkedOnDisappearReadsTheStateItsElementHad`, `aMonitorAssignedInOnAppearIsTheOneOnDisappearStops`, `aWriteInOnDisappearIsLostAndReturningContentStartsFresh`, `eachRemovalCountsOnlyTheDepartedValuesItsOwnSweepKept`, `onDisappearReadsItsOwnStateAsItWasLastFrame` |
| MG9.4 guard 9.4's negative fixture: root wrapped in `Column { }` | `aLifecycleModifierOnAWindowRootNeedsAContainer` |

**Lane 2** (`LC-T`, on `e3394e8`; the verifier re-ran MV1–MV3 and the two SDL
rows on `b95ed7d`, baseline **2429**, SDL **24 + 65**):

| mutation | main package | `Backends/SDL` |
|---|---|---|
| M10.1 the section's `.onDisappear { disappeared += 1 }` → `{ appeared += 1 }` | `theLooksLifecycleSectionCountsAppearancesDisappearancesAndChanges` | not run (the demo is not in it) |
| M10.2 `drawFrameIfNeeded`'s whole `if drainLifecycle() { … }` block deleted | 39 tests, 58 issues: every `LifecycleTests` test that runs an action (all of 1.1–1.12 but 1.8, 2.1–2.4, 3.1–3.4, 4.1–4.4, 4.6, 4.7, 5.1, 5.2, 5.4–5.6, 6.1–6.6, 7.1) and 10.1 | `anOnAppearRunsInAnSDLWindowsFirstFrame`, `closingAnSDLWindowRunsItsOnDisappear` |
| M10.3 `App.openWindow`'s `onClose`: `runDisappearancesForClose()` deleted | `closingTheWindowRunsEveryPresentOnDisappearOnce`, `closingTheWindowAlsoRunsParkedDisappearances` | `closingAnSDLWindowRunsItsOnDisappear` |
| MV1 the section's `.onChange(of: value) { changes += 1 }` → `{ }` (verifier) | `theLooksLifecycleSectionCountsAppearancesDisappearancesAndChanges` | — |
| MV2 `.transition(.opacity)` removed from the fading tile (verifier; the demo test checks the `onDisappear` waits for the fade, `LC-H`) | `theLooksLifecycleSectionCountsAppearancesDisappearancesAndChanges` | — |
| MV3 `drawFrameIfNeeded` keeps the drain, drops the settle build (verifier) | `anOnAppearWriteIsPresentedInTheFirstFrame`, `anObservableWriteInOnAppearIsPresentedAndNotLost`, `aChainOfAppearancesSettlesOneLevelOfWritesPerPresentedFrame`, `actionsRunOutsideEveryPhaseUnderTheirElementsDispatch`, `aListsFirstFrameAppearsEveryRowAndTheNextBuildDisappearsTheRowsOutsideItsWindow`, `reinsertingDuringTheGhostRunsNeitherCallbackAndStartsWithFreshState` | `anOnAppearRunsInAnSDLWindowsFirstFrame` (SDL-MV3, the same removal) |
| SDL-M10.3 `window?.runDisappearancesForClose()` → `_ = window` in the SDL `App` path (verifier) | — | `closingAnSDLWindowRunsItsOnDisappear` |

**Guards reddened once each**: MG9.1–MG9.4 (above). **Counts**: the guard
mutations each redden exactly their one guard.

## §6 Green mutations and pins that prove less than they look

- **M1.7 is green** (§5). Lane 1 read the depth in the lifecycle key as
  redundant with the occurrence. **That was refuted at the branch check
  (`LC-U` item 1, §11):** the depth is load-bearing, and no committed test pins
  it. A test gap, not a correct spelling.
- **Test 5.5 is green by design.** It pins **divergence 125** — the
  never-written `@State` default is re-seeded every build, so `onAppear` (build
  1) and `onDisappear` (the last present build) reach different instances
  (`["start 1", "stop 4"]` after four builds). `LC-I`'s original reasoning said
  the overlay fixes the SMK shape `@State var monitor = Monitor()`; **that was
  refuted by measurement** (`LC-S` item 1, probe `D2`). Its separating arm is
  5.6 (the documented spelling: assign the instance in `onAppear`, one
  instance, `["start 1"]` then `["stop 1"]`, reddened by M5.1). Making
  `@State` keep its first value would move state retention (a never-written
  slot would become a stored entry, with every `TB-AH`/`ID-C` count that
  implies) and is not done.
- **Test 3.6 has no mutation of its own**; M3.3 (a first sighting fires)
  reddens it, recorded as its spelling.
- **`LC-R` finding 3's counts** read 65 and 145 in an earlier draft; the
  table's rows name 47 and 96 tests (`LC-S` item 6).
- **Test 1.9** (`lifecycleModifiersFireInsideAComponentAnEnvironmentScopeAndADeferred`)
  is a composition test reddened by 1.1's mutation: a per-container mutation
  would be a mutation of `Component`, `EnvironmentScope` or `Deferred`, files
  outside the lane.
- **Tests 1.5 and 5.4** read the visit count the row last wrote, not a literal,
  because the cold frame adds an appearance before the scroll (divergence
  124).
- **Test 5.3's control arm** keeps 4 departed values, not the 1 the design
  assumed (the subtree's other entries are kept too); the test asserts `> 0`
  there and `== 0` for the arm the ruling is about.

## §7 Demo comparison and looks

- **Fourteen offscreen images**: `docs/probes/demo-pixels/compare.sh <scratch>
  047f0ab HEAD` — controls as recorded in §75 (1048576, 1031003, 454895, 0,
  1048576, 0; 544 and 216 distinct), **all fourteen `differing=0`, scene
  identical**; `Expected.swift` unedited since `047f0ab` (Linux/Windows CI
  confirm on push). The looks demo is not among the fourteen images, so the
  section's pixels are unseen by the comparison; it is measured headless: the
  looks content is **1100 × 817** at its widest and tallest rect, inside
  `MetalUIDemo`'s 1180 × 880 window (it was 804 tall at `047f0ab`; 1000 under
  the transitions, 968 at the foot of the left column, so the section was moved
  beside H1 and its counters laid two by two, `LC-T` item 2).
- **Looks owed — group T, none performed (an agent cannot)**: **T1** the
  fading tile's `faded` counter moves when the ~0.8 s fade ends, not on the
  click, and a second press during the fade brings the tile back with no
  count (`T1`/`T3`/`T4`; divergence 123); **T2** ten presses of "Toggle tile"
  leave `appeared` and `disappeared` equal (5 and 5), the bars equal and the
  window idle; the stepper's + three times reads `changes` 3. Screen locked
  (`CGSSessionScreenIsLocked = 1`, `displayAsleep main: 1`): no real-window
  capture, no demo launch. Record §03 carries the entry.

## §8 Hazards

- **The 1 MB thread overflowed twice** (`everyProductionTreeBuildsOnAOneMegabyteThread`,
  the Windows stack rule). The row composed inline in `looksRoot` failed on
  macOS arm64 (`SIGBUS`, two runs out of two); a separate `looksBesideH1` passed
  on macOS and failed in `swift:6.4-noble` aarch64 (`SIGSEGV`; green at `8cefc01`).
  Final shape: `LooksLifecycle()` alone with its title inside the component's
  body (built lazily, not part of the tree value). Green on macOS and Linux;
  **Windows' own 1 MB is not measured here — the `root-windows` job on push is
  the confirmation, and its margin is thin.** If it fails: shrink the
  composition or move the section out of `looksBesideH1`.
- **A `List`'s first frame appears every row** (divergence 124): `List`'s
  cold-frame rule builds every row while its scroller has no measured
  viewport, so a 12-row list in a 20-point viewport logs twelve appearances and
  nine disappearances (rows 3…11), the latter in the same `drawFrameIfNeeded`
  when an action wrote (the settle build is the windowed one), else on frame
  two. Not fixed: the rule is `List`'s and changing it re-opens the flash it
  prevents.
- **An unconditional settle or an always-dirty drain changes 47/96 tests'
  build counts and timing** (M4.2, M4.5): the settle build runs only on an
  action's write.
- **Observation sessions**: when only a `@State` write dirtied, the settle
  build arms a second session; both read the sentinel and the next tick flushes
  them, so outstanding sessions stay bounded at two (`CR-Q`'s own second build).
- **A write in `onDisappear` at window close is lost with the window** (the
  display link is invalidated before `onClose` on AppKit, `closed` is set
  before it on SDL); a write in `onDisappear` otherwise lands in the overlay
  and is lost (`D1`).
- **`SDLPlatform.windows` is private**: the SDL tests reach the window through
  a forwarding `Platform`; every new SDL test helper creating an `SDLPlatform`
  arms `armMainRunLoopExitCheck()`.
- **A lifecycle modifier is an `ElementGroup`, not an `Element`**: a `Self`-
  returning legacy decoration after it does not compile and it cannot be a
  window's root (divergence 120; wrap the root in a container).

## §9 The Record phase's own close (2026-10-03)

`git fetch`: `origin/master` is still `047f0ab`; no merge, no renumbering.
Re-taken on `feat/lifecycle` after the docs below: `swift package clean`,
`swift build --build-system native --build-tests`, unfiltered `swift test
--build-system native --no-parallel`:

- **`Test run with 2429 tests in 3 suites passed after 127.611 seconds`**; `FR-J no-argument frame: succeeded=true`; `LC-B window root: positive succeeded=true; negative succeeded=false`; 0 `error:`; the only `warning:` SwiftPM's deprecation notice for `--build-system native` (the build log and the test log). The clean native build took 66.5 s.
- Both closeout scripts print nothing; the census is re-recorded (2315
  declarations, matching `docs/api-overview.md`).
- `MetalUILayout` imports only `MetalUICore`; `MetalUIScene` imports only
  `MetalUIShaderTypes`.
- Verified by the lane-2 gate on `b95ed7d` (not re-taken here — no source
  changed since): `swift:6.4-noble` on a `git archive` of HEAD, 0 `warning:`/
  `error:`, **199 + 22 + 36 + 31 + 18 + 6** passed
  (`everyProductionTreeBuildsOnAOneMegabyteThread` green on Linux);
  `Backends/SDL` (`PKG_CONFIG_PATH=.accesskit`) **24 + 65**, the only warning
  the existing pkg-config `rpath` one for sdl. OrbStack was already running and
  was left running.

## §10 Deferrals, with owners

| item | reason | owner |
|---|---|---|
| `.task(perform:)`, `.task(id:priority:_:)` | a main-actor task never runs inside `SDLPlatform.run()` (`LC-L`, probe `B1` on macOS and Linux; Windows not measured) | the plan's gap 10 (the SDL run-loop main-queue drain); probe `B2` is its measured candidate, `K1`/`K2` its SwiftUI answers. Until then a port starts its monitor from `onAppear`. "Not offered" row in `docs/divergences.md` |
| `onChange(of:perform:)` (one parameter) | deprecated by SwiftUI in macOS 14 | none |
| `onReceive`, `scenePhase`, app lifecycle | no request; needs a scene model MetalUI does not have (`PB-A`) | none |
| lifecycle modifiers on menu content | `MenuContent` is data, not an `ElementGroup` | none |
| a decoration after a lifecycle modifier; a lifecycle modifier as a window root | the transparent-scope constraint shared with `.animation(_:value:)`/`.environment` (divergence 120) | none (the fix, if a port needs it, is one forwarding conformance for all three scopes) |
| re-inserted content keeping its state mid-transition (divergence 123) | `ID-C` resets at removal; changing it moves identity rules | none |
| a `List`'s cold frame appearing every row (divergence 124) | the cold-frame rule is `List`'s | none scheduled |
| a never-written `@State` default keeping its first value (divergence 125) | moves state retention | none scheduled |
| a transitioned group that painted nothing (no ghost, so no parked disappearance) | unprobed against SwiftUI (`LC-P` item 7) | none until a probe shows a difference |
| human checks T1, T2 | an agent cannot; screen locked | a human (group T) |
| Windows' 1 MB stack for the looks tree; Windows `Backends/SDL` | no Windows host here | `root-windows` CI on push |

## §11 The adversarial branch check (2026-10-03, on `0813a47`)

Ruling `LC-U`. Everything below was re-taken on `feat/lifecycle` at `0813a47`.

- **Suite.** `swift package clean`, then `swift build --build-system native
  --build-tests`, then the unfiltered `swift test --build-system native
  --no-parallel`: **`Test run with 2429 tests in 3 suites passed after 127.761
  seconds`**. The log has `FR-J no-argument frame: succeeded=true` and
  `LC-B window root: positive succeeded=true; negative succeeded=false`. It
  has 0 `error:`, and the only `warning:` is SwiftPM's native-build-system
  deprecation notice. `swift build --build-tests` (the default build system)
  has 0 `warning:`.
- **Invariants.** These are unchanged and green in that run, and the branch
  edits no existing test file except `CloseoutTests.swift`, whose demo button
  census goes from 10 to 14 (`LC-T` item 1):
  - `theSevenRetentionSlotsAreMutuallyDistinct`
  - `everyNamingSiteStartsAReturningNameFresh`
  - `everyRegisteringSiteAnimatesItsLoweredRectUnderTheProposalAuthority`
  - `everyBackgroundPaintingSiteAnimatesItsColour`
  - `everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn`
  - `everyProductionTreeBuildsOnAOneMegabyteThread`
  - `theLegacyEngineSymbolsAreAbsentFromTheTestProcess`

  No hit-testing, accessibility, animation, focus, `List` or text-input source
  or test file is in the diff.
- **Docs.** `cmp CLAUDE.md AGENTS.md` reports them identical. Every
  `LC-` id cited in a changed doc resolves to a `## LC-` heading; `LC-U`
  resolved only once this check appended it. Every other prefixed id in the
  three lifecycle docs resolves to a heading. Every test name of 20 or more
  characters cited in an added doc line resolves to a `func`. Every probe arm
  cited in `docs/divergences.md` 120–125 and in the rulings is in
  `swiftui-lifecycle.swift`.
- **Inventory.** Both closeout scripts print nothing. **The census was stale**:
  `d294515` moved four `LooksDemo.swift` declarations, which now sit at lines
  22, 338, 340 and 349, while the census still recorded 20, 322, 324 and 333.
  It is re-recorded here, still 2315 declarations.
- **Pixels.** `compare.sh <scratch> 047f0ab HEAD` gives the same controls as
  §9 (1048576, 1031003, 454895, 0, 1048576, 0; 544 and 216 distinct). All
  fourteen images have `differing=0` and `scene identical`.
- **Backends/SDL** (`PKG_CONFIG_PATH=$PWD/.accesskit`, macOS): **24 + 65
  passed**, 0 `error:`. The warnings are the existing sdl `rpath` one and
  `ld`'s macOS-27 dylib notices.
- **Linux.** In `swift:6.4-noble` (OrbStack), on a `git archive` of HEAD,
  `swift build --build-tests` has 0 `warning:` and 0 `error:`. `swift test
  --skip-build` passes **199 + 22 + 36 + 31 + 18 + 6**. OrbStack was found
  running and was stopped afterwards.
- **Mutations of the checker's own design.** Each was applied to a copy of
  `0813a47`'s source, run on the full unfiltered native suite, restored from
  the copy, and followed by a clean `git status --short`:

  | # | spelling mutated | result |
  |---|---|---|
  | BC1 | `Lifecycle.swift` `noteLifecycle`: `ElementID("$lifecycle\(lifecycleDepth)")` → `ElementID("$lifecycle")` (M1.7's spelling), with a scratch test added: an inner `onAppear(perform:)` toggled `nil` → non-nil → `nil` under an outer `onDisappear` | 2430 tests, 1 issue. Only the scratch test reddened (`["disappear b"]`; unmutated it logged `["appear a"]` and passed, 2430 passed). **`LC-R` finding 1's "redundant" is refuted**: `LC-U` item 1 |
  | BC2 | `Window.drainLifecycle`: `StateDispatch.dispatching(to: event.owner) { event.action() }` → `event.action()` | 2429 tests, 2 issues: `actionsRunOutsideEveryPhaseUnderTheirElementsDispatch`, `closingTheWindowRunsEveryPresentOnDisappearOnce` |

- **Code defect, reported and not fixed** (`LC-U` item 2): a lifecycle action
  that toggles to or from `nil` changes presence. This was measured with a
  filtered scratch run: `onDisappear(perform: flag ? f : nil)` with `flag`
  going from true to false logs `["disappear"]` on a still-present leaf.
  **Merge verdict: mergeable.** The defect is an edge spelling and is
  recorded with an owner. The human looks (group T) remain unperformed.
