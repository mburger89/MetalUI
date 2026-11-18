# 381 - Terminal performance and closeout (`TRM-BK`)

Branch `feat/terminal-perf-closeout` on master `b19462f9`. Plan Phase 6. No divergence, no public API (the new test seams are `package`/`@testable`; `MetalUITerminalTests` gains the `MetalUITestSupport` dependency for the allocation counter).

**Guards, existing versus added.**

| Budget | Where | State |
|---|---|---|
| Output frame 0 builds, 0 element requests, one draw | `outputIsASurfaceOnlyFrame`, `aHundredFeedsAreOneDraw` (TerminalViewTests) | existed |
| Blink frames the same, stop after 30 s | `theBlinkStopsThirtySecondsAfterTheLastOutput` | existed |
| Selection frame the same | `aSelectionFrameIsSurfaceOnly` | **added** (found: a selection set from outside costs one more, empty frame, the Copy text fetch) |
| Glyph instances at most damaged x cols + rects | `glyphInstancesAreBoundedByDamagedCellsPlusRects` | **added** (rects counted as instances over the sink's solid square) |
| Snapshot O(damaged rows), identity sharing | `publishedRowsAreSharedUntilTheyChange`, `untouchedRowsKeepTheirStorageAcrossTakes`; `SnapshotCostTests` at 200 x 60 | existed, **widened** |
| `onResize` only on a change | `onResizeFiresOncePerRealChange` | existed |
| Idle 0 timers, 0 wakeups | `anUnfocusedIdleViewDrawsNothing`, `aSteadyCursorSchedulesNothing`, `inputRestartsTheBlinkIdleClock` | existed |
| Scrollback 4 MB | `ScrollbackCensusTests` (`ScrollbackRing.byteCensus`) | existed; measured **1 927 680 B** (192 per row) |
| 0 allocations per `feed` | `FeedAllocationTests` (macOS, release) | **added**; plain 1 per 2 000 lines, scroll 1 per line, SGR 4 per line (not met) |

**Bench** (`METALUI_RUN_TERMINAL_BENCH=1 swift test -c release --filter TerminalBench`, this Mac, Apple silicon): plain ASCII 424 MB/s (target 300), SGR-heavy 88 MB/s (80), 200 x 60 full-grid surface frame 1.15 ms (1; one row 19 us), key to `onInput` 0.7 us, reflow of 10 000 rows 2 ms. Floors asserted: 20, 5, 50 ms, 5 ms, 50 ms.

**Fuzz.** `FuzzSoakTests`: 2 000 iterations always on, 400 000 gated (`METALUI_RUN_TERMINAL_FUZZ=1`, 25 s in debug), green. Its first draft failed on the cursor invariant: scrolled back, `TerminalSnapshot.cursor.row` is the live row plus the offset and the cursor is hidden (by design); the invariant says so.

**CI.** `.github/workflows/swift.yml`, `root-windows`: `swift build -c release --product MetalUITerminal` and `--product MetalUITerminalUI` after the existing release build of `MetalUI`. Not run locally on Windows (the VM was not used; CI covers it); both products build in release on macOS (the bench build).

**Mutations** (each shown red once): see the headers. `publishSnapshot` with `full = true` (SnapshotCostTests 42 issues); the draw that finds the selection changed calling `trigger.requestRedraw()` (aSelectionFrameIsSurfaceOnly); each glyph appended twice (instance bound); `resize` without the cursor column clamp (FuzzSoakTests, then a trap); `feed` copying its input (FeedAllocationTests: plain 2 001, SGR 10 001, scroll 4 000).

**Deferred.** Keypad digits under DECKPAM (AppKit and SDL), the ⌘-held pointing hand, the cost of selection-drag frames beyond surface-only, SGR allocations, a full-grid frame 15% over 1 ms. See `TRM-BK` item 6.
