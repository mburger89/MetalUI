# Record 244: verify mode compares a replayed build with its own journals (`RW-U`)

Branch `fix/verify-unrecorded-read` (master `6fb5ee3e`). Ruling `RW-U` in `docs/superpowers/2026-10-19-retained-withstate-decisions.md` (next `RW-V`). No public API, no divergence.

## 1. What was reported

MetalCreator (`ca9229b`, branch library-groups): `PanelContentSkipWindowTests/panningEvaluatesOnlyTheSurface` trapped `METALUI_VERIFY_RETAINED: unrecordedRead …` with the path cut by `suffix(80)`. The sibling `NodeLibraryView` is an `.equatable()` panel holding `ScrollView { List(rows, rowHeight:) { ZStack { row } } }` at VStack index 4.

## 2. Cause

Not a replay missing a read. `Window.buildAndAdoptFrame` took `replayedReads` from `StateTable.lastReadJournal`/`lastMarkJournal`, which a **completed** frame's sweep fills. A verify frame is abandoned in `Frame.render` before `sweep()`, so those were the previous frame's. An entry first met in the replayed frame (the panel shown in that frame, so the `ScrollState` read by `ScrollView.requestLayout`, `ScrollChrome.resolvedOffsets`, `resolvedOffset`, `paintIndicator`) was reported unrecorded. Steady frames passed because consecutive frames read the same set.

## 3. Fix

1. `StateTable.takeUnsweptJournals()` returns and empties the open read and mark journals; `replayedReads` uses it.
2. That exposed `a replayed prepaint differs from a fresh one: scene rects count 68 vs 22` on the same frames: the first build's `List` window was unbounded, the second found the viewport the first wrote. A first attempt skipped the scene comparison when the first build created entries (committed, then replaced: it blinds verify on first-sighting frames). Kept: `StateTable.discardEntries(createdSince:)` deletes the created entries (not `$ax`) before the fresh build, so both start from the same table; `comparedWriteIDs` (verify only) lets the `writeMissed` check ignore a compared write to an entry the rollback recreated. The rollback leaves the memo store and the build-wide tables alone, as the existing verify second build already did; the suite under verify mode did not object.
3. The `unrecordedRead` trap prints the full path.

## 4. Test and mutations

`Tests/MetalUITestingTests/RetainedUnrecordedReadTests.swift`, `aPanelFirstShownBesideAReplayedSiblingVerifies` (arms `late`, `early`, `hover`, `scrolled`, each in a verify-mode child). Mutations, each alone after the commit, restored with `git checkout`:

| Mutation | Reddened |
| --- | --- |
| `replayedReads` back to `Set(lastReadJournal).union(lastMarkJournal)` | `late`, `hover`, `scrolled` (`early` green) |
| rollback removed (`recreated` an empty set, no `discardEntries`) | `late`, `hover`, `scrolled` (`early` green) |

The `StateTable` channel guard `everyStateTableAndAnimationStoreChannelIsClassified` objected to the new property until `comparedWriteIDs` got a row (`.frameLocal`).

## 5. Counts

Native, unfiltered, `--no-parallel`, after `swift package clean`: `Test run with 5694 tests in 26 suites passed after 356.814 seconds` (5669 on the previous master; this branch adds four cases and master moved since), `FR-J no-argument frame: succeeded=true`. The same under `METALUI_VERIFY_RETAINED=1`: `Test run with 5694 tests in 26 suites passed after 353.335 seconds`, no trap anywhere.
