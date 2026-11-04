# Record 211: a replayed occurrence re-notes its matched groups (round 4 item R4-3c)

Branch `feat/r4-3c-replayed-leaver`, stacked on `feat/r4-3a-followups` (430bf5d3, PR #206). Decisions: `XF-N` in `docs/superpowers/2026-11-03-default-transition-decisions.md`, closing `XF-M` item 6. Divergences: **none added, retired or narrowed** (209 live, next label 217; row 897 lost its replay residue). Human check `XF7` new. `Tasks.md` R4-3c ticked, R4-3f added.

## 1. What changed

- `MatchedGeometryStore`: `noted` (appended by `noteSequences` and `renote`, cleared in `endFrame`) and `renote(_:base:)` (sets `displayed = target` always; with a base also sets `sequences` and appends to `noted`).
- `RetainedSubtree.swift`: `SubtreeRecorder.matchedFrom`, `RetainedRecord.matched` (window-relative), copied by `moved(to:)`, compared by `differences(from:)` as `"matched groups"`; `replayPaint` re-notes after the unit-range block, with `base: nil` when the emitted count differs.
- No journal event owed (the store is no `StateTable` slot; the occurrence is graft-refused); `everyStateWriteSiteIsClassified` green.

## 2. Done differently from the plan

- **`rollbackBuild` has no `noted` clear** (the prototype had one). MR6 was green as predicted; the smaller spelling is kept. An abandoned attempt's entries sit below the redo recorder's `matchedFrom`.
- **Added arms**: a painted box before the hero (hero's range is not at sequence 0) and an outer occurrence that misses once while the inner replays (`aReplayedLeaverFliesAfterPaintedContentAndAnOuterMiss`). Without them MR3 and MR4 were **green** (all first-pass hero occurrences started at sequence 0, and the outer record was built by a live inner paint).
- Added `renoteNotesRangesOnlyAtABase` (callee unit pin) and `twoRecordsDifferByTheirMatchedGroups` (direct call on two records, the plan's MR8 fallback; MR8 reddened it only).
- The emitted-count break ranges are shifted by one as well as `emitted`, for the reason in section 4 (MR5).

## 3. Existing tests whose expectation changed

`aLeaverInAReplayedOccurrenceHandsNothingOverToday` -> `aLeaverInAReplayedOccurrenceHandsOverAsAFreshFrameDoes`: steady (flights, ghosts) 0 / 1 -> 1 / 2. Oracle (1 / 2) and early (1 / 2) unchanged. No other test changed. The at-rest pins `aSteadyFrameCapturesAndOpensNothing` and `anEquatableOccurrenceWithAnIfStillGrafts` (455 / 0 / 4 / 4 / 4 / 1 / 2) stayed green, unmoved.

## 4. Mutations

Applied to the committed tree, `swift test --no-parallel --filter MatchedGeometryTests`, restored with `git checkout -- Sources`, `git status` clean after each.

| mutation (spelling) | reddened |
|---|---|
| MR1 `renote` without `displayed = target` | the renamed pin, `aReplayedLeaverFliesInThePlainArm`, `...InANestedOccurrence`, `...AfterATranslatedReplay`, `aReplayedOccurrenceAfterAnInterruptedFlightOrALandingEqualsTheOracle`, `aReplayThatEmittedAnotherCountDropsTheMatchedRanges` |
| MR2 `renote` without `sequences = range` | the renamed pin, the plain, nested and translated arms |
| MR3 `renote`'s range without `+ base` | `aReplayedLeaverFliesAfterPaintedContentAndAnOuterMiss` only (green until that arm was added) |
| MR4 `renote` without `noted.append` | `aReplayedLeaverFliesAfterPaintedContentAndAnOuterMiss` only (green until that arm was added) |
| MR5 count check skipped (`base: sequenceBase`) | **green, a finding**: see below |
| MR6 `rollbackBuild` clears `noted` | green as predicted; the clear was removed |
| MR7 `moved(to:)` drops `matched` | green in the default run: `moved(to:)` is verify mode's copy only (not run under verify) |
| MR8 `differences` ignores `matched` | `twoRecordsDifferByTheirMatchedGroups` only |

**MR5 is green and stays green.** A replay that emitted another count drops the unit's ranges (`XF-I`) on the same condition, and a leaver is carved out of its unit's ghost, so ghosts read 1 with or without the matched range; `displayed` is re-noted either way. Pinned at the callee (`renoteNotesRangesOnlyAtABase`), not at the caller. **MR7 was run only in the default build**; the verify-mode run (`METALUI_VERIFY_RETAINED=1`) compares a moved copy against a fresh record, and whether it reddens under MR7 was not measured.

## 5. Counts

Native, after `swift package clean`, unfiltered, `--no-parallel`: **5154 tests in 14 suites passed**; `FR-J no-argument frame: succeeded=true`. Verify runs and probe scripts: section 6.

## 6. Verify runs and probe scripts

`METALUI_VERIFY_RETAINED=1`: 5154 tests in 14 suites passed. `METALUI_VERIFY_LAYOUT_MEMO=1`: 5154 tests in 14 suites passed (both native, unfiltered, `--no-parallel`). `record-05-check.sh`, `closeout-inventory-check.sh` and `closeout-undocumented.sh` printed nothing. Not run: guard count re-take, `Backends/SDL`, Linux, Windows, human group `XF`.
