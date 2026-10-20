# F3 - memo and retained observation off the main thread - design

Item F3 of the gpui-gap list (MetalCreator report, 2026-10-02). Rulings: `../2026-10-19-memo-observation-thread-decisions.md`
(prefix `MO-`). Record: `docs/record/123-memo-observation-thread.md`.

**Status: LANDED with two pin gaps open** (record 123 §6: the retained handle and `MO-F` have no macOS-reddening pin; spec test 5 dropped, `MO-H`; verification list unfinished). Branch `fix/memo-observation-thread` from `4d91f27f`.
No public API, no divergence (labels 535-544 reserved, none taken), no `Platform`/`PlatformWindow` requirement, no shader change.

## 1. The defect (hypothesis verified by reading the source; the Linux red is the implementer's first step)

`.equatable()` skips its getter while `ContentMemoStore.Entry.stale == false` (`materialize`, `ContentMemo.swift` ~200), and a
subtree is replayed or grafted while `Entry.observedChange == false` (`RetainedSubtree.swift` ~550, `RetainedGraft.swift` ~264/294,
`RetainedPrepaint.swift` ~164). Both flags are set only by `ContentMemoHandle.fireOnMain` / `RetainedHandle.fireOnMain`, reached from
the observation `onChange` through `fire()`, which branches on `Thread.isMainThread`: true runs `fireOnMain` synchronously, false
queues `Task { @MainActor in … }`. Off Darwin, Swift Testing runs main-actor code on a pool thread, so `isMainThread` is false for a
write made from main-actor test code (record §106 `RU-A` found the same for `Window.markDirtyFromObservation`). The write returns, the
test renders at once, the queued task has not run, `stale` is still false: the getter is skipped, the old content is grafted. macOS
is right only because its main-actor code really is on the main thread. Without `.equatable()` there is no memo, so it is correct
(the whole-window sentinel only dirties the window; it decides nothing). The same flaw covers a genuinely different thread: the flag
arrives a hop late, so a frame that starts after the write returns can still skip.

`Thread.isMainThread` audit (grep, `Sources/` and `Backends/SDL/Sources`): `ContentMemo.swift:34`, `RetainedSubtree.swift:277` (the
defect); `Window.swift:1454` (dirty-only, `RU-A` already guards the flush; a late dirty costs latency, never stale content: unchanged,
`MO-C`); `StackMeter.swift:108/116` (debug counter guard, writes happen on the main thread by construction; unchanged);
`AppKitAccessibility.swift:55` (AppKit only, a real main thread; unchanged); `SDLGPUDevice.swift:59/68` (SDL requires the real
main thread; unchanged). Two sites change.

## 2. Design (rulings `MO-A`…`MO-E`)

Make the **decision state** thread-safe and written synchronously by the `onChange`, whichever thread calls it; keep the main-actor
bookkeeping (armed count, window dirtying) where it is.

- New internal `final class MemoFlags: @unchecked Sendable` (file `ContentMemo.swift`), one per `Entry`, one `NSLock`, fields
  `serial: Int`, `stale: Bool`, `observedChange: Bool`, plus one `serial` per `RetainedSession`. `Entry.serial/stale/observedChange`
  and `RetainedSession.serial` become computed properties forwarding to it, so no call site changes (the main actor reads and
  writes them as before; the lock is uncontended).
- `ContentMemoHandle.fire()`: take the lock; if the entry's serial equals the handle's, set `stale`; release; then do the old
  main-actor part (`armed -= 1`, `markDirty`) synchronously when `Thread.isMainThread`, else through the hop. `RetainedHandle.fire()`
  likewise sets `observedChange` under the lock when the session serial matches. The handle holds the `MemoFlags` **strongly** (a
  leaf object that references nothing else, so no cycle through the model's registrar) and `entry`/`store`/`session` weakly as today
  (`IV-R`, `IV-S`).
- The flush ordering stays load-bearing: bump the serial (under the lock), then write the token; the old session's handler sees a
  moved serial and ignores it, on any thread. `materialize` clears `stale` **in the same locked step as the serial bump**, before the
  getter runs, not after it (today's clear after the getter drops a write that lands during evaluation; ruled `MO-D`).
- No `Mutex` (needs Swift 6 stdlib availability off Apple platforms and macOS 15); `NSLock` is Foundation, present on all three
  platforms and already a `ContentMemo` import.

SwiftUI/gpui: not SwiftUI-facing (no probe owed). SwiftUI's `@Observable` invalidation is synchronous with the write on the main
actor; the fix restores exactly that. gpui's `cx.notify()` sets a dirty flag synchronously on the entity; same shape.

## 3. Files and lanes

One lane (Opus/Sonnet implementer, one agent): `Sources/MetalUI/ContentMemo.swift`, `Sources/MetalUI/RetainedSubtree.swift`
(`RetainedSession`, `RetainedHandle`), `Sources/MetalUI/EquatableComponent.swift` only if a write site needs the property form;
tests `Tests/MetalUITestingTests/MemoObservationThreadTests.swift`, guard additions in
`Tests/MetalUITests/ContentMemoCompileGuards.swift` only if a type becomes reachable (none expected). No `Backends/SDL` change, so
the SDL package run is a sanity build only; the Linux image runs the root portable tests (`MetalUITestingTests`).

## 4. Tests (all in `MemoObservationThreadTests`, portable: `MetalUI` + `MetalUITesting`, serialized through the `MemoGate` pattern)

Fixture shapes: `Store` is `@MainActor @Observable final class` with `var colour`; `Box: Component, Equatable` with `let rect`,
`==` on `rect` only, `@Environment(Store.self) var store: Store?`, content `Rectangle` filled from `store.colour`; built as
`Box(rect:).equatable()` inside a non-equatable parent. `Plain` is the same with a captured `let model: Store` (no environment).
A frame is `setNeedsRedraw()` + `tick()` (no `runUntilIdle()`, `DG-P`); reads are `FrameWork` counters (`lastEvaluations`,
`lastSkips`) and the painted colour from the scene.

| # | name | asserts | red before the fix | mutation that must redden it |
|---|------|---------|--------------------|------------------------------|
| 1 | `anObservedWriteOnTheMainActorIsSeenByTheNextFrameThroughAnEnvironmentStore` | frame 2 steady: 0 evaluations, 1 skip; write on the same instance; next frame 1 evaluation and the new colour | Linux image: red (pool-thread main actor); macOS: passes, recorded | restore `Thread.isMainThread` branching in `ContentMemoHandle.fire` without the locked flag set |
| 2 | `…ThroughAPlainObservedModel` | same, model captured | Linux red; macOS passes | same |
| 3 | `…ForTheRetainedReplayAndTheGraft` | `.equatable()` over a leaf whose content is retained; after the write the record is not replayed (`FrameWork` replay/graft counters 0, element paints > 0) and the paint is the new colour | Linux red | restore the branch in `RetainedHandle.fire` |
| 4 | `aWriteFromAnotherThreadIsSeenBeforeTheWriterReturns` | a `Thread` writes `store.colour` (the store is a non-main-actor `@unchecked Sendable` `@Observable` test class, `MO-G`), the test joins without yielding, then renders: re-evaluates | red on **macOS and Linux** (the hop has not run) | same as 1 |
| 5 | `aWriteDuringTheGetterSurvivesTheEvaluation` | a write inside the getter (after its read) leaves `stale == true` after `materialize`; the next frame evaluates once more | red on both (clear-after-getter) | move the `stale = false` back after the getter |
| 6 | `aRetiredSessionsLateFireChangesNothing` | re-evaluate twice, then fire the first handle (retained via the flush): `stale` stays false, `armed` unmoved on the next hop | passes before (guards `IV-L` item 5); the pin that the lock keeps ordering | drop the serial compare in `fire()` |
| 7 | (existing `MemoryReleaseTests`, not a new pin) | unchanged and green (`IV-R`): the `MemoFlags` hold creates no cycle | passes before | make a handle hold `entry` strongly |
| 8 | `aChangeDuringARecordsFrameIsNotErasedByItsClear` | a write between arming and the record's clear leaves the record unreplayed next frame (`MO-F`) | red on both if the plain clear is kept | restore the plain `observedChange = false` |

Exit/trap: none. Counters are `FrameWork`'s existing ones; no new public surface. Run with `METALUI_VERIFY_RETAINED=1` and
`METALUI_VERIFY_LAYOUT_MEMO=1` once (green, no trap). Mutation rules per CLAUDE.md: commit first, full unfiltered native suite,
`git status --short` after each, name reddened tests. Tests 1-3 are also run in the `metalui-portable` Linux image before the fix
(red recorded) and after (green); tests 1-5 gated for Windows by CI.

## 5. Demo, human checks

No demo change (a work-count fix; `METALUI_INVALIDATION_DEMO=1` unchanged, 14 images 0 px against `4d91f27f` via
`docs/probes/demo-pixels/compare.sh`). Human checks: none (nothing a person sees differs on macOS). Windows is CI-only; note in the
record that the Windows red was not measured locally.

Rulings `MO-F` (lost update at the two clear sites) and `MO-G` (handle holds) amend sections 2 and 4; `MemoFlags` also carries `changes`.

## 6. Deferred (named)

- Dirtying the window synchronously when the write is on a pool-thread main actor: latency only (a frame later), unchanged
  from `RU-A`; owner F3 follow-up if a harness test needs it, not blocking.
- `@FocusState` and uncomparable readings stay refused (divergence 346, C14-c2).
- Moving `armed` accounting off the hop: test 2.7 reads it on the main actor; no value.
