# 407: Graft records are copied at the end of the frame, only where a later frame can graft from them (`RK-AG`, G47)

No public API beyond two `FrameWork` counters, no divergence (labels unchanged). Branch `perf/g47-graft-capture-backoff`, base master `361c9944`. **Numbering:** 404 and 406 belong to in-flight PRs, 405 is master's last.

## Problem

Alloy scrolls a 1M-row `Table` inside five nested `.equatable()` occurrences. Every scroll frame each ancestor missed its graft, built, and `closeGraftWindow` copied the table's whole subtree (`LayoutTree.captureSegment`) and the journal slice, for a record the next frame could not use: the same frame's paint was ineligible (`activeAnimation`, `stateWrite`) or ran under the pointer or focus, which leaves the entry with no paint record, and `graftRecord` needs one. Typing into a focused field under a chain of occurrences did the same on every key.

## Change

- `closeGraftWindow` takes the marks (`LayoutTree.captureSegmentMarks`), the journal slice and the top items, and parks a `PendingGraft` in `ContentMemoStore.pendingGrafts`. Refusals decidable at close (taint, audit, items) are reported there as before.
- `Frame.flushPendingGrafts` (after the root's paint, before `StateTable.sweep()`) calls `LayoutTree.completeSegment` and makes the `GraftRecord` only if the entry holds a paint record with a prepaint ledger and complete coverage. The list is cleared when a frame is abandoned for a redo (`resetBuildCounters`, the abandon return) and emptied by every flush: bounded by the occurrences built in one frame, freed with the frame; no per-entry state was added.
- `FrameWork.retainedGraftCaptures` / `retainedGraftCapturesSkipped`.
- Exactness argument: `RK-AG` in the decisions doc. No history, so no backoff to recover from.

## Tests

`GraftCaptureBackoffTests`, four: scroll through five occurrences copies 0 rows (master 30, frame work 3384 requests, no hit, unchanged); six keys into a focused field copy 0 (30), requests 24 unchanged; the first frame after scrolling stops (pointer out, indicator fade out) copies five records and builds as before, the next three graft (0 requests, 564 skipped); the same after focus leaves (skipped, copied, grafted, grafted). Root 7319 to 7323 tests in 79 suites (+4), `--build-system native`, `--no-parallel`. **No existing pin moved**: every steady-frame cost test passed unchanged. One kernel test (`aWindowThatIsNotACleanSubtreeIsRefusedByName`) caught a refusal-order change in the split and was fixed (stray roots are counted after the loop, as before).

## Mutations

Run on the committed code, restored with `git checkout`.

| mutation | red |
|---|---|
| flush captures whatever the entry holds (master's behaviour) | the two cost pins and the typing recovery pin (capture counts only; every `requests`/`hits`/`grafts` comparison stays green: it is today's frame work) |
| flush never captures | both recovery pins (`captures == 5` fails, then the graft frames rebuild) |

## Measurements (release `G47Probe`, `G47_N=100`, interleaved, 3 repeats, load average 4-25)

A first version also deferred the journal slice (shared `ArraySlice`); it saved more time but the shared buffer made `removeAll(keepingCapacity:)` allocate a full buffer per frame and `phys_footprint` rose from about 50 MB to 309 MB on `scrollcells nest`. It was dropped.

| probe | CPU ms median master / branch (3 repeats) | heap in use MB master / branch | live malloc blocks master / branch | `phys_footprint` MB master / branch |
|---|---|---|---|---|
| `scrollcells eq nest` | 10.05, 9.56, 9.97 / 9.25, 9.17, 13.21 (load spike; mins 9.26, 9.19, 9.64 / 8.92, 8.79, 9.30) | 17.8 / 14.0 | about 72,100 / 70,100 | 50.0-51.0 / 48.7-53.9 (no change) |
| `scroll eq nest` | 6.69, 6.73, 10.03 / 6.50, 6.69, 9.71 | 9.3 / 5.7 | about 18,500 / 15,200 | 31-32 / 30 |
| `chat eq` | 3.30, 3.42, 4.74 / 3.29, 4.40, 4.70 (load) | 6.7 / 6.6 | about 15,200 / 14,900 | 26 / 27 |

Time on `scrollcells nest`: about 0.4-0.8 ms by medians, 0.35 by minimums; the remaining close-time cost is the journal copy (0.47 ms a frame measured with timers) and the items scan. Memory: 3.6-3.8 MB less live heap and 2,000-3,000 fewer live blocks on the scrolling probes.
