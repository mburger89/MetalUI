# 418: an abandoned attempt's glyphs are forgotten with it (`GL-K`; PR 1.2 of the exact-redo plan)

Class `M`, no divergence. Branch `fix/exact-redo-atlas`, **stacked on #434** (record 417, `fix/exact-redo-rollback`). Public API: one protocol requirement, `TextSystem.abandonFrame()` with a default (`endFrame()`), implemented by `CoreTextTextSystem` and `PortableTextSystem`; the glyph atlas's bracket is `package`. Not here: the verify-mode digest channel and the census (1.3), the scoped redo (Piece 2).

## What the abandoned attempt left in the atlas

`GlyphAtlas.beginFrame()` advances `currentGeneration`; `packed(for:)` inserts into `placed` and `keysBySlot`, advances the shelf packer, adds to `packedArea` and blits the bitmap. None of it was undone, so a redo ran one generation ahead of a fresh frame with the attempt's glyphs already packed. Record 416 put `aZoomedNodeIsHitWhereItIsDrawn`'s red under a scoped redo down to this.

## The mechanism

- `GlyphAtlas.beginAttempt()` (before the frame's `beginFrame()`, armed with `StateTable.beginAttempt()` under the same condition) snapshots the packer fields, `currentGeneration`, `packedArea`, `droppedGlyphs`, `reclaimRequested`, the extent, `growCount` and the dirty regions; while open, a pack miss logs its key (one key a new glyph, an empty glyph included), and a re-stamp keeps the replaced stamp in `Placement.previous` (eight bytes a glyph; nothing is logged for the visible glyphs a quiet frame re-stamps).
- `rollbackAttempt()` removes the logged keys from `placed` and their slots from `keysBySlot`, zeroes the rectangles, gives the stamps back (a scan of `placed`, once, on a redo), restores the packer and the counters, and restores the dirty regions **only when the extent did not change**. Growth is not undone and is counted (`growthsInAbandonedAttempts`, pinned 0 in the fixtures).
- `acceptAttempt()` after adoption; the log keeps its capacity up to 1024 keys.
- **A paint record the attempt made is cleared at the rollback unless every glyph slot it names is still packed** (`ContentMemoStore.attemptRecorded`, one append at the single site that stores `entry.record`; `RetainedRecord.glyphSlotsAre(packed:)`). Clearing every record the attempt made was the first version and it moved two pins that count the redo's hits of those records (`aMovedOccurrenceCostsOneMissAndTheNextFrameHits`, `theKeyOnlyArmCostsOneMiss`: 6 misses, 2 hits against 4 and 4); a record that names only glyphs that were packed before the attempt is still valid and the redo still hits it. Found by the new redo test, not by a scene comparison: the first version rolled the atlas back and the redo **replayed the attempt's paint record**, so the redo's scene drew two glyphs from rectangles the atlas had forgotten (an empty sprite on a GPU; no scene byte comparison can see it). `xrDanglingGlyphs` reads every scene glyph's atlas rectangle back to a key and is in the redo tests. A record from an earlier frame names glyphs that are still packed and is kept. Graft records are made at the end of an accepted frame and cannot come from an attempt (`pendingGrafts` is emptied on an abandoned one).
- **The plan's open question, answered: yes, `ShapingCache.beginFrame` aged entries twice on a redo.** `ShapingCache.beginFrame()` is `currentGeneration += 1` (`ShapingCache.swift` `beginFrame`), the abandoned frame called `endFrame()` (sweep included, `Frame.swift` abandon branch), and the redo called `beginFrame()` again: two steps for one frame, so an entry last used the frame before (stamp G-1, redo at G+1, cutoff G-1) was swept a frame early once the dictionary was over its threshold; `PortableTextSystem.endFrame` filtered `generation - stamp <= 1` on every call and dropped such an entry unconditionally. A cache residency loss only (shaping is a pure function of an exact key), but it is a difference from a fresh frame. `TextSystem.abandonFrame()` (default `endFrame()`) gives the epoch back with no sweep in both systems; the abandon branch of `Frame.render` calls it.

## Tests (`ExactRedoTests.swift` unless noted) and mutations

- `aRolledBackAttemptLeavesEveryStoreAsItFoundIt` gained the atlas arm (glyph map with slots and stamps, slot map, packer, `currentGeneration`, `packedArea`, counters, extent, dirty regions, a hash of the pixels) and the **zoom arm** (ten `.equatable()` nodes under `scaleEffect`, the shape of `aZoomedNodeIsHitWhereItIsDrawn`, under the opacity trigger); it requires an attempt that packed a glyph, and `growthsInAbandonedAttempts == 0`. The streaming word is now one new Latin Extended-A letter a step, so every step packs a glyph (the earlier fixtures re-ran green with it).
- `aRedoneFrameEqualsAFreshFrameInEveryChannel` (four arms): the slot map and packer of the redoing window equal the plain window's at every step, and no scene glyph names a slot the atlas forgot.
- `aZoomedNodeIsHitWhereItIsDrawnThroughARedo`: the zoom shape, 24 steps, a click at the drawn centre after each, redone at least twice; equal to the plain window, slots equal, no dangling glyph.
- `anAbandonedAttemptsGlyphsArePackedOnce` (atlas unit): A, B and an empty glyph packed in an attempt and re-stamped glyph; rollback equals the digest before; the redo's B takes A's slot and `rasterize` runs once per key; accepted attempts keep everything; a doubling inside a rolled-back attempt stays and is counted.
- `aRedoAdvancesTheTextCachesEpochOnce` (window, a counting `TextSystem`): abandons equal redos, begins equal ends plus abandons. `anAbandonedFrameDoesNotAdvanceTheEpochOrSweep` (`ShapingCacheTests`).
- Steady frame: `aQuietFrameWithAnArmedRollbackLogsNothing` also reads the atlas (0 keys over four armed quiet frames); `aStreamingFrameLogsOneEntryPerWrittenState` reads at most 2 keys a streaming frame.

| mutation | reddened |
|---|---|
| A1 key log off for the empty glyph | `anAbandonedAttemptsGlyphsArePackedOnce` |
| A1b key log off for a packed glyph | unit, `aRolledBack...` (4), `aRedone...` (4), the zoom hit test |
| A2 packer cursor not restored | the same four |
| A3 stamps not restored | unit, `aRolledBack...` |
| A4 pixels not zeroed | unit, `aRolledBack...` |
| A5 `currentGeneration` not restored | unit, `aRolledBack...` |
| A6 attempt records not cleared | `aRedone...` (the dangling-glyph arm) |
| A7 the window skips the atlas rollback | `aRolledBack...` |
| A8 the abandon path calls `endFrame()` | `aRedoAdvancesTheTextCachesEpochOnce` |
| A9 `ShapingCache.abandonFrame` keeps the epoch | `anAbandonedFrameDoesNotAdvanceTheEpochOrSweep` |
| A10 slot map not forgotten | unit, `aRolledBack...` |
| A11 dirty regions not restored | unit, `aRolledBack...` |
| A12 area and dropped counter not restored | unit, `aRolledBack...`, `aRedone...`, the zoom hit test |

## Cost (release probe, 120 streamed words each a new glyph, 3 interleaved runs, PR 1.1 as base)

| | requests | CPU ms a frame, median | allocations a frame, median | footprint start to end, MB |
|---|---|---|---|---|
| base, plain | 12.0 | 0.567, 0.670, 0.546 | 1541, 1539, 1532 | 11.7 to 21.1, 21.5, 21.0 |
| branch, plain | 12.0 | 0.522, 0.444, 0.575 | 1534, 1533, 1532 | 11.8 to 21.1, 21.2, 21.2 |
| base, redo | 33.8 | 0.623, 0.541, 0.707 | 1970, 1961, 1952 | 11.8 to 21.2, 21.1, 21.2 |
| branch, redo | 33.8 | 0.591, 0.563, 0.623 | 1959, 1961, 1946 | 11.7 to 21.2, 21.2, 21.1 |

No difference beyond the run-to-run spread in CPU, allocations or footprint. The log is a handful of keys a streaming frame and none on a quiet one.

## Left

The verify-mode digest channel and the census of state-held classes (1.3), the `testingRedoBackoff = false` greening of the three pins, the scoped redo (Piece 2). A holder of atlas rectangles other than a paint record (a transition ghost or a drag snapshot made inside an attempt) is covered by `AnimationStore`'s checkpoint, not by this record; `xrDanglingGlyphs` is the instrument that would name one.
