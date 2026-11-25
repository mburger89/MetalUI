# 412: allocation churn on the scroll path (`SB-AG`, `RK-AH`, `HP-L`, G47, Alloy)

Class `M` (package declarations, internal types; no public API), no divergence (labels unchanged). Branch `perf/g47-allocation-churn`, base master `4d030e94`. **Numbering:** 411 is in flight.

## The problem

Alloy scrolls a 1M-row `Table` with `.equatable()` cells at about 8.6 ms a frame against an 8.3 ms target. An Allocations run on an older build counted 9.3M allocations in two minutes, 9.1M of them transient, 5.7 GB, and a `closeGraftWindow` closure of 236-267 ms.

## Profile (release `G47Probe`, `scrollcells eq nest`, a `malloc_logger` hook with `backtrace`, 20 scroll steps)

`xctrace record --template Allocations` hung in this sandbox (the target stayed stopped under `xctrace` for 10 minutes), so the attribution is the probe's own: every allocation of the stepping thread hashed by its top frames and reported with its bytes. Before the changes, per scroll step (AX client on, as the probe's default): 39.4k allocations, 20.5 MB.

| Site | per step |
|---|---|
| `closeGraftWindow` copying the journal slice (`BuildJournal.Event`, four windows a frame, 736 KB each) | 4 allocations, 2.9 MB |
| `AccessibilityTreeBuilder.buildResult` dictionaries (only with an AX client) | about 8 allocations, 3.6 MB |
| `Scene.insert` growing the glyph and rect arrays | 12 allocations, 1.5 MB |
| `replayPaint` `op.leaves.flatMap(\.0)`: a `[CapturedPrimitive]` per op | 2688 allocations, 1.2 MB |
| `movedPaintRecord`, the scene moved | 2400 + 2400 + 400 arrays, 1.0 MB |
| `movedPaintRecord`, the same ops moved again as the final stream | the same again, 1.0 MB |
| `TableCellHolder` (a class of 1.8 KB per realised cell) | 410 allocations, 0.7 MB |
| `ComponentLayout.init(grafted:)` | 400 allocations, 0.4 MB |
| `captureSegmentMarks` rows of the nested windows | 18 allocations of 9 KB |
| about 45 sites of one 40-128 B array per cell (`retainedAmbientKey`, `prepaintExtras`, `enteringGroupMember`, the layout's per-cell `[LayoutNodeID]`, `zeroScrollOffsets`...) | 8200 per 20 steps each |

## What the numbers say about the five items

1. **`CapturedPrimitive` arrays**: three sources. The two moves of `movedPaintRecord` (one array per glyph per stream) and the flatten in `replayPaint` (one per glyph per replayed op) are fixed (`SB-AG`). The remaining ones are the scene move itself (one array per glyph, kept: it is the record's new storage) and the `processScopes` copies of the translated replay. A live census of 449-512 B blocks (`G47_LIVE=512` on the probe, a malloc/free ledger by pointer) finds **2400 of the 2874 survivors are those moved arrays**, the record's own storage, and 410 are `PendingGraft.topItems`: the **persistent 512 B blocks are the retained records' per-glyph `[CapturedPrimitive]`**, two streams of them before `SB-AG`, one after.
2. **`movedPaintRecord` double move**: done, `finalIsScene` (`SB-AG`).
3. **`closeGraftWindow` closure #2** is the `.map` that copies `journal.events[recorder.start...]` and rewrites the lifecycle notes. With nested `.equatable()` occurrences every window's slice starts near the front of the journal, so four copies of the whole journal (about 14k events, 736 KB) were made a frame and the flush then dropped them for any occurrence with no paint record. Fixed by keeping the range and copying at the flush (`RK-AH`). The marks (`captureSegmentMarks`) stay: a container built after the occurrence writes to them (`RK-AG`).
4. **Layout arrays** (`Int`, `Double`, `GroupMark`, `LayoutNodeID`, `LayoutMeasurement`, `ProposedSize`): in this probe they are one small array per cell per site (40-128 B, 8200 per 20 steps each, 45 sites: 410 cells, one per frame), not large rebuilt buffers; the probe has no `GroupMark` source (no opacity groups or masks). Dropped: a reserve from last frame's count saves nothing per cell (the arrays are 1-5 elements), and no site is worth 0.5 ms alone. `PrepaintExtras.equalIgnoringScrollOffset` makes two `[Double]` copies per cell (`zeroScrollOffsets` on copies; 2 x 410 allocations of 128 B a step): about 1.5% of the allocations and unmeasurable in time, left alone.
5. **`__StringStorage` (379k, 254 MB) and the persistent 512 B blocks**: the 512 B blocks are item 1 above. No `__StringStorage` source of that size exists in the probe: the Table's own strings are `AnyTableColumn.name`'s `String(describing:)` (30 a frame, 40 B), so Alloy's 670 B average strings are app-side (its code view and file tree) or the text-shaping keys, which another session is changing. Not fixed; report.

## Changes

- `RetainedRecord.finalIsScene` (`SB-AG`): a record made with no paint scope around it keeps `finalScene = scene` (one array), `movedPaintRecord` moves it once, `replayPaint` hands a one-group op's leaves to `insertLeaves` without `flatMap`.
- `PendingGraft.events` is a `Range<Int>`, `BuildJournal.held`/`clearIfIdle()`/`rebased(_:lifecycleBase:)`, `ContentMemoStore.pendingGrafts.didSet`; the flush copies the slice for the entries it makes records for (`RK-AH`). No slice of the buffer is kept: the buffer stays unique and `removeAll(keepingCapacity:)` clears it in place (a held `ArraySlice` made it copy the whole buffer each frame in an earlier attempt: footprint 50 MB to 309 MB).
- `FrameCapacityHints.sceneRects`/`sceneGlyphs` and `Scene.reserveCapacity(rects:glyphs:)` (`package`), an eighth over (`HP-L`).
- `countAllocatedBytes` in `MetalUITestSupport/AllocationCounter.swift`.

## Measurement (release `G47Probe`, base `4d030e94` vs branch interleaved, 6 repeats alternating order, 60 steps each, the machine loaded: load average 18-48 from other sessions' builds)

| Mode (AX client off unless said) | CPU ms median of medians (base, branch) | min of mins | paired delta ms (median; range) | allocations per step | bytes per step | `phys_footprint` at exit (median) | live blocks (median) |
|---|---|---|---|---|---|---|---|
| `scrollcells eq nest` | 18.30, 15.04 | 8.32, 7.02 | -3.11 (-3.96 to -2.02) | 35503 to 27546 | 15.2 to 8.6 MB | 49.8 to 38.0 MB | 66291 to 60613 |
| `scrollcells` (plain `Text` cells) | 16.52, 15.43 | 8.82, 7.83 | -0.99 (-1.64 to -0.37) | 35329 to 30068 | 11.4 to 9.0 MB | 37.2 to 34.0 MB | 59550 to 54017 |
| `scroll eq nest` (plain `Text` in a `Table`) | 13.52, 11.82 | 7.98, 6.24 | -1.72 (-2.01 to -1.54) | 27092 to 24345 | 15.6 to 10.6 MB | 36.8 to 26.2 MB | 15022 to 15036 |
| `scrollcells eq nest`, AX client on | 21.68, 18.85 | 12.29, 10.51 | -2.29 (-2.83 to -0.54), 5 repeats | 39457 to 31454 | 20.5 to 13.8 MB | 57.2 to 50.9 MB | 68037 to 62374 |

The machine was loaded throughout (load average 18-55), so the absolute milliseconds of this table are inflated (an earlier, quieter run of `scrollcells eq nest` read 11.4 and 9.7 ms, paired delta -1.71 ms, min of mins 7.8 and 6.5); the paired deltas and the allocation counts are the evidence. Footprint is the process's `phys_footprint` after the run (`TASK_VM_INFO`), live blocks `malloc_zone_statistics` after it; neither rises.

Ablation (each change turned off alone in a temporary build, 5 rounds interleaved, `scrollcells eq nest`, AX off): all four off 10.45 ms median of medians; all on 8.84; `SB-AG` replay alone off 10.09 (+2688 allocations, +1.2 MB); the stream sharing alone off 10.90 (+5214, +1.5 MB); the journal copy back 10.58 (+4 allocations, +2.9 MB); the scene reserve off 10.22 (+51 allocations, +1.1 MB). Each is worth at least 0.5 ms on its own in that run; the sum exceeds the interleaved paired delta because the ablation run drifted with the load, so the paired delta of the finished branch (below) is the number to read.

Live census: the surviving blocks of the retained records halve (`SB-AG`), 66.2k to 60.6k live blocks, no pool or buffer is added, the journal's capacity is the peak of one frame as before.

## Pins and mutations

`ScrollAllocationChurnTests` (two tests: a scroll step and a redraw of a table of `.equatable()` cells in three nested `.equatable()` wrappers beside a static `.equatable()` pane; ceilings on allocations and bytes, `countAllocatedBytes`); `theSecondFrameReservesWhatTheFirstFrameHeld` and `aFrameWithNoHintStartsEmpty` gained the scene's counts. Debug build, scroll step / redraw, allocations and bytes:

| Build | scroll step | redraw |
|---|---|---|
| branch | 66027 / 4604158 | 57710 / 3785794 |
| `finalIsScene` ignored (double move) | 74011 / 5276766 | 60713 / 3977658 |
| `replayPaint` flattening every op | 68427 / 5013758 | 60109 / 4195130 |
| journal slice copied at the close | 67237 / 4951614 | 58919 / 4132986 |
| scene reserve removed | `theSecondFrameReservesWhatTheFirstFrameHeld` red (`start.sceneRects >= held.sceneRects`) | |

Ceilings: 66600 allocations and 4.70 MB (scroll), 58300 and 3.88 MB (redraw): each mutation goes over at least one of them. Steady-frame pins: `aNonAnimatableComponentAllocatesWhatItDid` improved 322 to 319 (the scene's arrays grow three times less), every other cost pin is unchanged. Full run: 7358 tests in 80 suites, green after that literal (`--build-system native`, `--no-parallel`).

## Dropped

- Moving `movedPaintRecord` in place (the biggest remaining item: one array per glyph per cell, about 5k allocations and 1 MB a frame): a refusal midway would leave a half-moved record, so it needs a validating pass first, and the record may be shared with the paint translation memo and verify mode. Not attempted.
- `AccessibilityTreeBuilder.buildResult` dictionaries (only with an AX client): not on the scroll path's list; with a client attached they are 3.6 MB a frame.
- Per-cell small arrays (item 4 above).
