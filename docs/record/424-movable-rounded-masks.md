# 424: a paint record whose rounded mask is cut by the viewport replays translated, exactly (`FS-V`; Piece 3(a) of the exact-redo plan)

Class `M`, no divergence, no public API. Branch `perf/movable-rounded-masks` on master `ef42c1b9`. Plan: `docs/superpowers/plans/2026-11-25-exact-redo-and-movable-records.md`, Piece 3(a). Ruling `FS-V` (`docs/superpowers/2026-10-20-finer-scopes-decisions.md`); the rule line is in `docs/rules/retained.md`.

## The mechanism

Record 416 attributed Alloy's 423 element requests per streamed delta to two refusals of a grafted row's paint record: `maskStraddlesEntryClip` (a rounded mask cut by the viewport edge) and `inexactTranslation`. The first is what this removes. The old move shifted a leaf's mask by the delta only when it lay strictly inside the entry clip before and after; the cut of a moved mask is not the moved cut (a row flush with the viewport and cut by its edge has its two cut corners square and the other two round: `intersectReportingCrossing`, `CM-J`), so a row at the edge was refused, the prepaint missed (`recordCannotMove`), and the frame was redone.

- **Record.** While a recorder is open every `pushClip`/`pushRootClip` deeper than its entry appends an `InnerClip` (`RetainLog.notePush`, `notePop`): `pushClip`'s arguments (layout bounds before `activeOffset` is added, the offset, the radii), the parent push, the clip depth, the range of the record's scene ops it covered (each recorder counts the ops at its entry height, `opCount`) and flags (the intersection's `crosses`, `atFlatteningEntry`, root, inexact). The record keeps them relative to its first top node (`RetainedRecord.innerClips`, `nil` when the occurrence pushed none), so a record made over at a new position needs no rewrite. A replayed record inside another recording notes its clips between its ops at the origin it stands at (`Frame.replayOps`).
- **Move.** `Frame.pushedClip` is the one copy of `pushClip`'s arithmetic (translate by `activeOffset`, `intersectReportingCrossing`, compose the offset); `movedPaintRecord` folds the clips from the key's entry clip, radii and offset at the old position and at the new one, and a leaf deeper than the entry takes the mask and radii of the clip it was read under (a group mask primitive: the clip on the leaf's chain at its `maskDepth`). The old fold must reproduce the recorded mask and radii bit for bit (`maskNotFolded`, `maskUnmapped`), so a clip the record did not note refuses instead of moving wrongly.
- **Refusals.** `maskStraddlesEntryClip` is retired. `maskCrossingChanged`: a clip that holds leaves now crosses (the square-box fallback) where it did not, or the reverse: a row with under 16 pt left in view, or a cut within 8 pt of its far edge. `maskCrossed`: a clip crosses in both. `rootClip` (`Deferred`), `entryClipChanged`, `inexactTranslation` (a bound or origin not a multiple of 1/16).
- **Exactness.** The fold calls `pushClip`'s own function, so the expressions are not parallel copies. Verify mode compares the moved record's `innerClips` with the fresh run's and found nothing in the retained, translation, prepaint, scoped redo and fixture suites.

## Cost

- 60 bytes per clip pushed inside a record (`MemoryLayout<InnerClip>.stride`, pinned); the plan estimated about 40. A transcript row (`.background(tint).cornerRadius(8)`) pushes one. An occurrence that pushes none stores `nil` and its recorder never allocates the arrays. Bounded by the occurrence's own pushes; nothing is cached across records.
- A move folds each clip twice (old, new): two arrays of the clip count, no allocation for a record without clips.
- **Found by the churn pins:** the first draft's per-op `for ... in recorders` inside `noteBoundary` allocated on every op of a nested replay (+6 000 allocations in `aRedrawOfRetainedCellsReplaysTheFinalStreamWithoutCopies`, 57 789 to 63 844); indexed loops (noted in the code) bring it to 57 813, +24 over master.

## Numbers

`ChromeTranscriptFixture` (the record 416/423 transcript, 40 streamed words, scale 2; element requests per streamed word, release-independent):

| | mean requests | redos in 40 | refusals |
|---|---|---|---|
| master (record 423) | 24.85 | 3 | `maskStraddlesEntryClip` and `innerScope` each step a row is cut |
| this branch | 15.95 | 1 | `maskCrossingChanged` once (step 29), `innerScope` once (step 36) |

The refusal that remains is the corner-zone crossing: a row recorded while the viewport edge is inside its corner zone is made inside a mask scope (`paintClipped`'s `CM-B` crossing group), so its record is `innerScope`, and a row that moves into the zone refuses `maskCrossingChanged`. Both come from the same mechanism (an inner clip pushing a mask scope) and are about 16 pt of scroll per row edge; not widened here. `inexactTranslation` is never refused by this fixture.

`G51ChurnTests` (debug, 12 streamed frames, 40 rows; master -> branch): bytes 20.52 -> 20.20 MB, allocations 172 977 -> 159 760, large requests 7.58 -> 8.0 and large bytes 7.19 -> 7.52 MB. The large requests rise because the rows the edge cuts now move (`Frame.movedOps` copies a 239 392-byte leaf group) where they used to refuse and rebuild; the redo frame translates them in attempt 1 before the abandon (21 against 16). Ceilings: allocations 176 500 -> 163 800 (lowered); large requests 7.9 -> 8.2, large bytes 7.25 -> 7.7 MB, the redo frame's 16 -> 22 (raised, with the reason in the test). A move in place of the copy is the lever for the large requests. `g51LargeCeiling` is not removable: it was never only the redo's.

## Tests (`MovableRoundedMasksTests.swift`) and mutations

`aRoundedRowAtTheViewportEdgeReplaysTranslated` (two arms: plain rows, and rows whose outer occurrence is re-made from a replay of a nested rounded one), `aRowWhoseCornerZoneCrossesTheEdgeRefusesByName`, `aRecordPaysOnlyForTheClipsItsOccurrencePushed`, `theStreamingTranscriptRefusesOnlyAtACornerZone`. Mutations, each reddens:

| mutation | reddened |
|---|---|
| radii not re-folded (the old radii kept on the folded mask) | `aRoundedRowAtTheViewportEdgeReplaysTranslated` (both arms: the differential and the refusal count), `aRowWhoseCornerZoneCrossesTheEdgeRefusesByName` |
| the old move in place of the fold (master's `RetainedTranslation.swift`) | `aRoundedRowAtTheViewportEdgeReplaysTranslated`, `aRowWhoseCornerZoneCrossesTheEdgeRefusesByName` |
| a replay does not note its clips into the open recorders | the nested arm (`maskUnmapped`), only after the arm retinted the outer so that its record is made from a replay (the first version of the arm survived) |
| the crossing check off | `aRowWhoseCornerZoneCrossesTheEdgeRefusesByName` and the transcript test (the differential) |

## Pins that moved

`everyKeyComponentSeparates` scroll arm now reads a translated hit (the probe card is cut by the viewport; the differential stays the separating pin), `everyUntranslatableKindRefusesByName` loses its `maskStraddle` arm (covered here), `aTranslatedLayoutReplayEqualsAFreshFrameAtEveryScale`'s allowed names, the G51 ceilings above, comments naming `maskStraddlesEntryClip`.

Counts and the full run are in `CLAUDE.md`.
