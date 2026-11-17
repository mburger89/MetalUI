# 346 - Selection helpers on `CodeSelectionState` (`CV-BJ`)

Renumbered from 345 because #348 merged first.

Branch `feat/code-selection-helpers` from master `c9b7c7c0`. Class M, no divergence. `MetalUICodeBuffer` plus one reveal line in `CodeViewPlan`; Alloy gap G2. Expect renumbering at merge (a parallel G3 branch may take 345).

**What landed.** `CodeSelectionState`: `addNextOccurrence(limit:)`, `selectAllOccurrences(limit:)`, `skipToNextOccurrence()`, `addCaret(lineDelta:tabWidth:limit:)` (all `@discardableResult Bool`, `false` only when the limit stopped them) and `collapseToPrimary()`. `CodeSnapshot` gains the package `firstRange(of:options:from:accept:)` (first match from an offset, wrapping) and the shared `isWordByte` / `wordRange(at:)`; `ranges(of:)` now runs on the same `scan` (behaviour unchanged). `package` state: `nearestRevealSerial` (observed), `goalColumn`.

**Decisions made while building.**
- *"Later calls add whole-word matches."* After a caret selected its word, the primary is non-empty, which would switch to exact matching. The state remembers `mutationSerial` after a helper that searched whole words; any other write or edit raises the serial, so the next call is exact again.
- *Select all.* More than `limit` matches selects the first `limit` and returns `false` (the primary is the first match at or after the old primary's start).
- *Nothing to do is `true`.* No word at a caret, no match, a target line off the text: nothing changes and no reveal is asked.
- *`addCaret`.* The goal column is cleared by `setSelections` and by an edit moving the selections, and set by `addCaret` itself. A tab inside the target line snaps to the nearer column boundary (ties go before). Hidden rows are those of any fold state registered with the state.
- *The reveal.* `CodeViewPlan` takes `nearestRevealSerial` in beside `revealSerial`: a change under the same state turns on the caret reveal a key asks for (`CV-X`, least scroll, also horizontally); the first frame only records it.
- *`addCaret` takes a `limit` parameter* beyond the design's signature, so the cap is testable like the others.

**Tests.** `Tests/MetalUICodeBufferTests/SelectionHelpersTests.swift` (the 22-row table, cap, undo neutrality, goal column with tabs and graphemes, edges, folded rows, fold opening, collapse, reveal serials) and `Tests/MetalUITestingTests/CodeViewSelectionHelpersTests.swift` (least scroll against centred, a visible result does not scroll, a pre-mount helper scrolls nothing, the literal frame cost 1 request / 0 hits / 1 miss / 0 ineligible, equal to a plain selection write). Mutations shown red: `.wholeWord` dropped, case folded, goal column dropped, centring serial, direct write instead of `setSelections`, cap guard removed.
