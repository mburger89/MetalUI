# State first value (round 4 item R4-1 PR B) — decisions (prefix `FV-`)

Rulings for the second of three R4-1 PRs: divergence 125, "a never-written `@State` default is re-seeded every build". Branch `feat/r4-1-state-first-value`, from master `0319a42b`;
the orchestrator's plan is not in the repo, its predictions are quoted where a probe moved them. Code: `StateTable.swift` (`mark(_:seeding:)`, class doc), `State.swift` (`bind`, doc comments).
Probe (recorded in its header, macOS 27.2, 2026-11-03): `swiftui-lifecycle.swift` `D3`, `D5`, `D5b` (new; `D2` is the 2026-10-03 arm). Tests: `StateFirstValueTests.swift`,
`StateFirstValueRetainedTests.swift`, `LifecycleTests.swift`, `OccurrenceIdentityTests.swift`, `RetainedWithStatePanelTests.swift` (`everyStateWriteSiteIsClassified`).
**Next unused: `FV-E`.** Divergences: 125 retired, 210 added (live count 207 unchanged; next label 211). No human-check group (nothing here is a look).

**One prediction of the plan was confirmed by its gate and changed the divergence list** (`FV-C`); the rest of the plan held (`FV-A`, `FV-B`).

## FV-A: a `@State` keeps its default's first evaluation (divergence 125 retired; overturns `LC-S` item 1)

1. **`LC-S` item 1's reason was scope, not impossibility.** It said keeping the first value "would move state retention (a never-written slot would become a stored entry, with every `TB-AH`/`ID-C` count that implies), which this item's
   'MUST NOT MOVE' forbids without a ruling of its own". This is that ruling. Probe `D2` showed SwiftUI evaluates the default on every re-init and discards it; probe `D3` adds the same for a value type seeded from a parameter through `init`
   (`s=0` as `v` goes 0, 1, 2).
2. `StateTable.mark(_:seeding:)` is `mark`, and on a slot with **no entry** stores the default (`@autoclosure`, boxed into `Any` only on a miss, one `storage.index(forKey:)` lookup as `PA-E`) with a version from the write counter, live in this
   generation. `State.bind` calls it (`State.swift`); `GestureState` and `Namespace` reach it through `State.bind`, `FocusState` keeps its own plain `mark` and `FocusStateValue` slot. A slot that already has an entry, of any type, is untouched.
3. **A seeded entry obeys every rule unchanged**, which is why nothing else moved: `ID-C`, `ID-R` and `DD-C` delete it in `resetQueuedEntries` (so content that returns is seeded again from the new parameter: pinned for the `if`, `.id` and loop arms);
   `TB-AH` applies through `sweep`'s liveness pass and the reap (a `List` row outside its window keeps its first value for `staleAfterGenerations` = 2 generations and is seeded again after more, once the table is over `sweepThreshold`);
   `LC-I`'s overlay needs no edit (`departedValues[id] = removed.value`, `peek` reads the overlay), so a ghost-parked `onDisappear` and a window close read the first instance. A ghost replays captured primitives and no
   `StateBinder.bind` is in the transition code, so a ghost cannot seed. Re-seeding in a frame is idempotent and `withState` is not involved, so no `rollbackBuild` is owed: an abandoned build's first value is kept. Bind precedes every
   version read (`EquatableComponent`, `ContentMemo`, `RetainedSubtree`).
4. **Costs, stated.** One `Entry` per declared `@State` of a live element (it was one per *written* `@State`); `sweepThreshold` (256) engages that many entries sooner, so an out-of-window **written** value can be reaped sooner, inside `TB-AH`'s
   stated bound; a cold `List` frame seeds every row's `@State` and the reap then clears what goes stale. The 100k-row list test (`aListsWorkIsTheSameFor100kRowsAsFor500`) is the work check (record 199).
5. **Behaviour that changes for callers** (`docs/migration.md`): a `@State` set through `init` or the memberwise initialiser no longer follows the parent until it is written (`_s = State(wrappedValue: v)`, `@State var s: Int` set by the
   parent); `@State var owner = UUID()` is one UUID for the element's lifetime where every build re-minted it; a reference default (`@State var monitor = Monitor()`) is one instance. In this repo the only literal reads of the old
   behaviour were `OccurrenceIdentityTests`' `aStateBoxForgetsTheOccurrencesOfAnEarlierGeneration` (the dead slot now reads its seed 0, not `nil`) and the 5.5 pin, flipped.

## FV-B: a seed is not a write; the journal rule (amends `RW-F`)

1. `mark(_:seeding:)` raises no `isDirty`, fires no `onWrite`, moves no `writeCount` and taints nothing (`retainLog`, `prepaintLog`, the build journal). `RW-F` ("a creating read is a write") does not extend to it: any window opened on that build reads the
   seeded version afterwards, so a record made there hits the next frame (pinned with a seeded state **inside** the recorded window: mutation M6 below). Versions come from the same counter, so a slot that was reset and seeded again never repeats a number.
2. **It is journalled as the plain `.mark` and records no value.** A replay marks an entry that is still there (it stays while it is marked), and a `GraftRecord` holding the instance would keep it past its reset.
3. `everyStateWriteSiteIsClassified` counted only `withState(`/`readState(` and skipped `StateTable.swift`, so it could not see this site: it gains a fourth column, `seeds`, with `"State.swift": (0, 0, 0, 1)`. A second seeding call in any file moves a row.
4. `retained.md` carries the sentence; `identity-state.md` the `@State` clause.

## FV-C: an erased type swap shares the old slot (divergence 210; the hazard the plan named)

1. **Probe `D5`/`D5b`**: an `AnyView` that swaps two view types, each holding an `Int` `@State` (seeds 10 and 20), resets state. `SeedB` reads its own 20 after `SeedA` (10) and `SeedA` reads 10 again on the swap back; with `SeedA`'s state *written*
   to 11 the swap still reads 20 (`D5b`).
2. **MetalUI's `AnyElement` has no type tracking**: both elements bind under the same id's `$state<n>`. Measured on the tree before this change: a never-written default read **its own 20** (`D5`, the right answer, by accident, because nothing
   was stored) and a written value leaked **11** (`D5b`, wrong). After `FV-A` the never-written case reads **10** too. So `FV-A` made one SwiftUI-matching answer newly wrong, and divergence 210 records both (the written half was an unrecorded
   divergence already).
3. **Not fixed here.** A fix needs a type key per `AnyElement` position (`ObjectIdentifier(E.self)` held by the window) and a reset of the subtree's entries on change, through the `ID-C` sweep and a journal event for the graft: not small, and it
   touches every `AnyElement`. Two types in the two branches of an `if`/`else` are two positions and reset (`ID-B`); only an erased swap at one position shares. Pinned wrong on purpose by `anAnyElementSwapKeepsTheSlotOfTheTypeItReplaced`
   (arms `seeded`, `written`); a fix reddens both and takes 210 out. Owner: none scheduled.

## FV-D: tests and the pieces the plan predicted

Read the mutation table in record 199. Summary of what moved against the plan: the only existing tests that flipped were `aNeverWrittenStateDefaultIsReseeded...` (the pin, renamed) and `aStateBoxForgetsTheOccurrencesOfAnEarlierGeneration` (`nil` to the
seed 0). Every literal table read the plan listed for adjudication (`ControlAccessibilityTests`, `ListLoweringTests`, `ListSelectionTests`, `ContextMenuTests`, `PopoverTests`, `MeasurePerformanceTests`, `RetainedPrepaintTests`) stayed green; the graft
mutation vehicle the plan named (`testingCorruptGraftRecords("marks")`) does not separate a seeded entry on its own because the paint record's `marks` replay also keeps it live (record 199, section 4).

## Mutations (restored; names are the tests that reddened)

See record 199 section "Mutations".
