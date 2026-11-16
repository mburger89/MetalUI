# 333 - The primary selection and batched multi-range edits (`CV-BE`, `CV-BF`)

Branch `feat/code-selection-primary-batch` from master `c625d565`. Class M, no divergence. Buffer only (`MetalUICodeBuffer`); PR 2 of the editor-essentials foundation (multi-caret editing for Alloy).

**What landed.**
- `CodeSelectionState.primaryIndex`, `primarySelection = selections[primaryIndex]`, `setSelections(_:primary:)`, `selectionLimit = 10_000`, `replaceSelections(withEach:origin:)` on the state and the buffer. Assigning `selections` makes the input's first element primary; normalize tracks it through clamping, sort and merge; undo groups store `undoPrimary`/`redoPrimary`.
- Multi-selection replace applies the rope edits highest first, logs N `CodeEdit`s (`CV-D`), and moves each state once with `CodeEditRun` (new file): edits ascending in the coordinates before the first, prefix sums of length changes, a monotone-pointer sweep, the per-event rules folded only over the edits an offset touches. Undo/redo replay and external edits use it when their steps are monotone (descending or ascending), else one move per event.
- Alloy's ruling (2026-11-16): multi-caret typing coalesces like single-caret typing. `recordBatchUndo` merges a batched `.typing`/`.deletion` pairwise into the previous group of the same state (`mergedBatch`: next's coordinates taken back over the lower carets' earlier length changes).

**Splice.** With 32 or more descending edits close together the rope is replaced once over their span (log entries, scalar ranges and points read from the pre-splice text); without it the 10,000 rope edits alone cost about 10 ms in release. Measured 10,000 carets, one character, edit plus normalize: 4.4 to 5.8 ms (release). `aSplicedBatchEqualsTheOneByOneResult` compares text, log and undo with the one-by-one path, CRLF seams included.

**One semantic difference found by the property test.** The old path normalised (sorted, merged) the selections after every event, so two selections touching mid-run fused and then moved as one. Batched and fallback runs now normalise once at the end; the oracle (`CodeBuffer.sequentialMoves`, `package`) uses the same rule. Single events are unchanged.

**Tests** (`Tests/MetalUICodeBufferTests/MultiSelectionBatchTests.swift`): `aBatchMovesEveryStateAsTheSequentialPathDoes` (seeded, 400 rounds x 6 ops, 4 states, replace/external/undo/redo, text, selections, primary and edit log compared), `typingAtManyCaretsMatchesTheSequentialPath`, `aBatchMovesEachStateOnceNotOncePerEvent`, `theSequentialHookMovesOncePerEvent`, `undoRestoresEverySelectionAndThePrimary`, `typingWithThreeCaretsIsOneUndoStep`, `multiCaretTypingDoesNotCoalesceAfterAnotherEditOrASelectionWrite`, primary tracking (`assigningMakesTheFirstInputTheTrackedPrimary`, `thePrimaryFollowsTheRangeItMergesInto`, ...), `replaceSelectionsWithEach...`, and the gated `oneTypedCharacterWithTenThousandCaretsIsFast` (`METALUI_RUN_CODE_PERF=1`, release).

**Cost.** Nothing in the view changes; the CodeView steady keystroke-frame element-request literals pass unchanged.
