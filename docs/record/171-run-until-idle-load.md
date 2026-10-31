# 171 — `runUntilIdle()` under load, and `runUntil` (`HT-Y`)

2026-10-31, branch `fix/run-until-idle-load` from master `d2797c5d`. Report from the MetalFlow app session (low priority): three
tests in MetalFlow's `CommandTests.swift` — `quitWithDirtyDraftSaveThenQuits`, `dirtyDraftAndRunningRunsAsksBothInOrder`,
`closingTheWindowWithRunningRunAsksAndSuspends` — threw `TestHarnessError.notIdle` ("the window was still drawing after 64 rounds")
a few times a day, only while other suites ran. Records 169 and 170 are claimed by branches in flight.

## The mechanism, measured

A copy of MetalFlow (its tests at `49144ee^`, the version with a `runUntilIdle()` after the last alert answer) was pointed at this
branch, with a temporary per-round trace in `runUntilIdle()` (`D` drew, `.` quiet, `c` the window was closed and the tick drew
nothing, `!` still dirty after the tick; not committed). Every failure printed `..c!c!c!…` (62 `c!` rounds) in the
`runUntilIdle()` after `respondToAlert(button: "Save")` / `"Quit"`:

- Each test's last alert answer starts work that leaves the main actor (`saveDraft`'s `Task.detached` for the file name, the fake
  engine actor's `suspend`), then writes the model and approves the termination (`App.replyToTerminateRequest(true)`) or the close.
- An approved termination closes every window (`AppShell.endEverything`); a closed window draws nothing more (`AS-B` item 4,
  `drawFrameIfNeeded`'s first line). The writes just before the close left `needsRedraw` `true`, and nothing could clear it, so
  every remaining round was dirty and `runUntilIdle()` threw. A higher round cap could not help.
- Load decides only *whether the hop lands inside the four quiet yields* (the throw) or after them (the call returns early and
  MetalFlow's later `waitUntil` sees the reply): 4 of 10 runs failed under 24 `yes` processes on 12 cores, 1 of 14 alone.

With the fix, the same pre-`49144ee` tests passed 15 of 15 under the same load. MetalFlow's current tests (`49144ee`, waiting with
its own `waitUntil` instead) do not call `runUntilIdle()` after the last answer, so they no longer hit it; rewritten with
`runUntil` they passed 10 of 10 under load.

## What changed (`HT-Y`)

- `runUntilIdle()` counts a dirty window that is closed as quiet (`isDirtyAndOpen`), so it returns; its contract is otherwise
  unchanged (four quiet yields, 64 rounds). `Window.needsRedraw` is unchanged.
- `TestWindow.runUntil(timeout: Duration = .seconds(10), _ condition: () throws -> Bool) async throws`: draw if dirty and open,
  read the condition, check the deadline, yield. `TestHarnessError.timedOut(after: Duration)` past the deadline. The deadline is a
  `ContinuousClock` reading, the harness's one wall-clock read, a failure bound only (amends `HT-E` item 4).
- Docs: `HT-Y` in `docs/superpowers/2026-10-09-test-harness-decisions.md` (next `HT-Z`), prefix row, `docs/rules/tooling.md`,
  `docs/testing.md` (the clock section), `docs/api-overview.md`, a `docs/migration.md` row. The public-API inventory's regex row for
  `MetalUITesting` already classifies both new declarations (`closeout-inventory-check.sh` and `closeout-undocumented.sh` print
  nothing). The census `closeout-public-api.tsv` was not re-recorded (it is stale on master too: line numbers in `AnimationScope.swift`,
  `AppShell.swift`).

## For MetalFlow

Replace each `await waitUntil("…") { X }` in the three tests with `try await window.runUntil { X }` (drawing while waiting, the
alert frame included), for example:

```swift
try window.respondToAlert(button: "Save")
try await window.runUntil { platform.terminateReplies.count == 1 }
```

## Tests

`Tests/MetalUITestingTests/HarnessSettleTests.swift`, mutation-verified (the table is in `HT-Y`):
`runUntilIdleReturnsWhenAnApprovedTerminationClosesTheWindowMidSettle` (the MetalFlow shape, deterministic: a main-actor task two
turns into the settle writes the model and approves a `.later` termination; the separating arm reads `needsRedraw` still `true`),
`runUntilIdleTreatsAClosedDirtyWindowAsIdle`, `runUntilWaitsForLateWorkAndDrawsIt` (a write 1000 turns away: `runUntilIdle()`
returns before it, `runUntil` returns with it drawn), `runUntilThrowsTimedOutWhenTheConditionNeverHolds`.

## Counts

Native build (incremental, not after `swift package clean`), `swift test --build-system native --no-parallel --skip AppKitPresentationTests`
(the screen lock was not read, so the presentation tests were skipped as in records 167 and 168): **4613 tests passed** (4609 + the 4
new), `FR-J no-argument frame: succeeded=true`. Guards 285, unchanged (no guard added; not re-tallied by grep).
