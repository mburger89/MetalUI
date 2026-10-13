# `runUntilIdle()` after a click on Linux — design

Item C29 (user request 2026-10-02; not a plan task), found by item 10b (record 103, `DG-P`).
Rulings: [`../2026-10-13-rununtilidle-linux-decisions.md`](../2026-10-13-rununtilidle-linux-decisions.md).
Record: `../../record/106-rununtilidle-linux.md`.

**Status: LANDED** (record §106; one lane verified `ok`).

## 1 The defect

In `swift:6.4-noble` on arm64, `TestWindow.runUntilIdle()` throws `notIdle(rounds: 64)` once a window
has drawn a second frame — after a `Button` click, whatever the action. macOS returns idle.

## 2 Cause (measured)

`Window.markDirtyFromObservation()` chooses between a synchronous branch and a hop by
`Thread.isMainThread`. The per-frame sentinel flush (`drawFrameIfNeeded`) writes
`redrawSentinel.tick` under `isFlushing`, which trips the previous frame's armed session, so
`onChange` fires synchronously on the flushing thread. When the main *actor* runs on a thread that
is not the process's main thread (Swift Testing's async tests and `TestWindow` on Linux), the
synchronous branch is skipped: the callback hops with `Task { @MainActor }`, and by the time the hop
runs the flush has returned, `isFlushing` reads `false`, and `setNeedsRedraw()` dirties the window.
Every drawn frame after the first therefore schedules the next. Probe (Linux, after one click):
`Thread.isMainThread == false`, `observationDirtyings` 1, 2, 3, … one per round, `needsRedraw`
true each round, `hasActiveAnimations` false.

Not the cause: the pressed wash (`hasActiveAnimations` false throughout), the main-queue drain, a
tooltip timer.

## 3 Fix

`Window` keeps the flushing thread (`FlushingThread`, a lock-guarded reference) set for the duration
of the flush; `markDirtyFromObservation` returns at once when called on that thread. A write from
any other thread still hops; a main-thread write outside a flush still dirties synchronously.
`runUntilIdle`'s bound and quiet-yield count are untouched.

## 4 Tests

`RunUntilIdleAfterClickTests.swift` (portable, plain imports): 3.1 a click then `runUntilIdle()`
returns; 3.2 an `@Observable` write after a click is still drawn, then idle. Red before the fix in the
Linux image, green after; mutations in the record.
