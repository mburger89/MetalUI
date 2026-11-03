# Record 199: a `@State` keeps its first value (round 4 item R4-1 PR B)

Branch `feat/r4-1-state-first-value`, from master `0319a42b`. Decisions: `docs/superpowers/2026-11-03-state-first-value-decisions.md` (`FV-A`..`FV-D`). Human checks: none (nothing here is a look). Divergences: **125 retired, 210 added** (207 live: 207 - 1 + 1; next label 211).

## 1. What the probes showed (macOS 27.2, 2026-11-03, `docs/probes/swiftui-lifecycle.swift`, header holds the output)

| gate | result | consequence |
|---|---|---|
| `D3` | a value-type `@State` seeded from a changing parent parameter through `init` reads `s=0` at `v=0, 1, 2`: SwiftUI keeps the first value | as the plan predicted; pinned by `aSeedFromAParentParameterDoesNotFollowIt` |
| `D5` | an `AnyView` swapping two view types (seeds 10 and 20, never written) resets state: `SeedB` reads **20**, and `SeedA` reads 10 on the swap back | **the plan's hazard is real**: SwiftUI resets |
| `D5b` | with `SeedA`'s state written to 11 the swap still reads **20** | the written value must not carry over either |

**MetalUI side of `D5`, measured before and after the change** (a test, since removed in favour of the pin): `AnyElement(Stack { SeedA }) -> AnyElement(Stack { SeedB })`: before `FV-A` `SeedB` read **20** (nothing was stored, so the default of the new type won, correct by accident); after it **10**. The written case read **11** before and after (an unrecorded
divergence already). So the plan's branch was taken: divergence **210** records both, `FV-C`. A fix was judged not small (a type key per `AnyElement` position and a reset on change through the `ID-C` sweep, with a graft journal event). The change was not stopped for it: `FV-A` itself does what the plan said and `D5` was
the gate the plan set for choosing 210 over a fix.

## 2. What changed

- `StateTable.mark(_:seeding:)` (`@autoclosure`, `PA-E`: one `storage.index(forKey:)`, boxed on a miss only), called by `State.bind`. `GestureState` and `Namespace` go through `State.bind`; `FocusState` keeps its own `mark`. Journalled as the plain `.mark`, no value (`FV-B`).
- `everyStateWriteSiteIsClassified` gains the `seeds` column (`"State.swift": (0, 0, 0, 1)`).
- Divergence 125 retired, 210 added; `LC-S` item 1 overturned with notes in the lifecycle decisions, `identity-state.md`, `retained.md`, `drawing.md`, the guide, `api-overview.md`, `migration.md` (the `owner = UUID()` and parameter-seeded rows), comments in `MetalViewDemo`, `ControlsDemo`, `MetalViewTests`, `Jotter`.
- **Tests that moved:** `aNeverWrittenStateDefaultIsReseededSoOnAppearAndOnDisappearSeeDifferentInstances` became `aNeverWrittenStateDefaultKeepsItsFirstEvaluationForTheViewsLifetime` (`["start 1"]`, `["stop 1"]`, `made > 1`); `aStateBoxForgetsTheOccurrencesOfAnEarlierGeneration` expects the dead slot to read its seed 0, not `nil`. The full unfiltered run before the new files existed (default build system) failed only that second test; every table read the plan listed for adjudication stayed green.
- **New:** `StateFirstValueTests` (`aSeedFromAParentParameterDoesNotFollowIt`, `aReturningSeededStateStartsFresh` x 3 arms, `aSeedIsNotAWriteAndIsVersioned`, `aSeedWritesNothingAndLeavesTheWindowClean`, `aSeededStateInAListRowHoldsWithinTheBoundButNotPastIt`, `aSteadySeedingMarkAllocatesNothingMore`, `anAnyElementSwapKeepsTheSlotOfTheTypeItReplaced` x 2 arms), `StateFirstValueRetainedTests` (`aSeedDoesNotTaintARetainedRecord`, `aGraftedOccurrenceKeepsItsSeededEntry`), `LifecycleTests` (`aGhostParkedOnDisappearReadsTheSeededInstance`, `closingTheWindowStopsTheSeededInstance`).

## 3. For callers (the `owner = UUID()` shape)

- `@State var owner = UUID()` is **one UUID for the element's lifetime** (it was a new one every build, so a value compared against an "owner" from an earlier build could never match). A site that relied on the re-mint (a fresh id per build) now gets a stable one; a site that wanted stable (the usual intent) starts working.
- A `@State` seeded from a parameter (`init(v: Int) { _s = State(wrappedValue: v) }`, or a memberwise `@State var s: Int` the parent sets) **stops following the parent** until written. Use the parameter, a `Binding`, or an `.onChange(of:)` write.
- A reference default (`@State var monitor = Monitor()`) is one instance: `onAppear` and `onDisappear` reach the same one.
- The `StateTable` holds one entry per declared `@State`; `sweepThreshold` (256) engages sooner.
- An `AnyElement` swapped between two types at one position carries the old slot (210).
- In this repo `ProposalGroupEntryTests.swift:31` and `ListTests.swift:861` (the plan's init-seeded sites) stayed green.

## 4. Mutations (each applied to the declaration its test is named for, restored; `git status` clean after)

Applied from the committed tree by `/tmp/r41b-mut/run.py` (a script that edits one file, runs the filtered suites under the default build system, restores with `git checkout --`). Names are tests that reddened; arguments of a parameterised test are not separated in the log.

| mutation | reddened |
|---|---|
| M1 the seed removed from `State.bind` (`mark(slotID)`) | `aNeverWrittenStateDefaultKeepsItsFirstEvaluationForTheViewsLifetime`, `aSeedFromAParentParameterDoesNotFollowIt`, `aReturningSeededStateStartsFresh`, `aSeedWritesNothingAndLeavesTheWindowClean`, `aSeededStateInAListRowHoldsWithinTheBoundButNotPastIt`, `aGhostParkedOnDisappearReadsTheSeededInstance`, `closingTheWindowStopsTheSeededInstance`, `aGraftedOccurrenceKeepsItsSeededEntry`, `anAnyElementSwapKeepsTheSlotOfTheTypeItReplaced`, `aStateBoxForgetsTheOccurrencesOfAnEarlierGeneration`, `everyStateWriteSiteIsClassified` (the `seeds` row) |
| M2 the seed overwrites a present entry | most of that set plus 14 existing state tests that write (`aClickWritesTheStateOfTheOccurrenceThatWasClicked`, `aListRowsStateSurvivesABoundedExcursionButNotALongerOne`, `onDisappearReadsItsOwnStateAsItWasLastFrame`, `stateInsideAnAnyElementPersistsAcrossFrames`, ...), `aSeedIsNotAWriteAndIsVersioned`, `aSteadySeedingMarkAllocatesNothingMore`, `aSeedDoesNotTaintARetainedRecord` |
| M3 the seed stored through `write` (dirty, `onWrite`, taint) | `aSeedIsNotAWriteAndIsVersioned`, `aSeedWritesNothingAndLeavesTheWindowClean` |
| M4 the seed's version 0 | `aSeedIsNotAWriteAndIsVersioned` |
| M5 the seed reads the version counter and does not advance it | `aSeedIsNotAWriteAndIsVersioned` |
| M6 the seed taints `retainLog`, `prepaintLog` and the build journal | `aSeedDoesNotTaintARetainedRecord` (**first run green**: the test's seeded state was the occurrence's own, bound before its recorded window opens; a seeded child inside the card was added, then this) |
| M7 the seed boxed into `Any` before the lookup | `aSteadySeedingMarkAllocatesNothingMore` |
| M8 `staleAfterGenerations` 2 to 3 | `aSeededStateInAListRowHoldsWithinTheBoundButNotPastIt`, `aListRowsStateSurvivesABoundedExcursionButNotALongerOne` |
| M9 `noteAbsent` queues nothing (the `if` reset) | `aReturningSeededStateStartsFresh`, `aGraftedOccurrenceKeepsItsSeededEntry`, `aSeedIsNotAWriteAndIsVersioned` and 11 existing reset tests (`contentAnIfRemovesIsResetWhenItReturns`, `anIfElseBranchFlippedAwayAndBackStartsFresh`, ...) |
| M10 `noteNamed` does not queue a departed name (the `.id` reset) | `aReturningSeededStateStartsFresh` |
| M11 `noteLoop` records no extent (the loop reset) | `aReturningSeededStateStartsFresh`, `aShrinkingForLoopLeavesTheTrailingSiblingsStateAlone` |
| M12 the parked `onDisappear` built with `departed: nil` | `aGhostParkedOnDisappearReadsTheSeededInstance`, `aNeverWrittenStateDefaultKeepsItsFirstEvaluationForTheViewsLifetime`, `aGhostParkedOnDisappearReadsTheStateItsElementHad` and four more existing |
| M13 a second `mark(_, seeding:)` in `Frame.swift` | `everyStateWriteSiteIsClassified` |
| M14 the graft's `.mark` replay dropped | `verifyChannelNamesALifecycleStoreMismatch` only: **nothing seed-specific**; the paint record's `marks` replay (`RetainedSubtree`) keeps the entry live by itself |
| M14b the graft's `.mark` replay **and** the record's `marks` replay dropped | `aGraftedOccurrenceKeepsItsSeededEntry`, `aSeedDoesNotTaintARetainedRecord`, `verifyChannelNamesALifecycleStoreMismatch` |
| M15 an illustrative fix: `AnyElementBox` binds and lays out under an id keyed by `E.self` | `anAnyElementSwapKeepsTheSlotOfTheTypeItReplaced` (both arms); `stateInsideAnAnyElementPersistsAcrossFrames` and `...IsReboundForPrepaintAndPaint` stay green |

The plan's vehicle for the graft arm (`testingCorruptGraftRecords("marks")`, `TestingHooks.swift`) did not separate a seeded entry in a test of its own: with the graft's `.mark` damaged the record's marks keep the entry live (the digests stay equal), which is why M14 reddens nothing seed-specific. The verify-mode channel test `aVerifiedGraftThatDiffersTraps` covers
the graft's `marks` in verify mode.

## 5. Counts and checks

`swift package clean`, `swift build --build-system native --build-tests`, `swift test --build-system native --no-parallel`, unfiltered, 2026-11-03: **`Test run with 4997 tests in 14 suites passed after 307.460 seconds`** (PR A's record read 4986 at its last run; the first unfiltered run of this branch, after the
same clean, read 4997 with one failure, `aBehaviourWordHasAPinOnItsLine`: the guide sentence on the `AnyElement` swap had no pin, fixed by naming `anAnyElementSwapKeepsTheSlotOfTheTypeItReplaced`), 0 failures; `FR-J no-argument frame: succeeded=true` (guards ran). The counts line of `CLAUDE.md` is not replaced (the batch's three PRs
re-take it once). `zsh docs/probes/record-05-check.sh`, `closeout-inventory-check.sh` and `closeout-undocumented.sh` print nothing (the `any-element` family carries 210 and `FV-C`, `state` carries `FV-A`, `FV-B`; no public declaration changed).

**Verify modes**, filter `Retained|Graft|StateFirstValue|LifecycleTests|StateTableTests|TombstoneTests|OccurrenceIdentity|ContentMemo|Equatable|EnvironmentEpoch|EnvironmentReading|IdentityTests|ConditionalIdentity` under `--build-system native --no-parallel`: `METALUI_VERIFY_RETAINED=1` **422 tests in 9 suites passed (74.132 s)**; `METALUI_VERIFY_LAYOUT_MEMO=1` **422 tests in 9 suites passed (118.681 s)**.
`METALUI_RUN_100K_LIST_TEST=1 ... --filter aListsWorkIsTheSameFor100kRowsAsFor500` passed (25.165 s): the work a 100k-row list does is the same as 500 rows' with the seeds (that test counts work, not time).
Not run: `Backends/SDL` tests (no source there changed), the Windows/Linux CI jobs (`StateFirstValueTests` is `#if canImport(Darwin)`; the retained tests are Darwin-only by their target), a human look (there is none to take). No window or desktop interaction was needed beyond the headless fake platform windows.
