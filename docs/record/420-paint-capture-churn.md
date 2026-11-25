# 420: the paint path's capture arrays, group scenes and layout dictionaries (`HP-M`, G51, Alloy)

Class `M` (package declarations, internal types; no public API), no divergence (labels unchanged). Branch `perf/g51-paint-capture-churn`, base master `aadf3f11` (#432). **Binding rule from the Alloy peer:** fast and small; memory counts as much as frame time; every cache bounded.

## The report

Alloy streaming one 23 KB reply into a bottom-anchored `LazyVStack` of `.equatable()` rows: 230 MB/s of heap allocation, a footprint of 700-840 MB mostly `Malloc Large (empty)`, and `_ContiguousArrayStorage<CapturedPrimitive>` regrowing 16 times and 1.9 MB a frame. A second run, scrolled up with a longer transcript, read 436 MB/s: the suspicion was a cost that scales with the transcript, not the window.

## Does it scale with N? No

Fixture (`G51Fixture.swift`): `ScrollView(.defaultScrollAnchor(.bottom)) > LazyVStack(spacing 10) > ForEach > ChatRow.equatable()` with rounded tinted chrome and three `.equatable()` 110-word paragraphs a row, one row streaming a word a frame, a 600 x 800 window at scale 2, no accessibility client; debug build, harness text system. The whole of it sits in a composite scope (`.compositingGroup().opacity(0.98)`), which is what makes every text draw a leaf group and every scope a collector: without any scope (`paintScopes` empty) the glyphs go straight to the scene and none of the arrays below exist, which is why a first fixture without it did not reproduce Alloy.

| rows | without scope: bytes / frame, allocations | lazy units realised | with scope, before: bytes, allocations, requests >= 32 KiB | with scope, after |
|---|---|---|---|---|
| 20 | 3.94 MB, 45.0k | 6 | 39.25 MB, 168.7k, 28.5 (24.0 MB) | 20.00 MB, 168.6k, 15.5 (7.57 MB) |
| 50 | 4.74 MB, 54.6k | 6 | | |
| 100 | 4.79 MB, 54.9k | 6 | 44.10 MB, 188.5k, 29.6 (27.1 MB) | 22.14 MB, 188.4k, 15.6 (8.28 MB) |
| 200 | 4.80 MB, 55.0k | 6 | | |
| 60 / 240 (the pin) | | | | 22.872 / 22.888 MB: +0.07 % for four times the rows |

Per-frame bytes follow the **visible window** (the glyphs and rects the lazy window realises: 6 rows, 3.8-4.2k glyphs without the large paragraphs, 8.3-9.3k with), not the transcript: 50, 100 and 200 rows read the same to three digits, and the pin compares 60 with 240. A row above or below the window is not realised, captured, moved or replayed. Alloy's "scrolled up, 52 GB" run is a window with more glyphs in it, and the blocks are bigger because a leaf group, a capture array and a record are sized by the window. The 20 to 100 step in the table is the scroller's first frames (extent), 5 MB, not a slope. The redo cascade (`G49-B`, record 416) is present in the fixture at about one frame in eleven (`redos 0.1`, `backoff 0.6` a frame) and was not toggled: every number here is with the backoff as it stands.

## Attribution

Stack sites are the probe's (`G51ChurnProbe.swift`, a `malloc_logger` hook with `backtrace`, not committed), the Alloy lines are the report's.

| Alloy source | cause | status |
|---|---|---|
| `CapturedPrimitive` via `Frame.insertThroughScopes(_:)` Frame.swift:4035 (`leafGroup.required.append`) from `PaintPass.drawGlyphs` | a text draw under any open paint scope collects its glyphs in `leafGroup`, which `beginLeafGroup` made `[]`: a doubling run per draw, and the record keeps the array with its slack (28 live groups of 260 KiB) | **fixed**: `beginLeafGroup(reserving: glyphs.underestimatedCount)`, also the gradient text's ink array |
| `processScopes` under `replayPaint` (RetainedSubtree.swift:775, 6.9 MB), `paintWithMask` (ClipMask.swift:104, 5.5 MB) | the `.composite` case of `processScopes` appends every leaf to `scope.captures`: a doubling run (6 to 7 allocations, three times the final size), and the close then copied the array (`var captures = scope.captures` before inserting the group marks) | **fixed**: the n-th composite/mask scope reserves what the n-th of the last frame collected (`FrameCapacityHints.scopeCaptures`, 64 at most), and the close takes the array |
| `[MUIGlyph]` 196k allocations, 15 KiB average | `Scene.glyphs` of the group scenes (`insertGroup`, `insertMaskedGroup`, `GroupFilter`): a fresh `Scene()` per offscreen group, grown from empty (about 170 glyphs, a doubling run each) | **fixed**: `collectingIntoFreshScene(reserving:)` counts the group's own rects and glyphs |
| `CapturedPrimitive` 424 bytes | the largest kind was inline (a gradient 280, a backdrop 256, a path 192) for every glyph | **fixed**: `path`, `shadow`, `gradient`, `blur`, `backdrop` are `indirect`; 424 to 272 bytes, the kind 280 to 128 |
| `Dictionary<NativeMeasurementKey, LayoutMeasurement>` 70 KiB average, `Dictionary<LayoutMemo.MeasureKey, ...>` | `NativeLayoutRun.cache` and the memo's three generations were made empty and regrown every frame | **fixed**: the run's cache reserves the last call's count (per entry point), `LayoutMemo.endFrame` makes each generation at the count of the one before; both follow the count down |
| `movedPaintRecord` RetainedTranslation.swift:211 (38 blocks, 147 KiB) | `movedOps` moves every translated occurrence's record, exactly sized, once a frame the bottom anchor moves the rows: one array per op per *visible* occurrence | not changed: moving by an offset instead of copying is the redesign `412` left; a 424 to 272 byte primitive makes each copy 36 % smaller |
| `Frame.insertLeaves` Frame.swift:4188 (5.5 MB) | `Array(primitives[i..<j])` for a marked run: each child loses its first group mark, so each is copied once | not changed: one copy a group, exact |
| `Scene.finalize` Scene.swift:672 (1.1 MB), the group scenes' | the sorted copies, reserved exactly | not changed |
| `[BuildJournal.Event]` 47k allocations, 692 MB | `BuildJournal.rebased` makes one exactly sized array per graft record; an ancestor's range holds its descendants' events, so a record made again (a redo, a changed row) copies the subtree's journal once per enclosing occurrence | **not reproduced** (no large events array in the fixture); it is the record-made-again cost of the redo cascade, `G49-B` |
| `RasterScratch.takeCells` via `gradientPixels` (7.8 MB) | a gradient rasterised | not in the fixture; not touched |
| IOAccelerator 670 MB, `Renderer.encode` | encoder buffers | not in the headless harness; not looked at |

## Changes

`Frame.beginLeafGroup(reserving:)`; `Frame.reserveCaptures(of:)`/`noteCaptured(_:ordinal:)` and `FrameCapacityHints.scopeCaptures` (`HP-K`'s struct); `collectingIntoFreshScene(reserving:)` (counted with a `while`: a `for` over an array allocates per element in a debug build, `CV-R`); `indirect` on five `CapturedPrimitive.Kind` cases; `NativeLayoutRun.init(tree:cacheHint:)`, `LayoutTree.computeCacheHint`/`measureCacheHint`; `LayoutMemo.endFrame`. In the test target `profileAllocations` (`AllocationProfile`: allocations, bytes by request size with a realloc at its new size, and the requests of 128 KiB and over; `countAllocatedBytes` adds a realloc's old pointer, which is why it is left as it is).

## Pins and mutations

`G51ChurnTests` (`aStreamedFrameOfAScopedTranscriptStaysUnderItsCeilings`, `aLongerTranscriptCostsTheSameStreamedFrame`, `aCapturedPrimitiveDoesNotCarryItsRarestKindInline`), `LayoutCacheHintTests`, `theSecondFrameReservesWhatTheFirstFramesScopeCollected`. 12 streamed frames of 40 rows, debug, 128 KiB threshold, per frame:

| Build | bytes | allocations | requests >= 128 KiB (bytes) |
|---|---|---|---|
| branch | 20.13 MB | 172.3k | 7.08 (6.85 MB) |
| group scenes without their reserve | 21.21 MB | 172.4k | 9.08 (7.51 MB) |
| leaf group without its reserve | 20.42 MB | 172.4k | 7.58 (7.01 MB) |
| scope captures without the hint | 25.33 MB | 172.3k | 11.0 (12.05 MB) |
| ceilings | 20.65 MB | 176.5k | 7.4 (7.05 MB) |

The memo's generations made empty again do not show in this fixture (20.14 MB); `LayoutCacheHintTests` reads 4 000 440 bytes for a settled 400-leaf frame and 4 788 504 with the generations remade empty (ceiling 4.15 MB). The kind's `indirect` removed fails the stride pin (424 against 280); the hint field removed from `Frame.init` fails `theSecondFrameReservesWhatTheFirstFramesScopeCollected`. The first draft of the group-scene reserve counted with a `for` loop and added 16k allocations a frame in a debug build (two a glyph): found by the A/B table and replaced by a `while`.

## Not measured

A release build, `phys_footprint`, the `Malloc Large (empty)` region count and the frame time: the machine was at load average 40 to 45 throughout and the numbers above are allocation counts and bytes, which do not depend on it. The 28.5 to 15.5 requests a frame (probe threshold 32 KiB) is the proxy for the large blocks malloc keeps; the footprint effect in Alloy is the reader's to measure.

## What is left

The record move (one copy of every visible occurrence's ops per frame the window scrolls), the child copy of `insertLeaves` (2.5 MB a frame in this fixture), `Scene.finalize`'s sorted copies and the capture array itself (2.7 MB, the viewport's glyphs at 272 bytes each), the per-record journal copies of a redo, and the 272-byte primitive's `transform` (112 bytes inline, boxing it would put an allocation on every transformed primitive).
