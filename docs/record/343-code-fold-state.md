# 343 - The fold model (`CV-BL`)

Renumbered from 342 because #345 merged first.

Branch `feat/code-fold-state` from master `0dfd9f13`. Class M, no divergence. `MetalUICodeBuffer` only, plus `CodeGutterMarker.severity` in `MetalUI`; Alloy gap G5 part 1 (the layout, `CV-BM`, is the next change). Renumbered from 342 because #345 merged first. `CV-BL` as the design names it (`CV-BG` is PR #344's; `CV-BH`..`CV-BK` reserved for G3, G2 and G4).

**What landed.** `Sources/MetalUICodeBuffer/CodeFoldState.swift`: `CodeFoldState` (see `CV-BL` for the rules table), the internal `FoldRangeSet` (sorted ranges with a prefix maximum of the ends) and `FoldLineEdit` (an edit as rows, a break count and a column-0 flag). The buffer keeps `foldStates` (weak), and `applyEvent`, the spliced batch and `applyBatch` feed them: a lone event moves them at once, a run collects its line edits and moves them once (`moveFoldsOverRun`). `CodeSelectionState` keeps its fold states weakly and `openFolds()` runs after every explicit write (`setSelections`, so `selections`, `select`, the buffer's forwards, find's step) and after undo and redo restore their selections. `CodeBuffer.lineEdits(since:)` reads the edit log for `setFoldableRanges(_:asOf:)`.

**Decisions made while building.**
- *Nesting and the binary search.* Ends are not monotone with nesting, so the first fold an edit can touch is found over a running maximum of the ends (`maxEnd`); folds before it are never visited. After the last edit the sweep ends as soon as the remaining folds are unaffected (every edit above them, net line change zero, running maximum unchanged).
- *Header rule.* A pure insertion at column 0 that adds breaks shifts the fold; any other header edit with a break (including a replace starting at column 0) opens it, as the design table says.
- *`fold` and the setter evict carets.* Assigning `folded` moves carets out of the rows it hides as `fold` does, so a restore cannot leave a caret in a hidden row. The eviction goes through `setInternal`, so it opens nothing.
- *The opened fold's observers.* An edit that moves or drops a fold wakes `folded` observers after the change, inside the same synchronous edit; an edit that moves nothing wakes nobody (`foldedIsObservableAndAnUnrelatedEditDoesNotWakeIt`).
- *`setFoldableRanges` on a stale log* returns false and leaves the ranges alone (the caller recomputes); it does not clear them.
- *Ascending runs.* An undo of a descending batch replays ascending in moment coordinates; the line edits are taken back over the line changes of the edits below before the merged sweep (the column-0 flag keeps its moment value).

**Evidence.**
- Mutations, each red (and restored): column-0 shift made an open (`theEditRules`, the counted test); body edits made an open (rules, nesting, `editsNeverOpenAFold`, the foldable tests); no `openFolds()` in `setSelections` (`selectRevealOpensFold`); no eviction in `fold` (`foldEvictsCarets`); the early exit removed (the counted test); the asOf mapping removed so ranges apply raw (`setFoldableRangesMaps...`); no `openFolds()` in undo (`undoAndRedoRestore...`); the run not reversed (the three batch tests); the first-affected search off by one (rules, both batch properties, the asOf test).
- The batch properties compare a batched run, its undo and its redo with `sequentialMoves` over 300 random runs and 40 spliced 40-caret runs.
- Timing, counts and the verification command are in the commit message and the branch's report.
