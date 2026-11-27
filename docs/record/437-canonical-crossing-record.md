# 437: a crossing mask scope is seen through, and a record holds what a paint with no crossing makes (`FS-Z`; class M, no divergence)

Branch `perf/canonical-crossing-record`, base master `eb25ea24`. No public API, no divergence (242 live, next label 250). Amends `FS-D` (a seen scope is not an inner scope), `FS-V` (a painted clip at paint height 0 may change whether it
crosses) and `FS-Y` (the two redos it left are gone); replaces the item carried out of record 434.

**Why.** Alloy's streaming transcript had six redos left, all of one kind: a grafted `.equatable()` row whose own rounded clip (`BlockChrome`'s radius 8, a bubble's 10) is cut by the scroll viewport's straight edge opens a `CM-B` crossing scope
(`ClipMask.paintClipped`), the leaves that reach the scope are collected and leave it as one masked group, and a record made so could not move: `innerScope` (the scope is one the recorder passed), `maskCrossingChanged` and `maskCrossed` (the fold
refused any change of a clip's crossing). Alloy moves the viewport clear of the island's arcs, so no scope is open around the row: the regime this ruling makes movable. Record 434's first attempt kept the crossing's own emitted count, unit ranges and
glyph batching and tried to repair them when the row moved (range anchors, a verify-mode prediction, skips in `differences`); this one records the row **as a paint with no crossing there records it**, so nothing needs repairing.

**What.** `docs/superpowers/2026-10-20-finer-scopes-decisions.md` `FS-Z`:
- `ClipMask.swift`: `opensCrossingScope` and `crossingMask` are the one copy of `paintClipped`'s test and mask rect; `openMaskScope`/`closeMaskScope` are `paintWithMask` split in two. `Frame.opensSeenThrough` decides.
- `RetainLog`: `noteBoundary(closing:)` and `noteSeen` note the leaves that enter a seen-through scope as the recorders' own ops (one per primitive), the merged leaf that leaves it in the final stream only; `virtualSequence`, `virtualRanges` and
  `noteVirtualRange` keep `emitted` and the unit ranges as the sequence would run with no scope; `noteSeenClose` taints `crossingUncounted` and `crossingMatchedGroup`.
- `InnerClip`: `paintedFlag`, `scopeFlag`, `uncountedFlag`, `rangesBefore: UInt8`, `insideCount: UInt16` in the struct's padding (stride 60).
- `RetainedTranslation.swift`: `FoldedClip.crosses`/`opensScope`, `foldedClips(scopesAllowed:)`, `scopeChangeRefusal` (`maskNested`, `maskNotCanonical`, `maskMatchedGroups`, `maskNotFolded`), the flags rewritten in place by `applyPaintTranslation` and
  in a copy by `copiedPaintTranslation`.
- `RetainedSubtree.swift`: `replayOps` opens the scope again at a clip that holds the scope bit (`parentState`, `crossingMask`), `insertFinalStream` replays a cached final stream and measures its scopes, `trueRanges` converts the record's ranges to the
  true sequence, `ContentMemoStore.finalTap` captures the final stream of the replay that follows a move.
- Verify mode: `RetainedVerifySnapshot.groups`, a recursive digest of the scene's groups, masks and filters (the arrays it had are the top level only, and under a clip that crosses the whole transcript is one group quad).

**Measured** (master `eb25ea24` and this branch, same fixtures, retention on, 40 streamed steps; allocations counted around the retaining window's draw):

| | master `9aec1177` | branch |
|---|---|---|
| chrome transcript `ctPair`, scale 2: redos / element requests / allocations | 2 / 547 / 750,250 | 0 / 442 / 705,505 |
| island fixture (`MaskEdgeFixture.swift`), scale 1: redos / requests / allocations | 7 / 1389 / 554,258 | 3 / 1335 / 530,630 |
| island fixture, scale 2 | 7 / 1389 / 555,359 | 3 / 1335 / 531,226 |
| island with a path icon, scale 2: redos / requests / allocations | 5 / 1654 / 621,808 | 5 / 1654 / 622,4xx (+0.1%) |
| island with a gradient icon, scale 2 | 5 / 1654 / 594,074 | 5 / 1654 / 594,6xx (+0.1%) |
| idle island frame: allocations / requests | 2438 to 2441 / 10 | 2440 to 2443 / 10 |
| idle frame with a crossing row holding a path / gradient / faded content: allocations / requests | 5271 / 16, 4263 / 16, 4034 / 14 | 5271 / 16, 4263 / 16, 3842 / 11 |
| a translated non-crossing step: allocations | 3975 | 3975 |
| `theMaskCountersAddNothingToAnIdleFrame`: bytes (allocations 324) | 25,922 | 25,690 (`Frame` holds its verify snapshot boxed) |
| `class_getInstanceSize(RetainedRecord.self)`; `InnerClip`, `CapturedPrimitive`, `UnitRange` strides | 248; 60, 272, 24 | 248; 60, 272, 24 |

The three island redos that remain (steps 1, 17, 33) are the same steps on master: grafted rows whose prepaint key differs in `rects`, `interior`, `shapeInterior` and `ambient.offset` as the lazy window grows, not a mask (no refusal names one).

**Tests.** `MaskEdgeFixture.swift` (the island, a fixed scroller of seven rows, `meDeepSnapshot`) and `MaskEdgeTests.swift`: `aStraightEdgeCutMasksOnlyInTheArcBand`, `aRoundedRowCrossingAStraightEdgeTranslates`, `aFreshCrossingRecordIsTheRecordANonCrossingPaintMakes`,
`aCrossingRecordsGlyphsAreOneOpAGlyph`, `aUnitRangeInsideACrossingRowIsWhatAFreshFrameNotes`, `aCrossingUnderAnOuterScopeStillRefusesByName`, `eachCrossingThatCannotBeCanonicalRefusesByName`, `anIslandTranscriptStreamsWithoutAMaskRedo`,
`aRecordThatNeverCrossesPaysNothing`, `anIdleFrameOfTheIslandTranscriptIsUnchanged`. Inverted: `aRowWhoseCornerZoneCrossesTheEdgeRefusesByName` is `aRowWhoseCornerZoneCrossesTheEdgeReplaysThroughALiveMask`,
`theStreamingTranscriptRefusesOnlyAtACornerZone` is `theStreamingTranscriptRefusesNothing`. The `ScopedRedoTests` and `RedoAttributionTests` that read a redo of the chrome transcript read `ctOuterScopePair` (the same rows under a faded root, so the crossing scope is an inner
scope as on master); their ceilings are untouched. The shaped fixture (`ctShapedPair`, promoted from `RedoAttributionTests`) refuses every grafted row every step, so it cannot carry the scoped-redo pins (`requests <= 50`, `mean < 30`): it keeps the one test it carried.

**Review follow-up (same branch).** Two blocking findings and three smaller ones were fixed, each with a test red on `19ad4a0a` first. (1) `aRecordThatNeverCrossesReNotesAllItsUnitRanges`: `replayPaint` dropped every unit range of a record holding an `uncountedFlag` clip (a painted clip after more than 255 ranges), crossing or not; the gate now reads only the clips of scopes the replay crossed, a clip that holds the scope bit and saturated falls back, and the verify snapshot compares the live unit ranges (`unitRanges`). (2) `aCrossingRowWithUncountableContentStillReplaysUnmoved`: an inexact scope used to taint every open height-0 recorder, so a row with a path icon and its `.equatable()` ancestors repainted every frame; they now fall back to master's record (the merged leaf as the scene, true count and ranges, `innerScopes`, no clips): unmovable across a crossing, replayed unmoved. `aStreamedTranscriptWithUncountableIconsIsNoWorseThanMaster`: path and gradient icons, scale 2, 40 steps: 5 redos and 1654 requests as on master, idle frames hit; allocations are +0.1% over master (622,4xx against 621,808 and 594,6xx against 594,074), not found to the allocation. (3) `aRecordThatStoppedCrossingReplaysItsSharedFinalStream`: a move that uncrosses shares the scene as the final stream again. (4) `aRecorderOpenedAfterACrossingClosedIsNotTaintedByAMatchedGroup`: `noteMatchedGroup` taints only the recorders whose true-to-virtual distance changed since they opened. Not done: caching `anyScope`/`anyUncounted` on the record (the scan is a loop over a record's few clips; no stored bytes added). Per-frame bytes: `theMaskCountersAddNothingToAnIdleFrame` (record 436) caught the follow-up fields on `Frame` (the verify snapshot is a struct stored inline: it is boxed now, `Frame.verifySnapshotBox`), on `RetainedPhase` (one `MovedPaintCopy` reference for the moved leaves and clips) and on `ContentMemoStore` (`finalTap`, off `Frame`); the idle frame is 25,690 bytes against master's 25,922. The baselines of the tables moved with master (`9aec1177`: a translated non-crossing step 3975 allocations, idle island 2438 to 2441, island stream 554,258 / 555,359).

**Deviations from the plan.** The island's icon is a rect, not an image: an image's texture is a new object each paint and verify mode refuses to equate two. The remaining three island redos are not zero (above). `RetainedRecord` and `UnitRange` are as they were; the notCanonical flag of the plan is not
needed (an inexact scope taints, a move across a non-canonical status refuses). The `groups` digest found no unrelated difference in the suites run.

**Mutations** (each run in a scratch copy of the branch with the test suites `MaskEdge*`, `MovableRoundedMasks*`, and restored; "island" is `anIslandTranscriptStreamsWithoutAMaskRedo`):

| # | mutation | reddens |
|---|---|---|
| 1 | the scope not seen through (`opensSeenThrough` false) | `aRoundedRowCrossingAStraightEdgeTranslates`, `aFreshCrossingRecordIsTheRecordANonCrossingPaintMakes`, `aCrossingRecordsGlyphsAreOneOpAGlyph`, island |
| 2 | the glyph split off | `aFreshCrossingRecordIsTheRecordANonCrossingPaintMakes`, `aCrossingRecordsGlyphsAreOneOpAGlyph` |
| 3 | replay from `op.boundary` without the open scope | the translate test, `aUnitRangeInside...`, island, `aStraightEdgeCutMasksOnlyInTheArcBand`, both inverted tests |
| 4 | the scope not opened again on a live replay | the same seven |
| 5 | `closeMaskScope` with the live depth in a replay | `aFreshCrossingRecordIsTheRecordANonCrossingPaintMakes` (the captured final stream's depth) |
| 6 | true values stored for `emitted` and the ranges | the translate test, `aFreshCrossingRecordIsTheRecordANonCrossingPaintMakes` |
| 7 | the re-note without the conversion | the translate test, `aUnitRangeInsideACrossingRowIsWhatAFreshFrameNotes` |
| 8 | the flags not rewritten on a move | nine tests (the translate, fresh-record, island, idle, ranges, refusal and inverted tests) |
| 9 | the `maskNested` check removed | `eachCrossingThatCannotBeCanonicalRefusesByName` (nested arm) |
| 10 | the canonical-content check removed | `eachCrossingThatCannotBeCanonicalRefusesByName` (shape arm) |
| 11 | the paint height 0 restriction removed | `aCrossingUnderAnOuterScopeStillRefusesByName` |
| 12 | `rangesBefore` off by one | the translate test, `aUnitRangeInside...`, island, both inverted tests |
| 13 | the final stream not captured after a move | `aFreshCrossingRecordIsTheRecordANonCrossingPaintMakes` |
| 14 | `groups` left out of the verify snapshot | **not covered**: a verify-only arm needs a hook that tampers a replayed frame's group scene, and a trap cannot be asserted in process; the digest is exercised by the verify-mode runs of every suite above (no difference found) |

Verify mode (`METALUI_VERIFY_RETAINED=1`) over `MaskEdge`, `MovableRoundedMasks`, `ClippedEntryRelation`, `ClippedRegistrationFold`, `PlacementTranslation`, `FinerScopes`, every `Retained` suite, `ScopedRedo`, `RedoAttribution`, `G51`, `G52`, `ExactRedo`, `RedoCounter`, `LazyRowGraft`, `TabSplit`, `TableRetained`:
384 tests, no trap, and the five issues that are on master (`aFocusChangeLeavesAnUnconcernedViewRetained` and four `TableRetained` "beside a redrawing sibling" tests).
