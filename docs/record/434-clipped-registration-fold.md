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
