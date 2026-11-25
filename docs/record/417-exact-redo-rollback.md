# 417: a redo starts from the table the abandoned attempt found (`RK-AI`, `RK-AJ`; PR 1.1 of the exact-redo plan)

Class `M`, no public API, no divergence. Branch `fix/exact-redo-rollback`, base master `c6a4d4ed`. Plan: `docs/superpowers/plans/2026-11-25-exact-redo-and-movable-records.md` (Piece 1). This is PR 1.1: the `StateTable` undo log and the `RowExtentIndex` journal. The glyph atlas bracket (1.2), the verify-mode digest channel and the reference census (1.3), the scoped redo (Piece 2) and any change to the backoff are **not** here: the window-wide nine-build backoff is as it was.

## The 11 pt difference of record 416: confirmed, and its cause

Fixture (`ExactRedoTests.swift`): Alloy's transcript, a bottom-anchored `LazyVStack` of 51 `.equatable()` rows with a tinted rounded chrome (one streaming), 420 x 600 at scale 2, one word a frame; above it a replayed `RPCard` under an `.opacity` that changes every frame, which abandons the frame after paint (`RK-C`) and redoes it. Master, first redo frame (step 26): the element bounds of a retention-off window and of the redone window differ for **every** lazy row, the streaming one included, by **11 points** (4348 against 4337; 3768 against 3757; the stack's 10 and a point of the anchor's remainder), while scene, hitboxes, tallies and Tab order are equal. The frames after it are equal.

The cause is the inferred one, narrowed: the **`RowExtentIndex`** in the lazy container's `LazyOrigin` entry. Attempt 1's prepaint records the realised rows' measured extents into the class in place; the redo's `LazyLinePlanner.plan` plans the window from them (the estimate is the running mean of the measured rows, and a measured row's extent replaces the estimate), so the redo places the rows against this frame's measurements. It is **not** the scroller's anchor memory: with only the table's undo log off (mutation M1) the bounds test stays green in this fixture, and with only the index journal off (M2, M6, M7) it is red. The undo log is still owed (the entries the prepaint writes were left as the attempt wrote them; the digest tests are red without it).

## The mechanism as built

- `StateTable.beginAttempt()` (armed in `Window.buildAndAdoptFrame` under the checkpoint's own condition, `prepaintReplayAllowed && ledgerEntries > 0`, and always in verify mode) logs, on the **first** touch of an id, the entry as it stood: `withState`, the compared form's write, `write`, `mark(seeding:)` (creation), the mid-frame reset of `noteProduced` (deletion), and a tombstone's liveness flip in `mark`, `touchLive`, `markLive` (so `isLive` is exact too). `attemptUndo: [GlobalElementID: Entry?]`, `nil` for an id the attempt created.
- `rollbackAttempt()` restores each entry (value, generation, `isLive`, **version**), deletes the created ones, restores `marked` (a snapshot at the begin, empty at a frame's start so the copy is free), truncates `readJournal` and `markJournal`, and rolls back every registered `AttemptRestorable`. `versionCounter` stays monotonic. The window calls it beside `animationStore.rollbackBuild`, and in verify mode **instead of** `discardEntries(createdSince:)` (amends `RW-U`; removed). `$ax`: the old exemption kept a `$ax` the first build created; the rollback deletes it and the fresh build creates it again before anything is published (the suite, with verify mode on, is the check; see Tests).
- `acceptAttempt()` runs at the top of `sweep()` (an abandoned frame returns before it) and again after adoption. The log keeps its capacity up to 1024 entries and is dropped above that.
- `AttemptRestorable` (`beginAttempt`, `rollbackAttempt`, `endAttempt`, `attemptContents`), registered by `StateTable.restorable(_:)` before the first mutation: `LazyLinePlanner.plan` and `.prepaint` (so `LazyStack` and `LazyGrid`), `List.variableWindow` and `prepaintVariableRows`. `RowExtentIndex` logs the old height and id of each row `record` changes, the old value of each **Fenwick node** it touches (an inverse delta is not bit-exact), and the arrays as a snapshot on the first `rebuild` or `forgetMeasurements` (records logged before the snapshot are undone over it). Equal records journal nothing.
- Verify mode's `writeMissed` check compared the fresh run's compared writes with the entries the first build created; with the table rolled back the fresh run writes again what the replayed build wrote, so the check now excludes the ids the replayed build's own compared writes cover (`comparedWritesBefore`). Found by running the suite under `METALUI_VERIFY_RETAINED=1`: the first version of this change trapped `writeMissed` in `aKeystrokeAndItsOutputCost...`.

## Tests (`ExactRedoTests.swift`) and mutations

Each mutation was run against the filtered set (the five fixture tests, the two unit tests); the entries are the tests it reddens.

| mutation | reddened |
|---|---|
| M1 undo log off (`logUndo` never logs) | `aRolledBackAttemptLeavesEveryStoreAsItFoundIt` (3 arms), `aRolledBackStateTableIsTheTableItWas`, `aStreamingFrameLogsOneEntryPerWrittenState`; **not** the bounds test |
| M2 index journal off | `theRedoFrameRegistersTheElementBoundsAFreshFrameDoes`, `aRedoneFrameEqualsAFreshFrameInEveryChannel` (transcript, grid), `aRolledBack...` (transcript, grid), `aRolledBackIndexIsTheIndexItWas` |
| M3 `marked` not restored | `aRolledBackAttempt...` (3), `aRolledBackStateTable...` |
| M4 journals not truncated | `aRolledBackAttempt...` (3), `aRolledBackStateTable...` |
| M5 index snapshot off (rebuild and width change not undone) | `aRolledBackIndexIsTheIndexItWas` |
| M6 Fenwick node journal off | bounds test, `aRedone...` (3 arms), `aRolledBackAttempt...` (2), `aRolledBackIndex...` |
| M7 row journal off | bounds test, `aRedone...` (3), `aRolledBackAttempt...` (2), `aRolledBackIndex...` |
| M8 the window does not roll back | bounds test, `aRedone...`, `aRolledBackAttempt...` |
| M9a/b/c/d a liveness flip not logged (`touchLive`, `mark`, `mark(seeding:)`, `markLive`) | `aRolledBackStateTableIsTheTableItWas`, one each |
| M10 a mid-frame reset's deletion not logged | `aRolledBackStateTable...` |
| M11 restorables not registered | bounds test, `aRedone...`, `aRolledBackAttempt...` |
| M12 an attempt's created entry not deleted | `aRolledBackStateTable...` |

- `theRedoFrameRegistersTheElementBoundsAFreshFrameDoes`: **red on master** (11 points, all 51 rows), green here.
- `aRolledBackAttemptLeavesEveryStoreAsItFoundIt` (transcript, variable-row `List`, lazy grid; the zoom and mirrored-row arms of the plan are not in this PR): the state table's digest (every entry's value description, liveness, generation, version, `marked`, journal lengths, and every `RowExtentIndex`'s contents bit for bit) before the attempt equals the one after the rollback at every redo, and differs from the one the attempt left (an attempt that wrote nothing proves nothing).
- `aRedoneFrameEqualsAFreshFrameInEveryChannel` (three arms): scene, hitboxes, tallies, Tab order, registrations, element bounds and the live state entries of the redoing window equal the retention-off window's, at the redo and three frames after it. Not in this PR: the atlas slots, the timeline cursors and the delivered-events log (1.2 and 1.3).
- `aRolledBackIndexIsTheIndexItWas`, `aRolledBackStateTableIsTheTableItWas`: the units (records, an id change, a width, a rebuild, records before a rebuild, records around a width change; a created entry, a rewrite with another type, the four liveness flips, a mid-frame reset's deletion, accept, no-op without an attempt, the 1024 bound).
- Steady frame: `aQuietFrameWithAnArmedRollbackLogsNothing` (4 quiet frames: all armed, 0 entries logged, at most one registered store, 7 requests, the same count on master: the card's 3 and the scroller's 4) and `aStreamingFrameLogsOneEntryPerWrittenState` (the log is the scroller's one entry, 0 in the frames the backoff leaves unarmed, never one per row). `everyStateTableAndAnimationStoreChannelIsClassified` gained the seven attempt rows. `Window.testingRollbackDigests` and `testingLastAttempt` are the hooks.

The plan's `Window.testingRedoBackoff = false` greening of `aMirroredScrollersGrowing...`, `aZoomedNodeIsHitWhereItIsDrawn` and `BackgroundProminenceTests` belongs to 1.3 (it needs the atlas bracket).

## Cost (release, throw-away `G49Probe`, never committed)

The transcript above in a `TestWindow`, 120 streamed words, three interleaved runs of each side on a loaded machine, base `c6a4d4ed` against this branch. "redo" adds the changing opacity ancestor (4 redos in 120 frames).

| | requests a frame | CPU ms a frame, median | allocations a frame, median | `phys_footprint` start to end, MB |
|---|---|---|---|---|
| base, plain | 12.0 | 0.655, 0.691, 0.666 | 3191, 3193, 3205 | 11.8 to 41.3, 41.3, 41.2 |
| branch, plain | 12.0 | 0.649, 0.708, 0.634 | 3208, 3207, 3212 | 11.8 to 41.4, 41.3, 41.2 |
| base, redo | 31.2 | 0.699, 0.723, 0.702 | 3598, 3596, 3596 | 11.8 to 41.4, 41.2, 41.4 |
| branch, redo | 31.2 | 0.708, 0.716, 0.710 | 3599, 3601, 3603 | 11.7 to 41.6, 41.6, 41.6 |

+15 allocations a frame (+0.5 %) on the plain run, +4 (+0.1 %) with redos; frame CPU is within the run-to-run spread; the footprint is equal on the plain run and 0.2 MB higher at the end of the redo run on all three pairs (the log's and the journal's retained capacity at one frame's worth, and the redo frames' transient snapshot; nothing grows with the run: the 30 MB rise from start to end is the same on both sides, the growing text's shaping and glyph caches). The log is bounded (1024 entries kept, dropped above) and one frame long; the index journal is freed at the end of the attempt.

## Left

The atlas bracket (`GL-K`), the digest channel in verify mode, the census of classes held in state, the zoom and mirrored-row arms of the rollback test, and the scoped redo, in that order (plan Piece 1.2, 1.3, Piece 2). Alloy's number (~423 requests a delta) is unchanged by this PR: it is a correctness change.
