# `runUntilIdle()` on Linux — decisions

Rulings for item C29. Spec: [`specs/2026-10-13-rununtilidle-linux-design.md`](specs/2026-10-13-rununtilidle-linux-design.md).
Record: `../record/106-rununtilidle-linux.md`.

Prefix **`RU-`**, lettered. **Next unused: `RU-C`.** (Moves in the commit that appends a ruling.)
Branch `fix/rununtilidle-linux` from `848ee029`. Reserved divergence labels 365–374: none used.
No SwiftUI claim, so no probe.

**Carried items.** `RX-K`/`RX-S` (the flush ordering and `isFlushing`), `HT-S` item 1 (`runUntilIdle`),
`DG-P` (the guides' workaround).

## RU-A — The sentinel flush's own change is recognised by thread identity, not by `Thread.isMainThread`

**Ruling.** `markDirtyFromObservation` returns when called on the thread running the flush
(`Window.flushingThread`, set and cleared with `isFlushing`). **Reasoning.** `isFlushing` is
main-actor state; a callback that cannot prove it is on the main thread can read it only after a hop,
too late. The flush fires `onChange` synchronously on its own thread, so identity of that thread is
the one fact available without a hop. **Evidence (measured, Linux arm64).** Before: 6 of 6 rounds
dirty, `observationDirtyings` 1…6; after: 0 and `runUntilIdle` returns. **Cost if wrong.** A write
from another thread landing exactly during a flush is hopped as before; a write on the flushing thread
during the flush can only be the sentinel's. macOS is value-identical (the flushing thread is the main
thread there).

## RU-B — The 64-round bound, the quiet-yield count and `TestWindow` are untouched; the DG-P workaround can go

**Ruling.** The defect was in `Window`, not the harness. **Evidence.** The guides tree
(`docs/guides` at `9f8b6c35`) with this fix and its one `setNeedsRedraw()`/`tick()` workaround replaced
by `try await runUntilIdle()` passes all 167 `MetalUITestingTests` in the Linux image. The guides'
text is left to item 10c; it may drop the "(the observation hop is asynchronous off macOS)" caveat
and `DG-P`'s advice. **Cost if wrong.** None; the workaround still works.
