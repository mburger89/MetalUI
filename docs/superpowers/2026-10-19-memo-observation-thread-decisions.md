# Memo and retained observation off the main thread - decisions

Rulings for item F3 (MetalCreator report: an `.equatable()` component stays skipped on SDL/Linux/Windows after an observed write).
Spec: [`specs/2026-10-19-memo-observation-thread-design.md`](specs/2026-10-19-memo-observation-thread-design.md). Record:
`../record/123-memo-observation-thread.md`. Branch `fix/memo-observation-thread` from `4d91f27f`. Reserved divergence
labels 535-544: none taken (no SwiftUI-visible difference; SwiftUI invalidates synchronously, which this restores).

Prefix **`MO-`**, lettered. **Next unused: `MO-I`.** (Moves in the commit that appends a ruling.)

**Carried.** `IV-C` item 2 (both branches of the observation handler), `IV-L` item 5 (retire the old session by serial then token
write), `IV-R`/`IV-S` (weak holds), `RU-A` (recognise the flush by thread, not `isMainThread`), `SB-W`/`RK-N` (verify env switches),
`EE-` (readings), `PA-J` (debug-build counts).

## MO-A - The decision flags are written synchronously, under a lock, by whichever thread fires

**Ruling.** `stale`, `observedChange` and the serials the handler compares move into one `NSLock`-guarded `MemoFlags` per entry
(and one per `RetainedSession` for its serial); `fire()` sets the flag under the lock before it does anything else, on any thread.
**Evidence.** Code reading: the only writers of `stale`/`observedChange` are the two `fireOnMain` bodies, reached after
`Thread.isMainThread` (false for a pool-thread main actor, record §106) through an unstructured `Task`; every skip/graft/replay
decision reads those flags on the main actor in the next build. **Cost if wrong.** A lock per flag access (uncontended, a few per
occurrence per frame; pins count work not time); if a reader missed one site the old bug survives there, so the properties keep the
old names and a grep for stored `var stale`/`var observedChange` must read 0.
**Alternatives rejected.** (1) `MainActor.assumeIsolated` for "main actor by isolation": traps on a real off-actor write and there is
no non-trapping isolation query. (2) An atomic: no stable `Atomic` on the three platforms' toolchains (macOS 15 floor). (3) Leaving the
hop and making `materialize` drain it: no hook to run a queued task synchronously.

## MO-B - The handle holds the flags strongly, the entry, store and session weakly

**Ruling.** `MemoFlags` references nothing (Bool/Int and a lock), so the handle's strong hold cannot create the `IV-R` cycle (the
closure lives in the model's registrar; the entry's pristine content holds the model). A fire after the entry is gone sets a flag nobody
reads. **Cost if wrong.** A leak per memo session, caught by `MemoryReleaseTests` (unchanged, must stay green).

## MO-C - The main-actor bookkeeping keeps `Thread.isMainThread`; window dirtying is unchanged

**Ruling.** `armed -= 1` and `markDirty` stay behind the old branch (sync on the true main thread, hop otherwise). They decide
nothing: `armed` is a test counter and a late dirty costs one frame of latency, never stale content, because the flag is already set when
the next decision runs. `Window.markDirtyFromObservation` is untouched (`RU-A`). The other four `isMainThread` sites in `Sources/` and
`Backends/SDL` are audited unchanged (spec section 1). **Cost if wrong.** A harness test that relies on a click-less write dirtying the
window in the same turn on Linux still needs `setNeedsRedraw()`; named as deferred in the spec.

## MO-D - A write that lands during the getter survives the evaluation

**Ruling.** `materialize` clears `stale` in the same locked step that bumps the serial, **before** the getter runs and before the
new session is armed; the old clear after the getter erased a flag set by a handler of the new session mid-evaluation (a write from
another thread, or a write in the getter itself after its read). **Evidence.** `ContentMemo.swift` lines ~218-234 as read at
`4d91f27f`. **Cost if wrong.** One extra evaluation on the following frame for a getter that writes what it read (it already
re-dirties through the sentinel); work-count pins of steady frames are unchanged because a steady frame has no write.

## MO-E - Tests: the Linux red is the proof, plus one deterministic cross-thread red that also fails on macOS

**Ruling.** Tests 1-3 of the spec reproduce the report with `MetalUI` and `MetalUITesting` types only and are measured red in the
`metalui-portable` image before the fix (macOS passing is expected and recorded, not a defect of the pin). Test 4 uses a real second
thread joined without a main-actor yield, so it is red on macOS too and is the pin that does not depend on the test runner's executor.
Mutations run (record 123 §5, §10): the `isMainThread`-only flag set is proven; dropping the serial compare does **not** redden test 6 (it reddens 13 other memo and retained tests); the clear-after-getter and plain-clear mutations are unpinned (`MO-H`).
**Cost if wrong.** If the Linux image already passes tests 1-3 (the report's repro was reached through a different ordering), the
design stands on test 4 and the hypothesis is re-opened in the record, not silently kept.

## MO-F - A change during a record's own frame is not erased by the record's clear

**Ruling.** `RetainedSubtree.swift` ~651 (`entry.observedChange = false` after a record is made) and `ContentMemo.swift` ~234 run after
the occurrence's sessions are armed, so a fire that lands between the arming and the clear (another thread, or a write in paint) is
erased by a plain Bool clear: the same lost-update shape as `MO-D`. `MemoFlags` therefore keeps a monotonic `changes: Int` beside
the Bool; the session handler increments it under the lock, and a record stores the value read **before** its sessions were armed
(`RetainedBuildWindow.init`); the clear at ~651 becomes `clearObservedChange(ifChangesEqual:)` (a no-op when the count moved).
**Evidence.** Code reading of the two clear sites at `4d91f27f`; the `EquatableComponent.swift:90` write (`observedChange = true`
after an evaluation) stays a plain locked set. **Cost if wrong.** A steady frame gets one extra miss after a mid-frame write, which
is correct but moves a work counter: if any existing pin moves, the clear is reverted to today's Bool and the finding recorded as
deferred, not silently kept (the Linux red does not depend on it). Test 8 pins it; its mutation is the plain clear.

## MO-G - The handle holds each `MemoFlags` it writes, and test 4's store is not main-actor

**Ruling.** `RetainedHandle` writes two objects (the entry's flags for `observedChange`/`changes`, the session's for its serial) and holds
both `MemoFlags` strongly, the entry, store and session weakly; a fire never dereferences a weak reference to decide, only to do the
main-actor bookkeeping. Test 4's store is a separate `@unchecked Sendable` `@Observable` class (a `@MainActor` store cannot be written
from a `Thread` without a hop, which is what the test must avoid), read by a component whose getter runs on the main actor.
**Rejected:** table row 7 as a new test (it is the existing `MemoryReleaseTests`, run unchanged, not counted among the new pins).
**Cost if wrong.** A strong hold on a non-leaf object reintroduces the `IV-R` cycle (`MemoryReleaseTests` reddens).

## MO-H - What the implementation measured: MO-D is unpinned, `armed` is not asserted

**Ruling.** (1) The Linux image reddens tests 1-4 and 6 before the fix and passes all six after it (record 123). (2) **Test 5 (a write
inside the getter after its read) was dropped**: `withObservationTracking` installs its registrations after the body returns, so a write
inside the getter is not seen by that session on any platform (the first Linux run read `contentEvaluations == 0` both before and after
the fix); `MO-D`'s clear-before-getter stays as code (the same locked step as the serial bump) but has **no deterministic pin**, only
the window between registration and the old clear, which only another thread can hit. The mutation "move the clear after the getter" is
therefore recorded as unpinned, not as reddened. (3) **Test 6 no longer asserts `armedSessions`**: `armed` is the `MO-C` bookkeeping,
decremented behind the old branch, so on a pool-thread main actor it lags until the next yield; the stale-skip assertion (the part that
decides) stays. **Cost if wrong.** A reader trusting `armedSessions` off Darwin sees a high count until the hop runs.
