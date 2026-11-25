# 422: a redo rebuilds the failing occurrences and what is under them, not the window (`RK-AM`, `RK-AN`; Piece 2 of the exact-redo plan)

Class `M`, no divergence, no public API but `FrameWork.retainedRedoEscalations` (test-support). Branch `perf/scoped-redo`, **stacked on #438** (record 419; #438 on #435 on #434). Plan: `docs/superpowers/plans/2026-11-25-exact-redo-and-movable-records.md`, Piece 2. Records 420 and 421 belong to concurrent branches.

## The mechanism

`Window.buildAndAdoptFrame`: when attempt 1 asks for a redo, `noteRedo(entries, scoped:)` quarantines each failing entry **and its identity as a scope** and, scoped, leaves `prepaintSuspendedUntil` alone; the attempt is rolled back (record 417 to 419); attempt 2 is armed and built with `redoScopes` = the failing ids. In attempt 2 `prepaintReplayAllowed` holds, so occurrences graft and replay as in attempt 1 except those at, under or above a scope (`isInRedoScope`) or under a quarantined one (`isInQuarantinedScope`). Quarantine is `quarantinedScopes`, at most 64, with the entry's own doubling. Escalation, the unrestorable channel, an occurrence with no identity and verify mode build window-wide (every replay off, nine builds of backoff); an attempt 2 that asks again counts `retainedRedoEscalations`. Details and why it is exact: `RK-AM`, `RK-AN`.

## The fixture (`ChromeTranscriptFixture.swift`, permanent)

`ScrollView(.defaultScrollAnchor(.bottom)) > LazyVStack > ForEach` of 51 `.equatable()` rows (50 settled, one streaming a word a step), each `VStack { paragraph.equatable(); paragraph.equatable(); Button }.background(tint).cornerRadius(8)` (the rounded **clip**, whose mask a moved record cannot re-derive at the viewport edge: `maskStraddlesEntryClip`; a rounded `background(_, in:)` does not reproduce it), 420 x 600 at scale 2. 3 redos in 40 steps.

Per step, 40 streamed words, release-independent counts (`FrameWork`), base `fix/exact-redo-verify` against this branch:

| | requests, mean | prepaints, mean | redos | backoff builds | grafts | redo frame |
|---|---|---|---|---|---|---|
| base | 39.1 | 55.0 | 3 | 22 | 151 | 70 requests, 0 grafts |
| branch | 24.85 | 34.35 | 3 | 0 | 235 | 43 requests, 4 grafts |

(Quiet steps are 11 requests on both; the redo's rows and their paragraphs stay on the rebuild path while quarantined: 34 requests a step for 8 builds on the branch, 61 on base.) The transcript here is lighter than Alloy's (about 9 visible rows of simple text); the expected effect on Alloy's measured 423 requests a delta (record 416) is the quarantine's width: a failing row and its subtree instead of the whole window for nine builds. Alloy re-runs `measureStreamingRows`; the number is not claimed from this fixture.

## Release probe (`G49Probe`, never committed): the same chrome rows, 120 streamed words, 3 interleaved runs

| | requests a frame | redos | CPU ms a frame (median) | allocations a frame (median, mean) | `phys_footprint` start to end, MB |
|---|---|---|---|---|---|
| base | 37.5 | 7 | 0.649, 0.648, 0.659 | 2220, 2218, 2232 (mean 2810, 2806, 2816) | 12.9 to 18.8, 19.0, 18.8 |
| branch | 24.9 | 7 | 0.571, 0.558, 0.555 | 2216, 2228, 2218 (mean 2360, 2358, 2361) | 12.8 to 18.5, 18.6, 18.7 |

-34 % requests, -14 % frame CPU, -16 % mean allocations (the redo frames are the heavy ones), footprint -0.3 MB; the median frame is the same.

## Tests (`ScopedRedoTests.swift`) and mutations

`aScopedRedoRebuildsOnlyTheFailingRowAndItsDescendants`, `aRedoDoesNotCascadeIntoTheRowsDescendants`, `aScopedRedoEqualsAFreshFrameInEveryChannel` (scene, hitboxes, bounds, live state, atlas slots, no dangling glyph), `theWindowBacksOffOnlyOnEscalation` (three arms: scoped, an unrestorable channel, an attempt 2 that asks again), `aQuietChromeTranscriptFrameCostsOnlyTheScroller` (4; the G49 `aQuietTranscriptFrameCostsOnlyTheScroller` is unchanged at 4). `RPPair.redraw` records an issue for any escalation outside the fault arm: **0 across the suite**.

| mutation | reddened |
|---|---|
| S1 descendants not quarantined (`isInQuarantinedScope` false) | `aRedoDoesNotCascadeIntoTheRowsDescendants` (redos repeat) |
| S2 the scope check off (`isInRedoScope` false) | **survives**: the scope is quarantined before attempt 2, so the same refusal comes from `isInQuarantinedScope`; `isInRedoScope` adds the ancestors (a defence: an ancestor built in attempt 1 decides the same in attempt 2) and nothing in the suite has a fixture where it decides |
| S3 the rollback off | the redo differentials of 417 to 419 and the three scoped tests |
| S4 a scoped redo suspending replay | `aScopedRedoRebuildsOnlyTheFailingRowAndItsDescendants`, the scoped arm of `theWindowBacksOffOnlyOnEscalation` |
| S5 the scope never set (attempt 2 window-wide in effect) | `aScopedRedoRebuildsOnlyTheFailingRowAndItsDescendants`, the escalation arm |

## The pins that moved (full run before they were edited: 7417 tests, 8 failing plus the `Frame` classification row)

The eight backoff-behaviour pins of record 419's list and its two literals, now with the reason:

- `aChangedPaintOnlyAmbientRedoesTheFrameOnce`, `aRedoSuspendsPrepaintReplayForEveryOccurrence`, `aRedoAfterAGraftMismatchRestoresEverything` and the two `RedoCounterTests` (`aRedoFrameKeepsTheRedosOtherCounters`, `theFrameAfterARedoReportsNoCarriedEvaluation`) pinned **the window-wide path**: they now take it with `testingRedoFault = .unrestorableChannel` (the first three also gained a scoped arm that pins the new behaviour: the neighbour replays or grafts in the redo and in the eight builds after it, no build is suspended; "moved by a sibling" fails both occurrences and so grafts nothing in either path).
- `BackgroundProminenceTests` `P7b` and `P14`: steady requests 41 to 40 and prepaints 42 to 41, 32 to 31 and 33 to 32. The measured frame is the first after a redo; the scoped redo quarantines only the occurrence that failed, so the one that did not replays at once.
- `everyFrameChannelIsClassified` gained `unrestorableChannels`.

## Found by running the whole suite under `METALUI_VERIFY_RETAINED=1` (record 419 had run filtered subsets only)

- **The rollback channel trapped on the replayed frame's journals** (`aRetainedPrepaintReplayKeepsTheLiveValue`, a terminal test): verify mode's `takeUnsweptJournals` emptied the read and mark journals, which also dropped what an input handler had noted between frames, so the rollback channel saw them gone. It now only reads them; the rollback truncates them to what they held when the attempt began.
- **The census missed classes** because no demo holds them: `OutlineIndex` (an `OutlineGroup`'s per-frame cache: `cache`; the census gained an `OutlineGroup` window), `GlobalElementID` (`immutable`), `RecordingEnd` (`immutable`: written by a key event, never by a build).
- **`TableEditSession` is a class a build writes** (`TableBody`: the row position and last frame, the editor's focus, and the one-shot `needsSeed` and `needsFocus` flags consumed in prepaint): a redo's second attempt found the focus request already consumed and never made it. It is now `AttemptRestorable` and `TableBody` registers it in layout and prepaint (`aRolledBackTableEditSessionRequestsItsFocusAgain`). A real exactness gap of the redo since `RK-D`, only reachable with a cell-mode edit open in a frame that redoes.
- The whole suite under `METALUI_VERIFY_RETAINED=1` now ends: no trap, and the failing tests are the count pins of record 419's baseline (same names, plus `colourOnlyHighlightsCostWhatMasterCosts`, `aWriteReadOnlyBelowAMemoBoundaryCosts...`), two allocation pins (`recordingAndNotRecordingAllocateTheSame`, `anEnabledIdleTextAllocatesNothingPerRow`: a verify-mode frame also digests the table, which allocates; I could not baseline them on master here) and the census test, which is skipped under verify (the demo windows never idle there).

## Not here

The movable-record work (record 416's Piece 3: `maskStraddlesEntryClip`, `inexactTranslation`) removes the redos' cause; this removes their cost. `Frame.noteUnrestorable` has no caller in the product: the census of record 419 found no state a rollback cannot restore.

Root 7418 tests in 80 suites green (`--build-system native`, `--no-parallel`); `swiftlint lint --strict --baseline` 0; the closeout checks print nothing.
