# 346 - Terminal selection, text, search and viewport (`TRM-AQ`..`TRM-AT`)

Branch `feat/terminal-selection-search` from master `a9827471`; Phase 1.6 of `docs/superpowers/plans/2026-11-16-terminal.md`. Class M, no divergence label. Record number 346 is the next free after 345; a parallel branch may take it (renumber at merge).

**What landed.** The frozen `TerminalEmulator.selection` (get/set), `selectedText()`, `search(_:from:backwards:)` and `scrollViewport(toOffset:)`; `rowText` already fit (absolute rows, nil for evicted or missing) and now shares `row(at:)`. The snapshot carries the selection and the viewport offset. Package: `wordRange(at:wordCharacters:)` and `lineRange(at:)` for Phase 5 double and triple click. Files: `TerminalEmulator+Selection.swift`, `TerminalEmulator+Search.swift`; the publish path in `TerminalEmulator.swift`.

**The rules chosen** (full text in `TRM-AQ`..`TRM-AT`).
- *Selection lifecycle.* Cleared by a later reflow generation (`TRM-AM` 3), by an alternate-screen switch, and by output that changes the text of the selected columns of a screen row (xterm; attributes alone do not). Eviction clips the selection to the retained rows and clears it once none remain. Scrolling alone changes nothing.
- *Text.* Soft-wrapped rows join with no separator and keep their trailing blanks; every other row break is `"\n"` with that row's trailing blanks trimmed; block selections always join with `"\n"`; a wide character is taken once.
- *Search.* Case-sensitive, whole cells, wrap-spanning, no wrap-around (the caller restarts); forward `lowerBound >= from`, backwards `upperBound < from`.
- *Viewport.* Offset clamps to scrollback, 0 on the alternate screen; a change is a full frame; output while scrolled back keeps the same rows in view.
- *Word characters.* Letters, digits and `_-.~/:`; blank and other-character runs select themselves.

**Guards, each shown red.** Never joining wraps; skipping the trim; dropping the generation check; dropping the overwrite check; dropping a wide cell's second column; no viewport clamp; forward `>` for `>=`; backwards `<=` for `<`; lines that do not extend over wraps; matching inside a cell; the end column of a wide match; no viewport anchoring; the alternate-screen clear on entry and on leaving; clipping a linear selection to column 0; padding a wrapped row's gap column in `wordRange`.

**Cost.** A selection is checked on each publish: O(rows in view x selected width) while one exists, nothing otherwise; search builds one line at a time, so it is linear in the retained bytes.
