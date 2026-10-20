# 123 — Memo and retained observation off the main thread

Branch `fix/memo-observation-thread` from `4d91f27f` (master: PR #99, single-instance). **Not a plan task**: item F3 of the gpui-gap
list (user request 2026-10-02), from a MetalCreator report: on Linux aarch64, Linux x86_64 and Windows x64 (macOS correct) an
`.equatable()` `Component` that reads an `@Observable` (the report: an `@Environment(ThemeStore.self)` object) stays skipped and
grafted with its old colours after an observed property changes on the same instance. Spec
`docs/superpowers/specs/2026-10-19-memo-observation-thread-design.md`; rulings `MO-A`…`MO-H` in the new decisions doc
`docs/superpowers/2026-10-19-memo-observation-thread-decisions.md` (next unused `MO-I`). No SwiftUI probe: SwiftUI invalidates
synchronously with the write on the main actor, and this restores exactly that (no SwiftUI-visible difference).

**Numbering.** Written as §123 against master `4d91f27f`; `git fetch` showed `origin/master` still `4d91f27f` at the Record phase and
§122 is the newest record, so §123 stands. Divergence labels 535–544 were reserved for this branch; **none was taken**. No human-checks
group: nothing a person sees differs on macOS.

**Status: LANDED, with two pin gaps open (§6).** One lane, red first in the Linux image per the implementer's report, verified
**`ok: false`**: the fix and four of its six pins are proven, the retained-handle fix and the `MO-F` clear have **no macOS pin that
reddens under their mutation**, and the verification list was not finished. Nothing is claimed beyond that; §6 names each gap and its
owner.

## §0 Baseline

At `4d91f27f`: **3971 tests in 3 suites**, 0 goldens, 248 typecheck guards. Carried: `IV-C` item 2 (both branches of the observation
handler), `IV-L` item 5 (retire the old session by serial, then the token write), `IV-R`/`IV-S` (weak holds), `RU-A` (§106: recognise
the flush by thread, not `isMainThread`), `SB-W`/`RK-N` (the verify switches), `EE-` (readings), `PA-J` (debug-build counts).

## §1 The defect, verified by reading

`ContentMemoStore.materialize` skips an `.equatable()` getter while `Entry.stale == false`, and a subtree is replayed, grafted or its
prepaint replayed while `Entry.observedChange == false`. Both flags were set **only** inside `fireOnMain` of `ContentMemoHandle`
(`ContentMemo.swift`) and `RetainedHandle` (`RetainedSubtree.swift`), reached from the observation `onChange` through `fire()`,
which chose by `Thread.isMainThread`: true ran `fireOnMain` at once, false queued `Task { @MainActor in … }`. Off Darwin Swift Testing
runs main-actor code on a pool thread (the same fact as §106), so a write from main-actor test code took the hop; the write returned,
the test rendered, the queued task had not run, `stale` was still false, and the old content was grafted. macOS is right only because
its main-actor code is on the real main thread. Without `.equatable()` there is no memo (the window's own sentinel only dirties, it
decides nothing), which is why the report saw it only there. **A write from a genuinely different thread had the same flaw**: the
flag arrived a hop late, so a frame starting after the writer returned could skip. The orchestrator's hypothesis held; the Linux red
(§4) is the measurement.

**`Thread.isMainThread` audit** (grep, `Sources/` and `Backends/SDL/Sources`): `ContentMemo.swift` and `RetainedSubtree.swift` (the
defect, changed); `Window.swift` `markDirtyFromObservation` (dirty-only, `RU-A` already guards the flush: a late dirty costs a frame of
latency, never stale content; unchanged, `MO-C`); `StackMeter.swift` ×2 (debug counter guard, writes are on the main thread by
construction); `AppKitAccessibility.swift` (AppKit only, a real main thread); `SDLGPUDevice.swift` ×2 (SDL requires the real main
thread). Two sites changed, five audited and left.

## §2 What landed

- **`MemoFlags`** (`ContentMemo.swift`, internal, `final class … @unchecked Sendable`, one `NSLock`): the entry's `serial`, `stale`,
  `observedChange` and a monotonic `changes`. `Entry.serial`/`stale`/`observedChange` and `RetainedSession.serial` are now computed
  properties forwarding to it, so no call site moved (`MO-A`). Methods `advance()` (serial bump and `stale = false` in one locked step,
  `MO-D`), `fireMemo(serial:)`, `fireRetained()`, `clearObservedChange(ifChangesEqual:)` (`MO-F`).
- **`ContentMemoHandle.fire()`** sets `stale` under the lock first, on any thread, if its serial is still the entry's; only then does the
  main-actor bookkeeping (`armed -= 1`, `markDirty`) run behind the old `isMainThread` branch, now named `bookkeep` (`MO-C`).
  **`RetainedHandle.fire()`** likewise sets `observedChange` and bumps `changes` when its session's serial still matches. Handles hold
  the `MemoFlags` strongly (a leaf referencing nothing, so no `IV-R` cycle) and the entry, store and session weakly (`MO-B`, `MO-G`).
- **`materialize` clears `stale` in the same locked step as the serial bump**, before the getter runs (`MO-D`); the old clear after the
  getter could drop a flag a handler of the new session set mid-evaluation.
- **`RetainedPhase`** reads `changes` when it opens, before the paint session is armed; the record's clear is
  `clearObservedChange(ifChangesEqual:)`, a no-op when a fire moved the count (`MO-F`).
- No public declaration, no `Platform`/`PlatformWindow`/`WindowRenderer` requirement, no shader or SDL change, no `EquatableComponent`
  change (its `observedChange = true` after an evaluation stays a plain locked set). Alternatives rejected in `MO-A`:
  `MainActor.assumeIsolated` (traps on a real off-actor write, no non-trapping isolation query), an atomic (no stable `Atomic` on the
  three toolchains at the macOS 15 floor), draining the queued hop in `materialize` (no hook to run a queued task synchronously).

## §3 Tests and guards

`Tests/MetalUITestingTests/MemoObservationThreadTests.swift` (7 tests, portable: `MetalUI` and `MetalUITesting` only; no test yields
the main actor between a write and its frame):

1. `anObservedWriteOnTheMainActorIsSeenByTheNextFrameThroughAnEnvironmentStore` — the report's shape.
2. `anObservedWriteOnTheMainActorIsSeenByTheNextFrameThroughAPlainObservedModel` — a captured model, no environment.
3. `anObservedWriteOnTheMainActorIsSeenByTheRetainedReplayAndTheGraft` — the retained path (`retainedHits`/`retainedGrafts` 0 after a write).
4. `aWriteFromAnotherThreadIsSeenBeforeTheWriterReturns` — a real `Thread` writes a non-main-actor `@unchecked Sendable` `@Observable`
   store (`MO-G`), is joined with no yield, the next frame re-evaluates. Memo-only (the model is read in a memo getter).
5. `aRetiredSessionsFireChangesNothing` — three re-evaluations then two steady frames skip (guards `IV-L` item 5 under the lock).
6. `aChangeDuringARecordsFrameIsNotErasedByItsClear` — `MO-F`, now through the `package` seam `RetainedTestingHooks.beforeRecordClear`
   (`RetainedSubtree.swift`, run between the record being stored and the clear; the test's hook writes the model once there, so a live
   build session fires after arming and before the clear).
7. `aWriteFromAnotherThreadIsSeenByTheRetainedRecordBeforeTheWriterReturns` — a real `Thread` writes an `@unchecked Sendable` model read
   only by a descendant of an `.equatable()` occurrence (retained session only, no content memo reads it), joined with no yield; the next
   frame has `retainedHits == retainedGrafts == 0` and paints `v1`. Red on macOS.

**The spec's test 5 (a write inside the getter) was dropped** (`MO-H`): `withObservationTracking` installs its registrations after the
body returns, so such a write is invisible to that session on every platform (contentEvaluations read 0 both before and after the
fix in the Linux image). `MO-D`'s clear-before-getter therefore stays as code with **no deterministic pin**. Spec table row 7 is the
existing `MemoryReleaseTests`, run unchanged. **Typecheck guards: 0 new** (no type became reachable; the count is unmoved).

## §4 Red runs (where each pin was measured red)

- **Linux image (`metalui-portable`), before the fix**, implementer's report (`MO-H` 1): tests 1, 2, 3, 4 and the stale-skip part of
  the old test 6 red; all six green after the fix. **This run was not repeated by the verifier or the Record phase**; the log is not
  kept in the tree. Windows red unmeasured (CI only).
- **macOS, before the fix:** tests 1–3 pass (expected: main-actor code is on the real main thread); test 4 is the pin that is red on
  macOS too, as the verifier's first mutation shows (§5).

## §5 Mutation table (verifier, native unfiltered, `3977 tests in 5 suites` at `e55f43c3`; commit first, restore, `git status --short` clean after each)

| mutation | spelling | reddened | verdict |
|---|---|---|---|
| set `stale` only when `Thread.isMainThread` (the old off-main behaviour) | `ContentMemoHandle.fire`, memo branch | `aWriteFromAnotherThreadIsSeenBeforeTheWriterReturns` (2 issues), `ContentMemoWindowTests.aBackgroundThreadWriteDirtiesAMemoWithinOneFrame` | proven |
| `fireRetained()` only when `Thread.isMainThread` | `RetainedHandle.fire` | **nothing** | **gap, §6 item 1 (closed, test 7)** |
| plain `_observedChange = false` (drop the `changes` equality guard) | `MemoFlags.clearObservedChange` | **nothing** (`aChangeDuringARecordsFrameIsNotErasedByItsClear` stayed green) | **gap, §6 item 2 (closed, test 6 reworked)** |

Both survivors ran the full suite: 3977 tests, the only issues the five `AppKitPresentationTests` sheet issues of a locked screen
(`CI-AF`, pre-existing). Not run: the `MO-D` mutation (unpinned by construction), the serial-compare mutation behind test 5, the
`IV-R` strong-hold mutation behind `MemoryReleaseTests`.

## §6 Open at the Record phase (named, with owners)

**Items 1 and 2 are CLOSED by the F3 follow-up** (test 7 and the reworked test 6; measured below). Their original text stays for the record.

1. **The retained-handle fix has no macOS pin.** Tests 3 and 4 do not separate it on macOS: test 4 is memo-only. The pin that does is red
   only in the Linux image. Owed: a deterministic cross-thread retained test (a real `Thread` writes a model only a retained session
   observes, the `MOOuter` shape; assert `retainedHits == 0 && retainedGrafts == 0` on the next frame without a yield), then re-run the
   mutation red on macOS. Owner: F3 follow-up.
2. **The `MO-F` pin does not detect its mutation.** The test docstring names the plain-clear mutation, and it stays green: the budget
   write does not fire a live retained session between arming and the clear. Either build the scenario (the write must land after the
   paint session is armed and before the clear) and show it red, or weaken `MO-F`'s ruling and the docstring to "unproven". The fix itself
   is in the source and harmless (a no-op when no fire landed), so no existing pin moved; its pin is unproven. Owner: F3 follow-up.
3. **Follow-up measurements (native, filtered `MemoObservationThread`, 7 tests):** item 1, `RetainedHandle.fire` `if live && Thread.isMainThread { entryFlags.fireRetained() }`:
   reddened `aWriteFromAnotherThreadIsSeenByTheRetainedRecordBeforeTheWriterReturns` (2 issues: the retained counters and the missing `v1`) and
   nothing else in the filter. Item 2, `MemoFlags.clearObservedChange` replaced by an unconditional `_observedChange = false`: reddened
   `aChangeDuringARecordsFrameIsNotErasedByItsClear` (2 issues). Both restored with `git checkout`. The scenario for `MO-F` can occur only
   after the paint session is armed (a write in paint, or another thread); the guard is needed and now pinned through the hook.
4. **Not run:** `swift build --build-tests` (default build system) warning count, `METALUI_VERIFY_RETAINED=1` and
   `METALUI_VERIFY_LAYOUT_MEMO=1` runs, the fourteen-image comparison against `4d91f27f`, `Backends/SDL` and the Linux image
   re-take after the final commit. The change touches no `Backends/SDL` file and no pixel path; the comparison is owed, not assumed.

## §7 Counts (Record phase, `swift package clean`, native build, native unfiltered run)

`swift package clean`, `swift build --build-system native --build-tests` 0 `error:`, the only `warning:` SwiftPM's deprecation notice; native
unfiltered `--no-parallel` run on a **locked screen**: **`3977 tests in 5 suites`** (3971 + the 6 of `MemoObservationThreadTests`),
0 goldens, **248 typecheck guards** (no guard added, count by construction, not re-grepped), `FR-J no-argument frame: succeeded=true`. The
only issues were exactly the five `AppKitPresentationTests` sheet issues of `CI-AF` (`attachedSheet` on a locked screen) and nothing
else. Not taken: default-build-system warning count, the verify-switch runs, census (no public declaration: the inventory and
undocumented scripts were not run, nothing moved), the fourteen images (§6 item 3).

## §8 Hazards

- A reader of `Entry.stale`/`observedChange`/`serial` must go through the properties (the lock); a stored `var` of those names in
  `ContentMemoStore.Entry` or `RetainedSession` reopens the bug (grep reads 0).
- `armedSessions` (`MO-C`) still lags behind a hop off Darwin: a test must not assert it after a write on a pool-thread main actor.
- The window is still dirtied behind the old branch: a harness test on Linux that expects a click-less write to draw a frame in the same
  turn still needs `setNeedsRedraw()` (`RU-A`, latency only).

## §9 Deferred

- Dirtying the window synchronously for a write on a pool-thread main actor (latency only; `RU-A`). Owner: F3 follow-up.
- `@FocusState` and uncomparable readings stay refused (divergence 346, C14-c2).
- Moving `armed` off the hop: no value.

## §10 Branch checker (adversarial, 4d91f27f..HEAD)

- Clean build (`swift package clean`, native): 0 `error:`, only SwiftPM's deprecation warning. Native unfiltered at `02056538`:
  `Test run with 3977 tests in 5 suites passed after 339.318 seconds.` (unlocked screen), `FR-J no-argument frame: succeeded=true`.
  `cmp CLAUDE.md AGENTS.md` equal. Inventory and undocumented scripts print nothing.
- Fourteen images, `compare.sh <scratch> 4d91f27f HEAD`: 14 of 14 `differing=0`, scene identical, controls as recorded.
- Mutation 1, `ContentMemoHandle.fire` sets `stale` only when `Thread.isMainThread` (full native suite, `3977 tests ... 8 issues`, 5 of them
  the locked-screen sheet issues): reddened `aWriteFromAnotherThreadIsSeenBeforeTheWriterReturns` and
  `ContentMemoWindowTests.aBackgroundThreadWriteDirtiesAMemoWithinOneFrame`. Same mutation plus `RetainedHandle.fire` main-thread-only,
  re-measured in the Linux image (`MemoObservationThreadTests`, 6 tests): tests 1, 2, 3, 4 and `aRetiredSessionsFireChangesNothing` red,
  `aChangeDuringARecordsFrameIsNotErasedByItsClear` green. The implementer's Linux red-first claim is confirmed. Unmutated Linux: 6 of 6 pass.
- Mutation 2, `MemoFlags.fireMemo` drops its serial compare (full suite, 30 issues): reddened 13 tests (`anOwnStateWriteBeatsAnEqualValue`,
  `sessionsNeverExceedLiveEntries`, `aComponentThatReEvaluatesEveryFrameLetsTheWindowIdle`, `lifecycleAnimationAndListInsideAMemoizedComponent`,
  the two `...ArmCostsWhatTheValueArmCosts`, `aReplayMissesWhenAnEnvironmentValueItReadChanges`, `aReaderIsEvaluatedAgainWhenTheValueItReadChanges`,
  `aReaderOfAnotherKeyIsSkippedWhenAnUnreadKeyChanges`, `aCustomEquatableKeyRewrittenEqualIsSkipped`,
  `aNestedOccurrencesObservedChangeRebuildsTheGraftedOuter`, `aReplayedHandlerActsLikeAFreshOne`, `theBracketNodeDragRebuildsTheWholeWindow`)
  but **not** `aRetiredSessionsFireChangesNothing`, whose docstring named it. Docstring and `MO-E` corrected; the pin guards the property only
  through older tests.
- Defect fixed: the spec's test table named tests 5 and 6 as planned; it now says test 5 was not written and test 6 was renamed.
- `Backends/SDL` on macOS: 215 tests, 1 failure `sdlAFileDroppedOnTheAppIsAnOpenURL`, **identical on `4d91f27f`'s `Sources/`**: pre-existing, not this branch.
- Not re-taken: default-build-system warning count, `METALUI_VERIFY_RETAINED=1`/`METALUI_VERIFY_LAYOUT_MEMO=1`, Windows. Pin gaps §6 items 1 and 2 stand.
