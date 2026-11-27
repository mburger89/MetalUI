# 434: a registration cut by a clip its occurrence pushed moves at the viewport edge (`FS-X`; class M, no divergence)

Branch `perf/clipped-registration-fold`, base master `164978ef`. No public API, no divergence (242 live, next label 250).

**Why.** Record 431 found the redos of Alloy's streamed transcript to be `graftedPrepaint` refusals, and the `prepaint` half of them `translationRefused: hitboxClipped` / `accessibilityClipped`: a registration cut by a clip its occurrence opened (the row's rounded chrome) moved only while it stayed strictly inside the ambient clip before and after, so a row crossing the scroll viewport's edge refused, the frame was redone and the row quarantined for 8 builds and more.

**What.** `FS-X` (`docs/superpowers/2026-10-20-finer-scopes-decisions.md`): `PrepaintLog` journals clip pushes and pops while a recorder is open (`PrepaintClip` = `InnerClip` + the emission range; the frame's hitbox and emission counts are the ranges), a ledger keeps them as `innerClips` only when a hitbox or emission sits at a depth other than its entry's, and `PrepaintClipFold` (`RetainedTranslationCarries.swift`) re-derives the cut with `Frame.pushedClip` at the old key (which must reproduce the recorded rect bit for bit, else `…NotFolded`) and the new, where the strictly-inside fast path refuses. Refusals: `accessibilityNotFolded`, `hitboxNotFolded`, `accessibilityUnmapped`, `hitboxUnmapped`, `rootClip`, `inexactTranslation`. Threaded through `movedAccessibility`, `shiftedLocals` and `movedHitbox`; `replayPrepaintLedger` re-notes a replayed ledger's clips (`layoutOrigin` for verify mode).

## Measured (chrome transcript, accessibility client on, 40 streamed words, scale 2; `ClippedRegistrationFoldTests` fixture and a scratch probe, master `164978ef` against this branch)

| | master | branch |
|---|---|---|
| element requests (40 steps) | 1151 | 593 |
| allocations (40 steps, the retaining window's frame) | 893,894 | 817,992 |
| redos | 4 | 4 |
| idle frame, `CF` fixture (allocations / requests) | 7115 / 67 | 7115 / 67 |

The redo count did not fall on this fixture: the `hitboxClipped` redos of rows 42 and 45 are gone, and the rows the earlier quarantine used to hold now meet the next gate, `maskCrossingChanged` (rows 45 and 46, steps 29 and 36 with accessibility off), which is the later fix; the two key-mismatch redos (the streaming row's clip grew) are unchanged. **`aRedoDoesNotCascadeIntoTheRowsDescendants` pins at most 3 redos in 40 steps and now sees 4; it fails and was not changed (the pin may only go down).** No other pin moved: `aNonAnimatableComponentAllocatesWhatItDid` 319, the G51/G52 ceilings, `ScrollOffsetPixelSnapTests` 1562 / 43 pass unchanged.

## Tests

`ClippedRegistrationFoldTests` (six tests, 12 cases): the cut row moves (3 steps, trace silent, pair equal); the streamed transcript refuses no clipped registration (40 steps, accessibility on); a tampered recorded rect refuses `…NotFolded` (hitbox and emission arms); scale arms 1, 9/8 (8 and 16 pt) and 1.2 (5 pt and 1 pt); ledgers pay only for the clips they need, idle frame pinned to master's numbers; a root clip folds to `nil`. **Scale 1.2 does not move** (brief expected it to for 5 pt): the paint record refuses `inexactTranslation` first (layout origins times 1.2 are not sixteenths, `FS-W`), so the ledger is never asked; the arm pins that and the 1 pt arm's `fractionalTranslation`. **Flipped:** `PlacementTranslationTests` 10 (`anInnerClippedHitboxTouchingTheAmbientClipRefuses`, now `...MovesByTheFold`: prepaint hits equal translated) and 11 (`theClippedRowsAreRefusedByTheNameHitboxClipped`, now `...NoLongerRefuseByTheNameHitboxClipped`: no refusal).

**Mutations checked (each reddened the named tests, restored from git):** slow path off in `movedHitbox` (`aRowCutByTheViewport...`, `aCutRowMovesExactlyAtEveryScale`, `theFoldAtTheOldPosition...` hitbox arm, flipped 10 and 11); new rect taken from the old fold (`aCutRowMovesExactlyAtEveryScale` 16 pt arms); recorded-rect comparison off (`theFoldAtTheOldPosition...`, both arms); root/flattening check off (`aRegistrationUnderARootClipStillRefuses`); `innerClips` kept for every ledger that pushed a clip (`aLedgerPaysOnlyForTheClipsItsOccurrencePushed`, after its chrome-only fixture was made to push a clip: the first fixture pushed none and the mutant survived).

**Verify mode** (`METALUI_VERIFY_RETAINED=1`, the new suite and the retained, translation, scoped-redo, G51 and chrome suites): no trap; 5 issues in 6 tests on this branch and on master alike (325 against 319 tests).

**Counts.** Root 7485 tests in 80 suites (`--build-system native`, `--no-parallel`), one failure: the cascade pin above.

# Cause 2: a row that starts or stops crossing the viewport edge replays through a live mask (`FS-Y`)

Same branch, second commit series. After cause 1 the rows the earlier quarantine held met the next gate: `maskCrossingChanged` (rows 45 and 46, steps 29 and 36), the corner-zone crossings of record 424. A rounded row whose clip pushes a **crossing** clip pair opens a `CM-B` mask scope in `Frame.paintClipped`; a record made then held one merged leaf that left the scope, noted at the recorder's own height, and `passedInnerScope` refused every later move (`innerScope`), so a row could not become that output by moving leaves.

**What.** `FS-Y`: the scope is transparent to the recorder directly below it. `paintWithMask` is `openMaskScope` + `closeMaskScope`; `Frame.crossingMask` is the one copy of the test and the mask rect, `Frame.markCaptures` the one mark. `RetainLog.noteBoundary` notes the leaves where they enter a `PaintScope.isClipCrossing` scope as an op of the recorder's height (no `passedInnerScope`) and notes nothing for the merged leaf that leaves it (`closing`). The flagged clip (`InnerClip.scopeFlag`, with `paintedFlag` on every clip `paintClipped` pushed) and its mask (`crossingMasks`) are kept; `replayOps` opens the scope again at the clip's push, sends the range's ops through `processScopes(from: boundary + 1)` and closes it before the pop; `Frame.finalStream` derives the final stream of a record that crossed (record close and every move); `foldedClips` evaluates `crossingMask` for each painted clip at the old position (must agree with the flag) and the new, and `scopeState` rewrites the flags and masks. Still refused by name: a crossing clip inside another (`maskNested`), a clip not pushed by `paintClipped` that changes crossing (`maskCrossingChanged`, `maskCrossed`), a record with unit ranges or matched groups moving into, out of or within a crossing (their numbers are emission counts).

**Two things the plan did not foresee.** (1) A text draw's glyphs are one leaf only while a scope is open (`beginLeafGroup`), one op a glyph otherwise: a record made without the scope held 12 ops where a fresh paint inside it held 10, and verify mode trapped at `scene.count`. Inside a crossing-only scope the glyphs now go in one at a time (the scope merges them anyway). (2) `RetainedRecord.emitted` counts emissions, and a masked group's count is not its leaves' sum (`insertMaskedGroup`): a moved record marks it stale (`emittedIsStale`) and verify mode does not compare it; the ranges and matched groups that read it refuse such a move. The plan's `ScopedRedoTests` / `RedoAttributionTests` fixture move was not needed: the 40-word transcript still redoes three times, for the growing row's own ledger key (`ledgerKey.rects`, `interior`), not for a mask; only `aRowThatAlwaysRefuses...` changed (its `innerScope` cause is gone). The nested arm of the corner-zone test (two clips on one rect, both crossing) refuses `maskNested` and, once painted, `innerScope`: the second scope is an inner one.

## Cause 2: measured and what stays

40 streamed words, accessibility on, scale 2, a scratch probe on the retaining window (the same probe on `4a1e3856` and on this branch):

| | `4a1e3856` | branch |
|---|---|---|
| element requests | 593 | 569 |
| allocations | 818,097 | 820,427 |
| redos | 4 | 4 |
| `theStreamingTranscriptRefusesOnlyAtACornerZone` (no accessibility) mean requests a word | 24.85 (record 423) | 14.2, nothing refuses |

**The pin is not met: `aRedoDoesNotCascadeIntoTheRowsDescendants` still sees 4 redos (pin 3).** The redos of the mask causes at steps 29 and 36 fell to one (step 29): row 45 moving into a corner zone holds a unit range (`ranges ["74..81"]`, `emitted 81`: a default-fade unit of its button) and a unit range is a number of emissions. A fresh paint inside the crossing scope emits the whole row as one masked group (`emitted 1`, `ranges ["0..0"]`), and whether a unit's boundary lies inside the scope or outside it is not in the record, so the fresh range cannot be derived from the old one without storing, per range end, the op index and the clip-event index it was noted at (an anchor on `UnitRange`, noted from the log, measured again in `replayOps`). Rather than approximate, such a move refuses by name (`maskCrossingChanged`, `maskCrossed`) and the grafted row is redone, as before. With that refusal off the transcript redoes 3 times and requests are 488, but a record moved into a crossing then holds ranges that are not a fresh paint's; not done. **Not done, for the next session: the range anchors.**

**The allocation total rose by 2,330 over 40 words (0.3 percent) on this probe**, against 593 to 569 requests; no pin moved (the idle fixture 7115 / 67, `aNonAnimatableComponentAllocatesWhatItDid` 319, the G51 and G52 ceilings, `ScrollOffsetPixelSnapTests` 1562 / 43 all pass unchanged), and the probe's total is not one. Where it comes from was not isolated.

**Mutations checked (each reddened the named tests, restored):** the mark not inserted (`aCrossedRecordHoldsItsLeavesBeforeTheMask`), one mark per primitive (`aStreamedTranscript...`), the final stream taken as the scene (`aRowWhoseCornerZone...`, `aCrossedRecord...`, `theStreamingTranscript...`), `from: op.boundary` without the `+ 1` (`aRowWhoseCornerZone...`, `theStreamingTranscript...`), the transparency off in `noteBoundary` (`aRowThatAlwaysRefuses...`: its `innerScope` cause returns; the aCrossedRecord fresh arm needs `testingDropRetainedRecords`, added), the scope flag never set (the corner-zone, transcript and shaped tests), text leaf groups batched inside the scope again (`aStreamedTranscript...`), the consistency refusal `maskNotFolded` off (`aStreamedTranscript...`).

**Verify mode** (`METALUI_VERIFY_RETAINED=1`, the suites listed in the brief, 366 tests): no trap; 5 issues in 5 tests, the same five as on `4a1e3856` over the same filter (364 tests): `aFocusChangeLeavesAnUnconcernedViewRetained` and four `TableRetainedTests` "beside a redrawing sibling" tests, none about masks.

**Counts.** Root 7487 tests in 80 suites (`--build-system native`, `--no-parallel`), one failure: the cascade pin above (4 redos, as on `4a1e3856`).
